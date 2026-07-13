import UIKit
import PocketCastsServer

class SyncLoadingAlert: ShiftyLoadingAlert {
    private var totalPodcastsToImport: Int = 0

    init() {
        super.init(title: L10n.syncAccountLogin)
    }

    override func showAlert(_ presentingController: UIViewController, hasProgress: Bool, completion: (() -> Void)?) {
        super.showAlert(presentingController, hasProgress: hasProgress, completion: completion)
        subscribeToSyncChanges()
    }

    override func hideAlert(_ animated: Bool, completion: (() -> Void)? = nil) {
        super.hideAlert(animated, completion: completion)
        unsubscribeToSyncChanges()
    }

    private var messageTokens: [NotificationCenter.ObservationToken] = []

    private func subscribeToSyncChanges() {
        guard messageTokens.isEmpty else { return }

        messageTokens = [
            NotificationCenter.default.addObserver(for: SyncProgressPodcastCountKnown.self) { [weak self] message in
                self?.totalPodcastsToImport = message.count
            },
            NotificationCenter.default.addObserver(for: SyncProgressPodcastUptoChanged.self) { [weak self] message in
                self?.syncUpToChanged(message.upTo)
            },
            NotificationCenter.default.addObserver(for: SyncProgressPodcastsImported.self) { [weak self] _ in
                self?.podcastsImported()
            },
            NotificationCenter.default.addObserver(for: UserLoginDidChange.self) { [weak self] _ in
                self?.title = L10n.syncAccountLogin
            }
        ]
    }

    private func unsubscribeToSyncChanges() {
        let tokens = messageTokens
        messageTokens = []
        for token in tokens {
            NotificationCenter.default.removeObserver(token)
        }
    }

    // isolated deinit: ShiftyLoadingAlert is @MainActor so its deinit is isolated and this
    // override must match; it tears down isolated observation tokens.
    isolated deinit {
        for token in messageTokens {
            NotificationCenter.default.removeObserver(token)
        }
    }

    private func syncUpToChanged(_ upTo: Int) {
        DispatchQueue.main.async {
            if self.totalPodcastsToImport > 0 {
                self.title = L10n.syncProgress(upTo.localized(), self.totalPodcastsToImport.localized())
                self.progress = CGFloat(upTo / self.totalPodcastsToImport)
            } else {
                // Used when the total number of podcasts to sync isn't known.
                self.title = upTo == 1 ? L10n.syncProgressUnknownCountSingular : L10n.syncProgressUnknownCountPluralFormat(upTo.localized())
            }
        }
    }

    private func podcastsImported() {
        DispatchQueue.main.async {
            self.title = L10n.syncInProgress
        }
    }
}
