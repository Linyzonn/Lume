import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @EnvironmentObject var library: LibraryStore
    @EnvironmentObject var engine: PlayerEngine

    enum Tab: String, CaseIterable { case songs = "Titres", albums = "Albums", artists = "Artistes", favorites = "Favoris" }
    @State private var tab: Tab = .songs
    @State private var showImporter = false
    @State private var trackForPlaylist: Track?

    var body: some View {
        NavigationStack {
            Group {
                if library.tracks.isEmpty {
                    emptyState
                } else {
                    content
                }
            }
            .navigationTitle("Lume")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if !library.tracks.isEmpty {
                        Button {
                            shufflePlayAll()
                        } label: {
                            Image(systemName: "shuffle")
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showImporter = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                    }
                }
            }
            .fileImporter(isPresented: $showImporter,
                          allowedContentTypes: audioTypes,
                          allowsMultipleSelection: true) { result in
                if case .success(let urls) = result {
                    Task { await library.importFiles(urls) }
                }
            }
            .sheet(item: $trackForPlaylist) { track in
                AddToPlaylistSheet(track: track)
            }
            .overlay {
                if library.isImporting {
                    importingOverlay
                }
            }
            .safeAreaInset(edge: .bottom) {
                // Espace pour ne pas masquer la derniere ligne sous le mini-lecteur.
                if engine.currentTrack != nil { Color.clear.frame(height: 64) }
            }
        }
    }

    // MARK: - Contenu principal

    private var content: some View {
        VStack(spacing: 0) {
            Picker("", selection: $tab) {
                ForEach(Tab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.bottom, 8)

            switch tab {
            case .songs:     songsList(library.tracks)
            case .favorites: songsList(library.favorites)
            case .albums:    albumsList
            case .artists:   artistsList
            }
        }
    }

    private func songsList(_ tracks: [Track]) -> some View {
        List {
            if tracks.isEmpty {
                Text(tab == .favorites ? "Aucun favori pour l'instant." : "Aucun titre.")
                    .foregroundStyle(.secondary)
            }
            ForEach(tracks) { track in
                TrackRow(track: track, context: tracks)
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            library.delete(track)
                        } label: { Label("Supprimer", systemImage: "trash") }
                    }
                    .swipeActions(edge: .leading) {
                        Button {
                            library.toggleFavorite(track)
                        } label: { Label("Favori", systemImage: "heart") }
                        .tint(LumeTheme.accentSecondary)
                    }
                    .contextMenu {
                        trackMenu(track)
                    }
            }
        }
        .listStyle(.plain)
    }

    private var albumsList: some View {
        List {
            ForEach(library.albums.keys.sorted(), id: \.self) { album in
                let albumTracks = library.albums[album] ?? []
                NavigationLink {
                    CollectionDetailView(title: album, tracks: albumTracks)
                } label: {
                    HStack(spacing: 12) {
                        ArtworkView(track: albumTracks.first, size: 52, corner: 6)
                        VStack(alignment: .leading) {
                            Text(album).lineLimit(1)
                            Text("\(albumTracks.count) titre\(albumTracks.count > 1 ? "s" : "")")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
    }

    private var artistsList: some View {
        List {
            ForEach(library.artists.keys.sorted(), id: \.self) { artist in
                let artistTracks = library.artists[artist] ?? []
                NavigationLink {
                    CollectionDetailView(title: artist, tracks: artistTracks)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "person.crop.circle.fill")
                            .font(.system(size: 40))
                            .foregroundStyle(LumeTheme.accent.gradient)
                        VStack(alignment: .leading) {
                            Text(artist).lineLimit(1)
                            Text("\(artistTracks.count) titre\(artistTracks.count > 1 ? "s" : "")")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
    }

    @ViewBuilder
    private func trackMenu(_ track: Track) -> some View {
        Button {
            engine.playSingle(track, in: library.tracks)
        } label: { Label("Lire", systemImage: "play") }
        Button {
            trackForPlaylist = track
        } label: { Label("Ajouter à une playlist", systemImage: "text.badge.plus") }
        Button {
            library.toggleFavorite(track)
        } label: { Label("Favori", systemImage: "heart") }
        Button(role: .destructive) {
            library.delete(track)
        } label: { Label("Supprimer", systemImage: "trash") }
    }

    // MARK: - Etats

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "music.note.house.fill")
                .font(.system(size: 56))
                .foregroundStyle(LumeTheme.accent.gradient)
            Text("Ta bibliothèque est vide")
                .font(.title3.weight(.semibold))
            Text("Touche le bouton + en haut à droite pour importer tes fichiers audio (MP3, M4A, FLAC, WAV…) depuis l'app Fichiers.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button {
                showImporter = true
            } label: {
                Label("Importer de la musique", systemImage: "plus.circle.fill")
                    .font(.headline)
                    .padding(.horizontal, 20).padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 4)
        }
    }

    private var importingOverlay: some View {
        ZStack {
            Color.black.opacity(0.25).ignoresSafeArea()
            VStack(spacing: 12) {
                ProgressView()
                Text(library.importProgress.isEmpty ? "Import en cours…" : library.importProgress)
                    .font(.subheadline)
            }
            .padding(24)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        }
    }

    // MARK: - Actions

    private func shufflePlayAll() {
        guard !library.tracks.isEmpty else { return }
        engine.shuffleEnabled = true
        let start = Int.random(in: 0..<library.tracks.count)
        engine.play(tracks: library.tracks, startAt: start)
    }

    private var audioTypes: [UTType] {
        [.audio, .mp3, .mpeg4Audio, .wav, .aiff]
    }
}

// Detail d'un album ou d'un artiste.
struct CollectionDetailView: View {
    let title: String
    let tracks: [Track]
    @EnvironmentObject var engine: PlayerEngine

    var body: some View {
        List {
            Section {
                Button {
                    engine.play(tracks: tracks, startAt: 0)
                } label: {
                    Label("Tout lire", systemImage: "play.fill")
                }
                Button {
                    engine.shuffleEnabled = true
                    engine.play(tracks: tracks, startAt: Int.random(in: 0..<max(1, tracks.count)))
                } label: {
                    Label("Lecture aléatoire", systemImage: "shuffle")
                }
            }
            Section {
                ForEach(tracks) { track in
                    TrackRow(track: track, context: tracks)
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
