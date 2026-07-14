import Foundation

/// Everything the client uploads for one transcript contribution
/// (docs/TranscriptContributions.md §3, `POST transcripts/contribute`).
///
/// The blob fields carry the bytes exactly as they go on the wire: the VTT and
/// fingerprint are individually gzipped by the pipeline before they are queued.
public struct TranscriptContributionPayload: Equatable, Sendable {
    /// Catalog UUID or deterministic local-feed identity — indistinguishable by design.
    public let episodeUuid: String
    public let podcastUuid: String
    /// Gzipped VTT bytes, speaker labels included, exactly the on-device artifact.
    public let gzippedVtt: Data
    /// Gzipped `fingerprint-compact-v2` JSON of the contributor's audio stitch.
    public let gzippedFingerprint: Data
    /// `whisperkit` | `applespeech` | remote provider identifier.
    public let engine: String
    /// The specific producer, e.g. `whisper-large-v3-turbo`, `apple-speech-ios26`.
    public let modelId: String
    /// BCP-47 as reported by the engine.
    public let language: String
    public let diarized: Bool
    /// Build marketing version.
    public let appVersion: String
    /// Sanity anchor for server-side validation.
    public let episodeDurationSeconds: TimeInterval
    /// Contribution creation time (no listening timestamps).
    public let createdAt: Date

    public init(episodeUuid: String,
                podcastUuid: String,
                gzippedVtt: Data,
                gzippedFingerprint: Data,
                engine: String,
                modelId: String,
                language: String,
                diarized: Bool,
                appVersion: String,
                episodeDurationSeconds: TimeInterval,
                createdAt: Date) {
        self.episodeUuid = episodeUuid
        self.podcastUuid = podcastUuid
        self.gzippedVtt = gzippedVtt
        self.gzippedFingerprint = gzippedFingerprint
        self.engine = engine
        self.modelId = modelId
        self.language = language
        self.diarized = diarized
        self.appVersion = appVersion
        self.episodeDurationSeconds = episodeDurationSeconds
        self.createdAt = createdAt
    }
}

/// A sighting of a publisher-provided transcript
/// (docs/TranscriptContributions.md §3, `POST transcripts/sighting`).
/// The server fetches the transcript content itself; the client only reports the URL.
public struct TranscriptSightingPayload: Equatable, Sendable {
    public let episodeUuid: String
    public let podcastUuid: String
    /// Token-free publisher URL (enforced client-side before queueing, re-validated server-side).
    public let transcriptUrl: String
    /// Mime type of the sighted transcript.
    public let format: String
    /// Optional BCP-47 tag; nil when the feed didn't declare one.
    public let language: String?

    public init(episodeUuid: String,
                podcastUuid: String,
                transcriptUrl: String,
                format: String,
                language: String?) {
        self.episodeUuid = episodeUuid
        self.podcastUuid = podcastUuid
        self.transcriptUrl = transcriptUrl
        self.format = format
        self.language = language
    }
}
