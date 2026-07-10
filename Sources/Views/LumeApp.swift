import SwiftUI

@main
struct LumeApp: App {
    @StateObject private var library = LibraryStore()
    @StateObject private var engine = PlayerEngine()
    @StateObject private var sleepTimer = SleepTimer()
    // Lire la couleur du theme ici force le re-rendu de toute la hierarchie
    // quand l'utilisateur change de palette dans les Reglages.
    @AppStorage("theme.accent") private var themeID = "violet"
    // Ecran d'accueil interne : prolonge l'ecran de lancement systeme
    // (voir SplashView) puis se fond vers l'interface.
    @State private var showSplash = true

    init() {
        // Cache HTTP plus genereux que celui par defaut : les pochettes de
        // Decouvrir (AsyncImage) et autres images distantes ne sont plus
        // re-telechargees a chaque visite de l'onglet.
        URLCache.shared = URLCache(memoryCapacity: 16 * 1024 * 1024,
                                   diskCapacity: 100 * 1024 * 1024)
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                RootView()
                    .environmentObject(library)
                    .environmentObject(engine)
                    .environmentObject(sleepTimer)
                    .tint(LumeTheme.accent)
                    .id(themeID)   // change de theme => reconstruit avec la nouvelle couleur

                if showSplash {
                    SplashView {
                        withAnimation(.easeInOut(duration: 0.45)) { showSplash = false }
                    }
                    .zIndex(10)
                    .transition(.opacity)
                }
            }
            .onAppear {
                engine.library = library
                sleepTimer.attach(engine)
                // Menage du cache d'API (entrees > 30 jours), hors du thread
                // principal pour ne pas ralentir le lancement.
                Task.detached(priority: .utility) { APICache.purgeStale() }
            }
            // « Ouvrir avec Lume » : un fichier audio partage depuis
            // Fichiers, Safari, Mail... arrive ici et est importe.
            .onOpenURL { url in
                Task { await library.importFiles([url]) }
            }
        }
    }
}
