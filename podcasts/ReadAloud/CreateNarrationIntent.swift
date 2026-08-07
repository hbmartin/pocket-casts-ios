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

        let engine = AppleSpeechSynthesisEngine()
        let catalog = VoiceCatalog(voices: (try? await engine.availableVoices(apiKey: nil)) ?? [])
        guard let voice = catalog.voice(id: Settings.readAloudDefaultVoiceId())
            ?? catalog.preferredVoice(for: preview.document.detectedLanguage) else {
            throw ReadAloudIntentError.noVoiceAvailable
        }

        // No confirmation, by decision: the intent behaves exactly like the
        // import sheet's Narrate button so automations stay predictable.
        //
        // The consequence to keep in view when a paid provider ships: a shortcut
        // running unattended would then spend the user's quota with nothing in
        // the loop. `EngineCapabilities.requiresConfirmation` exists to gate
        // that, and this is where it would be honoured.
        let narration: NarrationRecord
        do {
            narration = try importer.commit(
                preview: preview,
                title: self.title ?? preview.document.suggestedTitle,
                engine: .appleBuiltIn,
                providerId: nil,
                voice: voice
            ).narration
        } catch {
            throw ReadAloudIntentError.couldNotSave
        }

        Analytics.track(.readAloudIntentInvoked, properties: [
            "character_count": preview.document.characterCount,
        ])
        await NarrationQueue.shared.enqueue(uuid: narration.uuid)

        return .result()
    }
}

/// Failures a Shortcut can show. Deliberately coarse — a shortcut author can act
/// on "no voice installed", not on a chunking error.
enum ReadAloudIntentError: Error, CustomLocalizedStringResourceConvertible {
    case unavailable
    case unreadableText
    case noVoiceAvailable
    case couldNotSave

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .unavailable: "Read Aloud isn't available."
        case .unreadableText: "That text couldn't be read."
        case .noVoiceAvailable: "No narration voice is installed on this device."
        case .couldNotSave: "The document couldn't be saved."
        }
    }
}
