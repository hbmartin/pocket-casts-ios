import Foundation
import PocketCastsDataModel
import PocketCastsReadAloud
import SwiftUI

/// Drives the sheet shown after a text file is picked: title, size, voice, and
/// the button that starts narrating.
@MainActor
final class ReadAloudImportViewModel: ObservableObject {
    enum Source {
        case file(URL, NarrationSourceKind)
        /// Text typed or pasted on the compose screen, already extracted there
        /// so this sheet has nothing to re-read.
        case composed(NarrationImporter.Preview)
        /// An existing document being narrated again in another voice.
        case existingDocument(ReadAloudDocumentRecord)
    }

    @Published var title = ""
    @Published private(set) var characterCount = 0
    @Published private(set) var detectedLanguage: String?
    @Published private(set) var catalog = VoiceCatalog(voices: [])
    @Published var selectedVoice: SynthesisVoice?
    @Published private(set) var loadError: ReadAloudError?
    @Published private(set) var isCommitting = false

    /// True when the document's own language had no installed voice, so the
    /// selection fell back to the device language.
    @Published private(set) var fellBackToDeviceLanguage = false

    /// True once the user has seen and accepted the cost of a paid run.
    @Published var hasConfirmedCost = false

    let source: Source
    private let importer: NarrationImporter
    private let engine: any SpeechSynthesisEngine
    private let engineKind: NarrationEngineKind
    private let providerId: String?
    private let modelId: String?
    private var preview: NarrationImporter.Preview?

    init(
        source: Source,
        importer: NarrationImporter = NarrationImporter(),
        engine: (any SpeechSynthesisEngine)? = nil
    ) {
        self.source = source
        self.importer = importer

        // Resolved once here rather than read per-access: whatever the user has
        // configured now is what this narration is committed to, and settings
        // changing mid-sheet must not repartition the text under it.
        let kind = NarrationEngineKind(rawValue: Settings.readAloudEngineKind()) ?? .appleBuiltIn
        let providerId = kind == .remoteProvider ? ElevenLabsTTSEngine.providerId : nil
        let modelId = kind == .remoteProvider
            ? (Settings.readAloudProviderModelId() ?? ElevenLabsModel.default.id)
            : nil
        self.engineKind = kind
        self.providerId = providerId
        self.modelId = modelId
        self.engine = engine
            ?? (try? NarrationEngineFactory().makeEngine(for: kind, providerId: providerId, modelId: modelId))
            ?? AppleSpeechSynthesisEngine()
    }

    /// Whether this run will spend the user's provider quota.
    var requiresCostConfirmation: Bool {
        engine.capabilities.requiresConfirmation
    }

    var isReady: Bool {
        selectedVoice != nil && loadError == nil && characterCount > 0 && !isCommitting
            && (!requiresCostConfirmation || hasConfirmedCost)
    }

    var estimatedDuration: TimeInterval {
        engine.estimatedDuration(characterCount: characterCount, settings: SynthesisSettings())
    }

    /// Language name for the mismatch footnote, e.g. "French".
    var detectedLanguageName: String? {
        detectedLanguage.map { VoiceCatalog.displayName(forLanguage: $0) }
    }

    // MARK: - Loading

    func load() async {
        let voices = (try? await engine.availableVoices(
            apiKey: providerId.flatMap { ProviderKeyStore.apiKey(providerId: $0) }
        )) ?? []
        catalog = VoiceCatalog(voices: voices)

        switch source {
        case .file(let url, let kind):
            do {
                let preview = try importer.preview(fileURL: url, sourceKind: kind)
                self.preview = preview
                title = preview.document.suggestedTitle
                characterCount = preview.document.characterCount
                detectedLanguage = preview.document.detectedLanguage
            } catch {
                loadError = error as? ReadAloudError ?? .sourceUnreadable
            }
        case .composed(let preview):
            self.preview = preview
            title = preview.document.suggestedTitle
            characterCount = preview.document.characterCount
            detectedLanguage = preview.document.detectedLanguage
        case .existingDocument(let document):
            title = document.title
            characterCount = Int(document.characterCount)
            detectedLanguage = document.language
        }

        selectDefaultVoice()
    }

    /// Preselect the user's default voice when it is still installed and speaks
    /// the right language, otherwise the best voice for the document.
    private func selectDefaultVoice() {
        let documentVoices = catalog.voices(matching: detectedLanguage)
        if let stored = catalog.voice(id: Settings.readAloudDefaultVoiceId()),
           detectedLanguage == nil || documentVoices.contains(stored) {
            selectedVoice = stored
        } else {
            selectedVoice = catalog.preferredVoice(for: detectedLanguage)
        }
        // Only a document whose language we actually detected can mismatch;
        // "we couldn't tell" is not a mismatch worth explaining.
        fellBackToDeviceLanguage = detectedLanguage != nil && documentVoices.isEmpty && selectedVoice != nil
    }

    // MARK: - Commit

    /// Creates the rows and queues the render. Returns false when nothing was
    /// enqueued, so the caller can keep the sheet up.
    func narrate() async -> Bool {
        guard let voice = selectedVoice, !isCommitting else { return false }
        isCommitting = true
        defer { isCommitting = false }

        do {
            let narrationUuid: String
            switch source {
            case .file, .composed:
                guard let preview else { throw ReadAloudError.sourceUnreadable }
                let created = try importer.commit(
                    preview: preview,
                    title: title,
                    engine: engineKind,
                    providerId: providerId,
                    modelId: modelId,
                    voice: voice
                )
                narrationUuid = created.narration.uuid
                Analytics.track(.readAloudNarrationQueued, properties: [
                    "source": created.document.source.analyticsValue,
                    "character_count": characterCount,
                    "voice_quality": voice.quality.analyticsValue,
                ])
            case .existingDocument(let document):
                if title != document.title {
                    _ = DataManager.sharedManager.readAloud.renameDocument(uuid: document.uuid, title: title)
                }
                let narration = try importer.narrateAgain(
                    document: document,
                    engine: engineKind,
                    providerId: providerId,
                    modelId: modelId,
                    voice: voice
                )
                narrationUuid = narration.uuid
                Analytics.track(.readAloudNarratedAgain, properties: [
                    "character_count": characterCount,
                    "voice_quality": voice.quality.analyticsValue,
                ])
            }

            Settings.setReadAloudDefaultVoiceId(voice.id)
            await NarrationQueue.shared.enqueue(uuid: narrationUuid)
            return true
        } catch {
            loadError = error as? ReadAloudError ?? .engineFailure
            return false
        }
    }
}

extension NarrationSourceKind {
    var analyticsValue: String {
        switch self {
        case .picked: "picked"
        case .composed: "composed"
        case .shared: "shared"
        case .intent: "intent"
        }
    }
}

extension VoiceQuality {
    var analyticsValue: String {
        switch self {
        case .standard: "standard"
        case .enhanced: "enhanced"
        case .premium: "premium"
        }
    }

    /// Badge text, or nil for compact voices which get no badge.
    var badge: String? {
        switch self {
        case .standard: nil
        case .enhanced: L10n.readAloudVoiceEnhanced
        case .premium: L10n.readAloudVoicePremium
        }
    }
}

extension ReadAloudError {
    /// User-facing message. Deliberately small: most failures here are one of
    /// three things a person can actually act on, and everything else is "try
    /// again".
    var userMessage: String {
        switch self {
        case .undecodableText, .unsupportedFileType, .sourceUnreadable:
            L10n.readAloudErrorUnreadable
        case .documentTooLarge:
            L10n.readAloudErrorTooLarge
        case .emptyDocument:
            L10n.readAloudErrorEmpty
        default:
            L10n.readAloudErrorGeneric
        }
    }
}
