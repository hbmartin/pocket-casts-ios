import XCTest
@testable import PocketCastsFileSync

final class MergeEngineTests: XCTestCase {

    // MARK: Helpers

    private func episodeOp(
        uuid: String = "ep-1", device: String, seq: UInt64, wallClockMs: Int64,
        playedUpTo: Int64? = nil, playedUpToModified: Int64? = nil,
        starred: Bool? = nil, starredModified: Int64? = nil,
        archived: Bool? = nil, archivedModified: Int64? = nil
    ) -> Filesync_OpEnvelope {
        var episode = Api_SyncUserEpisode()
        episode.uuid = uuid
        episode.podcastUuid = "pod-1"
        if let playedUpTo {
            episode.playedUpTo = .with { $0.value = playedUpTo }
            episode.playedUpToModified = .with { $0.value = playedUpToModified ?? wallClockMs }
        }
        if let starred {
            episode.starred = .with { $0.value = starred }
            episode.starredModified = .with { $0.value = starredModified ?? wallClockMs }
        }
        if let archived {
            episode.isDeleted = .with { $0.value = archived }
            episode.isDeletedModified = .with { $0.value = archivedModified ?? wallClockMs }
        }
        var record = Api_Record()
        record.episode = episode
        var envelope = Filesync_OpEnvelope()
        envelope.opID = "op-\(device)-\(seq)"
        envelope.deviceID = device
        envelope.seq = seq
        envelope.wallClockMs = wallClockMs
        envelope.record = record
        return envelope
    }

    private func podcastOp(
        uuid: String = "pod-1", device: String, seq: UInt64, wallClockMs: Int64,
        subscribed: Bool? = nil, sortPosition: Int32? = nil, folderUuid: String? = nil,
        feedURL: String? = nil
    ) -> Filesync_OpEnvelope {
        var podcast = Api_SyncUserPodcast()
        podcast.uuid = uuid
        if let subscribed { podcast.subscribed = .with { $0.value = subscribed } }
        if let sortPosition { podcast.sortPosition = .with { $0.value = sortPosition } }
        if let folderUuid { podcast.folderUuid = .with { $0.value = folderUuid } }
        if let feedURL { podcast.feedURL = feedURL }
        var record = Api_Record()
        record.podcast = podcast
        var envelope = Filesync_OpEnvelope()
        envelope.opID = "op-\(device)-\(seq)"
        envelope.deviceID = device
        envelope.seq = seq
        envelope.wallClockMs = wallClockMs
        envelope.record = record
        return envelope
    }

    // MARK: Per-field LWW

    func testNewerTimestampWinsPerField() {
        let ops = [
            episodeOp(device: "a", seq: 1, wallClockMs: 1000, playedUpTo: 100, starred: true),
            episodeOp(device: "b", seq: 1, wallClockMs: 2000, playedUpTo: 200),
        ]
        let state = MergeEngine.merged(snapshots: [], ops: ops)

        let episode = state.episodes["ep-1"]!.record
        XCTAssertEqual(episode.playedUpTo.value, 200, "newer position wins")
        XCTAssertTrue(episode.starred.value, "untouched field keeps the older device's value")
    }

    func testOlderOpNeverOverwritesNewerField() {
        let ops = [
            episodeOp(device: "a", seq: 2, wallClockMs: 5000, playedUpTo: 500),
            episodeOp(device: "b", seq: 1, wallClockMs: 1000, playedUpTo: 100),
        ]
        let state = MergeEngine.merged(snapshots: [], ops: ops)
        XCTAssertEqual(state.episodes["ep-1"]!.record.playedUpTo.value, 500)
    }

    func testEmbeddedModifiedTimestampBeatsEnvelopeOrder() {
        // Device b's op is written later (envelope ts 9000) but carries an
        // older user action (embedded modified 1000) — the embedded stamp is
        // authoritative, matching the app's *_modified LWW scheme.
        let ops = [
            episodeOp(device: "a", seq: 1, wallClockMs: 2000, playedUpTo: 222, playedUpToModified: 2000),
            episodeOp(device: "b", seq: 1, wallClockMs: 9000, playedUpTo: 111, playedUpToModified: 1000),
        ]
        let state = MergeEngine.merged(snapshots: [], ops: ops)
        XCTAssertEqual(state.episodes["ep-1"]!.record.playedUpTo.value, 222)
    }

    func testDeviceIDBreaksExactTimestampTies() {
        let ops = [
            episodeOp(device: "b", seq: 1, wallClockMs: 1000, playedUpTo: 200, playedUpToModified: 1000),
            episodeOp(device: "a", seq: 1, wallClockMs: 1000, playedUpTo: 100, playedUpToModified: 1000),
        ]
        let state = MergeEngine.merged(snapshots: [], ops: ops)
        XCTAssertEqual(state.episodes["ep-1"]!.record.playedUpTo.value, 200,
                       "on equal timestamps the lexically larger device id wins, deterministically")
    }

    // MARK: Determinism

    func testMergeIsOrderIndependent() {
        let ops = [
            episodeOp(device: "a", seq: 1, wallClockMs: 1000, playedUpTo: 100),
            episodeOp(device: "b", seq: 1, wallClockMs: 2000, starred: true),
            episodeOp(device: "a", seq: 2, wallClockMs: 3000, playedUpTo: 300),
            episodeOp(device: "c", seq: 1, wallClockMs: 1500, archived: true),
            podcastOp(device: "b", seq: 2, wallClockMs: 1200, subscribed: true),
            podcastOp(device: "c", seq: 2, wallClockMs: 2200, sortPosition: 7),
        ]
        let forward = MergeEngine.merged(snapshots: [], ops: ops)
        let reversed = MergeEngine.merged(snapshots: [], ops: ops.reversed())
        let shuffled = MergeEngine.merged(snapshots: [], ops: ops.shuffled())

        for state in [reversed, shuffled] {
            XCTAssertEqual(state.episodes["ep-1"]?.record, forward.episodes["ep-1"]?.record)
            XCTAssertEqual(state.podcasts["pod-1"]?.record, forward.podcasts["pod-1"]?.record)
        }
    }

    func testMergeIsIdempotent() {
        let ops = [
            episodeOp(device: "a", seq: 1, wallClockMs: 1000, playedUpTo: 100, starred: true),
            podcastOp(device: "b", seq: 1, wallClockMs: 2000, subscribed: true, feedURL: "https://feed"),
        ]
        let once = MergeEngine.merged(snapshots: [], ops: ops)
        let twice = MergeEngine.merged(snapshots: [], ops: ops + ops)

        XCTAssertEqual(once.episodes["ep-1"]?.record, twice.episodes["ep-1"]?.record)
        XCTAssertEqual(once.podcasts["pod-1"]?.record, twice.podcasts["pod-1"]?.record)
    }

    // MARK: Podcasts

    func testPodcastFieldsMergeIndependently() {
        let ops = [
            podcastOp(device: "a", seq: 1, wallClockMs: 1000, subscribed: true, sortPosition: 1),
            podcastOp(device: "b", seq: 1, wallClockMs: 2000, sortPosition: 5),
            podcastOp(device: "a", seq: 2, wallClockMs: 3000, folderUuid: "folder-9"),
        ]
        let state = MergeEngine.merged(snapshots: [], ops: ops)
        let podcast = state.podcasts["pod-1"]!.record

        XCTAssertTrue(podcast.subscribed.value)
        XCTAssertEqual(podcast.sortPosition.value, 5)
        XCTAssertEqual(podcast.folderUuid.value, "folder-9")
    }

    func testFeedURLPropagates() {
        let ops = [podcastOp(device: "a", seq: 1, wallClockMs: 1000, subscribed: true,
                             feedURL: "https://example.com/feed.rss")]
        let state = MergeEngine.merged(snapshots: [], ops: ops)
        XCTAssertEqual(state.podcasts["pod-1"]!.record.feedURL, "https://example.com/feed.rss")
    }

    // MARK: Bookmarks

    private func bookmarkOp(
        uuid: String = "bm-1", device: String, seq: UInt64, wallClockMs: Int64,
        title: String? = nil, titleModified: Int64? = nil,
        excerpt: String? = nil, endTime: Double? = nil,
        trimModified: Int64? = nil,
        tags: [String]? = nil, tagsModified: Int64? = nil
    ) -> Filesync_OpEnvelope {
        var bookmark = Api_SyncUserBookmark()
        bookmark.bookmarkUuid = uuid
        bookmark.episodeUuid = "ep-1"
        if let title {
            bookmark.title = .with { $0.value = title }
            bookmark.titleModified = .with { $0.value = titleModified ?? wallClockMs }
        }
        if let excerpt { bookmark.excerpt = .with { $0.value = excerpt } }
        if let endTime { bookmark.endTime = .with { $0.value = endTime } }
        if let trimModified { bookmark.trimModified = .with { $0.value = trimModified } }
        if let tags { bookmark.tags = tags }
        if let tagsModified { bookmark.tagsModified = .with { $0.value = tagsModified } }
        var record = Api_Record()
        record.bookmark = bookmark
        var envelope = Filesync_OpEnvelope()
        envelope.opID = "op-\(device)-\(seq)"
        envelope.deviceID = device
        envelope.seq = seq
        envelope.wallClockMs = wallClockMs
        envelope.record = record
        return envelope
    }

    func testBookmarkEnrichmentFillsInFromLaterOp() {
        let ops = [
            bookmarkOp(device: "a", seq: 1, wallClockMs: 1000, title: "Bookmark"),
            bookmarkOp(device: "a", seq: 2, wallClockMs: 2000, excerpt: "The quote", endTime: 42.5),
        ]
        let state = MergeEngine.merged(snapshots: [], ops: ops)
        let bookmark = state.bookmarks["bm-1"]!.record

        XCTAssertEqual(bookmark.title.value, "Bookmark")
        XCTAssertEqual(bookmark.excerpt.value, "The quote")
        XCTAssertEqual(bookmark.endTime.value, 42.5)
    }

    func testBookmarkEnrichmentIsLastWriterWins() {
        let ops = [
            bookmarkOp(device: "a", seq: 1, wallClockMs: 1000, excerpt: "first", endTime: 10),
            bookmarkOp(device: "b", seq: 1, wallClockMs: 2000, excerpt: "second", endTime: 20),
        ]
        let state = MergeEngine.merged(snapshots: [], ops: ops)
        let bookmark = state.bookmarks["bm-1"]!.record

        XCTAssertEqual(bookmark.excerpt.value, "second",
                       "conflicting enrichments resolve by op stamp, like title")
        XCTAssertEqual(bookmark.endTime.value, 20)
    }

    func testBookmarkEnrichmentConflictIsOrderIndependent() {
        // Two devices enrich the same bookmark with different excerpts; every
        // replay order must converge on the same winner or devices diverge
        // permanently after compaction.
        let older = bookmarkOp(device: "a", seq: 1, wallClockMs: 1000, excerpt: "first", endTime: 10)
        let newer = bookmarkOp(device: "b", seq: 1, wallClockMs: 2000, excerpt: "second", endTime: 20)

        let forward = MergeEngine.merged(snapshots: [], ops: [older, newer]).bookmarks["bm-1"]!.record
        let reversed = MergeEngine.merged(snapshots: [], ops: [newer, older]).bookmarks["bm-1"]!.record

        XCTAssertEqual(forward.excerpt.value, reversed.excerpt.value)
        XCTAssertEqual(forward.endTime.value, reversed.endTime.value)
        XCTAssertEqual(forward.excerpt.value, "second")
    }

    // MARK: Trim & tags (ADR-0016)

    func testTrimBeatsMachineEnrichmentInEveryReplayOrder() {
        // The machine op carries a LATER op stamp than the trim — the trim must
        // still win, in both orders, or devices diverge after compaction.
        let trim = bookmarkOp(device: "a", seq: 1, wallClockMs: 1000,
                              excerpt: "user trim", endTime: 55, trimModified: 1000)
        let machine = bookmarkOp(device: "b", seq: 1, wallClockMs: 2000,
                                 excerpt: "machine", endTime: 60)

        for ops in [[trim, machine], [machine, trim]] {
            let bookmark = MergeEngine.merged(snapshots: [], ops: ops).bookmarks["bm-1"]!.record
            XCTAssertEqual(bookmark.excerpt.value, "user trim")
            XCTAssertEqual(bookmark.endTime.value, 55)
            XCTAssertEqual(bookmark.trimModified.value, 1000)
        }
    }

    func testConflictingTrimsResolveByTrimStampNotOpOrder() {
        let older = bookmarkOp(device: "a", seq: 5, wallClockMs: 9000,
                               excerpt: "older trim", endTime: 40, trimModified: 1000)
        let newer = bookmarkOp(device: "b", seq: 1, wallClockMs: 1500,
                               excerpt: "newer trim", endTime: 50, trimModified: 2000)

        for ops in [[older, newer], [newer, older]] {
            let bookmark = MergeEngine.merged(snapshots: [], ops: ops).bookmarks["bm-1"]!.record
            XCTAssertEqual(bookmark.excerpt.value, "newer trim",
                           "trim-vs-trim is LWW by the trim stamp, not by op arrival")
            XCTAssertEqual(bookmark.trimModified.value, 2000)
        }
    }

    func testTagsMergeAsWholeSetByStamp() {
        let first = bookmarkOp(device: "a", seq: 1, wallClockMs: 1000,
                               tags: ["ai", "investing"], tagsModified: 1000)
        let second = bookmarkOp(device: "b", seq: 1, wallClockMs: 500,
                                tags: ["climate"], tagsModified: 2000)

        for ops in [[first, second], [second, first]] {
            let bookmark = MergeEngine.merged(snapshots: [], ops: ops).bookmarks["bm-1"]!.record
            XCTAssertEqual(bookmark.tags, ["climate"], "whole-set LWW by tagsModified")
            XCTAssertEqual(bookmark.tagsModified.value, 2000)
        }
    }

    func testUnstampedTagsNeverTouchTheSet() {
        let stamped = bookmarkOp(device: "a", seq: 1, wallClockMs: 1000,
                                 tags: ["keep"], tagsModified: 1000)
        var unstamped = bookmarkOp(device: "b", seq: 1, wallClockMs: 2000, title: "rename")
        unstamped.record.bookmark.tags = ["ignored"]

        let bookmark = MergeEngine.merged(snapshots: [], ops: [stamped, unstamped]).bookmarks["bm-1"]!.record
        XCTAssertEqual(bookmark.tags, ["keep"])
    }

    func testSnapshotFoldReplaysTrimAndTagsIdentically() {
        // Live-replay result must equal fold(snapshot(live-replay)) — the
        // compaction invariant that keeps devices convergent. The snapshot
        // record is built the way SnapshotWriter.buildSnapshot does: merged
        // record + fieldModifiedMs from the merged stamps.
        let ops = [
            bookmarkOp(device: "a", seq: 1, wallClockMs: 1000, title: "Bookmark"),
            bookmarkOp(device: "b", seq: 1, wallClockMs: 2000,
                       excerpt: "trimmed", endTime: 44, trimModified: 2000),
            bookmarkOp(device: "a", seq: 2, wallClockMs: 3000,
                       tags: ["ai"], tagsModified: 3000),
        ]
        let live = MergeEngine.merged(snapshots: [], ops: ops)
        let liveMerged = live.bookmarks["bm-1"]!

        var record = Api_Record()
        record.bookmark = liveMerged.record
        var snapshotRecord = Filesync_SnapshotRecord()
        snapshotRecord.record = record
        snapshotRecord.fieldModifiedMs = liveMerged.stamps.mapValues(\.wallClockMs)
        var snapshot = Filesync_Snapshot()
        snapshot.deviceID = "a"
        snapshot.records = [snapshotRecord]

        let folded = MergeEngine.merged(snapshots: [snapshot], ops: [])
        let bookmark = folded.bookmarks["bm-1"]!.record

        XCTAssertEqual(bookmark.excerpt.value, liveMerged.record.excerpt.value)
        XCTAssertEqual(bookmark.endTime.value, liveMerged.record.endTime.value)
        XCTAssertEqual(bookmark.trimModified.value, liveMerged.record.trimModified.value)
        XCTAssertEqual(bookmark.tags, liveMerged.record.tags)
        XCTAssertEqual(bookmark.tagsModified.value, liveMerged.record.tagsModified.value)

        // And a machine op replayed AFTER the trimmed snapshot still loses.
        let lateMachine = bookmarkOp(device: "c", seq: 1, wallClockMs: 9000,
                                     excerpt: "late machine", endTime: 99)
        let refolded = MergeEngine.merged(snapshots: [snapshot], ops: [lateMachine])
        XCTAssertEqual(refolded.bookmarks["bm-1"]!.record.excerpt.value, "trimmed")
    }

    // MARK: Tombstones and resurrection

    func testTombstoneDeletesEntity() {
        var tombstone = Filesync_RecordTombstone()
        tombstone.entityType = .playlist
        tombstone.uuid = "pl-1"
        tombstone.deletedAtMs = 5000
        var tombstoneEnvelope = Filesync_OpEnvelope()
        tombstoneEnvelope.deviceID = "b"
        tombstoneEnvelope.seq = 1
        tombstoneEnvelope.wallClockMs = 5000
        tombstoneEnvelope.tombstone = tombstone

        var playlist = Api_SyncUserPlaylist()
        playlist.uuid = "pl-1"
        playlist.title = .with { $0.value = "News" }
        var record = Api_Record()
        record.playlist = playlist
        var createEnvelope = Filesync_OpEnvelope()
        createEnvelope.deviceID = "a"
        createEnvelope.seq = 1
        createEnvelope.wallClockMs = 1000
        createEnvelope.record = record

        let state = MergeEngine.merged(snapshots: [], ops: [createEnvelope, tombstoneEnvelope])
        XCTAssertTrue(state.playlists["pl-1"]!.record.isDeleted.value,
                      "the newer tombstone must win over the older create")
    }

    func testLaterEditResurrectsDeletedPlaylist() {
        var tombstone = Filesync_RecordTombstone()
        tombstone.entityType = .playlist
        tombstone.uuid = "pl-1"
        tombstone.deletedAtMs = 1000
        var tombstoneEnvelope = Filesync_OpEnvelope()
        tombstoneEnvelope.deviceID = "a"
        tombstoneEnvelope.seq = 1
        tombstoneEnvelope.wallClockMs = 1000
        tombstoneEnvelope.tombstone = tombstone

        var playlist = Api_SyncUserPlaylist()
        playlist.uuid = "pl-1"
        playlist.title = .with { $0.value = "Recreated" }
        playlist.isDeleted = .with { $0.value = false }
        var record = Api_Record()
        record.playlist = playlist
        var recreateEnvelope = Filesync_OpEnvelope()
        recreateEnvelope.deviceID = "b"
        recreateEnvelope.seq = 1
        recreateEnvelope.wallClockMs = 2000
        recreateEnvelope.record = record

        let state = MergeEngine.merged(snapshots: [], ops: [tombstoneEnvelope, recreateEnvelope])
        let merged = state.playlists["pl-1"]!.record
        XCTAssertFalse(merged.isDeleted.value, "a strictly newer create wins over the tombstone")
        XCTAssertEqual(merged.title.value, "Recreated")
    }

    // MARK: Settings / stats / uploads

    func testSettingsMergePerNameByModifiedAt() {
        func settingOp(device: String, seq: UInt64, name: String, value: String, modifiedMs: Int64) -> Filesync_OpEnvelope {
            var setting = Filesync_SettingOp()
            setting.name = name
            setting.jsonValue = value
            setting.modifiedAtMs = modifiedMs
            var envelope = Filesync_OpEnvelope()
            envelope.deviceID = device
            envelope.seq = seq
            envelope.wallClockMs = modifiedMs
            envelope.setting = setting
            return envelope
        }
        let ops = [
            settingOp(device: "a", seq: 1, name: "skipForward", value: "30", modifiedMs: 1000),
            settingOp(device: "b", seq: 1, name: "skipForward", value: "45", modifiedMs: 2000),
            settingOp(device: "a", seq: 2, name: "skipBack", value: "10", modifiedMs: 3000),
        ]
        let state = MergeEngine.merged(snapshots: [], ops: ops)
        XCTAssertEqual(state.settings["skipForward"]?.jsonValue, "45")
        XCTAssertEqual(state.settings["skipBack"]?.jsonValue, "10")
    }

    func testStatsKeepLatestPerDevice() {
        func statsOp(device: String, seq: UInt64, wallClockMs: Int64, listened: Int64) -> Filesync_OpEnvelope {
            var stats = Filesync_StatsCumulative()
            stats.timeListened = listened
            var envelope = Filesync_OpEnvelope()
            envelope.deviceID = device
            envelope.seq = seq
            envelope.wallClockMs = wallClockMs
            envelope.stats = stats
            return envelope
        }
        let ops = [
            statsOp(device: "a", seq: 1, wallClockMs: 1000, listened: 100),
            statsOp(device: "a", seq: 2, wallClockMs: 2000, listened: 250),
            statsOp(device: "b", seq: 1, wallClockMs: 1500, listened: 40),
        ]
        let state = MergeEngine.merged(snapshots: [], ops: ops)
        XCTAssertEqual(state.statsByDevice["a"]?.stats.timeListened, 250)
        XCTAssertEqual(state.statsByDevice["b"]?.stats.timeListened, 40)
        XCTAssertEqual(state.statsByDevice.values.reduce(0) { $0 + $1.stats.timeListened }, 290,
                       "displayed totals sum the per-device counters")
    }

    func testUploadIdentityLatestWinsAndTombstoneTracked() {
        func uploadOp(device: String, seq: UInt64, wallClockMs: Int64, path: String) -> Filesync_OpEnvelope {
            var identity = Filesync_UploadIdentity()
            identity.uuid = "ue-1"
            identity.relativePath = path
            identity.sha256 = "abc"
            var envelope = Filesync_OpEnvelope()
            envelope.deviceID = device
            envelope.seq = seq
            envelope.wallClockMs = wallClockMs
            envelope.upload = identity
            return envelope
        }
        var removal = Filesync_UploadTombstone()
        removal.uuid = "ue-1"
        removal.deletedAtMs = 3000
        var removalEnvelope = Filesync_OpEnvelope()
        removalEnvelope.deviceID = "b"
        removalEnvelope.seq = 9
        removalEnvelope.wallClockMs = 3000
        removalEnvelope.uploadRemoved = removal

        let state = MergeEngine.merged(snapshots: [], ops: [
            uploadOp(device: "a", seq: 1, wallClockMs: 1000, path: "old.mp3"),
            uploadOp(device: "a", seq: 2, wallClockMs: 2000, path: "Audiobooks/new.mp3"),
            removalEnvelope,
        ])
        XCTAssertEqual(state.uploads["ue-1"]?.identity.relativePath, "Audiobooks/new.mp3")
        XCTAssertEqual(state.uploadTombstones["ue-1"]?.wallClockMs, 3000,
                       "removal is recorded; the applier resolves delete-vs-identity by stamp")
    }

    func testUploadManifestOnlySuppressesUploadsNoNewerThanTombstone() {
        func manifest(uploadStamp: Int64, tombstoneStamp: Int64) -> [Filesync_UploadIdentity] {
            var identity = Filesync_UploadIdentity()
            identity.uuid = "ue-1"
            identity.relativePath = "Audiobooks/new.mp3"

            var mergedState = MergeEngine.MergedState()
            mergedState.uploads[identity.uuid] = MergeEngine.UploadEntry(
                identity: identity,
                stamp: OpStamp(wallClockMs: uploadStamp, deviceID: "a", seq: 1)
            )
            mergedState.uploadTombstones[identity.uuid] = OpStamp(wallClockMs: tombstoneStamp, deviceID: "b", seq: 1)

            return FileSyncManager.UploadManifestState(mergedState: mergedState).manifest
        }

        XCTAssertEqual(manifest(uploadStamp: 4000, tombstoneStamp: 3000).map(\.uuid), ["ue-1"])
        XCTAssertTrue(manifest(uploadStamp: 3000, tombstoneStamp: 3000).isEmpty)
        XCTAssertTrue(manifest(uploadStamp: 2000, tombstoneStamp: 3000).isEmpty)
    }

    // MARK: Snapshot equivalence

    func testSnapshotBootstrapMatchesLogReplayForEpisodes() {
        // State built purely from ops…
        let ops = [
            episodeOp(device: "a", seq: 1, wallClockMs: 1000, playedUpTo: 100, starred: true),
            episodeOp(device: "b", seq: 1, wallClockMs: 2000, playedUpTo: 200),
        ]
        let fromOps = MergeEngine.merged(snapshots: [], ops: ops)

        // …must match state built from a snapshot capturing the same merge,
        // because episode records carry their *_modified stamps inline.
        var snapshotRecord = Filesync_SnapshotRecord()
        var record = Api_Record()
        record.episode = fromOps.episodes["ep-1"]!.record
        snapshotRecord.record = record
        var snapshot = Filesync_Snapshot()
        snapshot.deviceID = "a"
        snapshot.createdAtMs = 5000
        snapshot.records = [snapshotRecord]

        let fromSnapshot = MergeEngine.merged(snapshots: [snapshot], ops: [])
        XCTAssertEqual(fromSnapshot.episodes["ep-1"]?.record, fromOps.episodes["ep-1"]?.record)

        // A newer live op still beats the snapshot…
        let newer = episodeOp(device: "c", seq: 1, wallClockMs: 9000, playedUpTo: 900)
        let advanced = MergeEngine.merged(snapshots: [snapshot], ops: [newer])
        XCTAssertEqual(advanced.episodes["ep-1"]?.record.playedUpTo.value, 900)

        // …and an older live op does not.
        let older = episodeOp(device: "c", seq: 1, wallClockMs: 500, playedUpTo: 5, playedUpToModified: 500)
        let unchanged = MergeEngine.merged(snapshots: [snapshot], ops: [older])
        XCTAssertEqual(unchanged.episodes["ep-1"]?.record.playedUpTo.value, 200)
    }
}
