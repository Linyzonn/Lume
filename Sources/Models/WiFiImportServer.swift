import Foundation
import Network
import UIKit

// MARK: - Import Wi-Fi
//
// Petit serveur web embarque dans l'app : quand il est actif, un ordinateur
// sur le MEME reseau Wi-Fi ouvre http://<ip-de-l-iphone>:8080 dans son
// navigateur et y glisse-depose des fichiers audio. Chaque fichier est
// recu, depose dans la boite d'import (Documents) puis importe dans la
// bibliotheque automatiquement — plus besoin de cable ni d'iTunes.
//
// Choix techniques :
//  - Network.framework (NWListener), aucun framework tiers.
//  - La page HTML envoie chaque fichier en POST brut avec le nom dans
//    l'URL (/upload?name=...) : cela evite d'avoir a analyser du
//    multipart/form-data, beaucoup plus fragile.
//  - Le transfert n'a lieu que quand l'app est A L'ECRAN (iOS coupe les
//    connexions TCP en arriere-plan). L'ecran est garde allume pendant
//    que le serveur tourne (isIdleTimerDisabled).
@MainActor
final class WiFiImportServer: ObservableObject {
    @Published var isRunning = false
    @Published var address: String?
    @Published var receivedCount = 0

    weak var library: LibraryStore?

    private var listener: NWListener?
    private var connections: [UUID: HTTPConnection] = [:]
    private var rescanScheduled = false

    static let port: UInt16 = 8080

    func start(library: LibraryStore) {
        guard listener == nil else { return }
        self.library = library
        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            let l = try NWListener(using: params, on: NWEndpoint.Port(rawValue: Self.port)!)
            l.newConnectionHandler = { [weak self] conn in
                let http = HTTPConnection(connection: conn) { name, data in
                    Task { @MainActor in self?.handleFile(name: name, data: data) }
                } onClosed: { id in
                    Task { @MainActor in self?.connections[id] = nil }
                }
                Task { @MainActor in
                    self?.connections[http.id] = http
                    http.start()
                }
            }
            l.stateUpdateHandler = { [weak self] state in
                if case .failed = state {
                    Task { @MainActor in self?.stop() }
                }
            }
            l.start(queue: .global(qos: .userInitiated))
            listener = l
            isRunning = true
            receivedCount = 0
            address = Self.localIPAddress().map { "http://\($0):\(Self.port)" }
            // L'ecran reste allume pendant le transfert (iOS couperait
            // les connexions si l'app passait en veille).
            UIApplication.shared.isIdleTimerDisabled = true
        } catch {
            isRunning = false
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        for (_, c) in connections { c.close() }
        connections = [:]
        isRunning = false
        address = nil
        UIApplication.shared.isIdleTimerDisabled = false
    }

    // Fichier recu : depose dans la boite d'import, puis import (regroupe).
    private func handleFile(name: String, data: Data) {
        guard let library else { return }
        library.saveToInbox(fileName: name, data: data)
        receivedCount += 1
        importSoon()
    }

    // Regroupe les imports : on attend 1,5 s apres le dernier fichier recu
    // avant de scanner la boite, pour importer tout un lot d'un coup.
    private func importSoon() {
        guard !rescanScheduled else { return }
        rescanScheduled = true
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            rescanScheduled = false
            await library?.scanInbox()
            // Un import etait peut-etre deja en cours : s'il reste des
            // fichiers en attente, on retente un peu plus tard.
            if library?.inboxHasAudio == true {
                importSoon()
            }
        }
    }

    // Adresse IPv4 locale de l'iPhone sur le Wi-Fi (interface en0).
    nonisolated static func localIPAddress() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }
        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        while let current = ptr {
            let interface = current.pointee
            if interface.ifa_addr.pointee.sa_family == UInt8(AF_INET),
               String(cString: interface.ifa_name) == "en0" {
                var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                getnameinfo(interface.ifa_addr,
                            socklen_t(interface.ifa_addr.pointee.sa_len),
                            &hostname, socklen_t(hostname.count),
                            nil, 0, NI_NUMERICHOST)
                address = String(cString: hostname)
            }
            ptr = current.pointee.ifa_next
        }
        return address
    }
}

// MARK: - Connexion HTTP minimaliste (une par requete du navigateur)

final class HTTPConnection {
    let id = UUID()

    private let connection: NWConnection
    private var buffer = Data()
    private let onFileReceived: (String, Data) -> Void
    private let onClosed: (UUID) -> Void
    private var responded = false

    // Taille maximale d'un fichier accepte (garde-fou memoire).
    private static let maxBodySize = 300 * 1024 * 1024
    private static let queue = DispatchQueue(label: "lume.wifi.http")

    init(connection: NWConnection,
         onFileReceived: @escaping (String, Data) -> Void,
         onClosed: @escaping (UUID) -> Void) {
        self.connection = connection
        self.onFileReceived = onFileReceived
        self.onClosed = onClosed
    }

    func start() {
        connection.start(queue: Self.queue)
        receiveNext()
    }

    func close() {
        connection.cancel()
        onClosed(id)
    }

    private func receiveNext() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 128 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                self.buffer.append(data)
                self.process()
            }
            if error != nil || isComplete {
                if !self.responded { self.close() }
                return
            }
            if !self.responded {
                self.receiveNext()
            }
        }
    }

    private func process() {
        guard !responded else { return }
        // Fin des en-tetes HTTP ?
        guard let headerRange = buffer.range(of: Data("\r\n\r\n".utf8)) else {
            if buffer.count > 64_000 { close() }   // en-tetes anormalement longs
            return
        }
        guard let head = String(data: buffer[..<headerRange.lowerBound], encoding: .utf8) else {
            close()
            return
        }
        let lines = head.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { close(); return }
        let parts = requestLine.components(separatedBy: " ")
        guard parts.count >= 2 else { close(); return }
        let method = parts[0]
        let path = parts[1]

        if method == "GET" {
            respond(contentType: "text/html; charset=utf-8", body: Data(Self.pageHTML.utf8))
            return
        }

        guard method == "POST", path.hasPrefix("/upload") else {
            respond(status: "404 Not Found", body: Data("Introuvable".utf8))
            return
        }

        // Content-Length obligatoire pour savoir quand le corps est complet.
        var contentLength = 0
        for line in lines.dropFirst() {
            let kv = line.split(separator: ":", maxSplits: 1)
            if kv.count == 2,
               kv[0].trimmingCharacters(in: .whitespaces).lowercased() == "content-length" {
                contentLength = Int(kv[1].trimmingCharacters(in: .whitespaces)) ?? 0
            }
        }
        guard contentLength > 0, contentLength <= Self.maxBodySize else {
            respond(status: "413 Payload Too Large", body: Data("Fichier trop volumineux".utf8))
            return
        }

        let bodyStart = headerRange.upperBound
        guard buffer.count - bodyStart >= contentLength else { return }   // corps incomplet : on attend

        let body = buffer.subdata(in: bodyStart..<(bodyStart + contentLength))

        // Nom du fichier passe dans l'URL : /upload?name=Mon%20titre.mp3
        var fileName = "import-\(Int(Date().timeIntervalSince1970)).m4a"
        if let comps = URLComponents(string: path),
           let n = comps.queryItems?.first(where: { $0.name == "name" })?.value,
           !n.isEmpty {
            fileName = (n as NSString).lastPathComponent
        }

        onFileReceived(fileName, body)
        respond(body: Data("OK".utf8))
    }

    private func respond(status: String = "200 OK",
                         contentType: String = "text/plain; charset=utf-8",
                         body: Data) {
        responded = true
        let head = "HTTP/1.1 \(status)\r\nContent-Type: \(contentType)\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
        var out = Data(head.utf8)
        out.append(body)
        connection.send(content: out, completion: .contentProcessed { [weak self] _ in
            self?.close()
        })
    }

    // Page servie au navigateur du PC : zone de glisser-deposer + envoi.
    private static let pageHTML = """
    <!doctype html>
    <html lang="fr"><head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width,initial-scale=1">
    <title>Lume — Import Wi-Fi</title>
    <style>
      body{font-family:-apple-system,Segoe UI,Roboto,sans-serif;background:#12121a;color:#eee;
           display:flex;flex-direction:column;align-items:center;padding:40px 16px;margin:0}
      h1{font-size:28px;margin:0 0 4px}
      p{color:#9a9ab0;margin:0 0 28px}
      #drop{width:min(520px,90vw);border:2px dashed #6b5ceb;border-radius:18px;padding:56px 20px;
            text-align:center;font-size:17px;color:#c9c9e0;transition:.15s;background:#1a1a26}
      #drop.over{background:#241f4d;border-color:#eb5c9e}
      #pick{margin-top:14px}
      ul{list-style:none;padding:0;width:min(520px,90vw)}
      li{background:#1a1a26;border-radius:10px;padding:10px 14px;margin-top:8px;font-size:14px;
         overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
      small{color:#9a9ab0}
    </style></head><body>
    <h1>&#127925; Lume</h1>
    <p>D&eacute;pose tes fichiers audio, ils arrivent directement sur l'iPhone.</p>
    <div id="drop">
      Glisse tes fichiers ici (MP3, M4A, FLAC, WAV&hellip;)<br><small>ou</small><br>
      <input type="file" id="pick" multiple accept="audio/*,.mp3,.m4a,.aac,.wav,.flac,.aif,.aiff">
    </div>
    <ul id="list"></ul>
    <script>
    const drop=document.getElementById('drop'),list=document.getElementById('list');
    async function send(file){
      const li=document.createElement('li');
      li.textContent=file.name+' \\u2026 envoi';
      list.prepend(li);
      try{
        const r=await fetch('/upload?name='+encodeURIComponent(file.name),{method:'POST',body:file});
        li.textContent=file.name+(r.ok?' \\u2705 re\\u00e7u':' \\u274c erreur');
      }catch(e){ li.textContent=file.name+' \\u274c erreur r\\u00e9seau'; }
    }
    async function sendAll(files){ for(const f of files){ await send(f); } }
    drop.addEventListener('dragover',e=>{e.preventDefault();drop.classList.add('over');});
    drop.addEventListener('dragleave',()=>drop.classList.remove('over'));
    drop.addEventListener('drop',e=>{e.preventDefault();drop.classList.remove('over');sendAll(e.dataTransfer.files);});
    document.getElementById('pick').addEventListener('change',e=>sendAll(e.target.files));
    </script>
    </body></html>
    """
}
