import Foundation
import PocketCastsTranscription

/// Provides the speech-to-text engine (or remote provider) for a transcription
/// job. The queue manager resolves through this seam so tests can inject mocks.
nonisolated protocol TranscriptionEngineProviding: Sendable {
    func makeEngine(for mode: TranscriptionEngineMode) throws -> any SpeechToTextEngine
    func makeRemoteProvider(id: String) -> (any RemoteTranscriptionProvider)?
}

extension TranscriptionEngineProviding {
    /// Default resolution through the module's provider registry; test factories
    /// override to inject a mock provider. Explicitly nonisolated: app-target
    /// extension members default to MainActor, which would poison the
    /// nonisolated conformance.
    nonisolated func makeRemoteProvider(id: String) -> (any RemoteTranscriptionProvider)? {
        RemoteProviderRegistry.makeProvider(id: id)
    }
}

/// The single engine/provider selection point across transcription phases.
///
/// Phase 1 ships the Apple built-in engine, Phase 3 the remote providers (which
/// bypass `makeEngine` — the queue's remote pipeline resolves adapters via
/// `makeRemoteProvider`). The local-model (WhisperKit) mode is a documented
/// placeholder that throws until Phase 2 lands; the settings UI keeps that mode
/// unselectable, so hitting the throw means a stale persisted setting rather
/// than a user action.
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
            // Phase 2 (WhisperKit/Parakeet) attaches here; .remoteProvider jobs
            // never reach makeEngine (the queue routes them to the remote pipeline).
            throw TranscriptionError.engineFailure
        }
    }
}
