import SwiftUI

struct RootView: View {
    @EnvironmentObject var engine: PlayerEngine
    @EnvironmentObject var library: LibraryStore
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("resumeOnLaunch") private var resumeOnLaunch = false
    @State private var showNowPlaying = false

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView {
                LibraryView()
                    .tabItem { Label("Musique", systemImage: "music.note.list") }
                PlaylistsView()
                    .tabItem { Label("Playlists", systemImage: "square.stack") }
                DiscoverView()
                    .tabItem { Label("Découvrir", systemImage: "sparkles") }
                SearchView()
                    .tabItem { Label("Recherche", systemImage: "magnifyingglass") }
                SettingsView()
                    .tabItem { Label("Réglages", systemImage: "gearshape") }
            }

            // Mini-lecteur flottant au-dessus de la barre d'onglets.
            if engine.currentTrack != nil {
                MiniPlayerView(onTap: { showNowPlaying = true })
                    .padding(.horizontal, 8)
                    .padding(.bottom, 49)   // hauteur de la tab bar
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: engine.currentTrack)
        .fullScreenCover(isPresented: $showNowPlaying) {
            NowPlayingView(isPresented: $showNowPlaying)
        }
        .task {
            // Cablage defensif : garantit que le moteur connait la bibliotheque
            // avant la reprise de session (l'ordre onAppear/task n'est pas garanti).
            engine.library = library
            // Branche la remontee des statistiques d'ecoute vers la bibliotheque.
            engine.onTrackCompleted = { [weak library] track in
                library?.recordPlay(track.id)
            }
            engine.onTrackSkipped = { [weak library] track in
                library?.recordSkip(track.id)
            }
            engine.onListenFlush = { [weak library] track, seconds in
                library?.recordListening(track.id, seconds: seconds)
            }
            // Reprise de la derniere session (option des Reglages), en pause.
            if resumeOnLaunch {
                engine.restoreSavedSessionIfNeeded()
            }
            // Import automatique des fichiers deposes via iTunes/Finder.
            await library.scanInbox()
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active {
                Task { await library.scanInbox() }
            } else if phase == .background {
                engine.persistSession()
                // Les stats sont sauvegardees en differe (5 s) : au passage
                // en arriere-plan, on force l'ecriture pour ne rien perdre.
                library.flushStatsNow()
            }
        }
    }
}
