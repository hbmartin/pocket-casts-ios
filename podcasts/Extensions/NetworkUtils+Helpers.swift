import Foundation
import PocketCastsDataModel
import PocketCastsServer
import PocketCastsUtils

extension NetworkUtils {
    func downloadEpisodeRequested(autoDownloadStatus: AutoDownloadStatus, _ allowed: ((_ later: Bool) -> Void)?, disallowed: (() -> Void)?) {
        let mobileDataAllowed = autoDownloadStatus == .autoDownloaded ? Settings.autoDownloadMobileDataAllowed() : Settings.mobileDataAllowed()

        if mobileDataAllowed || isConnectedToUnexpensiveConnection() {
            allowed?(false)

            return
        }

        // The prompt presents on the main actor while callers can arrive from background
        // download paths. The callbacks are handed over wholesale and only invoked from the
        // picker's main-actor actions.
        let allowed = UncheckedSendable(allowed)
        let disallowed = UncheckedSendable(disallowed)
        Task { @MainActor in
            let optionsPicker = OptionsPicker()
            let downloadAction = OptionAction(label: L10n.podcastDownloadNow, icon: nil) {
                allowed.value?(false)
            }
            let laterAction = OptionAction(label: L10n.queueForLater, icon: nil) {
                allowed.value?(true)
            }
            laterAction.outline = true

            optionsPicker.addAttributedDescriptiveActions(title: L10n.notOnWifi, message: L10n.downloadDataWarningWithSettingsLink("thcast://settings/storage-and-data"), icon: "option-alert", actions: [downloadAction, laterAction])

            optionsPicker.setNoActionCallback {
                disallowed.value?()
            }

            optionsPicker.present()
        }
    }

    func streamEpisodeRequested(_ allowed: (() -> Void)?, disallowed: (() -> Void)?) {
        if Settings.mobileDataAllowed() || isConnectedToUnexpensiveConnection() {
            allowed?()

            return
        }

        // See downloadEpisodeRequested: main-actor prompt, callbacks handed over wholesale
        let allowed = UncheckedSendable(allowed)
        let disallowed = UncheckedSendable(disallowed)
        Task { @MainActor in
            let optionsPicker = OptionsPicker()
            let streamAction = OptionAction(label: L10n.podcastStreamConfirmation, icon: nil) {
                allowed.value?()
            }
            optionsPicker.addAttributedDescriptiveActions(title: L10n.notOnWifi, message: L10n.podcastStreamDataWarningWithSettings("thcast://settings/storage-and-data"), icon: "option-alert", actions: [streamAction])

            optionsPicker.setNoActionCallback {
                disallowed.value?()
            }

            optionsPicker.present()
        }
    }
}
