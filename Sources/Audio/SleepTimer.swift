import Foundation
import Combine

// Minuteur de sommeil : met la lecture en pause apres un delai
// ou a la fin du morceau en cours. Les 15 dernieres secondes baissent
// progressivement le volume (fondu) pour ne pas couper le son d'un coup.
@MainActor
final class SleepTimer: ObservableObject {
    @Published var isActive = false
    @Published var remaining: TimeInterval = 0
    @Published var stopAtEndOfTrack = false

    private var timer: Timer?
    private weak var engine: PlayerEngine?

    func attach(_ engine: PlayerEngine) { self.engine = engine }

    // delaiMinutes = nombre de minutes ; si endOfTrack, on coupe a la fin du titre.
    func start(minutes: Int, endOfTrack: Bool = false) {
        cancel()
        if endOfTrack {
            stopAtEndOfTrack = true
            isActive = true
            engine?.stopAfterCurrentTrack = true
            engine?.onAutoStop = { [weak self] in self?.cancel() }
            return
        }
        remaining = TimeInterval(minutes * 60)
        isActive = true
        // Mode .common : en .default le timer serait gele pendant un scroll
        // (decompte fige tant qu'un doigt touche l'ecran).
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.remaining -= 1
                if self.remaining <= 0 {
                    self.engine?.pause()
                    self.engine?.setOutputVolume(1)   // volume retabli pour la prochaine ecoute
                    self.cancel()
                } else if self.remaining <= 15 {
                    // Fondu de fin : de 100 % a 0 % sur les 15 dernieres secondes.
                    self.engine?.setOutputVolume(Float(self.remaining) / 15)
                }
            }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func cancel() {
        timer?.invalidate()
        timer = nil
        isActive = false
        stopAtEndOfTrack = false
        remaining = 0
        engine?.stopAfterCurrentTrack = false
        engine?.setOutputVolume(1)
    }

    var remainingString: String {
        let total = Int(remaining)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
