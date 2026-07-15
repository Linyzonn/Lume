import Foundation
import AVFoundation
import UIKit
import Combine

// Extensions audio reconnues. Constante GLOBALE (hors de tout acteur) :
// elle est utilisee aussi bien sur le MainActor (imports) que sur la file
// reseau du serveur d'import Wi-Fi (filtrage des envois).
let lumeAudioExtensions: Set<String> = ["mp3", "m4a", "aac", "wav", "flac", "aif", "aiff", "aifc", "caf"]

// Le cerveau de la bibliotheque : importe les fichiers, lit les metadonnees,
// sauvegarde tout sur le disque, gere playlists et favoris.
@MainActor
final class LibraryStore: ObservableObject {
    @Published var tracks: [Track] = [] { didSet { invalidateGroupCaches() } }
    @Published var playlists: [Playlist] = []
    @Published var isImporting = false
    @Published var importProgress: String = ""
    // Fichiers refuses lors du dernier import (nom + raison), pour informer
    // l'utilisateur au lieu d'ignorer silencieusement.
    @Published var importErrors: [String] = []
    // Message affiche au lancement quand la bibliotheque a du etre recuperee
    // (copie de secours ou reconstruction depuis les fichiers audio).
    @Published var startupNotice: String?

    // Statistiques d'ecoute, stockees SEPAREMENT de la bibliotheque
    // (fichier stats.json) pour ne jamais mettre en peril tes donnees.
    @Published var stats: [UUID: TrackStats] = [:]
    @Published var dailyListening: [String: Double] = [:]   // "2026-07-02" -> secondes
    // Incremente quand une photo d'artiste est telechargee (rafraichit les vues).
    @Published var artistImagesVersion = 0

    // Liste d'envies : titres reperes dans Decouvrir, a recuperer plus tard.
    // Quand un fichier correspondant est importe (via iTunes ou Fichiers),
    // il est automatiquement reconnu, retire de la liste et range dans la
    // playlist "Découvertes".
    @Published var wishlist: [WishItem] = []

    // Dossiers de stockage.
    // - `docs` (Documents) est VISIBLE dans iTunes/Finder : il sert uniquement
    //   de boite de depot pour ajouter de la musique depuis un ordinateur.
    // - Les donnees internes (fichiers importes, pochettes, base library.json)
    //   vivent dans Application Support : INVISIBLES dans le partage de
    //   fichiers, elles n'encombrent plus la liste iTunes.
    private let docs: URL
    private let tracksDir: URL
    private let artworkDir: URL
    private let artistImagesDir: URL
    private let libraryFile: URL
    private let statsFile: URL
    private let wishlistFile: URL

    // Caches de regroupement (recalcules uniquement quand la liste change) :
    // sans eux, chaque ligne de l'onglet Artistes recalculait TOUT le
    // regroupement, d'ou les saccades de defilement.
    private var artistsCache: [String: [Track]]?
    private var albumsCache: [String: [Track]]?
    // Cache de miniatures de pochettes (decodage disque fait une seule fois).
    private let thumbCache = NSCache<NSString, UIImage>()

    // Extensions audio reconnues pour l'import automatique.
    static let audioExtensions: Set<String> = lumeAudioExtensions

    // Les repertoires sont injectables : les TESTS UNITAIRES passent des
    // dossiers temporaires et ne touchent plus jamais aux vraies donnees.
    // Reference partagee pour les commandes Siri / Raccourcis (AppIntents).
    static weak var shared: LibraryStore?

    init(rootDirectory: URL? = nil, documentsDirectory: URL? = nil) {
        let fm = FileManager.default
        docs = documentsDirectory ?? fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        try? fm.createDirectory(at: docs, withIntermediateDirectories: true)
        let support = rootDirectory ?? fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Lume", isDirectory: true)
        tracksDir = support.appendingPathComponent("Tracks", isDirectory: true)
        artworkDir = support.appendingPathComponent("Artwork", isDirectory: true)
        artistImagesDir = support.appendingPathComponent("ArtistImages", isDirectory: true)
        libraryFile = support.appendingPathComponent("library.json")
        statsFile = support.appendingPathComponent("stats.json")
        wishlistFile = support.appendingPathComponent("wishlist.json")

        try? fm.createDirectory(at: tracksDir, withIntermediateDirectories: true)
        try? fm.createDirectory(at: artworkDir, withIntermediateDirectories: true)
        try? fm.createDirectory(at: artistImagesDir, withIntermediateDirectories: true)
        migrateFromDocumentsIfNeeded()
        LibraryStore.shared = self

        // Rend le dossier Lume visible dans l'app Fichiers (Sur mon iPhone).
        // iOS n'affiche parfois le dossier d'une app que s'il contient au moins
        // un element ; or l'import automatique vide Documents apres chaque
        // depot. Ce petit lisez-moi permanent regle le probleme (il n'est pas
        // un fichier audio, donc jamais importe ni supprime par le scan).
        let readme = docs.appendingPathComponent("Dépose ta musique ici.txt")
        if !fm.fileExists(atPath: readme.path) {
            let text = """
            Dépose ici tes fichiers audio (MP3, M4A, FLAC, WAV…),
            depuis l'app Fichiers de l'iPhone ou depuis iTunes/Finder sur ordinateur.

            Ils seront importés automatiquement à l'ouverture de Lume,
            puis ce dossier se videra : c'est normal, ta musique est rangée
            dans la bibliothèque de l'app.
            """
            try? text.write(to: readme, atomically: true, encoding: .utf8)
        }

        load()
        loadStats()
        loadWishlist()
    }

    // Migration depuis les anciennes versions ou tout vivait dans Documents.
    private func migrateFromDocumentsIfNeeded() {
        let fm = FileManager.default
        let oldPairs: [(URL, URL)] = [
            (docs.appendingPathComponent("Tracks", isDirectory: true), tracksDir),
            (docs.appendingPathComponent("Artwork", isDirectory: true), artworkDir)
        ]
        for (oldDir, newDir) in oldPairs {
            guard fm.fileExists(atPath: oldDir.path) else { continue }
            let items = (try? fm.contentsOfDirectory(at: oldDir, includingPropertiesForKeys: nil)) ?? []
            for item in items {
                let dest = newDir.appendingPathComponent(item.lastPathComponent)
                if !fm.fileExists(atPath: dest.path) {
                    try? fm.moveItem(at: item, to: dest)
                }
            }
            if ((try? fm.contentsOfDirectory(atPath: oldDir.path)) ?? []).isEmpty {
                try? fm.removeItem(at: oldDir)
            }
        }
        let oldLibrary = docs.appendingPathComponent("library.json")
        if fm.fileExists(atPath: oldLibrary.path) {
            if !fm.fileExists(atPath: libraryFile.path) {
                try? fm.moveItem(at: oldLibrary, to: libraryFile)
            } else {
                try? fm.removeItem(at: oldLibrary)
            }
        }
    }

    private func invalidateGroupCaches() {
        artistsCache = nil
        albumsCache = nil
    }

    // MARK: - Chemins

    func url(for track: Track) -> URL {
        tracksDir.appendingPathComponent(track.fileName)
    }

    func artworkImage(for track: Track) -> UIImage? {
        guard let name = track.artworkFileName else { return nil }
        let url = artworkDir.appendingPathComponent(name)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    // Miniature de pochette, mise en cache et utilisable hors du thread
    // principal : les listes ne relisent plus le disque a chaque ligne.
    nonisolated func thumbnail(for track: Track, pixelSize: CGFloat) -> UIImage? {
        guard let name = track.artworkFileName else { return nil }
        let key = "\(name)#\(Int(pixelSize))" as NSString
        if let cached = thumbCache.object(forKey: key) { return cached }
        let fileURL = artworkDir.appendingPathComponent(name)
        guard let data = try? Data(contentsOf: fileURL),
              let image = UIImage(data: data) else { return nil }
        let thumb = image.resized(maxDimension: pixelSize)
        thumbCache.setObject(thumb, forKey: key)
        return thumb
    }

    // MARK: - Persistance

    private struct LibraryData: Codable {
        var tracks: [Track]
        var playlists: [Playlist]
    }

    private var libraryBackupFile: URL { libraryFile.appendingPathExtension("bak") }

    private static func decodeLibrary(at url: URL) -> LibraryData? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(LibraryData.self, from: data)
    }

    private func load() {
        let fm = FileManager.default
        if let decoded = Self.decodeLibrary(at: libraryFile) {
            apply(decoded)
            return
        }
        // Fichier principal absent : premiere ouverture… ou base perdue avec
        // des fichiers audio encore presents -> on les re-relie.
        guard fm.fileExists(atPath: libraryFile.path) else {
            rebuildFromFilesOnDisk(notify: false)
            return
        }
        // library.json EXISTE mais est illisible (corruption, app tuee en
        // pleine ecriture…). AVANT ce correctif, l'app repartait de zero en
        // silence et le prochain save() ECRASAIT le fichier : bibliotheque
        // definitivement perdue. Desormais :
        //  1) le fichier corrompu est mis de cote (jamais ecrase),
        //  2) on restaure la copie de secours si elle est lisible,
        //  3) en dernier recours on reconstruit depuis les fichiers audio.
        let quarantine = libraryFile.appendingPathExtension("corrompu")
        try? fm.removeItem(at: quarantine)
        try? fm.copyItem(at: libraryFile, to: quarantine)
        try? fm.removeItem(at: libraryFile)   // save() ne doit pas copier le corrompu vers .bak
        if let backup = Self.decodeLibrary(at: libraryBackupFile) {
            apply(backup)
            save()
            startupNotice = "La bibliothèque n'a pas pu être lue ; la copie de secours a été restaurée automatiquement."
            return
        }
        rebuildFromFilesOnDisk(notify: true)
    }

    private func apply(_ decoded: LibraryData) {
        // On ne garde que les morceaux dont le fichier existe encore.
        tracks = decoded.tracks.filter {
            FileManager.default.fileExists(atPath: tracksDir.appendingPathComponent($0.fileName).path)
        }
        playlists = decoded.playlists
        // Nettoyage des references orphelines : si des morceaux ont disparu
        // (fichier supprime hors de l'app, restauration partielle...), les
        // playlists ne doivent pas garder d'identifiants morts.
        let validIDs = Set(tracks.map(\.id))
        for i in playlists.indices {
            playlists[i].trackIDs.removeAll { !validIDs.contains($0) }
        }
    }

    // Reconstruit une bibliotheque minimale depuis les fichiers audio du
    // stockage interne : meme si la base est perdue, les morceaux ne
    // deviennent plus des orphelins invisibles. Les vrais titres / artistes /
    // pochettes se retrouvent ensuite via « Réanalyser les métadonnées ».
    private func rebuildFromFilesOnDisk(notify: Bool) {
        let fm = FileManager.default
        let files = (try? fm.contentsOfDirectory(at: tracksDir, includingPropertiesForKeys: nil)) ?? []
        let audio = files.filter { Self.audioExtensions.contains($0.pathExtension.lowercased()) }
        guard !audio.isEmpty else { return }
        tracks = audio.map { url in
            Track(fileName: url.lastPathComponent,
                  title: url.deletingPathExtension().lastPathComponent,
                  artist: "Artiste inconnu",
                  album: "Album inconnu",
                  duration: 0)
        }
        save()
        if notify {
            startupNotice = "La bibliothèque était illisible : \(tracks.count) morceau(x) ont été retrouvés depuis tes fichiers. Va dans Réglages → « Réanalyser les métadonnées » pour restaurer titres, artistes et pochettes."
        }
    }

    func save() {
        let data = LibraryData(tracks: tracks, playlists: playlists)
        guard let encoded = try? JSONEncoder().encode(data) else { return }
        let fm = FileManager.default
        // Copie de secours AVANT d'ecraser : si une future lecture echoue
        // (corruption), la version precedente reste recuperable.
        if fm.fileExists(atPath: libraryFile.path) {
            try? fm.removeItem(at: libraryBackupFile)
            try? fm.copyItem(at: libraryFile, to: libraryBackupFile)
        }
        try? encoded.write(to: libraryFile, options: .atomic)
    }

    // MARK: - Import de fichiers

    // Resultat de la copie + validation d'un fichier (fait hors du thread
    // principal : copier un gros FLAC bloquait toute l'interface).
    private enum ImportValidation { case ok, unreadable, unsupported }

    private static func copyAndValidate(from source: URL, to dest: URL,
                                        move: Bool) async -> ImportValidation {
        await Task.detached(priority: .userInitiated) { () -> ImportValidation in
            do {
                if move {
                    try FileManager.default.moveItem(at: source, to: dest)
                } else {
                    try FileManager.default.copyItem(at: source, to: dest)
                }
            } catch {
                return .unreadable
            }
            // Validation IMMEDIATE : si le moteur audio ne sait pas lire ce
            // fichier (ex. .opus), on le refuse maintenant avec un message
            // clair, plutot que de decouvrir le probleme a la lecture.
            if (try? AVAudioFile(forReading: dest)) == nil {
                try? FileManager.default.removeItem(at: dest)
                return .unsupported
            }
            return .ok
        }.value
    }

    func importFiles(_ urls: [URL]) async {
        isImporting = true
        importErrors = []
        defer { isImporting = false; importProgress = ""; save() }

        for (index, source) in urls.enumerated() {
            importProgress = "Import \(index + 1)/\(urls.count)…"
            let needsStop = source.startAccessingSecurityScopedResource()
            defer { if needsStop { source.stopAccessingSecurityScopedResource() } }

            // Nom de fichier unique dans notre dossier.
            let ext = source.pathExtension.isEmpty ? "m4a" : source.pathExtension
            let storedName = "\(UUID().uuidString).\(ext)"
            let dest = tracksDir.appendingPathComponent(storedName)

            switch await Self.copyAndValidate(from: source, to: dest, move: false) {
            case .unreadable:
                importErrors.append("\(source.lastPathComponent) : fichier illisible ou inaccessible")
                continue
            case .unsupported:
                importErrors.append("\(source.lastPathComponent) : format audio non pris en charge")
                continue
            case .ok:
                break
            }

            let track = await extractMetadata(from: dest,
                                              storedName: storedName,
                                              fallbackName: source.deletingPathExtension().lastPathComponent)
            // Deja dans la bibliotheque ? On jette la copie plutot que de creer un doublon.
            if isAlreadyInLibrary(track) {
                try? FileManager.default.removeItem(at: dest)
                if let art = track.artworkFileName {
                    try? FileManager.default.removeItem(at: artworkDir.appendingPathComponent(art))
                }
                continue
            }
            tracks.append(track)
            matchWishlist(track)
        }
        // Tri par date d'ajout (recent en haut).
        tracks.sort { $0.dateAdded > $1.dateAdded }
    }

    // Importe automatiquement les fichiers audio DEPOSES via iTunes/Finder
    // (partage de fichiers) a la racine de Documents. Les fichiers sont
    // DEPLACES (pas copies) vers le stockage interne : aucun doublon possible.
    // Les morceaux deja presents dans la bibliotheque sont ignores et leur
    // copie supprimee.
    func scanInbox() async {
        guard !isImporting else { return }
        let fm = FileManager.default
        let items = (try? fm.contentsOfDirectory(at: docs, includingPropertiesForKeys: nil)) ?? []
        let candidates = items.filter { Self.audioExtensions.contains($0.pathExtension.lowercased()) }
        guard !candidates.isEmpty else { return }

        isImporting = true
        importErrors = []
        defer { isImporting = false; importProgress = ""; save() }

        for (index, source) in candidates.enumerated() {
            importProgress = "Import \(index + 1)/\(candidates.count)…"
            let ext = source.pathExtension.isEmpty ? "m4a" : source.pathExtension
            let storedName = "\(UUID().uuidString).\(ext)"
            let dest = tracksDir.appendingPathComponent(storedName)
            switch await Self.copyAndValidate(from: source, to: dest, move: true) {
            case .unreadable:
                continue
            case .unsupported:
                importErrors.append("\(source.lastPathComponent) : format audio non pris en charge")
                continue
            case .ok:
                break
            }
            let track = await extractMetadata(from: dest,
                                              storedName: storedName,
                                              fallbackName: source.deletingPathExtension().lastPathComponent)
            if isAlreadyInLibrary(track) {
                try? fm.removeItem(at: dest)
                if let art = track.artworkFileName {
                    try? fm.removeItem(at: artworkDir.appendingPathComponent(art))
                }
                continue
            }
            tracks.append(track)
            matchWishlist(track)
        }
        tracks.sort { $0.dateAdded > $1.dateAdded }
    }

    // MARK: - Boite de depot (utilisee par l'import Wi-Fi)

    // Deplace un fichier recu (par le serveur Wi-Fi, deja ecrit sur disque
    // dans un fichier temporaire) vers la boite de depot ; il sera ensuite
    // importe par scanInbox comme un depot iTunes classique. Le DEPLACEMENT
    // (pas de lecture en memoire) permet de recevoir de tres gros fichiers
    // sans jamais peser sur la RAM.
    func saveToInbox(fileName: String, movingFrom tempURL: URL) {
        let safe = fileName
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: "\\", with: "-")
        var dest = docs.appendingPathComponent(safe)
        if FileManager.default.fileExists(atPath: dest.path) {
            dest = docs.appendingPathComponent("\(UUID().uuidString.prefix(8))-\(safe)")
        }
        do {
            try FileManager.default.moveItem(at: tempURL, to: dest)
        } catch {
            try? FileManager.default.removeItem(at: tempURL)
        }
    }

    // Reste-t-il des fichiers audio a importer dans la boite de depot ?
    var inboxHasAudio: Bool {
        let items = (try? FileManager.default.contentsOfDirectory(at: docs, includingPropertiesForKeys: nil)) ?? []
        return items.contains { Self.audioExtensions.contains($0.pathExtension.lowercased()) }
    }

    // Deux morceaux sont consideres identiques si titre + artiste correspondent
    // (comparaison sans casse ni accents) et duree quasi egale.
    private func sameSong(_ a: Track, _ b: Track) -> Bool {
        Self.normalized(a.title) == Self.normalized(b.title) &&
        Self.normalized(a.artist) == Self.normalized(b.artist) &&
        abs(a.duration - b.duration) < 2
    }

    private func isAlreadyInLibrary(_ track: Track) -> Bool {
        tracks.contains { $0.id != track.id && sameSong($0, track) }
    }

    // Supprime les doublons deja presents dans la bibliotheque. Pour chaque
    // groupe identique, garde le plus ancien et fusionne dessus favori,
    // paroles, pochette et appartenance aux playlists. Retourne le nombre
    // de doublons supprimes.
    @discardableResult
    func removeDuplicateTracks() -> Int {
        var kept: [Track] = []
        var removedCount = 0
        for track in tracks.sorted(by: { $0.dateAdded < $1.dateAdded }) {
            guard let original = kept.first(where: { sameSong($0, track) }) else {
                kept.append(track)
                continue
            }
            // Fusion vers l'original.
            if let oi = tracks.firstIndex(where: { $0.id == original.id }) {
                if track.isFavorite { tracks[oi].isFavorite = true }
                if tracks[oi].lyrics == nil { tracks[oi].lyrics = track.lyrics }
                if tracks[oi].artworkFileName == nil { tracks[oi].artworkFileName = track.artworkFileName }
            }
            for i in playlists.indices {
                while let idx = playlists[i].trackIDs.firstIndex(of: track.id) {
                    if playlists[i].trackIDs.contains(original.id) {
                        playlists[i].trackIDs.remove(at: idx)
                    } else {
                        playlists[i].trackIDs[idx] = original.id
                    }
                }
            }
            // Suppression du fichier du doublon (et de sa pochette si elle
            // n'a pas ete transferee a l'original).
            try? FileManager.default.removeItem(at: url(for: track))
            if let art = track.artworkFileName,
               tracks.first(where: { $0.id == original.id })?.artworkFileName != art {
                try? FileManager.default.removeItem(at: artworkDir.appendingPathComponent(art))
            }
            tracks.removeAll { $0.id == track.id }
            removedCount += 1
        }
        if removedCount > 0 { save() }
        return removedCount
    }

    // Lit titre / artiste / album / pochette / paroles / duree depuis le fichier.
    private func extractMetadata(from url: URL, storedName: String, fallbackName: String) async -> Track {
        // PreferPreciseDurationAndTiming : sans cette option, AVAsset ESTIME la
        // duree des MP3/M4A a debit variable depuis l'en-tete (souvent faux sur
        // les fichiers convertis depuis YouTube) -> ex. 3:30 affiche pour un
        // morceau de 4:00. Avec l'option, il scanne le fichier : duree exacte.
        let asset = AVURLAsset(url: url,
                               options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])

        var title = fallbackName
        var artist = "Artiste inconnu"
        var album = "Album inconnu"
        var lyrics: String? = nil
        var artworkName: String? = nil
        var duration: Double = 0

        // Duree.
        if let d = try? await asset.load(.duration) {
            let seconds = CMTimeGetSeconds(d)
            if seconds.isFinite { duration = seconds }
        }

        // Metadonnees communes.
        if let metadata = try? await asset.load(.commonMetadata) {
            for item in metadata {
                guard let key = item.commonKey else { continue }
                switch key {
                case .commonKeyTitle:
                    if let v = try? await item.load(.stringValue), !v.isEmpty { title = v }
                case .commonKeyArtist:
                    if let v = try? await item.load(.stringValue), !v.isEmpty { artist = v }
                case .commonKeyAlbumName:
                    if let v = try? await item.load(.stringValue), !v.isEmpty { album = v }
                case .commonKeyArtwork:
                    if let data = try? await item.load(.dataValue) {
                        // Decodage + redimensionnement + ecriture JPEG hors
                        // du thread principal (travail lourd par morceau).
                        let lib = self
                        artworkName = await Task.detached(priority: .userInitiated) {
                            lib.saveArtwork(data)
                        }.value
                    }
                default:
                    break
                }
            }
        }

        // Paroles (tags ID3 USLT ou iTunes).
        if let allMeta = try? await asset.load(.metadata) {
            for item in allMeta {
                let idString = item.identifier?.rawValue ?? ""
                if idString.contains("USLT") || idString.lowercased().contains("lyric") {
                    if let v = try? await item.load(.stringValue), !v.isEmpty {
                        lyrics = v
                        break
                    }
                }
            }
        }

        // Nettoyage des suffixes de type YouTube : "(Official Video)",
        // "[Clip Officiel]", "(Lyrics)", etc. polluent le titre affiche.
        title = Self.cleanedTitle(title)

        // Heuristique "ARTISTE - TITRE" (typique des fichiers YouTube) :
        //  - si l'artiste est inconnu, la partie gauche devient l'artiste ;
        //  - si l'artiste est connu ET que la partie gauche lui correspond
        //    (ex. titre "JAY-Z - Run This Town", tag artiste "JAY-Z"), on retire
        //    le prefixe du titre. Si la gauche contient l'artiste + d'autres noms,
        //    on garde la version la plus complete comme artiste.
        if let range = title.range(of: " - ") {
            let left = String(title[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
            let right = String(title[range.upperBound...]).trimmingCharacters(in: .whitespaces)
            if !left.isEmpty, !right.isEmpty {
                let normLeft = Self.normalized(left)
                let normArtist = Self.normalized(artist)
                if artist == "Artiste inconnu" {
                    artist = left
                    title = right
                } else if normLeft == normArtist {
                    title = right
                } else if normLeft.contains(normArtist) {
                    artist = left      // gauche = artiste principal + collaborateurs
                    title = right
                } else if normArtist.contains(normLeft) {
                    title = right      // le tag artiste est deja plus complet
                }
            }
        }

        // "feat. / ft. / featuring" restes dans le titre -> deplaces vers l'artiste.
        // "Run This Town ft. Rihanna, Kanye West" -> titre "Run This Town",
        // artiste complete avec "Rihanna, Kanye West".
        let (strippedTitle, featured) = Self.extractFeaturedArtists(from: title)
        title = strippedTitle
        if !featured.isEmpty {
            if artist == "Artiste inconnu" {
                artist = featured.joined(separator: ", ")
            } else {
                let normArtist = Self.normalized(artist)
                for name in featured where !normArtist.contains(Self.normalized(name)) {
                    artist += ", \(name)"
                }
            }
        }

        return Track(fileName: storedName,
                     title: title,
                     artist: artist,
                     album: album,
                     duration: duration,
                     artworkFileName: artworkName,
                     lyrics: lyrics)
    }

    // Retire les mentions parasites du titre : (Official Video), [Clip Officiel],
    // (Lyrics), (Audio), (Visualizer), etc.
    static func cleanedTitle(_ raw: String) -> String {
        let pattern = #"\s*[\(\[][^\)\]]*(official|officiel|video|vidéo|audio|lyric|parole|clip|visuali[sz]er|full\s?hd|4k|mv|hq)[^\)\]]*[\)\]]"#
        let cleaned = raw.replacingOccurrences(of: pattern,
                                               with: "",
                                               options: [.regularExpression, .caseInsensitive])
            .trimmingCharacters(in: .whitespaces)
        return cleaned.isEmpty ? raw : cleaned
    }

    // Re-lit les metadonnees de TOUTE la bibliotheque (utile apres une correction
    // du code d'import : les morceaux deja importes gardent sinon leurs anciennes
    // donnees — titre sale, duree fausse, etc.). Conserve favoris, playlists,
    // date d'ajout, pochette et paroles deja presentes.
    func reanalyzeMetadata() async {
        isImporting = true
        defer { isImporting = false; importProgress = ""; save() }

        for (index, track) in tracks.enumerated() {
            importProgress = "Analyse \(index + 1)/\(tracks.count)…"
            let fileURL = url(for: track)
            guard FileManager.default.fileExists(atPath: fileURL.path) else { continue }
            let fresh = await extractMetadata(from: fileURL,
                                              storedName: track.fileName,
                                              fallbackName: track.title)
            guard let i = tracks.firstIndex(where: { $0.id == track.id }) else { continue }
            tracks[i].title = fresh.title
            tracks[i].artist = fresh.artist
            tracks[i].album = fresh.album
            if fresh.duration > 0 { tracks[i].duration = fresh.duration }
            if tracks[i].artworkFileName == nil { tracks[i].artworkFileName = fresh.artworkFileName }
            if tracks[i].lyrics == nil { tracks[i].lyrics = fresh.lyrics }
        }
    }

    // Comparaison souple : minuscules + sans accents ("JAŸ-Z" == "jay-z").
    // nonisolated : utilisee aussi depuis les taches d'arriere-plan (photos).
    nonisolated static func normalized(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespaces)
    }

    // Extrait les artistes en featuring d'un titre.
    // "Run This Town ft. Rihanna, Kanye West" -> ("Run This Town", ["Rihanna", "Kanye West"])
    // "Song (feat. X & Y)" -> ("Song", ["X", "Y"])
    static func extractFeaturedArtists(from title: String) -> (String, [String]) {
        let pattern = #"(?i)\s*[\(\[]?\s*\b(?:feat\.?|ft\.?|featuring|avec)\s+([^\)\]]+?)[\)\]]?\s*$"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return (title, []) }
        let full = NSRange(title.startIndex..., in: title)
        guard let m = regex.firstMatch(in: title, range: full),
              let matchRange = Range(m.range, in: title),
              let capture = Range(m.range(at: 1), in: title) else { return (title, []) }

        let names = String(title[capture])
            .replacingOccurrences(of: #"(?i)\s*(?:,|;|&|\bet\b|\band\b|\sx\s)\s*"#,
                                  with: "\u{1}", options: .regularExpression)
            .components(separatedBy: "\u{1}")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        var cleaned = title
        cleaned.removeSubrange(matchRange)
        cleaned = cleaned.trimmingCharacters(in: CharacterSet(charactersIn: " -–—("))
            .trimmingCharacters(in: .whitespaces)
        return (cleaned.isEmpty ? title : cleaned, names)
    }

    // MARK: - Paroles

    func setLyrics(_ lyrics: String?, for track: Track) {
        guard let i = tracks.firstIndex(where: { $0.id == track.id }) else { return }
        tracks[i].lyrics = lyrics
        save()
    }

    // MARK: - Edition manuelle des metadonnees

    func updateMetadata(for track: Track, title: String, artist: String, album: String) {
        guard let i = tracks.firstIndex(where: { $0.id == track.id }) else { return }
        let t = title.trimmingCharacters(in: .whitespaces)
        let a = artist.trimmingCharacters(in: .whitespaces)
        let al = album.trimmingCharacters(in: .whitespaces)
        if !t.isEmpty { tracks[i].title = t }
        tracks[i].artist = a.isEmpty ? "Artiste inconnu" : a
        tracks[i].album = al.isEmpty ? "Album inconnu" : al
        save()
    }

    // MARK: - Statistiques d'ecoute

    private struct StatsData: Codable {
        var perTrack: [UUID: TrackStats]
        var daily: [String: Double]
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func dayKey(_ date: Date = Date()) -> String { dayFormatter.string(from: date) }

    private func loadStats() {
        guard let data = try? Data(contentsOf: statsFile),
              let decoded = try? JSONDecoder().decode(StatsData.self, from: data) else { return }
        stats = decoded.perTrack
        dailyListening = decoded.daily
    }

    private func saveStatsNow() {
        let data = StatsData(perTrack: stats, daily: dailyListening)
        if let encoded = try? JSONEncoder().encode(data) {
            try? encoded.write(to: statsFile, options: .atomic)
        }
    }

    // Sauvegarde DIFFEREE des stats : les evenements arrivent en rafale
    // (temps d'ecoute toutes les quelques secondes, skips...) et reecrire
    // tout le fichier a chaque fois est inutile. On regroupe : au plus une
    // ecriture toutes les 5 s. flushStatsNow() force l'ecriture immediate
    // (appele quand l'app passe en arriere-plan).
    private var statsSaveTask: Task<Void, Never>?

    private func scheduleStatsSave() {
        guard statsSaveTask == nil else { return }
        statsSaveTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard let self, !Task.isCancelled else { return }
            self.statsSaveTask = nil
            self.saveStatsNow()
        }
    }

    func flushStatsNow() {
        statsSaveTask?.cancel()
        statsSaveTask = nil
        saveStatsNow()
    }

    // Une ecoute complete (fin naturelle du morceau, ou > 80 % ecoute).
    func recordPlay(_ trackID: UUID) {
        stats[trackID, default: TrackStats()].plays += 1
        stats[trackID]?.lastPlayed = Date()
        scheduleStatsSave()
    }

    // Morceau passe volontairement avant la fin -> signal "j'aime moins".
    func recordSkip(_ trackID: UUID) {
        stats[trackID, default: TrackStats()].skips += 1
        scheduleStatsSave()
    }

    // Temps d'ecoute accumule (envoye par paquets par le moteur).
    func recordListening(_ trackID: UUID, seconds: Double) {
        guard seconds > 0.5 else { return }
        stats[trackID, default: TrackStats()].seconds += seconds
        dailyListening[Self.dayKey(), default: 0] += seconds
        scheduleStatsSave()
    }

    // MARK: - Pochettes en ligne (iTunes)

    // Cherche et enregistre la pochette d'un morceau. Retourne true si trouvee.
    @discardableResult
    func fetchArtworkOnline(for track: Track) async -> Bool {
        let mainArtist = track.artistList.first ?? track.artist
        guard let data = await ITunesArtwork.fetchArtworkData(title: track.title, artist: mainArtist) else { return false }
        let lib = self
        guard let name = await Task.detached(priority: .userInitiated, operation: { lib.saveArtwork(data) }).value,
              let i = tracks.firstIndex(where: { $0.id == track.id }) else { return false }
        tracks[i].artworkFileName = name
        save()
        return true
    }

    // Recupere toutes les pochettes manquantes. Retourne le nombre trouve.
    func fetchMissingArtwork() async -> Int {
        guard !isImporting else { return 0 }
        isImporting = true
        defer { isImporting = false; importProgress = "" }
        let missing = tracks.filter { $0.artworkFileName == nil }
        var found = 0
        for (index, track) in missing.enumerated() {
            importProgress = "Pochettes \(index + 1)/\(missing.count)…"
            if await fetchArtworkOnline(for: track) { found += 1 }
        }
        return found
    }

    // MARK: - Photos d'artistes (Deezer)

    private nonisolated func artistImageFile(for name: String) -> URL {
        let slug = Self.normalized(name)
            .replacingOccurrences(of: #"[^a-z0-9]+"#, with: "-", options: .regularExpression)
        return artistImagesDir.appendingPathComponent("\(slug).jpg")
    }

    nonisolated func artistImage(named name: String, pixelSize: CGFloat) -> UIImage? {
        let key = "artist#\(Self.normalized(name))#\(Int(pixelSize))" as NSString
        if let cached = thumbCache.object(forKey: key) { return cached }
        guard let data = try? Data(contentsOf: artistImageFile(for: name)),
              let image = UIImage(data: data) else { return nil }
        let thumb = image.resized(maxDimension: pixelSize)
        thumbCache.setObject(thumb, forKey: key)
        return thumb
    }

    func hasArtistImage(_ name: String) -> Bool {
        FileManager.default.fileExists(atPath: artistImageFile(for: name).path)
    }

    // Telecharge la photo d'un artiste depuis Deezer. Retourne true si trouvee.
    @discardableResult
    func fetchArtistImage(for name: String) async -> Bool {
        guard !hasArtistImage(name) else { return true }
        guard let artist = await DeezerAPI.searchArtist(name),
              Self.normalized(artist.name) == Self.normalized(name) ||
              Self.normalized(artist.name).contains(Self.normalized(name)) ||
              Self.normalized(name).contains(Self.normalized(artist.name)),
              let data = await DeezerAPI.imageData(from: artist.picture_big ?? artist.picture_medium) else {
            return false
        }
        try? data.write(to: artistImageFile(for: name))
        artistImagesVersion += 1
        return true
    }

    // Telecharge les photos manquantes de tous les artistes. Retourne le nombre trouve.
    func fetchAllArtistImages() async -> Int {
        guard !isImporting else { return 0 }
        isImporting = true
        defer { isImporting = false; importProgress = "" }
        let names = artists.keys.filter { !hasArtistImage($0) }.sorted()
        var found = 0
        for (index, name) in names.enumerated() {
            importProgress = "Photos d'artistes \(index + 1)/\(names.count)…"
            if await fetchArtistImage(for: name) { found += 1 }
        }
        return found
    }

    // Tous les morceaux d'un artiste donne (correspondance sans casse ni accents).
    func tracks(forArtist name: String) -> [Track] {
        let key = Self.normalized(name)
        if let match = artists.first(where: { Self.normalized($0.key) == key }) {
            return match.value
        }
        return []
    }

    // MARK: - Liste d'envies

    private func loadWishlist() {
        guard let data = try? Data(contentsOf: wishlistFile),
              let decoded = try? JSONDecoder().decode([WishItem].self, from: data) else { return }
        wishlist = decoded
    }

    private func saveWishlist() {
        if let encoded = try? JSONEncoder().encode(wishlist) {
            try? encoded.write(to: wishlistFile, options: .atomic)
        }
    }

    func isWished(_ id: Int) -> Bool {
        wishlist.contains { $0.id == id }
    }

    func toggleWish(_ item: WishItem) {
        if let idx = wishlist.firstIndex(where: { $0.id == item.id }) {
            wishlist.remove(at: idx)
        } else {
            wishlist.insert(item, at: 0)
        }
        saveWishlist()
    }

    func removeWish(_ item: WishItem) {
        wishlist.removeAll { $0.id == item.id }
        saveWishlist()
    }

    // Reconnaissance automatique : appele apres chaque import. Si le morceau
    // correspond a une envie (titre + artiste), l'envie est retiree et le
    // morceau range dans la playlist "Découvertes".
    // Correspondance souple mais SANS faux positifs : l'inclusion d'un titre
    // dans l'autre n'est acceptee que si le plus court fait au moins 6
    // caracteres (sinon "Home" matcherait "Coming Home", etc.).
    private static func flexibleTitleMatch(_ a: String, _ b: String) -> Bool {
        if a == b { return true }
        let shorter = a.count <= b.count ? a : b
        let longer = a.count <= b.count ? b : a
        return shorter.count >= 6 && longer.contains(shorter)
    }

    private func matchWishlist(_ track: Track) {
        let trackTitle = Self.normalized(Self.cleanedTitle(track.title))
        let trackArtists = track.artistList.map { Self.normalized($0) }
        guard let match = wishlist.first(where: { wish in
            let wishTitle = Self.normalized(Self.cleanedTitle(wish.title))
            let wishArtist = Self.normalized(wish.artist)
            let titleOK = Self.flexibleTitleMatch(wishTitle, trackTitle)
            let artistOK = trackArtists.contains { candidate in
                candidate == wishArtist
                || (min(candidate.count, wishArtist.count) >= 4
                    && (candidate.contains(wishArtist) || wishArtist.contains(candidate)))
            }
            return titleOK && artistOK
        }) else { return }

        wishlist.removeAll { $0.id == match.id }
        saveWishlist()

        // Range dans la playlist "Découvertes" (creee au besoin).
        if !playlists.contains(where: { $0.name == "Découvertes" }) {
            playlists.append(Playlist(name: "Découvertes"))
        }
        if let i = playlists.firstIndex(where: { $0.name == "Découvertes" }),
           !playlists[i].trackIDs.contains(track.id) {
            playlists[i].trackIDs.append(track.id)
        }
        save()
    }

    // nonisolated : appelable depuis les taches d'arriere-plan (le decodage
    // d'image et l'ecriture JPEG n'ont rien a faire sur le thread principal).
    nonisolated private func saveArtwork(_ data: Data) -> String? {
        guard let image = UIImage(data: data) else { return nil }
        // On redimensionne raisonnablement pour economiser l'espace.
        let resized = image.resized(maxDimension: 600)
        guard let jpeg = resized.jpegData(compressionQuality: 0.85) else { return nil }
        let name = "\(UUID().uuidString).jpg"
        try? jpeg.write(to: artworkDir.appendingPathComponent(name))
        return name
    }

    // MARK: - Suppression

    func delete(_ track: Track) {
        try? FileManager.default.removeItem(at: url(for: track))
        if let art = track.artworkFileName {
            try? FileManager.default.removeItem(at: artworkDir.appendingPathComponent(art))
        }
        tracks.removeAll { $0.id == track.id }
        for i in playlists.indices {
            playlists[i].trackIDs.removeAll { $0 == track.id }
        }
        save()
    }

    // MARK: - Favoris

    func toggleFavorite(_ track: Track) {
        guard let i = tracks.firstIndex(where: { $0.id == track.id }) else { return }
        tracks[i].isFavorite.toggle()
        save()
    }

    var favorites: [Track] { tracks.filter { $0.isFavorite } }

    // MARK: - Playlists

    func createPlaylist(name: String) {
        playlists.append(Playlist(name: name))
        save()
    }

    func deletePlaylist(_ playlist: Playlist) {
        playlists.removeAll { $0.id == playlist.id }
        save()
    }

    func renamePlaylist(_ playlist: Playlist, to name: String) {
        guard let i = playlists.firstIndex(where: { $0.id == playlist.id }) else { return }
        playlists[i].name = name
        save()
    }

    func add(_ track: Track, to playlist: Playlist) {
        guard let i = playlists.firstIndex(where: { $0.id == playlist.id }) else { return }
        if !playlists[i].trackIDs.contains(track.id) {
            playlists[i].trackIDs.append(track.id)
            save()
        }
    }

    func remove(_ track: Track, from playlist: Playlist) {
        guard let i = playlists.firstIndex(where: { $0.id == playlist.id }) else { return }
        playlists[i].trackIDs.removeAll { $0 == track.id }
        save()
    }

    func tracks(in playlist: Playlist) -> [Track] {
        playlist.trackIDs.compactMap { id in tracks.first { $0.id == id } }
    }

    // MARK: - Sauvegarde / restauration
    //
    // Vital avec le sideload (limite des 7 jours) : si l'app doit etre
    // reinstallee de zero, l'utilisateur restaure favoris, playlists,
    // paroles, statistiques et liste d'envies depuis un simple fichier JSON.
    // (Les fichiers audio eux-memes ne sont pas dans la sauvegarde : ils se
    // reimportent via le Wi-Fi ou iTunes, et sont re-relies automatiquement
    // par titre + artiste + duree.)

    struct BackupData: Codable {
        var tracks: [Track]
        var playlists: [Playlist]
        var stats: [UUID: TrackStats]
        var daily: [String: Double]
        var wishlist: [WishItem]
    }

    // Genere le fichier de sauvegarde dans un dossier temporaire et
    // retourne son URL (a partager via la feuille de partage).
    func exportBackup() -> URL? {
        let backup = BackupData(tracks: tracks, playlists: playlists,
                                stats: stats, daily: dailyListening,
                                wishlist: wishlist)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(backup) else { return nil }
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Lume-sauvegarde-\(df.string(from: Date())).json")
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    // Restaure une sauvegarde en FUSIONNANT avec l'existant (rien n'est
    // supprime). Les morceaux sont reconnus par titre + artiste + duree
    // (ou nom de fichier identique). Retourne le nombre de morceaux relies.
    @discardableResult
    func restoreBackup(from url: URL) -> Int {
        let needsStop = url.startAccessingSecurityScopedResource()
        defer { if needsStop { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url),
              let backup = try? JSONDecoder().decode(BackupData.self, from: data) else { return 0 }

        // Table ancienne ID -> ID locale, pour re-lier playlists et stats.
        var idMap: [UUID: UUID] = [:]
        for old in backup.tracks {
            guard let local = tracks.first(where: { sameSong($0, old) || $0.fileName == old.fileName })
            else { continue }
            idMap[old.id] = local.id
            if let i = tracks.firstIndex(where: { $0.id == local.id }) {
                if old.isFavorite { tracks[i].isFavorite = true }
                if tracks[i].lyrics == nil { tracks[i].lyrics = old.lyrics }
            }
        }

        // Playlists : fusionnees par nom.
        for pl in backup.playlists {
            let mapped = pl.trackIDs.compactMap { idMap[$0] }
            if let i = playlists.firstIndex(where: { $0.name == pl.name }) {
                for id in mapped where !playlists[i].trackIDs.contains(id) {
                    playlists[i].trackIDs.append(id)
                }
            } else if !mapped.isEmpty {
                playlists.append(Playlist(name: pl.name, trackIDs: mapped))
            }
        }

        // Statistiques : on garde le maximum des deux cotes.
        for (oldID, st) in backup.stats {
            guard let newID = idMap[oldID] else { continue }
            var merged = stats[newID] ?? TrackStats()
            merged.plays = max(merged.plays, st.plays)
            merged.skips = max(merged.skips, st.skips)
            merged.seconds = max(merged.seconds, st.seconds)
            merged.lastPlayed = [merged.lastPlayed, st.lastPlayed].compactMap { $0 }.max()
            stats[newID] = merged
        }
        for (day, secs) in backup.daily {
            dailyListening[day] = max(dailyListening[day] ?? 0, secs)
        }

        // Liste d'envies.
        for wish in backup.wishlist where !wishlist.contains(where: { $0.id == wish.id }) {
            wishlist.append(wish)
        }

        save()
        saveWishlist()
        flushStatsNow()
        return idMap.count
    }

    // Regroupements pratiques pour l'affichage (mis en cache, voir plus haut).
    var albums: [String: [Track]] {
        if let albumsCache { return albumsCache }
        let grouped = Dictionary(grouping: tracks) { $0.album }
        albumsCache = grouped
        return grouped
    }

    // Un morceau a plusieurs artistes apparait sous CHACUN d'eux.
    // Regroupement insensible a la casse ("rihanna" et "Rihanna" fusionnent).
    var artists: [String: [Track]] {
        if let artistsCache { return artistsCache }
        var canonical: [String: String] = [:]   // cle normalisee -> nom affiche
        var dict: [String: [Track]] = [:]
        for track in tracks {
            for name in track.artistList {
                let key = name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
                let display = canonical[key] ?? name
                canonical[key] = display
                dict[display, default: []].append(track)
            }
        }
        artistsCache = dict
        return dict
    }
}

// Petit utilitaire de redimensionnement d'image.
extension UIImage {
    func resized(maxDimension: CGFloat) -> UIImage {
        let maxSide = max(size.width, size.height)
        guard maxSide > maxDimension else { return self }
        let scale = maxDimension / maxSide
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in self.draw(in: CGRect(origin: .zero, size: newSize)) }
    }
}
