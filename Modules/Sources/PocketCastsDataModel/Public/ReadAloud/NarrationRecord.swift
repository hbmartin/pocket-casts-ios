import Foundation
import GRDB
import GRDBMacros

/// One Narration (migration 91, ADR-0019): a text document rendered by one voice
/// into one episode.
///
/// The row is pipeline state, not content. The document itself is the file at
/// `sourcePath`; the audio is the `UserEpisode` at `episodeUuid`. Both can
/// outlive the other — deleting the episode nulls `episodeUuid` and leaves the
/// document narratable again, and deleting the document takes the episode with
/// it.
///
/// Device-local: no `syncStatus`, no journal hooks, nothing here ever leaves the
/// device.
@GRDBRecord(table: "Narration")
public struct NarrationRecord: Equatable, Sendable {
    public var uuid = ""
    public var title = ""

    /// The picked file's name, kept for display when the user renamed the
    /// narration. Nil for composed text, which never had a file.
    public var originalFilename: String?

    /// Raw `NarrationSourceKind`.
    public var sourceKind: Int32 = 0

    /// UTType identifier the document was extracted as, so a re-extract on
    /// resume routes to the same extractor even if the extension is ambiguous.
    public var utType: String?

    /// Path of the retained source copy, relative to the sources directory.
    /// Relative rather than absolute because the app container's path changes
    /// between installs and OS upgrades.
    public var sourcePath = ""

    public var characterCount: Int32 = 0

    /// BCP-47 identifier detected at import, or nil when detection was
    /// inconclusive.
    public var language: String?

    /// Raw `NarrationEngineKind`.
    public var engineKind: Int32 = 0

    /// Provider identifier when `engineKind` is a remote provider; nil otherwise.
    public var providerId: String?

    public var voiceId = ""
    public var voiceName = ""

    /// Speaking rate as a multiplier of normal pace.
    public var rate: Double = 1

    /// Raw `NarrationState`.
    public var state: Int32 = 0

    public var chunkCount: Int32 = 0

    /// How many chunks have been rendered to the workspace. This IS the
    /// checkpoint — there is no manifest file. Safe because the synthesis
    /// settings above are frozen at enqueue, so a resumed run cannot be
    /// rendering something different from what the completed chunks hold.
    public var completedChunkCount: Int32 = 0

    /// The generated episode, or nil before completion and after the user
    /// deletes it.
    public var episodeUuid: String?

    /// Stable `ReadAloudError.code` of the last failure.
    public var errorCode: String?

    /// Developer-authored failure detail. Never provider-generated text — that
    /// can echo user content, and this string reaches file logs.
    public var errorDetails: String?

    public var createdDate: Double = 0
    public var completedDate: Double?
    public var outputDuration: Double?
    public var outputSizeInBytes: Int64?

    public init() {}

    public var narrationState: NarrationState {
        get { NarrationState(rawValue: state) ?? .queued }
        set { state = newValue.rawValue }
    }

    public var engine: NarrationEngineKind {
        get { NarrationEngineKind(rawValue: engineKind) ?? .appleBuiltIn }
        set { engineKind = newValue.rawValue }
    }

    public var source: NarrationSourceKind {
        get { NarrationSourceKind(rawValue: sourceKind) ?? .picked }
        set { sourceKind = newValue.rawValue }
    }
}

/// Lifecycle of a Narration. Raw values are persisted in `Narration.state` —
/// never renumber.
///
/// `detached` is reached when the user deletes the generated episode: the audio
/// is gone but the source document survives, so the row stays and offers a
/// regenerate. It is a resting state, not a failure.
public enum NarrationState: Int32, Sendable, CaseIterable {
    case queued = 0
    case rendering = 1
    case completed = 2
    case failed = 3
    case cancelled = 4
    case detached = 5

    /// States a launch-time resume should pick up. `rendering` is included
    /// because a process kill leaves the row exactly as it was mid-run — there
    /// is no chance to write a "stopped" state on the way down.
    public static let resumable: [NarrationState] = [.queued, .rendering]
}

/// Which synthesis stack rendered (or should render) a Narration. Raw values are
/// persisted in `Narration.engineKind` — never renumber.
///
/// `localModel` is reserved, not implemented: local TTS stays blocked behind the
/// espeak-ng (GPL-3.0) phonemization review. Its slot is claimed now so the
/// column never needs renumbering when it lands.
public enum NarrationEngineKind: Int32, Sendable, CaseIterable {
    case appleBuiltIn = 0
    case localModel = 1
    case remoteProvider = 2
}

/// How the source document arrived. Persisted in `Narration.sourceKind` — never
/// renumber.
public enum NarrationSourceKind: Int32, Sendable, CaseIterable {
    /// Picked from the Files screen's document picker.
    case picked = 0
    /// Typed or pasted into the compose screen.
    case composed = 1
    /// Arrived via share sheet, Open-in, or the import-file URL route.
    case shared = 2
    /// Created by an App Intent / Shortcut.
    case intent = 3
}
