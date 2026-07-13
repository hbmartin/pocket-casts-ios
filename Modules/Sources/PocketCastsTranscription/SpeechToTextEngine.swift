import Foundation

/// Stage 1 of the pipeline: audio file in, timed text out. Implementations:
/// `AppleSpeechEngine` (this module), WhisperKit/Parakeet wrappers (app layer —
/// their SPM products must not be linked into this module).
///
/// Progress closures report 0.0…1.0 and may be called from any thread/task;
/// callers own any main-thread hop and throttling.
public protocol SpeechToTextEngine: Sendable {
    /// Stable identifier persisted with the transcription record (e.g. "apple.speechanalyzer").
    var id: String { get }

    /// Downloads/installs whatever assets the engine needs for `locale`
    /// (nil = device locale). Safe to call repeatedly; a no-op when already prepared.
    func prepare(locale: Locale?, progress: @escaping @Sendable (Double) -> Void) async throws

    /// Transcribes a local audio file. `language` is a BCP-47 identifier override
    /// (nil = device locale). Implementations call `Task.checkCancellation()`
    /// between result batches so queue cancellation lands promptly.
    func transcribe(audioFile: URL, language: String?, progress: @escaping @Sendable (Double) -> Void) async throws -> [ASRSegment]
}

/// Stage 2 of the pipeline: audio file in, speaker turns out. Apple ships no
/// diarizer, so mode 0 runs with empty turns (untagged cues) until a local
/// diarizer (SpeakerKit/pyannote, app layer) is attached in Phase 2.
public protocol SpeakerDiarizing: Sendable {
    /// Downloads/installs diarizer models. Safe to call repeatedly.
    func prepare(progress: @escaping @Sendable (Double) -> Void) async throws

    /// Detects "who spoke when". `maxSpeakers` nil/0 means auto-detect.
    func diarize(audioFile: URL, maxSpeakers: Int?, progress: @escaping @Sendable (Double) -> Void) async throws -> [SpeakerTurn]
}

/// Mode 2: a hosted transcription API driven by a user-supplied key. Providers
/// return diarized output natively, skipping the align stage.
public protocol RemoteTranscriptionProvider: Sendable {
    /// Stable identifier used for keychain storage and job-handle round-trips.
    var id: String { get }
    /// User-facing provider name (e.g. "AssemblyAI").
    var displayName: String { get }
    /// True when the provider can fetch a public episode URL itself, which also
    /// makes it usable for episodes that aren't downloaded locally.
    var supportsPublicURL: Bool { get }

    /// Starts a transcription. Asynchronous providers return `.job(handle)` for
    /// later polling; synchronous ones return `.completed` directly.
    func submit(source: RemoteAudioSource, language: String?, apiKey: String) async throws -> SubmitOutcome

    /// Checks an in-flight job. Implementations perform a single request; the
    /// queue manager owns the polling schedule and backoff.
    func poll(handle: RemoteJobHandle, apiKey: String) async throws -> RemoteJobStatus
}
