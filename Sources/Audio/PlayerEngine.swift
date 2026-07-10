import Foundation
import AVFoundation
import AudioToolbox
import MediaPlayer
import Combine

// Position / duree de lecture, publiees dans un objet SEPARE du moteur.
//
// POURQUOI : la position avance 4 fois par seconde. Quand elle etait
// @Published directement sur PlayerEngine, CHAQUE vue observant le moteur
// (chaque TrackRow d'une liste, la bibliotheque entiere...) etait invalidee
// et re-rendue 4x/s pendant la lecture -> defilement saccade.
// Desormais, seules les vues qui affichent vraiment la progression
// (mini-lecteur, barre du lecteur, paroles synchronisees) observent cet
// objet ; le reste de l'interface n'est plus reveille par le tic d'horloge.
@MainActor
final class PlaybackProgress: ObservableObject {
    @Published var time: Double = 0
    @Published var duration: Double = 0
}

// Moteur de lecture base sur AVAudioEngine.
// Chaine audio (x2 pour le crossfade / gapless) :
//   playerNode -> egaliseur -> mixeur dedie -> sous-mixeur
//   -> vitesse (timePitch) -> basses -> reverb -> limiteur -> mixer principal -> sortie
@MainActor
final class PlayerEngine: ObservableObject {

    // Etat observable par l'interface.
    @Published var currentTrack: Track?
    @Published var isPlaying = false
    @Published var queue: [Track] = []
    @Published var queueIndex = 0

    // Progression : voir PlaybackProgress ci-dessus. Le moteur continue de
    // lire/ecrire currentTime et duration comme avant ; les changements sont
    // simplement republies via `progress` au lieu d'invalider tout le moteur.
    let progress = PlaybackProgress()
    var currentTime: Double = 0 {
        didSet { if currentTime != oldValue { progress.time = currentTime } }
    }
    var duration: Double = 0 {
        didSet { if duration != oldValue { progress.duration = duration } }
    }

    // VRAI mode aleatoire : quand il s'active, la file est melangee UNE FOIS
    // (Fisher-Yates) en gardant le morceau courant en tete. Avantages par
    // rapport a l'ancien tirage au hasard a chaque piste : aucun morceau ne
    // repasse avant que tous soient joues, « precedent » revient vraiment au
    // morceau precedent, la file « A suivre » est exacte, et le crossfade /
    // gapless fonctionnent aussi en aleatoire.
    @Published var shuffleEnabled = false {
        didSet {
            if oldValue != shuffleEnabled { shuffleChanged() }
            saveAudioSettings()
        }
    }
    @Published var repeatMode: RepeatMode = .off {
        didSet { invalidatePreload(); saveAudioSettings() }
    }

    // Reglages (tous persistes entre les lancements, voir saveAudioSettings).
    @Published var crossfadeDuration: Double = 0 { didSet { saveAudioSettings() } }
    @Published var eqEnabled = false { didSet { applyEQ(); saveAudioSettings() } }
    @Published var eqGains: [Float] = Array(repeating: 0, count: 10) { didSet { applyEQ(); saveAudioSettings() } }

    // Optimiseur de basses (filtre low-shelf, 0 = neutre).
    @Published var bassBoostEnabled = false { didSet { applyBass(); saveAudioSettings() } }
    @Published var bassBoostAmount: Float = 6 { didSet { applyBass(); saveAudioSettings() } }   // 0 a 12 dB

    // Ambiance / reverberation (effet « salle » ou « concert »).
    @Published var reverbOption: ReverbOption = .off { didSet { applyReverb(); saveAudioSettings() } }
    @Published var reverbAmount: Float = 35 { didSet { applyReverb(); saveAudioSettings() } }   // 0 a 100 %

    // Profil d'ecoute actif.
    @Published var listeningMode: ListeningMode = .normal { didSet { applyMode(); saveAudioSettings() } }

    // Boost de volume : amplification appliquee APRES le volume systeme.
    // 0 = 100 %, 0.5 = +50 %. Le limiteur en bout de chaine empeche la saturation.
    @Published var volumeBoost: Float = 0 { didSet { applyVolumeBoost(); saveAudioSettings() } }

    // Vitesse de lecture (0.75x a 2x) — pratique pour les podcasts / voix.
    @Published var playbackRate: Float = 1.0 { didSet { applyRate(); saveAudioSettings() } }

    enum RepeatMode: String { case off, all, one }

    // Reverberation : options simples -> presets systeme.
    enum ReverbOption: String, CaseIterable, Identifiable {
        case off = "Aucune"
        case room = "Pièce"
        case hall = "Salle"
        case cathedral = "Cathédrale"
        case concert = "Concert"
        var id: String { rawValue }
        var preset: AVAudioUnitReverbPreset? {
            switch self {
            case .off:        return nil
            case .room:       return .mediumRoom
            case .hall:       return .mediumHall
            case .cathedral:  return .cathedral
            case .concert:    return .largeHall2
            }
        }
    }

    // Profils d'ecoute : combinaisons coherentes d'egaliseur + basses + ambiance.
    enum ListeningMode: String, CaseIterable, Identifiable {
        case normal = "Normal"
        case headphones = "Casque"
        case speaker = "Haut-parleur"
        case plane = "Avion"
        case car = "Voiture"
        case concert = "Concert"
        case voice = "Voix / Podcast"
        var id: String { rawValue }
        var icon: String {
            switch self {
            case .normal:     return "circle"
            case .headphones: return "headphones"
            case .speaker:    return "iphone.gen3"
            case .plane:      return "airplane"
            case .car:        return "car.fill"
            case .concert:    return "music.mic"
            case .voice:      return "waveform.badge.mic"
            }
        }
        // (eqGains, eqOn, basses dB, reverb, reverb %)
        var profile: (eq: [Float], eqOn: Bool, bass: Float, reverb: ReverbOption, reverbAmount: Float) {
            switch self {
            case .normal:
                return ([0,0,0,0,0,0,0,0,0,0], false, 0, .off, 0)
            case .headphones:
                return ([4,3,2,1,0,0,1,2,3,3], true, 5, .off, 0)
            case .speaker:
                return ([-6,-4,-1,0,1,2,3,3,2,1], true, 0, .off, 0)
            case .plane:
                return ([5,4,2,-1,0,1,2,3,2,1], true, 5, .off, 0)
            case .car:
                return ([2,3,1,0,1,2,3,3,2,1], true, 3, .off, 0)
            case .concert:
                return ([3,2,1,0,0,0,1,2,2,2], true, 4, .hall, 18)
            case .voice:
                return ([-4,-3,-1,1,3,3,2,1,-1,-2], true, 0, .room, 12)
            }
        }
    }

    // Reference vers la bibliotheque (pour resoudre les URL de fichiers).
    weak var library: LibraryStore?

    // MARK: - Remontee des statistiques d'ecoute (branchee dans RootView)
    var onTrackCompleted: ((Track) -> Void)?
    var onTrackSkipped: ((Track) -> Void)?
    var onListenFlush: ((Track, Double) -> Void)?

    private var listenAccumulator: Double = 0

    func flushListenTime() {
        guard let track = currentTrack, listenAccumulator > 0.5 else {
            listenAccumulator = 0
            return
        }
        onListenFlush?(track, listenAccumulator)
        listenAccumulator = 0
    }

    // Pour le minuteur « fin du morceau » : arret apres la piste en cours.
    var stopAfterCurrentTrack = false
    var onAutoStop: (() -> Void)?

    // Frequences des 10 bandes de l'egaliseur.
    static let eqFrequencies: [Float] = [32, 64, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]

    // --- Internes audio ---
    private let engine = AVAudioEngine()
    private let players = [AVAudioPlayerNode(), AVAudioPlayerNode()]
    private let eqs = [AVAudioUnitEQ(numberOfBands: 10), AVAudioUnitEQ(numberOfBands: 10)]
    private let playerMixers = [AVAudioMixerNode(), AVAudioMixerNode()]
    private let mixFormat = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!
    private let subMixer = AVAudioMixerNode()
    // Vitesse de lecture (sans changer la hauteur du son).
    private let timePitch = AVAudioUnitTimePitch()
    private let bassBoost = AVAudioUnitEQ(numberOfBands: 2)
    private let reverb = AVAudioUnitReverb()
    // Limiteur de crete : garde-fou en bout de chaine. Il empeche la
    // saturation quand le boost de volume ou les basses poussent le signal
    // au-dela de 0 dB (c'etait la cause du son « sale » a fort reglage).
    private let limiter: AVAudioUnitEffect = {
        let desc = AudioComponentDescription(componentType: kAudioUnitType_Effect,
                                             componentSubType: kAudioUnitSubType_PeakLimiter,
                                             componentManufacturer: kAudioUnitManufacturer_Apple,
                                             componentFlags: 0,
                                             componentFlagsMask: 0)
        return AVAudioUnitEffect(audioComponentDescription: desc)
    }()

    private var files: [AVAudioFile?] = [nil, nil]
    private var startFrames: [AVAudioFramePosition] = [0, 0]
    private var generations: [Int] = [0, 0]
    private var activeIndex = 0
    private var isCrossfading = false
    private var consecutiveLoadFailures = 0

    // File d'origine (ordre normal), memorisee quand le shuffle est actif.
    private var orderedQueue: [Track] = []

    // Gapless : piste suivante pre-chargee sur le lecteur inactif.
    private var preloadedPlayer: Int?
    private var preloadedIndex: Int?
    private var preloadedTrackID: UUID?

    private var ticker: Timer?
    private var fadeTimer: Timer?
    private var lastTickDate: Date?
    private var lastPersistDate = Date.distantPast
    private var restoringSettings = false

    // Reference partagee pour les commandes Siri / Raccourcis (AppIntents).
    static weak var shared: PlayerEngine?

    init() {
        configureSession()
        setupEngine()
        setupRemoteCommands()
        observeInterruptions()
        // NOTE batterie : le ticker n'est PLUS demarre ici. Il ne tourne que
        // pendant la lecture (voir startTicker / stopTicker) — avant, il
        // reveillait le CPU 4x/seconde en permanence, meme a l'arret.
        restoreAudioSettings()
        PlayerEngine.shared = self
    }

    // MARK: - Mise en place du graphe audio

    private func setupEngine() {
        engine.attach(subMixer)
        engine.attach(timePitch)
        engine.attach(bassBoost)
        engine.attach(reverb)
        engine.attach(limiter)

        // Assise : plateau bas (tout ce qui est sous ~100 Hz est renforce).
        let shelf = bassBoost.bands[0]
        shelf.filterType = .lowShelf
        shelf.frequency = 100
        shelf.gain = 0
        shelf.bypass = false
        // Punch : bosse centree sur 62 Hz (le "coup" du kick et de la basse).
        let punch = bassBoost.bands[1]
        punch.filterType = .parametric
        punch.frequency = 62
        punch.bandwidth = 1.2
        punch.gain = 0
        punch.bypass = false

        reverb.loadFactoryPreset(.mediumHall)
        reverb.wetDryMix = 0
        timePitch.rate = 1.0
        timePitch.bypass = true   // court-circuite a 1x (voir applyRate)

        for i in 0..<2 {
            engine.attach(players[i])
            engine.attach(eqs[i])
            engine.attach(playerMixers[i])
            configureEQ(eqs[i])
            engine.connect(players[i], to: eqs[i], format: mixFormat)
            engine.connect(eqs[i], to: playerMixers[i], format: mixFormat)
            engine.connect(playerMixers[i], to: subMixer, format: mixFormat)
        }

        engine.connect(subMixer, to: timePitch, format: mixFormat)
        engine.connect(timePitch, to: bassBoost, format: mixFormat)
        engine.connect(bassBoost, to: reverb, format: mixFormat)
        engine.connect(reverb, to: limiter, format: mixFormat)
        engine.connect(limiter, to: engine.mainMixerNode, format: mixFormat)

        engine.prepare()
        // NOTE batterie : on ne demarre PAS le moteur ici. Un AVAudioEngine
        // demarre fait tourner son thread de rendu et garde le materiel audio
        // alimente EN CONTINU, meme sans lecture. Il est demarre a la demande
        // (load / resume) et mis en pause des que la lecture s'arrete.
    }

    private func configureEQ(_ eq: AVAudioUnitEQ) {
        for (idx, band) in eq.bands.enumerated() where idx < Self.eqFrequencies.count {
            band.filterType = .parametric
            band.frequency = Self.eqFrequencies[idx]
            band.bandwidth = 0.5
            band.gain = 0
            band.bypass = true
        }
    }

    private func applyEQ() {
        for eq in eqs {
            for (idx, band) in eq.bands.enumerated() where idx < eqGains.count {
                band.gain = eqEnabled ? eqGains[idx] : 0
                band.bypass = !eqEnabled
            }
        }
    }

    private func applyBass() {
        let amount = bassBoostEnabled ? bassBoostAmount : 0
        bassBoost.bands[0].gain = amount
        bassBoost.bands[1].gain = amount * 0.6
        bassBoost.globalGain = -amount * 0.3
    }

    private func applyVolumeBoost() {
        let boost = max(0, min(0.5, volumeBoost))
        let gainDB = Float(20.0 * log10(Double(1.0 + boost)))
        for eq in eqs { eq.globalGain = gainDB }
    }

    private func applyReverb() {
        if let preset = reverbOption.preset {
            reverb.loadFactoryPreset(preset)
            reverb.wetDryMix = reverbAmount
        } else {
            reverb.wetDryMix = 0
        }
    }

    private func applyRate() {
        let r = max(0.5, min(2.0, playbackRate))
        timePitch.rate = r
        // CORRECTIF : le module de vitesse traite l'audio EN CONTINU, meme a
        // 1x, et son algorithme d'etirement temporel degrade legerement le
        // son (voix "phasees", aigus adoucis). A vitesse normale, on le
        // court-circuite completement -> son 100 % intact.
        timePitch.bypass = (r == 1.0)
        updateNowPlayingElapsed()
    }

    // Applique un profil d'ecoute complet (egaliseur + basses + ambiance).
    private func applyMode() {
        let p = listeningMode.profile
        eqGains = p.eq
        eqEnabled = p.eqOn
        bassBoostAmount = p.bass
        bassBoostEnabled = p.bass > 0
        reverbAmount = p.reverbAmount
        reverbOption = p.reverb
    }

    // MARK: - Son personnalise (memorise avant l'application d'un profil)

    private struct SoundSnapshot: Codable {
        var eq: [Float]
        var eqOn: Bool
        var bass: Float
        var bassOn: Bool
        var reverb: String
        var reverbAmount: Float
    }

    // A appeler depuis l'interface a la place de `listeningMode = ...` :
    // sauvegarde d'abord les reglages manuels pour pouvoir y revenir.
    func selectListeningMode(_ mode: ListeningMode) {
        if listeningMode == .normal && mode != .normal {
            let snap = SoundSnapshot(eq: eqGains, eqOn: eqEnabled,
                                     bass: bassBoostAmount, bassOn: bassBoostEnabled,
                                     reverb: reverbOption.rawValue, reverbAmount: reverbAmount)
            if let data = try? JSONEncoder().encode(snap) {
                UserDefaults.standard.set(data, forKey: "audio.customSnapshot")
            }
        }
        listeningMode = mode
    }

    var hasCustomSound: Bool {
        UserDefaults.standard.data(forKey: "audio.customSnapshot") != nil
    }

    // Restaure les reglages manuels sauvegardes ("Personnalisé").
    func restoreCustomSound() {
        guard let data = UserDefaults.standard.data(forKey: "audio.customSnapshot"),
              let snap = try? JSONDecoder().decode(SoundSnapshot.self, from: data) else { return }
        listeningMode = .normal            // remet tout a plat...
        eqGains = snap.eq                  // ...puis reapplique les reglages perso.
        eqEnabled = snap.eqOn
        bassBoostAmount = snap.bass
        bassBoostEnabled = snap.bassOn
        reverbAmount = snap.reverbAmount
        reverbOption = ReverbOption(rawValue: snap.reverb) ?? .off
    }

    // MARK: - Persistance des reglages audio

    private func saveAudioSettings() {
        guard !restoringSettings else { return }
        let d = UserDefaults.standard
        d.set(crossfadeDuration, forKey: "audio.crossfade")
        d.set(eqEnabled, forKey: "audio.eqOn")
        d.set(eqGains.map { NSNumber(value: $0) }, forKey: "audio.eqGains")
        d.set(bassBoostEnabled, forKey: "audio.bassOn")
        d.set(Double(bassBoostAmount), forKey: "audio.bassAmount")
        d.set(reverbOption.rawValue, forKey: "audio.reverb")
        d.set(Double(reverbAmount), forKey: "audio.reverbAmount")
        d.set(listeningMode.rawValue, forKey: "audio.mode")
        d.set(Double(volumeBoost), forKey: "audio.volumeBoost")
        d.set(Double(playbackRate), forKey: "audio.rate")
        d.set(shuffleEnabled, forKey: "audio.shuffle")
        d.set(repeatMode.rawValue, forKey: "audio.repeat")
    }

    private func restoreAudioSettings() {
        let d = UserDefaults.standard
        guard d.object(forKey: "audio.crossfade") != nil else { return }  // premiere ouverture
        restoringSettings = true
        // Le mode d'abord (il ecrase gains/basses/reverb), puis les valeurs
        // individuelles par-dessus (identiques au profil pour un utilisateur
        // "mode", personnalisees pour un utilisateur "manuel").
        if let raw = d.string(forKey: "audio.mode"), let mode = ListeningMode(rawValue: raw) {
            listeningMode = mode
        }
        crossfadeDuration = d.double(forKey: "audio.crossfade")
        if let gains = d.array(forKey: "audio.eqGains") as? [NSNumber], gains.count == 10 {
            eqGains = gains.map { $0.floatValue }
        }
        eqEnabled = d.bool(forKey: "audio.eqOn")
        bassBoostAmount = Float(d.double(forKey: "audio.bassAmount"))
        bassBoostEnabled = d.bool(forKey: "audio.bassOn")
        reverbAmount = Float(d.double(forKey: "audio.reverbAmount"))
        if let raw = d.string(forKey: "audio.reverb"), let opt = ReverbOption(rawValue: raw) {
            reverbOption = opt
        }
        volumeBoost = Float(d.double(forKey: "audio.volumeBoost"))
        let rate = d.double(forKey: "audio.rate")
        playbackRate = rate > 0 ? Float(rate) : 1.0
        shuffleEnabled = d.bool(forKey: "audio.shuffle")
        if let raw = d.string(forKey: "audio.repeat"), let mode = RepeatMode(rawValue: raw) {
            repeatMode = mode
        }
        restoringSettings = false
    }

    private func configureSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default)
        try? session.setActive(true)
    }

    // MARK: - Lecture d'une file

    func play(tracks: [Track], startAt index: Int) {
        guard !tracks.isEmpty, index >= 0, index < tracks.count else { return }
        isCrossfading = false
        invalidatePreload()
        if shuffleEnabled {
            // File melangee UNE fois, le morceau demande en tete.
            orderedQueue = tracks
            var rest = tracks
            let start = rest.remove(at: index)
            rest.shuffle()
            queue = [start] + rest
            queueIndex = 0
        } else {
            orderedQueue = []
            queue = tracks
            queueIndex = index
        }
        load(track: queue[queueIndex], intoPlayer: activeIndex, startFrame: 0, autoPlay: true)
    }

    func playSingle(_ track: Track, in context: [Track]) {
        if let idx = context.firstIndex(of: track) {
            play(tracks: context, startAt: idx)
        } else {
            play(tracks: [track], startAt: 0)
        }
    }

    // Activation / desactivation du shuffle sur la file en cours.
    private func shuffleChanged() {
        guard !queue.isEmpty else { return }
        invalidatePreload()
        if shuffleEnabled {
            orderedQueue = queue
            var rest = queue
            var head: [Track] = []
            if queueIndex >= 0, queueIndex < rest.count {
                head = [rest.remove(at: queueIndex)]
            }
            rest.shuffle()
            queue = head + rest
            queueIndex = 0
        } else if !orderedQueue.isEmpty {
            let current = currentTrack
            queue = orderedQueue
            orderedQueue = []
            if let current, let idx = queue.firstIndex(of: current) {
                queueIndex = idx
            } else {
                queueIndex = min(queueIndex, max(0, queue.count - 1))
            }
        }
    }

    // MARK: - Gestion de la file (Lire ensuite / Ajouter a la file)

    func playNext(_ track: Track) {
        guard currentTrack != nil, !queue.isEmpty else {
            play(tracks: [track], startAt: 0)
            return
        }
        invalidatePreload()
        queue.insert(track, at: min(queueIndex + 1, queue.count))
    }

    func addToQueue(_ track: Track) {
        guard currentTrack != nil, !queue.isEmpty else {
            play(tracks: [track], startAt: 0)
            return
        }
        invalidatePreload()
        queue.append(track)
    }

    // Suppression d'elements « A suivre » (indices ABSOLUS dans la file).
    func removeFromQueue(atQueueIndices indices: [Int]) {
        invalidatePreload()
        for i in indices.sorted(by: >) where i > queueIndex && i < queue.count {
            queue.remove(at: i)
        }
    }

    // Reordonnancement de la partie « A suivre » (offsets RELATIFS a cette partie).
    func moveUpcoming(from source: IndexSet, to destination: Int) {
        guard queueIndex + 1 <= queue.count else { return }
        invalidatePreload()
        var upcoming = Array(queue[(queueIndex + 1)...])
        upcoming.move(fromOffsets: source, toOffset: destination)
        queue.replaceSubrange((queueIndex + 1)..., with: upcoming)
    }

    // Charge un morceau dans l'un des deux lecteurs et (optionnellement) demarre.
    private func load(track: Track, intoPlayer i: Int, startFrame: AVAudioFramePosition, autoPlay: Bool) {
        guard let lib = library else { return }
        let url = lib.url(for: track)
        guard let file = try? AVAudioFile(forReading: url) else {
            consecutiveLoadFailures += 1
            if consecutiveLoadFailures >= max(1, queue.count) {
                consecutiveLoadFailures = 0
                stopPlayback()
                return
            }
            next()
            return
        }
        consecutiveLoadFailures = 0

        players[i].stop()
        players[i].volume = 1.0
        files[i] = file
        startFrames[i] = startFrame

        generations[i] += 1
        let gen = generations[i]
        let remaining = AVAudioFrameCount(max(0, file.length - startFrame))
        players[i].scheduleSegment(file,
                                   startingFrame: startFrame,
                                   frameCount: remaining,
                                   at: nil,
                                   completionCallbackType: .dataPlayedBack) { [weak self] _ in
            Task { @MainActor in self?.handlePlaybackFinished(player: i, generation: gen) }
        }

        if !engine.isRunning { try? engine.start() }

        if autoPlay {
            activeIndex = i
            currentTrack = track
            duration = computedDuration(for: i, fallback: track.duration)
            currentTime = Double(startFrame) / max(1, file.processingFormat.sampleRate)
            lastTickDate = nil
            players[i].play()
            isPlaying = true
            updateNowPlaying()
            persistSession()
            startTicker()
        }
    }

    private func computedDuration(for i: Int, fallback: Double) -> Double {
        guard let file = files[i] else { return fallback }
        let sr = file.processingFormat.sampleRate
        let secs = sr > 0 ? Double(file.length) / sr : 0
        return secs > 0.1 ? secs : fallback
    }

    // MARK: - Gapless (enchainement sans blanc)

    // Pre-charge la piste suivante sur le lecteur inactif : ouverture du
    // fichier et planification faites A L'AVANCE. A la fin du morceau, il ne
    // reste qu'a appuyer sur « play » -> l'enchainement est quasi instantane
    // (sans crossfade, l'ancien code rouvrait le fichier a ce moment-la,
    // d'ou un blanc audible entre les pistes).
    private func preload(track: Track, atQueueIndex idx: Int) {
        guard let lib = library,
              let file = try? AVAudioFile(forReading: lib.url(for: track)) else { return }
        let j = 1 - activeIndex
        players[j].stop()
        players[j].volume = 1.0
        files[j] = file
        startFrames[j] = 0
        generations[j] += 1
        let gen = generations[j]
        players[j].scheduleSegment(file,
                                   startingFrame: 0,
                                   frameCount: AVAudioFrameCount(file.length),
                                   at: nil,
                                   completionCallbackType: .dataPlayedBack) { [weak self] _ in
            Task { @MainActor in self?.handlePlaybackFinished(player: j, generation: gen) }
        }
        preloadedPlayer = j
        preloadedIndex = idx
        preloadedTrackID = track.id
    }

    private func invalidatePreload() {
        if let p = preloadedPlayer {
            generations[p] += 1
            players[p].stop()
        }
        preloadedPlayer = nil
        preloadedIndex = nil
        preloadedTrackID = nil
    }

    // Fin naturelle d'un morceau (signalee par le callback de planification).
    private func handlePlaybackFinished(player i: Int, generation gen: Int) {
        guard gen == generations[i] else { return }
        guard i == activeIndex, !isCrossfading else { return }

        // Bascule gapless : la piste suivante est deja prete sur l'autre lecteur.
        if let pp = preloadedPlayer, let pi = preloadedIndex, let pid = preloadedTrackID,
           pp != i, !stopAfterCurrentTrack, repeatMode != .one,
           pi < queue.count, queue[pi].id == pid {
            if let finished = currentTrack { onTrackCompleted?(finished) }
            flushListenTime()
            players[pp].play()
            activeIndex = pp
            queueIndex = pi
            currentTrack = queue[pi]
            duration = computedDuration(for: pp, fallback: queue[pi].duration)
            currentTime = 0
            lastTickDate = nil
            preloadedPlayer = nil
            preloadedIndex = nil
            preloadedTrackID = nil
            isPlaying = true
            updateNowPlaying()
            persistSession()
            return
        }
        advanceAtEnd()
    }

    // MARK: - Transport

    func togglePlayPause() { isPlaying ? pause() : resume() }

    func pause() {
        players[activeIndex].pause()
        if isCrossfading { players[1 - activeIndex].pause() }
        isPlaying = false
        flushListenTime()
        persistSession()
        updateNowPlaying()
        // Economie d'energie : plus de tic d'horloge ni de thread de rendu
        // audio tant que rien ne joue.
        stopTicker()
        engine.pause()
    }

    func resume() {
        if !engine.isRunning { try? engine.start() }
        players[activeIndex].play()
        if isCrossfading { players[1 - activeIndex].play() }
        isPlaying = true
        updateNowPlaying()
        startTicker()
    }

    func next() {
        cancelCrossfade()
        invalidatePreload()
        if let track = currentTrack, duration > 0 {
            if currentTime / duration < 0.8 {
                onTrackSkipped?(track)
            } else {
                onTrackCompleted?(track)
            }
        }
        flushListenTime()
        guard !queue.isEmpty else { return }
        if repeatMode == .one {
            restartCurrent()
            return
        }
        var newIndex = queueIndex + 1
        if newIndex >= queue.count {
            if repeatMode == .all { newIndex = 0 } else { stopPlayback(); return }
        }
        queueIndex = newIndex
        load(track: queue[newIndex], intoPlayer: activeIndex, startFrame: 0, autoPlay: true)
    }

    func previous() {
        cancelCrossfade()
        flushListenTime()
        if currentTime > 3 {
            restartCurrent()
            return
        }
        guard !queue.isEmpty else { return }
        invalidatePreload()
        var newIndex = queueIndex - 1
        if newIndex < 0 {
            newIndex = repeatMode == .all ? queue.count - 1 : 0
        }
        queueIndex = newIndex
        load(track: queue[newIndex], intoPlayer: activeIndex, startFrame: 0, autoPlay: true)
    }

    // Saut avant/arriere (utilise en mode Voix / Podcast).
    func skip(by seconds: Double) {
        guard duration > 0 else { return }
        seek(to: max(0, min(duration - 0.5, currentTime + seconds)))
    }

    private func advanceAtEnd() {
        if let track = currentTrack { onTrackCompleted?(track) }
        flushListenTime()
        if stopAfterCurrentTrack {
            stopPlayback()
            stopAfterCurrentTrack = false
            onAutoStop?()
            return
        }
        if repeatMode == .one { restartCurrent(); return }
        var newIndex = queueIndex + 1
        if newIndex >= queue.count {
            if repeatMode == .all { newIndex = 0 } else { stopPlayback(); return }
        }
        queueIndex = newIndex
        load(track: queue[newIndex], intoPlayer: activeIndex, startFrame: 0, autoPlay: true)
    }

    private func restartCurrent() {
        guard let t = currentTrack else { return }
        load(track: t, intoPlayer: activeIndex, startFrame: 0, autoPlay: true)
    }

    private func stopPlayback() {
        invalidatePreload()
        players.forEach { $0.stop() }
        isPlaying = false
        currentTime = 0
        updateNowPlaying()
        stopTicker()
        engine.pause()
    }

    // Volume de sortie global (utilise par le fondu du minuteur de sommeil).
    func setOutputVolume(_ v: Float) {
        engine.mainMixerNode.outputVolume = max(0, min(1, v))
    }

    // MARK: - Reprise de session (redemarrage de l'app)

    func persistSession() {
        let d = UserDefaults.standard
        guard let track = currentTrack, !queue.isEmpty else {
            d.removeObject(forKey: "session.queue")
            return
        }
        d.set(queue.map { $0.id.uuidString }, forKey: "session.queue")
        d.set(queueIndex, forKey: "session.index")
        d.set(currentTime, forKey: "session.time")
        d.set(track.id.uuidString, forKey: "session.trackID")
    }

    func restoreSavedSessionIfNeeded() {
        guard currentTrack == nil, let lib = library else { return }
        let d = UserDefaults.standard
        guard let ids = d.stringArray(forKey: "session.queue"), !ids.isEmpty else { return }
        let byID = Dictionary(uniqueKeysWithValues: lib.tracks.map { ($0.id.uuidString, $0) })
        let restored = ids.compactMap { byID[$0] }
        guard !restored.isEmpty else { return }
        var index = d.integer(forKey: "session.index")
        if let savedID = d.string(forKey: "session.trackID"),
           let realIdx = restored.firstIndex(where: { $0.id.uuidString == savedID }) {
            index = realIdx
        }
        guard index >= 0, index < restored.count else { return }
        let time = d.double(forKey: "session.time")
        let track = restored[index]

        queue = restored
        queueIndex = index
        guard let file = try? AVAudioFile(forReading: lib.url(for: track)) else { return }
        let sr = file.processingFormat.sampleRate
        let frame = AVAudioFramePosition(max(0, min(time, max(0, track.duration - 2))) * sr)
        load(track: track, intoPlayer: activeIndex, startFrame: frame, autoPlay: true)
        pause()
        currentTime = Double(frame) / max(1, sr)
    }

    // MARK: - Recherche de position (seek)

    func seek(to time: Double) {
        guard let file = files[activeIndex] else { return }
        let sr = file.processingFormat.sampleRate
        let frame = AVAudioFramePosition(max(0, time) * sr)
        guard let track = currentTrack else { return }
        cancelCrossfade()
        // NOTE : on ne touche PAS au pre-chargement gapless — la piste suivante
        // reste la meme, sa planification reste valable.
        let wasPlaying = isPlaying
        load(track: track, intoPlayer: activeIndex, startFrame: frame, autoPlay: true)
        if !wasPlaying { pause() }
        currentTime = time
        // La position poussee a l'ecran verrouille n'est plus rafraichie en
        // continu : apres un seek (surtout en pause), on la synchronise ici.
        updateNowPlayingElapsed()
    }

    // MARK: - Crossfade

    private func startCrossfade(to track: Track) {
        invalidatePreload()
        let newPlayer = 1 - activeIndex
        isCrossfading = true
        load(track: track, intoPlayer: newPlayer, startFrame: 0, autoPlay: false)
        players[newPlayer].volume = 0
        players[newPlayer].play()

        let oldPlayer = activeIndex
        let steps = 40
        let interval = crossfadeDuration / Double(steps)
        var step = 0
        fadeTimer?.invalidate()
        // Mode .common : en mode .default le timer serait GELE pendant un
        // scroll ou un doigt pose sur l'ecran -> fondu fige en plein milieu.
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] timer in
            Task { @MainActor in
                guard let self else { timer.invalidate(); return }
                // Pause utilisateur en plein fondu : on FIGE le fondu (les
                // lecteurs sont en pause, le moteur aussi) au lieu de le
                // laisser se terminer en silence — il reprend au resume().
                guard self.isPlaying else { return }
                step += 1
                let p = Float(step) / Float(steps)
                self.players[oldPlayer].volume = max(0, 1 - p)
                self.players[newPlayer].volume = min(1, p)
                if step >= steps {
                    timer.invalidate()
                    self.finishCrossfade(newPlayer: newPlayer, track: track)
                }
            }
        }
        RunLoop.main.add(t, forMode: .common)
        fadeTimer = t
    }

    private func finishCrossfade(newPlayer: Int, track: Track) {
        if let finished = currentTrack { onTrackCompleted?(finished) }
        flushListenTime()
        players[activeIndex].stop()
        activeIndex = newPlayer
        currentTrack = track
        duration = computedDuration(for: newPlayer, fallback: track.duration)
        isPlaying = true
        isCrossfading = false
        if let idx = queue.firstIndex(of: track) { queueIndex = idx }
        updateNowPlaying()
        persistSession()
    }

    private func cancelCrossfade() {
        fadeTimer?.invalidate()
        fadeTimer = nil
        if isCrossfading {
            players[1 - activeIndex].stop()
            players[activeIndex].volume = 1
            isCrossfading = false
        }
    }

    // Piste qui suivra dans la file (index + morceau). Fonctionne desormais
    // aussi en shuffle, puisque la file melangee est deterministe.
    private func upcoming() -> (Int, Track)? {
        guard !queue.isEmpty, repeatMode != .one else { return nil }
        let nextIdx = queueIndex + 1
        if nextIdx < queue.count { return (nextIdx, queue[nextIdx]) }
        if repeatMode == .all, let first = queue.first { return (0, first) }
        return nil
    }

    // MARK: - Tic d'horloge (temps + crossfade + gapless + sauvegarde)
    //
    // Le ticker ne tourne QUE pendant la lecture : demarre au play, arrete
    // au pause / stop. Avant, il tournait en permanence des l'init (4 reveils
    // CPU par seconde, app en arriere-plan comprise) pour rien.

    private func startTicker() {
        guard ticker == nil else { return }
        let t = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        ticker = t
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
        lastTickDate = nil
    }

    private func tick() {
        guard isPlaying else { lastTickDate = nil; return }
        if let t = playbackPosition() {
            if t > duration, duration > 0 {
                duration = t
            }
            let delta = t - currentTime
            if delta > 0, delta < 2 { listenAccumulator += delta }
            currentTime = t
            lastTickDate = Date()
            afterTick()
            return
        }
        let now = Date()
        if let last = lastTickDate {
            var t = currentTime + now.timeIntervalSince(last)
            if duration > 0 { t = min(t, duration) }
            currentTime = t
        }
        lastTickDate = now
        afterTick()
    }

    private func playbackPosition() -> Double? {
        let p = players[activeIndex]
        guard let nodeTime = p.lastRenderTime,
              let playerTime = p.playerTime(forNodeTime: nodeTime),
              playerTime.isSampleTimeValid,
              playerTime.sampleRate > 0 else { return nil }
        let played = max(0, Double(playerTime.sampleTime) / playerTime.sampleRate)
        let fileSR = files[activeIndex]?.processingFormat.sampleRate ?? 0
        let offset = fileSR > 0 ? Double(startFrames[activeIndex]) / fileSR : 0
        return offset + played
    }

    private func afterTick() {
        if duration > 0, !isCrossfading {
            let remaining = duration - currentTime
            if crossfadeDuration > 0 {
                // Declenchement du crossfade.
                if remaining <= crossfadeDuration, remaining > 0.1, let (_, nextTrack) = upcoming() {
                    startCrossfade(to: nextTrack)
                }
            } else if remaining <= 15, remaining > 0.5, preloadedPlayer == nil,
                      !stopAfterCurrentTrack, let (idx, nextTrack) = upcoming() {
                // Pre-chargement gapless de la piste suivante.
                preload(track: nextTrack, atQueueIndex: idx)
            }
        }
        // Sauvegarde periodique de la position : si l'app est tuee en pleine
        // lecture (ou crash), la reprise ne perd plus tout depuis la derniere
        // pause — au pire les 10 dernieres secondes.
        if Date().timeIntervalSince(lastPersistDate) > 10 {
            lastPersistDate = Date()
            persistSession()
        }
        // NOTE batterie : on ne pousse PLUS la position vers l'ecran
        // verrouille a chaque tic (4 ecritures IPC / seconde). iOS interpole
        // lui-meme la position a partir de PlaybackRate ; il suffit de mettre
        // les infos a jour aux changements d'etat (play/pause/seek/piste),
        // ce que updateNowPlaying() fait deja.
    }

    // MARK: - Ecran verrouille / centre de controle

    private func setupRemoteCommands() {
        let c = MPRemoteCommandCenter.shared()
        c.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.resume() }
            return .success
        }
        c.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.pause() }
            return .success
        }
        c.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.togglePlayPause() }
            return .success
        }
        c.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.next() }
            return .success
        }
        c.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.previous() }
            return .success
        }
        c.changePlaybackPositionCommand.addTarget { [weak self] event in
            if let e = event as? MPChangePlaybackPositionCommandEvent {
                let t = e.positionTime
                Task { @MainActor in self?.seek(to: t) }
            }
            return .success
        }
    }

    private func updateNowPlaying() {
        guard let track = currentTrack else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: track.title,
            MPMediaItemPropertyArtist: track.artist,
            MPMediaItemPropertyAlbumTitle: track.album,
            // Duree REELLE calculee depuis le fichier (self.duration), pas la
            // metadonnee track.duration souvent fausse sur les fichiers VBR :
            // la barre de l'ecran verrouille est desormais coherente avec l'app.
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? Double(playbackRate) : 0.0
        ]
        if let image = library?.artworkImage(for: track) {
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func updateNowPlayingElapsed() {
        guard var info = MPNowPlayingInfoCenter.default().nowPlayingInfo else { return }
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        info[MPMediaItemPropertyPlaybackDuration] = duration
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? Double(playbackRate) : 0.0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    // MARK: - Interruptions (appels, autres apps) et changements de sortie

    private func observeInterruptions() {
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil, queue: .main) { [weak self] note in
            Task { @MainActor in self?.handleInterruption(note) }
        }
        // Debranchement des ecouteurs / deconnexion Bluetooth : on met en
        // pause au lieu de continuer sur le haut-parleur (comportement
        // standard des lecteurs de musique).
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil, queue: .main) { [weak self] note in
            Task { @MainActor in self?.handleRouteChange(note) }
        }
    }

    private func handleInterruption(_ note: Notification) {
        guard let info = note.userInfo,
              let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }
        switch type {
        case .began:
            pause()
        case .ended:
            if let optionsValue = info[AVAudioSessionInterruptionOptionKey] as? UInt,
               AVAudioSession.InterruptionOptions(rawValue: optionsValue).contains(.shouldResume) {
                resume()
            }
        @unknown default:
            break
        }
    }

    private func handleRouteChange(_ note: Notification) {
        guard let info = note.userInfo,
              let reasonValue = info[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else { return }
        if reason == .oldDeviceUnavailable, isPlaying {
            pause()
        }
    }
}
