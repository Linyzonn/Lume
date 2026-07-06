import Foundation
import AppIntents

// MARK: - Siri & Raccourcis (AppIntents, iOS 16+)
//
// Ces intents rendent Lume pilotable par Siri, l'app Raccourcis et la
// recherche Spotlight, SANS extension separee : ils vivent dans l'app.
//  - Lancer de la musique ouvre l'app (openAppWhenRun) : iOS interdit de
//    demarrer une session audio depuis le fond, donc on passe au premier plan.
//  - Pause / Suivant agissent en arriere-plan si la musique joue deja.
//
// Exemples : « Dis Siri, lire mes favoris dans Lume »,
//            « Dis Siri, lecture aléatoire dans Lume ».

// Attend que le moteur et la bibliotheque soient prets (l'intent peut
// s'executer une fraction de seconde avant le premier rendu SwiftUI).
@MainActor
private func waitForApp() async -> (PlayerEngine, LibraryStore)? {
    var tries = 0
    while tries < 30 {
        if let engine = PlayerEngine.shared, let library = LibraryStore.shared,
           engine.library != nil {
            return (engine, library)
        }
        try? await Task.sleep(nanoseconds: 100_000_000)
        tries += 1
    }
    return nil
}

struct PlayFavoritesIntent: AppIntent {
    static var title: LocalizedStringResource = "Lire mes favoris"
    static var description = IntentDescription("Lance tes morceaux favoris en aléatoire dans Lume.")
    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let (engine, library) = await waitForApp() else { return .result() }
        let favorites = library.favorites
        guard !favorites.isEmpty else { return .result() }
        engine.shuffleEnabled = true
        engine.play(tracks: favorites, startAt: Int.random(in: 0..<favorites.count))
        return .result()
    }
}

struct ShufflePlayIntent: AppIntent {
    static var title: LocalizedStringResource = "Lecture aléatoire"
    static var description = IntentDescription("Lance toute ta bibliothèque en aléatoire dans Lume.")
    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let (engine, library) = await waitForApp() else { return .result() }
        let tracks = library.tracks
        guard !tracks.isEmpty else { return .result() }
        engine.shuffleEnabled = true
        engine.play(tracks: tracks, startAt: Int.random(in: 0..<tracks.count))
        return .result()
    }
}

struct TogglePlaybackIntent: AppIntent {
    static var title: LocalizedStringResource = "Lecture / pause"
    static var description = IntentDescription("Met en pause ou reprend la lecture de Lume.")
    static var openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let engine = PlayerEngine.shared, engine.currentTrack != nil else { return .result() }
        engine.togglePlayPause()
        return .result()
    }
}

struct NextTrackIntent: AppIntent {
    static var title: LocalizedStringResource = "Morceau suivant"
    static var description = IntentDescription("Passe au morceau suivant dans Lume.")
    static var openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let engine = PlayerEngine.shared, engine.currentTrack != nil else { return .result() }
        engine.next()
        return .result()
    }
}

// Phrases proposees a Siri et affichees dans l'app Raccourcis.
struct LumeShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: PlayFavoritesIntent(),
                    phrases: [
                        "Lire mes favoris dans \(.applicationName)",
                        "Lance mes favoris dans \(.applicationName)",
                        "Mes favoris dans \(.applicationName)"
                    ])
        AppShortcut(intent: ShufflePlayIntent(),
                    phrases: [
                        "Lecture aléatoire dans \(.applicationName)",
                        "Mets de la musique dans \(.applicationName)",
                        "Lance de la musique dans \(.applicationName)"
                    ])
        AppShortcut(intent: TogglePlaybackIntent(),
                    phrases: [
                        "Pause dans \(.applicationName)",
                        "Mets pause dans \(.applicationName)"
                    ])
        AppShortcut(intent: NextTrackIntent(),
                    phrases: [
                        "Morceau suivant dans \(.applicationName)",
                        "Chanson suivante dans \(.applicationName)"
                    ])
    }
}
