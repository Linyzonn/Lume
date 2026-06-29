import SwiftUI

struct SearchView: View {
    @EnvironmentObject var library: LibraryStore
    @EnvironmentObject var engine: PlayerEngine
    @State private var query = ""

    private var results: [Track] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return [] }
        return library.tracks.filter {
            $0.title.lowercased().contains(q) ||
            $0.artist.lowercased().contains(q) ||
            $0.album.lowercased().contains(q)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if query.isEmpty {
                    ContentUnavailableViewCompat(
                        title: "Rechercher",
                        systemImage: "magnifyingglass",
                        message: "Trouve un titre, un artiste ou un album."
                    )
                } else if results.isEmpty {
                    ContentUnavailableViewCompat(
                        title: "Aucun résultat",
                        systemImage: "magnifyingglass",
                        message: "Rien ne correspond à « \(query) »."
                    )
                } else {
                    List {
                        ForEach(results) { track in
                            TrackRow(track: track, context: results)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Recherche")
            .searchable(text: $query, prompt: "Titres, artistes, albums")
            .safeAreaInset(edge: .bottom) {
                if engine.currentTrack != nil { Color.clear.frame(height: 64) }
            }
        }
    }
}

// Petit equivalent de ContentUnavailableView compatible iOS 16.
struct ContentUnavailableViewCompat: View {
    let title: String
    let systemImage: String
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text(title).font(.title3.weight(.semibold))
            Text(message)
                .font(.subheadline).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).padding(.horizontal, 40)
        }
    }
}
