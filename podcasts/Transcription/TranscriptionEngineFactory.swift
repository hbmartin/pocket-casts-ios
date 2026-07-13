import Foundation
import PocketCastsTranscription

/// Provides the speech-to-text engine, speaker diarizer and remote provider for
/// a transcription job. The queue manager resolves through this seam so tests
/// can inject mocks.
nonisolated protocol TranscriptionEngineProviding: Sendable {
    func makeEngine(for mode: TranscriptionEngineMode) throws -> any SpeechToTextEngine
    func makeRemoteProvider(id: String) -> (any RemoteTranscriptionProvider)?
    func makeDiarizer() -> (any SpeakerDiarizing)?
}

extension TranscriptionEngineProviding {
    /// Default resolution through the module's provider registry; test factories
    /// override to inject a mock provider. Explicitly nonisolated: app-target
    /// extension members default to MainActor, which would poison the
    /// nonisolated conformance.
    nonisolated func makeRemoteProvider(id: String) -> (any RemoteTranscriptionProvider)? {
        RemoteProviderRegistry.makeProvider(id: id)
    }

    /// Default: no diarizer — the queue skips the diarizing stage and emits
    /// monologue (untagged) cues. The production factory overrides this with
    /// SpeakerKit; test factories keep the default or inject a mock.
    nonisolated func makeDiarizer() -> (any SpeakerDiarizing)? {
        nil
    }
}

/// The single engine/provider selection point across transcription phases.
///
/// Phase 1 shipped the Apple built-in engine, Phase 2 the WhisperKit local
/// models plus the SpeakerKit diarizer, Phase 3 the remote providers (which
/// bypass `makeEngine` — the queue's remote pipeline resolves adapters via
/// `makeRemoteProvider`).
nonisolated struct TranscriptionEngineFactory: TranscriptionEngineProviding {
    /// The user's currently selected engine mode. Unknown persisted raw values
    /// fall back to the Apple built-in engine.
    static func currentMode() -> TranscriptionEngineMode {
        TranscriptionEngineMode(rawValue: Settings.transcriptionEngineMode()) ?? .appleBuiltIn
    }

    func makeEngine(for mode: TranscriptionEngineMode) throws -> any SpeechToTextEngine {
        switch mode {
        case .appleBuiltIn:
            return AppleSpeechEngine()
        case .localModel:
            // Settings.transcriptionLocalStack selects the local stack. Only the
            // WhisperKit stack is implemented; the FluidAudio alternate (Parakeet
            // TDT + pyannote) is deferred as transcription Phase 2b, and its
            // stub value — like any unknown value — falls back to WhisperKit
            // rather than failing the job.
            return WhisperKitEngine()
        case .remoteProvider:
            // .remoteProvider jobs never reach makeEngine (the queue routes them
            // to the remote pipeline).
            throw TranscriptionError.engineFailure
        }
    }

    /// SpeakerKit attaches to BOTH local pipeline modes: Apple ASR + SpeakerKit
    /// is the "diarized built-in" mode, WhisperKit + SpeakerKit the local-model
    /// one. Remote providers diarize server-side and never hit this.
    func makeDiarizer() -> (any SpeakerDiarizing)? {
        SpeakerKitDiarizer()
    }
}
