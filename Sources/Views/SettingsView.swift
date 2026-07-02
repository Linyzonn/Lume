import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var engine: PlayerEngine
    @EnvironmentObject var library: LibraryStore
    @EnvironmentObject var sleepTimer: SleepTimer
    @State private var showSleepOptions = false
    @State private var duplicatesRemoved: Int?
    @State private var artworkFound: Int?
    @State private var artistPhotosFound: Int?
    @AppStorage("resumeOnLaunch") private var resumeOnLaunch = false

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
                Section {
                    LabeledContent("Titres", value: "\(library.tracks.count)")
                    LabeledContent("Playlists", value: "\(library.playlists.count)")
                    LabeledContent("Favoris", value: "\(library.favorites.count)")
                    Button {
                        Task { await library.reanalyzeMetadata() }
                    } label: {
                        if library.isImporting {
                            HStack(spacing: 10) {
                                ProgressView()
                                Text(library.importProgress.isEmpty ? "Analyse…" : library.importProgress)
                            }
                        } else {
                            Label("Réanalyser les métadonnées", systemImage: "arrow.clockwise")
                        }
                    }
                    .disabled(library.isImporting)
                    Button {
                        duplicatesRemoved = library.removeDuplicateTracks()
                    } label: {
                        Label("Nettoyer les doublons", systemImage: "doc.on.doc")
                    }
                    .disabled(library.isImporting)
                    Button {
                        Task { artworkFound = await library.fetchMissingArtwork() }
                    } label: {
                        Label("Récupérer les pochettes manquantes", systemImage: "photo.badge.arrow.down")
                    }
                    .disabled(library.isImporting)
                    Button {
                        Task { artistPhotosFound = await library.fetchAllArtistImages() }
                    } label: {
                        Label("Récupérer les photos d'artistes", systemImage: "person.crop.circle.badge.plus")
                    }
                    .disabled(library.isImporting)
                } header: {
                    Text("Bibliothèque")
                } footer: {
                    Text("Astuce : dépose des fichiers audio dans « Documents Lume » via iTunes/Finder, ils sont importés automatiquement à l'ouverture de l'app. « Nettoyer les doublons » fusionne les morceaux identiques (favoris, paroles et playlists sont conservés).")
                }

                // Reprise de session.
                Section {
                    Toggle(isOn: $resumeOnLaunch) {
                        Label("Reprendre où j'en étais", systemImage: "memories")
                    }
                } footer: {
                    Text("Au lancement, l'app recharge ta dernière file d'attente et ta position dans le morceau, en pause.")
                }

                // Statistiques.
                Section {
                    NavigationLink {
                        StatsView()
                    } label: {
                        Label("Statistiques d'écoute", systemImage: "chart.bar.fill")
                    }
                }

                Section {
                    LabeledContent("Version", value: "1.8 (v17)")
                } footer: {
                    Text("Lume — lecteur de musique local. Tes fichiers restent sur ton iPhone, aucune connexion requise.")
                }
            }
            .navigationTitle("Réglages")
            .alert("Nettoyage terminé", isPresented: Binding(
                get: { duplicatesRemoved != nil },
                set: { if !$0 { duplicatesRemoved = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text((duplicatesRemoved ?? 0) == 0
                     ? "Aucun doublon trouvé, ta bibliothèque est propre."
                     : "\(duplicatesRemoved ?? 0) doublon(s) supprimé(s).")
            }
            .alert("Pochettes", isPresented: Binding(
                get: { artworkFound != nil },
                set: { if !$0 { artworkFound = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("\(artworkFound ?? 0) pochette(s) trouvée(s) en ligne.")
            }
            .alert("Photos d'artistes", isPresented: Binding(
                get: { artistPhotosFound != nil },
                set: { if !$0 { artistPhotosFound = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("\(artistPhotosFound ?? 0) photo(s) d'artiste trouvée(s).")
            }
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
