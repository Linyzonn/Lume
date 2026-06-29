import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var engine: PlayerEngine
    @EnvironmentObject var library: LibraryStore
    @EnvironmentObject var sleepTimer: SleepTimer
    @State private var showSleepOptions = false

    var body: some View {
        NavigationStack {
            List {
                // Crossfade.
                Section {
                    Toggle("Activer le crossfade", isOn: Binding(
                        get: { engine.crossfadeDuration > 0 },
                        set: { engine.crossfadeDuration = $0 ? 6 : 0 }
                    ))
                    if engine.crossfadeDuration > 0 {
                        VStack(alignment: .leading) {
                            HStack {
                                Text("Durée")
                                Spacer()
                                Text("\(Int(engine.crossfadeDuration)) s")
                                    .foregroundStyle(.secondary)
                            }
                            Slider(value: $engine.crossfadeDuration, in: 1...12, step: 1)
                                .tint(LumeTheme.accent)
                        }
                    }
                } header: {
                    Text("Lecture")
                } footer: {
                    Text("Le crossfade fond la fin d'un morceau avec le début du suivant. Fonctionne en lecture séquentielle (pas en aléatoire).")
                }

                // Minuteur de sommeil.
                Section("Minuteur de sommeil") {
                    if sleepTimer.isActive {
                        HStack {
                            Image(systemName: "moon.zzz.fill").foregroundStyle(LumeTheme.accent)
                            if sleepTimer.stopAtEndOfTrack {
                                Text("Arrêt à la fin du morceau")
                            } else {
                                Text("Arrêt dans \(sleepTimer.remainingString)")
                                    .monospacedDigit()
                            }
                            Spacer()
                            Button("Annuler") { sleepTimer.cancel() }
                                .foregroundStyle(.red)
                        }
                    } else {
                        Button {
                            showSleepOptions = true
                        } label: {
                            Label("Programmer un minuteur", systemImage: "moon.zzz")
                        }
                    }
                }

                // Bibliotheque.
                Section("Bibliothèque") {
                    LabeledContent("Titres", value: "\(library.tracks.count)")
                    LabeledContent("Playlists", value: "\(library.playlists.count)")
                    LabeledContent("Favoris", value: "\(library.favorites.count)")
                }

                Section {
                    LabeledContent("Version", value: "1.0")
                } footer: {
                    Text("Lume — lecteur de musique local. Tes fichiers restent sur ton iPhone, aucune connexion requise.")
                }
            }
            .navigationTitle("Réglages")
            .confirmationDialog("Minuteur de sommeil", isPresented: $showSleepOptions, titleVisibility: .visible) {
                ForEach([10, 15, 30, 45, 60, 90], id: \.self) { minutes in
                    Button("\(minutes) minutes") { sleepTimer.start(minutes: minutes) }
                }
                Button("Fin du morceau en cours") { sleepTimer.start(minutes: 0, endOfTrack: true) }
                Button("Annuler", role: .cancel) { }
            }
            .safeAreaInset(edge: .bottom) {
                if engine.currentTrack != nil { Color.clear.frame(height: 64) }
            }
        }
    }
}
