import AVFoundation
import Foundation
@testable import PocketCastsReadAloud
import XCTest

/// Coverage for which system voices Read Aloud is willing to narrate with.
final class AppleSpeechSynthesisEngineTests: XCTestCase {
    /// `speechVoices()` still returns the legacy macOS novelty voices — Bells,
    /// Boing, Bubbles, Zarvox — which are sound effects rather than narrators.
    /// They report `.default` quality and carry no distinguishing trait, so
    /// nothing but the identifier namespace separates them from real compact
    /// voices, and left in they dominate the English list.
    ///
    /// Asserts an absence, so it holds even on a runner with no voices at all.
    func testNoveltyVoicesAreNotOffered() async throws {
        let voices = try await AppleSpeechSynthesisEngine().availableVoices(apiKey: nil)

        let novelty = voices.filter { $0.id.hasPrefix("com.apple.speech.synthesis.voice.") }
        XCTAssertTrue(novelty.isEmpty, "novelty voices offered as narrators: \(novelty.map(\.name))")
    }

    func testPersonalVoiceIsNotOffered() async throws {
        let voices = try await AppleSpeechSynthesisEngine().availableVoices(apiKey: nil)
        let personalIdentifiers = Set(
            AVSpeechSynthesisVoice.speechVoices()
                .filter { $0.voiceTraits.contains(.isPersonalVoice) }
                .map(\.identifier)
        )

        XCTAssertTrue(voices.allSatisfy { !personalIdentifiers.contains($0.id) })
    }

    /// The filter must not be so aggressive that it empties the list on a device
    /// that genuinely has voices — the inverse failure of the bug above.
    func testRealVoicesSurviveTheFilter() async throws {
        let installed = AVSpeechSynthesisVoice.speechVoices().filter {
            !$0.voiceTraits.contains(.isPersonalVoice)
                && !$0.identifier.hasPrefix("com.apple.speech.synthesis.voice.")
        }
        try XCTSkipIf(installed.isEmpty, "no non-novelty system voices installed on this runner")

        let voices = try await AppleSpeechSynthesisEngine().availableVoices(apiKey: nil)

        XCTAssertEqual(voices.count, installed.count)
    }
}
