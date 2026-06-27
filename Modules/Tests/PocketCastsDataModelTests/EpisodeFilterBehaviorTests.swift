import XCTest
@testable import PocketCastsDataModel
@testable import PocketCastsUtils

/// Behaviour parity net for `EpisodeFilter`, written ahead of the class -> struct (value-type,
/// `Sendable`) migration (see `docs/Phase3-RecordSendability.md`). Every assertion is phrased to hold
/// for both the current `NSObject` class and the future struct:
///   - equality/hashing is exercised via `==`, `hashValue`, and `Set` (not the class-only
///     `isEqual(_:)`/`hash`), so the same tests validate the struct's synthesised conformances;
///   - persistence assertions read the value *returned* by `save(playlist:)`, never the argument,
///     because the struct will no longer back-mutate the caller's instance.
///
/// Pure-logic tests use `let` bindings (mutation through a class reference is legal today); the
/// class -> struct flip will turn the relevant `let`s into `var`s as part of its compiler-driven sweep.
final class EpisodeFilterLogicTests: XCTestCase {

    // MARK: - Equality & hashing (keyed on uuid)

    func testEqualWhenUuidMatches() {
        let a = EpisodeFilter()
        a.uuid = "shared-uuid"
        let b = EpisodeFilter()
        b.uuid = "shared-uuid"

        XCTAssertEqual(a, b)
        XCTAssertEqual(a.hashValue, b.hashValue)
    }

    /// Regression test for the `isEqual`-by-`uuid` / `hash`-by-`id` inconsistency: two filters equal by
    /// uuid must also hash equally even when their local row `id`s differ (e.g. unsaved vs saved).
    func testEqualAndHashConsistentWhenUuidMatchesButIdDiffers() {
        let unsaved = EpisodeFilter()
        unsaved.uuid = "shared-uuid"
        unsaved.id = 0

        let saved = EpisodeFilter()
        saved.uuid = "shared-uuid"
        saved.id = 4242

        XCTAssertEqual(unsaved, saved, "Filters with the same uuid should be equal regardless of id")
        XCTAssertEqual(unsaved.hashValue, saved.hashValue, "Equal filters must hash equally (Hashable contract)")
    }

    func testNotEqualWhenUuidDiffers() {
        let a = EpisodeFilter()
        a.uuid = "uuid-a"
        let b = EpisodeFilter()
        b.uuid = "uuid-b"

        XCTAssertNotEqual(a, b)
    }

    /// The `ManualPlaylistsChooserViewController` scenario: a `Set<EpisodeFilter>` must dedupe by uuid
    /// even when members carry different `id`s. Before the hash fix this set would have held 3 elements.
    func testSetDedupesByUuidIgnoringId() {
        let first = EpisodeFilter()
        first.uuid = "same"
        first.id = 1

        let duplicate = EpisodeFilter()
        duplicate.uuid = "same"
        duplicate.id = 999

        let other = EpisodeFilter()
        other.uuid = "different"

        let set: Set<EpisodeFilter> = [first, duplicate, other]

        XCTAssertEqual(set.count, 2)
        XCTAssertTrue(set.contains(first))
        XCTAssertTrue(set.contains(other))
    }

    // MARK: - addPodcast / removePodcast

    func testAddPodcastToEmptyFilterSetsUuidAndClearsAllPodcasts() {
        let filter = EpisodeFilter()
        filter.filterAllPodcasts = true
        filter.podcastUuids = ""
        filter.syncStatus = SyncStatus.synced.rawValue

        filter.addPodcast(podcastUuid: "podcast-1")

        XCTAssertEqual(filter.podcastUuids, "podcast-1")
        XCTAssertFalse(filter.filterAllPodcasts, "Adding a specific podcast turns off 'all podcasts'")
        XCTAssertEqual(filter.syncStatus, SyncStatus.notSynced.rawValue, "Mutation marks the filter unsynced")
    }

    func testAddPodcastAppendsCommaSeparated() {
        let filter = EpisodeFilter()
        filter.podcastUuids = "podcast-1"

        filter.addPodcast(podcastUuid: "podcast-2")

        XCTAssertEqual(filter.podcastUuids, "podcast-1,podcast-2")
    }

    func testRemovePodcastLeavesRemaining() {
        let filter = EpisodeFilter()
        filter.podcastUuids = "podcast-1,podcast-2,podcast-3"

        filter.removePodcast(podcastUuid: "podcast-2")

        XCTAssertEqual(filter.podcastUuids, "podcast-1,podcast-3")
    }

    func testRemovingLastPodcastReenablesAllPodcasts() {
        let filter = EpisodeFilter()
        filter.filterAllPodcasts = false
        filter.podcastUuids = "podcast-1"

        filter.removePodcast(podcastUuid: "podcast-1")

        XCTAssertEqual(filter.podcastUuids, "")
        XCTAssertTrue(filter.filterAllPodcasts, "Removing the last podcast falls back to 'all podcasts'")
    }

    func testRemovePodcastNotPresentIsNoOp() {
        let filter = EpisodeFilter()
        filter.podcastUuids = "podcast-1,podcast-2"

        filter.removePodcast(podcastUuid: "podcast-3")

        XCTAssertEqual(filter.podcastUuids, "podcast-1,podcast-2")
    }

    // MARK: - setTitle

    func testSetTitleWithValueUsesValue() {
        let filter = EpisodeFilter()
        filter.playlistName = "old"

        filter.setTitle("My Filter", defaultTitle: "New Filter")

        XCTAssertEqual(filter.playlistName, "My Filter")
    }

    func testSetTitleWithNilUsesDefault() {
        let filter = EpisodeFilter()
        filter.playlistName = "old"

        filter.setTitle(nil, defaultTitle: "New Filter")

        XCTAssertEqual(filter.playlistName, "New Filter")
    }

    func testSetTitleWithWhitespaceOnlyUsesDefault() {
        let filter = EpisodeFilter()
        filter.playlistName = "old"

        filter.setTitle("   \n ", defaultTitle: "New Filter")

        XCTAssertEqual(filter.playlistName, "New Filter")
    }

    // MARK: - Removal-rule helpers

    func testMarkingAsPlayedRemovesItemMirrorsFilterFinished() {
        let removes = EpisodeFilter()
        removes.filterFinished = false
        XCTAssertTrue(removes.markingAsPlayedRemovesItem())

        let keeps = EpisodeFilter()
        keeps.filterFinished = true
        XCTAssertFalse(keeps.markingAsPlayedRemovesItem())
    }

    func testMarkingAsUnplayedRemovesItemMirrorsFilterUnplayed() {
        let removes = EpisodeFilter()
        removes.filterUnplayed = false
        XCTAssertTrue(removes.markingAsUnplayedRemovesItem())

        let keeps = EpisodeFilter()
        keeps.filterUnplayed = true
        XCTAssertFalse(keeps.markingAsUnplayedRemovesItem())
    }

    func testDeletingFileRemovesItemMirrorsFilterDownloaded() {
        let removes = EpisodeFilter()
        removes.filterDownloaded = false
        XCTAssertTrue(removes.deletingFileRemovesItem())

        let keeps = EpisodeFilter()
        keeps.filterDownloaded = true
        XCTAssertFalse(keeps.deletingFileRemovesItem())
    }
}

/// Persistence parity for `EpisodeFilter`, run against both the legacy SQL and GRDB query-interface
/// code paths. Asserts on the value returned by `save(playlist:)` so the contract survives the
/// value-type migration.
final class EpisodeFilterPersistenceTests: DataManagerTestCase {

    func testSaveReturnsValueWithAssignedIdAndUpdateDate() throws {
        try runWithBothImplementations { dataManager, implementationName in
            let filter = EpisodeFilter()
            filter.uuid = UUID().uuidString.lowercased()
            filter.playlistName = "Returns id"
            XCTAssertEqual(filter.id, 0, "\(implementationName): a new filter has no id yet")

            let saved = dataManager.save(playlist: filter)

            XCTAssertNotEqual(saved.id, 0, "\(implementationName): save assigns a row id on insert")
            XCTAssertNotNil(saved.playlistUpdateDate, "\(implementationName): save stamps playlistUpdateDate")
            XCTAssertEqual(saved.uuid, filter.uuid, "\(implementationName): uuid is preserved")
        }
    }

    func testSavedReturnValueMatchesReloaded() throws {
        try runWithBothImplementations { dataManager, implementationName in
            let filter = EpisodeFilter()
            filter.uuid = UUID().uuidString.lowercased()
            filter.playlistName = "Round trip"
            filter.podcastUuids = "p1,p2"
            filter.sortType = 3

            let saved = dataManager.save(playlist: filter)

            guard let loaded = dataManager.findPlaylist(uuid: filter.uuid) else {
                XCTFail("\(implementationName): saved filter should reload")
                return
            }

            XCTAssertEqual(loaded.id, saved.id, "\(implementationName): persisted id matches the returned id")
            XCTAssertEqual(loaded.playlistName, saved.playlistName, "\(implementationName): name persisted")
            XCTAssertEqual(loaded.podcastUuids, saved.podcastUuids, "\(implementationName): podcastUuids persisted")
            XCTAssertEqual(loaded.sortType, saved.sortType, "\(implementationName): sortType persisted")
        }
    }

    func testResaveKeepsIdAndUpdatesRowInPlace() throws {
        try runWithBothImplementations { dataManager, implementationName in
            var filter = EpisodeFilter()
            filter.uuid = UUID().uuidString.lowercased()
            filter.playlistName = "First name"

            filter = dataManager.save(playlist: filter)
            let firstId = filter.id

            filter.playlistName = "Second name"
            let resaved = dataManager.save(playlist: filter)

            XCTAssertEqual(resaved.id, firstId, "\(implementationName): re-saving keeps the same row id")

            let matching = dataManager.allPlaylists(includeDeleted: true).filter { $0.uuid == filter.uuid }
            XCTAssertEqual(matching.count, 1, "\(implementationName): update must not create a duplicate row")
            XCTAssertEqual(matching.first?.playlistName, "Second name", "\(implementationName): update persisted the new name")
        }
    }

    func testAddAndRemovePodcastPersistThroughSave() throws {
        try runWithBothImplementations { dataManager, implementationName in
            let filter = EpisodeFilter()
            filter.uuid = UUID().uuidString.lowercased()
            filter.playlistName = "Membership"
            filter.filterAllPodcasts = true

            filter.addPodcast(podcastUuid: "podcast-1")
            filter.addPodcast(podcastUuid: "podcast-2")
            let saved = dataManager.save(playlist: filter)

            guard let loaded = dataManager.findPlaylist(uuid: saved.uuid) else {
                XCTFail("\(implementationName): filter should reload")
                return
            }
            XCTAssertEqual(loaded.podcastUuids, "podcast-1,podcast-2", "\(implementationName): membership persisted")
            XCTAssertFalse(loaded.filterAllPodcasts, "\(implementationName): adding podcasts cleared filterAllPodcasts")
        }
    }

    func testFindMissingPlaylistReturnsNil() throws {
        try runWithBothImplementations { dataManager, implementationName in
            XCTAssertNil(
                dataManager.findPlaylist(uuid: "does-not-exist"),
                "\(implementationName): unknown uuid returns nil"
            )
        }
    }
}
