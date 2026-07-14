import PocketCastsDataModel
import XCTest

@testable import podcasts

/// The analyzer-gating condition behind adaptive effects (P2-2a regression):
/// the system sound classifier must run for VAD-discriminated trim silence OR
/// whenever adaptive effects are on — including with trim silence off
/// (Voice-Boost-only playback must still detect music segments).
final class AudioReadTaskGatingTests: XCTestCase {
    func testVADTrimWantsAnalyzer() {
        XCTAssertTrue(AudioReadTask.wantsAnalyzer(trimSilence: .low, discriminator: .vad, adaptiveEnabled: false))
    }

    func testAdaptiveAloneWantsAnalyzerEvenWithTrimOff() {
        XCTAssertTrue(AudioReadTask.wantsAnalyzer(trimSilence: .off, discriminator: .rms, adaptiveEnabled: true))
        XCTAssertTrue(AudioReadTask.wantsAnalyzer(trimSilence: .off, discriminator: .vad, adaptiveEnabled: true))
        XCTAssertTrue(AudioReadTask.wantsAnalyzer(trimSilence: .off, discriminator: .heuristic, adaptiveEnabled: true))
    }

    func testNothingWantedWhenTrimOffAndAdaptiveOff() {
        for discriminator in TrimDiscriminator.allCases {
            XCTAssertFalse(AudioReadTask.wantsAnalyzer(trimSilence: .off, discriminator: discriminator, adaptiveEnabled: false))
        }
    }

    func testNonVADTrimWithoutAdaptiveDoesNotWantAnalyzer() {
        XCTAssertFalse(AudioReadTask.wantsAnalyzer(trimSilence: .low, discriminator: .rms, adaptiveEnabled: false))
        XCTAssertFalse(AudioReadTask.wantsAnalyzer(trimSilence: .high, discriminator: .heuristic, adaptiveEnabled: false))
    }
}
