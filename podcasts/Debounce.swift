import Foundation
import PocketCastsUtils

class Debounce {
    private let delay: Double
    private weak var timer: Timer?

    init(delay: TimeInterval) {
        self.delay = delay
    }

    func call(_ callback: @escaping (() -> Void)) {
        timer?.invalidate()
        let boxed = PocketCastsUtils.UncheckedSendable(callback)
        timer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { _ in
            boxed.value()
        }
    }

    func cancel() {
        timer?.invalidate()
    }
}
