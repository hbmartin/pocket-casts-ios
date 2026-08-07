#if os(iOS)
import AVFoundation
import Foundation
import Synchronization

/// `NarrationEngineKind.appleBuiltIn`: offline synthesis with the system voices,
/// rendered to a file via `AVSpeechSynthesizer.write(_:toBufferCallback:)`.
///
/// Free, private and faster than real time, which is why it is the default and
/// why the whole pipeline can afford to be eager (synthesize the entire document
/// at import rather than streaming it during playback).
///
/// Wrapped in `#if os(iOS)` so the module still builds for host-side `swift test`
/// runs, which exercise the pure extraction and chunking code.
public struct AppleSpeechSynthesisEngine: SpeechSynthesisEngine {
    public let id = "apple.avspeech"

    public var capabilities: EngineCapabilities {
        EngineCapabilities(
            // No API limit exists offline; chunking is purely about resume
            // granularity, so this is a "how much work do we want to redo after
            // a kill" number, not a hard cap.
            maxCharactersPerChunk: 2500,
            // CPU-bound: parallel utterances would fight for the same cores and
            // burn battery for no wall-clock gain.
            maxConcurrentChunks: 1,
            requiresAPIKey: false,
            requiresConfirmation: false,
            supportsFreePreview: true
        )
    }

    public init() {}

    // MARK: - Voices

    /// Legacy macOS-era novelty voices, which `speechVoices()` still returns.
    ///
    /// These are the joke voices — Bells, Boing, Bubbles, Zarvox, Bad News — and
    /// they are sound effects, not narrators: "Bells" sings each word to a
    /// chime. They share one identifier namespace, which is the only reliable
    /// way to spot them (they carry no distinguishing trait and report
    /// `.default` quality like any compact voice).
    ///
    /// Left in, they sort alphabetically among the real voices and dominate the
    /// English list — a picker where most entries are gags reads as broken.
    private static let noveltyVoicePrefix = "com.apple.speech.synthesis.voice."

    /// Installed system voices worth narrating a document with.
    ///
    /// Personal Voice is excluded deliberately: it is a recording of the user's
    /// own voice, gated behind a per-use authorization prompt, and rendering
    /// documents into someone's synthesized likeness is not a thing this feature
    /// should do without a conversation the app hasn't had. Novelty voices are
    /// excluded for the reason above.
    public func availableVoices(apiKey: String?) async throws -> [SynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { !$0.voiceTraits.contains(.isPersonalVoice) }
            .filter { !$0.identifier.hasPrefix(Self.noveltyVoicePrefix) }
            .map { voice in
                SynthesisVoice(
                    id: voice.identifier,
                    name: voice.name,
                    language: voice.language,
                    quality: Self.quality(for: voice.quality)
                )
            }
            .sorted { ($0.language, $0.name) < ($1.language, $1.name) }
    }

    private static func quality(for quality: AVSpeechSynthesisVoiceQuality) -> VoiceQuality {
        switch quality {
        case .enhanced: .enhanced
        case .premium: .premium
        default: .standard
        }
    }

    // MARK: - Synthesis

    public func synthesize(
        chunk: NarrationChunk,
        voice: SynthesisVoice,
        settings: SynthesisSettings,
        apiKey: String?,
        to outputURL: URL
    ) async throws {
        try Task.checkCancellation()

        guard let systemVoice = AVSpeechSynthesisVoice(identifier: voice.id) else {
            throw ReadAloudError.voiceUnavailable
        }

        let utterance = AVSpeechUtterance(string: chunk.text)
        utterance.voice = systemVoice
        utterance.rate = Self.utteranceRate(for: settings.rate)

        // A leftover file from a failed attempt must never be mistaken for a
        // completed chunk by the resume path.
        try? FileManager.default.removeItem(at: outputURL)

        // nonisolated(unsafe): the cancellation handler may run on another
        // thread, but `stopSpeaking` is the one call it makes and
        // AVSpeechSynthesizer tolerates it from off-thread.
        nonisolated(unsafe) let synthesizer = AVSpeechSynthesizer()
        let session = WriteSession(outputURL: outputURL)

        let watchdog = Task {
            try? await Task.sleep(for: Self.watchdogTimeout(forCharacters: chunk.text.count))
            session.settle(with: .failure(ReadAloudError.engineFailure))
        }
        defer { watchdog.cancel() }

        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                session.attach(continuation)
                synthesizer.write(utterance) { buffer in
                    session.consume(buffer)
                }
            }
        } onCancel: {
            // Without this a cancelled task would hang suspended until the
            // watchdog fires: the synthesizer has no reason to end the stream.
            synthesizer.stopSpeaking(at: .immediate)
            session.settle(with: .failure(CancellationError()))
        }
        // `synthesizer` is only referenced from inside the closure above, which
        // ARC cannot see as keeping it alive across the suspension.
        withExtendedLifetime(synthesizer) {}

        try session.finalize()
    }

    /// `AVSpeechUtterance.rate` runs 0…1 with `Default` (0.5) as normal pace, so
    /// the caller's multiplier scales that midpoint rather than the range.
    static func utteranceRate(for multiplier: Float) -> Float {
        let scaled = AVSpeechUtteranceDefaultSpeechRate * (multiplier > 0 ? multiplier : 1)
        return min(max(scaled, AVSpeechUtteranceMinimumSpeechRate), AVSpeechUtteranceMaximumSpeechRate)
    }

    /// Offline rendering runs far faster than real time, so this is an
    /// order-of-magnitude backstop against a wedged synthesizer, not a real
    /// expectation: roughly ten seconds plus a second per 100 characters.
    static func watchdogTimeout(forCharacters count: Int) -> Duration {
        .seconds(10 + Double(count) / 100)
    }
}

// MARK: - Write session

/// Bridges `write(_:toBufferCallback:)` — an unbounded stream of callbacks on an
/// arbitrary queue — into a single `async` call.
///
/// All mutable state lives behind one `Mutex` because the buffer callback, the
/// watchdog and the caller's task can all touch it concurrently. The whole point
/// of `settle` is that exactly one of them wins.
private final class WriteSession: Sendable {
    private struct State {
        var file: AVAudioFile?
        var wroteFrames = false
        var continuation: CheckedContinuation<Void, any Error>?
        var outcome: Result<Void, any Error>?
        var settled = false
    }

    private let outputURL: URL
    private let state = Mutex(State())

    init(outputURL: URL) {
        self.outputURL = outputURL
    }

    func attach(_ continuation: CheckedContinuation<Void, any Error>) {
        // The watchdog can only have fired this early in pathological cases, but
        // if it did, resume immediately rather than waiting forever.
        let alreadySettled: Result<Void, any Error>? = state.withLock { state in
            guard state.outcome == nil else { return state.outcome }
            state.continuation = continuation
            return nil
        }
        if let alreadySettled {
            continuation.resume(with: alreadySettled)
        }
    }

    /// Appends one buffer. A zero-length buffer marks end of stream — but only
    /// once some audio has actually been written: some voices deliver an empty
    /// buffer first, and treating that as the end would silently truncate the
    /// chunk to nothing.
    func consume(_ buffer: AVAudioBuffer) {
        guard let pcm = buffer as? AVAudioPCMBuffer else { return }

        if pcm.frameLength == 0 {
            let finished = state.withLock { $0.wroteFrames }
            if finished { settle(with: .success(())) }
            return
        }

        do {
            try state.withLock { state in
                // Checked under the same lock that owns the file: a buffer
                // arriving after the watchdog or a cancellation settled the
                // session must not create or write the file again.
                guard !state.settled else { return }
                if state.file == nil {
                    // The output format is whatever the voice rendered; the
                    // assembler re-encodes later, so nothing here needs to match
                    // across chunks.
                    state.file = try AVAudioFile(forWriting: outputURL, settings: pcm.format.settings)
                }
                try state.file?.write(from: pcm)
                state.wroteFrames = true
            }
        } catch {
            settle(with: .failure(ReadAloudError.engineFailure))
        }
    }

    /// Delivers the first outcome and ignores every later one.
    func settle(with outcome: Result<Void, any Error>) {
        let continuation: CheckedContinuation<Void, any Error>? = state.withLock { state in
            guard !state.settled else { return nil }
            state.settled = true
            state.outcome = outcome
            // Release the write handle here: on the failure paths the caller
            // never reaches `finalize`, and this is the only other closer.
            state.file = nil
            defer { state.continuation = nil }
            return state.continuation
        }
        continuation?.resume(with: outcome)
    }

    /// Closes the file and rejects a chunk that produced no audio, so a 0-byte
    /// artifact can never be mistaken for a rendered chunk on resume.
    func finalize() throws {
        let wroteFrames = state.withLock { state in
            state.file = nil
            return state.wroteFrames
        }
        guard wroteFrames else {
            try? FileManager.default.removeItem(at: outputURL)
            throw ReadAloudError.synthesisProducedNoAudio
        }
    }
}
#endif
