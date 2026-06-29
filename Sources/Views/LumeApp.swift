import SwiftUI

@main
struct LumeApp: App {
    @StateObject private var library = LibraryStore()
    @StateObject private var engine = PlayerEngine()
    @StateObject private var sleepTimer = SleepTimer()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(library)
                .environmentObject(engine)
                .environmentObject(sleepTimer)
                .tint(LumeTheme.accent)
                .onAppear {
                    engine.library = library
                    sleepTimer.attach(engine)
                }
        }
    }
}
