import Foundation

/// One structural unit of an extracted document. Extractors flatten whatever
/// markup they parse down to this: narration only cares about "run of prose" vs
/// "heading", and headings exist as their own kind so the chunker can force a
/// break (and so a future phase can promote them to chapters).
public struct DocumentBlock: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        case paragraph
        /// `level` is the source's heading depth (1 = top level), clamped by the
        /// extractor to 1...6.
        case heading(level: Int)
    }

    public let kind: Kind
    /// Narration-ready plain text: markup already stripped, whitespace collapsed.
    public let text: String

    public init(kind: Kind, text: String) {
        self.kind = kind
        self.text = text
    }

    public var isHeading: Bool {
        if case .heading = kind { return true }
        return false
    }
}

/// The output of extraction: a document reduced to narratable blocks plus the
/// metadata the import screen needs before anything is synthesized.
public struct ExtractedDocument: Sendable, Equatable {
    /// Title proposed to the user, derived from a leading heading when the
    /// document has one and from the filename otherwise. Always editable.
    public let suggestedTitle: String
    public let blocks: [DocumentBlock]
    /// Total narratable characters — what the cost-confirmation gate and the
    /// duration estimate are computed from. Not the file's byte count.
    public let characterCount: Int
    /// BCP-47 identifier from language detection, or nil when detection was
    /// inconclusive (very short documents, symbol soup).
    public let detectedLanguage: String?

    /// Longest document that may be narrated. ~500k characters is roughly ten
    /// hours of audio — past the point where synthesizing a whole document
    /// eagerly is a sensible thing to start. Public so the compose screen can
    /// warn while typing rather than only failing at extraction.
    public static let maximumCharacterCount = 500_000

    public init(suggestedTitle: String, blocks: [DocumentBlock], characterCount: Int, detectedLanguage: String?) {
        self.suggestedTitle = suggestedTitle
        self.blocks = blocks
        self.characterCount = characterCount
        self.detectedLanguage = detectedLanguage
    }
}

/// A unit of synthesis: whole sentences packed to fit an engine's per-request
/// limit. Deliberately NOT called a "segment" — that word is taken by the
/// transcript corpus and by Salient Segments.
///
/// `index` is the chunk's position in the narration and is what makes resume
/// work: the queue writes `chunk-<index>.caf` and skips indices whose file
/// already exists. Chunking is pure and deterministic, so the same document and
/// the same limit always reproduce the same indices.
public struct NarrationChunk: Sendable, Equatable {
    public let index: Int
    public let text: String
    /// True when this chunk starts a new block, which is where the assembler
    /// inserts a pause.
    public let startsBlock: Bool

    public init(index: Int, text: String, startsBlock: Bool) {
        self.index = index
        self.text = text
        self.startsBlock = startsBlock
    }
}

/// Failures surfaced by extraction, chunking and synthesis engines. Cases map
/// onto user-facing recovery guidance in the app layer.
public enum ReadAloudError: Error, Sendable, Equatable {
    /// No registered extractor claims this file's type.
    case unsupportedFileType
    /// The file could not be decoded as text under any candidate encoding.
    case undecodableText
    /// Decoded fine but contains nothing narratable (empty, or only markup).
    case emptyDocument
    /// Over the character cap; payload is the cap that was exceeded.
    case documentTooLarge(limit: Int)
    /// The selected engine needs an API key and none is configured.
    case apiKeyMissing
    /// Provider rejected the key (HTTP 401/403).
    case invalidAPIKey
    /// The key is valid but lacks the permission this call needs — an ElevenLabs
    /// key granted only speech-to-text hits this, and it must never be reported
    /// as an invalid key.
    case insufficientKeyPermissions
    /// Provider refused for billing/rate reasons; `retryAfter` is the provider's
    /// hint in seconds when it supplied one.
    case rateLimited(retryAfter: TimeInterval?)
    /// Provider rejected the request. `providerMessage` is provider-generated and
    /// may echo request identifiers or user text, so it stays in memory only —
    /// `sanitizedDescription` drops it.
    case providerResponseFailure(status: Int?, providerMessage: String)
    case networkUnavailable
    /// The selected voice is no longer installed or offered.
    case voiceUnavailable
    /// The engine produced no audio for a chunk.
    case synthesisProducedNoAudio
    /// Chunk files could not be joined or encoded.
    case assemblyFailed
    /// The retained source file is missing or unreadable, so the narration can
    /// neither run nor resume.
    case sourceUnreadable
    /// The document or narration rows could not be written.
    case persistenceFailure
    /// Engine failed for a reason with no more specific case.
    case engineFailure
    case cancelled
}

public extension ReadAloudError {
    /// Stable, low-cardinality identifier persisted in `Narration.errorCode` and
    /// sent to analytics. Deliberately hand-written rather than derived from the
    /// case name: these strings outlive refactors and must never carry payloads.
    var code: String {
        switch self {
        case .unsupportedFileType: "unsupported_file_type"
        case .undecodableText: "undecodable_text"
        case .emptyDocument: "empty_document"
        case .documentTooLarge: "document_too_large"
        case .apiKeyMissing: "api_key_missing"
        case .invalidAPIKey: "invalid_api_key"
        case .insufficientKeyPermissions: "insufficient_key_permissions"
        case .rateLimited: "rate_limited"
        case .providerResponseFailure: "provider_response_failure"
        case .networkUnavailable: "network_unavailable"
        case .voiceUnavailable: "voice_unavailable"
        case .synthesisProducedNoAudio: "synthesis_produced_no_audio"
        case .assemblyFailed: "assembly_failed"
        case .sourceUnreadable: "source_unreadable"
        case .persistenceFailure: "persistence_failure"
        case .engineFailure: "engine_failure"
        case .cancelled: "cancelled"
        }
    }

    /// Description safe for file logs and persisted records: static case content
    /// only, with provider-generated payloads reduced to the HTTP status.
    var sanitizedDescription: String {
        switch self {
        case .providerResponseFailure(let status, _):
            status.map { "providerResponseFailure(HTTP \($0))" } ?? "providerResponseFailure"
        default:
            String(describing: self)
        }
    }

    /// Whether retrying could plausibly succeed on its own.
    ///
    /// There is deliberately no automatic retry — a failed narration keeps its
    /// workspace, so the user's Retry resumes from the last good chunk with
    /// nothing re-rendered or re-paid. This exists to choose what the failure
    /// *says*: "try again" for a blip the user can simply re-run, versus
    /// something they have to go and fix, like a rejected key.
    var isTransient: Bool {
        switch self {
        case .rateLimited, .networkUnavailable:
            true
        case .providerResponseFailure(let status, _):
            // 5xx may clear on a retry; client errors (400, 422, …) will just
            // repeat. No status means the response never parsed, which smells
            // like network trouble and is worth one more attempt.
            status.map { $0 >= 500 } ?? true
        default:
            false
        }
    }
}
