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
}
