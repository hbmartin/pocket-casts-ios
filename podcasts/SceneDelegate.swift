import AVFoundation
import JLRoutes
import UIKit
import PocketCastsUtils

class SceneDelegate: UIResponder, UISceneDelegate, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = (scene as? UIWindowScene) else { return }

        let window = UIWindow(windowScene: windowScene)
        self.window = window
        window.rootViewController = MainTabBarController()

        // Capture the system style before applying any window-level override so the
        // initial value reflects the actual system, not our override.
        Theme.systemIsDark = (windowScene.traitCollection.userInterfaceStyle == .dark)
        window.applyInterfaceStyleForActiveTheme()
        NotificationCenter.default.addObserver(self, selector: #selector(themeDidChange), name: Constants.Notifications.themeChanged, object: nil)

        window.makeKeyAndVisible()

        #if DEBUG
        MediaConcurrencyUITestHarness.exerciseIfRequested()
        #endif

        if let shortcutItem = connectionOptions.shortcutItem {
            appDelegate()?.handleShortcutItem(shortcutItem)
        }
        if let url = connectionOptions.urlContexts.first?.url, let rootViewController = window.rootViewController {
            _ = appDelegate()?.handleOpenUrl(url: url, rootViewController: rootViewController)
        }
        if let userActivity = connectionOptions.userActivities.first {
            appDelegate()?.handleContinue(userActivity)
        }
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        appDelegate()?.handleBecomeActive()
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        appDelegate()?.handleEnterBackground()
    }

    func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
        appDelegate()?.handleContinue(userActivity)
    }

    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        guard !URLContexts.isEmpty, let url = URLContexts.first?.url, let rootViewController = window?.rootViewController else {
            return
        }
        _ = appDelegate()?.handleOpenUrl(url: url, rootViewController: rootViewController)
    }

    func windowScene(_ windowScene: UIWindowScene,
                     performActionFor shortcutItem: UIApplicationShortcutItem,
                     completionHandler: @escaping (Bool) -> Void) {
        appDelegate()?.handleShortcutItem(shortcutItem)
    }

    @objc private func themeDidChange() {
        window?.applyInterfaceStyleForActiveTheme()
    }
}

#if DEBUG
/// Debug-only app-side driver for deterministic XCUITest coverage of APIs that
/// are called by system frameworks from background threads.
@MainActor
enum MediaConcurrencyUITestHarness {
    private static let artworkEnvironment = "POCKET_CASTS_UI_TEST_EXERCISE_ARTWORK_HANDLERS"
    private static let audioSessionEnvironment = "POCKET_CASTS_UI_TEST_EXERCISE_AUDIO_SESSION_NOTIFICATIONS"
    private static let artworkCompletedIdentifier = "mediaConcurrencyArtworkHandlersCompleted"
    private static let artworkFailedIdentifier = "mediaConcurrencyArtworkHandlersFailed"
    private static let audioSessionCompletedIdentifier = "mediaConcurrencyAudioSessionNotificationsCompleted"
    private static var handledAudioSessionNotifications = Set<Notification.Name>()

    private static let expectedAudioSessionNotifications: Set<Notification.Name> = [
        AVAudioSession.routeChangeNotification,
        AVAudioSession.interruptionNotification,
        AVAudioSession.mediaServicesWereResetNotification
    ]

    static func exerciseIfRequested() {
        let environment = ProcessInfo.processInfo.environment

        if environment[artworkEnvironment] == "1" {
            NowPlayingHelper.exerciseArtworkRequestHandlersForUITesting()
        }

        if environment[audioSessionEnvironment] == "1" {
            // Initialize the live coordinator before posting its system notifications.
            _ = PlaybackManager.shared
            postAudioSessionNotificationsOffMain()
        }
    }

    static func artworkRequestHandlersCompleted(succeeded: Bool) {
        guard ProcessInfo.processInfo.environment[artworkEnvironment] == "1" else { return }
        addMarker(identifier: succeeded ? artworkCompletedIdentifier : artworkFailedIdentifier)
    }

    static func audioSessionNotificationHandled(_ name: Notification.Name) {
        guard ProcessInfo.processInfo.environment[audioSessionEnvironment] == "1" else { return }

        handledAudioSessionNotifications.insert(name)
        if expectedAudioSessionNotifications.isSubset(of: handledAudioSessionNotifications) {
            addMarker(identifier: audioSessionCompletedIdentifier)
        }
    }

    private static func postAudioSessionNotificationsOffMain() {
        let notificationCenter = NotificationCenter.default
        Task {
            await Task.detached {
                notificationCenter.post(name: AVAudioSession.routeChangeNotification, object: nil)
                notificationCenter.post(name: AVAudioSession.interruptionNotification, object: nil)
                notificationCenter.post(name: AVAudioSession.mediaServicesWereResetNotification, object: nil)
            }.value
        }
    }

    private static func addMarker(identifier: String) {
        guard let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap(\.windows)
            .first(where: \.isKeyWindow),
              !window.subviews.contains(where: { $0.accessibilityIdentifier == identifier }) else { return }

        let marker = UIView(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
        marker.isAccessibilityElement = true
        marker.accessibilityIdentifier = identifier
        window.addSubview(marker)
    }
}
#endif
