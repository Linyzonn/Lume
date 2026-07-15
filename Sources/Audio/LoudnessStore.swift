import Foundation
import AVFoundation

// MARK: - Volume homogene (normalisation du niveau entre morceaux)
//
// PRINCIPE : chaque fichier est mesure UNE FOIS (niveau moyen RMS, en dBFS),
// le resultat est memorise sur disque (loudness.json). A la lecture, les
// morceaux plus forts que la reference sont simplement ATTENUES en reglant
// le volume du mixeur de leur lecteur.
//
// GARANTIES QUALITE (exigence explicite du projet) :
//  - aucune compression ni traitement dynamique : le signal est multiplie
//    par une constante, exactement comme baisser le volume ;
//  - attenuation uniquement, jamais d'amplification -> aucune saturation
//    possible (le limiteur en bout de chaine n'est meme pas sollicite) ;
//  - le gain est fige AVANT la lecture d'un morceau et ne change JAMAIS en
//    cours de lecture.
final class LoudnessStore: @unchecked Sendable {
    static let shared = LoudnessStore()

    // Niveau de reference vise (RMS, dBFS). Les morceaux au-dessus sont
    // ramenes vers ce niveau ; ceux en dessous restent tels quels.
    static let referenceRMS: Double = -16
    // Attenuation maximale appliquee (garde-fou).
    static let maxAttenuationDB: Double = 12

    private let file: URL
    private let lock = NSLock()
    private var values: [String: Double]        // fileName -> RMS mesure (dBFS)
    private var inProgress = Set<String>()      // mesures deja en file
    // File SERIELLE de mesure : un fichier a la fois, priorite basse —
    // l'analyse d'une grosse bibliotheque ne sature ni le CPU ni le disque.
    private let analysisQueue = DispatchQueue(label: "lume.loudness", qos: .utility)

    private init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Lume", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        file = dir.appendingPathComponent("loudness.json")
        if let data = try? Data(contentsOf: file),
           let decoded = try? JSONDecoder().decode([String: Double].self, from: data) {
            values = decoded
        } else {
            values = [:]
        }
    }

    // Gain lineaire (0...1) a appliquer au morceau, ou nil si pas encore mesure.
    func gain(forFileName name: String) -> Float? {
        lock.lock(); defer { lock.unlock() }
        guard let rms = values[name] else { return nil }
        let gainDB = max(-Self.maxAttenuationDB, min(0, Self.referenceRMS - rms))
        return Float(pow(10.0, gainDB / 20.0))
    }

    func hasMeasurement(forFileName name: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return values[name] != nil
    }

    // Mesure le niveau d'un fichier si ce n'est pas deja fait, en arriere-plan.
    // `onMeasured` est execute sur le thread principal UNIQUEMENT si une
    // nouvelle mesure a abouti.
    func measureIfNeeded(url: URL, fileName: String, onMeasured: (() -> Void)? = nil) {
        lock.lock()
        let alreadyHandled = values[fileName] != nil || inProgress.contains(fileName)
        if !alreadyHandled { inProgress.insert(fileName) }
        lock.unlock()
        guard !alreadyHandled else { return }

        analysisQueue.async { [weak self] in
            guard let self else { return }
            let rms = Self.measureRMS(url: url)
            self.lock.lock()
            self.inProgress.remove(fileName)
            if let rms { self.values[fileName] = rms }
            let snapshot = self.values
            self.lock.unlock()
            guard rms != nil else { return }
            if let data = try? JSONEncoder().encode(snapshot) {
                try? data.write(to: self.file, options: .atomic)
            }
            if let onMeasured {
                DispatchQueue.main.async(execute: onMeasured)
            }
        }
    }

    // Oublie la mesure d'un fichier supprime (le JSON ne grossit pas a vide).
    func forget(fileName: String) {
        lock.lock()
        let removed = values.removeValue(forKey: fileName) != nil
        let snapshot = values
        lock.unlock()
        guard removed, let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: file, options: .atomic)
    }

    // Niveau moyen (RMS) d'un fichier audio, en dBFS. Lecture complete par
    // blocs (~0,3 s pour un titre de 4 min), 1 echantillon sur 4 (largement
    // suffisant pour une moyenne d'energie).
    nonisolated static func measureRMS(url: URL) -> Double? {
        guard let file = try? AVAudioFile(forReading: url), file.length > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                            frameCapacity: 131_072) else { return nil }
        var sum: Double = 0
        var count: Double = 0
        while true {
            do { try file.read(into: buffer, frameCount: 131_072) } catch { break }
            let n = Int(buffer.frameLength)
            if n == 0 { break }
            guard let data = buffer.floatChannelData?[0] else { break }
            var i = 0
            while i < n {
                let v = Double(data[i])
                sum += v * v
                count += 1
                i += 4
            }
        }
        guard count > 0, sum > 0 else { return nil }
        return 10 * log10(sum / count)
    }
}
