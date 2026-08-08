import Foundation
import GRDB
import GRDBMacros

/// A text document the user imported to be read aloud (migration 91, ADR-0020).
///
/// The durable half of Read Aloud. It owns the retained `.txt`/`.md` file and
/// everything derived from reading it; narrations come and go against it. A
/// document with no narrations is an ordinary resting state — it is what
/// deleting the generated episode leaves behind.
///
/// Device-local: no `syncStatus`, no journal hooks, nothing here ever leaves the
/// device.
@GRDBRecord(table: "ReadAloudDocument")
public struct ReadAloudDocumentRecord: Equatable, Sendable {
    public var uuid = ""

    /// Editable display name, seeded from a leading heading or the filename.
    public var title = ""

    /// The picked file's name, kept for display when the user renamed the
    /// document. Nil for composed text, which never had a file.
    public var originalFilename: String?

    /// Raw `NarrationSourceKind`.
    public var sourceKind: Int32 = 0

    /// UTType identifier the document was extracted as, so a re-extract routes
    /// to the same extractor even when the extension is ambiguous.
    public var utType: String?

    /// Path of the retained source copy, relative to the sources directory.
    /// Relative rather than absolute because the app container's path changes
    /// between installs and OS upgrades.
    public var sourcePath = ""

    /// Narratable characters — what the duration estimate and any cost
    /// confirmation are computed from. Not the file's byte count.
    public var characterCount: Int32 = 0

    /// BCP-47 identifier detected at import, or nil when detection was
    /// inconclusive.
    public var language: String?

    public var addedDate: Double = 0

    public init() {}

    public var source: NarrationSourceKind {
        get { NarrationSourceKind(rawValue: sourceKind) ?? .picked }
        set { sourceKind = newValue.rawValue }
    }
}

/// One attempt to render a document in one voice (migration 91, ADR-0020).
///
/// Pipeline state, not content: the document is the file at its `sourcePath`,
/// and the audio is the `UserEpisode` at `episodeUuid`. Several narrations may
/// exist for a document over time — a different voice, a retry after a failure —
/// and they all share the document's single source file.
@GRDBRecord(table: "Narration")
public struct NarrationRecord: Equatable, Sendable {
    public var uuid = ""

    /// The `ReadAloudDocumentRecord` this renders.
    public var documentUuid = ""

    /// Raw `NarrationEngineKind`.
    public var engineKind: Int32 = 0

    /// Provider identifier when `engineKind` is a remote provider; nil otherwise.
    public var providerId: String?

    /// The provider model that rendered this, frozen at enqueue like the voice.
    /// Nil for the built-in engine. See migration 92 for why it cannot be read
    /// from settings at render time.
    public var modelId: String?

    public var voiceId = ""
    public var voiceName = ""

    /// Speaking rate as a multiplier of normal pace. Not exposed in the UI — the
    /// player's own speed control does that job live and reversibly — but kept
    /// so a per-narration rate can be added without a migration.
    public var rate: Double = 1

    /// Raw `NarrationState`.
    public var state: Int32 = 0

    public var chunkCount: Int32 = 0

    /// How many chunks have been rendered to the workspace. This IS the
    /// checkpoint — there is no manifest file. Safe because the synthesis
    /// settings above are frozen at enqueue, so a resumed run cannot be
    /// rendering something different from what the completed chunks hold.
    public var completedChunkCount: Int32 = 0

    /// The generated episode, or nil until completion. Deleting the episode
    /// deletes this narration rather than nulling the link — the document is
    /// what survives (ADR-0019).
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
}

/// Lifecycle of a Narration. Raw values are persisted in `Narration.state` —
/// never renumber.
///
/// Every case is an attempt in flight or an attempt that ended. There is no
/// state meaning "finished, but the audio is gone": deleting the episode deletes
/// the narration, and the document it belonged to expresses "nothing narrated
/// right now" all by itself.
public enum NarrationState: Int32, Sendable, CaseIterable {
    case queued = 0
    case rendering = 1
    case completed = 2
    case failed = 3
    case cancelled = 4

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

/// How a document arrived. Persisted in `ReadAloudDocument.sourceKind` — never
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
