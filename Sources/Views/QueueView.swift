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
                    // id par POSITION (offset) : la meme piste peut apparaitre
                    // deux fois dans la file (« Lire ensuite »), or ForEach
                    // exige des identifiants uniques.
                    ForEach(Array(upcoming.enumerated()), id: \.offset) { pair in
                        TrackRow(track: pair.element, context: engine.queue, showArtwork: true)
                    }
                    .onDelete { offsets in
                        let absolute = offsets.map { $0 + engine.queueIndex + 1 }
                        engine.removeFromQueue(atQueueIndices: absolute)
                    }
                    .onMove { from, to in
                        engine.moveUpcoming(from: from, to: to)
                    }
                }
            }
            .navigationTitle("File d'attente")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    HStack(spacing: 14) {
                        Image(systemName: "shuffle")
                            .foregroundStyle(engine.shuffleEnabled ? LumeTheme.accent : .secondary)
                            .onTapGesture { engine.shuffleEnabled.toggle() }
                            .accessibilityLabel("Lecture aléatoire")
                            .accessibilityAddTraits(.isButton)
                        Image(systemName: engine.repeatMode == .one ? "repeat.1" : "repeat")
                            .foregroundStyle(engine.repeatMode == .off ? .secondary : LumeTheme.accent)
                            .onTapGesture { cycleRepeat() }
                            .accessibilityLabel("Répétition")
                            .accessibilityAddTraits(.isButton)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 12) {
                        EditButton()
                        Button("Fermer") { dismiss() }
                    }
                }
            }
        }
    }

    private var upcomingTracks: [Track] {
        guard engine.queueIndex + 1 < engine.queue.count else { return [] }
        return Array(engine.queue[(engine.queueIndex + 1)...])
    }

    private func cycleRepeat() {
        switch engine.repeatMode {
        case .off: engine.repeatMode = .all
        case .all: engine.repeatMode = .one
        case .one: engine.repeatMode = .off
        }
    }
}
