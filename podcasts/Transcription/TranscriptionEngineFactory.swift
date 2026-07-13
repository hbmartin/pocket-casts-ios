import Foundation
import PocketCastsTranscription

/// Provides the speech-to-text engine for a transcription job. The queue manager
/// resolves engines through this seam so tests can inject a mock engine.
nonisolated protocol TranscriptionEngineProviding: Sendable {
    func makeEngine(for mode: TranscriptionEngineMode) throws -> any SpeechToTextEngine
}

/// The single engine/provider selection point across transcription phases.
///
/// Phase 1 ships only the Apple built-in engine. The local-model (WhisperKit)
/// and remote-provider modes are documented placeholders that throw until their
/// phases land; the settings UI keeps those modes unselectable, so hitting the
/// throw means a stale persisted setting rather than a user action.
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
        case .localModel, .remoteProvider:
            // Phase 2 (WhisperKit/Parakeet) and Phase 3 (remote providers) attach here.
            throw TranscriptionError.engineFailure
        }
    }
}
