import Foundation
import AVFoundation
import UIKit
import Combine

// Le cerveau de la bibliotheque : importe les fichiers, lit les metadonnees,
// sauvegarde tout sur le disque, gere playlists et favoris.
@MainActor
final class LibraryStore: ObservableObject {
    @Published var tracks: [Track] = []
    @Published var playlists: [Playlist] = []
    @Published var isImporting = false
    @Published var importProgress: String = ""

    // Dossiers de stockage dans le conteneur de l'app.
    private let docs: URL
    private let tracksDir: URL
    private let artworkDir: URL
    private let libraryFile: URL

    init() {
        let fm = FileManager.default
        docs = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        tracksDir = docs.appendingPathComponent("Tracks", isDirectory: true)
        artworkDir = docs.appendingPathComponent("Artwork", isDirectory: true)
        libraryFile = docs.appendingPathComponent("library.json")

        try? fm.createDirectory(at: tracksDir, withIntermediateDirectories: true)
        try? fm.createDirectory(at: artworkDir, withIntermediateDirectories: true)
        load()
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

    // MARK: - Persistance

    private struct LibraryData: Codable {
        var tracks: [Track]
        var playlists: [Playlist]
    }

    private func load() {
        guard let data = try? Data(contentsOf: libraryFile),
              let decoded = try? JSONDecoder().decode(LibraryData.self, from: data) else { return }
        // On ne garde que les morceaux dont le fichier existe encore.
        tracks = decoded.tracks.filter {
            FileManager.default.fileExists(atPath: tracksDir.appendingPathComponent($0.fileName).path)
        }
        playlists = decoded.playlists
    }

    func save() {
        let data = LibraryData(tracks: tracks, playlists: playlists)
        if let encoded = try? JSONEncoder().encode(data) {
            try? encoded.write(to: libraryFile, options: .atomic)
        }
    }

    // MARK: - Import de fichiers

    func importFiles(_ urls: [URL]) async {
        isImporting = true
        defer { isImporting = false; importProgress = ""; save() }

        for (index, source) in urls.enumerated() {
            importProgress = "Import \(index + 1)/\(urls.count)…"
            let needsStop = source.startAccessingSecurityScopedResource()
            defer { if needsStop { source.stopAccessingSecurityScopedResource() } }

            // Nom de fichier unique dans notre dossier.
            let ext = source.pathExtension.isEmpty ? "m4a" : source.pathExtension
            let storedName = "\(UUID().uuidString).\(ext)"
            let dest = tracksDir.appendingPathComponent(storedName)

            do {
                try FileManager.default.copyItem(at: source, to: dest)
            } catch {
                continue // fichier illisible : on passe au suivant
            }

            let track = await extractMetadata(from: dest,
                                              storedName: storedName,
                                              fallbackName: source.deletingPathExtension().lastPathComponent)
            tracks.append(track)
        }
        // Tri par date d'ajout (recent en haut).
        tracks.sort { $0.dateAdded > $1.dateAdded }
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
                        artworkName = saveArtwork(data)
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
    static func normalized(_ s: String) -> String {
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

    private func saveArtwork(_ data: Data) -> String? {
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

    // Regroupements pratiques pour l'affichage.
    var albums: [String: [Track]] { Dictionary(grouping: tracks) { $0.album } }

    // Un morceau a plusieurs artistes apparait sous CHACUN d'eux.
    // Regroupement insensible a la casse ("rihanna" et "Rihanna" fusionnent).
    var artists: [String: [Track]] {
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
