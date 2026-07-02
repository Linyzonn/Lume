import SwiftUI

struct LyricsView: View {
    @EnvironmentObject var engine: PlayerEngine
    @EnvironmentObject var library: LibraryStore
    @Environment(\.dismiss) var dismiss

    @State private var isSearching = false
    @State private var searchFailed = false

    var body: some View {
        NavigationStack {
            Group {
                if let track = engine.currentTrack {
                    content(for: track)
                } else {
                    emptyState(message: "Aucun morceau en cours de lecture.")
                }
            }
            .navigationTitle(engine.currentTrack?.title ?? "Paroles")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    // Recherche (ou remplacement) des paroles en ligne.
                    if engine.currentTrack != nil {
                        Button {
                            searchOnline()
                        } label: {
                            if isSearching {
                                ProgressView()
                            } else {
                                Image(systemName: "magnifyingglass")
                            }
                        }
                        .disabled(isSearching)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fermer") { dismiss() }
                }
            }
        }
    }

    // MARK: - Contenu selon l'etat

    @ViewBuilder
    private func content(for track: Track) -> some View {
        if let raw = track.lyrics, !raw.isEmpty {
            if let lines = LRCParser.parse(raw) {
                SyncedLyricsView(lines: lines)
            } else {
                plainLyrics(raw)
            }
        } else {
            noLyricsState
        }
    }

    private func plainLyrics(_ text: String) -> some View {
        ScrollView {
            Text(text)
                .font(.title3)
                .lineSpacing(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
    }

    private var noLyricsState: some View {
        VStack(spacing: 14) {
            Image(systemName: "quote.bubble")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text("Pas de paroles pour ce titre")
                .font(.headline)
            Text("Recherche-les en ligne : si des paroles synchronisées existent, elles suivront la musique en direct.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button {
                searchOnline()
            } label: {
                if isSearching {
                    ProgressView().padding(.horizontal, 24)
                } else {
                    Label("Rechercher en ligne", systemImage: "magnifyingglass")
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(LumeTheme.accent)
            .disabled(isSearching)
            if searchFailed {
                Text("Paroles introuvables pour ce titre. Vérifie le titre et l'artiste (Réglages → Réanalyser peut aider), ou réessaie connecté à Internet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func emptyState(message: String) -> some View {
        Text(message)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Recherche en ligne

    private func searchOnline() {
        guard let track = engine.currentTrack, !isSearching else { return }
        isSearching = true
        searchFailed = false
        Task {
            defer { isSearching = false }
            // L'artiste principal (le premier) donne les meilleures correspondances.
            let mainArtist = track.artistList.first ?? track.artist
            do {
                let lyrics = try await LyricsFetcher.fetch(title: track.title,
                                                           artist: mainArtist,
                                                           duration: track.duration)
                library.setLyrics(lyrics, for: track)
                // Met aussi a jour le morceau en cours pour rafraichir l'affichage.
                if engine.currentTrack?.id == track.id {
                    engine.currentTrack?.lyrics = lyrics
                }
            } catch {
                searchFailed = true
            }
        }
    }
}

// MARK: - Paroles synchronisees (suivi en direct)

private struct SyncedLyricsView: View {
    let lines: [LyricLine]
    @EnvironmentObject var engine: PlayerEngine

    var body: some View {
        // engine.currentTime est publie 4x/seconde -> la ligne active suit la musique.
        let currentID = currentLineID
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    ForEach(lines) { line in
                        let isCurrent = line.id == currentID
                        Text(line.text.isEmpty ? "♪" : line.text)
                            .font(.title3.weight(isCurrent ? .bold : .medium))
                            .foregroundStyle(isCurrent ? AnyShapeStyle(LumeTheme.accent)
                                                       : AnyShapeStyle(Color.secondary))
                            .scaleEffect(isCurrent ? 1.04 : 1.0, anchor: .leading)
                            .animation(.easeInOut(duration: 0.25), value: isCurrent)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                // Toucher une ligne = s'y deplacer dans le morceau.
                                engine.seek(to: line.time)
                            }
                            .id(line.id)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 40)
            }
            .onChange(of: currentID) { newID in
                guard let newID else { return }
                withAnimation(.easeInOut(duration: 0.35)) {
                    proxy.scrollTo(newID, anchor: .center)
                }
            }
            .onAppear {
                if let currentID { proxy.scrollTo(currentID, anchor: .center) }
            }
        }
    }

    // Derniere ligne dont l'horodatage est deja passe.
    private var currentLineID: Int? {
        lines.last(where: { $0.time <= engine.currentTime })?.id
    }
}
