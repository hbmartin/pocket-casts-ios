import Foundation
import PocketCastsFileSync
import PocketCastsUtils
import UIKit

enum FileSyncBanner {
    private static let dismissedKey = "FileSyncBannerDismissed"

    @MainActor
    static var shouldShow: Bool {
        !UserDefaults.standard.bool(forKey: dismissedKey)
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
