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

// MARK: - Statistiques d'ecoute d'un morceau (stockees a part dans stats.json)

struct TrackStats: Codable {
    var plays = 0                 // ecoutes completes (ou > 80 %)
    var skips = 0                 // fois passe avant la fin
    var seconds: Double = 0       // temps total d'ecoute
    var lastPlayed: Date?
}

// MARK: - Decoupage multi-artistes

extension Track {
    // Noms d'artistes celebres qui CONTIENNENT un separateur (virgule, &, /)
    // et qu'il ne faut donc jamais decouper.
    private static let protectedArtists: [String] = [
        "tyler, the creator", "earth, wind & fire",
        "crosby, stills, nash & young", "crosby, stills & nash",
        "emerson, lake & palmer", "ac/dc", "simon & garfunkel",
        "hall & oates", "salt-n-pepa", "mumford & sons", "she & him",
        "kool & the gang", "ike & tina turner", "brooks & dunn",
        "dan + shay", "bob marley & the wailers",
        "tom petty & the heartbreakers", "derek & the dominos",
        "florence + the machine", "now, now"
    ]

    // Liste des artistes individuels d'un morceau.
    // "JAY-Z, Rihanna & Kanye West" -> ["JAY-Z", "Rihanna", "Kanye West"]
    // mais "Tyler, The Creator" reste entier grace a la liste protegee.
    var artistList: [String] {
        var s = artist
        // 1) On met les noms proteges de cote (remplaces par des jetons).
        var placeholders: [String: String] = [:]
        for (i, name) in Self.protectedArtists.enumerated() {
            if let range = s.range(of: name, options: [.caseInsensitive, .diacriticInsensitive]) {
                let token = "\u{2}P\(i)\u{2}"
                placeholders[token] = String(s[range])
                s.replaceSubrange(range, with: token)
            }
        }
        // 2) Decoupage sur les separateurs usuels de collaborations.
        let pattern = #"(?i)\s*(?:,|;|/|\||&|\bfeat\b\.?|\bft\b\.?|\bfeaturing\b|\bavec\b|\swith\s|\sx\s)\s*"#
        let marked = s.replacingOccurrences(of: pattern, with: "\u{1}", options: .regularExpression)
        // 3) On restaure les noms proteges et on nettoie.
        let parts = marked.components(separatedBy: "\u{1}")
            .map { part -> String in
                var out = part
                for (token, original) in placeholders {
                    out = out.replacingOccurrences(of: token, with: original)
                }
                return out.trimmingCharacters(in: .whitespaces)
            }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? [artist] : parts
    }
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
