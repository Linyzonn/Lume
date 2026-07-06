import SwiftUI
import Charts

// Statistiques d'ecoute : totaux, activite des 14 derniers jours,
// tops titres / artistes, morceaux les plus zappes.
struct StatsView: View {
    @EnvironmentObject var library: LibraryStore

    var body: some View {
        List {
            recapSection
            totalsSection
            activitySection
            topTracksSection
            topArtistsSection
            skippedSection
        }
        .navigationTitle("Statistiques")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Retrospective (Wrapped)

    private var recapSection: some View {
        Section {
            NavigationLink {
                RecapView()
            } label: {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(LinearGradient(colors: [LumeTheme.accent, LumeTheme.accentSecondary],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 44, height: 44)
                        Image(systemName: "sparkles")
                            .foregroundStyle(.white)
                    }
                    VStack(alignment: .leading) {
                        Text("Ta rétrospective").font(.headline)
                        Text("Ton année en musique, façon Wrapped")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - Totaux

    private var totalsSection: some View {
        Section {
            LabeledContent("Temps d'écoute total", value: formatDuration(totalSeconds))
            LabeledContent("Écoutes complètes", value: "\(totalPlays)")
            LabeledContent("Titres écoutés", value: "\(listenedCount) / \(library.tracks.count)")
            if currentStreak > 1 {
                LabeledContent {
                    Text("\(currentStreak) jours 🔥")
                } label: {
                    Text("Série en cours")
                }
            }
        } header: {
            Text("En résumé")
        }
    }

    // Nombre de jours CONSECUTIFS avec au moins une minute d'ecoute,
    // en remontant depuis aujourd'hui (ou hier, pour ne pas casser la
    // serie avant d'avoir ecoute quelque chose dans la journee).
    private var currentStreak: Int {
        let cal = Calendar.current
        func listened(_ date: Date) -> Bool {
            (library.dailyListening[LibraryStore.dayKey(date)] ?? 0) >= 60
        }
        var day = Date()
        if !listened(day) {
            guard let yesterday = cal.date(byAdding: .day, value: -1, to: day),
                  listened(yesterday) else { return 0 }
            day = yesterday
        }
        var streak = 0
        while listened(day) {
            streak += 1
            guard let previous = cal.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return streak
    }

    // MARK: - Activite 14 jours

    private struct DayPoint: Identifiable {
        let id: String
        let label: String
        let minutes: Double
    }

    private var last14Days: [DayPoint] {
        let cal = Calendar.current
        let df = DateFormatter()
        df.dateFormat = "E d"   // "mar. 2"
        return (0..<14).reversed().compactMap { offset in
            guard let day = cal.date(byAdding: .day, value: -offset, to: Date()) else { return nil }
            let key = LibraryStore.dayKey(day)
            let seconds = library.dailyListening[key] ?? 0
            return DayPoint(id: key, label: df.string(from: day), minutes: seconds / 60)
        }
    }

    private var activitySection: some View {
        Section {
            Chart(last14Days) { point in
                BarMark(
                    x: .value("Jour", point.label),
                    y: .value("Minutes", point.minutes)
                )
                .foregroundStyle(LumeTheme.accent.gradient)
                .cornerRadius(3)
            }
            .frame(height: 160)
            .padding(.vertical, 6)
        } header: {
            Text("Minutes écoutées — 14 derniers jours")
        }
    }

    // MARK: - Tops

    private struct RankedTrack: Identifiable {
        var id: UUID { track.id }
        let rank: Int
        let track: Track
        let stats: TrackStats
    }

    private var rankedTracks: [RankedTrack] {
        let sorted = library.tracks
            .compactMap { t -> (Track, TrackStats)? in
                guard let s = library.stats[t.id], s.plays > 0 || s.seconds > 30 else { return nil }
                return (t, s)
            }
            .sorted { a, b in
                if a.1.plays != b.1.plays { return a.1.plays > b.1.plays }
                return a.1.seconds > b.1.seconds
            }
        return sorted.enumerated().map { RankedTrack(rank: $0.offset + 1, track: $0.element.0, stats: $0.element.1) }
    }

    private var topTracksSection: some View {
        Section {
            let top = Array(rankedTracks.prefix(10))
            if top.isEmpty {
                Text("Écoute quelques morceaux pour voir tes tops apparaître ici.")
                    .foregroundStyle(.secondary)
            }
            ForEach(top) { entry in
                HStack(spacing: 12) {
                    Text("\(entry.rank)")
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(entry.rank <= 3 ? LumeTheme.accent : .secondary)
                        .frame(width: 26)
                    ArtworkView(track: entry.track, size: 42, corner: 6)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.track.title).lineLimit(1)
                        Text(entry.track.artist)
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(entry.stats.plays) écoutes")
                            .font(.caption.monospacedDigit())
                        Text(formatDuration(entry.stats.seconds))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            Text("Tes titres les plus écoutés")
        }
    }

    private struct ArtistStat: Identifiable {
        let id: String
        let name: String
        let plays: Int
        let seconds: Double
    }

    private var topArtists: [ArtistStat] {
        var plays: [String: Int] = [:]
        var seconds: [String: Double] = [:]
        var display: [String: String] = [:]
        for track in library.tracks {
            guard let s = library.stats[track.id] else { continue }
            for name in track.artistList {
                let key = LibraryStore.normalized(name)
                plays[key, default: 0] += s.plays
                seconds[key, default: 0] += s.seconds
                if display[key] == nil { display[key] = name }
            }
        }
        return plays.keys
            .compactMap { key -> ArtistStat? in
                guard let name = display[key] else { return nil }
                let p = plays[key] ?? 0
                let sec = seconds[key] ?? 0
                guard p > 0 || sec > 30 else { return nil }
                return ArtistStat(id: key, name: name, plays: p, seconds: sec)
            }
            .sorted { a, b in
                if a.plays != b.plays { return a.plays > b.plays }
                return a.seconds > b.seconds
            }
    }

    private var topArtistsSection: some View {
        Section {
            let top = Array(topArtists.prefix(8))
            if top.isEmpty {
                Text("Pas encore assez d'écoutes.")
                    .foregroundStyle(.secondary)
            }
            ForEach(top) { artist in
                let index = top.firstIndex(where: { $0.id == artist.id }) ?? 0
                HStack(spacing: 12) {
                    Text("\(index + 1)")
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(index < 3 ? LumeTheme.accent : .secondary)
                        .frame(width: 26)
                    ArtistAvatarView(name: artist.name, size: 42)
                    Text(artist.name).lineLimit(1)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(artist.plays) écoutes")
                            .font(.caption.monospacedDigit())
                        Text(formatDuration(artist.seconds))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            Text("Tes artistes préférés")
        }
    }

    // MARK: - Les plus zappes

    private struct SkippedEntry: Identifiable {
        var id: UUID { track.id }
        let track: Track
        let skips: Int
    }

    private var skippedSection: some View {
        Section {
            let skipped: [SkippedEntry] = library.tracks
                .compactMap { t in
                    guard let s = library.stats[t.id], s.skips >= 2 else { return nil }
                    return SkippedEntry(track: t, skips: s.skips)
                }
                .sorted { $0.skips > $1.skips }
                .prefix(5)
                .map { $0 }
            if skipped.isEmpty {
                Text("Aucun morceau que tu zappes régulièrement. 👍")
                    .foregroundStyle(.secondary)
            }
            ForEach(skipped) { entry in
                HStack(spacing: 12) {
                    ArtworkView(track: entry.track, size: 42, corner: 6)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.track.title).lineLimit(1)
                        Text(entry.track.artist)
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                    Text("passé \(entry.skips)×")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.orange)
                }
            }
        } header: {
            Text("Ceux que tu passes souvent")
        } footer: {
            Text("Ces signaux (écoutes, temps, favoris, morceaux passés) alimentent l'onglet Découvrir.")
        }
    }

    // MARK: - Aides

    private var totalSeconds: Double { library.dailyListening.values.reduce(0, +) }
    private var totalPlays: Int { library.stats.values.reduce(0) { $0 + $1.plays } }
    private var listenedCount: Int {
        library.tracks.filter { (library.stats[$0.id]?.plays ?? 0) > 0 }.count
    }

    private func formatDuration(_ seconds: Double) -> String {
        let total = Int(seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        if h > 0 { return "\(h) h \(m) min" }
        if m > 0 { return "\(m) min" }
        return "\(total) s"
    }
}
