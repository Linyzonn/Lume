import SwiftUI

// Charte graphique, dans l'esprit iOS.
// Le theme (couleur d'accent) est desormais choisi par l'utilisateur dans
// les Reglages parmi plusieurs palettes.
enum LumeTheme {
    struct Palette: Identifiable {
        let id: String
        let name: String
        let accent: Color
        let secondary: Color
    }

    static let palettes: [Palette] = [
        Palette(id: "violet", name: "Violet",
                accent: Color(red: 0.42, green: 0.36, blue: 0.92),
                secondary: Color(red: 0.92, green: 0.36, blue: 0.62)),
        Palette(id: "ocean", name: "Océan",
                accent: Color(red: 0.15, green: 0.50, blue: 0.95),
                secondary: Color(red: 0.20, green: 0.80, blue: 0.85)),
        Palette(id: "sunset", name: "Crépuscule",
                accent: Color(red: 0.95, green: 0.45, blue: 0.20),
                secondary: Color(red: 0.95, green: 0.25, blue: 0.45)),
        Palette(id: "forest", name: "Forêt",
                accent: Color(red: 0.16, green: 0.65, blue: 0.45),
                secondary: Color(red: 0.55, green: 0.80, blue: 0.30)),
        Palette(id: "cherry", name: "Cerise",
                accent: Color(red: 0.88, green: 0.20, blue: 0.35),
                secondary: Color(red: 0.98, green: 0.55, blue: 0.35)),
        Palette(id: "night", name: "Nuit",
                accent: Color(red: 0.55, green: 0.58, blue: 0.72),
                secondary: Color(red: 0.75, green: 0.78, blue: 0.90)),
    ]

    static var current: Palette {
        let id = UserDefaults.standard.string(forKey: "theme.accent") ?? "violet"
        return palettes.first { $0.id == id } ?? palettes[0]
    }

    static var accent: Color { current.accent }
    static var accentSecondary: Color { current.secondary }
}

// MARK: - Marque Lume reutilisable (rappel d'identite dans l'app)
//
// Petit glyphe (le meme que l'icone / l'ecran de lancement) accompagne du
// nom de l'app en style "rounded". Utilise dans les etats vides, l'ecran
// de chargement de Decouvrir et la section A propos : l'identite de Lume
// est presente aux moments cles sans envahir les listes.
struct LumeBrandMark: View {
    var glyphSize: CGFloat = 26
    var showName = true

    var body: some View {
        HStack(spacing: 8) {
            Image("LaunchGlyph")
                .resizable()
                .scaledToFit()
                .frame(width: glyphSize, height: glyphSize)
                .clipShape(RoundedRectangle(cornerRadius: glyphSize * 0.22, style: .continuous))
            if showName {
                Text("Lume")
                    .font(.system(size: glyphSize * 0.72, weight: .bold, design: .rounded))
                    .foregroundStyle(LumeTheme.accent)
            }
        }
        .accessibilityHidden(true)
    }
}

// Pochette d'album reutilisable. Affiche une jolie pochette par defaut si absente.
// La miniature est chargee EN ARRIERE-PLAN (et mise en cache) : sans cela,
// chaque ligne de liste relirait et decoderait le fichier image sur le thread
// principal, ce qui saccade le defilement.
struct ArtworkView: View {
    let track: Track?
    var size: CGFloat = 56
    var corner: CGFloat = 8
    @EnvironmentObject var library: LibraryStore
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            placeholder
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
        )
        .task(id: track?.artworkFileName) {
            guard let track, track.artworkFileName != nil else { image = nil; return }
            let target = size * UIScreen.main.scale
            let lib = library
            image = await Task.detached(priority: .userInitiated) {
                lib.thumbnail(for: track, pixelSize: target)
            }.value
        }
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
            Haptics.light()
            library.toggleFavorite(track)
        } label: {
            Image(systemName: isFavorite ? "heart.fill" : "heart")
                .foregroundStyle(isFavorite ? LumeTheme.accentSecondary : .secondary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isFavorite ? "Retirer des favoris" : "Ajouter aux favoris")
    }

    private var isFavorite: Bool {
        library.tracks.first(where: { $0.id == track.id })?.isFavorite ?? false
    }
}
