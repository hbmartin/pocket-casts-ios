import Foundation
import PocketCastsDataModel
import PocketCastsServer
import PocketCastsUtils

extension NetworkUtils {
#if os(tvOS)
    //On tvOS it's allways allowed to download.
    func downloadEpisodeRequested(autoDownloadStatus: AutoDownloadStatus, _ allowed: ((_ later: Bool) -> Void)?, disallowed: (() -> Void)?) {
        allowed?(true)
    }

    func streamEpisodeRequested(_ allowed: (() -> Void)?, disallowed: (() -> Void)?) {
        allowed?()
    }

#else
    func downloadEpisodeRequested(autoDownloadStatus: AutoDownloadStatus, _ allowed: ((_ later: Bool) -> Void)?, disallowed: (() -> Void)?) {
        let mobileDataAllowed = autoDownloadStatus == .autoDownloaded ? Settings.autoDownloadMobileDataAllowed() : Settings.mobileDataAllowed()

        if mobileDataAllowed || isConnectedToUnexpensiveConnection() {
            allowed?(false)

            return
        }

        let optionsPicker = OptionsPicker()
        let downloadAction = OptionAction(label: L10n.podcastDownloadNow, icon: nil) {
            allowed?(false)
        }
        let laterAction = OptionAction(label: L10n.queueForLater, icon: nil) {
            allowed?(true)
        }
        laterAction.outline = true

        optionsPicker.addAttributedDescriptiveActions(title: L10n.notOnWifi, message: L10n.downloadDataWarningWithSettingsLink("pktc://settings/storage-and-data"), icon: "option-alert", actions: [downloadAction, laterAction])

        optionsPicker.setNoActionCallback {
            disallowed?()
        }

        optionsPicker.present()
    }

    func streamEpisodeRequested(_ allowed: (() -> Void)?, disallowed: (() -> Void)?) {
        if Settings.mobileDataAllowed() || isConnectedToUnexpensiveConnection() {
            allowed?()

            return
        }

        let optionsPicker = OptionsPicker()
        let streamAction = OptionAction(label: L10n.podcastStreamConfirmation, icon: nil) {
            allowed?()
        }
        optionsPicker.addAttributedDescriptiveActions(title: L10n.notOnWifi, message: L10n.podcastStreamDataWarningWithSettings("pktc://settings/storage-and-data"), icon: "option-alert", actions: [streamAction])

        optionsPicker.setNoActionCallback {
            disallowed?()
        }

        optionsPicker.present()
    }

#endif
}
