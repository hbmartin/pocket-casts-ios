import XCTest
@testable import podcasts
import PocketCastsUtils

/// Exercises the VoiceBoostN C DSP through the test bridging header. The
/// symbols live in the host app binary; declarations come from
/// PocketCastsTests-Bridging-Header.h.
final class VoiceBoostNTests: XCTestCase {
    private let sampleRate = 44100.0
    private let framesPerBuffer = 1152

    // MARK: - Helpers

    /// A config with the normalization gain pinned at 0 dB and everything else
    /// off, so individual stages can be tested in isolation.
    private func isolationConfig() -> VBNConfig {
        var config = VBN_GetDefaultConfig()
        config.gainSmoothingTauSeconds = 100_000 // gain effectively frozen
        config.hpEnabled = false
        config.compEnabled = false
        config.limiterCeilingDB = -0.1
        return config
    }

    /// Feeds `seconds` of a sine through VBN_Process in playback-sized chunks,
    /// regenerating the buffer each chunk (VBN_Process mutates in place).
    /// Returns every output sample of channel 0 concatenated.
    @discardableResult
    private func processSine(_ state: OpaquePointer, frequency: Double, amplitude: Double, seconds: Double, channels: Int = 1, phase: Double = 0) -> [Float] {
        var output = [Float]()
        let totalFrames = Int(seconds * sampleRate)
        var frame = 0
        while frame < totalFrames {
            let count = min(framesPerBuffer, totalFrames - frame)
            let chunk = (0 ..< count).map { i in
                Float(amplitude * sin(2 * .pi * frequency * Double(frame + i) / sampleRate + phase))
            }

            // copy each channel into raw memory so we can build the
            // float-pointer array VBN_Process expects
            var pointers = [UnsafeMutablePointer<Float>?]()
            for _ in 0 ..< channels {
                let pointer = UnsafeMutablePointer<Float>.allocate(capacity: count)
                chunk.withUnsafeBufferPointer { source in
                    pointer.initialize(from: source.baseAddress!, count: count)
                }
                pointers.append(pointer)
            }

            pointers.withUnsafeMutableBufferPointer { buffer in
                VBN_Process(state, buffer.baseAddress, Int32(count), Int32(channels))
            }

            output.append(contentsOf: UnsafeBufferPointer(start: pointers[0], count: count))
            for pointer in pointers {
                pointer?.deallocate()
            }
            frame += count
        }
        return output
    }

    // MARK: - Config plumbing

    func testDefaultConfigMatchesHistoricalConstants() {
        let config = VBN_GetDefaultConfig()
        XCTAssertEqual(config.targetLUFS, -17)
        XCTAssertEqual(config.maxGainDB, 24)
        XCTAssertEqual(config.minGainDB, -12)
        XCTAssertEqual(config.gainSmoothingTauSeconds, 0.5)
        XCTAssertFalse(config.adaptiveGainSmoothing)
        XCTAssertTrue(config.hpEnabled)
        XCTAssertEqual(config.hpFrequency, 80)
        XCTAssertEqual(config.hpQ, 0.707)
        XCTAssertTrue(config.compEnabled)
        XCTAssertEqual(config.compThresholdDB, -8)
        XCTAssertEqual(config.compRatio, 2)
        XCTAssertEqual(config.compKneeWidthDB, 0, "hard knee is the historical behavior")
        XCTAssertEqual(config.limiterCeilingDB, -2)
        XCTAssertEqual(config.limiterLookaheadMs, 5)
        XCTAssertFalse(config.truePeakEnabled)
        XCTAssertTrue(config.initialGainDB.isNaN)
    }

    func testSetConfigIsAppliedAtNextProcess() throws {
        let state = try XCTUnwrap(VBN_Create(sampleRate))
        defer { VBN_Destroy(state) }

        XCTAssertEqual(VBN_GetTargetLUFS(state), -17)

        var config = VBN_GetDefaultConfig()
        config.targetLUFS = -12
        VBN_SetConfig(state, &config)

        // staged, not yet applied
        XCTAssertEqual(VBN_GetTargetLUFS(state), -17)

        processSine(state, frequency: 440, amplitude: 0.1, seconds: 0.05)
        XCTAssertEqual(VBN_GetTargetLUFS(state), -12)
    }

    func testSetInitialGainSeedsImmediately() throws {
        var config = VBN_GetDefaultConfig()
        let state = try XCTUnwrap(VBN_CreateWithConfig(sampleRate, &config))
        defer { VBN_Destroy(state) }

        VBN_SetInitialGainDB(state, 6)
        XCTAssertEqual(VBN_GetCurrentGainDB(state), 6, accuracy: 0.01)

        // clamped to the config's gain range
        VBN_SetInitialGainDB(state, 100)
        XCTAssertEqual(VBN_GetCurrentGainDB(state), config.maxGainDB, accuracy: 0.01)
    }

    func testConfigSwapFromAnotherThreadWhileProcessing() throws {
        let state = try XCTUnwrap(VBN_Create(sampleRate))
        defer { VBN_Destroy(state) }

        let stateBox = PocketCastsUtils.UncheckedSendable(state)
        let writerDone = expectation(description: "writer finished")
        Thread.detachNewThread {
            for i in 0 ..< 500 {
                var config = VBN_GetDefaultConfig()
                config.targetLUFS = -10 - Float(i % 10)
                config.compKneeWidthDB = Float(i % 12)
                config.truePeakEnabled = i % 2 == 0
                VBN_SetConfig(stateBox.value, &config)
            }
            writerDone.fulfill()
        }

        // reader keeps processing concurrently
        processSine(state, frequency: 440, amplitude: 0.2, seconds: 2)
        wait(for: [writerDone], timeout: 10)

        // one more buffer applies whatever was staged last; must not crash and
        // must end on a staged value
        processSine(state, frequency: 440, amplitude: 0.2, seconds: 0.05)
        XCTAssertLessThanOrEqual(VBN_GetTargetLUFS(state), -10)
    }

    // MARK: - LUFS measurement

    func testMonoSineLoudnessMeasurement() throws {
        var config = VBN_GetDefaultConfig()
        let state = try XCTUnwrap(VBN_CreateWithConfig(sampleRate, &config))
        defer { VBN_Destroy(state) }

        // A full-scale 997 Hz sine reads -3.01 LUFS; at peak 0.1 (-20 dBFS) it
        // reads about -23 LUFS
        processSine(state, frequency: 997, amplitude: 0.1, seconds: 5)
        XCTAssertEqual(VBN_GetMeasuredLUFS(state), -23.0, accuracy: 0.7)
    }

    func testStereoDualMonoReadsThreeLUHigherThanMono() throws {
        let monoState = try XCTUnwrap(VBN_Create(sampleRate))
        let stereoState = try XCTUnwrap(VBN_Create(sampleRate))
        defer {
            VBN_Destroy(monoState)
            VBN_Destroy(stereoState)
        }

        processSine(monoState, frequency: 997, amplitude: 0.1, seconds: 5, channels: 1)
        processSine(stereoState, frequency: 997, amplitude: 0.1, seconds: 5, channels: 2)

        let difference = VBN_GetMeasuredLUFS(stereoState) - VBN_GetMeasuredLUFS(monoState)
        XCTAssertEqual(difference, 3.01, accuracy: 0.3, "BS.1770 sums per-channel energy, so dual-mono stereo reads +3 LU")
    }

    // MARK: - Gain ramping

    func testGainChangesNeverClick() throws {
        var config = isolationConfig()
        config.gainSmoothingTauSeconds = 0.1 // fast convergence to stress ramping
        let state = try XCTUnwrap(VBN_CreateWithConfig(sampleRate, &config))
        defer { VBN_Destroy(state) }

        // settle at one target, then yank the target 10 dB
        var output = processSine(state, frequency: 500, amplitude: 0.05, seconds: 4)
        var louder = config
        louder.targetLUFS = config.targetLUFS + 10
        VBN_SetConfig(state, &louder)
        output += processSine(state, frequency: 500, amplitude: 0.05, seconds: 2)

        // natural adjacent-sample delta of a 500 Hz sine at the max possible
        // gain (24 dB → x15.8) is 0.05 * 15.8 * 2π * 500 / 44100 ≈ 0.056;
        // an un-ramped 1 dB gain step would jump ≥ 0.09 on a peak sample
        var maxDelta: Float = 0
        for i in 1 ..< output.count {
            maxDelta = max(maxDelta, abs(output[i] - output[i - 1]))
        }
        XCTAssertLessThan(maxDelta, 0.07, "per-sample gain ramping should keep the output continuous")
    }

    // MARK: - Compressor knee

    func testSoftKneeReducesBelowThresholdWhereHardKneeDoesNot() throws {
        // Same signal 2 dB below the threshold: a 12 dB soft knee starts
        // reducing before threshold, a hard knee doesn't touch it
        let amplitudeAtMinus10dB = pow(10.0, -10.0 / 20.0) // threshold is -8 dB

        var hardConfig = isolationConfig()
        hardConfig.compEnabled = true
        hardConfig.compKneeWidthDB = 0
        hardConfig.compAttackMs = 5
        hardConfig.compReleaseMs = 200

        var softConfig = hardConfig
        softConfig.compKneeWidthDB = 12

        let hardState = try XCTUnwrap(VBN_CreateWithConfig(sampleRate, &hardConfig))
        let softState = try XCTUnwrap(VBN_CreateWithConfig(sampleRate, &softConfig))
        defer {
            VBN_Destroy(hardState)
            VBN_Destroy(softState)
        }

        let hardOut = processSine(hardState, frequency: 997, amplitude: amplitudeAtMinus10dB, seconds: 2)
        let softOut = processSine(softState, frequency: 997, amplitude: amplitudeAtMinus10dB, seconds: 2)

        // compare steady-state RMS over the last half
        func rms(_ samples: ArraySlice<Float>) -> Float {
            sqrt(samples.reduce(0) { $0 + $1 * $1 } / Float(samples.count))
        }
        let hardRMS = rms(hardOut.suffix(hardOut.count / 2))
        let softRMS = rms(softOut.suffix(softOut.count / 2))

        let differenceDB = 20 * log10(softRMS / hardRMS)
        XCTAssertLessThan(differenceDB, -0.1, "soft knee should reduce gain below threshold")
        XCTAssertGreaterThan(differenceDB, -1.5, "knee reduction below threshold should stay gentle")
    }

    // MARK: - Limiter

    func testSamplePeakLimiterHoldsCeiling() throws {
        var config = isolationConfig()
        config.limiterCeilingDB = -2
        let state = try XCTUnwrap(VBN_CreateWithConfig(sampleRate, &config))
        defer { VBN_Destroy(state) }

        let output = processSine(state, frequency: 997, amplitude: 1.0, seconds: 1)
        let ceiling = pow(10.0 as Float, -2.0 / 20.0)
        let maxSample = output.map(abs).max() ?? 0
        XCTAssertLessThanOrEqual(maxSample, ceiling * 1.02)
    }

    func testTruePeakModeCatchesInterSamplePeaks() throws {
        // A sine at fs/4 with a 45° phase offset hits sample values of only
        // ±(amplitude/√2) while its true (inter-sample) peak is the full
        // amplitude. Sample peaks (0.636) sit below the -2 dB ceiling (0.794),
        // so only true-peak detection reduces it.
        var samplePeakConfig = isolationConfig()
        samplePeakConfig.limiterCeilingDB = -2
        samplePeakConfig.truePeakEnabled = false

        var truePeakConfig = samplePeakConfig
        truePeakConfig.truePeakEnabled = true

        let samplePeakState = try XCTUnwrap(VBN_CreateWithConfig(sampleRate, &samplePeakConfig))
        let truePeakState = try XCTUnwrap(VBN_CreateWithConfig(sampleRate, &truePeakConfig))
        defer {
            VBN_Destroy(samplePeakState)
            VBN_Destroy(truePeakState)
        }

        let amplitude = 0.9
        let spOut = processSine(samplePeakState, frequency: sampleRate / 4, amplitude: amplitude, seconds: 1, phase: .pi / 4)
        let tpOut = processSine(truePeakState, frequency: sampleRate / 4, amplitude: amplitude, seconds: 1, phase: .pi / 4)

        let spMax = spOut.map(abs).max() ?? 0
        let tpMax = tpOut.map(abs).max() ?? 0

        XCTAssertEqual(spMax, Float(amplitude / 2.0.squareRoot()), accuracy: 0.01, "sample-peak limiter should not touch this signal")
        XCTAssertLessThan(VBN_GetLimiterReductionDB(truePeakState), -0.3, "true-peak mode should be reducing")
        XCTAssertLessThan(tpMax, spMax * 0.95)
    }

    // MARK: - Offline loudness meter

    private func meterFeedSine(_ meter: OpaquePointer, frequency: Double, amplitude: Double, seconds: Double, channels: Int) {
        let totalFrames = Int(seconds * sampleRate)
        var frame = 0
        let chunkSize = 32768
        while frame < totalFrames {
            let count = min(chunkSize, totalFrames - frame)
            let chunk = (0 ..< count).map { i in
                Float(amplitude * sin(2 * .pi * frequency * Double(frame + i) / sampleRate))
            }
            chunk.withUnsafeBufferPointer { buffer in
                var pointers: [UnsafePointer<Float>?] = Array(repeating: buffer.baseAddress, count: channels)
                pointers.withUnsafeMutableBufferPointer { pointerBuffer in
                    VBN_MeterProcess(meter, pointerBuffer.baseAddress, Int32(count), Int32(channels))
                }
            }
            frame += count
        }
    }

    func testMeterIntegratedLoudnessAccuracy() throws {
        // Full-scale 997 Hz sine = -3.01 LUFS, so peak 0.1 reads about -23 LUFS
        let meter = try XCTUnwrap(VBN_MeterCreate(sampleRate, 1))
        defer { VBN_MeterDestroy(meter) }

        meterFeedSine(meter, frequency: 997, amplitude: 0.1, seconds: 10, channels: 1)
        XCTAssertEqual(VBN_MeterIntegratedLUFS(meter), -23.0, accuracy: 0.5)
    }

    func testMeterStereoDualMonoReadsThreeLUHigher() throws {
        let mono = try XCTUnwrap(VBN_MeterCreate(sampleRate, 1))
        let stereo = try XCTUnwrap(VBN_MeterCreate(sampleRate, 2))
        defer {
            VBN_MeterDestroy(mono)
            VBN_MeterDestroy(stereo)
        }

        meterFeedSine(mono, frequency: 997, amplitude: 0.1, seconds: 10, channels: 1)
        meterFeedSine(stereo, frequency: 997, amplitude: 0.1, seconds: 10, channels: 2)

        XCTAssertEqual(VBN_MeterIntegratedLUFS(stereo) - VBN_MeterIntegratedLUFS(mono), 3.01, accuracy: 0.2)
    }

    func testMeterReturnsNaNForSilence() throws {
        let meter = try XCTUnwrap(VBN_MeterCreate(sampleRate, 1))
        defer { VBN_MeterDestroy(meter) }

        XCTAssertTrue(VBN_MeterIntegratedLUFS(meter).isNaN, "nothing fed yet")

        meterFeedSine(meter, frequency: 997, amplitude: 0, seconds: 5, channels: 1)
        XCTAssertTrue(VBN_MeterIntegratedLUFS(meter).isNaN, "digital silence has no measurable blocks")
    }
}
