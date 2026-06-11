import Foundation

// @unchecked Sendable: `timer` and `action` are only accessed on the main thread, while
// `timerValid` is guarded by `lock`.
public final class TimedActionHelper: @unchecked Sendable {
    private let lock = NSLock()
    private var timer: Timer?
    private var timerValid = false

    private var action: (() -> Void)?

    public init() {}

    public func startTimer(for time: TimeInterval, action: @escaping () -> Void) {
        let action = UncheckedSendable(action)
        if Thread.isMainThread {
            performStartTimer(for: time, action: action.value)
        } else {
            DispatchQueue.main.sync { [weak self] in
                self?.performStartTimer(for: time, action: action.value)
            }
        }
    }

    public func cancelTimer() {
        if Thread.isMainThread {
            performCancelTimer()
        } else {
            DispatchQueue.main.sync { [weak self] in
                self?.performCancelTimer()
            }
        }
    }

    public func isTimerValid() -> Bool {
        lock.lock()
        defer { lock.unlock() }

        return timerValid
    }

    private func performStartTimer(for time: TimeInterval, action: @escaping () -> Void) {
        performCancelTimer()
        self.action = action

        // Timers need to run on a thread that has a runloop, the easiest one being the main thread so we use that here
        timer = Timer.scheduledTimer(timeInterval: time, target: self, selector: #selector(timerFired), userInfo: nil, repeats: false)
        setTimerValid(true)
    }

    private func performCancelTimer() {
        // a Timer must always be invalidated from the thread it was created on, in our case being the main thread
        timer?.invalidate()
        timer = nil
        action = nil
        setTimerValid(false)
    }

    @objc private func timerFired() {
        let action = action
        self.action = nil
        timer = nil
        setTimerValid(false)
        action?()
    }

    private func setTimerValid(_ valid: Bool) {
        lock.lock()
        timerValid = valid
        lock.unlock()
    }
}
