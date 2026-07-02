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

    // Boost de volume : amplification appliquee APRES le volume systeme.
    // 0 = 100 % (volume systeme normal), 0.5 = +50 % (soit 150 %).
    @Published var volumeBoost: Float = 0 { didSet { applyVolumeBoost() } }

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
                // Courbe chaleureuse : graves profonds, aigus aeres.
                return ([4,3,2,1,0,0,1,2,3,3], true, 5, .off, 0)
            case .speaker:
                // Petit HP d'iPhone : on coupe le sub inutile, on pousse clarte et presence.
                return ([-6,-4,-1,0,1,2,3,3,2,1], true, 0, .off, 0)
            case .plane:
                // Avion + casque antibruit : le grondement residuel des reacteurs
                // (bruit grave que meme l'ANC ne supprime pas totalement) masque
                // les basses et le bas-medium. On compense : graves renforces,
                // creux vers 250 Hz (zone du grondement), presence vocale relevee
                // pour garder les voix intelligibles sans monter le volume.
                return ([5,4,2,-1,0,1,2,3,2,1], true, 5, .off, 0)
            case .car:
                // Enceintes de voiture : le bruit de roulement mange voix et
                // details. Basses fermes (sans exces, les voitures en ont deja),
                // mediums/presence en avant pour la clarte a vitesse de croisiere.
                return ([2,3,1,0,1,2,3,3,2,1], true, 3, .off, 0)
            case .concert:
                // Sensation live SUBTILE : leger renfort des graves et de l'air,
                // petite salle a faible dose. (L'ancien reglage — grande salle a
                // 45 % — noyait tout dans l'echo.)
                return ([3,2,1,0,0,0,1,2,2,2], true, 4, .hall, 18)
            case .voice:
                // Parole nette : medianes en avant, extremes attenues.
                return ([-4,-3,-1,1,3,3,2,1,-1,-2], true, 0, .room, 12)
            }
        }
    }

    // Reference vers la bibliotheque (pour resoudre les URL de fichiers).
    weak var library: LibraryStore?

    // MARK: - Remontee des statistiques d'ecoute (branchee dans RootView)
    // Ecoute complete (fin naturelle ou > 80 % du morceau).
    var onTrackCompleted: ((Track) -> Void)?
    // Morceau passe volontairement avant 80 %.
    var onTrackSkipped: ((Track) -> Void)?
    // Paquet de secondes reellement ecoutees (envoye aux changements de piste/pause).
    var onListenFlush: ((Track, Double) -> Void)?

    // Secondes ecoutees depuis le dernier envoi (accumulees par le tic d'horloge).
    private var listenAccumulator: Double = 0

    private func flushListenTime() {
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
    // Un mixeur dedie par lecteur : il "absorbe" le format du fichier (qui peut
    // varier d'un morceau a l'autre) et ressort TOUJOURS au format fixe `mixFormat`.
    // Ainsi, charger un nouveau morceau ne reconfigure jamais le mixeur partage ni
    // la sortie -> plus de crash AVAudioEngine sur iOS 16+.
    private let playerMixers = [AVAudioMixerNode(), AVAudioMixerNode()]
    // Format de travail commun a tout l'etage partage (la sortie convertira si besoin).
    private let mixFormat = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!
    private let subMixer = AVAudioMixerNode()                 // somme les deux lecteurs
    // Optimiseur de basses a DEUX bandes : un plateau bas (assise) + une bosse
    // vers 60 Hz (punch). L'ancienne version (un seul plateau a 110 Hz) etait
    // peu audible a faible reglage et saturait a fort reglage.
    private let bassBoost = AVAudioUnitEQ(numberOfBands: 2)
    private let reverb = AVAudioUnitReverb()                  // ambiance / concert
    private var files: [AVAudioFile?] = [nil, nil]
    private var startFrames: [AVAudioFramePosition] = [0, 0]
    private var generations: [Int] = [0, 0]
    private var activeIndex = 0
    private var isCrossfading = false
    private var consecutiveLoadFailures = 0

    private var ticker: Timer?
    private var fadeTimer: Timer?
    private var lastTickDate: Date?   // pour un suivi du temps fiable (horloge murale)

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
        let amount = bassBoostEnabled ? bassBoostAmount : 0
        bassBoost.bands[0].gain = amount           // assise (plateau bas)
        bassBoost.bands[1].gain = amount * 0.6     // punch (bosse ~60 Hz)
        // Marge de securite : on abaisse legerement le niveau global du filtre
        // pour eviter que les graves renforces ne fassent saturer la sortie
        // (c'etait la cause du son "sale" a fort boost).
        bassBoost.globalGain = -amount * 0.3
    }

    // Amplifie la sortie au-dela de 100 % (1.0 = normal, 1.5 = +50 %).
    // NOTE : mainMixerNode.outputVolume est PLAFONNE a 1.0 par le systeme,
    // donc l'ancienne methode (1.0 + boost) ne faisait strictement rien.
    // On passe par le gain global des egaliseurs (en dB), qui lui peut
    // reellement amplifier le signal (+3,5 dB ~= +50 %).
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
            // Duree calculee depuis le fichier lui-meme (fiable), avec repli sur la
            // metadonnee si besoin. track.duration vaut souvent 0 -> barre cassee.
            duration = computedDuration(for: i, fallback: track.duration)
            // Position de depart + reamorcage de l'horloge (barre fiable des le debut).
            currentTime = Double(startFrame) / max(1, file.processingFormat.sampleRate)
            lastTickDate = nil
            players[i].play()
            isPlaying = true
            updateNowPlaying()
            persistSession()
        }
    }

    // Duree reelle du fichier charge dans le lecteur i (en secondes).
    private func computedDuration(for i: Int, fallback: Double) -> Double {
        guard let file = files[i] else { return fallback }
        let sr = file.processingFormat.sampleRate
        let secs = sr > 0 ? Double(file.length) / sr : 0
        return secs > 0.1 ? secs : fallback
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
        flushListenTime()
        persistSession()
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
        // Signal de gout : passer un morceau avant 80 % = "j'aime moins",
        // le passer apres 80 % compte comme une ecoute complete.
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
        flushListenTime()
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

    // MARK: - Reprise de session (redemarrage de l'app)

    // Sauvegarde l'etat courant (file, position) pour la reprise au lancement.
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

    // Restaure la derniere session EN PAUSE (jamais de lecture surprise).
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
        if let finished = currentTrack { onTrackCompleted?(finished) }
        flushListenTime()
        players[activeIndex].stop()
        activeIndex = newPlayer
        currentTrack = track
        duration = computedDuration(for: newPlayer, fallback: track.duration)
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
        // IMPORTANT : mode .common. En mode .default (celui de scheduledTimer),
        // le timer est GELE des que l'utilisateur touche l'ecran (scroll, drag,
        // doigt pose) -> la barre de progression semble ne jamais avancer.
        let t = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        ticker = t
    }

    private func tick() {
        guard isPlaying else { lastTickDate = nil; return }
        // 1) Source fiable : l'horloge du lecteur audio lui-meme (suit exactement
        //    ce qui sort des haut-parleurs, aucune derive possible).
        if let t = playbackPosition() {
            if t > duration, duration > 0 {
                // La duree annoncee (en-tete VBR souvent faux sur les fichiers
                // YouTube) etait sous-estimee : on l'etend au lieu de bloquer
                // la barre a 100 % alors que la musique continue.
                duration = t
            }
            // Temps reellement ecoute : delta borne pour ignorer seeks et reprises.
            let delta = t - currentTime
            if delta > 0, delta < 2 { listenAccumulator += delta }
            currentTime = t
            lastTickDate = Date()
            checkCrossfadeAndNowPlaying()
            return
        }
        // 2) Repli : horloge murale (utile la fraction de seconde ou le lecteur
        //    n'a pas encore rendu son premier buffer).
        let now = Date()
        if let last = lastTickDate {
            var t = currentTime + now.timeIntervalSince(last)
            if duration > 0 { t = min(t, duration) }
            currentTime = t
        }
        lastTickDate = now
        checkCrossfadeAndNowPlaying()
    }

    // Position de lecture reelle (secondes), lue sur l'horloge du player actif.
    private func playbackPosition() -> Double? {
        let p = players[activeIndex]
        guard let nodeTime = p.lastRenderTime,
              let playerTime = p.playerTime(forNodeTime: nodeTime),
              playerTime.isSampleTimeValid,
              playerTime.sampleRate > 0 else { return nil }
        let played = max(0, Double(playerTime.sampleTime) / playerTime.sampleRate)
        // Decalage de depart (apres un seek, la lecture commence a startFrame).
        let fileSR = files[activeIndex]?.processingFormat.sampleRate ?? 0
        let offset = fileSR > 0 ? Double(startFrames[activeIndex]) / fileSR : 0
        return offset + played
    }

    private func checkCrossfadeAndNowPlaying() {

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
