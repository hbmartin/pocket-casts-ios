import Foundation
import PocketCastsDataModel
import PocketCastsReadAloud

/// Resolves the synthesis engine and API key for a narration. The queue goes
/// through this seam so tests can inject a fake engine instead of speaking.
nonisolated protocol NarrationEngineProviding: Sendable {
    func makeEngine(for kind: NarrationEngineKind, providerId: String?, modelId: String?) throws -> any SpeechSynthesisEngine
    /// The user's key for a provider-backed engine, or nil when the engine
    /// needs none.
    func apiKey(providerId: String?) -> String?
}

/// The single engine-selection point across Read Aloud phases.
nonisolated struct NarrationEngineFactory: NarrationEngineProviding {
    func makeEngine(for kind: NarrationEngineKind, providerId: String?, modelId: String?) throws -> any SpeechSynthesisEngine {
        switch kind {
        case .appleBuiltIn:
            return AppleSpeechSynthesisEngine()
        case .localModel:
            // Reserved, not implemented: local TTS stays blocked behind the
            // espeak-ng (GPL-3.0) phonemization review. A row can only carry
            // this value if a future build wrote it, so fail rather than
            // silently narrating in a voice the user didn't pick.
            throw ReadAloudError.engineFailure
        case .remoteProvider:
            switch providerId {
            case ElevenLabsTTSEngine.providerId:
                // The model comes off the narration, never from settings: it
                // determines the chunk size, and a resumed run must partition
                // the text exactly as the original did.
                return ElevenLabsTTSEngine(model: .resolve(id: modelId))
            default:
                throw ReadAloudError.engineFailure
            }
        }
    }

    func apiKey(providerId: String?) -> String? {
        guard let providerId else { return nil }
        return ProviderKeyStore.apiKey(providerId: providerId)
    }
}
