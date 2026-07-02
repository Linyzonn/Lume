import Foundation
import AVFoundation
import NaturalLanguage

// MARK: - Modeles de recommandation

struct Recommendation: Identifiable, Equatable {
    let id: Int                  // identifiant Deezer
    let title: String
    let artistName: String
    let coverURL: String?
    let previewURL: String?      // extrait MP3 de 30 s (ecoute en ligne)
    let linkURL: String?         // page Deezer du titre
    let reason: String
    var bpm: Double? = nil       // tempo (si connu de Deezer)

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
    // Resume lisible du profil : genres, langues, tempo (affiche dans Decouvrir).
    @Published var profileSummary: String?

    private var lastRefresh: Date?
    private var genreNames: [Int: String] = [:]
    private var bpmCenter: Double?    // tempo median de tes titres preferes

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

        // Table des genres Deezer (une seule fois).
        if genreNames.isEmpty { genreNames = await DeezerAPI.genres() }

        // Profil BPM : tempo median de tes titres les mieux notes (mis en cache 7 jours).
        await computeBPMProfileIfNeeded(library: library, profile: profile)

        var newSections: [RecommendationSection] = []
        var seenIDs = Set<Int>()
        var mainGenreID: Int?
        var mainGenreName: String?

        for (rank, entry) in profile.prefix(4).enumerated() {
            let artistName = entry.name
            guard let dzArtist = await DeezerAPI.searchArtist(artistName) else { continue }

            // Genre principal du 1er artiste (pour la section Tendances plus bas).
            if rank == 0, let gid = await DeezerAPI.artistMainGenreID(artistID: dzArtist.id) {
                mainGenreID = gid
                mainGenreName = genreNames[gid]
            }

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

        // 3) Tendances du genre principal (au-dela de tes artistes : le STYLE).
        if let gid = mainGenreID {
            let chart = await DeezerAPI.genreChartTracks(genreID: gid, limit: 15)
            var items: [Recommendation] = []
            for t in chart where !alreadyOwned(t) && !seenIDs.contains(t.id) {
                items.append(recommendation(from: t, reason: mainGenreName ?? "Tendance"))
                seenIDs.insert(t.id)
                if items.count >= 8 { break }
            }
            if !items.isEmpty {
                newSections.append(RecommendationSection(
                    title: "Tendances \(mainGenreName ?? "de ton style")",
                    items: items))
            }
        }

        // 4) Enrichissement BPM des suggestions (plafonne pour rester rapide),
        //    puis tri : les titres proches de TON tempo passent en premier.
        newSections = await enrichWithBPM(sections: newSections, cap: 16)

        sections = newSections
        lastRefresh = Date()
        updateProfileSummary(library: library, genreName: mainGenreName)
        if newSections.isEmpty {
            message = "Impossible de charger des recommandations. Vérifie ta connexion Internet, puis réessaie."
        }
    }

    // MARK: - Profil BPM

    private func computeBPMProfileIfNeeded(library: LibraryStore,
                                           profile: [(name: String, score: Double)]) async {
        let d = UserDefaults.standard
        if let saved = d.object(forKey: "bpm.center") as? Double,
           let date = d.object(forKey: "bpm.date") as? Date,
           Date().timeIntervalSince(date) < 7 * 86400 {
            bpmCenter = saved > 0 ? saved : nil
            return
        }
        // Echantillon : tes 6 morceaux les mieux notes, retrouves sur Deezer.
        let ranked = library.tracks.sorted { a, b in
            let sa = library.stats[a.id], sb = library.stats[b.id]
            let scoreA = Double(sa?.plays ?? 0) * 2 + (a.isFavorite ? 4 : 0) - Double(sa?.skips ?? 0)
            let scoreB = Double(sb?.plays ?? 0) * 2 + (b.isFavorite ? 4 : 0) - Double(sb?.skips ?? 0)
            return scoreA > scoreB
        }
        var bpms: [Double] = []
        for track in ranked.prefix(6) {
            let artist = track.artistList.first ?? track.artist
            guard let found = await DeezerAPI.searchTrack(title: track.title, artist: artist),
                  let details = await DeezerAPI.trackDetails(id: found.id),
                  let bpm = details.bpm, bpm > 40 else { continue }
            bpms.append(bpm)
        }
        let center: Double = bpms.isEmpty ? 0 : bpms.sorted()[bpms.count / 2]
        bpmCenter = center > 0 ? center : nil
        d.set(center, forKey: "bpm.center")
        d.set(Date(), forKey: "bpm.date")
    }

    private func enrichWithBPM(sections: [RecommendationSection], cap: Int) async -> [RecommendationSection] {
        var budget = cap
        var out: [RecommendationSection] = []
        for section in sections {
            var items = section.items
            for i in items.indices where budget > 0 {
                if let details = await DeezerAPI.trackDetails(id: items[i].id),
                   let bpm = details.bpm, bpm > 40 {
                    items[i].bpm = bpm
                }
                budget -= 1
            }
            // Les titres dans ta zone de tempo (±15 %) remontent en tete.
            if let center = bpmCenter {
                items.sort { a, b in
                    func closeness(_ r: Recommendation) -> Double {
                        guard let bpm = r.bpm else { return 0.5 }
                        return abs(bpm - center) / center < 0.15 ? 0 : 1
                    }
                    return closeness(a) < closeness(b)
                }
            }
            out.append(RecommendationSection(title: section.title, items: items))
        }
        return out
    }

    // MARK: - Resume du profil (genres, langues, tempo)

    private func updateProfileSummary(library: LibraryStore, genreName: String?) {
        var parts: [String] = []
        if let genreName { parts.append(genreName) }
        let languages = dominantLanguages(library: library)
        if !languages.isEmpty { parts.append(languages.joined(separator: ", ")) }
        if let center = bpmCenter { parts.append("~\(Int(center)) BPM") }
        profileSummary = parts.isEmpty ? nil : parts.joined(separator: " • ")
    }

    // Langues dominantes, detectees LOCALEMENT depuis les paroles de ta
    // bibliotheque (aucune requete reseau).
    private func dominantLanguages(library: LibraryStore) -> [String] {
        var counts: [String: Int] = [:]
        for track in library.tracks {
            guard let lyrics = track.lyrics, lyrics.count > 80 else { continue }
            let sample = String(lyrics.prefix(500))
            guard let lang = NLLanguageRecognizer.dominantLanguage(for: sample)?.rawValue else { continue }
            counts[lang, default: 0] += 1
        }
        return counts.sorted { $0.value > $1.value }
            .prefix(2)
            .compactMap { code, _ in
                Locale.current.localizedString(forLanguageCode: code)?.capitalized
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
