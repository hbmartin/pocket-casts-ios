import XCTest
@testable import podcasts
import PocketCastsUtils

@MainActor
final class SettingsAudioTuningTests: XCTestCase {
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

    func testDefaultWhenNothingStored() {
        XCTAssertEqual(Settings.audioTuning, .default)
    }

    func testSetGetRoundTrip() {
        var tuning = AudioTuning.default
        tuning.voiceBoost.targetLUFS = -20
        tuning.trim.useCustomGate = true

        Settings.audioTuning = tuning
        XCTAssertEqual(Settings.audioTuning, tuning)
    }

    func testSettingDefaultRemovesStoredBlob() {
        var tuning = AudioTuning.default
        tuning.trim.hysteresisDB = 3
        Settings.audioTuning = tuning
        XCTAssertNotNil(UserDefaults.standard.object(forKey: Constants.UserDefaults.audioTuning))

        Settings.audioTuning = .default
        XCTAssertNil(UserDefaults.standard.object(forKey: Constants.UserDefaults.audioTuning))
        XCTAssertEqual(Settings.audioTuning, .default)
    }

    func testSetterPostsNotificationOnce() {
        var tuning = AudioTuning.default
        tuning.voiceBoost.compRatio = 3

        let notified = expectation(forNotification: Notification.Name("SJAudioTuningDidChange"), object: nil)
        notified.expectedFulfillmentCount = 1
        Settings.audioTuning = tuning
        wait(for: [notified], timeout: 1)
    }

    func testNoOpWritePostsNothing() {
        var tuning = AudioTuning.default
        tuning.voiceBoost.compRatio = 3
        Settings.audioTuning = tuning

        let notNotified = expectation(forNotification: Notification.Name("SJAudioTuningDidChange"), object: nil)
        notNotified.isInverted = true
        Settings.audioTuning = tuning
        wait(for: [notNotified], timeout: 0.2)
    }

    func testCorruptBlobFallsBackToDefault() {
        UserDefaults.standard.set(Data("not json".utf8), forKey: Constants.UserDefaults.audioTuning)
        XCTAssertEqual(Settings.audioTuning, .default)
    }

    func testLegacyVoiceBoostOptOutIsHonoredUntilBlobExists() {
        UserDefaults.standard.set(false, forKey: Constants.UserDefaults.voiceBoostNEnabled)
        XCTAssertFalse(Settings.audioTuning.voiceBoost.useVoiceBoostN)

        // Resetting to default clears the legacy opt-out too
        var tuning = AudioTuning.default
        tuning.trim.hysteresisDB = 1
        Settings.audioTuning = tuning
        Settings.audioTuning = .default
        XCTAssertTrue(Settings.audioTuning.voiceBoost.useVoiceBoostN)
    }
}
