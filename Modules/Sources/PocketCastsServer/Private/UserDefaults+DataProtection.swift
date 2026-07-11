import Foundation
import Synchronization
import UIKit

extension UserDefaults {
    /// Callable from any thread; off-main callers read the latest main-thread snapshot.
    static func isProtectedDataAvailable() -> Bool? {
        ProtectedDataAvailability.shared.currentValue()
    }
}

private final class ProtectedDataAvailability: Sendable {
    static let shared = ProtectedDataAvailability()

    private struct State {
        var cachedValue: Bool?
        var observersInstalled = false
        var refreshScheduled = false
        // Block-based observer tokens auto-unregister on dealloc, so they must stay retained
        // for the lifetime of this singleton.
        var notificationObservers = [NSObjectProtocol]()
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

        let notificationCenter = NotificationCenter.default
        let didBecomeAvailable = notificationCenter.addObserver(
            forName: UIApplication.protectedDataDidBecomeAvailableNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.setCachedValue(true)
        }
        let willBecomeUnavailable = notificationCenter.addObserver(
            forName: UIApplication.protectedDataWillBecomeUnavailableNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.setCachedValue(false)
        }

        state.withLock { $0.notificationObservers = [didBecomeAvailable, willBecomeUnavailable] }

        scheduleRefresh()
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
