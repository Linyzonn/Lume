import SwiftUI
import UIKit

// Onglet « Découvrir » : recommandations personnalisees basees sur ton profil
// d'ecoute (voir RecommendationEngine). Chaque suggestion est ecoutable en
// extrait de 30 s si tu es connecte a Internet.
struct DiscoverView: View {
    @EnvironmentObject var library: LibraryStore
    @EnvironmentObject var engine: PlayerEngine
    @StateObject private var recommender = Recommender()
    @StateObject private var preview = PreviewPlayer()
    @State private var showWishlist = false

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
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showWishlist = true
                    } label: {
                        Label("Mes envies (\(library.wishlist.count))", systemImage: "bookmark.fill")
                            .labelStyle(.titleAndIcon)
                            .font(.subheadline)
                    }
                }
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
            .sheet(isPresented: $showWishlist) { WishlistSheet() }
        }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 6) {
                    if let summary = recommender.profileSummary {
                        HStack(spacing: 6) {
                            Image(systemName: "person.crop.circle.badge.checkmark")
                                .foregroundStyle(LumeTheme.accent)
                            Text("Ton profil : \(summary)")
                                .font(.footnote.weight(.semibold))
                        }
                    }
                    Text("Suggestions basées sur tes écoutes, favoris, morceaux passés, tempo et style. Touche une carte pour un extrait de 30 s, le marque-page pour la garder dans tes envies.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
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
                                                       isPlaying: preview.playingID == item.id,
                                                       isWished: library.isWished(item.id),
                                                       onPlayTap: {
                                        preview.toggle(item, mainEngine: engine)
                                    },
                                                       onWishTap: {
                                        library.toggleWish(WishItem(id: item.id,
                                                                    title: item.title,
                                                                    artist: item.artistName,
                                                                    coverURL: item.coverURL,
                                                                    linkURL: item.linkURL))
                                    })
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
    let isWished: Bool
    let onPlayTap: () -> Void
    let onWishTap: () -> Void

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

                // Marque-page "envie" (coin superieur droit).
                VStack {
                    HStack {
                        Spacer()
                        Button(action: onWishTap) {
                            Image(systemName: isWished ? "bookmark.fill" : "bookmark")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(isWished ? LumeTheme.accent : .white)
                                .padding(7)
                                .background(Circle().fill(.black.opacity(0.5)))
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                }
                .padding(6)
                .frame(width: 150, height: 150)
            }
            .onTapGesture { if item.previewURL != nil { onPlayTap() } }

            Text(item.title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
            Text(item.artistName)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            HStack(spacing: 6) {
                Text(item.reason)
                    .font(.caption2)
                    .foregroundStyle(LumeTheme.accent)
                    .lineLimit(1)
                if let bpm = item.bpm {
                    Text("\(Int(bpm)) BPM")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
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


// MARK: - Mes envies : titres a recuperer, reconnus automatiquement a l'import

struct WishlistSheet: View {
    @EnvironmentObject var library: LibraryStore
    @Environment(\.dismiss) var dismiss
    @State private var copiedID: Int?

    var body: some View {
        NavigationStack {
            List {
                if library.wishlist.isEmpty {
                    Text("Aucune envie pour l'instant. Dans Découvrir, touche le marque-page d'une suggestion pour la garder ici.")
                        .foregroundStyle(.secondary)
                }
                ForEach(library.wishlist) { wish in
                    HStack(spacing: 12) {
                        AsyncImage(url: wish.coverURL.flatMap { URL(string: $0) }) { phase in
                            if let image = phase.image {
                                image.resizable().scaledToFill()
                            } else {
                                Color.secondary.opacity(0.2)
                            }
                        }
                        .frame(width: 46, height: 46)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(wish.title).lineLimit(1)
                            Text(wish.artist)
                                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        Button {
                            UIPasteboard.general.string = "\(wish.artist) - \(wish.title)"
                            copiedID = wish.id
                        } label: {
                            Image(systemName: copiedID == wish.id ? "checkmark" : "doc.on.doc")
                                .foregroundStyle(copiedID == wish.id ? .green : LumeTheme.accent)
                        }
                        .buttonStyle(.plain)
                    }
                    .contextMenu {
                        if let link = wish.linkURL, let url = URL(string: link) {
                            Link(destination: url) {
                                Label("Ouvrir dans Deezer", systemImage: "arrow.up.right.square")
                            }
                        }
                        if let yt = youtubeURL(for: wish) {
                            Link(destination: yt) {
                                Label("Chercher sur YouTube", systemImage: "magnifyingglass")
                            }
                        }
                        Button(role: .destructive) {
                            library.removeWish(wish)
                        } label: { Label("Retirer", systemImage: "trash") }
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            library.removeWish(wish)
                        } label: { Label("Retirer", systemImage: "trash") }
                    }
                }
            }
            .navigationTitle("Mes envies")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fermer") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Text("💡 Le bouton copie « Artiste - Titre » pour ta recherche sur PC. Quand tu déposes le fichier via iTunes, il est reconnu automatiquement, retiré d'ici et rangé dans la playlist « Découvertes ».")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(.thinMaterial)
            }
        }
    }

    private func youtubeURL(for wish: WishItem) -> URL? {
        let q = "\(wish.artist) \(wish.title)"
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return URL(string: "https://www.youtube.com/results?search_query=\(q)")
    }
}
