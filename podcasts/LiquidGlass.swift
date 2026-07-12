import Foundation
import UIKit
import PocketCastsUtils

extension UIWindow {
    /// Forces the window's interface style to match the active in-app theme so the
    /// Liquid Glass material renders with the right tint immediately, instead of
    /// briefly flashing the system appearance before the app's appearance overrides land.
    /// Read the actual system appearance via `view.systemUserInterfaceStyle` instead of
    /// `traitCollection.userInterfaceStyle`, which reflects this override.
    func applyInterfaceStyleForActiveTheme() {
        overrideUserInterfaceStyle = Theme.sharedTheme.activeTheme.isDark ? .dark : .light
    }
}

extension Theme {
    /// True if the *system* (not the in-app theme) is currently in dark mode.
    /// Captured at scene setup before we override the window, and refreshed in
    /// `MainTabBarController.traitCollectionDidChange`. Reads must come from the
    /// window scene's trait collection, since per-window `overrideUserInterfaceStyle`
    /// would otherwise pollute it.
    static var systemIsDark: Bool = false
}

extension Constants {
    @MainActor static var effectiveMiniPlayerOffset: CGFloat {
        // The player is shown using `UITabAccessory`, so it is automatically added
        // to the bottom safe area.
        0
    }

    @MainActor static var effectiveFooterViewPadding: CGFloat {
        Constants.effectiveMiniPlayerOffset + 4
    }

    /// Extra bottom content inset while the mini player accessory is visible.
    /// The accessory extends the safe area, but only exactly to its own edge —
    /// at maximum scroll the last row's bottom lands flush against the pill,
    /// so short lists read as stuck underneath it. This gives the last row
    /// room to rest clear of the pill.
    @MainActor static let miniPlayerRestingClearance: CGFloat = 12
}
