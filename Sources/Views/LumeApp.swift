import SwiftUI

@main
struct LumeApp: App {
    @StateObject private var library = LibraryStore()
    @StateObject private var engine = PlayerEngine()
    @StateObject private var sleepTimer = SleepTimer()
    // Lire la couleur du theme ici force le re-rendu de toute la hierarchie
    // quand l'utilisateur change de palette dans les Reglages.
    @AppStorage("theme.accent") private var themeID = "violet"

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(library)
                .environmentObject(engine)
                .environmentObject(sleepTimer)
                .tint(LumeTheme.accent)
                .id(themeID)   // change de theme => reconstruit avec la nouvelle couleur
                .onAppear {
                    engine.library = library
                    sleepTimer.attach(engine)
                }
                // « Ouvrir avec Lume » : un fichier audio partage depuis
                // Fichiers, Safari, Mail... arrive ici et est importe.
                .onOpenURL { url in
                    Task { await library.importFiles([url]) }
                }
        }
    }
}
