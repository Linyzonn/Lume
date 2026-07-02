import SwiftUI

struct RootView: View {
    @EnvironmentObject var engine: PlayerEngine
    @EnvironmentObject var library: LibraryStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var showNowPlaying = false

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView {
                LibraryView()
                    .tabItem { Label("Musique", systemImage: "music.note.list") }
                PlaylistsView()
                    .tabItem { Label("Playlists", systemImage: "square.stack") }
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
        // Import automatique des fichiers deposes via iTunes/Finder :
        // au lancement, puis a chaque retour au premier plan (ex. apres
        // une synchronisation iTunes pendant que l'app etait en fond).
        .task { await library.scanInbox() }
        .onChange(of: scenePhase) { phase in
            if phase == .active {
                Task { await library.scanInbox() }
            }
        }
    }
}
