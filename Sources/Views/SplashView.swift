import SwiftUI

// MARK: - Ecran d'accueil interne (raccord avec l'ecran de lancement)
//
// PROBLEME RESOLU : l'ecran de lancement systeme (fond sombre + glyphe) et le
// premier ecran de l'app (onglets, listes) ne se ressemblaient pas -> "saut"
// visuel au demarrage.
//
// SOLUTION : au premier rendu, l'app affiche par-dessus tout un ecran
// IDENTIQUE a l'ecran de lancement (meme couleur "LaunchBackground", meme
// asset "LaunchGlyph", meme position centree). Le systeme fond alors son
// ecran de lancement dans le notre sans aucune difference visible. Ensuite,
// le nom de l'app apparait sous le glyphe (moment d'identite), puis tout
// l'ecran se fond vers l'interface. Toucher l'icone -> lancement -> app
// forment desormais une seule sequence continue.
struct SplashView: View {
    var onFinished: () -> Void
    @State private var showWordmark = false

    var body: some View {
        ZStack {
            // Meme fond que l'ecran de lancement (asset LaunchBackground).
            Color("LaunchBackground")
                .ignoresSafeArea()

            // Meme glyphe, meme taille native, meme centrage que le systeme.
            // NE PAS lui ajouter de frame : le raccord doit etre pixel-perfect.
            Image("LaunchGlyph")

            // Le nom de l'app apparait APRES le raccord (il n'est pas sur
            // l'ecran de lancement systeme, il ne doit donc pas etre visible
            // a la premiere image).
            VStack(spacing: 4) {
                Text("Lume")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text("Ta musique, ta lumière.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.65))
            }
            .opacity(showWordmark ? 1 : 0)
            .offset(y: 132)
        }
        .task {
            withAnimation(.easeOut(duration: 0.35)) { showWordmark = true }
            // Assez long pour lire "Lume", assez court pour ne jamais gener.
            try? await Task.sleep(nanoseconds: 850_000_000)
            onFinished()
        }
        .accessibilityHidden(true)
    }
}
