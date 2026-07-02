import Foundation
import AVFoundation

// MARK: - Modeles de recommandation

struct Recommendation: Identifiable, Equatable {
    let id: Int                  // identifiant Deezer
    let title: String
    let artistName: String
    let coverURL: String?
    let previewURL: String?      // extrait MP3 de 30 s (ecoute en ligne)
    let linkURL: String?         // page Deezer du titre
    let reason: String

    static func == (l: Recommendation, r: Recommendation) -> Bool { l.id == r.id }
}

struct RecommendationSection: Identifiable {
    let id = UUID()
    let title: String
    let items: [Recommendation]
}

// MARK: - Moteur de recommandations
//
// 1. PROFIL DE GOUT : chaque morceau de la bibliotheque recoit un score a
//    partir des statistiques reelles d'ecoute :
//      + ecoutes completes (fort signal positif)
//      + favori (signal explicite)
//      + ecoute recente (le gout evolue, le recent pese plus)
//      - morceaux passes avant la fin (signal negatif)
//    Les scores sont agreges PAR ARTISTE (chaque artiste d'un featuring
//    recoit sa part), ce qui dresse ton profil : tes artistes prefere du
//    moment, ponderes par ton comportement reel et pas seulement tes clics.
//
// 2. DECOUVERTE : pour tes artistes les mieux notes, on interroge Deezer :
//    leurs titres que tu n'as PAS dans ta bibliotheque, et les titres phares
//    d'artistes PROCHES (la similarite Deezer encode le style musical).
//    Chaque suggestion est ecoutable en extrait de 30 s si tu es en ligne.
@MainActor
final class Recommender: ObservableObject {
    @Published var sections: [RecommendationSection] = []
    @Published var isLoading = false
    @Published var message: String?

    private var lastRefresh: Date?

    // Score de gout par artiste, du prefere au moins aime.
    static func tasteProfile(library: LibraryStore) -> [(name: String, score: Double)] {
        var scores: [String: Double] = [:]
        var displayNames: [String: String] = [:]
        let now = Date()

        for track in library.tracks {
            let st = library.stats[track.id] ?? TrackStats()
            var score = 0.5                                   // presence dans la bibliotheque
            score += Double(st.plays) * 2.0                   // ecoutes completes
            score -= Double(st.skips) * 1.5                   // morceaux zappes
            score += track.isFavorite ? 4.0 : 0               // favori explicite
            score += min(st.seconds / 600.0, 4.0)             // temps d'ecoute (plafonne)
            if let last = st.lastPlayed {                     // recence
                let days = now.timeIntervalSince(last) / 86400
                if days < 7 { score += 2 } else if days < 30 { score += 1 }
            }
            // Chaque artiste du morceau recoit le score (l'artiste principal
            // un peu plus que les invites).
            for (idx, name) in track.artistList.enumerated() {
                let key = LibraryStore.normalized(name)
                let weight = idx == 0 ? 1.0 : 0.6
                scores[key, default: 0] += score * weight
                if displayNames[key] == nil { displayNames[key] = name }
            }
        }
        return scores
            .sorted { $0.value > $1.value }
            .compactMap { key, value in
                guard let name = displayNames[key], value > 0 else { return nil }
                return (name, value)
            }
    }

    // Construit les recommandations en ligne a partir du profil.
    func refresh(library: LibraryStore, force: Bool = false) async {
        // Evite de re-interroger Deezer a chaque ouverture de l'onglet.
        if !force, let last = lastRefresh, Date().timeIntervalSince(last) < 1800,
           !sections.isEmpty { return }
        guard !isLoading else { return }

        isLoading = true
        message = nil
        defer { isLoading = false }

        let profile = Self.tasteProfile(library: library)
        guard !profile.isEmpty else {
            message = "Écoute d'abord quelques morceaux : ton profil musical se construit avec tes écoutes, tes favoris et les titres que tu passes."
            return
        }

        // Empreintes des morceaux deja possedes (pour ne pas les re-proposer).
        let owned = Set(library.tracks.map {
            LibraryStore.normalized($0.title) + "|" + LibraryStore.normalized($0.artistList.first ?? $0.artist)
        })
        func alreadyOwned(_ t: DeezerAPI.TrackItem) -> Bool {
            owned.contains(LibraryStore.normalized(LibraryStore.cleanedTitle(t.title)) + "|" +
                           LibraryStore.normalized(t.artist.name))
        }

        var newSections: [RecommendationSection] = []
        var seenIDs = Set<Int>()

        for (artistName, _) in profile.prefix(4) {
            guard let dzArtist = await DeezerAPI.searchArtist(artistName) else { continue }

            var items: [Recommendation] = []

            // 1) Ses titres que tu n'as pas encore.
            let own = await DeezerAPI.topTracks(artistID: dzArtist.id, limit: 10)
            for t in own where !alreadyOwned(t) && !seenIDs.contains(t.id) {
                items.append(recommendation(from: t, reason: "Titre de \(dzArtist.name)"))
                seenIDs.insert(t.id)
                if items.count >= 4 { break }
            }

            // 2) Les artistes proches (meme univers musical selon Deezer).
            let related = await DeezerAPI.relatedArtists(id: dzArtist.id)
            for rel in related.prefix(3) {
                let tops = await DeezerAPI.topTracks(artistID: rel.id, limit: 4)
                for t in tops where !alreadyOwned(t) && !seenIDs.contains(t.id) {
                    items.append(recommendation(from: t, reason: "Proche de \(dzArtist.name)"))
                    seenIDs.insert(t.id)
                    break   // un titre par artiste proche : plus de variete
                }
            }

            if !items.isEmpty {
                newSections.append(RecommendationSection(title: "Parce que tu écoutes \(dzArtist.name)",
                                                         items: items))
            }
        }

        sections = newSections
        lastRefresh = Date()
        if newSections.isEmpty {
            message = "Impossible de charger des recommandations. Vérifie ta connexion Internet, puis réessaie."
        }
    }

    private func recommendation(from t: DeezerAPI.TrackItem, reason: String) -> Recommendation {
        Recommendation(id: t.id,
                       title: t.title,
                       artistName: t.artist.name,
                       coverURL: t.album?.cover_big ?? t.album?.cover_medium,
                       previewURL: t.preview,
                       linkURL: t.link,
                       reason: reason)
    }
}

// MARK: - Lecteur d'extraits de 30 s (independant du moteur principal)

@MainActor
final class PreviewPlayer: ObservableObject {
    @Published var playingID: Int?

    private var player: AVPlayer?
    private var endObserver: NSObjectProtocol?

    func toggle(_ rec: Recommendation, mainEngine: PlayerEngine) {
        if playingID == rec.id {
            stop()
            return
        }
        guard let s = rec.previewURL, let url = URL(string: s) else { return }
        // On met la musique principale en pause pour laisser place a l'extrait.
        if mainEngine.isPlaying { mainEngine.pause() }
        stop()
        let item = AVPlayerItem(url: url)
        player = AVPlayer(playerItem: item)
        player?.play()
        playingID = rec.id
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.stop() }
        }
    }

    func stop() {
        player?.pause()
        player = nil
        playingID = nil
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
    }
}
