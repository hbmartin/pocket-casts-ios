import Foundation
import GRDB
import GRDBMacros

/// One ranked salient segment of an episode (migration 88, ADR-0018): the
/// on-device model's `[start, end, title]` judgment of a moment worth
/// revisiting. One generation per episode serves both the Highlights Tour
/// (prefix-by-rank under a time budget) and Suggested Highlights (top ranks
/// surfaced for review). Times are in the transcript's own time domain; the
/// source lives on the meta row.
@GRDBRecord(table: "SalientSegment")
public struct SalientSegmentRecord: Equatable, Sendable {
    public var episodeUuid = ""

    /// 0-based salience order: rank 0 is the most important segment.
    public var rank: Int32 = 0

    public var startTime: Double = 0
    public var endTime: Double = 0
    public var title = ""

    /// Model importance 1...10 (kept for re-ranking/debugging; rank is derived).
    public var score: Int32 = 0

    /// The segment's cue text, captured at generation time so acceptance can
    /// enrich the created Bookmark without re-loading the transcript.
    public var excerpt: String?

    public var suggestionStatus: Int32 = SalientSuggestionStatus.candidate.rawValue

    /// Set when the suggestion was accepted: the created Bookmark's uuid.
    public var bookmarkUuid: String?

    public init() {}

    public var status: SalientSuggestionStatus {
        get { SalientSuggestionStatus(rawValue: suggestionStatus) ?? .candidate }
        set { suggestionStatus = newValue.rawValue }
    }
}

/// The review-queue lifecycle of a segment. `candidate` rows only serve the
/// tour; `pending` rows also appear in the Suggested section.
public enum SalientSuggestionStatus: Int32, Sendable {
    case candidate = 0
    case pending = 1
    case accepted = 2
    case dismissed = 3
}

/// Per-episode generation bookkeeping (migration 88). A row with
/// `outcome == .noSegments` is the durable "don't retry" sentinel; transient
/// failures write nothing so a later attempt retries (the
/// `TranscriptChapterGenerator` semantics).
@GRDBRecord(table: "SalientSegmentMeta")
public struct SalientSegmentMetaRecord: Equatable, Sendable {
    public var episodeUuid = ""
    public var podcastUuid: String?
    public var outcome: Int32 = SalientSegmentOutcome.segments.rawValue

    /// "generated" | "provided" — drives seek-time mapping semantics.
    public var transcriptSource = ""

    /// Bumping the generator version orphans old rows for lazy regeneration.
    public var generatorVersion: Int32 = 0

    public var generatedAt: Double = 0
    public var segmentCount: Int32 = 0

    public init() {}
}

public enum SalientSegmentOutcome: Int32, Sendable {
    case segments = 0
    case noSegments = 1
}
