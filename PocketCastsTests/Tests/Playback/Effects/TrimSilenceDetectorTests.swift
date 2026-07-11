import XCTest
@testable import podcasts
import PocketCastsDataModel

final class TrimSilenceDetectorTests: XCTestCase {
    private let sampleRate = 44100.0
    private let framesPerBuffer = 1152

    private func makeDetector(_ parameters: TrimSilenceParameters, sampleRate: Double = 44100) -> TrimSilenceDetector {
        let detector = TrimSilenceDetector()
        detector.configure(parameters: parameters, sampleRate: sampleRate, framesPerBuffer: framesPerBuffer)
        return detector
    }

    private func feed(_ detector: TrimSilenceDetector, levelsDB: [Float], timeLeft: TimeInterval = 1000) -> [TrimSilenceDetector.Decision] {
        var stashed = 0
        return levelsDB.map { level in
            let decision = detector.analyze(TrimFeatureFrame(rmsDB: level), stashedCount: stashed, timeLeft: timeLeft)
            switch decision {
            case .stash: stashed += 1
            case .endGapEmitAll, .endGapTrim: stashed = 0
            case .passthrough: break
            }
            return decision
        }
    }

    // MARK: - Legacy equivalence

    func testPresetBufferCountsMatchLegacyConstants() {
        for (amount, expectedGap, expectedKeep) in [(TrimSilenceAmount.low, 20, 14), (.medium, 16, 12), (.high, 4, 0)] {
            let detector = makeDetector(.preset(for: amount))
            XCTAssertEqual(detector.minGapBuffers, expectedGap, "\(amount) minimum gap")
            XCTAssertEqual(detector.keepBuffers, expectedKeep, "\(amount) re-inserted buffers")
        }
    }

    func testLegacyGapDetectionSequence() {
        // medium preset: gaps of >= 16 buffers get trimmed keeping 12
        let detector = makeDetector(.preset(for: .medium))
        let loud: Float = -20
        let quiet: Float = -60

        let decisions = feed(detector, levelsDB: [Float](repeating: loud, count: 5) + [Float](repeating: quiet, count: 20) + [loud])

        XCTAssertEqual(Array(decisions[0 ..< 5]), Array(repeating: .passthrough, count: 5))
        XCTAssertEqual(Array(decisions[5 ..< 25]), Array(repeating: .stash, count: 20))
        XCTAssertEqual(decisions[25], .endGapTrim(keepBuffers: 12))
    }

    func testShortGapIsNotTrimmed() {
        let detector = makeDetector(.preset(for: .medium))
        let decisions = feed(detector, levelsDB: [-20] + [Float](repeating: -60, count: 10) + [-20])
        XCTAssertEqual(decisions.last, .endGapEmitAll, "10 quiet buffers < the 16-buffer minimum gap")
    }

    func testEndGuardForcesGateOpen() {
        let detector = makeDetector(.preset(for: .medium))
        var stashed = 0
        // silence with only 3 seconds left: gate must not close
        let decision = detector.analyze(TrimFeatureFrame(rmsDB: -80), stashedCount: stashed, timeLeft: 3)
        XCTAssertEqual(decision, .passthrough)

        // and an in-progress gap must close when the guard engages
        _ = detector.analyze(TrimFeatureFrame(rmsDB: -80), stashedCount: stashed, timeLeft: 100)
        stashed = 1
        let closing = detector.analyze(TrimFeatureFrame(rmsDB: -80), stashedCount: stashed, timeLeft: 3)
        XCTAssertEqual(closing, .endGapEmitAll)
    }

    func testStashCapForcesGapEnd() {
        var parameters = TrimSilenceParameters.preset(for: .high)
        parameters.maxGapHoldSeconds = 1 // ≈ 38 buffers at 44.1 kHz
        let detector = makeDetector(parameters)

        let decisions = feed(detector, levelsDB: [Float](repeating: -80, count: 60))
        guard let firstEnd = decisions.firstIndex(where: { $0 != .stash && $0 != .passthrough }) else {
            XCTFail("cap never triggered")
            return
        }
        XCTAssertEqual(decisions[firstEnd], .endGapTrim(keepBuffers: 0))
        XCTAssertLessThan(firstEnd, 45, "cap should trigger after roughly one second of stash")
    }

    // MARK: - Hysteresis and hold

    func testHysteresisKeepsGateClosedInDeadband() {
        var parameters = TrimSilenceParameters.preset(for: .medium)
        parameters.enterThresholdDB = -50
        parameters.hysteresisDB = 6 // exit at -44
        let detector = makeDetector(parameters)

        _ = feed(detector, levelsDB: [-20, -55]) // open, then closed
        // level in the deadband between enter (-50) and exit (-44): stays closed
        XCTAssertEqual(detector.analyze(TrimFeatureFrame(rmsDB: -47), stashedCount: 1, timeLeft: 1000), .stash)
        // crossing the exit threshold reopens
        XCTAssertNotEqual(detector.analyze(TrimFeatureFrame(rmsDB: -43), stashedCount: 2, timeLeft: 1000), .stash)
    }

    func testHoldTimePreventsImmediateReclose() {
        var parameters = TrimSilenceParameters.preset(for: .medium)
        parameters.holdTimeMs = 100 // ≈ 4 buffers
        let detector = makeDetector(parameters)

        _ = feed(detector, levelsDB: [-20, -60, -20]) // gap opens then closes → hold armed
        // silence right after the gate reopened: held open for ~4 buffers
        XCTAssertEqual(detector.analyze(TrimFeatureFrame(rmsDB: -60), stashedCount: 0, timeLeft: 1000), .passthrough)
        XCTAssertEqual(detector.analyze(TrimFeatureFrame(rmsDB: -60), stashedCount: 0, timeLeft: 1000), .passthrough)
    }

    // MARK: - Adaptive noise floor

    func testAdaptiveFloorTracksQuietRecording() {
        var parameters = TrimSilenceParameters.preset(for: .medium)
        parameters.useAdaptiveFloor = true
        parameters.adaptiveOffsetDB = 12
        parameters.adaptiveWindowSeconds = 10
        let detector = makeDetector(parameters)

        // before warmup the fixed threshold applies
        XCTAssertEqual(detector.effectiveEnterThresholdDB, Float(parameters.enterThresholdDB))

        // feed ~10 s of a -60 dB noise floor with occasional -30 dB speech
        for index in 0 ..< 400 {
            let level: Float = index % 10 == 0 ? -30 : -60
            _ = detector.analyze(TrimFeatureFrame(rmsDB: level), stashedCount: 0, timeLeft: 1000)
        }

        guard let floor = detector.currentFloorDB else { XCTFail("floor should be warmed up")
return }
        XCTAssertEqual(floor, -60, accuracy: 2)
        XCTAssertEqual(detector.effectiveEnterThresholdDB, floor + 12, accuracy: 0.01)
    }

    // MARK: - Time-based conversion

    func testMillisecondConversionAcrossSampleRates() {
        let parameters = TrimSilenceParameters.preset(for: .medium) // 418 ms gap / 313 ms keep
        for (rate, expectedGap) in [(22050.0, 8), (44100.0, 16), (48000.0, 17)] {
            let detector = makeDetector(parameters, sampleRate: rate)
            XCTAssertEqual(detector.minGapBuffers, expectedGap, "at \(rate) Hz")
        }
    }

    // MARK: - Discriminators

    func testHeuristicProtectsTonalContent() {
        var parameters = TrimSilenceParameters.preset(for: .medium)
        parameters.discriminator = .heuristic
        let detector = makeDetector(parameters)

        // quiet but tonal (low flatness): a reverb/music tail — keep the gate open
        var tonal = TrimFeatureFrame(rmsDB: -60)
        tonal.spectralFlatness = 0.05
        XCTAssertEqual(detector.analyze(tonal, stashedCount: 0, timeLeft: 1000), .passthrough)

        // quiet and noise-like: a real gap
        var noisy = TrimFeatureFrame(rmsDB: -60)
        noisy.spectralFlatness = 0.9
        XCTAssertEqual(detector.analyze(noisy, stashedCount: 0, timeLeft: 1000), .stash)
    }

    func testHeuristicProtectsQuietFricatives() {
        var parameters = TrimSilenceParameters.preset(for: .medium)
        parameters.discriminator = .heuristic
        parameters.enterThresholdDB = -46
        let detector = makeDetector(parameters)

        // just below the gate but with a very high zero-crossing rate: fricative
        var fricative = TrimFeatureFrame(rmsDB: -48)
        fricative.spectralFlatness = 0.9
        fricative.zeroCrossingRate = 0.4
        XCTAssertEqual(detector.analyze(fricative, stashedCount: 0, timeLeft: 1000), .passthrough)

        // same level, low ZCR: silence
        var silence = TrimFeatureFrame(rmsDB: -48)
        silence.spectralFlatness = 0.9
        silence.zeroCrossingRate = 0.02
        XCTAssertEqual(detector.analyze(silence, stashedCount: 0, timeLeft: 1000), .stash)
    }

    func testVADConfidenceForcesGateOpen() {
        var parameters = TrimSilenceParameters.preset(for: .medium)
        parameters.discriminator = .vad
        let detector = makeDetector(parameters)

        var speech = TrimFeatureFrame(rmsDB: -60)
        speech.spectralFlatness = 0.9
        speech.vadSpeechConfidence = 0.8
        XCTAssertEqual(detector.analyze(speech, stashedCount: 0, timeLeft: 1000), .passthrough)

        var silence = TrimFeatureFrame(rmsDB: -60)
        silence.spectralFlatness = 0.9
        silence.vadSpeechConfidence = 0.1
        XCTAssertEqual(detector.analyze(silence, stashedCount: 0, timeLeft: 1000), .stash)
    }

    // MARK: - Reconfiguration

    func testReconfigurePreservesGateState() {
        let detector = makeDetector(.preset(for: .medium))
        _ = feed(detector, levelsDB: [-20, -60, -60]) // in a gap with 2 stashed

        detector.configure(parameters: .preset(for: .high), sampleRate: sampleRate, framesPerBuffer: framesPerBuffer)

        // still in the gap: the stashed buffers must eventually flush through a
        // gap-end decision rather than being orphaned
        let closing = detector.analyze(TrimFeatureFrame(rmsDB: -20), stashedCount: 2, timeLeft: 1000)
        XCTAssertTrue(closing == .endGapEmitAll || closing == .endGapTrim(keepBuffers: 0))
    }
}
