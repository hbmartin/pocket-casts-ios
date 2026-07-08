import Foundation
import PocketCastsDataModel
import PocketCastsFileSync
import PocketCastsUtils
import UIKit

/// App-side driver for local-first file sync: owns the trigger cadence and
/// bridges app facilities (file types, download paths, notifications) into
/// the PocketCastsFileSync module. Owned by the AppDelegate, mirroring
/// BadgeHelper/ShortcutManager.
///
/// Cadence (from the sync design): a sync pass runs on meaningful events —
/// pause, track change, queue edits, app foreground/background — plus a 60s
/// heartbeat while playing, and from BGAppRefresh. Event triggers are
/// debounced so a burst of queue edits becomes one pass.
class FileSyncCoordinator {
    private static let debounceInterval: TimeInterval = 2
    private static let heartbeatInterval: TimeInterval = 60

    private var debounceTimer: Timer?
    private var heartbeatTimer: Timer?

    func setup() {
        guard FeatureFlag.fileSync.enabled else { return }

        let deviceName = UIDevice.current.name
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
            await FileSyncManager.shared.configureDeviceMetadata(name: deviceName)
            await FileSyncManager.shared.configureDelegate(FileSyncAppDelegate())
            await FileSyncManager.shared.restoreIfEnabled()
            // Silent onboarding: first launch with iCloud available starts
            // syncing with zero setup, like iOS Notes.
            await FileSyncManager.shared.enableICloudIfUnconfigured()
            await FileSyncManager.shared.syncNow()
        }

        addObservers()
    }

    private func addObservers() {
        let center = NotificationCenter.default
        for name in [Constants.Notifications.playbackPaused,
                     Constants.Notifications.playbackTrackChanged,
                     Constants.Notifications.upNextQueueChanged,
                     Constants.Notifications.upNextEpisodeAdded,
                     Constants.Notifications.upNextEpisodeRemoved] {
            center.addObserver(self, selector: #selector(syncTriggerFired), name: name, object: nil)
        }
        center.addObserver(self, selector: #selector(playbackStarted), name: Constants.Notifications.playbackStarted, object: nil)
        center.addObserver(self, selector: #selector(playbackStopped), name: Constants.Notifications.playbackPaused, object: nil)
        center.addObserver(self, selector: #selector(playbackStopped), name: Constants.Notifications.playbackEnded, object: nil)
        center.addObserver(self, selector: #selector(appDidEnterBackground), name: UIApplication.didEnterBackgroundNotification, object: nil)
    }

    // MARK: - Triggers

    /// Debounced event trigger; a burst of edits coalesces into one pass.
    @objc private func syncTriggerFired() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            debounceTimer?.invalidate()
            debounceTimer = Timer.scheduledTimer(withTimeInterval: Self.debounceInterval, repeats: false) { _ in
                Task { await FileSyncManager.shared.syncNow() }
            }
        }
    }

    /// Foreground: piggybacks on the AppDelegate's become-active handling.
    func handleAppBecameActive() {
        guard FeatureFlag.fileSync.enabled else { return }
        Task { await FileSyncManager.shared.syncNow() }
    }

    /// BGAppRefresh: runs a pass inside the existing refresh task budget.
    func performBackgroundSync() async {
        guard FeatureFlag.fileSync.enabled else { return }
        await FileSyncManager.shared.syncNow()
    }

    // MARK: - Playback heartbeat

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

    // MARK: - Background flush

    /// One final pass on backgrounding, under a finite-length background
    /// task so a just-paused position makes it into the folder before
    /// suspension.
    @objc private func appDidEnterBackground() {
        guard FeatureFlag.fileSync.enabled else { return }
        var taskId: UIBackgroundTaskIdentifier = .invalid
        taskId = UIApplication.shared.beginBackgroundTask(withName: "au.com.pocketcasts.filesync.flush") {
            UIApplication.shared.endBackgroundTask(taskId)
            taskId = .invalid
        }
        Task {
            await FileSyncManager.shared.syncNow()
            await MainActor.run {
                if taskId != .invalid {
                    UIApplication.shared.endBackgroundTask(taskId)
                }
            }
        }
    }
}
