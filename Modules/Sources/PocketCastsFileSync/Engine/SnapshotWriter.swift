import Foundation
import PocketCastsDataModel
import PocketCastsUtils

/// Writes this device's full-state checkpoint and compacts its own logs so
/// new devices bootstrap quickly and history does not grow forever.
struct SnapshotWriter {
    let folder: any SyncFolder
    let dataManager: DataManager
    let deviceID: String

    func snapshotIfNeeded(
        headSeq: Int64,
        nowMs: Int64,
        fullState: () async throws -> MergeEngine.MergedState
    ) async throws {
        var ownCursor = dataManager.fileSyncCursor(peerDeviceId: deviceID)
            ?? FileSyncCursor(peerDeviceId: deviceID)
        guard headSeq > ownCursor.lastSnapshotSeq else { return }

        let deviceDir = FileSyncFormat.deviceDirectory(deviceID: deviceID)
        let entries = try await folder.list(deviceDir)
        let logs = entries.filter { $0.fileName.hasSuffix(".\(FileSyncFormat.logFileExtension)") }
        let logBytes = logs.reduce(Int64(0)) { $0 + $1.sizeBytes }
        let newestSnapshotMtime = entries
            .filter { $0.fileName.hasSuffix(".\(FileSyncFormat.snapshotFileExtension)") }
            .map(\.mtimeMs)
            .max()

        let sizeDue = logBytes > Int64(FileSyncFormat.snapshotAfterLogBytes)
        let ageDue = newestSnapshotMtime.map {
            nowMs - $0 > Int64(FileSyncFormat.snapshotMaxAge * 1000)
        } ?? true
        guard sizeDue || ageDue else { return }

        let state = try await fullState()
        let snapshot = buildSnapshot(state: state, headSeq: headSeq, nowMs: nowMs)
        let path = "\(deviceDir)/\(FileSyncFormat.snapshotFileName(asOfSeq: UInt64(headSeq)))"
        try await folder.coordinatedWrite(path, data: snapshot.serializedData())

        ownCursor.lastSnapshotSeq = headSeq
        dataManager.save(fileSyncCursor: ownCursor)

        let graceCutoff = nowMs - Int64(FileSyncFormat.logCompactionGracePeriod * 1000)
        let activeLog = logs.map(\.fileName).max()
        for log in logs where log.mtimeMs < graceCutoff && log.fileName != activeLog {
            try? await folder.coordinatedDelete(log.relativePath)
        }
        for entry in entries where entry.fileName.hasSuffix(".\(FileSyncFormat.snapshotFileExtension)") {
            if entry.relativePath != path {
                try? await folder.coordinatedDelete(entry.relativePath)
            }
        }
        FileLog.shared.addMessage("FileSync: snapshot written at seq \(headSeq)")
    }

    func buildSnapshot(state: MergeEngine.MergedState, headSeq: Int64, nowMs: Int64) -> Filesync_Snapshot {
        var snapshot = Filesync_Snapshot()
        snapshot.deviceID = deviceID
        snapshot.createdAtMs = nowMs
        snapshot.asOfSeq = UInt64(headSeq)

        func snapshotRecord(_ record: Api_Record, stamps: [UInt32: OpStamp]) -> Filesync_SnapshotRecord {
            var out = Filesync_SnapshotRecord()
            out.record = record
            out.fieldModifiedMs = stamps.mapValues(\.wallClockMs)
            return out
        }

        for merged in state.podcasts.values {
            var record = Api_Record()
            record.podcast = merged.record
            snapshot.records.append(snapshotRecord(record, stamps: merged.stamps))
        }
        for merged in state.episodes.values {
            var record = Api_Record()
            record.episode = merged.record
            snapshot.records.append(snapshotRecord(record, stamps: [:]))
        }
        for merged in state.playlists.values {
            var record = Api_Record()
            record.playlist = merged.record
            snapshot.records.append(snapshotRecord(record, stamps: merged.stamps))
        }
        for merged in state.folders.values {
            var record = Api_Record()
            record.folder = merged.record
            snapshot.records.append(snapshotRecord(record, stamps: merged.stamps))
        }
        for merged in state.bookmarks.values {
            var record = Api_Record()
            record.bookmark = merged.record
            snapshot.records.append(snapshotRecord(record, stamps: merged.stamps))
        }

        let tombstoneCutoff = nowMs - Int64(FileSyncFormat.tombstoneRetention * 1000)
        snapshot.tombstones = state.tombstones.values.filter { $0.deletedAtMs > tombstoneCutoff }

        if let lastQueueOp = state.upNextOps.last {
            let entries = UpNextMerger.replay(ops: state.upNextOps)
            var upNext = Filesync_UpNextState()
            upNext.entries = entries.map { entry in
                var out = Filesync_UpNextEntry()
                out.episodeUuid = entry.episodeUuid
                out.podcastUuid = entry.podcastUuid
                return out
            }
            upNext.modifiedAtMs = lastQueueOp.stamp.wallClockMs
            snapshot.upNext = upNext
        }

        snapshot.settings = state.settings.map { name, value in
            var op = Filesync_SettingOp()
            op.name = name
            op.jsonValue = value.jsonValue
            op.modifiedAtMs = value.stamp.wallClockMs
            return op
        }
        if let ownStats = state.statsByDevice[deviceID]?.stats {
            snapshot.stats = ownStats
        }
        snapshot.uploads = state.uploads.values.map(\.identity)
        snapshot.uploadTombstones = state.uploadTombstones.map { uuid, stamp in
            var tombstone = Filesync_UploadTombstone()
            tombstone.uuid = uuid
            tombstone.deletedAtMs = stamp.wallClockMs
            return tombstone
        }
        return snapshot
    }
}
