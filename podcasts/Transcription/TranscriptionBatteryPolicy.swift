import Foundation
import UIKit

/// User-selectable policy for when LOCAL (on-device) transcription may run on
/// battery power. Remote/API jobs are unaffected — they cost network, not compute.
/// Low Power Mode always defers regardless of the chosen policy. Deferred jobs
/// stay queued (mirroring the thermal-throttle pattern) and drain when charging
/// begins, the battery recovers, or Low Power Mode ends.
nonisolated enum TranscriptionBatteryPolicy: Int32, CaseIterable {
    /// Run whenever thermals allow (Low Power Mode still defers).
    case always = 0
    /// Run on battery only above 30% charge. The default.
    case above30Percent = 1
    /// Run only while plugged in.
    case onlyWhileCharging = 2

    static let `default` = TranscriptionBatteryPolicy.above30Percent

    /// The threshold `above30Percent` gates on.
    static let batteryLevelThreshold: Float = 0.3

    var localizedTitle: String {
        switch self {
        case .always: L10n.transcriptionBatteryPolicyAlways
        case .above30Percent: L10n.transcriptionBatteryPolicyAbove30
        case .onlyWhileCharging: L10n.transcriptionBatteryPolicyCharging
        }
    }
}

/// Snapshot of the device's power situation, injectable for tests.
nonisolated struct TranscriptionPowerState: Sendable, Equatable {
    /// 0…1, or a negative value when battery monitoring is unavailable (the
    /// UIDevice convention). An unknown level is treated as below-threshold —
    /// policies stricter than `.always` defer rather than silently drain.
    var batteryLevel: Float
    var isCharging: Bool
    var isLowPowerModeEnabled: Bool

    /// Live device state. Requires `UIDevice.isBatteryMonitoringEnabled` to have
    /// been set at app start for a real `batteryLevel`.
    @MainActor
    static func current() -> TranscriptionPowerState {
        let device = UIDevice.current
        let charging = device.batteryState == .charging || device.batteryState == .full
        return TranscriptionPowerState(batteryLevel: device.batteryLevel,
                                       isCharging: charging,
                                       isLowPowerModeEnabled: ProcessInfo.processInfo.isLowPowerModeEnabled)
    }

    /// The pure deferral decision, unit-tested across the policy × state matrix.
    static func isDeferred(policy: TranscriptionBatteryPolicy, state: TranscriptionPowerState) -> Bool {
        if state.isLowPowerModeEnabled { return true }
        if state.isCharging { return false }
        switch policy {
        case .always:
            return false
        case .above30Percent:
            // Unknown level (< 0) defers: better to wait for a charger than to
            // silently drain a battery we can't read.
            return state.batteryLevel < TranscriptionBatteryPolicy.batteryLevelThreshold
        case .onlyWhileCharging:
            return true
        }
    }
}
