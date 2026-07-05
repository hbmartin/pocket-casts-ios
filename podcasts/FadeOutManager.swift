import Foundation

/// Volume fade driven by a repeating timer; owned and driven by the sleep timer flow.
@MainActor
final class FadeOutManager {
    weak var player: PlaybackProtocol?

    private var timer: Timer?

    private let volumeChangesPerSecond = 30.0
    private var currentChange = 0.0
    private var fadeDuration = 5.0
    private let fadeVelocity = 2.0
    private let fromVolume = 1.0
    private let toVolume = 0.0
    private var totalNumberOfVolumeChanges = 0.0
    private lazy var timerDelay = 1.0 / volumeChangesPerSecond


    /// Performs a fade out on the given `PlaybackProtocol` by using a logarithmic algorithm
    /// This way the final results is smooth 🧈 to the human's hearing 👂
    /// - Parameter duration: the duration of the fade out effect
    func fadeOut(duration: TimeInterval) {
        fadeDuration = duration
        currentChange = 0
        totalNumberOfVolumeChanges = fadeDuration * volumeChangesPerSecond
        timer = Timer.scheduledTimer(withTimeInterval: TimeInterval(timerDelay), repeats: true) { [weak self] _ in
            // scheduled from the main actor, so the timer fires on the main run loop
            MainActor.assumeIsolated {
                guard let self,
                      self.currentChange < self.totalNumberOfVolumeChanges else {
                    self?.timer?.invalidate()
                    return
                }

                let normalizedTime = (self.currentChange / self.totalNumberOfVolumeChanges).betweenZeroAndOne
                let volumeMultiplier = pow(M_E, -self.fadeVelocity * normalizedTime) * (1 - normalizedTime)
                let newVolume = self.toVolume - (self.toVolume - self.fromVolume) * volumeMultiplier

                self.player?.playing() == true ? self.player?.setVolume(Float(newVolume)) : self.timer?.invalidate()

                self.currentChange += 1
            }
        }
    }
}

private extension Double {
    var betweenZeroAndOne: Double {
        max(0, min(1, self))
    }
}
