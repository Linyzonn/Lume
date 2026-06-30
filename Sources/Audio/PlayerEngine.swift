import Foundation
import AVFoundation
import MediaPlayer
import Combine

// Moteur de lecture base sur AVAudioEngine.
// Chaine audio (x2 pour le crossfade) :  playerNode -> egaliseur -> mixer principal -> sortie
@MainActor
final class PlayerEngine: ObservableObject {

    // Etat observable par l'interface.
    @Published var currentTrack: Track?
    @Published var isPlaying = false
    @Published var currentTime: Double = 0
    @Published var duration: Double = 0
    @Published var queue: [Track] = []
    @Published var queueIndex = 0
    @Published var shuffleEnabled = false
    @Published var repeatMode: RepeatMode = .off

    // Reglages.
    @Published var crossfadeDuration: Double = 0           // 0 = desactive, jusqu'a 12 s
    @Published var eqEnabled = false { didSet { applyEQ() } }
    @Published var eqGains: [Float] = Array(repeating: 0, count: 10) { didSet { applyEQ() } }

    // Optimiseur de basses (filtre low-shelf, 0 = neutre).
    @Published var bassBoostEnabled = false { didSet { applyBass() } }
    @Published var bassBoostAmount: Float = 6 { didSet { applyBass() } }   // 0 a 12 dB

    // Ambiance / reverberation (effet « salle » ou « concert »).
    @Published var reverbOption: ReverbOption = .off { didSet { applyReverb() } }
    @Published var reverbAmount: Float = 35 { didSet { applyReverb() } }   // 0 a 100 %

    // Profil d'ecoute actif.
    @Published var listeningMode: ListeningMode = .normal { didSet { applyMode() } }

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
        case concert = "Concert"
        case voice = "Voix / Podcast"
        var id: String { rawValue }
        var icon: String {
            switch self {
            case .normal:     return "circle"
            case .headphones: return "headphones"
            case .speaker:    return "iphone.gen3"
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
                // Courbe chaleureuse : graves profonds, aigus aeres.
                return ([4,3,2,1,0,0,1,2,3,3], true, 5, .off, 0)
            case .speaker:
                // Petit HP d'iPhone : on coupe le sub inutile, on pousse clarte et presence.
                return ([-6,-4,-1,0,1,2,3,3,2,1], true, 0, .off, 0)
            case .concert:
                // Sensation live : basses pleines + grande salle.
                return ([5,4,2,1,0,0,1,2,3,3], true, 7, .concert, 45)
            case .voice:
                // Parole nette : medianes en avant, extremes attenues.
                return ([-4,-3,-1,1,3,3,2,1,-1,-2], true, 0, .room, 12)
            }
        }
    }

    // Reference vers la bibliotheque (pour resoudre les URL de fichiers).
    weak var library: LibraryStore?

    // Pour le minuteur « fin du morceau » : arret apres la piste en cours.
    var stopAfterCurrentTrack = false
    var onAutoStop: (() -> Void)?

    // Frequences des 10 bandes de l'egaliseur.
    static let eqFrequencies: [Float] = [32, 64, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]

    // --- Internes audio ---
    private let engine = AVAudioEngine()
    private let players = [AVAudioPlayerNode(), AVAudioPlayerNode()]
    private let eqs = [AVAudioUnitEQ(numberOfBands: 10), AVAudioUnitEQ(numberOfBands: 10)]
    // Un mixeur dedie par lecteur : il "absorbe" le format du fichier (qui peut
    // varier d'un morceau a l'autre) et ressort TOUJOURS au format fixe `mixFormat`.
    // Ainsi, charger un nouveau morceau ne reconfigure jamais le mixeur partage ni
    // la sortie -> plus de crash AVAudioEngine sur iOS 16+.
    private let playerMixers = [AVAudioMixerNode(), AVAudioMixerNode()]
    // Format de travail commun a tout l'etage partage (la sortie convertira si besoin).
    private let mixFormat = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!
    private let subMixer = AVAudioMixerNode()                 // somme les deux lecteurs
    private let bassBoost = AVAudioUnitEQ(numberOfBands: 1)   // filtre low-shelf
    private let reverb = AVAudioUnitReverb()                  // ambiance / concert
    private var files: [AVAudioFile?] = [nil, nil]
    private var startFrames: [AVAudioFramePosition] = [0, 0]
    private var generations: [Int] = [0, 0]
    private var activeIndex = 0
    private var isCrossfading = false
    private var consecutiveLoadFailures = 0

    private var ticker: Timer?
    private var fadeTimer: Timer?

    init() {
        configureSession()
        setupEngine()
        setupRemoteCommands()
        observeInterruptions()
        startTicker()
    }

    // MARK: - Mise en place du graphe audio

    private func setupEngine() {
        // Etage commun : sous-mixeur -> optimiseur de basses -> reverb -> sortie.
        engine.attach(subMixer)
        engine.attach(bassBoost)
        engine.attach(reverb)

        let bass = bassBoost.bands[0]
        bass.filterType = .lowShelf
        bass.frequency = 110
        bass.gain = 0
        bass.bypass = false

        reverb.loadFactoryPreset(.mediumHall)
        reverb.wetDryMix = 0   // sec par defaut (aucun effet)

        for i in 0..<2 {
            engine.attach(players[i])
            engine.attach(eqs[i])
            engine.attach(playerMixers[i])
            configureEQ(eqs[i])
            // Chaque lecteur : player -> egaliseur -> mixeur dedie -> sous-mixeur commun.
            // player->eq->mixeurDedie seront reconnectes au format du fichier dans load().
            engine.connect(players[i], to: eqs[i], format: mixFormat)
            engine.connect(eqs[i], to: playerMixers[i], format: mixFormat)
            // mixeurDedie -> sous-mixeur : connexion FIXE au format commun, jamais touchee.
            engine.connect(playerMixers[i], to: subMixer, format: mixFormat)
        }

        engine.connect(subMixer, to: bassBoost, format: mixFormat)
        engine.connect(bassBoost, to: reverb, format: mixFormat)
        engine.connect(reverb, to: engine.mainMixerNode, format: mixFormat)

        engine.prepare()
        try? engine.start()
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
        bassBoost.bands[0].gain = bassBoostEnabled ? bassBoostAmount : 0
    }

    private func applyReverb() {
        if let preset = reverbOption.preset {
            reverb.loadFactoryPreset(preset)
            reverb.wetDryMix = reverbAmount
        } else {
            reverb.wetDryMix = 0
        }
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

    private func configureSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default)
        try? session.setActive(true)
    }

    // MARK: - Lecture d'une file

    // Lance la lecture d'une liste de morceaux a partir d'un index donne.
    func play(tracks: [Track], startAt index: Int) {
        guard !tracks.isEmpty, index >= 0, index < tracks.count else { return }
        queue = tracks
        queueIndex = index
        isCrossfading = false
        load(track: tracks[index], intoPlayer: activeIndex, startFrame: 0, autoPlay: true)
    }

    func playSingle(_ track: Track, in context: [Track]) {
        if let idx = context.firstIndex(of: track) {
            play(tracks: context, startAt: idx)
        } else {
            play(tracks: [track], startAt: 0)
        }
    }

    // Charge un morceau dans l'un des deux lecteurs et (optionnellement) demarre.
    private func load(track: Track, intoPlayer i: Int, startFrame: AVAudioFramePosition, autoPlay: Bool) {
        guard let lib = library else { return }
        let url = lib.url(for: track)
        guard let file = try? AVAudioFile(forReading: url) else {
            // Fichier illisible (format non supporte, ex. .opus) : on saute au suivant,
            // mais on s'arrete si toute la file est illisible pour ne pas boucler.
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

        // IMPORTANT : on ne reconfigure PAS le graphe ici. Il est cable une seule fois
        // (au format fixe `mixFormat`) dans setupEngine(). `scheduleSegment` convertit
        // automatiquement le fichier (frequence d'echantillonnage ET canaux) vers ce
        // format. Reconnecter/disconnecter pendant que le moteur tourne fait planter
        // AVAudioEngine sur iOS 16+ (UpdateGraphAfterReconfig) -> a proscrire.

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
            duration = track.duration
            players[i].play()
            isPlaying = true
            updateNowPlaying()
        }
    }

    // Fin naturelle d'un morceau (signalee par le callback de planification).
    private func handlePlaybackFinished(player i: Int, generation gen: Int) {
        // On ignore les callbacks perimes (seek, crossfade, changement de piste).
        guard gen == generations[i] else { return }
        guard i == activeIndex, !isCrossfading else { return }
        advanceAtEnd()
    }

    // MARK: - Transport

    func togglePlayPause() { isPlaying ? pause() : resume() }

    func pause() {
        players[activeIndex].pause()
        if isCrossfading { players[1 - activeIndex].pause() }
        isPlaying = false
        updateNowPlaying()
    }

    func resume() {
        if !engine.isRunning { try? engine.start() }
        players[activeIndex].play()
        if isCrossfading { players[1 - activeIndex].play() }
        isPlaying = true
        updateNowPlaying()
    }

    func next() {
        cancelCrossfade()
        guard !queue.isEmpty else { return }
        if repeatMode == .one {
            restartCurrent()
            return
        }
        var newIndex = queueIndex + 1
        if shuffleEnabled, queue.count > 1 {
            newIndex = randomOtherIndex()
        }
        if newIndex >= queue.count {
            if repeatMode == .all { newIndex = 0 } else { stopPlayback(); return }
        }
        queueIndex = newIndex
        load(track: queue[newIndex], intoPlayer: activeIndex, startFrame: 0, autoPlay: true)
    }

    func previous() {
        cancelCrossfade()
        // Comportement classique : si on est au-dela de 3 s, on revient au debut.
        if currentTime > 3 {
            restartCurrent()
            return
        }
        guard !queue.isEmpty else { return }
        var newIndex = queueIndex - 1
        if newIndex < 0 {
            newIndex = repeatMode == .all ? queue.count - 1 : 0
        }
        queueIndex = newIndex
        load(track: queue[newIndex], intoPlayer: activeIndex, startFrame: 0, autoPlay: true)
    }

    private func advanceAtEnd() {
        if stopAfterCurrentTrack {
            stopPlayback()
            stopAfterCurrentTrack = false
            onAutoStop?()
            return
        }
        if repeatMode == .one { restartCurrent(); return }
        var newIndex = queueIndex + 1
        if shuffleEnabled, queue.count > 1 { newIndex = randomOtherIndex() }
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

    private func randomOtherIndex() -> Int {
        guard queue.count > 1 else { return queueIndex }
        var idx = queueIndex
        while idx == queueIndex { idx = Int.random(in: 0..<queue.count) }
        return idx
    }

    private func stopPlayback() {
        players.forEach { $0.stop() }
        isPlaying = false
        currentTime = 0
        updateNowPlaying()
    }

    // MARK: - Recherche de position (seek)

    func seek(to time: Double) {
        guard let file = files[activeIndex] else { return }
        let sr = file.processingFormat.sampleRate
        let frame = AVAudioFramePosition(max(0, time) * sr)
        guard let track = currentTrack else { return }
        cancelCrossfade()
        let wasPlaying = isPlaying
        load(track: track, intoPlayer: activeIndex, startFrame: frame, autoPlay: true)
        if !wasPlaying { pause() }
        currentTime = time
    }

    // MARK: - Crossfade

    private func startCrossfade(to track: Track) {
        let newPlayer = 1 - activeIndex
        isCrossfading = true
        // Charge la piste suivante en sourdine sur l'autre lecteur, sans la rendre active.
        load(track: track, intoPlayer: newPlayer, startFrame: 0, autoPlay: false)
        players[newPlayer].volume = 0
        players[newPlayer].play()

        let oldPlayer = activeIndex
        // L'ancien lecteur reste actif pour le suivi du temps jusqu'a bascule.
        let steps = 40
        let interval = crossfadeDuration / Double(steps)
        var step = 0
        fadeTimer?.invalidate()
        fadeTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] timer in
            Task { @MainActor in
                guard let self else { timer.invalidate(); return }
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
    }

    private func finishCrossfade(newPlayer: Int, track: Track) {
        players[activeIndex].stop()
        activeIndex = newPlayer
        currentTrack = track
        duration = track.duration
        isPlaying = true
        isCrossfading = false
        // Avance l'index logique de la file.
        if let idx = queue.firstIndex(of: track) { queueIndex = idx }
        updateNowPlaying()
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

    // Piste qui suivra dans la file (pour preparer le crossfade).
    private func upcomingTrack() -> Track? {
        guard !queue.isEmpty else { return nil }
        if repeatMode == .one { return nil }
        if shuffleEnabled { return nil } // pas de crossfade fiable en aleatoire
        let nextIdx = queueIndex + 1
        if nextIdx < queue.count { return queue[nextIdx] }
        if repeatMode == .all { return queue.first }
        return nil
    }

    // MARK: - Tic d'horloge (mise a jour du temps + declenchement crossfade)

    private func startTicker() {
        ticker = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    private func tick() {
        guard isPlaying, let file = files[activeIndex] else { return }
        // L'offset de depart est exprime en frames du FICHIER ; la position rendue par
        // le lecteur est exprimee a la frequence de rendu du moteur (mixFormat).
        let fileSR = file.processingFormat.sampleRate
        let renderSR = mixFormat.sampleRate
        var t = Double(startFrames[activeIndex]) / fileSR
        if let nodeTime = players[activeIndex].lastRenderTime,
           let playerTime = players[activeIndex].playerTime(forNodeTime: nodeTime) {
            t += Double(playerTime.sampleTime) / renderSR
        }
        currentTime = min(t, duration > 0 ? duration : t)

        // Declenchement du crossfade.
        if crossfadeDuration > 0, !isCrossfading, duration > 0 {
            let remaining = duration - currentTime
            if remaining <= crossfadeDuration, remaining > 0.1, let nextTrack = upcomingTrack() {
                startCrossfade(to: nextTrack)
            }
        }
        updateNowPlayingElapsed()
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
            MPMediaItemPropertyPlaybackDuration: track.duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0
        ]
        if let image = library?.artworkImage(for: track) {
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func updateNowPlayingElapsed() {
        guard var info = MPNowPlayingInfoCenter.default().nowPlayingInfo else { return }
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    // MARK: - Interruptions (appels, autres apps)

    private func observeInterruptions() {
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil, queue: .main) { [weak self] note in
            Task { @MainActor in self?.handleInterruption(note) }
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
}
