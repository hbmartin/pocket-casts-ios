import Foundation
import SwiftProtobuf

/// Local alias so the settings sub-merge reads cleanly.
typealias SwiftProtobufTimestamp = SwiftProtobuf.Google_Protobuf_Timestamp

/// Pure last-writer-wins merge of op streams from all devices.
///
/// No I/O and no database access happens here: callers feed in snapshots
/// and decoded op envelopes, and get back a `MergedState` describing the
/// folder's consensus view. `RemoteOpApplier` diffs that against the local
/// database.
///
/// Ordering: ops are folded in `(wallClockMs, deviceID, seq)` order (see
/// `OpStamp`), which makes the merge deterministic for any read order of
/// the underlying files.
///
/// Granularity:
/// - Episodes merge per field, using the `*_modified` timestamps embedded
///   in the record itself (the same LWW scheme the app's database and the
///   original server sync use).
/// - Podcasts merge per field on the envelope timestamp; the nested
///   `PodcastSettings` message sub-merges each setting on its own embedded
///   `modified_at`.
/// - Bookmarks merge title/deleted per field on their embedded `*_modified`
///   values; the immutable creation fields ride along whole.
/// - Playlists and folders merge whole-record (the app always saves them
///   whole, so field-level merging would invent states no device ever had).
/// - Deletion is not a separate lifecycle: it is just another LWW field
///   (`subscribed=false` for podcasts, `is_deleted=true` elsewhere), exactly
///   as server sync models it. `RecordTombstone` ops apply that field; they
///   also let snapshots keep resurrection protection for entities whose
///   full records have been compacted away.
public enum MergeEngine {

    // MARK: State

    public struct MergedRecord<R: Sendable & Equatable>: Sendable, Equatable {
        public var record: R
        /// Proto field number -> the stamp that last wrote it. Key 0 is the
        /// whole-record stamp for types merged wholesale.
        public var stamps: [UInt32: OpStamp]

        public init(record: R, stamps: [UInt32: OpStamp] = [:]) {
            self.record = record
            self.stamps = stamps
        }
    }

    public struct SettingValue: Sendable, Equatable {
        public var jsonValue: String
        public var stamp: OpStamp
    }

    public struct StatsEntry: Sendable, Equatable {
        public var stats: Filesync_StatsCumulative
        public var stamp: OpStamp
    }

    public struct UploadEntry: Sendable, Equatable {
        public var identity: Filesync_UploadIdentity
        public var stamp: OpStamp
    }

    public struct MergedState: Sendable {
        public var podcasts: [String: MergedRecord<Api_SyncUserPodcast>] = [:]
        public var episodes: [String: MergedRecord<Api_SyncUserEpisode>] = [:]
        public var playlists: [String: MergedRecord<Api_SyncUserPlaylist>] = [:]
        public var folders: [String: MergedRecord<Api_SyncUserFolder>] = [:]
        public var bookmarks: [String: MergedRecord<Api_SyncUserBookmark>] = [:]
        /// Compact deletion markers for entities whose records were
        /// compacted out of snapshots. Keyed by entity uuid.
        public var tombstones: [String: Filesync_RecordTombstone] = [:]
        /// Up Next mutations in stamp order, for `UpNextMerger.replay`.
        public var upNextOps: [(stamp: OpStamp, op: Filesync_UpNextOp)] = []
        public var settings: [String: SettingValue] = [:]
        /// Latest cumulative stats per device (counters are monotonic).
        public var statsByDevice: [String: StatsEntry] = [:]
        public var uploads: [String: UploadEntry] = [:]
        public var uploadTombstones: [String: OpStamp] = [:]
        /// Devices explicitly forgotten via the inspector.
        public var forgottenDevices: Set<String> = []

        public init() {}
    }

    // MARK: Entry points

    /// Builds the consensus state from every device's newest snapshot plus
    /// all ops not yet covered by those snapshots.
    public static func merged(snapshots: [Filesync_Snapshot], ops: [Filesync_OpEnvelope]) -> MergedState {
        var state = MergedState()
        for snapshot in snapshots {
            fold(snapshot: snapshot, into: &state)
        }
        fold(ops: ops, into: &state)
        return state
    }

    /// Folds loose ops (sorted internally) into the state.
    public static func fold(ops: [Filesync_OpEnvelope], into state: inout MergedState) {
        for envelope in ops.sorted(by: { $0.stamp < $1.stamp }) {
            apply(envelope, into: &state)
        }
    }

    // MARK: Op application

    static func apply(_ envelope: Filesync_OpEnvelope, into state: inout MergedState) {
        let stamp = envelope.stamp
        switch envelope.payload {
        case .record(let record)?:
            apply(record: record, stamp: stamp, into: &state)
        case .tombstone(let tombstone)?:
            apply(tombstone: tombstone, stamp: stamp, into: &state)
        case .upNext(let op)?:
            state.upNextOps.append((stamp, op))
            state.upNextOps.sort { $0.stamp < $1.stamp }
        case .setting(let op)?:
            let settingStamp = op.modifiedAtMs > 0
                ? OpStamp(wallClockMs: op.modifiedAtMs, deviceID: stamp.deviceID, seq: stamp.seq)
                : stamp
            if let existing = state.settings[op.name], settingStamp <= existing.stamp { break }
            state.settings[op.name] = SettingValue(jsonValue: op.jsonValue, stamp: settingStamp)
        case .stats(let stats)?:
            if let existing = state.statsByDevice[envelope.deviceID], stamp <= existing.stamp { break }
            state.statsByDevice[envelope.deviceID] = StatsEntry(stats: stats, stamp: stamp)
        case .upload(let identity)?:
            if let existing = state.uploads[identity.uuid], stamp <= existing.stamp { break }
            state.uploads[identity.uuid] = UploadEntry(identity: identity, stamp: stamp)
        case .uploadRemoved(let tombstone)?:
            let removalStamp = tombstone.deletedAtMs > 0
                ? OpStamp(wallClockMs: tombstone.deletedAtMs, deviceID: stamp.deviceID, seq: stamp.seq)
                : stamp
            if let existing = state.uploadTombstones[tombstone.uuid], removalStamp <= existing { break }
            state.uploadTombstones[tombstone.uuid] = removalStamp
        case .forget(let forget)?:
            state.forgottenDevices.insert(forget.deviceID)
        case nil:
            break
        }
    }

    static func apply(record: Api_Record, stamp: OpStamp, into state: inout MergedState) {
        switch record.record {
        case .podcast(let podcast)?:
            merge(podcast: podcast, stamp: stamp, into: &state.podcasts)
        case .episode(let episode)?:
            merge(episode: episode, stamp: stamp, into: &state.episodes)
        case .playlist(let playlist)?:
            mergeWhole(playlist, uuid: playlist.uuid, stamp: stamp, into: &state.playlists)
        case .folder(let folder)?:
            mergeWhole(folder, uuid: folder.folderUuid, stamp: stamp, into: &state.folders)
        case .bookmark(let bookmark)?:
            merge(bookmark: bookmark, stamp: stamp, into: &state.bookmarks)
        case .device?, nil:
            // Device stats travel as StatsCumulative ops in this format.
            break
        }
    }

    static func apply(tombstone: Filesync_RecordTombstone, stamp: OpStamp, into state: inout MergedState) {
        let deletionStamp = tombstone.deletedAtMs > 0
            ? OpStamp(wallClockMs: tombstone.deletedAtMs, deviceID: stamp.deviceID, seq: stamp.seq)
            : stamp

        // Keep the compact marker for snapshot writing/GC bookkeeping.
        if let existing = state.tombstones[tombstone.uuid] {
            if tombstone.deletedAtMs > existing.deletedAtMs {
                state.tombstones[tombstone.uuid] = tombstone
            }
        } else {
            state.tombstones[tombstone.uuid] = tombstone
        }

        // And fold the deletion into the record state as the LWW field it is.
        switch tombstone.entityType {
        case .podcast:
            var record = Api_SyncUserPodcast()
            record.uuid = tombstone.uuid
            record.subscribed = .with { $0.value = false }
            record.isDeleted = .with { $0.value = true }
            merge(podcast: record, stamp: deletionStamp, into: &state.podcasts)
        case .episode:
            var record = Api_SyncUserEpisode()
            record.uuid = tombstone.uuid
            record.isDeleted = .with { $0.value = true }
            record.isDeletedModified = .with { $0.value = deletionStamp.wallClockMs }
            merge(episode: record, stamp: deletionStamp, into: &state.episodes)
        case .playlist:
            var record = Api_SyncUserPlaylist()
            record.uuid = tombstone.uuid
            record.isDeleted = .with { $0.value = true }
            mergeWhole(record, uuid: tombstone.uuid, stamp: deletionStamp, into: &state.playlists)
        case .folder:
            var record = Api_SyncUserFolder()
            record.folderUuid = tombstone.uuid
            record.isDeleted = true
            mergeWhole(record, uuid: tombstone.uuid, stamp: deletionStamp, into: &state.folders)
        case .bookmark:
            var record = Api_SyncUserBookmark()
            record.bookmarkUuid = tombstone.uuid
            record.isDeleted = .with { $0.value = true }
            record.isDeletedModified = .with { $0.value = deletionStamp.wallClockMs }
            merge(bookmark: record, stamp: deletionStamp, into: &state.bookmarks)
        case .userEpisode:
            if let existing = state.uploadTombstones[tombstone.uuid], deletionStamp <= existing { break }
            state.uploadTombstones[tombstone.uuid] = deletionStamp
        case .unknown, .UNRECOGNIZED:
            break
        }
    }

    // MARK: Whole-record merge (playlists, folders)

    static func mergeWhole<R: Sendable & Equatable>(
        _ incoming: R, uuid: String, stamp: OpStamp, into records: inout [String: MergedRecord<R>]
    ) {
        guard !uuid.isEmpty else { return }
        if let existing = records[uuid], let existingStamp = existing.stamps[0], stamp <= existingStamp {
            return
        }
        records[uuid] = MergedRecord(record: incoming, stamps: [0: stamp])
    }

    // MARK: Podcast merge (per field, envelope-stamped; settings sub-merged)

    static func merge(
        podcast incoming: Api_SyncUserPodcast, stamp: OpStamp,
        into records: inout [String: MergedRecord<Api_SyncUserPodcast>]
    ) {
        guard !incoming.uuid.isEmpty else { return }
        var merged = records[incoming.uuid] ?? MergedRecord(record: {
            var record = Api_SyncUserPodcast()
            record.uuid = incoming.uuid
            return record
        }())

        func take(_ fieldNumber: UInt32, _ isPresent: Bool, _ copy: (inout Api_SyncUserPodcast) -> Void) {
            guard isPresent else { return }
            if let existing = merged.stamps[fieldNumber], stamp <= existing { return }
            copy(&merged.record)
            merged.stamps[fieldNumber] = stamp
        }

        take(2, incoming.hasIsDeleted) { $0.isDeleted = incoming.isDeleted }
        take(3, incoming.hasSubscribed) { $0.subscribed = incoming.subscribed }
        take(4, incoming.hasAutoStartFrom) { $0.autoStartFrom = incoming.autoStartFrom }
        take(5, incoming.hasEpisodesSortOrder) { $0.episodesSortOrder = incoming.episodesSortOrder }
        take(6, incoming.hasAutoSkipLast) { $0.autoSkipLast = incoming.autoSkipLast }
        take(7, incoming.hasFolderUuid) { $0.folderUuid = incoming.folderUuid }
        take(8, incoming.hasSortPosition) { $0.sortPosition = incoming.sortPosition }
        take(9, incoming.hasDateAdded) { $0.dateAdded = incoming.dateAdded }
        take(1000, !incoming.feedURL.isEmpty) { $0.feedURL = incoming.feedURL }

        if incoming.hasSettings {
            var settings = merged.record.hasSettings ? merged.record.settings : Api_PodcastSettings()
            mergeSettings(into: &settings, from: incoming.settings)
            merged.record.settings = settings
            // The stamp map entry marks that we have ever seen settings; the
            // real granularity lives in each setting's modified_at.
            merged.stamps[10] = max(merged.stamps[10] ?? stamp, stamp)
        }

        records[incoming.uuid] = merged
    }

    /// Per-setting LWW on the embedded `modified_at` timestamps.
    static func mergeSettings(into target: inout Api_PodcastSettings, from incoming: Api_PodcastSettings) {
        func newer(_ lhs: SwiftProtobufTimestamp?, than rhs: SwiftProtobufTimestamp?) -> Bool {
            guard let lhs else { return false }
            guard let rhs else { return true }
            return (lhs.seconds, lhs.nanos) > (rhs.seconds, rhs.nanos)
        }
        func mergeBool(_ has: Bool, _ get: (Api_PodcastSettings) -> Api_BoolSetting,
                       _ hasTarget: Bool, _ set: (inout Api_PodcastSettings, Api_BoolSetting) -> Void) {
            guard has else { return }
            let incomingSetting = get(incoming)
            let targetModified = hasTarget ? (get(target).hasModifiedAt ? get(target).modifiedAt : nil) : nil
            let incomingModified = incomingSetting.hasModifiedAt ? incomingSetting.modifiedAt : nil
            if !hasTarget || newer(incomingModified, than: targetModified) {
                set(&target, incomingSetting)
            }
        }
        func mergeInt32(_ has: Bool, _ get: (Api_PodcastSettings) -> Api_Int32Setting,
                        _ hasTarget: Bool, _ set: (inout Api_PodcastSettings, Api_Int32Setting) -> Void) {
            guard has else { return }
            let incomingSetting = get(incoming)
            let targetModified = hasTarget ? (get(target).hasModifiedAt ? get(target).modifiedAt : nil) : nil
            let incomingModified = incomingSetting.hasModifiedAt ? incomingSetting.modifiedAt : nil
            if !hasTarget || newer(incomingModified, than: targetModified) {
                set(&target, incomingSetting)
            }
        }
        func mergeDouble(_ has: Bool, _ get: (Api_PodcastSettings) -> Api_DoubleSetting,
                         _ hasTarget: Bool, _ set: (inout Api_PodcastSettings, Api_DoubleSetting) -> Void) {
            guard has else { return }
            let incomingSetting = get(incoming)
            let targetModified = hasTarget ? (get(target).hasModifiedAt ? get(target).modifiedAt : nil) : nil
            let incomingModified = incomingSetting.hasModifiedAt ? incomingSetting.modifiedAt : nil
            if !hasTarget || newer(incomingModified, than: targetModified) {
                set(&target, incomingSetting)
            }
        }

        mergeBool(incoming.hasNotification, { $0.notification }, target.hasNotification) { $0.notification = $1 }
        mergeBool(incoming.hasAddToUpNext, { $0.addToUpNext }, target.hasAddToUpNext) { $0.addToUpNext = $1 }
        mergeInt32(incoming.hasAddToUpNextPosition, { $0.addToUpNextPosition }, target.hasAddToUpNextPosition) { $0.addToUpNextPosition = $1 }
        mergeBool(incoming.hasAutoArchive, { $0.autoArchive }, target.hasAutoArchive) { $0.autoArchive = $1 }
        mergeBool(incoming.hasPlaybackEffects, { $0.playbackEffects }, target.hasPlaybackEffects) { $0.playbackEffects = $1 }
        mergeDouble(incoming.hasPlaybackSpeed, { $0.playbackSpeed }, target.hasPlaybackSpeed) { $0.playbackSpeed = $1 }
        mergeInt32(incoming.hasTrimSilence, { $0.trimSilence }, target.hasTrimSilence) { $0.trimSilence = $1 }
        mergeBool(incoming.hasVolumeBoost, { $0.volumeBoost }, target.hasVolumeBoost) { $0.volumeBoost = $1 }
        mergeInt32(incoming.hasAutoStartFrom, { $0.autoStartFrom }, target.hasAutoStartFrom) { $0.autoStartFrom = $1 }
        mergeInt32(incoming.hasAutoSkipLast, { $0.autoSkipLast }, target.hasAutoSkipLast) { $0.autoSkipLast = $1 }
        mergeInt32(incoming.hasEpisodesSortOrder, { $0.episodesSortOrder }, target.hasEpisodesSortOrder) { $0.episodesSortOrder = $1 }
        mergeInt32(incoming.hasAutoArchivePlayed, { $0.autoArchivePlayed }, target.hasAutoArchivePlayed) { $0.autoArchivePlayed = $1 }
        mergeInt32(incoming.hasAutoArchiveInactive, { $0.autoArchiveInactive }, target.hasAutoArchiveInactive) { $0.autoArchiveInactive = $1 }
        mergeInt32(incoming.hasAutoArchiveEpisodeLimit, { $0.autoArchiveEpisodeLimit }, target.hasAutoArchiveEpisodeLimit) { $0.autoArchiveEpisodeLimit = $1 }
        mergeInt32(incoming.hasEpisodeGrouping, { $0.episodeGrouping }, target.hasEpisodeGrouping) { $0.episodeGrouping = $1 }
        mergeBool(incoming.hasShowArchived, { $0.showArchived }, target.hasShowArchived) { $0.showArchived = $1 }
    }

    // MARK: Episode merge (per field, embedded *_modified timestamps)

    static func merge(
        episode incoming: Api_SyncUserEpisode, stamp: OpStamp,
        into records: inout [String: MergedRecord<Api_SyncUserEpisode>]
    ) {
        guard !incoming.uuid.isEmpty else { return }
        var merged = records[incoming.uuid] ?? MergedRecord(record: {
            var record = Api_SyncUserEpisode()
            record.uuid = incoming.uuid
            return record
        }())
        if merged.record.podcastUuid.isEmpty, !incoming.podcastUuid.isEmpty {
            merged.record.podcastUuid = incoming.podcastUuid
        }

        func take(_ fieldNumber: UInt32, _ isPresent: Bool, embeddedMs: Int64,
                  _ copy: (inout Api_SyncUserEpisode) -> Void) {
            guard isPresent else { return }
            let fieldStamp = embeddedMs > 0
                ? OpStamp(wallClockMs: embeddedMs, deviceID: stamp.deviceID, seq: stamp.seq)
                : stamp
            if let existing = merged.stamps[fieldNumber], fieldStamp <= existing { return }
            copy(&merged.record)
            merged.stamps[fieldNumber] = fieldStamp
        }

        take(3, incoming.hasIsDeleted, embeddedMs: incoming.isDeletedModified.value) {
            $0.isDeleted = incoming.isDeleted
            $0.isDeletedModified = incoming.isDeletedModified
        }
        take(5, incoming.hasDuration, embeddedMs: incoming.durationModified.value) {
            $0.duration = incoming.duration
            $0.durationModified = incoming.durationModified
        }
        take(7, incoming.hasPlayingStatus, embeddedMs: incoming.playingStatusModified.value) {
            $0.playingStatus = incoming.playingStatus
            $0.playingStatusModified = incoming.playingStatusModified
        }
        take(9, incoming.hasPlayedUpTo, embeddedMs: incoming.playedUpToModified.value) {
            $0.playedUpTo = incoming.playedUpTo
            $0.playedUpToModified = incoming.playedUpToModified
        }
        take(11, incoming.hasStarred, embeddedMs: incoming.starredModified.value) {
            $0.starred = incoming.starred
            $0.starredModified = incoming.starredModified
        }
        take(13, incoming.deselectedChaptersModified.value > 0, embeddedMs: incoming.deselectedChaptersModified.value) {
            $0.deselectedChapters = incoming.deselectedChapters
            $0.deselectedChaptersModified = incoming.deselectedChaptersModified
        }

        records[incoming.uuid] = merged
    }

    // MARK: Bookmark merge (title/deleted per field, creation fields whole)

    static func merge(
        bookmark incoming: Api_SyncUserBookmark, stamp: OpStamp,
        into records: inout [String: MergedRecord<Api_SyncUserBookmark>]
    ) {
        guard !incoming.bookmarkUuid.isEmpty else { return }
        var merged = records[incoming.bookmarkUuid] ?? MergedRecord(record: {
            var record = Api_SyncUserBookmark()
            record.bookmarkUuid = incoming.bookmarkUuid
            return record
        }())

        // Creation-time fields: immutable, first writer fills them in.
        if merged.record.podcastUuid.isEmpty, !incoming.podcastUuid.isEmpty {
            merged.record.podcastUuid = incoming.podcastUuid
        }
        if merged.record.episodeUuid.isEmpty, !incoming.episodeUuid.isEmpty {
            merged.record.episodeUuid = incoming.episodeUuid
        }
        if !merged.record.hasCreatedAt, incoming.hasCreatedAt {
            merged.record.createdAt = incoming.createdAt
        }
        if !merged.record.hasTime, incoming.hasTime {
            merged.record.time = incoming.time
        }

        func take(_ fieldNumber: UInt32, _ isPresent: Bool, embeddedMs: Int64,
                  _ copy: (inout Api_SyncUserBookmark) -> Void) {
            guard isPresent else { return }
            let fieldStamp = embeddedMs > 0
                ? OpStamp(wallClockMs: embeddedMs, deviceID: stamp.deviceID, seq: stamp.seq)
                : stamp
            if let existing = merged.stamps[fieldNumber], fieldStamp <= existing { return }
            copy(&merged.record)
            merged.stamps[fieldNumber] = fieldStamp
        }

        take(6, incoming.hasTitle, embeddedMs: incoming.titleModified.value) {
            $0.title = incoming.title
            $0.titleModified = incoming.titleModified
        }
        take(8, incoming.hasIsDeleted, embeddedMs: incoming.isDeletedModified.value) {
            $0.isDeleted = incoming.isDeleted
            $0.isDeletedModified = incoming.isDeletedModified
        }

        records[incoming.bookmarkUuid] = merged
    }

    // MARK: Snapshot folding

    static func fold(snapshot: Filesync_Snapshot, into state: inout MergedState) {
        for snapshotRecord in snapshot.records {
            guard snapshotRecord.hasRecord else { continue }
            let stamps = snapshotRecord.fieldModifiedMs
            // Reconstruct field stamps from the persisted timestamps. The
            // record is replayed as a single op whose per-field ordering is
            // restored via the stamp map, using each field's own timestamp.
            apply(record: snapshotRecord.record, stampsByField: stamps,
                  fallback: OpStamp(wallClockMs: snapshot.createdAtMs), into: &state)
        }
        for tombstone in snapshot.tombstones {
            apply(tombstone: tombstone, stamp: OpStamp(wallClockMs: tombstone.deletedAtMs), into: &state)
        }
        if snapshot.hasUpNext {
            var replace = Filesync_UpNextOp()
            replace.action = .replace
            replace.entries = snapshot.upNext.entries
            state.upNextOps.append((OpStamp(wallClockMs: snapshot.upNext.modifiedAtMs), replace))
            state.upNextOps.sort { $0.stamp < $1.stamp }
        }
        for setting in snapshot.settings {
            let stamp = OpStamp(wallClockMs: setting.modifiedAtMs)
            if let existing = state.settings[setting.name], stamp <= existing.stamp { continue }
            state.settings[setting.name] = SettingValue(jsonValue: setting.jsonValue, stamp: stamp)
        }
        if snapshot.hasStats {
            let stamp = OpStamp(wallClockMs: snapshot.createdAtMs)
            if state.statsByDevice[snapshot.deviceID].map({ stamp > $0.stamp }) ?? true {
                state.statsByDevice[snapshot.deviceID] = StatsEntry(stats: snapshot.stats, stamp: stamp)
            }
        }
        for upload in snapshot.uploads {
            let stamp = OpStamp(wallClockMs: upload.mtimeMs > 0 ? upload.mtimeMs : snapshot.createdAtMs)
            if let existing = state.uploads[upload.uuid], stamp <= existing.stamp { continue }
            state.uploads[upload.uuid] = UploadEntry(identity: upload, stamp: stamp)
        }
        for tombstone in snapshot.uploadTombstones {
            let stamp = OpStamp(wallClockMs: tombstone.deletedAtMs)
            if let existing = state.uploadTombstones[tombstone.uuid], stamp <= existing { continue }
            state.uploadTombstones[tombstone.uuid] = stamp
        }
    }

    /// Applies a snapshot record whose per-field ordering comes from a
    /// persisted stamp map rather than a live envelope.
    static func apply(
        record: Api_Record, stampsByField: [UInt32: Int64], fallback: OpStamp,
        into state: inout MergedState
    ) {
        func stampFor(_ field: UInt32) -> OpStamp {
            stampsByField[field].map { OpStamp(wallClockMs: $0) } ?? fallback
        }
        switch record.record {
        case .podcast(let podcast)?:
            // Split into one virtual op per field so each field carries its
            // own snapshot stamp.
            for field in podcastFieldNumbers(present: podcast) {
                var single = Api_SyncUserPodcast()
                single.uuid = podcast.uuid
                copyPodcastField(field, from: podcast, into: &single)
                merge(podcast: single, stamp: stampFor(field), into: &state.podcasts)
            }
        case .episode(let episode)?:
            // Episodes carry their own *_modified stamps inline.
            merge(episode: episode, stamp: fallback, into: &state.episodes)
        case .playlist(let playlist)?:
            mergeWhole(playlist, uuid: playlist.uuid, stamp: stampFor(0), into: &state.playlists)
        case .folder(let folder)?:
            mergeWhole(folder, uuid: folder.folderUuid, stamp: stampFor(0), into: &state.folders)
        case .bookmark(let bookmark)?:
            merge(bookmark: bookmark, stamp: fallback, into: &state.bookmarks)
        case .device?, nil:
            break
        }
    }

    static func podcastFieldNumbers(present podcast: Api_SyncUserPodcast) -> [UInt32] {
        var fields: [UInt32] = []
        if podcast.hasIsDeleted { fields.append(2) }
        if podcast.hasSubscribed { fields.append(3) }
        if podcast.hasAutoStartFrom { fields.append(4) }
        if podcast.hasEpisodesSortOrder { fields.append(5) }
        if podcast.hasAutoSkipLast { fields.append(6) }
        if podcast.hasFolderUuid { fields.append(7) }
        if podcast.hasSortPosition { fields.append(8) }
        if podcast.hasDateAdded { fields.append(9) }
        if podcast.hasSettings { fields.append(10) }
        if !podcast.feedURL.isEmpty { fields.append(1000) }
        return fields
    }

    static func copyPodcastField(_ field: UInt32, from source: Api_SyncUserPodcast, into target: inout Api_SyncUserPodcast) {
        switch field {
        case 2: target.isDeleted = source.isDeleted
        case 3: target.subscribed = source.subscribed
        case 4: target.autoStartFrom = source.autoStartFrom
        case 5: target.episodesSortOrder = source.episodesSortOrder
        case 6: target.autoSkipLast = source.autoSkipLast
        case 7: target.folderUuid = source.folderUuid
        case 8: target.sortPosition = source.sortPosition
        case 9: target.dateAdded = source.dateAdded
        case 10: target.settings = source.settings
        case 1000: target.feedURL = source.feedURL
        default: break
        }
    }
}
