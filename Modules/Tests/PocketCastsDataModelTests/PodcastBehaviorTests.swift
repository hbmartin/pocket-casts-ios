import XCTest
@testable import PocketCastsDataModel
@testable import PocketCastsUtils

/// Behaviour parity net for `Podcast`, written ahead of the class -> struct (value-type, `Sendable`)
/// migration (see `docs/Phase3-RecordSendability.md`, record 3). Every assertion is phrased to hold for
/// both the current `NSObject` class and the future struct:
///   - equality/hashing is exercised via `==`, `hashValue`, and `Set` (not the class-only
///     `isEqual(_:)`/`hash`), so the same tests validate the struct's synthesised conformances;
///   - persistence assertions read the value *returned* by `save(podcast:)` (or a reload), never the
///     argument, because the struct will no longer back-mutate the caller's instance.
///
/// Pure-logic tests use `let` bindings (mutation through a class reference is legal today); the
/// class -> struct flip turns the relevant `let`s into `var`s as part of its compiler-driven sweep.
final class PodcastLogicTests: XCTestCase {

    // MARK: - Equality & hashing (keyed on uuid)

    func testEqualWhenUuidMatches() {
        var a = Podcast()
        a.uuid = "shared-uuid"
        var b = Podcast()
        b.uuid = "shared-uuid"

        XCTAssertEqual(a, b)
        XCTAssertEqual(a.hashValue, b.hashValue)
    }

    /// Regression for the `isEqual`-by-`uuid` / `hash`-by-`id` inconsistency fixed alongside this
    /// migration: two podcasts equal by uuid must also hash equally even when their row `id`s differ
    /// (e.g. an unsaved id == 0 copy vs the saved row).
    func testEqualAndHashConsistentWhenUuidMatchesButIdDiffers() {
        var unsaved = Podcast()
        unsaved.uuid = "shared-uuid"
        unsaved.id = 0

        var saved = Podcast()
        saved.uuid = "shared-uuid"
        saved.id = 4242

        XCTAssertEqual(unsaved, saved, "Podcasts with the same uuid should be equal regardless of id")
        XCTAssertEqual(unsaved.hashValue, saved.hashValue, "Equal podcasts must hash equally (Hashable contract)")
    }

    func testNotEqualWhenUuidDiffers() {
        var a = Podcast()
        a.uuid = "uuid-a"
        var b = Podcast()
        b.uuid = "uuid-b"

        XCTAssertNotEqual(a, b)
    }

    func testSetDedupesByUuidIgnoringId() {
        var first = Podcast()
        first.uuid = "same"
        first.id = 1

        var duplicate = Podcast()
        duplicate.uuid = "same"
        duplicate.id = 999

        var other = Podcast()
        other.uuid = "different"

        let set: Set<Podcast> = [first, duplicate, other]

        XCTAssertEqual(set.count, 2)
        XCTAssertTrue(set.contains(first))
        XCTAssertTrue(set.contains(other))
    }

    // MARK: - Simple computed accessors

    func testIsSubscribedReflectsSubscribedFlag() {
        var subscribed = Podcast()
        subscribed.subscribed = 1
        XCTAssertTrue(subscribed.isSubscribed())

        var unsubscribed = Podcast()
        unsubscribed.subscribed = 0
        XCTAssertFalse(unsubscribed.isSubscribed())
    }

    func testAutoDownloadOnReflectsSetting() {
        var on = Podcast()
        on.autoDownloadSetting = AutoDownloadSetting.latest.rawValue
        XCTAssertTrue(on.autoDownloadOn())

        var off = Podcast()
        off.autoDownloadSetting = AutoDownloadSetting.off.rawValue
        XCTAssertFalse(off.autoDownloadOn())
    }

    // MARK: - autoAddToUpNext (legacy storage path)

    func testAutoAddToUpNextOnLegacyStorage() throws {
        let store = FeatureFlagOverrideStore()
        defer { store.resetOverrides() }
        try store.override(FeatureFlag.newSettingsStorage, withValue: false)

        var addLast = Podcast()
        addLast.autoAddToUpNext = AutoAddToUpNextSetting.addLast.rawValue
        XCTAssertTrue(addLast.autoAddToUpNextOn())

        var off = Podcast()
        off.autoAddToUpNext = AutoAddToUpNextSetting.off.rawValue
        XCTAssertFalse(off.autoAddToUpNextOn())
    }
}

/// Persistence parity for `Podcast`, run against both the legacy SQL and GRDB query-interface code
/// paths. Asserts on the value returned by `save(podcast:)` (and reloads) so the contract survives the
/// value-type migration: `save` assigns the row id, re-saving updates in place without duplicating, and
/// the shared cache hands out independent values.
final class PodcastPersistenceTests: DataManagerTestCase {

    func testSaveReturnsValueWithAssignedId() throws {
        try runWithBothImplementations { dataManager, implementationName in
            var podcast = Podcast()
            podcast.uuid = UUID().uuidString
            podcast.title = "Returns id"
            XCTAssertEqual(podcast.id, 0, "\(implementationName): a new podcast has no id yet")

            let saved = dataManager.save(podcast: podcast)

            XCTAssertNotEqual(saved.id, 0, "\(implementationName): save assigns a row id on insert")
            XCTAssertEqual(saved.uuid, podcast.uuid, "\(implementationName): uuid is preserved")
        }
    }

    func testSavedReturnValueMatchesReloaded() throws {
        try runWithBothImplementations { dataManager, implementationName in
            var podcast = Podcast()
            podcast.uuid = UUID().uuidString
            podcast.title = "Round trip"
            podcast.author = "Author"
            podcast.sortOrder = 7
            podcast.subscribed = 1
            podcast.addedDate = Date()

            let saved = dataManager.save(podcast: podcast)

            guard let loaded = dataManager.findPodcast(uuid: podcast.uuid) else {
                XCTFail("\(implementationName): saved podcast should reload")
                return
            }

            XCTAssertEqual(loaded.id, saved.id, "\(implementationName): persisted id matches the returned id")
            XCTAssertEqual(loaded.title, "Round trip", "\(implementationName): title persisted")
            XCTAssertEqual(loaded.author, "Author", "\(implementationName): author persisted")
            XCTAssertEqual(loaded.sortOrder, 7, "\(implementationName): sortOrder persisted")
        }
    }

    /// The duplicate-row guard: re-saving a podcast whose in-memory id is still 0 (because a value-type
    /// save no longer back-mutates the caller's copy) must update the existing row by uuid, never insert
    /// a second one. Mirrors the EpisodeFilter save-then-add regression fixed in PR #113.
    func testResaveByUuidDoesNotDuplicate() throws {
        try runWithBothImplementations { dataManager, implementationName in
            var podcast = Podcast()
            podcast.uuid = "dup-guard"
            podcast.title = "First"
            podcast.subscribed = 1
            podcast.addedDate = Date()
            dataManager.save(podcast: podcast)

            // Simulate a caller that kept the original (id still 0 after a value-type save) and re-saves.
            var resave = Podcast()
            resave.uuid = "dup-guard"
            resave.title = "Second"
            resave.subscribed = 1
            resave.addedDate = Date()
            XCTAssertEqual(resave.id, 0, "\(implementationName): caller copy has no id")
            dataManager.save(podcast: resave)

            let matches = dataManager.allPodcasts(includeUnsubscribed: true, reloadFromDatabase: true)
                .filter { $0.uuid == "dup-guard" }
            XCTAssertEqual(matches.count, 1, "\(implementationName): save by uuid must not duplicate the row")
            XCTAssertEqual(matches.first?.title, "Second", "\(implementationName): the row was updated in place")
        }
    }

    func testFindMissingPodcastReturnsNil() throws {
        try runWithBothImplementations { dataManager, implementationName in
            XCTAssertNil(
                dataManager.findPodcast(uuid: "does-not-exist"),
                "\(implementationName): unknown uuid returns nil"
            )
        }
    }
}
