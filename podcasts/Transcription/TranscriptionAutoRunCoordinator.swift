import Foundation
import PocketCastsDataModel
import PocketCastsTranscription
import PocketCastsUtils
import Synchronization

/// Pure decision for whether a freshly downloaded episode should be auto-enqueued
/// for on-device transcription. Extracted from `TranscriptionAutoRunCoordinator`
/// so the matrix is unit-testable without notifications or a database.
nonisolated enum TranscriptionAutoRunDecision {
    /// - Parameters:
    ///   - featureEnabled: `FeatureFlag.diarizedTranscription.enabled`.
    ///   - podcastOptedIn: the podcast's `settings.autoTranscribe` opt-in.
    ///   - hasExistingRecord: whether ANY transcription record exists for the
    ///     episode (completed, queued, failed, cancelled, …). Auto-run never
    ///     overwrites or retries — after a failure or cancel, another attempt is
    ///     the user's call.
    ///   - engineMode: the currently selected engine. Only the local modes
    ///     qualify — an automatic run must never spend the user's remote-provider
    ///     credits.
    static func shouldEnqueue(featureEnabled: Bool,
                              podcastOptedIn: Bool,
                              hasExistingRecord: Bool,
                              engineMode: TranscriptionEngineMode) -> Bool {
        guard featureEnabled, podcastOptedIn, !hasExistingRecord else { return false }

        switch engineMode {
        case .appleBuiltIn, .localModel:
            return true
        case .remoteProvider:
            return false
        }
    }
}

/// Auto-enqueues on-device transcription jobs for episodes of podcasts the user
/// opted in via the "Auto-Transcribe on Download" podcast setting.
///
/// Mirrors `EpisodeLoudnessScanner`'s shape: a singleton created once from
/// `AppDelegate`, observing typed `EpisodeDownloaded` messages and hopping to a
/// serial utility queue for the database reads. The singleton (and therefore its
/// observation token) deliberately lives for the whole process lifetime — it is
/// never torn down, so no removal path exists.
nonisolated final class TranscriptionAutoRunCoordinator: Sendable {
    static let shared = TranscriptionAutoRunCoordinator()

    /// Serial utility queue: the decision needs a few database reads, which don't
    /// belong on the main thread the download notification is delivered on.
    private let workQueue = DispatchQueue(label: "au.com.pocketcasts.TranscriptionAutoRun", qos: .utility, autoreleaseFrequency: .workItem)

    /// Held for the coordinator's whole (process-long) lifetime; set once in init.
    private let downloadToken = Mutex<NotificationCenter.ObservationToken?>(nil)

    init() {
        let token = NotificationCenter.default.addObserver(for: EpisodeDownloaded.self) { [weak self] message in
            guard let self, let episodeUuid = message.uuid else { return }
            self.evaluate(episodeUuid: episodeUuid)
        }
        downloadToken.withLock { $0 = token }
    }

    /// Applies the auto-run decision to a downloaded episode and enqueues a
    /// transcription job when it qualifies. The feature flag is checked per event
    /// (not at setup) so a Beta-menu toggle takes effect without a relaunch.
    func evaluate(episodeUuid: String) {
        workQueue.async {
            let dataManager = DataManager.sharedManager
            // Only podcast episodes carry the per-podcast opt-in; user (uploaded)
            // episodes never auto-transcribe.
            guard let episode = dataManager.findEpisode(uuid: episodeUuid),
                  let podcast = dataManager.findPodcast(uuid: episode.podcastUuid) else { return }

            let shouldEnqueue = TranscriptionAutoRunDecision.shouldEnqueue(
                featureEnabled: FeatureFlag.diarizedTranscription.enabled,
                podcastOptedIn: podcast.settings.autoTranscribe,
                hasExistingRecord: dataManager.transcriptions.find(episodeUuid: episodeUuid) != nil,
                engineMode: TranscriptionEngineFactory.currentMode()
            )
            guard shouldEnqueue else { return }

            FileLog.shared.addMessage("[Transcription] auto-enqueueing downloaded episode \(episodeUuid) of \(podcast.uuid)")
            Task {
                await TranscriptionQueueManager.shared.enqueue(episodeUuid: episodeUuid, podcastUuid: podcast.uuid)
            }
        }
    }
}
