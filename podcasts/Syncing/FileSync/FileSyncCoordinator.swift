import Foundation
import PocketCastsDataModel
import PocketCastsFileSync
import PocketCastsUtils
import UIKit

/// App-side driver for local file sync.
///
/// It configures the sync module once at launch, then runs debounced sync
/// passes on meaningful local events and app lifecycle transitions.
final class FileSyncCoordinator {
    private static let debounceInterval: TimeInterval = 2
    private static let heartbeatInterval: TimeInterval = 60

    private var debounceTimer: Timer?
    private var heartbeatTimer: Timer?
    private var isSetup = false

    func setup() {
        guard FeatureFlag.fileSync.enabled, !isSetup else { return }
        isSetup = true

        Task {
            await FileSyncManager.shared.configure(
                isSupportedFile: { FileTypeUtil.isSupportedUserFileType(fileName: $0) },
                localPathResolver: { episode in
                    episode.pathToDownloadedFile(pathFinder: DownloadManager.shared)
                },
                onUploadsChanged: {
                    NotificationCenter.postOnMainThread(notification: Constants.Notifications.fileSyncUploadsChanged)
                }
            )
            await FileSyncManager.shared.configureDelegate(FileSyncAppDelegate())
            await FileSyncManager.shared.restoreIfEnabled()
            await FileSyncManager.shared.enableICloudIfUnconfigured()
            await FileSyncManager.shared.syncNow()
        }

        addObservers()
    }

    func handleAppBecameActive() {
        guard FeatureFlag.fileSync.enabled else { return }
        Task { await FileSyncManager.shared.syncNow() }
    }

    func performBackgroundSync() async {
        guard FeatureFlag.fileSync.enabled else { return }
        await FileSyncManager.shared.syncNow()
    }

    private func addObservers() {
        let center = NotificationCenter.default
        for name in [
            Constants.Notifications.playbackPaused,
            Constants.Notifications.playbackTrackChanged,
            Constants.Notifications.upNextQueueChanged,
            Constants.Notifications.upNextEpisodeAdded,
            Constants.Notifications.upNextEpisodeRemoved
        ] {
            center.addObserver(self, selector: #selector(syncTriggerFired), name: name, object: nil)
        }
        center.addObserver(self, selector: #selector(playbackStarted), name: Constants.Notifications.playbackStarted, object: nil)
        center.addObserver(self, selector: #selector(playbackStopped), name: Constants.Notifications.playbackPaused, object: nil)
        center.addObserver(self, selector: #selector(playbackStopped), name: Constants.Notifications.playbackEnded, object: nil)
        center.addObserver(self, selector: #selector(appDidEnterBackground), name: UIApplication.didEnterBackgroundNotification, object: nil)
    }

    @objc private func syncTriggerFired() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            debounceTimer?.invalidate()
            debounceTimer = Timer.scheduledTimer(withTimeInterval: Self.debounceInterval, repeats: false) { _ in
                Task { await FileSyncManager.shared.syncNow() }
            }
        }
    }

    @objc private func playbackStarted() {
        DispatchQueue.main.async { [weak self] in
            guard let self, heartbeatTimer == nil else { return }
            heartbeatTimer = Timer.scheduledTimer(withTimeInterval: Self.heartbeatInterval, repeats: true) { _ in
                Task { await FileSyncManager.shared.syncNow() }
            }
        }
    }

    @objc private func playbackStopped() {
        DispatchQueue.main.async { [weak self] in
            self?.heartbeatTimer?.invalidate()
            self?.heartbeatTimer = nil
        }
    }

    @objc private func appDidEnterBackground() {
        guard FeatureFlag.fileSync.enabled else { return }
        var taskID: UIBackgroundTaskIdentifier = .invalid
        taskID = UIApplication.shared.beginBackgroundTask(withName: "au.com.pocketcasts.filesync.flush") {
            UIApplication.shared.endBackgroundTask(taskID)
            taskID = .invalid
        }
        Task {
            await FileSyncManager.shared.syncNow()
            await MainActor.run {
                if taskID != .invalid {
                    UIApplication.shared.endBackgroundTask(taskID)
                }
            }
        }
    }
}
