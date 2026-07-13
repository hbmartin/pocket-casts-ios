import Foundation
import PocketCastsTranscription

/// One-time, per-provider consent before episode audio (or its URL) is sent to a
/// remote transcription service.
///
/// Consent is only required for the remote engine mode; the on-device modes
/// enqueue straight away. Once granted, the flag persists in UserDefaults
/// (`transcription.consent.<providerId>`) — each provider is consented
/// separately because the data shared differs (URL-based providers receive the
/// episode's public audio link; upload-based providers receive the audio file).
@MainActor
enum TranscriptionConsentGate {
    nonisolated static func consentDefaultsKey(providerId: String) -> String {
        "transcription.consent.\(providerId)"
    }

    /// nonisolated: also consulted off-main by the acquisition coordinator and
    /// the transcription queue (UserDefaults is thread-safe).
    nonisolated static func hasConsent(providerId: String) -> Bool {
        UserDefaults.standard.bool(forKey: consentDefaultsKey(providerId: providerId))
    }

    static func recordConsent(providerId: String) {
        UserDefaults.standard.set(true, forKey: consentDefaultsKey(providerId: providerId))
    }

    /// True when enqueueing right now would hand audio to a remote provider the
    /// user hasn't consented to yet.
    static func needsConsent() -> Bool {
        guard TranscriptionEngineFactory.currentMode() == .remoteProvider else { return false }
        return !hasConsent(providerId: Settings.transcriptionRemoteProvider())
    }

    /// Runs `enqueue` immediately when no consent is needed; otherwise shows the
    /// consent prompt and runs it only on approval. Call from UI enqueue sites.
    static func requestConsentIfNeeded(then enqueue: @escaping () -> Void) {
        guard needsConsent() else {
            enqueue()
            return
        }

        let providerId = Settings.transcriptionRemoteProvider()
        let info = RemoteProviderRegistry.info(id: providerId)
        let providerName = info?.displayName ?? providerId
        // URL-based providers fetch the episode's public link themselves;
        // upload-based providers receive the audio file. The copy must say
        // which one the user is agreeing to.
        let message = info?.supportsPublicURL == true
            ? L10n.transcriptionConsentMessageUrl(providerName)
            : L10n.transcriptionConsentMessageUpload(providerName)

        let allowAction = OptionAction(label: L10n.transcriptionConsentAllow, icon: nil) {
            recordConsent(providerId: providerId)
            enqueue()
        }
        let cancelAction = OptionAction(label: L10n.cancel, icon: nil) {
            // Declined: nothing enqueued, nothing stored — asked again next time.
        }
        cancelAction.outline = true

        let picker = OptionsPicker(title: nil)
        picker.addDescriptiveActions(title: L10n.transcriptionConsentTitle,
                                     message: message,
                                     icon: "option-alert",
                                     actions: [allowAction, cancelAction])
        picker.show(statusBarStyle: .default)
    }
}
