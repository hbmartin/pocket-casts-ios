import Foundation

/// How good a voice sounds, ranked.
///
/// This matters more than it looks: iOS ships only `standard` (compact) voices
/// by default, and they are audibly robotic. The better ones are on-demand
/// downloads the user has to fetch by hand, so the UI has to be able to rank
/// voices, prefer the best available, and tell when nothing good is installed.
public enum VoiceQuality: Int, Sendable, Comparable, CaseIterable {
    case standard = 0
    case enhanced = 1
    case premium = 2

    public static func < (lhs: VoiceQuality, rhs: VoiceQuality) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// A voice a synthesis engine can speak in.
public struct SynthesisVoice: Sendable, Equatable, Identifiable {
    /// Stable identifier persisted on the narration row. For the built-in engine
    /// this is `AVSpeechSynthesisVoice.identifier`; for providers it's their
    /// voice id.
    public let id: String
    public let name: String
    /// BCP-47 identifier, used to group the picker and to match the document's
    /// detected language.
    public let language: String
    /// How good this voice sounds. Providers that make no such distinction
    /// report `.standard`.
    public let quality: VoiceQuality
    /// A free sample the app may play without spending the user's quota. Nil
    /// means previewing this voice would cost something, so the app must not
    /// offer it.
    public let previewURL: URL?

    public init(id: String, name: String, language: String, quality: VoiceQuality = .standard, previewURL: URL? = nil) {
        self.id = id
        self.name = name
        self.language = language
        self.quality = quality
        self.previewURL = previewURL
    }
}

/// Which block boundaries are required to end a chunk.
///
/// A pause exists only *between* rendered chunk files — the assembler advances a
/// cursor between them — so this decides which of a document's pauses survive,
/// and with it how many requests a narration costs.
///
/// The two answers suit two kinds of engine. Rendering locally is free, so the
/// built-in engine breaks everywhere and keeps every pause. A network engine
/// pays a round trip per chunk, and a document of short paragraphs is mostly
/// boundaries: a 31k-character sample with 137 blocks produced 137 chunks at 11%
/// of the size limit, which as sequential HTTPS calls is minutes of latency and
/// 137 chances to fail. Packing paragraphs together and breaking only at
/// headings cut that sample to roughly 48 while keeping the pauses that carry
/// structure — a heading running into its own body text is the one that sounds
/// broken.
public enum ChunkBoundary: Sendable, Equatable, CaseIterable {
    /// Every block ends a chunk. Every paragraph and heading keeps its pause.
    case everyBlock
    /// Only headings end a chunk; consecutive paragraphs pack together and lose
    /// the pause between them.
    case headingsOnly
}

/// What the app needs to know about an engine before it can build a sensible
/// UI or plan a run, without special-casing engines by identity.
public struct EngineCapabilities: Sendable, Equatable {
    /// Hard per-request character limit; the chunker targets a fraction of it.
    public let maxCharactersPerChunk: Int
    /// How many chunks may be in flight at once. Local engines stay at 1 —
    /// they're CPU-bound, so concurrency buys nothing and costs battery.
    public let maxConcurrentChunks: Int
    /// Which block boundaries must end a chunk.
    public let chunkBoundary: ChunkBoundary
    public let requiresAPIKey: Bool
    /// Whether a run costs the user money, and so must be confirmed first.
    public let requiresConfirmation: Bool

    public init(
        maxCharactersPerChunk: Int,
        maxConcurrentChunks: Int,
        requiresAPIKey: Bool,
        requiresConfirmation: Bool,
        chunkBoundary: ChunkBoundary = .everyBlock
    ) {
        self.maxCharactersPerChunk = maxCharactersPerChunk
        self.maxConcurrentChunks = maxConcurrentChunks
        self.chunkBoundary = chunkBoundary
        self.requiresAPIKey = requiresAPIKey
        self.requiresConfirmation = requiresConfirmation
    }
}

/// Per-run synthesis settings chosen by the user at import and then frozen onto
/// the narration row. Immutability is what lets resume skip the fingerprinting
/// the original design called for: settings cannot drift mid-run, because
/// changing them means starting a different narration.
public struct SynthesisSettings: Sendable, Equatable {
    /// Speaking rate as a multiplier of the engine's normal pace (1.0 = normal).
    /// Engines clamp it to their own range.
    public let rate: Float

    public init(rate: Float = 1) {
        self.rate = rate
    }
}

/// Text in, an audio file out. Implementations: `AppleSpeechSynthesisEngine`
/// (this module) and the provider-backed engines.
///
/// Engines never touch the Keychain — an API key arrives as a parameter, so this
/// module has no opinion about credential storage and stays dependency-free.
public protocol SpeechSynthesisEngine: Sendable {
    /// Stable identifier persisted with the narration (e.g. "apple.avspeech").
    var id: String { get }
    var capabilities: EngineCapabilities { get }

    /// Voices this engine can currently speak in. May hit the network for
    /// provider-backed engines, so callers should cache the result for the
    /// lifetime of a picker.
    func availableVoices(apiKey: String?) async throws -> [SynthesisVoice]

    /// Renders one chunk to `outputURL`, overwriting anything already there.
    ///
    /// Implementations call `Task.checkCancellation()` at their coarsest safe
    /// boundary so queue cancellation lands promptly. Throwing means the file at
    /// `outputURL` is not to be trusted; the queue deletes it before retrying,
    /// so a partial write can never be mistaken for a completed chunk.
    func synthesize(
        chunk: NarrationChunk,
        voice: SynthesisVoice,
        settings: SynthesisSettings,
        apiKey: String?,
        to outputURL: URL
    ) async throws
}

public extension SpeechSynthesisEngine {
    /// Rough narration length for a character count, used for the pre-run
    /// estimate shown in the confirmation gate.
    ///
    /// Based on ~15 characters per second, which is about 150–160 words per
    /// minute — ordinary audiobook pace. It is deliberately coarse: the estimate
    /// exists so someone can tell four minutes from four hours before spending
    /// money, not to be accurate to the second.
    func estimatedDuration(characterCount: Int, settings: SynthesisSettings) -> TimeInterval {
        let rate = settings.rate > 0 ? Double(settings.rate) : 1
        return Double(characterCount) / (15 * rate)
    }
}
