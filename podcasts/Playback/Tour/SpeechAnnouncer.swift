import AVFoundation
import Foundation
import PocketCastsUtils

/// The minimal synthesizer surface `SpeechAnnouncer` needs, so tests can drive
/// delegate events without real speech.
@MainActor
protocol SpeechSynthesizing: AnyObject {
    var announcerDelegate: AVSpeechSynthesizerDelegate? { get set }
    func speak(_ utterance: AVSpeechUtterance)
    func stopSpeaking()
}

extension AVSpeechSynthesizer: SpeechSynthesizing {
    var announcerDelegate: AVSpeechSynthesizerDelegate? {
        get { delegate }
        set { delegate = newValue }
    }

    func stopSpeaking() {
        stopSpeaking(at: .immediate)
    }
}

/// Speaks short interjections (capture confirmations, Highlights Tour bridges)
/// over the app's already-active audio session.
///
/// Deliberately session-agnostic: `AVSpeechSynthesizer.usesApplicationAudioSession`
/// defaults to true, so speech renders into the active
/// `.playback/.spokenAudio/.longFormAudio` session — the same mechanism that
/// lets the bookmark tone mix over podcast audio. Callers that need silence
/// underneath (the tour) pause playback first; callers that want speech over
/// audio (capture confirmation) just speak.
///
/// Bridges are content, not chrome: they are never routed through
/// `UIAccessibility.post`, which would double-speak under VoiceOver.
@MainActor
final class SpeechAnnouncer: NSObject {
    enum Outcome: Sendable {
        /// The utterance played to its end.
        case finished
        /// `stop()` was called, another speak superseded it, or the system
        /// interrupted the utterance.
        case interrupted
        /// No voice exists for the requested language (callers fall back to a tone).
        case unavailable
    }

    private let makeSynthesizer: () -> SpeechSynthesizing
    private var synthesizer: SpeechSynthesizing?
    private var continuation: CheckedContinuation<Outcome, Never>?
    private var watchdog: Task<Void, Never>?

    /// Voice lookup is injectable so tests can simulate a missing language.
    private let voiceForLanguage: (String) -> AVSpeechSynthesisVoice?

    init(makeSynthesizer: @escaping () -> SpeechSynthesizing = { AVSpeechSynthesizer() },
         voiceForLanguage: @escaping (String) -> AVSpeechSynthesisVoice? = { AVSpeechSynthesisVoice(language: $0) }) {
        self.makeSynthesizer = makeSynthesizer
        self.voiceForLanguage = voiceForLanguage
    }

    /// Speaks `text`, settling exactly once when the utterance finishes, is
    /// cancelled/superseded, or no voice exists. A watchdog settles
    /// `.interrupted` if the synthesizer wedges, so callers can never hang.
    func speak(_ text: String, languageCode: String? = nil) async -> Outcome {
        // A new speak supersedes any in-flight one.
        stop()

        let language = languageCode ?? AVSpeechSynthesisVoice.currentLanguageCode()
        guard let voice = voiceForLanguage(language) ?? voiceForLanguage(AVSpeechSynthesisVoice.currentLanguageCode()) else {
            return .unavailable
        }

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        utterance.preUtteranceDelay = 0.1

        let synthesizer = makeSynthesizer()
        synthesizer.announcerDelegate = self
        self.synthesizer = synthesizer

        return await withCheckedContinuation { continuation in
            self.continuation = continuation

            // Generous ceiling: ~10 chars/sec at default rate, plus slack.
            let ceiling = Duration.seconds(Double(text.count) * 0.1 + 10)
            watchdog = Task { [weak self] in
                try? await Task.sleep(for: ceiling)
                guard !Task.isCancelled else { return }
                FileLog.shared.addMessage("SpeechAnnouncer: watchdog settled a wedged utterance")
                self?.settle(.interrupted)
            }

            synthesizer.speak(utterance)
        }
    }

    /// Settles any in-flight `speak` with `.interrupted`. Safe to call anytime.
    func stop() {
        synthesizer?.stopSpeaking()
        settle(.interrupted)
    }

    private func settle(_ outcome: Outcome) {
        watchdog?.cancel()
        watchdog = nil
        continuation?.resume(returning: outcome)
        continuation = nil
        synthesizer?.announcerDelegate = nil
        synthesizer = nil
    }
}

extension SpeechAnnouncer: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.settle(.finished) }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.settle(.interrupted) }
    }
}
