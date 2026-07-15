import SwiftUI

struct PlaylistsView: View {
    @EnvironmentObject var library: LibraryStore
    @EnvironmentObject var engine: PlayerEngine
    @State private var showNewPlaylist = false
    @State private var newName = ""

    var body: some View {
        NavigationStack {
            List {
                smartSection
                userSection
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Playlists")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showNewPlaylist = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Nouvelle playlist")
                }
            }
            .alert("Nouvelle playlist", isPresented: $showNewPlaylist) {
                TextField("Nom", text: $newName)
                Button("Créer") {
                    let n = newName.trimmingCharacters(in: .whitespaces)
                    if !n.isEmpty { library.createPlaylist(name: n) }
                    newName = ""
                }
                Button("Annuler", role: .cancel) { newName = "" }
            }
            .safeAreaInset(edge: .bottom) {
                if engine.currentTrack != nil { Color.clear.frame(height: 64) }
            }
        }
    }

    // MARK: - Playlists intelligentes (calculees automatiquement)

    private struct SmartPlaylist: Identifiable {
        let id: String
        let name: String
        let icon: String
        let tracks: [Track]
    }

    private var smartPlaylists: [SmartPlaylist] {
        let now = Date()
        let stats = library.stats

        // Ajoutes ces 30 derniers jours.
        let recent = library.tracks
            .filter { now.timeIntervalSince($0.dateAdded) < 30 * 86400 }
            .sorted { $0.dateAdded > $1.dateAdded }

        // Jamais (vraiment) ecoutes.
        let neverPlayed = library.tracks.filter {
            let s = stats[$0.id]
            return (s?.plays ?? 0) == 0 && (s?.seconds ?? 0) < 30
        }

        // Les 25 plus ecoutes.
        let top = library.tracks
            .filter { (stats[$0.id]?.plays ?? 0) > 0 }
            .sorted { (stats[$0.id]?.plays ?? 0) > (stats[$1.id]?.plays ?? 0) }
            .prefix(25)

        // Aimes autrefois, pas reecoutes depuis 60 jours.
        let rediscover = library.tracks.filter {
            guard let s = stats[$0.id], s.plays > 0, let last = s.lastPlayed else { return false }
            return now.timeIntervalSince(last) > 60 * 86400
        }

        return [
            SmartPlaylist(id: "recent", name: "Ajoutés récemment", icon: "clock", tracks: recent),
            SmartPlaylist(id: "top", name: "Top 25", icon: "chart.line.uptrend.xyaxis", tracks: Array(top)),
            SmartPlaylist(id: "never", name: "Jamais écoutés", icon: "sparkles", tracks: neverPlayed),
            SmartPlaylist(id: "rediscover", name: "À redécouvrir", icon: "arrow.counterclockwise.heart", tracks: rediscover),
        ].filter { !$0.tracks.isEmpty }
    }

    @ViewBuilder
    private var smartSection: some View {
        let smart = smartPlaylists
        if !smart.isEmpty {
            Section {
                ForEach(smart) { pl in
                    NavigationLink {
                        CollectionDetailView(title: pl.name, tracks: pl.tracks)
                    } label: {
                        HStack(spacing: 12) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(LumeTheme.accentSecondary.gradient)
                                    .frame(width: 44, height: 44)
                                Image(systemName: pl.icon)
                                    .foregroundStyle(.white)
                            }
                            VStack(alignment: .leading) {
                                Text(pl.name).lineLimit(1)
                                Text("\(pl.tracks.count) titre\(pl.tracks.count > 1 ? "s" : "")")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            } header: {
                Text("Playlists intelligentes")
            } footer: {
                Text("Générées automatiquement à partir de tes écoutes, elles se mettent à jour toutes seules.")
            }
        }
    }

    // MARK: - Playlists de l'utilisateur

    @ViewBuilder
    private var userSection: some View {
        Section("Mes playlists") {
            if library.playlists.isEmpty {
                Text("Crée une playlist avec le bouton +, puis ajoute des titres depuis ta bibliothèque (appui long sur un morceau).")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            }
            ForEach(library.playlists) { pl in
                NavigationLink {
                    PlaylistDetailView(playlist: pl)
                } label: {
                    HStack(spacing: 12) {
                        PlaylistArtworkView(tracks: library.tracks(in: pl), size: 44)
                        VStack(alignment: .leading) {
                            Text(pl.name).lineLimit(1)
                            Text("\(pl.trackIDs.count) titre\(pl.trackIDs.count > 1 ? "s" : "")")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .swipeActions {
                    Button(role: .destructive) {
                        library.deletePlaylist(pl)
                    } label: { Label("Supprimer", systemImage: "trash") }
                }
            }
        }
    }
}

// Vignette d'une playlist : mosaique 2x2 des pochettes de ses premiers
// morceaux (repere visuel immediat), pochette unique s'il y en a moins de 4,
// icone generique si la playlist est vide.
struct PlaylistArtworkView: View {
    let tracks: [Track]
    var size: CGFloat = 44

    var body: some View {
        Group {
            if tracks.count >= 4 {
                let half = size / 2
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        ArtworkView(track: tracks[0], size: half, corner: 0)
                        ArtworkView(track: tracks[1], size: half, corner: 0)
                    }
                    HStack(spacing: 0) {
                        ArtworkView(track: tracks[2], size: half, corner: 0)
                        ArtworkView(track: tracks[3], size: half, corner: 0)
                    }
                }
            } else if let first = tracks.first {
                ArtworkView(track: first, size: size, corner: 0)
            } else {
                ZStack {
                    Rectangle().fill(LumeTheme.accent.gradient)
                    Image(systemName: "music.note.list")
                        .foregroundStyle(.white)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityHidden(true)
    }
}

struct PlaylistDetailView: View {
    let playlist: Playlist
    @EnvironmentObject var library: LibraryStore
    @EnvironmentObject var engine: PlayerEngine
    @State private var showShare = false

    private var tracks: [Track] { library.tracks(in: playlist) }

    var body: some View {
        List {
            if !tracks.isEmpty {
                Section {
                    Button {
                        engine.play(tracks: tracks, startAt: 0)
                    } label: { Label("Tout lire", systemImage: "play.fill") }
                    Button {
                        engine.shuffleEnabled = true
                        engine.play(tracks: tracks, startAt: Int.random(in: 0..<max(1, tracks.count)))
                    } label: { Label("Lecture aléatoire", systemImage: "shuffle") }
                }
            }
            Section {
                if tracks.isEmpty {
                    Text("Playlist vide. Ajoute des titres depuis l'onglet Musique (appui long sur un morceau → Ajouter à une playlist).")
                        .foregroundStyle(.secondary).font(.subheadline)
                }
                ForEach(tracks) { track in
                    TrackRow(track: track, context: tracks)
                        .swipeActions {
                            Button(role: .destructive) {
                                library.remove(track, from: playlist)
                            } label: { Label("Retirer", systemImage: "minus.circle") }
                        }
                }
                .onMove { from, to in
                    move(from: from, to: to)
                }
            }
        }
        .navigationTitle(playlist.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 12) {
                    // Partage des FICHIERS AUDIO de la playlist : AirDrop vers
                    // un Mac / autre iPhone, enregistrement dans Fichiers, etc.
                    // C'est la porte de sortie de ta musique hors de l'app.
                    if !tracks.isEmpty {
                        Button {
                            showShare = true
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .accessibilityLabel("Partager les fichiers de la playlist")
                    }
                    EditButton()
                }
            }
        }
        .sheet(isPresented: $showShare) {
            ShareSheet(items: tracks.map { library.url(for: $0) })
        }
    }

    private func move(from: IndexSet, to: Int) {
        guard let i = library.playlists.firstIndex(where: { $0.id == playlist.id }) else { return }
        library.playlists[i].trackIDs.move(fromOffsets: from, toOffset: to)
        library.save()
    }
}
