import Foundation
import Combine

// Minuteur de sommeil : met la lecture en pause apres un delai
// ou a la fin du morceau en cours.
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
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.remaining -= 1
                if self.remaining <= 0 {
                    self.engine?.pause()
                    self.cancel()
                }
            }
        }
    }

    func cancel() {
        timer?.invalidate()
        timer = nil
        isActive = false
        stopAtEndOfTrack = false
        remaining = 0
        engine?.stopAfterCurrentTrack = false
    }

    var remainingString: String {
        let total = Int(remaining)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
