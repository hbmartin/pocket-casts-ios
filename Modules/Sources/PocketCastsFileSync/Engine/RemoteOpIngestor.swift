import Foundation
import PocketCastsDataModel
import PocketCastsUtils

/// Reads peers' snapshots and op logs from the sync folder, resuming from
/// per-peer cursors, and produces the merged consensus state.
struct RemoteOpIngestor {
    let folder: any SyncFolder
    let dataManager: DataManager
    let deviceID: String

    struct IngestResult {
        var state: MergeEngine.MergedState
        /// Cursor updates to persist once the applier has committed.
        var cursorUpdates: [FileSyncCursor]
        var opsRead = 0
    }

    /// Incremental ingest of peers' new ops (resuming from stored cursors).
    func ingest() async throws -> IngestResult {
        try await ingest(devices: SyncFolderBootstrapper.peerDeviceIDs(folder: folder, ownDeviceID: deviceID),
                         useCursors: true)
    }

    /// Full re-read of every device's snapshot + logs (own included),
    /// ignoring cursors — used to build snapshots and the join bootstrap,
    /// which need complete state rather than the incremental tail.
    func fullMerge() async throws -> MergeEngine.MergedState {
        var devices = try await SyncFolderBootstrapper.peerDeviceIDs(folder: folder, ownDeviceID: deviceID)
        devices.append(deviceID)
        return try await ingest(devices: devices, useCursors: false).state
    }

    private func ingest(devices: [String], useCursors: Bool) async throws -> IngestResult {
        var snapshots: [Filesync_Snapshot] = []
        var ops: [Filesync_OpEnvelope] = []
        var cursorUpdates: [FileSyncCursor] = []

        for peer in devices {
            let peerDir = FileSyncFormat.deviceDirectory(deviceID: peer)
            let entries = try await folder.list(peerDir)
            var cursor = useCursors
                ? (dataManager.fileSyncCursor(peerDeviceId: peer) ?? FileSyncCursor(peerDeviceId: peer))
                : FileSyncCursor(peerDeviceId: peer)

            // Newest snapshot beyond what we've bootstrapped from.
            let snapshotEntries = entries
                .filter { !$0.isDirectory && $0.fileName.hasSuffix(".\(FileSyncFormat.snapshotFileExtension)") }
                .sorted { snapshotSeq($0.fileName) < snapshotSeq($1.fileName) }
            if let newest = snapshotEntries.last, snapshotSeq(newest.fileName) > cursor.lastAppliedSnapshotSeq {
                if let snapshot: Filesync_Snapshot = try? await folder.coordinatedRead(newest.relativePath, { url in
                    guard let data = try? Data(contentsOf: url) else { return nil }
                    return try? Filesync_Snapshot(serializedBytes: data)
                }) {
                    snapshots.append(snapshot)
                    cursor.lastAppliedSnapshotSeq = snapshotSeq(newest.fileName)
                    cursor.lastAppliedSeq = max(cursor.lastAppliedSeq, Int64(snapshot.asOfSeq))
                }
            }

            // Logs in order, resuming from the cursor's file+offset.
            let logEntries = entries
                .filter { !$0.isDirectory && $0.fileName.hasSuffix(".\(FileSyncFormat.logFileExtension)") }
                .sorted { $0.fileName < $1.fileName }
            for log in logEntries {
                // Skip logs entirely before the cursor's position.
                if let cursorFile = cursor.fileName, log.fileName < cursorFile { continue }

                let startOffset = (log.fileName == cursor.fileName) ? Int(cursor.recordOffset) : 0
                guard let data: Data = try? await folder.coordinatedRead(log.relativePath, { url in
                    try? Data(contentsOf: url)
                }) else { continue }
                guard startOffset < data.count else {
                    continue
                }

                let (result, nextOffset) = try OpLogFile.decode(data, fromOffset: startOffset)
                for envelope in result.envelopes where Int64(envelope.seq) > cursor.lastAppliedSeq {
                    ops.append(envelope)
                    cursor.lastAppliedSeq = max(cursor.lastAppliedSeq, Int64(envelope.seq))
                }
                cursor.fileName = log.fileName
                cursor.recordOffset = Int64(nextOffset)
                if result.truncated {
                    // Partially propagated file: stop here for this peer and
                    // retry the tail next pass.
                    break
                }
            }

            if useCursors {
                cursorUpdates.append(cursor)
            }
        }

        let state = MergeEngine.merged(snapshots: snapshots, ops: ops)
        return IngestResult(state: state, cursorUpdates: cursorUpdates, opsRead: ops.count)
    }

    /// Persist cursor progress after the applier commits.
    func commit(_ result: IngestResult) {
        for cursor in result.cursorUpdates {
            dataManager.save(fileSyncCursor: cursor)
        }
    }

    private func snapshotSeq(_ fileName: String) -> Int64 {
        // snapshot-<seq>.pcsnap
        let base = fileName
            .replacingOccurrences(of: "snapshot-", with: "")
            .replacingOccurrences(of: ".\(FileSyncFormat.snapshotFileExtension)", with: "")
        return Int64(base) ?? 0
    }
}
