import Foundation
import PocketCastsUtils
import PocketCastsServer

/// Listens for the user sign out notification and if it was not user initiated then we'll show
/// and alert to the user asking them to sign in again
@MainActor
class BackgroundSignOutListener {
    // Explicitly nonisolated: default-MainActor synthesized deinits hop executors and crash sync XCTests (swiftlang/swift#87316).
    // Property reads must precede any call that copies self; a nonisolated deinit may read stored state directly.
    nonisolated deinit {
        let token = signOutToken
        let center = notificationCenter
        if let token {
            center.removeObserver(token)
        }
    }

    private let notificationCenter: NotificationCenter
    private let navigationManager: NavigationManager

    private var presentingViewController: () -> UIViewController?

    private var canShowSignOut = true

    private var signOutToken: NotificationCenter.ObservationToken?

    init(notificationCenter: NotificationCenter = NotificationCenter.default,
         navigationManager: NavigationManager = NavigationManager.sharedManager,
         presentingViewController: @autoclosure @escaping () -> UIViewController?) {
        self.notificationCenter = notificationCenter
        self.navigationManager = navigationManager
        self.presentingViewController = presentingViewController

        addNotificationObservers()
    }

    func showSignIn() {
        canShowSignOut = true
        navigationManager.navigateTo(NavigationManager.onboardingFlow, data: ["flow": OnboardingFlow.Flow.forcedLoggedOut])
    }
}

// MARK: - Private: Notifications

private extension BackgroundSignOutListener {
    func addNotificationObservers() {
        signOutToken = notificationCenter.addObserver(for: UserWillBeSignedOut.self) { [weak self] message in
            self?.handleSignOut(message)
        }
    }

    func handleSignOut(_ message: UserWillBeSignedOut) {
        guard message.userInitiated == false else {
            return
        }

        showAlertIfPossible()
    }
}

// MARK: - Alert Showing

private extension BackgroundSignOutListener {
    func showAlertIfPossible() {
        // If we're already showing the sign out then don't try to show it again
        guard canShowSignOut else {
            return
        }

        canShowSignOut = false

        Analytics.track(.signedOutAlertShown)

        let alert = UIAlertController(title: L10n.accountSignedOutAlertTitle, message: L10n.accountSignedOutAlertMessage, preferredStyle: .alert)

        let okAction = UIAlertAction(title: L10n.signIn, style: .default, handler: { [weak self] _ in
            self?.showSignIn()
        })

        alert.addAction(okAction)

        presentingViewController()?.present(alert, animated: true, completion: nil)
    }
}
