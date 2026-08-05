import AVFoundation
import Foundation
import PocketCastsReadAloud
import SwiftUI

/// Speaks a short sample so a voice can be chosen by ear rather than by name.
///
/// Built-in voices preview by speaking live rather than by rendering a file:
/// it is instant, costs nothing, and is exactly what the voice will sound like.
/// Providers whose voices carry a `previewURL` play that instead; a voice with
/// neither is not previewable and the UI hides the control.
@MainActor
final class VoicePreviewPlayer: NSObject, ObservableObject {
    /// The voice currently speaking, so the list can show which row is playing.
    @Published private(set) var playingVoiceId: String?

    private let synthesizer = AVSpeechSynthesizer()
    private var player: AVPlayer?

    override init() {
        super.init()
        synthesizer.delegate = self
        // Mixes over whatever is playing rather than interrupting it: sampling a
        // voice is a glance, not a listening session.
        synthesizer.usesApplicationAudioSession = false
    }

    func isPlaying(_ voice: SynthesisVoice) -> Bool {
        playingVoiceId == voice.id
    }

    static func canPreview(_ voice: SynthesisVoice) -> Bool {
        voice.previewURL != nil || AVSpeechSynthesisVoice(identifier: voice.id) != nil
    }

    func preview(_ voice: SynthesisVoice, sampleText: String) {
        guard playingVoiceId != voice.id else {
            stop()
            return
        }
        stop()

        if let previewURL = voice.previewURL {
            playingVoiceId = voice.id
            let player = AVPlayer(url: previewURL)
            self.player = player
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(previewItemFinished),
                name: .AVPlayerItemDidPlayToEndTime,
                object: player.currentItem
            )
            player.play()
            return
        }

        guard let systemVoice = AVSpeechSynthesisVoice(identifier: voice.id) else { return }
        let utterance = AVSpeechUtterance(string: sampleText)
        utterance.voice = systemVoice
        playingVoiceId = voice.id
        synthesizer.speak(utterance)
    }

    func stop() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        player?.pause()
        if let item = player?.currentItem {
            NotificationCenter.default.removeObserver(self, name: .AVPlayerItemDidPlayToEndTime, object: item)
        }
        player = nil
        playingVoiceId = nil
    }

    @objc private func previewItemFinished() {
        stop()
    }
}

extension VoicePreviewPlayer: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.playingVoiceId = nil }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.playingVoiceId = nil }
    }
}
