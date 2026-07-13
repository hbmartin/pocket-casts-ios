import XCTest

@testable import podcasts

/// The pure deferral decision behind the "Transcribe on Battery" setting.
final class TranscriptionBatteryPolicyTests: XCTestCase {
    private func deferred(_ policy: TranscriptionBatteryPolicy,
                          level: Float,
                          charging: Bool = false,
                          lowPower: Bool = false) -> Bool {
        TranscriptionPowerState.isDeferred(policy: policy,
                                           state: TranscriptionPowerState(batteryLevel: level,
                                                                          isCharging: charging,
                                                                          isLowPowerModeEnabled: lowPower))
    }

    func testLowPowerModeDefersUnderEveryPolicy() {
        for policy in TranscriptionBatteryPolicy.allCases {
            XCTAssertTrue(deferred(policy, level: 1.0, charging: false, lowPower: true), "\(policy)")
            // Even while charging: Low Power Mode is an explicit user signal.
            XCTAssertTrue(deferred(policy, level: 1.0, charging: true, lowPower: true), "\(policy)")
        }
    }

    func testChargingRunsUnderEveryPolicy() {
        for policy in TranscriptionBatteryPolicy.allCases {
            XCTAssertFalse(deferred(policy, level: 0.05, charging: true), "\(policy)")
        }
    }

    func testAlwaysRunsOnAnyBatteryLevel() {
        XCTAssertFalse(deferred(.always, level: 0.02))
        XCTAssertFalse(deferred(.always, level: -1), "Unknown level fails open under .always")
    }

    func testAbove30PercentThreshold() {
        XCTAssertFalse(deferred(.above30Percent, level: 0.31))
        XCTAssertTrue(deferred(.above30Percent, level: 0.29))
        XCTAssertTrue(deferred(.above30Percent, level: -1),
                      "Unknown level defers: better to wait for a charger than silently drain")
    }

    func testOnlyWhileChargingDefersOnBattery() {
        XCTAssertTrue(deferred(.onlyWhileCharging, level: 1.0))
        XCTAssertFalse(deferred(.onlyWhileCharging, level: 1.0, charging: true))
    }

    func testDefaultPolicyIsAbove30() {
        XCTAssertEqual(TranscriptionBatteryPolicy.default, .above30Percent)
    }
}
