import SwiftUI

// Charte graphique simple, dans l'esprit iOS.
enum LumeTheme {
    static let accent = Color(red: 0.42, green: 0.36, blue: 0.92)   // violet doux
    static let accentSecondary = Color(red: 0.92, green: 0.36, blue: 0.62)
}

// Pochette d'album reutilisable. Affiche une jolie pochette par defaut si absente.
struct ArtworkView: View {
    let track: Track?
    var size: CGFloat = 56
    var corner: CGFloat = 8
    @EnvironmentObject var library: LibraryStore

    var body: some View {
        Group {
            if let track, let image = library.artworkImage(for: track) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
        )
    }

    private var placeholder: some View {
        ZStack {
            LinearGradient(colors: [LumeTheme.accent.opacity(0.7), LumeTheme.accentSecondary.opacity(0.7)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            Image(systemName: "music.note")
                .font(.system(size: size * 0.4, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
        }
    }
}

// Bouton de favori reutilisable.
struct FavoriteButton: View {
    let track: Track
    @EnvironmentObject var library: LibraryStore

    var body: some View {
        Button {
            library.toggleFavorite(track)
        } label: {
            Image(systemName: isFavorite ? "heart.fill" : "heart")
                .foregroundStyle(isFavorite ? LumeTheme.accentSecondary : .secondary)
        }
        .buttonStyle(.plain)
    }

    private var isFavorite: Bool {
        library.tracks.first(where: { $0.id == track.id })?.isFavorite ?? false
    }
}
