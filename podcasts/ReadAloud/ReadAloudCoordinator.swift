import Foundation
import PocketCastsDataModel
import PocketCastsUtils
import UIKit

/// App-lifecycle wiring for Read Aloud: resume unfinished narrations at launch,
/// keep rendering briefly after the user leaves, and detach a narration when its
/// episode is deleted.
///
/// No `BGProcessingTask`. Offline synthesis renders far faster than real time and
/// is chunk-resumable, so the grace period plus the next foreground covers it —
/// and a processing task, which the system only runs when charging and idle,
/// could sit for hours, which is the wrong contract for "finish my article".
@MainActor
final class ReadAloudCoordinator {
    private var isSetup = false
    private var backgroundTask: ReadAloudBackgroundTask?
    private let tokenBox = ObservationTokenBox()
    private let completionNotifier = NarrationCompletionNotifier()

    func setup() {
        guard !isSetup, FeatureFlag.readAloud.enabled else { return }
        isSetup = true

        observeEpisodeDeletion()
        completionNotifier.start()

        Task {
            await NarrationQueue.shared.restorePending()
        }
    }

    func handleAppBecameActive() {
        guard isSetup else { return }
        backgroundTask?.end()
        backgroundTask = nil
        Task {
            await NarrationQueue.shared.restorePending()
        }
    }

    /// Buys the queue a little time to finish what it's rendering. On expiry the
    /// queue stops after the chunk in flight — its file and checkpoint are
    /// already durable, so the next launch picks up exactly there.
    func handleEnterBackground() {
        guard isSetup else { return }

        // Begin synchronously: once this method returns the app can suspend at
        // any moment, and a task started from an async hop may come too late.
        backgroundTask?.end()
        let task = ReadAloudBackgroundTask.begin {
            Task { await NarrationQueue.shared.suspendAfterCurrentChunk() }
        }
        backgroundTask = task

        Task { [weak self] in
            guard await NarrationQueue.shared.isIdle else { return }
            guard let self, self.backgroundTask === task else { return }
            task.end()
            self.backgroundTask = nil
        }
    }

    /// The user deleted a generated episode. Its narration goes with it; the
    /// document survives and the library offers to narrate it again (ADR-0019).
    private func observeEpisodeDeletion() {
        tokenBox.token = NotificationCenter.default.addObserver(for: UserEpisodeDeleted.self) { message in
            guard let episodeUuid = message.uuid else { return }

            Task.detached(priority: .utility) {
                guard let narration = DataManager.sharedManager.readAloud.deleteNarration(episodeUuid: episodeUuid) else {
                    // An ordinary uploaded file, which is the common case.
                    return
                }
                ReadAloudStorage.default.deleteWorkspace(narrationUuid: narration.uuid)
                NotificationCenter.postOnMainThread(NarrationsChanged())
            }
        }
    }
}

/// Keeps the app alive while a chunk is rendering after the user backgrounds it.
/// `end()` is idempotent and is called from both the expiration handler and the
/// foreground path.
@MainActor
private final class ReadAloudBackgroundTask {
    private var taskId: UIBackgroundTaskIdentifier = .invalid

    static func begin(onExpiration: @escaping @MainActor () -> Void) -> ReadAloudBackgroundTask {
        let holder = ReadAloudBackgroundTask()
        holder.taskId = UIApplication.shared.beginBackgroundTask(withName: "au.com.pocketcasts.readaloud.narration") {
            onExpiration()
            holder.end()
        }
        return holder
    }

    func end() {
        guard taskId != .invalid else { return }
        UIApplication.shared.endBackgroundTask(taskId)
        taskId = .invalid
    }
}
