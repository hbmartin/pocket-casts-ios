import Foundation
import GRDB
import GRDBMacros

/// File-sync read/write progress, one row per peer device plus one row for
/// this device's own write-side state (`peerDeviceId` = own device id).
@GRDBRecord(table: "FileSyncCursor")
public struct FileSyncCursor: Equatable, Sendable {
    public var peerDeviceId = ""
    /// The log file this cursor stopped in (peer rows).
    public var fileName: String?
    /// Byte offset of the next unread record within `fileName`.
    public var recordOffset: Int64 = 0
    /// Highest peer op seq applied locally.
    public var lastAppliedSeq: Int64 = 0
    /// The peer snapshot seq this cursor bootstrapped from.
    public var lastAppliedSnapshotSeq: Int64 = 0
    /// Own row only: index of the log file currently being written.
    public var currentLogIndex: Int64 = 0
    /// Own row only: highest op seq assigned to a flushed journal entry.
    public var headSeq: Int64 = 0
    /// Own row only: seq covered by the newest snapshot written.
    public var lastSnapshotSeq: Int64 = 0

    public init(
        peerDeviceId: String = "",
        fileName: String? = nil,
        recordOffset: Int64 = 0,
        lastAppliedSeq: Int64 = 0,
        lastAppliedSnapshotSeq: Int64 = 0,
        currentLogIndex: Int64 = 0,
        headSeq: Int64 = 0,
        lastSnapshotSeq: Int64 = 0
    ) {
        self.peerDeviceId = peerDeviceId
        self.fileName = fileName
        self.recordOffset = recordOffset
        self.lastAppliedSeq = lastAppliedSeq
        self.lastAppliedSnapshotSeq = lastAppliedSnapshotSeq
        self.currentLogIndex = currentLogIndex
        self.headSeq = headSeq
        self.lastSnapshotSeq = lastSnapshotSeq
    }
}
