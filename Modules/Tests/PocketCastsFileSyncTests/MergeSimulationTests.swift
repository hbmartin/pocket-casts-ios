import Foundation
import GRDB
import XCTest
@testable import PocketCastsDataModel
@testable import PocketCastsFileSync

// MARK: - Deterministic PRNG

/// SplitMix64: tiny, statistically solid, and fully deterministic. No
/// `Date()` and no system randomness anywhere in these simulations — a seed
/// always regenerates the exact same schedule, so any failure message that
/// names its seed is a complete reproduction recipe.
private struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

// MARK: - Entity pools

/// Small fixed uuid pools so concurrent ops actually collide on the same
/// entities instead of writing disjoint keys.
private enum Pools {
    static let episodes = (0..<6).map { "ep-\($0)" }
    static let podcasts = (0..<3).map { "pod-\($0)" }
    static let playlists = ["pl-0", "pl-1"]
    static let folders = ["fo-0", "fo-1"]
    static let bookmarks = ["bm-0", "bm-1"]

    static func podcast(forEpisodeAt index: Int) -> String {
        podcasts[index % podcasts.count]
    }
}

private enum SimEntityKind: CaseIterable {
    case episode, podcast, playlist, folder, bookmark

    var protoEntityType: Filesync_EntityType {
        switch self {
        case .episode: .episode
        case .podcast: .podcast
        case .playlist: .playlist
        case .folder: .folder
        case .bookmark: .bookmark
        }
    }

    func randomUuid(using rng: inout SplitMix64) -> String {
        switch self {
        case .episode: Pools.episodes.randomElement(using: &rng)!
        case .podcast: Pools.podcasts.randomElement(using: &rng)!
        case .playlist: Pools.playlists.randomElement(using: &rng)!
        case .folder: Pools.folders.randomElement(using: &rng)!
        case .bookmark: Pools.bookmarks.randomElement(using: &rng)!
        }
    }
}

/// An explicit "this entity exists again" record: the alive counterpart of a
/// tombstone. Per-field kinds (episode, bookmark) carry the user-action time
/// in their embedded `*_modified` stamps; envelope-stamped kinds (podcast,
/// playlist, folder) rely on the envelope wall clock.
private func aliveRecord(kind: SimEntityKind, uuid: String, ms: Int64) -> Api_Record {
    var record = Api_Record()
    switch kind {
    case .episode:
        var episode = Api_SyncUserEpisode()
        episode.uuid = uuid
        episode.isDeleted = .with { $0.value = false }
        episode.isDeletedModified = .with { $0.value = ms }
        record.episode = episode
    case .podcast:
        var podcast = Api_SyncUserPodcast()
        podcast.uuid = uuid
        podcast.subscribed = .with { $0.value = true }
        podcast.isDeleted = .with { $0.value = false }
        record.podcast = podcast
    case .playlist:
        var playlist = Api_SyncUserPlaylist()
        playlist.uuid = uuid
        playlist.isDeleted = .with { $0.value = false }
        playlist.title = .with { $0.value = "Recreated @\(ms)" }
        record.playlist = playlist
    case .folder:
        var folder = Api_SyncUserFolder()
        folder.folderUuid = uuid
        folder.isDeleted = false
        folder.name = "Recreated @\(ms)"
        record.folder = folder
    case .bookmark:
        var bookmark = Api_SyncUserBookmark()
        bookmark.bookmarkUuid = uuid
        bookmark.isDeleted = .with { $0.value = false }
        bookmark.isDeletedModified = .with { $0.value = ms }
        record.bookmark = bookmark
    }
    return record
}

// MARK: - Canonical merged state

/// The observable projection of a `MergedState`: record contents, replayed
/// Up Next queue, and setting values — everything a device would materialize
/// into its database. Comparing projections (instead of raw states) lets the
/// snapshot path differ in bookkeeping (snapshot stamps lose device ids by
/// design) while still requiring identical user-visible outcomes.
private struct CanonicalState: Equatable {
    let podcasts: [String: Api_SyncUserPodcast]
    let episodes: [String: Api_SyncUserEpisode]
    let playlists: [String: Api_SyncUserPlaylist]
    let folders: [String: Api_SyncUserFolder]
    let bookmarks: [String: Api_SyncUserBookmark]
    let tombstones: [String: Filesync_RecordTombstone]
    let upNextQueue: [UpNextMerger.QueueEntry]
    let settings: [String: String]
    let statsByDevice: [String: Filesync_StatsCumulative]
    let uploads: [String: Filesync_UploadIdentity]
    let uploadTombstoneUuids: Set<String>
    let forgottenDevices: Set<String>

    init(_ state: MergeEngine.MergedState) {
        podcasts = state.podcasts.mapValues(\.record)
        episodes = state.episodes.mapValues(\.record)
        playlists = state.playlists.mapValues(\.record)
        folders = state.folders.mapValues(\.record)
        bookmarks = state.bookmarks.mapValues(\.record)
        tombstones = state.tombstones
        upNextQueue = UpNextMerger.replay(ops: state.upNextOps)
        settings = state.settings.mapValues(\.jsonValue)
        statsByDevice = state.statsByDevice.mapValues(\.stats)
        uploads = state.uploads.mapValues(\.identity)
        uploadTombstoneUuids = Set(state.uploadTombstones.keys)
        forgottenDevices = state.forgottenDevices
    }
}

// MARK: - Simulation

/// Generates a deterministic multi-device op schedule from a seed:
/// 2–5 virtual devices with skewed clocks, interleaved episode/podcast/
/// playlist/bookmark writes, Up Next mutations, tombstones, resurrections,
/// and settings writes.
///
/// Clock construction: device `d` starts at `base + skew_d * 1000 + d` and
/// advances by whole seconds per op, so every wall-clock value in a schedule
/// is globally unique (device `d`'s clock is always ≡ `d` mod 1000). Unique
/// stamps keep the invariants crisp: exact-tie behaviour between a live op
/// and a snapshot-reconstructed stamp is *defined* to favour live ops, which
/// would otherwise show up as false "divergence".
private struct MergeSimulation {
    struct Device {
        let id: String
        var clockMs: Int64
        var seq: UInt64 = 0
    }

    private(set) var log: [Filesync_OpEnvelope] = []
    private(set) var devices: [Device]

    /// Oracle bookkeeping for the tombstone-monotonicity invariant.
    private(set) var newestWriteMs: [String: Int64] = [:]
    private(set) var newestTombstoneMs: [String: Int64] = [:]
    private(set) var newestResurrectionMs: [String: Int64] = [:]
    private(set) var kindByUuid: [String: SimEntityKind] = [:]

    private var rng: SplitMix64

    init(seed: UInt64) {
        var seedRng = SplitMix64(seed: seed)
        let names = ["device-a", "device-b", "device-c", "device-d", "device-e"]
        let deviceCount = Int.random(in: 2...5, using: &seedRng)
        var initial: [Device] = []
        for index in 0..<deviceCount {
            let skewSeconds = Int64.random(in: -40...40, using: &seedRng)
            initial.append(Device(
                id: names[index],
                clockMs: 1_000_000_000 + skewSeconds * 1000 + Int64(index)))
        }
        let opCount = Int.random(in: 80...140, using: &seedRng)

        devices = initial
        rng = seedRng
        for _ in 0..<opCount {
            step()
        }
    }

    private mutating func step() {
        let deviceIndex = Int.random(in: 0..<devices.count, using: &rng)
        devices[deviceIndex].clockMs += Int64.random(in: 1...5, using: &rng) * 1000
        devices[deviceIndex].seq += 1
        let ms = devices[deviceIndex].clockMs

        var envelope = Filesync_OpEnvelope()
        envelope.opID = "op-\(devices[deviceIndex].id)-\(devices[deviceIndex].seq)"
        envelope.deviceID = devices[deviceIndex].id
        envelope.seq = devices[deviceIndex].seq
        envelope.wallClockMs = ms

        switch Int.random(in: 0..<100, using: &rng) {
        case 0..<28: envelope.record = episodeWrite(at: ms)
        case 28..<44: envelope.record = podcastWrite(at: ms)
        case 44..<52: envelope.record = playlistWrite(at: ms)
        case 52..<58: envelope.record = bookmarkWrite(at: ms)
        case 58..<74: envelope.upNext = upNextOp()
        case 74..<84: envelope.tombstone = tombstone(at: ms)
        case 84..<92: envelope.record = resurrection(at: ms)
        default: envelope.setting = settingWrite(at: ms)
        }
        log.append(envelope)
    }

    // MARK: Op builders

    private mutating func noteWrite(uuid: String, kind: SimEntityKind, ms: Int64, resurrection: Bool = false) {
        kindByUuid[uuid] = kind
        newestWriteMs[uuid] = max(newestWriteMs[uuid] ?? .min, ms)
        if resurrection {
            newestResurrectionMs[uuid] = max(newestResurrectionMs[uuid] ?? .min, ms)
        }
    }

    /// Plain episode field writes never touch `isDeleted` — archival travels
    /// only through tombstones and resurrections, which keeps the
    /// monotonicity oracle exact.
    private mutating func episodeWrite(at ms: Int64) -> Api_Record {
        let index = Int.random(in: 0..<Pools.episodes.count, using: &rng)
        let uuid = Pools.episodes[index]
        var episode = Api_SyncUserEpisode()
        episode.uuid = uuid
        episode.podcastUuid = Pools.podcast(forEpisodeAt: index)

        var wroteField = false
        if Bool.random(using: &rng) {
            let position = Int64.random(in: 0...36_000, using: &rng)
            episode.playedUpTo = .with { $0.value = position }
            episode.playedUpToModified = .with { $0.value = ms }
            wroteField = true
        }
        if Bool.random(using: &rng) {
            let starred = Bool.random(using: &rng)
            episode.starred = .with { $0.value = starred }
            episode.starredModified = .with { $0.value = ms }
            wroteField = true
        }
        if !wroteField || Bool.random(using: &rng) {
            let duration = Int64.random(in: 60...7200, using: &rng)
            episode.duration = .with { $0.value = duration }
            episode.durationModified = .with { $0.value = ms }
        }
        noteWrite(uuid: uuid, kind: .episode, ms: ms)
        var record = Api_Record()
        record.episode = episode
        return record
    }

    /// Plain podcast writes never touch `subscribed`/`isDeleted` — the
    /// subscription lifecycle travels only through tombstones and
    /// resurrections (same reason as episodes above).
    private mutating func podcastWrite(at ms: Int64) -> Api_Record {
        let uuid = Pools.podcasts.randomElement(using: &rng)!
        var podcast = Api_SyncUserPodcast()
        podcast.uuid = uuid

        switch Int.random(in: 0..<4, using: &rng) {
        case 0:
            let sortPosition = Int32.random(in: 0...30, using: &rng)
            podcast.sortPosition = .with { $0.value = sortPosition }
        case 1:
            let folderUuid = Pools.folders.randomElement(using: &rng)!
            podcast.folderUuid = .with { $0.value = folderUuid }
        case 2:
            podcast.feedURL = "https://example.com/\(uuid)/\(Int.random(in: 0...3, using: &rng)).rss"
        default:
            var settings = Api_PodcastSettings()
            if Bool.random(using: &rng) {
                let speed = Double(Int.random(in: 5...30, using: &rng)) / 10
                settings.playbackSpeed = .with {
                    $0.value = .with { $0.value = speed }
                    $0.modifiedAt = .with {
                        $0.seconds = ms / 1000
                        $0.nanos = Int32((ms % 1000) * 1_000_000)
                    }
                }
            } else {
                let boost = Bool.random(using: &rng)
                settings.volumeBoost = .with {
                    $0.value = .with { $0.value = boost }
                    $0.modifiedAt = .with {
                        $0.seconds = ms / 1000
                        $0.nanos = Int32((ms % 1000) * 1_000_000)
                    }
                }
            }
            podcast.settings = settings
        }
        noteWrite(uuid: uuid, kind: .podcast, ms: ms)
        var record = Api_Record()
        record.podcast = podcast
        return record
    }

    private mutating func playlistWrite(at ms: Int64) -> Api_Record {
        let uuid = Pools.playlists.randomElement(using: &rng)!
        var playlist = Api_SyncUserPlaylist()
        playlist.uuid = uuid
        playlist.title = .with { $0.value = "Playlist \(uuid) @\(ms)" }
        playlist.isDeleted = .with { $0.value = false }
        noteWrite(uuid: uuid, kind: .playlist, ms: ms)
        var record = Api_Record()
        record.playlist = playlist
        return record
    }

    private mutating func bookmarkWrite(at ms: Int64) -> Api_Record {
        let uuid = Pools.bookmarks.randomElement(using: &rng)!
        var bookmark = Api_SyncUserBookmark()
        bookmark.bookmarkUuid = uuid
        // Creation-time fields are immutable and identical on every device.
        bookmark.podcastUuid = "pod-0"
        bookmark.episodeUuid = "ep-0"
        bookmark.createdAt = .with { $0.seconds = 900_000 }
        bookmark.time = .with { $0.value = 90 }
        bookmark.title = .with { $0.value = "Bookmark \(uuid) @\(ms)" }
        bookmark.titleModified = .with { $0.value = ms }
        noteWrite(uuid: uuid, kind: .bookmark, ms: ms)
        var record = Api_Record()
        record.bookmark = bookmark
        return record
    }

    private mutating func upNextOp() -> Filesync_UpNextOp {
        var op = Filesync_UpNextOp()
        let roll = Int.random(in: 0..<10, using: &rng)
        if roll < 2 {
            op.action = .replace
            let count = Int.random(in: 0...Pools.episodes.count, using: &rng)
            op.entries = Pools.episodes.indices.shuffled(using: &rng).prefix(count).map { index in
                var entry = Filesync_UpNextEntry()
                entry.episodeUuid = Pools.episodes[index]
                entry.podcastUuid = Pools.podcast(forEpisodeAt: index)
                return entry
            }
        } else {
            switch roll {
            case 2, 3: op.action = .playNow
            case 4, 5: op.action = .playNext
            case 6, 7: op.action = .playLast
            default: op.action = .remove
            }
            let index = Int.random(in: 0..<Pools.episodes.count, using: &rng)
            var entry = Filesync_UpNextEntry()
            entry.episodeUuid = Pools.episodes[index]
            entry.podcastUuid = Pools.podcast(forEpisodeAt: index)
            op.entry = entry
        }
        return op
    }

    private mutating func tombstone(at ms: Int64) -> Filesync_RecordTombstone {
        let kind = SimEntityKind.allCases.randomElement(using: &rng)!
        let uuid = kind.randomUuid(using: &rng)
        var tombstone = Filesync_RecordTombstone()
        tombstone.uuid = uuid
        tombstone.entityType = kind.protoEntityType
        tombstone.deletedAtMs = ms
        kindByUuid[uuid] = kind
        newestTombstoneMs[uuid] = max(newestTombstoneMs[uuid] ?? .min, ms)
        return tombstone
    }

    private mutating func resurrection(at ms: Int64) -> Api_Record {
        let kind = SimEntityKind.allCases.randomElement(using: &rng)!
        let uuid = kind.randomUuid(using: &rng)
        noteWrite(uuid: uuid, kind: kind, ms: ms, resurrection: true)
        return aliveRecord(kind: kind, uuid: uuid, ms: ms)
    }

    private mutating func settingWrite(at ms: Int64) -> Filesync_SettingOp {
        var op = Filesync_SettingOp()
        op.name = ["skipForward", "skipBack", "playbackSpeed", "autoPlayEnabled"].randomElement(using: &rng)!
        op.jsonValue = "\(Int.random(in: 0...60, using: &rng))"
        op.modifiedAtMs = ms
        return op
    }
}

// MARK: - Tests

final class MergeSimulationTests: XCTestCase {

    /// Fixed seed matrix: every test runs each seed, and every assertion
    /// message names the seed, so a red run is reproducible verbatim.
    private static let seeds: [UInt64] = [
        1, 42, 777, 123_456_789,
        0xDEAD_BEEF, 0xC0FF_EE00, 0x5EED_5EED, 0xA5A5_A5A5_A5A5_A5A5,
    ]

    // MARK: Convergence

    func testConvergenceAcrossDeliveryOrders() {
        for seed in Self.seeds {
            let sim = MergeSimulation(seed: seed)
            let baseline = CanonicalState(MergeEngine.merged(snapshots: [], ops: sim.log))

            var deliveryRng = SplitMix64(seed: seed ^ 0xD311_7E4F)
            var variants: [(String, [Filesync_OpEnvelope])] = [
                ("stamp-sorted", sim.log.sorted { $0.stamp < $1.stamp }),
                ("reversed", Array(sim.log.reversed())),
            ]
            for index in 0..<3 {
                variants.append(("shuffle-\(index)", sim.log.shuffled(using: &deliveryRng)))
            }
            // Duplicated delivery: roughly a quarter of the ops arrive twice.
            var duplicated = sim.log
            for op in sim.log where Int.random(in: 0..<4, using: &deliveryRng) == 0 {
                duplicated.append(op)
            }
            variants.append(("duplicated+shuffled", duplicated.shuffled(using: &deliveryRng)))

            for (name, variant) in variants {
                let state = CanonicalState(MergeEngine.merged(snapshots: [], ops: variant))
                XCTAssertEqual(
                    state, baseline,
                    "Merge diverged for delivery order '\(name)' — reproduce with seed \(seed)")
            }
        }
    }

    // MARK: Idempotence

    func testReapplyingPrefixesToConvergedStateIsANoOp() {
        for seed in Self.seeds {
            let sim = MergeSimulation(seed: seed)
            var prefixRng = SplitMix64(seed: seed ^ 0x1DE4_907A)
            let merged = MergeEngine.merged(snapshots: [], ops: sim.log)
            let baseline = CanonicalState(merged)

            var prefixLengths: Set<Int> = [1, sim.log.count / 2, sim.log.count]
            prefixLengths.insert(Int.random(in: 1...sim.log.count, using: &prefixRng))
            for length in prefixLengths.sorted() {
                var state = merged
                MergeEngine.fold(ops: Array(sim.log.prefix(length)), into: &state)
                XCTAssertEqual(
                    CanonicalState(state), baseline,
                    "Re-applying a prefix of \(length) ops changed converged state — reproduce with seed \(seed)")
            }
        }
    }

    // MARK: Snapshot equivalence

    func testSnapshotPlusTailReplayMatchesFullReplay() {
        let folder = InMemorySyncFolder()
        let dataManager = Self.makeScratchDataManager()

        for seed in Self.seeds {
            var splitRng = SplitMix64(seed: seed ^ 0x5A45_0CA7)
            let sim = MergeSimulation(seed: seed)
            // Split by stamp order: a snapshot summarizes everything up to a
            // point in merge time; ops it has not covered are strictly newer.
            let sorted = sim.log.sorted { $0.stamp < $1.stamp }
            let full = CanonicalState(MergeEngine.merged(snapshots: [], ops: sorted))
            let nowMs = sorted.last!.wallClockMs + 60_000

            for _ in 0..<3 {
                let split = Int.random(in: 1..<sorted.count, using: &splitRng)
                let prefixState = MergeEngine.merged(snapshots: [], ops: Array(sorted.prefix(split)))
                let writer = SnapshotWriter(folder: folder, dataManager: dataManager, deviceID: "device-a")
                let snapshot = writer.buildSnapshot(state: prefixState, headSeq: Int64(split), nowMs: nowMs)
                let combined = MergeEngine.merged(snapshots: [snapshot], ops: Array(sorted.dropFirst(split)))
                XCTAssertEqual(
                    CanonicalState(combined), full,
                    "Snapshot after \(split) ops + tail replay diverged from full replay — reproduce with seed \(seed)")
            }
        }
    }

    // MARK: Tombstone monotonicity

    func testTombstoneMonotonicityInRandomSchedules() {
        for seed in Self.seeds {
            let sim = MergeSimulation(seed: seed)
            let state = MergeEngine.merged(snapshots: [], ops: sim.log)

            for (uuid, tombstoneMs) in sim.newestTombstoneMs.sorted(by: { $0.key < $1.key }) {
                let kind = sim.kindByUuid[uuid]!
                let newestWrite = sim.newestWriteMs[uuid] ?? .min
                let newestResurrection = sim.newestResurrectionMs[uuid] ?? .min

                if tombstoneMs > newestWrite {
                    XCTAssertEqual(
                        Self.isDeleted(uuid: uuid, kind: kind, in: state), true,
                        "\(kind) \(uuid): a write older than the newest tombstone (\(tombstoneMs)) resurrected it — reproduce with seed \(seed)")
                } else if newestResurrection > tombstoneMs {
                    XCTAssertEqual(
                        Self.isDeleted(uuid: uuid, kind: kind, in: state), false,
                        "\(kind) \(uuid): resurrection newer than the tombstone (\(tombstoneMs)) did not win — reproduce with seed \(seed)")
                }
            }
        }
    }

    func testNewerTombstoneBeatsOlderWritesDeliveredLate() {
        for seed in Self.seeds {
            var rng = SplitMix64(seed: seed ^ 0x70B3_57ED)
            for kind in SimEntityKind.allCases {
                let deletedAtMs: Int64 = 5_000_000
                let uuid = "victim-\(kind)"

                var tombstone = Filesync_RecordTombstone()
                tombstone.uuid = uuid
                tombstone.entityType = kind.protoEntityType
                tombstone.deletedAtMs = deletedAtMs
                var tombstoneEnvelope = Filesync_OpEnvelope()
                tombstoneEnvelope.opID = "op-x-1"
                tombstoneEnvelope.deviceID = "device-x"
                tombstoneEnvelope.seq = 1
                tombstoneEnvelope.wallClockMs = deletedAtMs
                tombstoneEnvelope.tombstone = tombstone

                // Older writes delivered after the tombstone. Per-field kinds
                // (episode, bookmark) even flush late — the envelope claims a
                // newer wall clock while the embedded user-action stamp stays
                // older, and the embedded stamp must govern.
                var writes: [Filesync_OpEnvelope] = []
                for index in 0..<3 {
                    let olderMs = deletedAtMs
                        - Int64(index + 1) * 1000
                        - Int64.random(in: 0...999, using: &rng)
                    var envelope = Filesync_OpEnvelope()
                    envelope.opID = "op-y-\(index + 1)"
                    envelope.deviceID = "device-y"
                    envelope.seq = UInt64(index + 1)
                    switch kind {
                    case .episode, .bookmark:
                        envelope.wallClockMs = deletedAtMs + 10_000 + Int64(index)
                    case .podcast, .playlist, .folder:
                        envelope.wallClockMs = olderMs
                    }
                    envelope.record = aliveRecord(kind: kind, uuid: uuid, ms: olderMs)
                    writes.append(envelope)
                }

                let deliveries: [[Filesync_OpEnvelope]] = [
                    [tombstoneEnvelope] + writes,
                    writes + [tombstoneEnvelope],
                    ([tombstoneEnvelope] + writes).shuffled(using: &rng),
                ]
                for delivery in deliveries {
                    let state = MergeEngine.merged(snapshots: [], ops: delivery)
                    XCTAssertEqual(
                        Self.isDeleted(uuid: uuid, kind: kind, in: state), true,
                        "\(kind): older writes resurrected a newer tombstone — reproduce with seed \(seed)")
                }

                // A strictly newer alive write must resurrect the entity.
                var resurrectEnvelope = Filesync_OpEnvelope()
                resurrectEnvelope.opID = "op-y-9"
                resurrectEnvelope.deviceID = "device-y"
                resurrectEnvelope.seq = 9
                resurrectEnvelope.wallClockMs = deletedAtMs + 20_000
                resurrectEnvelope.record = aliveRecord(kind: kind, uuid: uuid, ms: deletedAtMs + 20_000)
                let resurrected = MergeEngine.merged(
                    snapshots: [], ops: [tombstoneEnvelope] + writes + [resurrectEnvelope])
                XCTAssertEqual(
                    Self.isDeleted(uuid: uuid, kind: kind, in: resurrected), false,
                    "\(kind): a strictly newer alive write failed to resurrect — reproduce with seed \(seed)")
            }
        }
    }

    // MARK: Helpers

    private static func isDeleted(uuid: String, kind: SimEntityKind, in state: MergeEngine.MergedState) -> Bool? {
        switch kind {
        case .episode:
            state.episodes[uuid]?.record.isDeleted.value
        case .podcast:
            state.podcasts[uuid].map { $0.record.isDeleted.value && !$0.record.subscribed.value }
        case .playlist:
            state.playlists[uuid]?.record.isDeleted.value
        case .folder:
            state.folders[uuid]?.record.isDeleted
        case .bookmark:
            state.bookmarks[uuid]?.record.isDeleted.value
        }
    }

    /// `SnapshotWriter.buildSnapshot` never touches its folder or database,
    /// but the struct requires both; the DataManager points at a scratch
    /// sqlite file with a fixed, deterministic path.
    private static func makeScratchDataManager() -> DataManager {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("merge-simulation-tests", isDirectory: true)
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var config = Configuration()
        config.busyMode = .timeout(10)
        let pool = try! DatabasePool(
            path: directory.appendingPathComponent("scratch.sqlite3").path,
            configuration: config)
        return DataManager(dbQueue: GRDBQueue(dbPool: pool))
    }
}
