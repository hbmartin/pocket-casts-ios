import AppIntents
import Foundation
import PocketCastsDataModel
import PocketCastsReadAloud
import PocketCastsUtils

/// Narrates text handed over by a Shortcut.
///
/// Deliberately headless (`openAppWhenRun == false`): the useful shape is a
/// shortcut that takes an article, a note or a clipboard and leaves an episode
/// waiting, without bouncing the user into the app.
///
/// Not registered in `PocketCastsAppShortcuts` — that provider is at Apple's cap
/// of ten — so it carries no Siri phrase and is reached from the Shortcuts app.
struct CreateNarrationIntent: AppIntent {
    static let title: LocalizedStringResource = "Read Text Aloud"
    static let description = IntentDescription(
        "Turns text into an episode narrated by Pocket Casts."
    )
    static var openAppWhenRun: Bool { false }

    @Parameter(title: "Text")
    var text: String

    @Parameter(title: "Title")
    var title: String?

    /// Opt-in for engines that spend the user's provider quota. Off by default
    /// so an automation can never pay for audio nobody asked for.
    @Parameter(title: "Confirm Paid Narration", default: false)
    var confirmPaidNarration: Bool

    @MainActor
    func perform() async throws -> some IntentResult {
        guard FeatureFlag.readAloud.enabled else {
            throw ReadAloudIntentError.unavailable
        }

        let importer = NarrationImporter()
        let preview: NarrationImporter.Preview
        do {
            preview = try importer.preview(text: text, title: title)
        } catch {
            throw ReadAloudIntentError.unreadableText
        }

        // Honours whatever engine the user configured, so a Shortcut produces
        // the same audio as importing by hand.
        let engineKind = NarrationEngineKind(rawValue: Settings.readAloudEngineKind()) ?? .appleBuiltIn
        let providerId = engineKind == .remoteProvider ? ElevenLabsTTSEngine.providerId : nil
        let modelId = engineKind == .remoteProvider
            ? (Settings.readAloudProviderModelId() ?? ElevenLabsModel.default.id)
            : nil
        let apiKey = providerId.flatMap {
            ProviderKeyStore.apiKey(providerId: $0, purpose: .textToSpeech)
        }

        guard let engine = try? NarrationEngineFactory().makeEngine(
            for: engineKind, providerId: providerId, modelId: modelId
        ) else {
            throw ReadAloudIntentError.unavailable
        }
        if engine.capabilities.requiresAPIKey, apiKey?.isEmpty != false {
            throw ReadAloudIntentError.missingKey
        }

        // A paid engine spends the user's quota with nobody in the loop, so an
        // unattended shortcut must opt in explicitly — the same consent the
        // import sheet collects with its confirmation toggle. Free engines
        // never look at the parameter.
        //
        // Checked before the voice list, not after: listing voices is a request
        // to the provider, and a shortcut that hasn't opted in should not reach
        // them at all.
        if engine.capabilities.requiresConfirmation, !confirmPaidNarration {
            throw ReadAloudIntentError.paidNarrationNotConfirmed
        }

        let catalog = VoiceCatalog(voices: (try? await engine.availableVoices(apiKey: apiKey)) ?? [])
        guard let voice = catalog.preferredVoice(
            storedId: Settings.readAloudDefaultVoiceId(),
            for: preview.document.detectedLanguage
        ) else {
            throw ReadAloudIntentError.noVoiceAvailable
        }

        let narration: NarrationRecord
        do {
            narration = try importer.commit(
                preview: preview,
                title: self.title ?? preview.document.suggestedTitle,
                engine: engineKind,
                providerId: providerId,
                modelId: modelId,
                voice: voice
            ).narration
        } catch {
            throw ReadAloudIntentError.couldNotSave
        }

        Analytics.track(.readAloudIntentInvoked, properties: [
            "character_count": preview.document.characterCount,
        ])
        let outcome = await NarrationQueue.shared.enqueueAndWait(uuid: narration.uuid)
        switch outcome {
        case .completed, .suspended:
            // A suspended attempt has reached a durable chunk/manifest
            // checkpoint and remains resumable on the next foreground.
            break
        case .failed, .cancelled, .superseded, .missing:
            throw ReadAloudIntentError.couldNotSave
        }

        return .result()
    }
}

/// Failures a Shortcut can show. Deliberately coarse — a shortcut author can act
/// on "no voice installed", not on a chunking error.
enum ReadAloudIntentError: Error, CustomLocalizedStringResourceConvertible {
    case unavailable
    case missingKey
    case unreadableText
    case noVoiceAvailable
    case couldNotSave
    case paidNarrationNotConfirmed

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .unavailable:
            LocalizedStringResource("read_aloud_intent_error_unavailable",
                                    defaultValue: "Read Aloud isn't available.",
                                    table: "Localizable")
        case .missingKey:
            LocalizedStringResource("read_aloud_error_key_missing",
                                    defaultValue: "Add your provider API key in Pocket Casts settings first.",
                                    table: "Localizable")
        case .unreadableText:
            LocalizedStringResource("read_aloud_intent_error_unreadable_text",
                                    defaultValue: "That text couldn't be read.",
                                    table: "Localizable")
        case .noVoiceAvailable:
            LocalizedStringResource("read_aloud_intent_error_no_voice",
                                    defaultValue: "No narration voice is installed on this device.",
                                    table: "Localizable")
        case .couldNotSave:
            LocalizedStringResource("read_aloud_intent_error_could_not_save",
                                    defaultValue: "The document couldn't be saved.",
                                    table: "Localizable")
        case .paidNarrationNotConfirmed:
            LocalizedStringResource("read_aloud_intent_error_paid_not_confirmed",
                                    defaultValue: "This narration uses your provider quota. Turn on Confirm Paid Narration in the shortcut to allow it.",
                                    table: "Localizable")
        }
    }
}
