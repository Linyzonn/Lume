import SwiftUI

// MARK: - Retrospective (facon "Wrapped")
//
// Cartes plein ecran a faire defiler, avec les grands chiffres de l'annee :
// temps d'ecoute, tops, record du jour, plus longue serie... Toutes les
// donnees viennent des statistiques locales (rien ne quitte l'iPhone).
struct RecapView: View {
    @EnvironmentObject var library: LibraryStore

    // Annee GREGORIENNE : les cles de stats sont ecrites en calendrier
    // gregorien fige (voir LibraryStore.dayFormatter), le filtre par annee
    // doit utiliser le meme calendrier quel que soit le reglage du telephone.
    private var year: Int { Calendar(identifier: .gregorian).component(.year, from: Date()) }

    // Parseur des cles "yyyy-MM-dd", symetrique du formateur d'ecriture.
    private static let dayParser: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    var body: some View {
        TabView {
            timeCard
            topTracksCard
            topArtistsCard
            recordsCard
            funFactsCard
        }
        .tabViewStyle(.page(indexDisplayMode: .always))
        .indexViewStyle(.page(backgroundDisplayMode: .always))
        .background(Color.black.ignoresSafeArea())
        .navigationTitle("Rétrospective \(String(year))")
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
    }

    // MARK: - Donnees

    // Secondes ecoutees cette annee (les jours sont dates, donc exact).
    private var yearSeconds: Double {
        let prefix = "\(year)-"
        return library.dailyListening
            .filter { $0.key.hasPrefix(prefix) }
            .values.reduce(0, +)
    }

    private var activeDays: Int {
        let prefix = "\(year)-"
        return library.dailyListening.filter { $0.key.hasPrefix(prefix) && $0.value >= 60 }.count
    }

    private var topTracks: [(Track, Int)] {
        library.tracks
            .compactMap { t -> (Track, Int)? in
                guard let plays = library.stats[t.id]?.plays, plays > 0 else { return nil }
                return (t, plays)
            }
            .sorted { $0.1 > $1.1 }
    }

    private struct ArtistTotal: Identifiable {
        let id: String
        let name: String
        let seconds: Double
        let plays: Int
    }

    private var topArtists: [ArtistTotal] {
        var seconds: [String: Double] = [:]
        var plays: [String: Int] = [:]
        var names: [String: String] = [:]
        for track in library.tracks {
            guard let s = library.stats[track.id] else { continue }
            for artist in track.artistList {
                // Normalisation avec accents, comme partout ailleurs
                // ("Stromaé" et "Stromae" ne comptent plus double).
                let key = LibraryStore.normalized(artist)
                if names[key] == nil { names[key] = artist }
                seconds[key, default: 0] += s.seconds
                plays[key, default: 0] += s.plays
            }
        }
        return seconds.keys
            .map { ArtistTotal(id: $0, name: names[$0] ?? $0,
                               seconds: seconds[$0] ?? 0, plays: plays[$0] ?? 0) }
            .filter { $0.plays > 0 || $0.seconds > 60 }
            .sorted { $0.seconds > $1.seconds }
    }

    // Meilleur jour de l'annee (date + duree).
    private var bestDay: (label: String, seconds: Double)? {
        let prefix = "\(year)-"
        guard let best = library.dailyListening
            .filter({ $0.key.hasPrefix(prefix) })
            .max(by: { $0.value < $1.value }), best.value >= 60 else { return nil }
        var label = best.key
        if let date = Self.dayParser.date(from: best.key) {
            let out = DateFormatter()
            out.locale = Locale(identifier: "fr_FR")
            out.dateFormat = "d MMMM"
            label = out.string(from: date)
        }
        return (label, best.value)
    }

    // Plus longue serie de jours consecutifs (>= 1 min) de l'annee.
    private var longestStreak: Int {
        let days = library.dailyListening
            .filter { $0.value >= 60 }
            .keys.compactMap { Self.dayParser.date(from: $0) }
            .sorted()
        guard !days.isEmpty else { return 0 }
        var best = 1, current = 1
        for i in 1..<days.count {
            let gap = Calendar.current.dateComponents([.day], from: days[i - 1], to: days[i]).day ?? 99
            if gap == 1 { current += 1; best = max(best, current) }
            else if gap > 1 { current = 1 }
        }
        return best
    }

    private var totalSkips: Int {
        library.stats.values.reduce(0) { $0 + $1.skips }
    }

    // MARK: - Cartes

    private func card<Content: View>(colors: [Color],
                                     @ViewBuilder content: () -> Content) -> some View {
        ZStack {
            LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()
            VStack(spacing: 18) { content() }
                .padding(32)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var timeCard: some View {
        card(colors: [Color(red: 0.42, green: 0.36, blue: 0.92), Color(red: 0.16, green: 0.1, blue: 0.4)]) {
            Text("⏱️").font(.system(size: 56))
            Text("Cette année, tu as écouté")
                .font(.title3.weight(.medium))
                .foregroundStyle(.white.opacity(0.85))
            Text(bigDuration(yearSeconds))
                .font(.system(size: 52, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .minimumScaleFactor(0.5)
                .multilineTextAlignment(.center)
            Text("de musique, sur \(activeDays) jour\(activeDays > 1 ? "s" : "") différents.")
                .font(.title3.weight(.medium))
                .foregroundStyle(.white.opacity(0.85))
                .multilineTextAlignment(.center)
        }
    }

    private var topTracksCard: some View {
        card(colors: [Color(red: 0.92, green: 0.36, blue: 0.62), Color(red: 0.4, green: 0.08, blue: 0.28)]) {
            Text("🏆").font(.system(size: 56))
            // Les ecoutes par morceau ne sont pas datees : ce podium couvre
            // TOUTES tes ecoutes — le titre ne pretend plus « de l'annee ».
            Text("Tes titres les plus écoutés")
                .font(.title2.weight(.bold))
                .foregroundStyle(.white)
            if topTracks.isEmpty {
                Text("Pas encore assez d'écoutes… la suite au prochain épisode !")
                    .foregroundStyle(.white.opacity(0.85))
                    .multilineTextAlignment(.center)
            }
            VStack(alignment: .leading, spacing: 14) {
                ForEach(Array(topTracks.prefix(5).enumerated()), id: \.offset) { pair in
                    HStack(spacing: 14) {
                        Text("\(pair.offset + 1)")
                            .font(.title2.weight(.heavy).monospacedDigit())
                            .foregroundStyle(.white.opacity(0.6))
                            .frame(width: 30)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(pair.element.0.title).lineLimit(1)
                                .font(.headline).foregroundStyle(.white)
                            Text(pair.element.0.artist).lineLimit(1)
                                .font(.caption).foregroundStyle(.white.opacity(0.7))
                        }
                        Spacer()
                        Text("\(pair.element.1)×")
                            .font(.subheadline.weight(.bold).monospacedDigit())
                            .foregroundStyle(.white.opacity(0.85))
                    }
                }
            }
        }
    }

    private var topArtistsCard: some View {
        card(colors: [Color(red: 0.15, green: 0.5, blue: 0.95), Color(red: 0.05, green: 0.15, blue: 0.4)]) {
            Text("🎤").font(.system(size: 56))
            Text("Tes artistes les plus écoutés")
                .font(.title2.weight(.bold))
                .foregroundStyle(.white)
            if topArtists.isEmpty {
                Text("Pas encore assez d'écoutes pour établir le podium.")
                    .foregroundStyle(.white.opacity(0.85))
                    .multilineTextAlignment(.center)
            }
            VStack(alignment: .leading, spacing: 14) {
                ForEach(Array(topArtists.prefix(5).enumerated()), id: \.element.id) { pair in
                    HStack(spacing: 14) {
                        Text("\(pair.offset + 1)")
                            .font(.title2.weight(.heavy).monospacedDigit())
                            .foregroundStyle(.white.opacity(0.6))
                            .frame(width: 30)
                        Text(pair.element.name).lineLimit(1)
                            .font(.headline).foregroundStyle(.white)
                        Spacer()
                        Text(shortDuration(pair.element.seconds))
                            .font(.subheadline.weight(.bold).monospacedDigit())
                            .foregroundStyle(.white.opacity(0.85))
                    }
                }
            }
        }
    }

    private var recordsCard: some View {
        card(colors: [Color(red: 0.95, green: 0.45, blue: 0.2), Color(red: 0.45, green: 0.12, blue: 0.05)]) {
            Text("🔥").font(.system(size: 56))
            Text("Tes records")
                .font(.title2.weight(.bold))
                .foregroundStyle(.white)
            VStack(spacing: 22) {
                if let best = bestDay {
                    VStack(spacing: 4) {
                        Text("Ton plus gros jour : le \(best.label)")
                            .font(.headline).foregroundStyle(.white.opacity(0.85))
                        Text(bigDuration(best.seconds))
                            .font(.system(size: 40, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white)
                            .minimumScaleFactor(0.5)
                    }
                }
                if longestStreak > 1 {
                    VStack(spacing: 4) {
                        Text("Ta plus longue série")
                            .font(.headline).foregroundStyle(.white.opacity(0.85))
                        Text("\(longestStreak) jours d'affilée")
                            .font(.system(size: 34, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white)
                    }
                }
                if bestDay == nil && longestStreak <= 1 {
                    Text("Écoute encore un peu, les records arrivent…")
                        .foregroundStyle(.white.opacity(0.85))
                }
            }
        }
    }

    private var funFactsCard: some View {
        card(colors: [Color(red: 0.16, green: 0.65, blue: 0.45), Color(red: 0.03, green: 0.25, blue: 0.18)]) {
            Text("✨").font(.system(size: 56))
            Text("En vrac")
                .font(.title2.weight(.bold))
                .foregroundStyle(.white)
            VStack(alignment: .leading, spacing: 16) {
                factRow(icon: "music.note",
                        text: "\(library.tracks.count) titres dans ta bibliothèque")
                factRow(icon: "heart.fill",
                        text: "\(library.favorites.count) favoris")
                factRow(icon: "play.circle.fill",
                        text: "\(library.stats.values.reduce(0) { $0 + $1.plays }) écoutes complètes")
                factRow(icon: "forward.fill",
                        text: "\(totalSkips) morceaux zappés (ça arrive aux meilleurs)")
            }
            .padding(.top, 4)
        }
    }

    private func factRow(icon: String, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .frame(width: 28)
                .foregroundStyle(.white.opacity(0.8))
            Text(text)
                .font(.headline)
                .foregroundStyle(.white)
        }
    }

    // MARK: - Formats

    private func bigDuration(_ seconds: Double) -> String {
        let total = Int(seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        if h > 0 { return "\(h) h \(String(format: "%02d", m))" }
        if m > 0 { return "\(m) min" }
        return "\(total) s"
    }

    private func shortDuration(_ seconds: Double) -> String {
        let total = Int(seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        if h > 0 { return "\(h) h" }
        return "\(m) min"
    }
}
