import Foundation

/// The last-writer-wins ordering key for an op: wall-clock time, with the
/// writing device and its per-device sequence breaking ties so every merge
/// is deterministic regardless of the order logs are read in.
public struct OpStamp: Comparable, Hashable, Sendable {
    public let wallClockMs: Int64
    public let deviceID: String
    public let seq: UInt64

    public init(wallClockMs: Int64, deviceID: String, seq: UInt64) {
        self.wallClockMs = wallClockMs
        self.deviceID = deviceID
        self.seq = seq
    }

    /// A stamp reconstructed from a snapshot, which persists only the
    /// timestamp. Ties against snapshot stamps resolve in favour of live
    /// ops (empty device id sorts lowest).
    public init(wallClockMs: Int64) {
        self.init(wallClockMs: wallClockMs, deviceID: "", seq: 0)
    }

    public static func < (lhs: OpStamp, rhs: OpStamp) -> Bool {
        if lhs.wallClockMs != rhs.wallClockMs { return lhs.wallClockMs < rhs.wallClockMs }
        if lhs.deviceID != rhs.deviceID { return lhs.deviceID < rhs.deviceID }
        return lhs.seq < rhs.seq
    }
}

extension Filesync_OpEnvelope {
    var stamp: OpStamp {
        OpStamp(wallClockMs: wallClockMs, deviceID: deviceID, seq: seq)
    }
}
