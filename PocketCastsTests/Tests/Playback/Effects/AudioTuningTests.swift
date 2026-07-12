import XCTest
@testable import podcasts
import PocketCastsDataModel

final class AudioTuningTests: XCTestCase {
    // MARK: - Defaults match the legacy engine constants

    func testDefaultsMatchCurrentEngineBehavior() {
        let tuning = AudioTuning.default

        // Trim silence: legacy medium preset
        XCTAssertFalse(tuning.trim.useCustomGate)
        XCTAssertEqual(tuning.trim.discriminator, .rms)
        XCTAssertEqual(pow(10, tuning.trim.thresholdDB / 20), 0.00511, accuracy: 0.0001)
        XCTAssertFalse(tuning.trim.adaptiveNoiseFloor)
        XCTAssertEqual(tuning.trim.hysteresisDB, 0)
        XCTAssertEqual(tuning.trim.holdTimeMs, 0)
        XCTAssertEqual(tuning.trim.crossfadeMs, 0)
        XCTAssertEqual(tuning.trim.endGuardSeconds, 5)

        // Voice boost: VoiceBoostN_Internal.h constants
        XCTAssertTrue(tuning.voiceBoost.useVoiceBoostN)
        XCTAssertEqual(tuning.voiceBoost.targetLUFS, -17)
        XCTAssertEqual(tuning.voiceBoost.maxGainDB, 24)
        XCTAssertEqual(tuning.voiceBoost.minGainDB, -12)
        XCTAssertTrue(tuning.voiceBoost.hpEnabled)
        XCTAssertEqual(tuning.voiceBoost.hpFrequency, 80)
        XCTAssertEqual(tuning.voiceBoost.hpQ, 0.707)
        XCTAssertTrue(tuning.voiceBoost.compEnabled)
        XCTAssertEqual(tuning.voiceBoost.compThresholdDB, -8)
        XCTAssertEqual(tuning.voiceBoost.compRatio, 2)
        XCTAssertEqual(tuning.voiceBoost.compAttackMs, 100)
        XCTAssertEqual(tuning.voiceBoost.compReleaseMs, 400)
        XCTAssertEqual(tuning.voiceBoost.compKneeWidthDB, 0, "hard knee is the legacy behavior")
        XCTAssertEqual(tuning.voiceBoost.limiterCeilingDB, -2)
        XCTAssertEqual(tuning.voiceBoost.limiterLookaheadMs, 5)
        XCTAssertEqual(tuning.voiceBoost.limiterReleaseMs, 100)
        XCTAssertFalse(tuning.voiceBoost.truePeakEnabled, "sample-peak is the legacy behavior")

        // Time stretch
        XCTAssertEqual(tuning.timeStretch.effectsPlayerAlgorithm, .iPodTimeOther)
        XCTAssertEqual(tuning.timeStretch.defaultPlayerAlgorithm, .timeDomain)

        XCTAssertTrue(tuning.isDefault)
    }

    // MARK: - Preset table reproduces the legacy buffer math

    func testPresetTableMatchesLegacyBufferCounts() {
        // Legacy constants lived in AudioReadTask as buffer counts of 1152
        // frames; the preset table stores milliseconds that must convert back
        // to the identical counts at 44.1 kHz.
        func buffers(_ ms: Double, sampleRate: Double = 44100, framesPerBuffer: Double = 1152) -> Int {
            max(1, Int((ms / 1000 * sampleRate / framesPerBuffer).rounded()))
        }

        let low = TrimSilenceParameters.preset(for: .low)
        XCTAssertEqual(pow(10, low.enterThresholdDB / 20), 0.0055, accuracy: 0.0001)
        XCTAssertEqual(buffers(low.minGapMs), 20)
        XCTAssertEqual(buffers(low.keepGapMs), 14)

        let medium = TrimSilenceParameters.preset(for: .medium)
        XCTAssertEqual(pow(10, medium.enterThresholdDB / 20), 0.00511, accuracy: 0.0001)
        XCTAssertEqual(buffers(medium.minGapMs), 16)
        XCTAssertEqual(buffers(medium.keepGapMs), 12)

        let high = TrimSilenceParameters.preset(for: .high)
        XCTAssertEqual(pow(10, high.enterThresholdDB / 20), 0.005, accuracy: 0.0001)
        XCTAssertEqual(buffers(high.minGapMs), 4)
        XCTAssertEqual(high.keepGapMs, 0)

        for amount in [TrimSilenceAmount.low, .medium, .high] {
            let preset = TrimSilenceParameters.preset(for: amount)
            XCTAssertEqual(preset.hysteresisDB, 0)
            XCTAssertEqual(preset.holdTimeMs, 0)
            XCTAssertEqual(preset.crossfadeMs, 0)
            XCTAssertEqual(preset.endGuardSeconds, 5)
            XCTAssertFalse(preset.useAdaptiveFloor)
            XCTAssertEqual(preset.discriminator, .rms)
        }
    }

    func testTrimParametersPrefersPresetUnlessCustom() {
        var tuning = AudioTuning.default
        tuning.trim.thresholdDB = -60
        tuning.trim.minGapMs = 1000

        tuning.trim.useCustomGate = false
        XCTAssertEqual(tuning.trimParameters(for: .high), .preset(for: .high))

        tuning.trim.useCustomGate = true
        let custom = tuning.trimParameters(for: .high)
        XCTAssertEqual(custom.enterThresholdDB, -60)
        XCTAssertEqual(custom.minGapMs, 1000)
    }

    // MARK: - Codable

    func testCodableRoundTrip() throws {
        var tuning = AudioTuning.default
        tuning.trim.useCustomGate = true
        tuning.trim.discriminator = .vad
        tuning.trim.thresholdDB = -52.5
        tuning.voiceBoost.targetLUFS = -14
        tuning.voiceBoost.truePeakEnabled = true
        tuning.timeStretch.effectsPlayerAlgorithm = .spectral
        tuning.timeStretch.defaultPlayerAlgorithm = .varispeed
        tuning.normalize.enabled = true
        tuning.normalize.targetLUFS = -18

        let data = try JSONEncoder().encode(tuning)
        let decoded = try JSONDecoder().decode(AudioTuning.self, from: data)
        XCTAssertEqual(decoded, tuning)
    }

    // MARK: - Normalize volume (E1)

    func testNormalizeDefaultsOffAtMinusSixteen() {
        let tuning = AudioTuning.default
        XCTAssertFalse(tuning.normalize.enabled)
        XCTAssertEqual(tuning.normalize.targetLUFS, -16)
    }

    func testNormalizeTargetClampsOnDecode() throws {
        let json = """
        {"normalize": {"enabled": true, "targetLUFS": -60}}
        """
        let decoded = try JSONDecoder().decode(AudioTuning.self, from: Data(json.utf8))
        XCTAssertTrue(decoded.normalize.enabled)
        XCTAssertEqual(decoded.normalize.targetLUFS, NormalizeTuning.targetLUFSRange.lowerBound)

        let high = try JSONDecoder().decode(AudioTuning.self, from: Data("{\"normalize\": {\"targetLUFS\": 3}}".utf8))
        XCTAssertEqual(high.normalize.targetLUFS, NormalizeTuning.targetLUFSRange.upperBound)
    }

    func testNormalizeMissingSectionDecodesToDefault() throws {
        let decoded = try JSONDecoder().decode(AudioTuning.self, from: Data("{\"voiceBoost\": {\"targetLUFS\": -14}}".utf8))
        XCTAssertEqual(decoded.normalize, NormalizeTuning())
    }

    func testNormalizeConfigBypassesCharacterProcessing() {
        var tuning = AudioTuning.default
        tuning.normalize.enabled = true
        tuning.normalize.targetLUFS = -18
        // Character settings on the boost chain must not leak into normalize-only playback.
        tuning.voiceBoost.compEnabled = true
        tuning.voiceBoost.hpEnabled = true
        tuning.voiceBoost.targetLUFS = -12

        let config = tuning.vbnNormalizeConfig()
        XCTAssertEqual(config.targetLUFS, -18)
        XCTAssertFalse(config.compEnabled)
        XCTAssertFalse(config.hpEnabled)
        XCTAssertTrue(config.truePeakEnabled, "the true-peak limiter is the safety net and always stays on")

        // The boost config is unaffected by normalize settings.
        let boostConfig = tuning.vbnConfig()
        XCTAssertEqual(boostConfig.targetLUFS, -12)
        XCTAssertTrue(boostConfig.compEnabled)
    }

    func testDecodingEmptyObjectYieldsDefaults() throws {
        let decoded = try JSONDecoder().decode(AudioTuning.self, from: Data("{}".utf8))
        XCTAssertEqual(decoded, .default)
    }

    func testDecodingToleratesUnknownAndMissingFields() throws {
        let json = """
        {"version": 1, "trim": {"thresholdDB": -50, "someFutureField": true}, "someOtherFutureSection": {"x": 1}}
        """
        let decoded = try JSONDecoder().decode(AudioTuning.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.trim.thresholdDB, -50)

        var expected = AudioTuning.default
        expected.trim.thresholdDB = -50
        XCTAssertEqual(decoded, expected)
    }

    // MARK: - Resilient enum decode (C1)

    func testUnknownDiscriminatorDegradesOnlyThatField() throws {
        // An unrecognized enum raw value (e.g. a case a newer build added, decoded after a
        // downgrade) must fall back to the default for that one field WITHOUT discarding the
        // rest of the trim block or the other sections.
        let json = """
        {"trim": {"thresholdDB": -52, "discriminator": "someFutureAlgo"}, "voiceBoost": {"targetLUFS": -14}}
        """
        let decoded = try JSONDecoder().decode(AudioTuning.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.trim.discriminator, AudioTuning.default.trim.discriminator, "unknown enum falls back to default")
        XCTAssertEqual(decoded.trim.thresholdDB, -52, "a sibling field survives the unknown enum")
        XCTAssertEqual(decoded.voiceBoost.targetLUFS, -14, "other sections survive the unknown enum")
    }

    func testUnknownTimeStretchAlgorithmDegradesOnlyThatField() throws {
        let json = """
        {"timeStretch": {"effectsPlayerAlgorithm": "goneCase", "defaultPlayerAlgorithm": "spectral"}}
        """
        let decoded = try JSONDecoder().decode(AudioTuning.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.timeStretch.effectsPlayerAlgorithm, AudioTuning.default.timeStretch.effectsPlayerAlgorithm)
        XCTAssertEqual(decoded.timeStretch.defaultPlayerAlgorithm, .spectral, "a valid sibling enum still decodes")
    }

    // MARK: - Clamping (C3)

    func testDecodingClampsOutOfRangeValues() throws {
        let json = """
        {"trim": {"thresholdDB": 999, "minGapMs": -100}, "voiceBoost": {"maxGainDB": 1000, "compRatio": 0}}
        """
        let decoded = try JSONDecoder().decode(AudioTuning.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.trim.thresholdDB, TrimTuning.thresholdDBRange.upperBound)
        XCTAssertEqual(decoded.trim.minGapMs, TrimTuning.minGapMsRange.lowerBound)
        XCTAssertEqual(decoded.voiceBoost.maxGainDB, VoiceBoostTuning.maxGainDBRange.upperBound)
        XCTAssertEqual(decoded.voiceBoost.compRatio, VoiceBoostTuning.compRatioRange.lowerBound)
    }

    func testDefaultsAreWithinClampRanges() {
        // Guards against clamped() silently altering a default (every default must sit inside
        // its range, else decoding a default-valued blob would change behavior).
        XCTAssertEqual(AudioTuning.default.trim, AudioTuning.default.trim.clamped())
        XCTAssertEqual(AudioTuning.default.voiceBoost, AudioTuning.default.voiceBoost.clamped())
    }
}
