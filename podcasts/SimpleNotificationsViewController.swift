import UIKit

class SimpleNotificationsViewController: UIViewController {
    private var customObservers = [Notification.Name]()
    private var messageTokens = [Notification.Name: NotificationCenter.ObservationToken]()

    func addCustomObserver(_ name: Notification.Name, selector: Selector) {
        if containsObserver(name) { return } // we already have this one

        customObservers.append(name)

        NotificationCenter.default.addObserver(self, selector: selector, name: name, object: nil)
    }

    /// Typed-message registration; same register-in-viewWillAppear /
    /// remove-in-viewWillDisappear lifecycle and dedupe-by-name behavior as the
    /// selector-based variant above.
    func addCustomObserver<M: NotificationCenter.MainActorMessage>(_ type: M.Type, handler: @escaping @MainActor (M) -> Void) {
        guard messageTokens[M.name] == nil else { return } // we already have this one

        messageTokens[M.name] = NotificationCenter.default.addObserver(for: type, using: handler)
    }

    func removeAllCustomObservers() {
        let notCenter = NotificationCenter.default
        for name in customObservers {
            notCenter.removeObserver(self, name: name, object: nil)
        }
        customObservers.removeAll()

        for token in messageTokens.values {
            notCenter.removeObserver(token)
        }
        messageTokens.removeAll()
    }

    private func containsObserver(_ name: Notification.Name) -> Bool {
        if customObservers.isEmpty { return false }

        return customObservers.contains(name)
    }
}
