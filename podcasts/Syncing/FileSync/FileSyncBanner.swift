import Foundation
import PocketCastsFileSync
import PocketCastsUtils
import UIKit

/// One-time Profile banner shown after file sync was silently enabled via
/// iCloud, telling the user where their library now syncs and linking to
/// the Sync settings screen.
enum FileSyncBanner {
    private static let dismissedKey = "FileSyncBannerDismissed"

    @MainActor
    static var shouldShow: Bool {
        FeatureFlag.fileSync.enabled
            && !UserDefaults.standard.bool(forKey: dismissedKey)
            && UserDefaults.standard.bool(forKey: "FileSync.enabled")
    }

    static func dismiss() {
        UserDefaults.standard.set(true, forKey: dismissedKey)
    }

    @MainActor
    static func bannerView(onAction: @escaping () -> Void, onDismiss: @escaping () -> Void) -> UIView {
        let model = BannerModel(
            title: L10n.fileSyncBannerTitle,
            message: L10n.fileSyncBannerMessage,
            action: L10n.fileSyncBannerAction,
            iconName: "settings_import_podcasts",
            onActionTap: onAction,
            onCloseTap: {
                dismiss()
                onDismiss()
            }
        )
        return BannerView(model: model).themedUIView
    }
}
