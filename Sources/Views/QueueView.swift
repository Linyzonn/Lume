import SwiftUI

struct QueueView: View {
    @EnvironmentObject var engine: PlayerEngine
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("En lecture") {
                    if let current = engine.currentTrack {
                        TrackRow(track: current, context: engine.queue)
                    }
                }
                Section("À suivre") {
                    let upcoming = upcomingTracks
                    if upcoming.isEmpty {
                        Text("Fin de la file.").foregroundStyle(.secondary)
                    }
                    ForEach(upcoming) { track in
                        TrackRow(track: track, context: engine.queue, showArtwork: true)
                    }
                }
            }
            .navigationTitle("File d'attente")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    HStack {
                        Image(systemName: "shuffle")
                            .foregroundStyle(engine.shuffleEnabled ? LumeTheme.accent : .secondary)
                            .onTapGesture { engine.shuffleEnabled.toggle() }
                        Image(systemName: engine.repeatMode == .one ? "repeat.1" : "repeat")
                            .foregroundStyle(engine.repeatMode == .off ? .secondary : LumeTheme.accent)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fermer") { dismiss() }
                }
            }
        }
    }

    private var upcomingTracks: [Track] {
        guard engine.queueIndex + 1 < engine.queue.count else { return [] }
        return Array(engine.queue[(engine.queueIndex + 1)...])
    }
}
