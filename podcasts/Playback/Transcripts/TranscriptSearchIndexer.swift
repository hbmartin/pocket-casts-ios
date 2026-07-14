import Foundation
import PocketCastsDataModel
import PocketCastsUtils

/// Feeds the unified transcript search index with podcast-provided transcripts:
/// whenever one loads successfully, its cue text is merged into FTS-friendly
/// segments and written to `TranscriptSegmentIndex` (`source: .provided`) in the
/// background.
///
/// The provided corpus is currently "transcripts the app has loaded" — there is no
/// download-triggered background indexing yet. Locally generated (on-device)
/// transcripts are never indexed here: `TranscriptManager.loadTranscript()` returns
/// them before the hook runs, and the transcription pipeline writes them into the
/// same unified index as `source: .generated`.
nonisolated final class TranscriptSearchIndexer: Sendable {
    static let shared = TranscriptSearchIndexer()

    /// Adjacent cues are merged until a segment reaches this many characters, so
    /// FTS rows carry a sentence-ish amount of context instead of 2-word fragments.
    static let minimumSegmentLength = 40

    /// Indexes the episode's transcript unless it is already in the index.
    /// Fire-and-forget: kicks a background task and returns immediately.
    func indexIfNeeded(episodeUuid: String, podcastUuid: String, model: TranscriptModel) {
        guard FeatureFlag.transcriptSearch.enabled else { return }

        // Background index writes into the live database are unwanted noise under
        // XCTest (TranscriptManager is exercised with random UUIDs there).
        guard !isRunningTests else { return }

        let index = DataManager.sharedManager.transcriptSearch
        // Migration 82 couldn't create the FTS5 tables on this device; the feature
        // self-disables (see TranscriptSearchDataManager.isAvailable).
        guard index.isAvailable else { return }

        Task.detached(priority: .utility) {
            _ = await self.index(episodeUuid: episodeUuid, podcastUuid: podcastUuid, model: model)
        }
    }

    /// Awaitable single entry point shared by the view trigger above and the
    /// download-triggered `TranscriptAcquisitionCoordinator`. Dedupes against the
    /// unified index and returns whether new segments were written. The write is
    /// transactionally idempotent, so a benign race between the two triggers can
    /// at worst duplicate the tokenize work, never the rows.
    func index(episodeUuid: String, podcastUuid: String, model: TranscriptModel) async -> Bool {
        let index = DataManager.sharedManager.transcriptSearch
        guard index.isAvailable else { return false }

        // Dedupe: an episode already in TranscriptSearchIndexMeta keeps its rows.
        guard !index.isIndexed(episodeUuid: episodeUuid, source: .provided) else { return false }

        let cues = Self.indexableCues(from: model)
        guard !cues.isEmpty else { return false }

        let indexed = index.replaceSegments(episodeUuid: episodeUuid, podcastUuid: podcastUuid, source: .provided, segments: cues)
        if indexed {
            FileLog.shared.addMessage("TranscriptSearchIndexer: indexed \(cues.count) segments for episode \(episodeUuid)")
            TranscriptEmbeddingPipeline.shared.embedIfNeeded(episodeUuid: episodeUuid, podcastUuid: podcastUuid, source: .provided)
        }
        return indexed
    }

    // MARK: - Cue extraction and merging (pure)

    /// Extracts each cue's text via its `characterRange` and merges adjacent cues
    /// until segments reach ``minimumSegmentLength`` characters. Cues with invalid
    /// ranges (out of the text's UTF-16 bounds) or whitespace-only text are
    /// skipped. Segment start/end times span the merged cues.
    static func indexableCues(from model: TranscriptModel) -> [TranscriptSearchSegment] {
        // characterRange offsets are UTF-16 (NSRange convention), so extraction
        // goes through NSString to keep the offsets honest.
        let fullText = model.plainText as NSString

        var segments = [TranscriptSearchSegment]()
        var pendingText = ""
        var pendingStart = 0.0
        var pendingEnd = 0.0

        func flushPending() {
            guard !pendingText.isEmpty else { return }
            segments.append(TranscriptSearchSegment(index: segments.count, text: pendingText, startTime: pendingStart, endTime: pendingEnd))
            pendingText = ""
        }

        for cue in model.cues {
            let range = cue.characterRange
            guard range.location != NSNotFound, range.length > 0, NSMaxRange(range) <= fullText.length else { continue }

            let text = fullText.substring(with: range).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }

            if pendingText.isEmpty {
                pendingText = text
                pendingStart = cue.startTime
            } else {
                pendingText += " " + text
            }
            pendingEnd = cue.endTime

            if pendingText.count >= minimumSegmentLength {
                flushPending()
            }
        }
        flushPending()

        return segments
    }
}
