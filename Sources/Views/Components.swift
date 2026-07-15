import SwiftUI

// Ligne d'un morceau dans une liste.
struct TrackRow: View {
    let track: Track
    var context: [Track]                 // file de lecture si on tape dessus
    var showArtwork = true
    @EnvironmentObject var engine: PlayerEngine

    var body: some View {
        HStack(spacing: 12) {
            if showArtwork {
                ArtworkView(track: track, size: 48, corner: 6)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(track.title)
                    .font(.body)
                    .foregroundStyle(isCurrent ? LumeTheme.accent : .primary)
                    .lineLimit(1)
                Text(track.artist)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            if isCurrent && engine.isPlaying {
                Image(systemName: "waveform")
                    .foregroundStyle(LumeTheme.accent)
            }
            Text(track.duration.asTimeString)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            engine.playSingle(track, in: context)
        }
        // VoiceOver : la ligne entiere est UN element actionnable, lu
        // naturellement (titre, artiste, duree) au lieu de 3 fragments.
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(track.title), \(track.artist), \(track.duration.asTimeString)\(isCurrent ? ", en cours de lecture" : "")")
        .accessibilityHint("Lance la lecture")
        .accessibilityAddTraits(.isButton)
    }

    private var isCurrent: Bool { engine.currentTrack?.id == track.id }
}

// Feuille « Ajouter a une playlist ».
struct AddToPlaylistSheet: View {
    let track: Track
    @EnvironmentObject var library: LibraryStore
    @Environment(\.dismiss) var dismiss
    @State private var newName = ""

    var body: some View {
        NavigationStack {
            List {
                Section("Nouvelle playlist") {
                    HStack {
                        TextField("Nom de la playlist", text: $newName)
                        Button("Créer") {
                            guard !newName.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                            library.createPlaylist(name: newName)
                            if let pl = library.playlists.last {
                                library.add(track, to: pl)
                            }
                            dismiss()
                        }
                        .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
                if !library.playlists.isEmpty {
                    Section("Mes playlists") {
                        ForEach(library.playlists) { pl in
                            Button {
                                library.add(track, to: pl)
                                dismiss()
                            } label: {
                                HStack {
                                    Image(systemName: "music.note.list")
                                    Text(pl.name)
                                    Spacer()
                                    Text("\(pl.trackIDs.count)")
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Ajouter à…")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Photo d'artiste (ronde, chargee en arriere-plan, cache)

struct ArtistAvatarView: View {
    let name: String
    var size: CGFloat = 44
    @EnvironmentObject var library: LibraryStore
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Circle().fill(LumeTheme.accent.gradient.opacity(0.8))
                Image(systemName: "music.mic")
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        // Recharge quand une photo est telechargee (artistImagesVersion bouge).
        .task(id: "\(name)#\(library.artistImagesVersion)") {
            let target = size * UIScreen.main.scale
            let lib = library
            let n = name
            image = await Task.detached(priority: .userInitiated) {
                lib.artistImage(named: n, pixelSize: target)
            }.value
        }
    }
}

// MARK: - Edition manuelle des metadonnees d'un morceau

struct EditTrackSheet: View {
    let track: Track
    @EnvironmentObject var library: LibraryStore
    @Environment(\.dismiss) var dismiss

    @State private var title = ""
    @State private var artist = ""
    @State private var album = ""
    @State private var fetchingArtwork = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Titre") {
                    TextField("Titre du morceau", text: $title)
                }
                Section {
                    TextField("Artiste(s)", text: $artist)
                } header: {
                    Text("Artiste")
                } footer: {
                    Text("Sépare plusieurs artistes par des virgules : chacun aura son dossier dans l'onglet Artistes.")
                }
                Section("Album") {
                    TextField("Album", text: $album)
                }
                Section {
                    Button {
                        fetchingArtwork = true
                        Task {
                            await library.fetchArtworkOnline(for: track)
                            fetchingArtwork = false
                        }
                    } label: {
                        if fetchingArtwork {
                            HStack(spacing: 10) { ProgressView(); Text("Recherche…") }
                        } else {
                            Label("Chercher la pochette en ligne", systemImage: "photo.badge.arrow.down")
                        }
                    }
                    .disabled(fetchingArtwork)
                }
            }
            .navigationTitle("Modifier les infos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") {
                        library.updateMetadata(for: track, title: title, artist: artist, album: album)
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                title = track.title
                artist = track.artist
                album = track.album
            }
        }
    }
}

// MARK: - Dossier d'un artiste (ouvert depuis le lecteur)

struct ArtistTracksSheet: View {
    let artistName: String
    @EnvironmentObject var library: LibraryStore
    @EnvironmentObject var engine: PlayerEngine
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            List {
                let artistTracks = library.tracks(forArtist: artistName)
                Section {
                    HStack(spacing: 14) {
                        ArtistAvatarView(name: artistName, size: 64)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(artistName).font(.title3.weight(.bold))
                            Text("\(artistTracks.count) titre\(artistTracks.count > 1 ? "s" : "")")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button {
                            engine.play(tracks: artistTracks, startAt: 0)
                        } label: {
                            Image(systemName: "play.circle.fill")
                                .font(.system(size: 40))
                                .foregroundStyle(LumeTheme.accent)
                        }
                        .buttonStyle(.plain)
                        .disabled(artistTracks.isEmpty)
                    }
                    .padding(.vertical, 4)
                }
                Section {
                    ForEach(artistTracks) { track in
                        TrackRow(track: track, context: artistTracks)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(artistName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fermer") { dismiss() }
                }
            }
            .task { await library.fetchArtistImage(for: artistName) }
        }
    }
}

// MARK: - Feuille de partage systeme (fichiers, texte, URLs)

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
