import Combine
import Foundation
import PocketCastsDataModel
import PocketCastsUtils

/// Enriches freshly created bookmarks into smart highlights: loads the episode's
/// transcript, stores the excerpt around the bookmark position (plus the window's
/// end time) on the bookmark row, and auto-titles bookmarks the user hasn't
/// renamed.
///
/// Owned by `BookmarkManager` and driven by its `onBookmarkCreated` events. Every
/// pipeline step is best-effort: an episode without a transcript keeps its plain
/// bookmark, exactly as before the feature existed.
final class HighlightEnricher {
    private weak var bookmarkManager: BookmarkManager?
    private let dataManager: DataManager
    /// FM auto-titles with a deterministic fallback; the default generator wires
    /// itself to `OnDeviceIntelligence.shared`.
    private let titleGenerator: HighlightTitleGenerator

    /// Bookmarks currently being enriched, so replayed create events can't run the
    /// pipeline twice concurrently for the same bookmark.
    private var inFlight = Set<String>()

    private var cancellables = Set<AnyCancellable>()

    init(bookmarkManager: BookmarkManager,
         dataManager: DataManager = .sharedManager,
         titleGenerator: HighlightTitleGenerator = HighlightTitleGenerator()) {
        self.bookmarkManager = bookmarkManager
        self.dataManager = dataManager
        self.titleGenerator = titleGenerator

        bookmarkManager.onBookmarkCreated
            .receive(on: DispatchQueue.main)
            .filter { !$0.isDuplicate }
            .sink { [weak self] event in
                self?.enrichIfNeeded(bookmarkUuid: event.uuid)
            }
            .store(in: &cancellables)
    }

    func enrichIfNeeded(bookmarkUuid: String) {
        guard FeatureFlag.smartHighlights.enabled else { return }
        guard !inFlight.contains(bookmarkUuid) else { return }
        inFlight.insert(bookmarkUuid)

        Task { [weak self] in
            await self?.enrich(bookmarkUuid: bookmarkUuid)
            self?.inFlight.remove(bookmarkUuid)
        }
    }

    // MARK: - Pipeline

    private func enrich(bookmarkUuid: String) async {
        // Dedupe guard: the auto path is write-once, so a bookmark that already has
        // an excerpt (local run or sync) is left alone — and a user-trimmed window
        // (trimModified set) is authoritative and never regenerated (ADR-0016).
        // `updateEnrichment` re-checks the trim stamp at the write itself.
        guard let bookmark = dataManager.bookmarks.bookmark(for: bookmarkUuid),
              bookmark.excerpt == nil,
              bookmark.trimModified == nil else {
            return
        }

        // The fingerprint mapping only ever tracks the currently playing episode;
        // capture that gate on the main actor before hopping off.
        let allowFingerprintMapping: Bool = {
            guard PlaybackManager.shared.currentEpisode()?.uuid == bookmark.episodeUuid,
                  case .active = FingerprintTimingManager.shared.state else {
                return false
            }
            return true
        }()

        // Transcript download + parsing + cue-window work happens off the main
        // actor; a detached task also keeps the fingerprint manager's internal
        // `queue.sync` lookups away from the main thread.
        let result = await Task.detached(priority: .utility) {
            await HighlightEnricher.buildEnrichment(for: bookmark, allowFingerprintMapping: allowFingerprintMapping)
        }.value

        switch result {
        case .failure(let reason):
            // No transcript (or nothing said in the window) → plain bookmark, no regression.
            FileLog.shared.addMessage("[Highlights] Skipped enrichment for \(bookmarkUuid): \(reason.rawValue)")
            Analytics.track(.highlightEnrichmentFailed, properties: [
                "episode_uuid": bookmark.episodeUuid,
                "reason": reason.rawValue
            ])

        case .success(let enrichment):
            guard await dataManager.bookmarks.updateEnrichment(
                uuid: bookmarkUuid,
                excerpt: enrichment.excerpt,
                endTime: enrichment.endTime
            ) else {
                Analytics.track(.highlightEnrichmentFailed, properties: [
                    "episode_uuid": bookmark.episodeUuid,
                    "reason": "write_failed"
                ])
                return
            }

            bookmarkManager?.onBookmarkChanged.send(.init(uuid: bookmarkUuid, change: .excerpt(enrichment.excerpt)))

            await applyAutoTitleIfUnrenamed(bookmarkUuid: bookmarkUuid, excerpt: enrichment.excerpt)

            FileLog.shared.addMessage("[Highlights] Enriched bookmark \(bookmarkUuid) (mapped: \(enrichment.usedTimeMapping))")
            Analytics.track(.highlightEnrichmentCompleted, properties: [
                "episode_uuid": bookmark.episodeUuid,
                "used_time_mapping": enrichment.usedTimeMapping
            ])
        }
    }

    /// Applies the generated title, but only when the user hasn't renamed the
    /// bookmark in the meantime (the edit sheet pops right after creation, so a
    /// rename can easily race the enrichment).
    private func applyAutoTitleIfUnrenamed(bookmarkUuid: String, excerpt: String) async {
        guard let title = await titleGenerator.title(for: excerpt) else { return }

        guard let current = dataManager.bookmarks.bookmark(for: bookmarkUuid),
              Self.shouldApplyAutoTitle(currentTitle: current.title) else {
            return
        }

        // Routing through the manager emits onBookmarkChanged and journals the edit.
        await bookmarkManager?.update(title: title, for: current)
    }

    /// Pure rename-race guard: auto-titles only ever replace the untouched default.
    nonisolated static func shouldApplyAutoTitle(currentTitle: String) -> Bool {
        currentTitle == L10n.bookmarkDefaultTitle
    }

    // MARK: - Off-main enrichment build

    struct Enrichment: Sendable {
        let excerpt: String
        /// End of the excerpt window, in the bookmark's own (playback) time domain.
        let endTime: TimeInterval
        let usedTimeMapping: Bool
    }

    enum EnrichmentFailure: String, Sendable, Error {
        case noTranscript = "no_transcript"
        case noCuesInWindow = "no_cues_in_window"
    }

    /// Loads the transcript and builds the excerpt payload. Server-generated
    /// transcripts are timed against the reference audio, so the bookmark's
    /// playback time maps through the fingerprint alignment when it's active;
    /// locally generated and podcast-provided transcripts align natively, so the
    /// raw time is used.
    nonisolated private static func buildEnrichment(
        for bookmark: Bookmark,
        allowFingerprintMapping: Bool
    ) async -> Result<Enrichment, EnrichmentFailure> {
        let transcriptManager = TranscriptManager(
            episodeUUID: bookmark.episodeUuid,
            podcastUUID: bookmark.podcastUuid ?? ""
        )

        guard let transcript = try? await transcriptManager.loadTranscript(),
              !transcript.cues.isEmpty else {
            return .failure(.noTranscript)
        }

        let mappingApplies = allowFingerprintMapping
            && transcriptManager.isDisplayingGeneratedTranscript
            && !transcriptManager.isDisplayingLocalTranscription

        // The transcript download above can outlive a track change, after which
        // the shared fingerprint manager holds the NEXT episode's alignment —
        // the episode-bound calls return nil instead of mapping through it.
        var anchor = bookmark.time
        var usedTimeMapping = false
        if mappingApplies,
           let mapped = FingerprintTimingManager.shared.referenceTime(forPlaybackTime: bookmark.time, episodeUuid: bookmark.episodeUuid) {
            anchor = mapped
            usedTimeMapping = true
        }

        guard let excerpt = HighlightExcerptBuilder.smartExcerpt(
            around: anchor,
            cues: transcript.cues,
            plainText: transcript.plainText
        ) else {
            return .failure(.noCuesInWindow)
        }

        // Store endTime in the same domain as `time` (playback), mapping the cue
        // window's end back when the anchor was mapped out.
        var endTime = excerpt.endTime
        if usedTimeMapping {
            if let mappedBack = FingerprintTimingManager.shared.playbackTime(forReferenceTime: excerpt.endTime, episodeUuid: bookmark.episodeUuid) {
                endTime = mappedBack
            } else {
                // The mapping vanished between the two calls (track change):
                // approximate with the window's duration — both times are on the
                // reference timeline, so the span carries over closely enough.
                endTime = bookmark.time + max(0, excerpt.endTime - anchor)
            }
        }
        endTime = max(endTime, bookmark.time)

        return .success(Enrichment(excerpt: excerpt.text, endTime: endTime, usedTimeMapping: usedTimeMapping))
    }
}
