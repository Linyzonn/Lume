import Foundation
import AVFoundation
import NaturalLanguage

// MARK: - Modeles de recommandation

struct Recommendation: Identifiable, Equatable, Codable {
    let id: Int                  // identifiant Deezer
    let title: String
    let artistName: String
    let coverURL: String?
    let previewURL: String?      // extrait MP3 de 30 s (ecoute en ligne)
    let linkURL: String?         // page Deezer du titre
    let reason: String
    var bpm: Double? = nil       // tempo (si connu de Deezer)

    // L'egalite inclut le BPM : c'est le seul champ mutable, et SwiftUI se
    // sert de Equatable pour savoir quoi re-rendre — sans lui, le badge de
    // tempo pouvait ne pas apparaitre apres l'enrichissement.
    static func == (l: Recommendation, r: Recommendation) -> Bool {
        l.id == r.id && l.bpm == r.bpm
    }
}

struct RecommendationSection: Identifiable, Codable {
    var id = UUID()
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
    // true quand on affiche des suggestions rechargees du disque (pas de reseau).
    @Published var isOffline = false
    @Published var lastRefreshDate: Date?
    // Resume lisible du profil : genres, langues, tempo (affiche dans Decouvrir).
    @Published var profileSummary: String?

    private var lastRefresh: Date?

    // Persistance des dernieres suggestions (mode hors-ligne de Decouvrir).
    private struct SavedRecommendations: Codable {
        let date: Date
        let sections: [RecommendationSection]
    }

    private static var saveFile: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Lume", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("recommendations.json")
    }

    private func persistSections() {
        guard !sections.isEmpty else { return }
        let saved = SavedRecommendations(date: Date(), sections: sections)
        if let data = try? JSONEncoder().encode(saved) {
            try? data.write(to: Self.saveFile, options: .atomic)
        }
    }

    // Recharge les dernieres suggestions connues (affichage instantane et
    // mode hors-ligne). Retourne true si quelque chose a ete recharge.
    @discardableResult
    func loadPersistedSections() -> Bool {
        guard sections.isEmpty,
              let data = try? Data(contentsOf: Self.saveFile),
              let saved = try? JSONDecoder().decode(SavedRecommendations.self, from: data),
              !saved.sections.isEmpty else { return false }
        sections = saved.sections
        lastRefreshDate = saved.date
        return true
    }
    private var genreNames: [Int: String] = [:]
    private var bpmCenter: Double?    // tempo median de tes titres preferes

    // MARK: - Memoire des suggestions deja montrees
    //
    // Sans elle, rien n'empechait les MEMES titres de revenir a chaque
    // rafraichissement (les tops Deezer sont tres stables). On garde les
    // ~400 derniers identifiants proposes : ils sont evites tant qu'il
    // reste du neuf, et resservis seulement en dernier recours (petite
    // bibliotheque / catalogue epuise), plutot qu'un ecran vide.
    private var shownHistory: [Int] = []
    private var shownHistoryLoaded = false
    private static let shownHistoryCap = 400

    private static var shownHistoryFile: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Lume", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("seenSuggestions.json")
    }

    private func loadShownHistoryIfNeeded() {
        guard !shownHistoryLoaded else { return }
        shownHistoryLoaded = true
        if let data = try? Data(contentsOf: Self.shownHistoryFile),
           let ids = try? JSONDecoder().decode([Int].self, from: data) {
            shownHistory = ids
        }
    }

    private func rememberShown(_ ids: [Int]) {
        loadShownHistoryIfNeeded()
        // Les plus recents en fin de liste ; on retire les doublons d'abord.
        shownHistory.removeAll { ids.contains($0) }
        shownHistory.append(contentsOf: ids)
        if shownHistory.count > Self.shownHistoryCap {
            shownHistory.removeFirst(shownHistory.count - Self.shownHistoryCap)
        }
        if let data = try? JSONEncoder().encode(shownHistory) {
            try? data.write(to: Self.shownHistoryFile, options: .atomic)
        }
    }

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

    // Tirage pondere SANS remise (methode d'Efraimidis-Spirakis) parmi le
    // haut du profil. L'artiste n°1 est toujours garde (c'est l'ancre du
    // profil, elle fixe aussi le genre principal) ; les autres places sont
    // tirees parmi les ~11 suivants, proportionnellement a leur score.
    // Resultat : chaque rafraichissement explore un angle different de tes
    // gouts au lieu de toujours partir des 4 memes artistes.
    static func sampleArtists(from profile: [(name: String, score: Double)],
                              count: Int) -> [(name: String, score: Double)] {
        guard profile.count > count, count > 1 else { return Array(profile.prefix(count)) }
        var picked = [profile[0]]
        let pool = Array(profile.dropFirst().prefix(11))
        let drawn = pool
            .map { entry in (entry, pow(Double.random(in: 0.0001...1), 1.0 / max(entry.score, 0.001))) }
            .sorted { $0.1 > $1.1 }
            .prefix(count - 1)
            .map { $0.0 }
        picked.append(contentsOf: drawn)
        return picked.sorted { $0.score > $1.score }
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

        // Suggestions deja montrees lors des precedents rafraichissements :
        // on les evite tant qu'il reste des titres jamais proposes.
        loadShownHistoryIfNeeded()
        let previouslyShown = Set(shownHistory)

        // Un titre est proposable s'il n'est ni possede, ni deja affiche dans
        // CE rafraichissement, ni deja dans la liste d'envies.
        func eligible(_ t: DeezerAPI.TrackItem) -> Bool {
            !alreadyOwned(t) && !seenIDs.contains(t.id) && !library.isWished(t.id)
        }

        // Selection en deux passes dans un vivier MELANGE : d'abord les titres
        // jamais montres, puis (seulement si necessaire) les deja vus.
        func pick(from pool: [DeezerAPI.TrackItem], count: Int,
                  reason: (DeezerAPI.TrackItem) -> String) -> [Recommendation] {
            var out: [Recommendation] = []
            let shuffled = pool.shuffled()
            for allowSeen in [false, true] {
                for t in shuffled where eligible(t) && (allowSeen || !previouslyShown.contains(t.id)) {
                    out.append(recommendation(from: t, reason: reason(t)))
                    seenIDs.insert(t.id)
                    if out.count >= count { return out }
                }
            }
            return out
        }

        // Toutes les donnees d'un artiste (recherche, tops, artistes proches)
        // sont recuperees EN PARALLELE pour les 4 artistes retenus : le
        // rafraichissement passe de ~10-15 s a ~3-4 s. L'assemblage des
        // sections reste sequentiel (ordre stable + deduplication seenIDs).
        struct ArtistBundle {
            let rank: Int
            let artist: DeezerAPI.Artist
            let ownTop: [DeezerAPI.TrackItem]
            let relatedTops: [(name: String, tracks: [DeezerAPI.TrackItem])]
            let genreID: Int?
        }

        // 4 artistes : le n°1 du profil + 3 tires au sort (ponderes par score).
        let topProfile = Self.sampleArtists(from: profile, count: 4)
        // Le vivier est volontairement LARGE (top 35 au lieu de 10) : meme
        // quand la reponse vient du cache, on pioche au hasard dedans, donc
        // les suggestions changent d'un rafraichissement a l'autre.
        var bundles: [ArtistBundle] = await withTaskGroup(of: ArtistBundle?.self) { group in
            for (rank, entry) in topProfile.enumerated() {
                let artistName = entry.name
                group.addTask {
                    guard let dzArtist = await DeezerAPI.searchArtist(artistName) else { return nil }
                    async let ownTask = DeezerAPI.topTracks(artistID: dzArtist.id, limit: 35,
                                                            ignoreCache: force)
                    async let relatedTask = DeezerAPI.relatedArtists(id: dzArtist.id,
                                                                     ignoreCache: force)
                    let genreID: Int? = rank == 0
                        ? await DeezerAPI.artistMainGenreID(artistID: dzArtist.id)
                        : nil
                    // 3 artistes proches tires AU HASARD parmi les 12 renvoyes
                    // par Deezer (avant : toujours les 3 premiers).
                    let related = await relatedTask
                    var relatedTops: [(String, [DeezerAPI.TrackItem])] = []
                    for rel in related.shuffled().prefix(3) {
                        relatedTops.append((rel.name,
                                            await DeezerAPI.topTracks(artistID: rel.id, limit: 8,
                                                                      ignoreCache: force)))
                    }
                    return ArtistBundle(rank: rank, artist: dzArtist,
                                        ownTop: await ownTask,
                                        relatedTops: relatedTops.map { (name: $0.0, tracks: $0.1) },
                                        genreID: genreID)
                }
            }
            var results: [ArtistBundle] = []
            for await bundle in group {
                if let bundle { results.append(bundle) }
            }
            return results
        }
        bundles.sort { $0.rank < $1.rank }

        for bundle in bundles {
            let dzArtist = bundle.artist
            if bundle.rank == 0, let gid = bundle.genreID {
                mainGenreID = gid
                mainGenreName = genreNames[gid]
            }

            var items: [Recommendation] = []

            // 1) Ses titres que tu n'as pas encore (4, pioches dans le top 35).
            items += pick(from: bundle.ownTop, count: 4) { _ in "Titre de \(dzArtist.name)" }

            // 2) Les artistes proches (meme univers musical selon Deezer) :
            //    un titre par artiste proche, pour la variete.
            for related in bundle.relatedTops {
                items += pick(from: related.tracks, count: 1) { _ in "Proche de \(dzArtist.name)" }
            }

            if !items.isEmpty {
                newSections.append(RecommendationSection(title: "Parce que tu écoutes \(dzArtist.name)",
                                                         items: items))
            }
        }

        // 3) Tendances du genre principal (au-dela de tes artistes : le STYLE).
        if let gid = mainGenreID {
            let chart = await DeezerAPI.genreChartTracks(genreID: gid, limit: 30, ignoreCache: force)
            let items = pick(from: chart, count: 8) { _ in mainGenreName ?? "Tendance" }
            if !items.isEmpty {
                newSections.append(RecommendationSection(
                    title: "Tendances \(mainGenreName ?? "de ton style")",
                    items: items))
            }
        }

        // 4) Enrichissement BPM des suggestions (plafonne pour rester rapide),
        //    puis tri : les titres proches de TON tempo passent en premier.
        newSections = await enrichWithBPM(sections: newSections, cap: 16)

        updateProfileSummary(library: library, genreName: mainGenreName)

        if newSections.isEmpty {
            // Reseau indisponible (ou rien trouve) : on ressert les dernieres
            // suggestions sauvegardees plutot qu'un ecran vide.
            if loadPersistedSections() || !sections.isEmpty {
                isOffline = true
                message = nil
            } else {
                message = "Impossible de charger des recommandations. Vérifie ta connexion Internet, puis réessaie."
            }
        } else {
            sections = newSections
            lastRefresh = Date()
            lastRefreshDate = Date()
            isOffline = false
            persistSections()
            // Memorise ce qui vient d'etre montre pour ne pas le re-proposer.
            rememberShown(newSections.flatMap { $0.items.map(\.id) })
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
        // Les 6 recherches sont lancees en parallele (2 appels chacune).
        let samples: [(title: String, artist: String)] = ranked.prefix(6).map {
            ($0.title, $0.artistList.first ?? $0.artist)
        }
        let bpms: [Double] = await withTaskGroup(of: Double?.self) { group in
            for sample in samples {
                group.addTask {
                    guard let found = await DeezerAPI.searchTrack(title: sample.title, artist: sample.artist),
                          let details = await DeezerAPI.trackDetails(id: found.id),
                          let bpm = details.bpm, bpm > 40 else { return nil }
                    return bpm
                }
            }
            var results: [Double] = []
            for await bpm in group {
                if let bpm { results.append(bpm) }
            }
            return results
        }
        let center: Double = bpms.isEmpty ? 0 : bpms.sorted()[bpms.count / 2]
        bpmCenter = center > 0 ? center : nil
        d.set(center, forKey: "bpm.center")
        d.set(Date(), forKey: "bpm.date")
    }

    private func enrichWithBPM(sections: [RecommendationSection], cap: Int) async -> [RecommendationSection] {
        // Sans profil BPM (bibliotheque introuvable sur Deezer, hors-ligne...),
        // le tri par tempo est impossible : on s'epargne alors les ~16
        // requetes de details, qui etaient le poste reseau le plus cher de
        // Decouvrir pour un simple badge d'affichage.
        guard bpmCenter != nil else { return sections }
        // Les requetes de details (une par titre, plafonnees a `cap`) sont
        // lancees EN PARALLELE : ~16 appels passent de ~4 s a ~0,5 s.
        var ids: [Int] = []
        for section in sections {
            for item in section.items where ids.count < cap {
                ids.append(item.id)
            }
        }
        let bpmByID: [Int: Double] = await withTaskGroup(of: (Int, Double?).self) { group in
            for id in ids {
                group.addTask {
                    (id, await DeezerAPI.trackDetails(id: id)?.bpm)
                }
            }
            var map: [Int: Double] = [:]
            for await (id, bpm) in group {
                if let bpm, bpm > 40 { map[id] = bpm }
            }
            return map
        }

        var out: [RecommendationSection] = []
        for section in sections {
            var items = section.items
            for i in items.indices {
                if let bpm = bpmByID[items[i].id] { items[i].bpm = bpm }
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
        // La session audio n'est plus activee au lancement de l'app : on
        // s'assure qu'elle l'est avant de jouer l'extrait.
        try? AVAudioSession.sharedInstance().setActive(true)
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
