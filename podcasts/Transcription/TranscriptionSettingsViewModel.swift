import Foundation
import PocketCastsDataModel
import PocketCastsTranscription
import PocketCastsUtils

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

    /// Progress of the selected local model's download, driving the button row.
    enum ModelDownloadState: Equatable {
        case idle
        case downloading(Double)
    }

    @Published var engineMode: TranscriptionEngineMode
    @Published var languageOverride: String
    @Published var selectedProviderId: String
    /// The selected provider's API key as shown in the SecureField. Persisted to
    /// the keychain on every change; never logged or sent anywhere except the
    /// provider itself.
    @Published var apiKeyInput: String
    @Published var keyValidation: KeyValidationState = .idle

    // MARK: Local model state

    @Published var selectedModelVariant: String
    @Published var downloadedModelIds: Set<String> = []
    @Published var modelDownload: ModelDownloadState = .idle
    /// Non-nil shows the download error alert (cellular gate or network failure).
    @Published var modelDownloadError: String?
    @Published var modelsDiskUsage: Int64 = 0
    @Published var allowCellularModelDownloads: Bool
    /// 0 = auto-detect; otherwise a cap on distinct transcript speakers.
    @Published var maxSpeakers: Int
    /// When LOCAL transcription may run on battery. Remote jobs are unaffected.
    @Published var batteryPolicy: TranscriptionBatteryPolicy

    // MARK: Generated transcript storage state

    @Published var transcriptsDiskUsage: Int64 = 0
    @Published var transcriptCount: Int = 0
    @Published var showClearAllConfirmation = false

    /// The stepper's upper bound; podcasts beyond ~10 voices are out of scope
    /// for on-device diarization.
    static let maxSpeakersCap = 10

    let providers = RemoteProviderRegistry.providers
    let modelVariants = WhisperKitModelStore.curatedVariants

    private let modelStore: WhisperKitModelStore
    private let artifactStore: TranscriptionArtifactStore
    private var validationTask: Task<Void, Never>?
    private var downloadTask: Task<Void, Never>?

    init(modelStore: WhisperKitModelStore = WhisperKitModelStore(),
         artifactStore: TranscriptionArtifactStore = TranscriptionArtifactStore()) {
        self.modelStore = modelStore
        self.artifactStore = artifactStore
        engineMode = TranscriptionEngineFactory.currentMode()
        languageOverride = Settings.transcriptionLanguageOverride() ?? ""
        let providerId = Settings.transcriptionRemoteProvider()
        selectedProviderId = providerId
        apiKeyInput = ProviderKeyStore.apiKey(providerId: providerId) ?? ""
        selectedModelVariant = Settings.transcriptionWhisperModel()
        allowCellularModelDownloads = Settings.transcriptionAllowCellularModelDownloads()
        maxSpeakers = Settings.transcriptionMaxSpeakers()
        batteryPolicy = Settings.transcriptionBatteryPolicy()
        refreshStorage()
    }

    var selectedProvider: RemoteProviderInfo? {
        RemoteProviderRegistry.info(id: selectedProviderId)
    }

    var selectedVariantInfo: WhisperKitModelStore.Variant? {
        modelVariants.first { $0.id == selectedModelVariant }
    }

    var isSelectedModelDownloaded: Bool {
        downloadedModelIds.contains(selectedModelVariant)
    }

    func select(mode: TranscriptionEngineMode) {
        engineMode = mode
        Settings.setTranscriptionEngineMode(mode.rawValue)
        if mode == .localModel {
            refreshStorage()
        }
    }

    func select(batteryPolicy policy: TranscriptionBatteryPolicy) {
        batteryPolicy = policy
        Settings.setTranscriptionBatteryPolicy(policy)
        // A relaxed policy may make a deferred queue runnable right away.
        Task { await TranscriptionQueueManager.shared.powerConditionsChanged() }
    }

    func select(providerId: String) {
        guard providerId != selectedProviderId else { return }
        selectedProviderId = providerId
        Settings.setTranscriptionRemoteProvider(providerId)
        apiKeyInput = ProviderKeyStore.apiKey(providerId: providerId) ?? ""
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
        ProviderKeyStore.setAPIKey(apiKeyInput, providerId: selectedProviderId)
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

    // MARK: - Local model management

    func select(modelVariant: String) {
        guard modelVariant != selectedModelVariant, modelDownload == .idle else { return }
        selectedModelVariant = modelVariant
        Settings.setTranscriptionWhisperModel(modelVariant)
    }

    func setAllowCellularModelDownloads(_ allowed: Bool) {
        allowCellularModelDownloads = allowed
        Settings.setTranscriptionAllowCellularModelDownloads(allowed)
    }

    func setMaxSpeakers(_ count: Int) {
        let clamped = min(max(count, 0), Self.maxSpeakersCap)
        maxSpeakers = clamped
        Settings.setTranscriptionMaxSpeakers(clamped)
    }

    func downloadSelectedModel() {
        guard modelDownload == .idle else { return }

        // Pre-check the cellular gate so the user gets the specific explanation
        // rather than the generic failure (the store enforces the same gate).
        if !NetworkUtils.shared.isConnectedToUnexpensiveConnection(), !allowCellularModelDownloads {
            modelDownloadError = L10n.transcriptionModelCellularBlocked
            return
        }

        let variant = selectedModelVariant
        let store = modelStore
        modelDownload = .downloading(0)
        downloadTask = Task { [weak self] in
            // Strong self for the duration of the download: capturing the outer
            // weak `var` binding in the @Sendable progress closure is a Swift 6
            // error, and the settings page owning the download should stay alive.
            guard let self else { return }
            do {
                try await store.download(variant: variant) { fraction in
                    Task { @MainActor [weak self] in
                        guard let self, case .downloading = self.modelDownload else { return }
                        self.modelDownload = .downloading(fraction)
                    }
                }
                modelDownload = .idle
                Analytics.track(.transcriptionModelDownloaded, properties: ["model": variant])
                refreshStorage()
            } catch {
                guard !Task.isCancelled else { return }
                modelDownload = .idle
                modelDownloadError = L10n.transcriptionModelDownloadFailed
                refreshStorage()
            }
        }
    }

    func deleteSelectedModel() {
        let variant = selectedModelVariant
        do {
            try modelStore.delete(variant: variant)
            Analytics.track(.transcriptionModelDeleted, properties: ["model": variant])
        } catch {
            FileLog.shared.addMessage("[Transcription] failed to delete model \(variant): \(error.localizedDescription)")
        }
        refreshStorage()
    }

    // MARK: - Generated transcript storage

    func clearAllTranscriptions() {
        Task { [weak self] in
            await TranscriptionQueueManager.shared.deleteAllTranscriptions()
            // Spotlight items still carry the deleted transcripts' text.
            await SpotlightIndexCoordinator.shared.rebuildAll()
            self?.refreshStorage()
        }
    }

    // MARK: - Spotlight

    @Published private(set) var isRebuildingSpotlight = false

    /// The "Rebuild Spotlight Index" settings action: recomputes every episode
    /// and highlight item from scratch.
    func rebuildSpotlightIndex() {
        guard !isRebuildingSpotlight else { return }
        isRebuildingSpotlight = true
        Task { [weak self] in
            await SpotlightIndexCoordinator.shared.rebuildAll()
            self?.isRebuildingSpotlight = false
        }
    }

    /// Re-reads the on-disk facts (downloaded models, disk usage, transcript
    /// count) off the main thread and publishes them back.
    func refreshStorage() {
        let modelStore = modelStore
        let artifactStore = artifactStore
        Task.detached(priority: .userInitiated) { [weak self] in
            let downloaded = Set(modelStore.downloadedVariants().map(\.id))
            let modelsUsage = modelStore.diskUsage()
            let transcriptsUsage = artifactStore.totalDiskUsage()
            let transcriptCount = DataManager.sharedManager.transcriptions.allRecords().count
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.downloadedModelIds = downloaded
                self.modelsDiskUsage = modelsUsage
                self.transcriptsDiskUsage = transcriptsUsage
                self.transcriptCount = transcriptCount
            }
        }
    }
}
