import Foundation

// Un morceau de musique : un fichier audio + ses metadonnees.
struct Track: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    // Nom du fichier stocke dans Documents/Tracks (on stocke le relatif, pas le chemin absolu,
    // car le conteneur de l'app peut changer entre les versions iOS).
    var fileName: String
    var title: String
    var artist: String
    var album: String
    var duration: Double          // en secondes
    var artworkFileName: String?  // pochette extraite, stockee dans Documents/Artwork
    var lyrics: String?
    var dateAdded: Date
    var isFavorite: Bool

    init(id: UUID = UUID(),
         fileName: String,
         title: String,
         artist: String,
         album: String,
         duration: Double,
         artworkFileName: String? = nil,
         lyrics: String? = nil,
         dateAdded: Date = Date(),
         isFavorite: Bool = false) {
        self.id = id
        self.fileName = fileName
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
        self.artworkFileName = artworkFileName
        self.lyrics = lyrics
        self.dateAdded = dateAdded
        self.isFavorite = isFavorite
    }

    static func == (lhs: Track, rhs: Track) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

// Petites aides de mise en forme.
extension Double {
    var asTimeString: String {
        guard self.isFinite, self >= 0 else { return "0:00" }
        let total = Int(self.rounded())
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }
}
