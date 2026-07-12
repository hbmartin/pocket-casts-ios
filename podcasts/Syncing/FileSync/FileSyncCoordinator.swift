import Foundation
import PocketCastsDataModel
import PocketCastsFileSync
import PocketCastsUtils
import UIKit

/// App-side driver for local file sync.
///
/// It configures the sync module once at launch, then runs debounced sync
/// passes on meaningful local events and app lifecycle transitions.
@MainActor
final class FileSyncCoordinator {
    private static let debounceInterval: TimeInterval = 2
    private static let heartbeatInterval: TimeInterval = 60

    #if DEBUG
    private static let uiTestExerciseEventsEnvironment = "POCKET_CASTS_UI_TEST_EXERCISE_FILE_SYNC_COORDINATOR_EVENTS"
    private static let uiTestDebounceCompletedIdentifier = "fileSyncCoordinatorDebounceCompleted"
    #endif

    private var debounceTimer: Timer?
    private var heartbeatTimer: Timer?
    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
    private var isSetup = false

    /// Typed-message observations, registered once in `addObservers()` and removed in deinit.
    private var messageTokens = [NotificationCenter.ObservationToken]()

    deinit {
        // Read isolated stored properties into locals before any observer removal
        // (Swift 6.2 isolated-deinit rule).
        let tokens = messageTokens
        for token in tokens {
            NotificationCenter.default.removeObserver(token)
        }
    }

    func setup() {
        guard !isSetup else { return }
        isSetup = true

        Task {
            await FileSyncManager.shared.configure(
                isSupportedFile: { FileTypeUtil.isSupportedUserFileType(fileName: $0) },
                localPathResolver: { episode in
                    episode.pathToDownloadedFile(pathFinder: DownloadManager.shared)
                },
                episodeLocalPathResolver: { episode in
                    episode.pathToDownloadedFile(pathFinder: DownloadManager.shared)
                },
                isUnmeteredConnection: {
                    NetworkUtils.shared.isConnectedToUnexpensiveConnection()
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

        #if DEBUG
        if ProcessInfo.processInfo.environment[Self.uiTestExerciseEventsEnvironment] == "1" {
            exerciseNotificationHandlersForUITesting()
        }
        #endif
    }

    func handleAppBecameActive() {
        Task { await FileSyncManager.shared.syncNow() }
    }

    func performBackgroundSync() async {
        await FileSyncManager.shared.syncNow()
    }

    private func addObservers() {
        let center = NotificationCenter.default
        messageTokens.append(center.addObserver(for: PlaybackPaused.self) { [weak self] _ in
            self?.syncTriggerFired()
            self?.playbackStopped()
        })
        messageTokens.append(center.addObserver(for: PlaybackTrackChanged.self) { [weak self] _ in
            self?.syncTriggerFired()
        })
        messageTokens.append(center.addObserver(for: UpNextQueueChanged.self) { [weak self] _ in
            self?.syncTriggerFired()
        })
        messageTokens.append(center.addObserver(for: UpNextEpisodeAdded.self) { [weak self] _ in
            self?.syncTriggerFired()
        })
        messageTokens.append(center.addObserver(for: UpNextEpisodeRemoved.self) { [weak self] _ in
            self?.syncTriggerFired()
        })
        messageTokens.append(center.addObserver(for: PlaybackStarted.self) { [weak self] _ in
            self?.playbackStarted()
        })
        messageTokens.append(center.addObserver(for: PlaybackEnded.self) { [weak self] _ in
            self?.playbackStopped()
        })
        messageTokens.append(center.addObserver(for: UIApplication.DidEnterBackgroundMessage.self) { [weak self] _ in
            self?.appDidEnterBackground()
        })
    }

    private func syncTriggerFired() {
        debounceTimer?.invalidate()
        debounceTimer = Timer.scheduledTimer(withTimeInterval: Self.debounceInterval, repeats: false) { _ in
            Task { @MainActor in
                #if DEBUG
                Self.markDebounceCompletedForUITesting()
                #endif
                await FileSyncManager.shared.syncNow()
            }
        }
    }

    private func playbackStarted() {
        guard heartbeatTimer == nil else { return }
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: Self.heartbeatInterval, repeats: true) { _ in
            Task { await FileSyncManager.shared.syncNow() }
        }
    }

    private func playbackStopped() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
    }

    private func appDidEnterBackground() {
        backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "au.com.pocketcasts.filesync.flush") { [weak self] in
            Task { @MainActor [weak self] in
                self?.endBackgroundTaskIfNeeded()
            }
        }
        Task { @MainActor [weak self] in
            await FileSyncManager.shared.syncNow()
            self?.endBackgroundTaskIfNeeded()
        }
    }

    private func endBackgroundTaskIfNeeded() {
        guard backgroundTaskID != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTaskID)
        backgroundTaskID = .invalid
    }

    #if DEBUG
    private func exerciseNotificationHandlersForUITesting() {
        NotificationCenter.postOnMainThread(UpNextQueueChanged())
        NotificationCenter.postOnMainThread(UpNextQueueChanged())
        NotificationCenter.postOnMainThread(PlaybackStarted())
        NotificationCenter.postOnMainThread(PlaybackStarted())
        NotificationCenter.postOnMainThread(PlaybackPaused())
        NotificationCenter.postOnMainThread(PlaybackEnded())
    }

    private static func markDebounceCompletedForUITesting() {
        guard ProcessInfo.processInfo.environment[uiTestExerciseEventsEnvironment] == "1",
              let window = UIApplication.shared.connectedScenes
                  .compactMap({ $0 as? UIWindowScene })
                  .flatMap(\.windows)
                  .first(where: \.isKeyWindow) else { return }

        let marker = UIView(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
        marker.isAccessibilityElement = true
        marker.accessibilityIdentifier = uiTestDebounceCompletedIdentifier
        window.addSubview(marker)
    }
    #endif
}
