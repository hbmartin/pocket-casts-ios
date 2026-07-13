import Foundation
import PocketCastsTranscription

/// Backs `TranscriptionSettingsView`, bridging the UserDefaults-backed
/// transcription settings (and the keychain-backed provider API keys) into
/// observable UI state.
@MainActor
final class TranscriptionSettingsViewModel: ObservableObject {
    /// Outcome of the "Validate Key" probe, driving the result label.
    enum KeyValidationState: Equatable {
        case idle
        case validating
        case valid
        case invalid
        /// The check itself failed (network trouble) — says nothing about the key.
        case checkFailed
    }

    @Published var engineMode: TranscriptionEngineMode
    @Published var languageOverride: String
    @Published var selectedProviderId: String
    /// The selected provider's API key as shown in the SecureField. Persisted to
    /// the keychain on every change; never logged or sent anywhere except the
    /// provider itself.
    @Published var apiKeyInput: String
    @Published var keyValidation: KeyValidationState = .idle

    let providers = RemoteProviderRegistry.providers

    private var validationTask: Task<Void, Never>?

    init() {
        engineMode = TranscriptionEngineFactory.currentMode()
        languageOverride = Settings.transcriptionLanguageOverride() ?? ""
        let providerId = Settings.transcriptionRemoteProvider()
        selectedProviderId = providerId
        apiKeyInput = TranscriptionKeyStore.apiKey(providerId: providerId) ?? ""
    }

    var selectedProvider: RemoteProviderInfo? {
        RemoteProviderRegistry.info(id: selectedProviderId)
    }

    /// The local-model (WhisperKit) mode ships with transcription Phase 2; it is
    /// shown but not selectable, so selecting it is ignored defensively here too.
    func select(mode: TranscriptionEngineMode) {
        guard mode != .localModel else { return }
        engineMode = mode
        Settings.setTranscriptionEngineMode(mode.rawValue)
    }

    func select(providerId: String) {
        guard providerId != selectedProviderId else { return }
        selectedProviderId = providerId
        Settings.setTranscriptionRemoteProvider(providerId)
        apiKeyInput = TranscriptionKeyStore.apiKey(providerId: providerId) ?? ""
        keyValidation = .idle
        validationTask?.cancel()
    }

    /// Persists the language override; whitespace-only input clears it back to
    /// the device locale.
    func commitLanguageOverride() {
        let trimmed = languageOverride.trimmingCharacters(in: .whitespacesAndNewlines)
        Settings.setTranscriptionLanguageOverride(trimmed.isEmpty ? nil : trimmed)
    }

    /// Persists the entered key to the keychain (empty input deletes the item).
    func commitAPIKey() {
        TranscriptionKeyStore.setAPIKey(apiKeyInput, providerId: selectedProviderId)
        keyValidation = .idle
    }

    /// Probes the provider's cheapest authenticated endpoint with the entered
    /// key: 2xx → valid, 400/401/403 → invalid, anything else → check failed.
    func validateKey() {
        let providerId = selectedProviderId
        let apiKey = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty else {
            keyValidation = .invalid
            return
        }

        keyValidation = .validating
        validationTask?.cancel()
        validationTask = Task { [weak self] in
            let result = await RemoteProviderRegistry.validateKey(providerId: providerId, apiKey: apiKey)
            guard let self, !Task.isCancelled, self.selectedProviderId == providerId else { return }

            let resultName: String
            switch result {
            case .valid:
                keyValidation = .valid
                resultName = "valid"
            case .invalid:
                keyValidation = .invalid
                resultName = "invalid"
            case .indeterminate:
                keyValidation = .checkFailed
                resultName = "check_failed"
            }
            // Provider id and outcome only — key material must never be tracked.
            Analytics.track(.transcriptionKeyValidated, properties: ["provider": providerId, "result": resultName])
        }
    }
}
