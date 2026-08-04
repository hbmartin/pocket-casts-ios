import Foundation
import GRDB
import GRDBMacros

/// Lifecycle state of a locally generated episode transcription.
/// Stored in the `status` column of the `EpisodeTranscription` table.
public enum TranscriptionStatus: Int32, Sendable, CaseIterable {
    case queued = 0
    case processing = 1
    case completed = 2
    case failed = 3
    case cancelled = 4
}

/// Row record for the `EpisodeTranscription` table. One row per episode; the row is the
/// durable job/state record for locally generated diarized transcriptions. Device-local
/// only — no `sync_status`, no sync writes of any kind. Date columns are raw
/// `timeIntervalSince1970` Doubles, matching the other row records.
@GRDBRecord(table: "EpisodeTranscription")
public struct EpisodeTranscriptionRecord: Equatable, Sendable {
    public var episodeUuid = ""

    public var podcastUuid: String?

    /// Raw `TranscriptionStatus` value; prefer the typed `transcriptionStatus` accessor.
    public var status: Int32 = 0

    /// Raw engine-mode value. The cases (`appleBuiltIn = 0`, `localModel = 1`,
    /// `remoteProvider = 2`) are owned by `TranscriptionEngineMode` in the
    /// PocketCastsTranscription module, which this module deliberately doesn't depend on.
    public var engineMode: Int32 = 0

    /// Remote provider id (e.g. "assemblyai") when `engineMode` is remote.
    public var provider: String?

    /// Local model identifier (e.g. WhisperKit variant) when `engineMode` is local.
    public var modelId: String?

    /// BCP-47 language of the transcript, when known.
    public var language: String?

    public var createdAt: Double = 0

    public var updatedAt: Double = 0

    /// Duration of the transcribed audio, in seconds.
    public var durationSecs: Double = 0

    public var speakerCount: Int32 = 0

    /// User speaker renames as a JSON object, e.g. `{"Speaker 1":"Alice"}`.
    public var speakerNames: String?

    public var errorMessage: String?

    /// Provider-side job id for in-flight remote transcriptions, so polling can resume.
    public var remoteJobId: String?

    /// Path of the generated VTT artifact on disk. The app layer owns the file.
    public var filePath: String?

    public init() {}
}

public extension EpisodeTranscriptionRecord {
    /// Typed view over the raw `status` column. Unknown raw values read as `.queued`,
    /// which is the safe interpretation (the job will be re-examined, never lost).
    var transcriptionStatus: TranscriptionStatus {
        get { TranscriptionStatus(rawValue: status) ?? .queued }
        set { status = newValue.rawValue }
    }
}
