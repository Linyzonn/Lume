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
