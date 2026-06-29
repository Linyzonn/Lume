import SwiftUI

struct PlaylistsView: View {
    @EnvironmentObject var library: LibraryStore
    @EnvironmentObject var engine: PlayerEngine
    @State private var showNewPlaylist = false
    @State private var newName = ""

    var body: some View {
        NavigationStack {
            Group {
                if library.playlists.isEmpty {
                    emptyState
                } else {
                    List {
                        ForEach(library.playlists) { pl in
                            NavigationLink {
                                PlaylistDetailView(playlist: pl)
                            } label: {
                                HStack(spacing: 12) {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .fill(LumeTheme.accent.gradient)
                                            .frame(width: 52, height: 52)
                                        Image(systemName: "music.note.list")
                                            .foregroundStyle(.white)
                                    }
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
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Playlists")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showNewPlaylist = true } label: { Image(systemName: "plus") }
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

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "square.stack.3d.up")
                .font(.system(size: 50))
                .foregroundStyle(LumeTheme.accent.gradient)
            Text("Aucune playlist")
                .font(.title3.weight(.semibold))
            Text("Crée une playlist avec le bouton +, puis ajoute des titres depuis ta bibliothèque.")
                .font(.subheadline).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).padding(.horizontal, 32)
        }
    }
}

struct PlaylistDetailView: View {
    let playlist: Playlist
    @EnvironmentObject var library: LibraryStore
    @EnvironmentObject var engine: PlayerEngine

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
        .toolbar { EditButton() }
    }

    private func move(from: IndexSet, to: Int) {
        guard let i = library.playlists.firstIndex(where: { $0.id == playlist.id }) else { return }
        library.playlists[i].trackIDs.move(fromOffsets: from, toOffset: to)
        library.save()
    }
}
