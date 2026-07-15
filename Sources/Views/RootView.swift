import SwiftUI

struct RootView: View {
    @EnvironmentObject var engine: PlayerEngine
    @EnvironmentObject var library: LibraryStore
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("resumeOnLaunch") private var resumeOnLaunch = false
    // Onglet actif MEMORISE : changer de theme reconstruit la hierarchie
    // (.id(themeID) dans LumeApp) et renvoyait brutalement sur « Musique ».
    @AppStorage("ui.selectedTab") private var selectedTab = 0
    @State private var showNowPlaying = false

    // Hauteur standard de la tab bar iPhone en portrait.
    private let tabBarHeight: CGFloat = 49

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $selectedTab) {
                LibraryView()
                    .tabItem { Label("Musique", systemImage: "music.note.list") }
                    .tag(0)
                PlaylistsView()
                    .tabItem { Label("Playlists", systemImage: "square.stack") }
                    .tag(1)
                DiscoverView()
                    .tabItem { Label("Découvrir", systemImage: "sparkles") }
                    .tag(2)
                SearchView()
                    .tabItem { Label("Recherche", systemImage: "magnifyingglass") }
                    .tag(3)
                SettingsView()
                    .tabItem { Label("Réglages", systemImage: "gearshape") }
                    .tag(4)
            }

            // Mini-lecteur flottant au-dessus de la barre d'onglets.
            if engine.currentTrack != nil {
                MiniPlayerView(onTap: { showNowPlaying = true })
                    .padding(.horizontal, 8)
                    .padding(.bottom, tabBarHeight)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: engine.currentTrack)
        .fullScreenCover(isPresented: $showNowPlaying) {
            NowPlayingView(isPresented: $showNowPlaying)
        }
        // Echec d'ecriture sur disque (disque plein...) : signale ici, au
        // niveau racine, pour etre visible quel que soit l'onglet actif.
        .alert("Problème d'enregistrement", isPresented: Binding(
            get: { library.persistenceError != nil },
            set: { if !$0 { library.persistenceError = nil } }
        )) {
            Button("OK", role: .cancel) { library.persistenceError = nil }
        } message: {
            Text(library.persistenceError ?? "")
        }
        // Lecture impossible (session audio refusee, ex. appel en cours) :
        // avant, l'app restait simplement en pause sans explication.
        .alert("Lecture impossible", isPresented: Binding(
            get: { engine.playbackIssue != nil },
            set: { if !$0 { engine.playbackIssue = nil } }
        )) {
            Button("OK", role: .cancel) { engine.playbackIssue = nil }
        } message: {
            Text(engine.playbackIssue ?? "")
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
            // Suppression d'un morceau : le moteur le retire de la file
            // (et passe au suivant s'il etait en lecture).
            library.onTrackDeleted = { [weak engine] id in
                engine?.handleTrackDeleted(id)
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
