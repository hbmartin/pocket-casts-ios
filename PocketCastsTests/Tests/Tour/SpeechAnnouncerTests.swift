import AVFoundation
import XCTest

@testable import podcasts

/// The announcer must settle exactly once per speak — finish, cancel,
/// supersession, or watchdog — and report a missing voice as `.unavailable`.
@MainActor
final class SpeechAnnouncerTests: XCTestCase {
    private final class FakeSynthesizer: SpeechSynthesizing {
        var announcerDelegate: AVSpeechSynthesizerDelegate?
        private(set) var spoken: [AVSpeechUtterance] = []
        private(set) var stopCount = 0

        func speak(_ utterance: AVSpeechUtterance) {
            spoken.append(utterance)
        }

        func stopSpeaking() {
            stopCount += 1
            // Mirror AVSpeechSynthesizer: stopping an active utterance delivers didCancel.
            if let utterance = spoken.last {
                announcerDelegate?.speechSynthesizer?(AVSpeechSynthesizer(), didCancel: utterance)
            }
        }

        func finishCurrent() {
            guard let utterance = spoken.last else { return }
            announcerDelegate?.speechSynthesizer?(AVSpeechSynthesizer(), didFinish: utterance)
        }
    }

    private func makeAnnouncer(_ synthesizer: FakeSynthesizer, hasVoice: Bool = true) -> SpeechAnnouncer {
        SpeechAnnouncer(
            makeSynthesizer: { synthesizer },
            voiceForLanguage: { hasVoice ? AVSpeechSynthesisVoice(language: $0) : nil }
        )
    }

    /// Yields until the concurrent `speak` child task has installed its utterance.
    private func waitForUtterance(in synthesizer: FakeSynthesizer) async {
        for _ in 0..<1000 where synthesizer.spoken.isEmpty {
            await Task.yield()
        }
        XCTAssertFalse(synthesizer.spoken.isEmpty, "speak() never reached the synthesizer")
    }

    func testFinishSettlesFinished() async {
        let synthesizer = FakeSynthesizer()
        let announcer = makeAnnouncer(synthesizer)

        async let outcome = announcer.speak("Saved")
        await waitForUtterance(in: synthesizer)
        synthesizer.finishCurrent()

        let result = await outcome
        XCTAssertEqual(synthesizer.spoken.count, 1)
        XCTAssertEqual(synthesizer.spoken.first?.speechString, "Saved")
        if case .finished = result {} else { XCTFail("expected .finished, got \(result)") }
    }

    func testStopSettlesInterrupted() async {
        let synthesizer = FakeSynthesizer()
        let announcer = makeAnnouncer(synthesizer)

        async let outcome = announcer.speak("Saved")
        await waitForUtterance(in: synthesizer)
        announcer.stop()

        let result = await outcome
        if case .interrupted = result {} else { XCTFail("expected .interrupted, got \(result)") }
    }

    func testStopWithNothingInFlightIsSafe() {
        let announcer = makeAnnouncer(FakeSynthesizer())
        announcer.stop()
        announcer.stop()
    }

    func testMissingVoiceReturnsUnavailableWithoutSpeaking() async {
        let synthesizer = FakeSynthesizer()
        let announcer = makeAnnouncer(synthesizer, hasVoice: false)

        let result = await announcer.speak("Saved")

        XCTAssertTrue(synthesizer.spoken.isEmpty)
        if case .unavailable = result {} else { XCTFail("expected .unavailable, got \(result)") }
    }

    func testDuplicateDelegateEventsSettleOnlyOnce() async {
        let synthesizer = FakeSynthesizer()
        let announcer = makeAnnouncer(synthesizer)

        async let outcome = announcer.speak("Saved")
        await waitForUtterance(in: synthesizer)
        synthesizer.finishCurrent()
        _ = await outcome

        // A late duplicate event must be ignored (continuation already consumed).
        synthesizer.finishCurrent()
    }
}
