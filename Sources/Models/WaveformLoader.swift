import Foundation
import AVFoundation

// MARK: - Forme d'onde
//
// Calcule l'enveloppe d'amplitude d'un fichier audio : une liste de valeurs
// 0...1 (une par "barre") representant le volume au fil du morceau. Utilisee
// par la barre de lecture du lecteur : on VOIT les passages calmes et les
// refrains, et on peut viser directement un moment precis.
//
// Le calcul lit tout le fichier une fois (0,2 a 0,5 s pour un titre de
// 4 min) : il est donc fait en arriere-plan et mis en cache en memoire.
enum WaveformLoader {

    private static let cache = NSCache<NSString, NSArray>()

    // `cacheKey` : identifiant stable du fichier (son nom sur disque).
    nonisolated static func waveform(for url: URL, cacheKey: String, buckets: Int = 64) -> [Float]? {
        if let cached = cache.object(forKey: cacheKey as NSString) as? [Float] {
            return cached
        }
        guard buckets > 2, let file = try? AVAudioFile(forReading: url) else { return nil }
        let totalFrames = Int(file.length)
        guard totalFrames > buckets else { return nil }
        let framesPerBucket = max(1, totalFrames / buckets)

        var peaks = [Float](repeating: 0, count: buckets)
        let chunkSize: AVAudioFrameCount = 131_072
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                            frameCapacity: chunkSize) else { return nil }

        var frameIndex = 0
        while frameIndex < totalFrames {
            do { try file.read(into: buffer, frameCount: chunkSize) } catch { break }
            let n = Int(buffer.frameLength)
            if n == 0 { break }
            if let data = buffer.floatChannelData?[0] {
                // 1 echantillon sur 32 suffit largement pour une enveloppe.
                var i = 0
                while i < n {
                    let bucket = min(buckets - 1, (frameIndex + i) / framesPerBucket)
                    let v = abs(data[i])
                    if v > peaks[bucket] { peaks[bucket] = v }
                    i += 32
                }
            }
            frameIndex += n
        }

        let maxV = peaks.max() ?? 0
        guard maxV > 0.001 else { return nil }
        // Normalisation + plancher visuel (une barre reste toujours visible)
        var out = peaks.map { max(0.12, $0 / maxV) }
        // Petit lissage pour un rendu moins nerveux
        if out.count > 2 {
            for i in 1..<(out.count - 1) {
                out[i] = (out[i - 1] + out[i] * 2 + out[i + 1]) / 4
            }
        }
        cache.setObject(out as NSArray, forKey: cacheKey as NSString)
        return out
    }
}
