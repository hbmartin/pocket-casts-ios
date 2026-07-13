import Foundation
import PocketCastsDataModel
import PocketCastsUtils

/// Turns pending journal entries into op envelopes and appends them to
/// this device's current log file. Values are read from live DB rows at
/// flush time, so bursts of edits become compact, up-to-date ops.
struct OpJournalFlusher {
    let folder: any SyncFolder
    let dataManager: DataManager
    let deviceID: String
    /// Injectable clock so simulations control time; production uses the wall clock.
    var now: @Sendable () -> Int64 = FileSyncClock.currentUTCTimeInMillis

    struct Result {
        var flushedOps = 0
        var headSeq: Int64 = 0
    }

    func flush(settings: [FileSyncSettingChange], stats: Filesync_StatsCumulative?) async throws -> Result {
        var ownCursor = dataManager.fileSyncCursor(peerDeviceId: deviceID)
            ?? FileSyncCursor(peerDeviceId: deviceID, currentLogIndex: 1)
        if ownCursor.currentLogIndex == 0 { ownCursor.currentLogIndex = 1 }

        let entries = coalesce(dataManager.unflushedFileSyncEntries(limit: 500))
        var envelopes: [Filesync_OpEnvelope] = []
        var flushedAssignments: [(entryIDs: [Int64], seq: Int64)] = []
        var nextSeq = ownCursor.headSeq

        for group in entries {
            guard let payload = payload(for: group) else {
                if !group.holdBack {
                    flushedAssignments.append((group.entryIDs, nextSeq))
                }
                continue
            }
            nextSeq += 1
            var envelope = Filesync_OpEnvelope()
            envelope.opID = UUID().uuidString.lowercased()
            envelope.deviceID = deviceID
            envelope.seq = UInt64(nextSeq)
            envelope.wallClockMs = group.wallClockMs
            envelope.payload = payload
            envelopes.append(envelope)
            flushedAssignments.append((group.entryIDs, nextSeq))
        }

        let settingsDigest = settings.map { "\($0.name)=\($0.jsonValue)@\($0.modifiedAtMs)" }
            .sorted()
            .joined(separator: "|")
        let statsDigest = stats.map {
            "\($0.timeListened)|\($0.timesStartedAt)|\($0.timeSkipping)|\($0.timeIntroSkipping)|\($0.timeSilenceRemoval)|\($0.timeVariableSpeed)"
        } ?? ""
        let digestKey = "FileSync.flushDigest.\(deviceID)"
        let previousDigest = UserDefaults.standard.string(forKey: digestKey) ?? ""
        let digest = settingsDigest + "#" + statsDigest
        if digest != previousDigest {
            for change in settings {
                nextSeq += 1
                var envelope = Filesync_OpEnvelope()
                envelope.opID = UUID().uuidString.lowercased()
                envelope.deviceID = deviceID
                envelope.seq = UInt64(nextSeq)
                envelope.wallClockMs = change.modifiedAtMs
                var op = Filesync_SettingOp()
                op.name = change.name
                op.jsonValue = change.jsonValue
                op.modifiedAtMs = change.modifiedAtMs
                envelope.setting = op
                envelopes.append(envelope)
            }
            if let stats {
                nextSeq += 1
                var envelope = Filesync_OpEnvelope()
                envelope.opID = UUID().uuidString.lowercased()
                envelope.deviceID = deviceID
                envelope.seq = UInt64(nextSeq)
                envelope.wallClockMs = now()
                envelope.stats = stats
                envelopes.append(envelope)
            }
        }

        guard !envelopes.isEmpty else {
            return Result(flushedOps: 0, headSeq: ownCursor.headSeq)
        }

        let deviceDir = FileSyncFormat.deviceDirectory(deviceID: deviceID)
        var logPath = "\(deviceDir)/\(FileSyncFormat.logFileName(index: UInt64(ownCursor.currentLogIndex)))"
        var existing = (try? await folder.coordinatedRead(logPath) { url in
            (try? Data(contentsOf: url)) ?? Data()
        }) ?? Data()

        if existing.count > FileSyncFormat.maxLogFileBytes {
            ownCursor.currentLogIndex += 1
            logPath = "\(deviceDir)/\(FileSyncFormat.logFileName(index: UInt64(ownCursor.currentLogIndex)))"
            existing = Data()
        }

        var data = existing
        try OpLogFile.append(envelopes, to: &data)
        try await folder.coordinatedWrite(logPath, data: data)

        for assignment in flushedAssignments {
            dataManager.markFileSyncEntriesFlushed(entryIDs: assignment.entryIDs, seq: assignment.seq)
        }
        ownCursor.headSeq = nextSeq
        dataManager.save(fileSyncCursor: ownCursor)
        UserDefaults.standard.set(digest, forKey: digestKey)
        let cutoff = now() - Int64(7 * 24 * 60 * 60 * 1000)
        dataManager.purgeFlushedFileSyncEntries(olderThanMs: cutoff)

        FileLog.shared.addMessage("FileSync: flushed \(envelopes.count) ops (head seq \(nextSeq))")
        return Result(flushedOps: envelopes.count, headSeq: nextSeq)
    }

    // MARK: Coalescing

    struct EntryGroup {
        var entityType: FileSyncJournalEntry.EntityType
        var opType: FileSyncJournalEntry.OpType
        var entityUuid: String?
        var changedFields: Set<String>
        var fields: String?
        var wallClockMs: Int64
        var entryIDs: [Int64]
        var holdBack = false
    }

    func coalesce(_ entries: [FileSyncJournalEntry]) -> [EntryGroup] {
        var groups: [EntryGroup] = []
        var upsertIndex: [String: Int] = [:]

        for entry in entries {
            guard let entity = entry.entity, let op = entry.op else { continue }
            if op == .upsert, let uuid = entry.entityUuid {
                let key = "\(entity.rawValue):\(uuid)"
                if let index = upsertIndex[key] {
                    groups[index].changedFields.formUnion(entry.changedFieldNames)
                    groups[index].wallClockMs = max(groups[index].wallClockMs, entry.wallClockMs)
                    groups[index].entryIDs.append(entry.id)
                    continue
                }
                upsertIndex[key] = groups.count
            }
            groups.append(EntryGroup(
                entityType: entity,
                opType: op,
                entityUuid: entry.entityUuid,
                changedFields: Set(entry.changedFieldNames),
                fields: entry.fields,
                wallClockMs: entry.wallClockMs,
                entryIDs: [entry.id]))
        }
        return groups
    }

    // MARK: Payload building

    func payload(for group: EntryGroup) -> Filesync_OpEnvelope.OneOf_Payload? {
        switch (group.entityType, group.opType) {
        case (.episode, .upsert):
            guard let uuid = group.entityUuid,
                  let episode = dataManager.findEpisode(uuid: uuid) else { return nil }
            let fields = group.changedFields.isEmpty
                ? ["playedUpTo", "playingStatus", "archived", "starred", "duration"]
                : Array(group.changedFields)
            return .record(RecordConverters.record(from: episode, changedFields: Set(fields)))

        case (.podcast, .upsert):
            guard let uuid = group.entityUuid,
                  let podcast = dataManager.findPodcast(uuid: uuid, includeUnsubscribed: true) else { return nil }
            return .record(RecordConverters.record(from: podcast))

        case (.playlist, .upsert):
            guard let uuid = group.entityUuid,
                  let playlist = dataManager.findPlaylist(uuid: uuid),
                  // Custom playlists are device-local: peers can't represent the
                  // customQuery envelope, so their upserts never leave this device.
                  !playlist.isCustom else { return nil }
            return .record(RecordConverters.record(from: playlist))

        case (.folder, .upsert):
            guard let uuid = group.entityUuid,
                  let folder = dataManager.findFolder(uuid: uuid) else { return nil }
            return .record(RecordConverters.record(from: folder))

        case (.bookmark, .upsert):
            guard let uuid = group.entityUuid,
                  let bookmark = dataManager.bookmarks.bookmark(for: uuid, allowDeleted: true) else { return nil }
            return .record(RecordConverters.record(from: bookmark))

        case (.userEpisode, .upsert):
            guard let uuid = group.entityUuid,
                  let episode = dataManager.findUserEpisode(uuid: uuid),
                  episode.identity == .canonical,
                  let identity = RecordConverters.uploadIdentity(from: episode) else { return nil }
            return .upload(identity)

        case (let entity, .delete):
            guard let uuid = group.entityUuid else { return nil }
            switch entity {
            case .userEpisode:
                var removal = Filesync_UploadTombstone()
                removal.uuid = uuid
                removal.deletedAtMs = group.wallClockMs
                return .uploadRemoved(removal)
            case .podcast, .episode, .playlist, .folder, .bookmark:
                var tombstone = Filesync_RecordTombstone()
                tombstone.uuid = uuid
                tombstone.deletedAtMs = group.wallClockMs
                switch entity {
                case .podcast: tombstone.entityType = .podcast
                case .episode: tombstone.entityType = .episode
                case .playlist: tombstone.entityType = .playlist
                case .folder: tombstone.entityType = .folder
                case .bookmark: tombstone.entityType = .bookmark
                default: return nil
                }
                return .tombstone(tombstone)
            default:
                return nil
            }

        case (.upNext, let op):
            var upNext = Filesync_UpNextOp()
            switch op {
            case .upNextPlayNow: upNext.action = .playNow
            case .upNextPlayNext: upNext.action = .playNext
            case .upNextPlayLast: upNext.action = .playLast
            case .upNextRemove: upNext.action = .remove
            case .upNextReplace:
                upNext.action = .replace
                let uuids = group.fields.flatMap { fields in
                    (try? JSONDecoder().decode([String].self, from: Data(fields.utf8)))
                } ?? []
                upNext.entries = uuids.map { uuid in
                    var entry = Filesync_UpNextEntry()
                    entry.episodeUuid = uuid
                    entry.podcastUuid = podcastUuid(forQueuedEpisode: uuid)
                    return entry
                }
                return .upNext(upNext)
            default:
                return nil
            }
            guard let uuid = group.entityUuid else { return nil }
            var entry = Filesync_UpNextEntry()
            entry.episodeUuid = uuid
            entry.podcastUuid = podcastUuid(forQueuedEpisode: uuid)
            upNext.entry = entry
            return .upNext(upNext)

        default:
            return nil
        }
    }

    private func podcastUuid(forQueuedEpisode uuid: String) -> String {
        dataManager.findBaseEpisode(uuid: uuid)?.parentIdentifier() ?? ""
    }
}
