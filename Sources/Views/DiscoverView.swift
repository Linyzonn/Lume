import SwiftUI

// Onglet « Découvrir » : recommandations personnalisees basees sur ton profil
// d'ecoute (voir RecommendationEngine). Chaque suggestion est ecoutable en
// extrait de 30 s si tu es connecte a Internet.
struct DiscoverView: View {
    @EnvironmentObject var library: LibraryStore
    @EnvironmentObject var engine: PlayerEngine
    @StateObject private var recommender = Recommender()
    @StateObject private var preview = PreviewPlayer()

    var body: some View {
        NavigationStack {
            Group {
                if recommender.isLoading && recommender.sections.isEmpty {
                    loadingState
                } else if let message = recommender.message, recommender.sections.isEmpty {
                    emptyState(message)
                } else {
                    content
                }
            }
            .navigationTitle("Découvrir")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await recommender.refresh(library: library, force: true) }
                    } label: {
                        if recommender.isLoading {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .disabled(recommender.isLoading)
                }
            }
            .task { await recommender.refresh(library: library) }
            .onDisappear { preview.stop() }
        }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                Text("Suggestions basées sur tes écoutes, tes favoris et les titres que tu passes. Touche une carte pour un extrait de 30 s.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)

                ForEach(recommender.sections) { section in
                    VStack(alignment: .leading, spacing: 12) {
                        Text(section.title)
                            .font(.title3.weight(.bold))
                            .padding(.horizontal)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 14) {
                                ForEach(section.items) { item in
                                    RecommendationCard(item: item,
                                                       isPlaying: preview.playingID == item.id) {
                                        preview.toggle(item, mainEngine: engine)
                                    }
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                }
            }
            .padding(.vertical)
            .padding(.bottom, 70)   // espace pour le mini-lecteur
        }
        .refreshable { await recommender.refresh(library: library, force: true) }
    }

    private var loadingState: some View {
        VStack(spacing: 14) {
            ProgressView()
            Text("Analyse de ton profil musical…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func emptyState(_ message: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "sparkles")
                .font(.system(size: 44))
                .foregroundStyle(LumeTheme.accent.gradient)
            Text("Rien à te proposer pour l'instant")
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("Réessayer") {
                Task { await recommender.refresh(library: library, force: true) }
            }
            .buttonStyle(.borderedProminent)
            .tint(LumeTheme.accent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// Carte d'une suggestion : pochette + extrait + menu d'actions.
private struct RecommendationCard: View {
    let item: Recommendation
    let isPlaying: Bool
    let onPlayTap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                AsyncImage(url: item.coverURL.flatMap { URL(string: $0) }) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        LinearGradient(colors: [LumeTheme.accent.opacity(0.6),
                                                LumeTheme.accentSecondary.opacity(0.6)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                        Image(systemName: "music.note")
                            .font(.largeTitle)
                            .foregroundStyle(.white.opacity(0.8))
                    }
                }
                .frame(width: 150, height: 150)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                // Bouton extrait 30 s.
                if item.previewURL != nil {
                    Circle()
                        .fill(.black.opacity(0.55))
                        .frame(width: 46, height: 46)
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.title3)
                        .foregroundStyle(.white)
                }
            }
            .onTapGesture { if item.previewURL != nil { onPlayTap() } }

            Text(item.title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
            Text(item.artistName)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(item.reason)
                .font(.caption2)
                .foregroundStyle(LumeTheme.accent)
                .lineLimit(1)
        }
        .frame(width: 150)
        .contextMenu {
            if let link = item.linkURL, let url = URL(string: link) {
                Link(destination: url) {
                    Label("Ouvrir dans Deezer", systemImage: "arrow.up.right.square")
                }
            }
            if let ytURL = youtubeSearchURL {
                Link(destination: ytURL) {
                    Label("Chercher sur YouTube", systemImage: "magnifyingglass")
                }
            }
        }
    }

    private var youtubeSearchURL: URL? {
        let q = "\(item.artistName) \(item.title)"
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return URL(string: "https://www.youtube.com/results?search_query=\(q)")
    }
}
