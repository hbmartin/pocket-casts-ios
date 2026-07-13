import Foundation

/// Tracks rapid repeated skip taps so the skip interval can grow (×1 → ×2 → ×4).
///
/// Each same-direction tap within `window` of the previous one doubles the
/// multiplier up to `maxMultiplier`; a direction change, a tap outside the
/// window, or an explicit `reset()` returns the streak to ×1.
struct SeekAccelerationTracker {
    enum Direction {
        case back
        case forward
    }

    /// Maximum time between taps for them to count as part of the same streak.
    let window: TimeInterval
    /// Cap for the interval multiplier.
    let maxMultiplier: Double

    private var multiplier: Double = 1
    private var lastDirection: Direction?
    private var lastTapDate: Date?

    init(window: TimeInterval = 1.5, maxMultiplier: Double = 4) {
        self.window = window
        self.maxMultiplier = maxMultiplier
    }

    /// Records a skip tap and returns the (possibly accelerated) amount to skip by.
    /// - Parameters:
    ///   - direction: The direction of this tap.
    ///   - baseAmount: The user's configured skip interval in seconds.
    ///   - now: Injectable clock for tests.
    mutating func amount(for direction: Direction, baseAmount: TimeInterval, now: Date = Date()) -> TimeInterval {
        if let lastTapDate, let lastDirection,
           lastDirection == direction,
           now.timeIntervalSince(lastTapDate) <= window {
            multiplier = min(multiplier * 2, maxMultiplier)
        } else {
            multiplier = 1
        }

        lastDirection = direction
        lastTapDate = now

        return baseAmount * multiplier
    }

    /// Clears the streak so the next tap skips by the base amount again.
    mutating func reset() {
        multiplier = 1
        lastDirection = nil
        lastTapDate = nil
    }
}
