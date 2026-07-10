import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject var engine: PlayerEngine
    @EnvironmentObject var library: LibraryStore
    @EnvironmentObject var sleepTimer: SleepTimer
    @StateObject private var wifiServer = WiFiImportServer()

    @State private var showSleepOptions = false
    @State private var duplicatesRemoved: Int?
    @State private var artworkFound: Int?
    @State private var artistPhotosFound: Int?
    @State private var backupURL: URL?
    @State private var showRestoreImporter = false
    @State private var restoredCount: Int?
    @AppStorage("resumeOnLaunch") private var resumeOnLaunch = false
    @AppStorage("theme.accent") private var themeID = "violet"

    var body: some View {
        NavigationStack {
            List {
                importSection
                playbackSection
                sleepSection
                librarySection
                backupSection
                resumeSection
                appearanceSection
                statsSection
                aboutSection
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
            .alert("Restauration terminée", isPresented: Binding(
                get: { restoredCount != nil },
                set: { if !$0 { restoredCount = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("\(restoredCount ?? 0) morceau(x) relié(s) : favoris, playlists, paroles et statistiques ont été fusionnés.")
            }
            .confirmationDialog("Minuteur de sommeil", isPresented: $showSleepOptions, titleVisibility: .visible) {
                ForEach([10, 15, 30, 45, 60, 90], id: \.self) { minutes in
                    Button("\(minutes) minutes") { sleepTimer.start(minutes: minutes) }
                }
                Button("Fin du morceau en cours") { sleepTimer.start(minutes: 0, endOfTrack: true) }
                Button("Annuler", role: .cancel) { }
            }
            .sheet(item: Binding(
                get: { backupURL.map { ShareableURL(url: $0) } },
                set: { if $0 == nil { backupURL = nil } }
            )) { item in
                ShareSheet(items: [item.url])
            }
            .fileImporter(isPresented: $showRestoreImporter,
                          allowedContentTypes: [.json],
                          allowsMultipleSelection: false) { result in
                if case .success(let urls) = result, let url = urls.first {
                    restoredCount = library.restoreBackup(from: url)
                }
            }
            .safeAreaInset(edge: .bottom) {
                if engine.currentTrack != nil { Color.clear.frame(height: 64) }
            }
        }
    }

    private struct ShareableURL: Identifiable {
        let url: URL
        var id: String { url.absoluteString }
    }

    // MARK: - Import Wi-Fi

    private var importSection: some View {
        Section {
            Toggle(isOn: Binding(
                get: { wifiServer.isRunning },
                set: { on in
                    if on { wifiServer.start(library: library) } else { wifiServer.stop() }
                }
            )) {
                Label("Import Wi-Fi", systemImage: "wifi")
            }
            if wifiServer.isRunning {
                if let address = wifiServer.address {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Sur ton ordinateur (même Wi-Fi), ouvre :")
                            .font(.subheadline)
                        Text(address)
                            .font(.title3.weight(.bold).monospaced())
                            .foregroundStyle(LumeTheme.accent)
                            .textSelection(.enabled)
                        if !wifiServer.pairingCode.isEmpty {
                            HStack(spacing: 8) {
                                Text("Code :")
                                    .font(.subheadline)
                                Text(wifiServer.pairingCode)
                                    .font(.title3.weight(.bold).monospaced())
                                    .foregroundStyle(LumeTheme.accentSecondary)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                    .padding(.vertical, 2)
                } else {
                    Text("Connecte l'iPhone au Wi-Fi pour obtenir une adresse.")
                        .foregroundStyle(.secondary)
                }
                if wifiServer.receivedCount > 0 {
                    LabeledContent("Fichiers reçus", value: "\(wifiServer.receivedCount)")
                }
            }
        } header: {
            Text("Importer depuis un ordinateur")
        } footer: {
            Text("Glisse tes fichiers audio dans la page web qui s'ouvre : ils arrivent directement dans Lume, sans câble ni iTunes. Le code à 4 chiffres protège l'envoi : seul quelqu'un qui le voit sur ton écran peut t'envoyer des fichiers. Garde l'app ouverte pendant le transfert.")
        }
    }

    // MARK: - Lecture

    private var playbackSection: some View {
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
            Text("Le crossfade fond la fin d'un morceau avec le début du suivant (fonctionne aussi en aléatoire). Sans crossfade, l'enchaînement est désormais sans blanc (gapless).")
        }
    }

    // MARK: - Minuteur de sommeil

    private var sleepSection: some View {
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
    }

    // MARK: - Bibliotheque

    private var librarySection: some View {
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
    }

    // MARK: - Sauvegarde

    private var backupSection: some View {
        Section {
            Button {
                backupURL = library.exportBackup()
            } label: {
                Label("Exporter une sauvegarde", systemImage: "square.and.arrow.up")
            }
            Button {
                showRestoreImporter = true
            } label: {
                Label("Restaurer une sauvegarde", systemImage: "square.and.arrow.down")
            }
        } header: {
            Text("Sauvegarde")
        } footer: {
            Text("La sauvegarde (fichier JSON) contient playlists, favoris, paroles, statistiques et liste d'envies — pas les fichiers audio. Après une réinstallation, réimporte ta musique puis restaure : tout est relié automatiquement.")
        }
    }

    // MARK: - Reprise de session

    private var resumeSection: some View {
        Section {
            Toggle(isOn: $resumeOnLaunch) {
                Label("Reprendre où j'en étais", systemImage: "memories")
            }
        } footer: {
            Text("Au lancement, l'app recharge ta dernière file d'attente et ta position dans le morceau, en pause.")
        }
    }

    // MARK: - Apparence

    private var appearanceSection: some View {
        Section {
            HStack(spacing: 16) {
                ForEach(LumeTheme.palettes) { palette in
                    Button {
                        themeID = palette.id
                    } label: {
                        Circle()
                            .fill(LinearGradient(colors: [palette.accent, palette.secondary],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 36, height: 36)
                            .overlay(
                                Circle().strokeBorder(Color.primary.opacity(themeID == palette.id ? 0.7 : 0),
                                                      lineWidth: 2.5)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Thème \(palette.name)")
                    .accessibilityAddTraits(themeID == palette.id ? .isSelected : [])
                }
            }
            .padding(.vertical, 4)
        } header: {
            Text("Apparence")
        } footer: {
            Text("Couleur d'accent de l'app : \(LumeTheme.current.name).")
        }
    }

    // MARK: - Statistiques

    private var statsSection: some View {
        Section {
            NavigationLink {
                StatsView()
            } label: {
                Label("Statistiques d'écoute", systemImage: "chart.bar.fill")
            }
        }
    }

    // MARK: - A propos

    private var aboutSection: some View {
        Section {
            HStack(spacing: 12) {
                Image("LaunchGlyph")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 46, height: 46)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Lume")
                        .font(.system(.headline, design: .rounded).weight(.bold))
                    Text("Ta musique, ta lumière.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(appVersion)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 2)
        } footer: {
            Text("Lume — lecteur de musique local. Tes fichiers restent sur ton iPhone ; la lecture fonctionne 100 % hors connexion. Internet ne sert qu'à Découvrir, aux pochettes, photos d'artistes et paroles en ligne.")
        }
    }

    // Version lue depuis le bundle : plus jamais de numero mensonger en dur.
    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(version) (build \(build))"
    }
}
