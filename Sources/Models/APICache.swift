import Foundation
import CryptoKit

// Cache disque des reponses d'API (Deezer, iTunes, LRCLIB).
//
// POURQUOI : l'app depend d'API publiques gratuites, sans cle ni garantie.
// Ce cache (1) reduit drastiquement le nombre d'appels (moins de risque
// d'etre limite), (2) accelere l'affichage, et (3) permet un vrai mode
// hors-ligne : en cas d'echec reseau, on ressert la derniere reponse connue
// meme perimee, plutot que rien.
//
// Stockage dans Library/Caches : le systeme peut purger si l'espace manque,
// c'est exactement le bon endroit pour des donnees regenerables.
enum APICache {

    private static let directory: URL = {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("APICache", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }()

    // Nom de fichier stable derive de l'URL (SHA-256, insensible a la longueur).
    private static func file(for url: URL) -> URL {
        let digest = SHA256.hash(data: Data(url.absoluteString.utf8))
        let name = digest.map { String(format: "%02x", $0) }.joined().prefix(32)
        return directory.appendingPathComponent(String(name)).appendingPathExtension("cache")
    }

    // Reponse en cache si elle existe et n'est pas plus vieille que maxAge.
    // maxAge nil = accepter n'importe quel age (mode hors-ligne).
    static func data(for url: URL, maxAge: TimeInterval?) -> Data? {
        let f = file(for: url)
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: f.path),
              let modified = attrs[.modificationDate] as? Date else { return nil }
        if let maxAge, Date().timeIntervalSince(modified) > maxAge { return nil }
        return try? Data(contentsOf: f)
    }

    static func store(_ data: Data, for url: URL) {
        try? data.write(to: file(for: url), options: .atomic)
    }

    // Requete avec cache : cache frais -> reseau -> cache perime (hors-ligne).
    static func fetch(url: URL,
                      maxAge: TimeInterval,
                      userAgent: String? = nil) async -> Data? {
        // 1) Cache encore frais : pas d'appel reseau du tout.
        if let fresh = data(for: url, maxAge: maxAge) { return fresh }
        // 2) Reseau.
        var req = URLRequest(url: url)
        req.timeoutInterval = 15
        if let userAgent { req.setValue(userAgent, forHTTPHeaderField: "User-Agent") }
        if let (data, response) = try? await URLSession.shared.data(for: req),
           (response as? HTTPURLResponse)?.statusCode == 200,
           !data.isEmpty {
            store(data, for: url)
            return data
        }
        // 3) Echec reseau : on ressert la derniere reponse connue, meme vieille.
        return data(for: url, maxAge: nil)
    }
}
