import PocketCastsDataModel
import PocketCastsReadAloud
import SwiftUI

/// Settings for Read Aloud: the voice new documents start with, where to get
/// better ones, how much space documents use, and a way into the library.
struct ReadAloudSettingsView: View {
    @EnvironmentObject private var theme: Theme
    @StateObject private var model = ReadAloudSettingsViewModel()
    @StateObject private var previewPlayer = VoicePreviewPlayer()

    /// Pushes the library. Injected so the hosting controller owns navigation
    /// and the document picker it needs.
    let onLibraryTapped: () -> Void

    var body: some View {
        List {
            engineSection
            if model.engineKind == .remoteProvider {
                providerSection
            }
            defaultVoiceSection
            if model.engineKind == .appleBuiltIn {
                VoiceQualityExplainerSection()
            }
            storageSection
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(AppTheme.color(for: .primaryUi04, theme: theme).ignoresSafeArea())
        .task {
            Analytics.track(.readAloudSettingsShown)
            await model.load()
        }
        .onDisappear { previewPlayer.stop() }
    }

    private var engineSection: some View {
        Section {
            engineRow(.appleBuiltIn, title: L10n.readAloudEngineBuiltin)
            engineRow(.remoteProvider, title: L10n.readAloudEngineElevenlabs)
        } header: {
            Text(L10n.readAloudEngineSection)
                .font(style: .footnote, weight: .semibold)
                .foregroundColor(AppTheme.color(for: .primaryText02, theme: theme))
        } footer: {
            Text(L10n.readAloudEngineFooter)
                .font(style: .footnote)
                .foregroundColor(AppTheme.color(for: .primaryText02, theme: theme))
        }
        .listRowBackground(AppTheme.color(for: .primaryUi01, theme: theme))
    }

    private func engineRow(_ kind: NarrationEngineKind, title: String) -> some View {
        Button {
            Task { await model.selectEngine(kind) }
        } label: {
            HStack {
                Text(title)
                    .foregroundColor(AppTheme.color(for: .primaryText01, theme: theme))
                Spacer()
                if model.engineKind == kind {
                    Image(systemName: "checkmark")
                        .foregroundColor(AppTheme.color(for: .primaryIcon01, theme: theme))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .font(style: .body)
    }

    private var providerSection: some View {
        Section {
            SecureField(L10n.readAloudApiKey, text: $model.apiKeyInput)
                .font(style: .body)
                .foregroundColor(AppTheme.color(for: .primaryText01, theme: theme))
                .onSubmit { Task { await model.saveAndValidateKey() } }

            Button(L10n.readAloudValidateKey) {
                Task { await model.saveAndValidateKey() }
            }
            .font(style: .body)
            .foregroundColor(AppTheme.color(for: .primaryInteractive01, theme: theme))
            .disabled(model.apiKeyInput.isEmpty || model.isValidating)

            Picker(L10n.readAloudModelLabel, selection: Binding(
                get: { model.modelId },
                set: { model.selectModel($0) }
            )) {
                ForEach(ElevenLabsModel.allCases) { option in
                    Text(option.displayName).tag(option.id)
                }
            }
            .font(style: .body)
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                if let status = model.keyStatus {
                    Text(status.message)
                        .foregroundColor(AppTheme.color(for: status.isGood ? .primaryText02 : .support05, theme: theme))
                }
                Text(L10n.readAloudModelFooter)
                    .foregroundColor(AppTheme.color(for: .primaryText02, theme: theme))
            }
            .font(style: .footnote)
        }
        .listRowBackground(AppTheme.color(for: .primaryUi01, theme: theme))
    }

    private var defaultVoiceSection: some View {
        Section {
            NavigationLink {
                VoicePickerView(
                    catalog: model.catalog,
                    documentLanguage: Locale.current.identifier,
                    selection: Binding(
                        get: { model.defaultVoice },
                        set: { model.setDefaultVoice($0) }
                    ),
                    previewPlayer: previewPlayer
                )
                .environmentObject(theme)
            } label: {
                HStack {
                    Text(L10n.readAloudSettingsDefaults)
                        .foregroundColor(AppTheme.color(for: .primaryText01, theme: theme))
                    Spacer()
                    if let voice = model.defaultVoice {
                        VoiceLabel(voice: voice)
                    }
                }
                .font(style: .body)
            }
        } footer: {
            Text(L10n.readAloudSettingsDefaultsFooter)
                .font(style: .footnote)
                .foregroundColor(AppTheme.color(for: .primaryText02, theme: theme))
        }
        .listRowBackground(AppTheme.color(for: .primaryUi01, theme: theme))
    }

    private var storageSection: some View {
        Section {
            Button(action: onLibraryTapped) {
                HStack {
                    Text(L10n.readAloudSettingsLibrary)
                        .foregroundColor(AppTheme.color(for: .primaryText01, theme: theme))
                    Spacer()
                    Text("\(model.documentCount)")
                        .foregroundColor(AppTheme.color(for: .primaryText02, theme: theme))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            HStack {
                Text(L10n.readAloudSettingsStorage)
                    .foregroundColor(AppTheme.color(for: .primaryText01, theme: theme))
                Spacer()
                Text(model.storageDescription)
                    .foregroundColor(AppTheme.color(for: .primaryText02, theme: theme))
            }
        }
        .font(style: .body)
        .listRowBackground(AppTheme.color(for: .primaryUi01, theme: theme))
    }
}

@MainActor
final class ReadAloudSettingsViewModel: ObservableObject {
    struct KeyStatus {
        let message: String
        let isGood: Bool
    }

    @Published private(set) var catalog = VoiceCatalog(voices: [])
    @Published private(set) var defaultVoice: SynthesisVoice?
    @Published private(set) var documentCount = 0
    @Published private(set) var storageDescription = ""
    @Published private(set) var engineKind: NarrationEngineKind = .appleBuiltIn
    @Published var apiKeyInput = ""
    @Published private(set) var modelId = ElevenLabsModel.default.id
    @Published private(set) var keyStatus: KeyStatus?
    @Published private(set) var isValidating = false

    private let storage: ReadAloudStorage

    init(storage: ReadAloudStorage = .default) {
        self.storage = storage
    }

    private var providerId: String? {
        engineKind == .remoteProvider ? ElevenLabsTTSEngine.providerId : nil
    }

    /// The engine whose voices the picker should show — the same one a narration
    /// started now would use.
    private func currentEngine() -> any SpeechSynthesisEngine {
        (try? NarrationEngineFactory().makeEngine(for: engineKind, providerId: providerId, modelId: modelId))
            ?? AppleSpeechSynthesisEngine()
    }

    func selectEngine(_ kind: NarrationEngineKind) async {
        guard kind != engineKind else { return }
        engineKind = kind
        Settings.setReadAloudEngineKind(kind.rawValue)
        Analytics.track(.readAloudEngineChanged, properties: ["engine": kind == .remoteProvider ? "elevenlabs" : "builtin"])
        // The voice list is engine-specific, and a stored default from the other
        // engine will not resolve — reload so the row shows something real.
        await load()
    }

    func selectModel(_ id: String) {
        modelId = id
        Settings.setReadAloudProviderModelId(id)
    }

    /// Validates a normalized replacement before committing it to Keychain, so
    /// a typo never destroys the last working text-to-speech credential.
    func saveAndValidateKey() async {
        guard let providerId else { return }
        guard let normalizedKey = ProviderKeyStore.normalizedAPIKey(apiKeyInput) else {
            keyStatus = KeyStatus(message: L10n.readAloudKeyInvalid, isGood: false)
            return
        }
        guard let model = ElevenLabsModel.resolve(id: modelId) else {
            keyStatus = KeyStatus(message: L10n.readAloudErrorGeneric, isGood: false)
            return
        }

        isValidating = true
        defer { isValidating = false }

        let result = await ElevenLabsTTSEngine(model: model).validate(apiKey: normalizedKey)
        switch result {
        case .success:
            guard ProviderKeyStore.setAPIKey(
                normalizedKey,
                providerId: providerId,
                purpose: .textToSpeech
            ) else {
                keyStatus = KeyStatus(message: L10n.readAloudKeySaveFailed, isGood: false)
                Analytics.track(.readAloudKeyValidated, properties: ["result": "save_failed"])
                return
            }
            apiKeyInput = normalizedKey
            keyStatus = KeyStatus(message: L10n.readAloudKeyValid, isGood: true)
            Analytics.track(.readAloudKeyValidated, properties: ["result": "valid"])
            await load()
        case .failure(.insufficientKeyPermissions):
            // Distinct from an invalid key on purpose: this key is real, it just
            // isn't allowed to do text to speech, and telling someone to
            // regenerate it would send them after the wrong thing.
            keyStatus = KeyStatus(message: L10n.readAloudKeyNoPermission, isGood: false)
            Analytics.track(.readAloudKeyValidated, properties: ["result": "no_permission"])
        case .failure(let error):
            keyStatus = KeyStatus(message: error.userMessage, isGood: false)
            Analytics.track(.readAloudKeyValidated, properties: ["result": "invalid"])
        }
    }

    func load() async {
        engineKind = NarrationEngineKind(rawValue: Settings.readAloudEngineKind()) ?? .appleBuiltIn
        let persistedModelId = Settings.readAloudProviderModelId()
        let resolvedModel = ElevenLabsModel.resolve(id: persistedModelId) ?? .default
        modelId = resolvedModel.id
        if persistedModelId != nil, persistedModelId != modelId {
            Settings.setReadAloudProviderModelId(modelId)
        }
        if let providerId {
            apiKeyInput = ProviderKeyStore.apiKey(
                providerId: providerId,
                purpose: .textToSpeech
            ) ?? ""
        }

        let key = providerId.flatMap {
            ProviderKeyStore.apiKey(providerId: $0, purpose: .textToSpeech)
        }
        do {
            catalog = VoiceCatalog(voices: try await currentEngine().availableVoices(apiKey: key))
        } catch let error as ReadAloudError {
            catalog = VoiceCatalog(voices: [])
            keyStatus = KeyStatus(message: error.userMessage, isGood: false)
        } catch {
            catalog = VoiceCatalog(voices: [])
            keyStatus = KeyStatus(message: L10n.readAloudErrorGeneric, isGood: false)
        }
        // Falls back to the best installed voice for this device rather than
        // showing nothing: an unset default still has an effective value, and
        // hiding it would make the row look broken.
        defaultVoice = catalog.voice(id: Settings.readAloudDefaultVoiceId())
            ?? catalog.preferredVoice(for: Locale.current.identifier)

        let documents = DataManager.sharedManager.readAloud.allDocuments()
        documentCount = documents.count
        let bytes = documents.reduce(into: Int64(0)) { total, document in
            let url = storage.sourceURL(relativePath: document.sourcePath)
            if let size = try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64 {
                total += size
            }
        }
        storageDescription = ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    func setDefaultVoice(_ voice: SynthesisVoice?) {
        defaultVoice = voice
        Settings.setReadAloudDefaultVoiceId(voice?.id)
    }
}
