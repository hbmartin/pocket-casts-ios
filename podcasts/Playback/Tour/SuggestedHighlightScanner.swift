import Foundation
import PocketCastsDataModel
import PocketCastsUtils
import UIKit

/// Queues finished episodes for salient-segment generation and surfaces the
/// top ranks as pending suggestions (Highlights S8). Clone of the
/// `TranscriptEmbeddingBackfill` shape: a durable UserDefaults queue, small
/// drains, battery/thermal gating, launch kick.
@MainActor
final class SuggestedHighlightScanner {
    static let shared = SuggestedHighlightScanner()

    static let suggestionsPerEpisode = 3
    private static let queueKey = "suggestedHighlights.pendingEpisodes"
    private static let maxPerDrain = 5
    private static let retryInterval: TimeInterval = 5 * 60

    private var drainTask: Task<Void, Never>?
    private let dataManager: DataManager

    /// Injectable deferral gate (battery, Low Power Mode, thermals).
    private let isDeferred: @MainActor () -> Bool

    init(dataManager: DataManager = .sharedManager,
         isDeferred: (@MainActor () -> Bool)? = nil) {
        self.dataManager = dataManager
        self.isDeferred = isDeferred ?? {
            TranscriptionPowerState.isDeferred(policy: Settings.transcriptionBatteryPolicy(), state: .current())
                || ProcessInfo.processInfo.thermalState == .serious
                || ProcessInfo.processInfo.thermalState == .critical
        }
    }

    /// `playerDidFinishPlayingEpisode` hook: the listener provably heard the
    /// whole episode, so its best moments are suggestion-worthy.
    func episodeDidComplete(episodeUuid: String) {
        guard FeatureFlag.suggestedHighlights.enabled else { return }
        guard !dataManager.salientSegments.hasGeneration(episodeUuid: episodeUuid) else { return }

        var queue = pendingEpisodes
        guard !queue.contains(episodeUuid) else { return }
        queue.append(episodeUuid)
        pendingEpisodes = queue
        scheduleDrain(after: 5)
    }

    /// The on-demand "Suggest highlights" path: generates immediately when
    /// needed and marks the top ranks pending even on a cached generation.
    func suggestNow(episodeUuid: String, podcastUuid: String?) async {
        guard FeatureFlag.suggestedHighlights.enabled else { return }

        if dataManager.salientSegments.hasGeneration(episodeUuid: episodeUuid) {
            dataManager.salientSegments.markTopCandidatesPending(
                episodeUuid: episodeUuid, count: Self.suggestionsPerEpisode)
            NotificationCenter.postOnMainThread(SuggestedHighlightsUpdated())
            return
        }
        let completed = await scan(episodeUuid: episodeUuid, markPending: true)
        if !completed {
            requeue(episodeUuid)
            scheduleDrain(after: Self.retryInterval)
        }
    }

    func kickAfterLaunch(delay: TimeInterval = 45) {
        guard FeatureFlag.suggestedHighlights.enabled, !pendingEpisodes.isEmpty else { return }
        scheduleDrain(after: delay)
    }

    // MARK: - Queue

    private var pendingEpisodes: [String] {
        get { UserDefaults.standard.stringArray(forKey: Self.queueKey) ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: Self.queueKey) }
    }

    private func scheduleDrain(after delay: TimeInterval) {
        guard drainTask == nil else { return }
        drainTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(delay))
            } catch {
                return
            }
            await self?.drain()
            self?.drainTask = nil
            if let self, FeatureFlag.suggestedHighlights.enabled, !self.pendingEpisodes.isEmpty {
                self.scheduleDrain(after: Self.retryInterval)
            }
        }
    }

    private func drain() async {
        guard FeatureFlag.suggestedHighlights.enabled, !isDeferred() else { return }

        var drained = 0
        while drained < Self.maxPerDrain {
            var queue = pendingEpisodes
            guard let episodeUuid = queue.first else { break }
            queue.removeFirst()
            pendingEpisodes = queue

            let completed = await scan(episodeUuid: episodeUuid, markPending: true)
            if !completed {
                requeue(episodeUuid)
            }
            drained += 1

            if isDeferred() { break }
        }
    }

    private func requeue(_ episodeUuid: String) {
        var queue = pendingEpisodes
        guard !queue.contains(episodeUuid) else { return }
        queue.append(episodeUuid)
        pendingEpisodes = queue
    }

    /// Loads the transcript and runs one generation. Transient failures
    /// re-queue implicitly (no meta row is written, so a later trigger retries).
    @discardableResult
    private func scan(episodeUuid: String, markPending: Bool) async -> Bool {
        guard let episode = dataManager.findBaseEpisode(uuid: episodeUuid) else { return true }
        let podcastUuid = (episode as? Episode)?.podcastUuid
        let duration = episode.duration

        let transcriptManager = TranscriptManager(episodeUUID: episodeUuid, podcastUUID: podcastUuid ?? "")
        let model: TranscriptModel
        do {
            model = try await transcriptManager.loadTranscript()
        } catch {
            FileLog.shared.addMessage("SuggestedHighlightScanner: transcript load failed for \(episodeUuid), will retry: \(error)")
            return false
        }
        guard !model.cues.isEmpty else {
            // No transcript is a durable verdict for this episode today.
            dataManager.salientSegments.replaceGeneration(
                episodeUuid: episodeUuid, podcastUuid: podcastUuid,
                transcriptSource: "", generatedAt: Date(), segments: [])
            return true
        }

        // Locally generated transcripts are playback-aligned ("generated");
        // everything else is on the reference timeline ("provided" semantics
        // for seek-time mapping, per ADR-0018).
        let source = transcriptManager.isDisplayingLocalTranscription ? "generated" : "provided"
        let cues = SummaryTakeawayGenerator.timedCues(from: model)

        let generator = SalientSegmentGenerator(dataManager: dataManager)
        let segments = await generator.segments(
            episodeUuid: episodeUuid,
            podcastUuid: podcastUuid,
            transcriptSource: source,
            cues: cues,
            duration: duration,
            markPendingTop: markPending ? Self.suggestionsPerEpisode : 0
        )

        if !segments.isEmpty {
            NotificationCenter.postOnMainThread(SuggestedHighlightsUpdated())
            Analytics.track(.suggestedHighlightsGenerated, properties: [
                "episode_uuid": episodeUuid,
                "count": segments.count
            ])
        }
        // The generator deliberately leaves no meta row for transient model
        // failures. Keep the episode durable in the queue until a terminal
        // generation (segments or no-segments) exists.
        return dataManager.salientSegments.hasGeneration(episodeUuid: episodeUuid)
    }
}

/// Accept/dismiss for pending suggestions (Highlights S8). Accepting creates a
/// real Bookmark at the segment start and enriches it with the stored excerpt
/// and end time — from there it syncs and exports like any highlight.
@MainActor
struct SuggestedHighlightsManager {
    let bookmarkManager: BookmarkManager
    let dataManager: DataManager

    init(bookmarkManager: BookmarkManager = PlaybackManager.shared.bookmarkManager,
         dataManager: DataManager = .sharedManager) {
        self.bookmarkManager = bookmarkManager
        self.dataManager = dataManager
    }

    func accept(_ suggestion: SalientSegmentRecord) async {
        guard let episode = dataManager.findBaseEpisode(uuid: suggestion.episodeUuid) else { return }

        // The suggestion is a render-time snapshot: a regeneration between
        // render and tap can reuse the same (episode, rank) for a different
        // segment, and accepting blindly would bookmark the old times while
        // marking the NEW row accepted. Only proceed while the live row still
        // carries the snapshot's identity; a stale-generation snapshot
        // resolves no metadata and bails the same way.
        guard let generation = dataManager.salientSegments.generation(episodeUuid: suggestion.episodeUuid),
              let live = generation.segments.first(where: { $0.rank == suggestion.rank }),
              live.startTime == suggestion.startTime,
              live.title == suggestion.title else {
            NotificationCenter.postOnMainThread(SuggestedHighlightsUpdated())
            return
        }

        // ADR-0018: segment times live in the transcript's own time domain
        // (recorded in meta) — apply `resolvedSeekTime` semantics when the
        // suggestion becomes a real bookmark, or an ad offset lands the
        // highlight seconds away from the actual moment.
        let mapsReferenceTime = generation.meta.transcriptSource == "provided"
        let startTime = resolvedPlaybackTime(suggestion.startTime,
                                             mapsReferenceTime: mapsReferenceTime,
                                             episodeUuid: suggestion.episodeUuid)
        let endTime = resolvedPlaybackTime(suggestion.endTime,
                                           mapsReferenceTime: mapsReferenceTime,
                                           episodeUuid: suggestion.episodeUuid)

        let bookmark = bookmarkManager.add(to: episode, at: startTime, title: suggestion.title)
        guard let bookmark else { return }

        if let excerpt = suggestion.excerpt, !excerpt.isEmpty {
            let trimmed = await bookmarkManager.updateTrim(excerpt: excerpt, endTime: endTime, for: bookmark)
            if !trimmed {
                // The bookmark itself is sound (right time, right title), so
                // the acceptance stands — only the enrichment went missing.
                FileLog.shared.addMessage("SuggestedHighlights: trim enrichment failed for accepted suggestion \(bookmark.uuid)")
            }
        }
        dataManager.salientSegments.setStatus(.accepted, episodeUuid: suggestion.episodeUuid,
                                              rank: suggestion.rank, bookmarkUuid: bookmark.uuid)
        NotificationCenter.postOnMainThread(SuggestedHighlightsUpdated())
        Analytics.track(.suggestedHighlightAccepted, properties: ["episode_uuid": suggestion.episodeUuid])
    }

    func dismiss(_ suggestion: SalientSegmentRecord) {
        dataManager.salientSegments.setStatus(.dismissed, episodeUuid: suggestion.episodeUuid, rank: suggestion.rank)
        NotificationCenter.postOnMainThread(SuggestedHighlightsUpdated())
        Analytics.track(.suggestedHighlightDismissed, properties: ["episode_uuid": suggestion.episodeUuid])
    }

    /// Same mapping rule as the tour's `resolvedSeekTime`: only reference-
    /// timeline transcripts, and only while the episode's fingerprint
    /// alignment is already active.
    private func resolvedPlaybackTime(
        _ referenceTime: TimeInterval,
        mapsReferenceTime: Bool,
        episodeUuid: String
    ) -> TimeInterval {
        guard mapsReferenceTime,
              case .active = FingerprintTimingManager.shared.state,
              let mapped = FingerprintTimingManager.shared.playbackTime(
                  forReferenceTime: referenceTime, episodeUuid: episodeUuid) else {
            return referenceTime
        }
        return mapped
    }
}

/// Posted whenever the pending-suggestion set changes.
nonisolated struct SuggestedHighlightsUpdated: NotificationCenter.MainActorMessage {
    typealias Subject = AnyObject
    static var name: Notification.Name { Notification.Name("SJSuggestedHighlightsUpdated") }

    static func makeMessage(_ notification: Notification) -> Self? {
        Self()
    }

    static func makeNotification(_ message: Self) -> Notification {
        Notification(name: name)
    }
}
