import Foundation
import PocketCastsDataModel
import PocketCastsTranscription
import PocketCastsUtils
import Synchronization

/// Pure decision for what a freshly downloaded episode should trigger, extracted
/// so the matrix is unit-testable without notifications or a database.
///
/// Provided-first: a transcript the feed already offers is cheaper (no ASR
/// compute) and usually better than a generated one, so it wins; on-device or
/// remote generation is the fallback. Generation is always on — the only
/// per-episode gates are "already done" checks (a record of ANY status blocks:
/// auto-run never overwrites or retries; after a failure or cancel, another
/// attempt is the user's call).
nonisolated enum TranscriptAcquisitionDecision {
    enum Action: Equatable, Sendable {
        case none
        /// Fetch and index the feed-provided transcript.
        case indexProvided
        /// Enqueue a transcription job (engine resolved at run time).
        case enqueueTranscription
    }

    /// - Parameters:
    ///   - searchIndexingEnabled: `FeatureFlag.transcriptSearch` and the FTS index
    ///     is available on this device.
    ///   - transcriptionEnabled: `FeatureFlag.diarizedTranscription.enabled`.
    ///   - hasProvidedTranscript: the feed offers a transcript in a supported format.
    ///   - alreadyIndexedProvided: the unified index already has the episode's
    ///     provided segments.
    ///   - hasExistingRecord: whether ANY transcription record exists for the episode.
    static func action(searchIndexingEnabled: Bool,
                       transcriptionEnabled: Bool,
                       hasProvidedTranscript: Bool,
                       alreadyIndexedProvided: Bool,
                       hasExistingRecord: Bool) -> Action {
        if hasProvidedTranscript {
            // A provided transcript exists, so generating would be wasteful even
            // when indexing is off/unavailable — there is nothing else to do.
            guard searchIndexingEnabled, !alreadyIndexedProvided else { return .none }
            return .indexProvided
        }
        guard transcriptionEnabled, !hasExistingRecord else { return .none }
        return .enqueueTranscription
    }
}

/// Acquires a transcript for every downloaded episode: indexes the feed-provided
/// transcript when the show publishes one, otherwise enqueues a transcription job
/// (remote provider when configured and consented, on-device engines otherwise —
/// resolved by `TranscriptionQueueManager` at run time).
///
/// Mirrors `EpisodeLoudnessScanner`'s shape: a singleton created once from
/// `AppDelegate`, observing typed `EpisodeDownloaded` messages. The singleton (and
/// therefore its observation token) deliberately lives for the whole process
/// lifetime — it is never torn down, so no removal path exists. User (uploaded)
/// episodes never qualify: they have no feed metadata and no per-podcast settings.
nonisolated final class TranscriptAcquisitionCoordinator: Sendable {
    static let shared = TranscriptAcquisitionCoordinator()

    typealias TranscriptMetadata = Episode.Metadata.Transcript

    /// Held for the coordinator's whole (process-long) lifetime; set once in init.
    private let downloadToken = Mutex<NotificationCenter.ObservationToken?>(nil)

    private let dataManager: DataManager
    private let loadTranscriptsMetadata: @Sendable (_ podcastUuid: String, _ episodeUuid: String) async throws -> [TranscriptMetadata]
    private let fetchTranscriptText: @Sendable (URL) async throws -> String?
    private let indexProvided: @Sendable (_ episodeUuid: String, _ podcastUuid: String, _ model: TranscriptModel) async -> Bool
    private let enqueueTranscription: @Sendable (_ episodeUuid: String, _ podcastUuid: String) async -> Void

    /// Shared with nobody else: provided-transcript fetches go through the same
    /// URL cache the viewer uses, so indexing a download makes later viewing free.
    private static let defaultRetriever = TranscriptsDataRetriever()

    init(dataManager: DataManager = .sharedManager,
         loadTranscriptsMetadata: @escaping @Sendable (_ podcastUuid: String, _ episodeUuid: String) async throws -> [TranscriptMetadata] = { podcastUuid, episodeUuid in
             try await ShowInfoCoordinator.shared.loadTranscriptsMetadata(podcastUuid: podcastUuid, episodeUuid: episodeUuid).transcripts
         },
         fetchTranscriptText: @escaping @Sendable (URL) async throws -> String? = { url in
             try await TranscriptAcquisitionCoordinator.defaultRetriever.loadTranscript(url: url)
         },
         indexProvided: @escaping @Sendable (_ episodeUuid: String, _ podcastUuid: String, _ model: TranscriptModel) async -> Bool = { episodeUuid, podcastUuid, model in
             await TranscriptSearchIndexer.shared.index(episodeUuid: episodeUuid, podcastUuid: podcastUuid, model: model)
         },
         enqueueTranscription: @escaping @Sendable (_ episodeUuid: String, _ podcastUuid: String) async -> Void = { episodeUuid, podcastUuid in
             await TranscriptionQueueManager.shared.enqueue(episodeUuid: episodeUuid, podcastUuid: podcastUuid)
         }) {
        self.dataManager = dataManager
        self.loadTranscriptsMetadata = loadTranscriptsMetadata
        self.fetchTranscriptText = fetchTranscriptText
        self.indexProvided = indexProvided
        self.enqueueTranscription = enqueueTranscription

        let token = NotificationCenter.default.addObserver(for: EpisodeDownloaded.self) { [weak self] message in
            guard let self, let episodeUuid = message.uuid else { return }
            Task(priority: .utility) { await self.evaluate(episodeUuid: episodeUuid) }
        }
        downloadToken.withLock { $0 = token }
    }

    /// Applies the acquisition decision to a downloaded episode. Feature flags are
    /// checked per event (not at setup) so a Beta-menu toggle takes effect without
    /// a relaunch.
    func evaluate(episodeUuid: String) async {
        guard let episode = dataManager.findEpisode(uuid: episodeUuid),
              let podcast = dataManager.findPodcast(uuid: episode.podcastUuid) else { return }

        let searchIndexingEnabled = FeatureFlag.transcriptSearch.enabled && dataManager.transcriptSearch.isAvailable
        let transcriptionEnabled = FeatureFlag.diarizedTranscription.enabled
        guard searchIndexingEnabled || transcriptionEnabled else { return }

        var provided: [TranscriptMetadata] = []
        do {
            provided = try await loadTranscriptsMetadata(podcast.uuid, episodeUuid)
        } catch {
            // Metadata unavailable: don't guess. Generating for a show that DOES
            // publish transcripts wastes hours of compute; skipping just means the
            // episode indexes when viewed instead.
            FileLog.shared.addMessage("[TranscriptAcquisition] show-info fetch failed for \(episodeUuid), skipping: \(error)")
            return
        }

        let action = TranscriptAcquisitionDecision.action(
            searchIndexingEnabled: searchIndexingEnabled,
            transcriptionEnabled: transcriptionEnabled,
            hasProvidedTranscript: TranscriptFormat.bestTranscript(from: provided) != nil,
            alreadyIndexedProvided: dataManager.transcriptSearch.isIndexed(episodeUuid: episodeUuid, source: .provided),
            hasExistingRecord: dataManager.transcriptions.find(episodeUuid: episodeUuid) != nil
        )

        switch action {
        case .none:
            return
        case .indexProvided:
            let indexed = await acquireProvided(episodeUuid: episodeUuid, podcastUuid: podcast.uuid, from: provided)
            // An unfetchable or unparseable provided transcript is as good as
            // absent — fall through to generation under its own gates.
            if !indexed, transcriptionEnabled, dataManager.transcriptions.find(episodeUuid: episodeUuid) == nil {
                await enqueue(episodeUuid: episodeUuid, podcast: podcast)
            }
        case .enqueueTranscription:
            await enqueue(episodeUuid: episodeUuid, podcast: podcast)
        }
    }

    /// Fetches the best provided transcript and writes it into the unified index.
    /// Returns false when fetching, parsing or indexing failed.
    private func acquireProvided(episodeUuid: String, podcastUuid: String, from available: [TranscriptMetadata]) async -> Bool {
        guard let best = TranscriptFormat.bestTranscript(from: available),
              let format = best.transcriptFormat,
              let url = URL(string: best.url) else { return false }

        do {
            guard let text = try await fetchTranscriptText(url), !text.isEmpty,
                  let model = TranscriptModel.makeModel(from: text, format: format) else {
                FileLog.shared.addMessage("[TranscriptAcquisition] provided transcript unusable for \(episodeUuid) (\(best.type))")
                return false
            }
            let indexed = await indexProvided(episodeUuid, podcastUuid, model)
            if indexed {
                FileLog.shared.addMessage("[TranscriptAcquisition] indexed provided transcript for downloaded episode \(episodeUuid)")
            }
            return indexed
        } catch {
            FileLog.shared.addMessage("[TranscriptAcquisition] provided transcript fetch failed for \(episodeUuid): \(error)")
            return false
        }
    }

    private func enqueue(episodeUuid: String, podcast: Podcast) async {
        // Cost visibility: say up front when this automatic job is expected to
        // spend the user's remote-provider credits (the queue re-resolves the
        // engine at run time; see TranscriptionQueueManager.run).
        let providerId = Settings.transcriptionRemoteProvider()
        let expectsRemote = TranscriptionEngineFactory.currentMode() == .remoteProvider
            && !podcast.settings.disableRemoteTranscription
            && TranscriptionConsentGate.hasConsent(providerId: providerId)
        if expectsRemote {
            FileLog.shared.addMessage("[TranscriptAcquisition] auto-enqueueing \(episodeUuid) — expected to use remote provider \(providerId)")
        } else {
            FileLog.shared.addMessage("[TranscriptAcquisition] auto-enqueueing \(episodeUuid) for on-device transcription")
        }
        await enqueueTranscription(episodeUuid, podcast.uuid)
    }
}
