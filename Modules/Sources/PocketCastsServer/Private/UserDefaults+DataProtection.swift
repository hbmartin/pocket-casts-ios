import Foundation
import Synchronization
import UIKit

extension UserDefaults {
    /// Callable from any thread; off-main callers read the latest main-thread snapshot.
    static func isProtectedDataAvailable() -> Bool? {
        ProtectedDataAvailability.shared.currentValue()
    }
}

private final class ProtectedDataAvailability: NSObject, Sendable {
    static let shared = ProtectedDataAvailability()

    private struct State {
        var cachedValue: Bool?
        var observersInstalled = false
        var refreshScheduled = false
    }

    private let state = Mutex(State())

    func currentValue() -> Bool? {
        installObserversIfNeeded()

        if Thread.isMainThread {
            return refreshFromUIApplicationOnMain()
        }

        let value = cached()
        scheduleRefresh()
        return value
    }

    private func installObserversIfNeeded() {
        let alreadyInstalled = state.withLock { state in
            defer { state.observersInstalled = true }
            return state.observersInstalled
        }
        guard !alreadyInstalled else {
            return
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(protectedDataDidBecomeAvailable),
            name: UIApplication.protectedDataDidBecomeAvailableNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(protectedDataWillBecomeUnavailable),
            name: UIApplication.protectedDataWillBecomeUnavailableNotification,
            object: nil
        )

        scheduleRefresh()
    }

    @objc private func protectedDataDidBecomeAvailable() {
        setCachedValue(true)
    }

    @objc private func protectedDataWillBecomeUnavailable() {
        setCachedValue(false)
    }

    private func cached() -> Bool? {
        state.withLock { $0.cachedValue }
    }

    private func scheduleRefresh() {
        let alreadyScheduled = state.withLock { state in
            defer { state.refreshScheduled = true }
            return state.refreshScheduled
        }
        guard !alreadyScheduled else {
            return
        }

        DispatchQueue.main.async { [weak self] in
            self?.refreshFromUIApplicationOnMain()
        }
    }

    @discardableResult
    private func refreshFromUIApplicationOnMain() -> Bool {
        let value = MainActor.assumeIsolated {
            UIApplication.shared.isProtectedDataAvailable
        }
        setCachedValue(value)
        return value
    }

    private func setCachedValue(_ value: Bool) {
        state.withLock {
            $0.cachedValue = value
            $0.refreshScheduled = false
        }
    }
}
