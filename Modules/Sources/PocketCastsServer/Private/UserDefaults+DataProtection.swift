import Foundation
import UIKit

extension UserDefaults {
    /// Callable from any thread; off-main callers read the latest main-thread snapshot.
    static func isProtectedDataAvailable() -> Bool? {
        ProtectedDataAvailability.shared.currentValue()
    }
}

private final class ProtectedDataAvailability: @unchecked Sendable {
    static let shared = ProtectedDataAvailability()

    private let lock = NSLock()
    private var cachedValue: Bool?
    private var observersInstalled = false
    private var refreshScheduled = false
    private var notificationObservers = [NSObjectProtocol]()

    deinit {
        notificationObservers.forEach(NotificationCenter.default.removeObserver)
    }

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
        lock.lock()
        guard !observersInstalled else {
            lock.unlock()
            return
        }
        observersInstalled = true
        lock.unlock()

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

        lock.lock()
        notificationObservers = [didBecomeAvailable, willBecomeUnavailable]
        lock.unlock()

        scheduleRefresh()
    }

    private func cached() -> Bool? {
        lock.lock()
        defer { lock.unlock() }

        return cachedValue
    }

    private func scheduleRefresh() {
        lock.lock()
        guard !refreshScheduled else {
            lock.unlock()
            return
        }
        refreshScheduled = true
        lock.unlock()

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
        lock.lock()
        cachedValue = value
        refreshScheduled = false
        lock.unlock()
    }
}
