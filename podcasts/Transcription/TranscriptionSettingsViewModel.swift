import Foundation
import PocketCastsTranscription

/// Backs `TranscriptionSettingsView`, bridging the UserDefaults-backed
/// transcription settings into observable UI state.
@MainActor
final class TranscriptionSettingsViewModel: ObservableObject {
    @Published var engineMode: TranscriptionEngineMode
    @Published var languageOverride: String

    init() {
        engineMode = TranscriptionEngineFactory.currentMode()
        languageOverride = Settings.transcriptionLanguageOverride() ?? ""
    }

    /// Phase 1 ships only the Apple built-in engine; other modes are shown but
    /// not selectable, so selecting them is ignored defensively here too.
    func select(mode: TranscriptionEngineMode) {
        guard mode == .appleBuiltIn else { return }
        engineMode = mode
        Settings.setTranscriptionEngineMode(mode.rawValue)
    }

    /// Persists the language override; whitespace-only input clears it back to
    /// the device locale.
    func commitLanguageOverride() {
        let trimmed = languageOverride.trimmingCharacters(in: .whitespacesAndNewlines)
        Settings.setTranscriptionLanguageOverride(trimmed.isEmpty ? nil : trimmed)
    }
}
