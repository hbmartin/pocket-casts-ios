import XCTest
@testable import podcasts
import PocketCastsDataModel

@MainActor
final class AdvancedAudioSettingsViewModelTests: XCTestCase {
    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: Constants.UserDefaults.audioTuning)
        UserDefaults.standard.removeObject(forKey: Constants.UserDefaults.voiceBoostNEnabled)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: Constants.UserDefaults.audioTuning)
        UserDefaults.standard.removeObject(forKey: Constants.UserDefaults.voiceBoostNEnabled)
        super.tearDown()
    }

    private func drainMainQueue() {
        let drained = expectation(description: "main queue drained")
        DispatchQueue.main.async { drained.fulfill() }
        wait(for: [drained], timeout: 1)
    }

    func testInitLoadsFromSettings() {
        var stored = AudioTuning.default
        stored.voiceBoost.targetLUFS = -22
        Settings.audioTuning = stored

        let model = AdvancedAudioSettingsViewModel(commitDebounce: 0)
        XCTAssertEqual(model.tuning, stored)
    }

    func testMutationCommitsToSettings() {
        let model = AdvancedAudioSettingsViewModel(commitDebounce: 0)
        model.tuning.trim.hysteresisDB = 4

        drainMainQueue()
        XCTAssertEqual(Settings.audioTuning.trim.hysteresisDB, 4)
    }

    func testSectionResetOnlyTouchesThatSection() {
        let model = AdvancedAudioSettingsViewModel(commitDebounce: 0)
        model.tuning.trim.hysteresisDB = 4
        model.tuning.voiceBoost.targetLUFS = -22

        model.resetTrimSilence()
        drainMainQueue()

        XCTAssertEqual(model.tuning.trim, TrimTuning())
        XCTAssertEqual(model.tuning.voiceBoost.targetLUFS, -22)
    }

    func testResetAllRemovesStoredTuning() {
        let model = AdvancedAudioSettingsViewModel(commitDebounce: 0)
        model.tuning.voiceBoost.compRatio = 4
        drainMainQueue()
        XCTAssertNotNil(UserDefaults.standard.object(forKey: Constants.UserDefaults.audioTuning))

        model.resetAll()
        drainMainQueue()

        XCTAssertNil(UserDefaults.standard.object(forKey: Constants.UserDefaults.audioTuning))
        XCTAssertEqual(model.tuning, .default)
    }

    func testLoadTrimPresetSeedsCustomValues() {
        let model = AdvancedAudioSettingsViewModel(commitDebounce: 0)
        model.loadTrimPreset(.high)

        XCTAssertTrue(model.tuning.trim.useCustomGate)
        let preset = TrimSilenceParameters.preset(for: .high)
        XCTAssertEqual(model.tuning.trim.thresholdDB, preset.enterThresholdDB)
        XCTAssertEqual(model.tuning.trim.minGapMs, preset.minGapMs)
        XCTAssertEqual(model.tuning.trim.keepGapMs, preset.keepGapMs)
    }
}
