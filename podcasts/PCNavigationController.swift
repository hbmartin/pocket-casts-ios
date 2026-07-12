import UIKit
import SwiftUI

class PCNavigationController: UINavigationController, UIGestureRecognizerDelegate {
    private var navStyle: ThemeStyle = .secondaryUi01
    private var titleStyle: ThemeStyle = .secondaryText01
    private var iconStyle: ThemeStyle = .secondaryIcon01
    private var themeOverride: Theme.ThemeType?

    init(rootViewController: UIViewController, navStyle: ThemeStyle? = nil, titleStyle: ThemeStyle? = nil, iconStyle: ThemeStyle? = nil, themeOverride: Theme.ThemeType? = nil) {
        super.init(rootViewController: rootViewController)

        if let navStyle { self.navStyle = navStyle }
        if let titleStyle { self.titleStyle = titleStyle }
        if let iconStyle { self.iconStyle = iconStyle }
        self.themeOverride = themeOverride

        updateNavColors()

        themeToken = NotificationCenter.default.addObserver(for: ThemeChanged.self) { [weak self] _ in
            self?.updateNavColors()
        }
    }

    private var themeToken: NotificationCenter.ObservationToken?

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }

    deinit {
        let token = themeToken
        NotificationCenter.default.removeObserver(self)
        if let token {
            NotificationCenter.default.removeObserver(token)
        }
    }

    override func setNavigationBarHidden(_ hidden: Bool, animated: Bool) {
        super.setNavigationBarHidden(hidden, animated: animated)
        enableInteractivePopGestureWorkaround()
    }

    func enableInteractivePopGestureWorkaround() {
        interactivePopGestureRecognizer?.delegate = self
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        viewControllers.count > 1
    }

    private func updateNavColors() {
        // Under Liquid Glass we rely on the system glass nav bar, which derives its
        // title/button colors from the interface style. Force it to match the nav
        // controller's theme override so an always-dark screen like Up Next keeps a
        // light title even after content scrolls under the bar (otherwise the glass
        // renders with the ambient appearance and the title flips to black on scroll).
        if let themeOverride {
            overrideUserInterfaceStyle = themeOverride.isDark ? .dark : .light
        }
    }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        #if APPCLIP
        return .lightContent
        #else
        // it's a little dodgy, but if the full screen player is open, always use a light tab bar
        if appDelegate()?.miniPlayer()?.playerOpenState == .open {
            return .lightContent

        // when using a navigationlink the hosting controller might be generated automatically and will apply the default status bar style
        } else if topViewController is AnyUIHostingViewController, topViewController?.preferredStatusBarStyle == .default {
            return AppTheme.defaultStatusBarStyle()
        } else {
            return topViewController?.preferredStatusBarStyle ?? AppTheme.defaultStatusBarStyle()
        }
        #endif
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)

        topViewController?.viewWillTransition(to: size, with: coordinator)
        NotificationCenter.postOnMainThread(notification: Constants.Notifications.viewWillTransitionToSize, object: NSCoder.string(for: size))
    }

    // MARK: - Orientation

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        if let topViewController {
            return topViewController.supportedInterfaceOrientations
        }

        return .portrait // default to portrait only
    }

    // MARK: - Edge Gesture Support

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        true
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        gestureRecognizer is UIScreenEdgePanGestureRecognizer
    }
}

// MARK: - UIHostingController
/// Used so we can check if a VC is a UIHostingController
private protocol AnyUIHostingViewController: AnyObject {}
extension UIHostingController: AnyUIHostingViewController {}
