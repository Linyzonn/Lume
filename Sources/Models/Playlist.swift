import Foundation

// Une playlist : un nom + une liste ordonnee d'identifiants de morceaux.
struct Playlist: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    var name: String
    var trackIDs: [UUID]
    var dateCreated: Date

    init(id: UUID = UUID(), name: String, trackIDs: [UUID] = [], dateCreated: Date = Date()) {
        self.id = id
        self.name = name
        self.trackIDs = trackIDs
        self.dateCreated = dateCreated
    }

    // Decodage tolerant : un champ manquant ne doit pas invalider toute la
    // bibliotheque (voir le meme mecanisme dans Track).
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Playlist"
        trackIDs = try c.decodeIfPresent([UUID].self, forKey: .trackIDs) ?? []
        dateCreated = try c.decodeIfPresent(Date.self, forKey: .dateCreated) ?? Date()
    }
}
