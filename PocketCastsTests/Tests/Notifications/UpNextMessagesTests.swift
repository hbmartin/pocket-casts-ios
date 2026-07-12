import XCTest

@testable import podcasts

/// Round-trip tests for the Up Next typed notification messages (migration
/// Phase 5.3). The bridged representations are frozen while string-based
/// posters/observers still exist, so these assert the exact `object`/`userInfo`
/// shapes as well as the typed round trip.
final class UpNextMessagesTests: XCTestCase {
    // MARK: - UpNextEpisodeAdded (payload-carrying)

    func testEpisodeAddedRoundTripsUuidAndAddedToTop() throws {
        for toTop in [true, false] {
            let message = UpNextEpisodeAdded(uuid: "episode-uuid", addedToTop: toTop)
            let notification = UpNextEpisodeAdded.makeNotification(message)

            // Frozen bridged shape: uuid in `object`, addedToTop in `userInfo`.
            XCTAssertEqual(notification.name, Constants.Notifications.upNextEpisodeAdded)
            XCTAssertEqual(notification.object as? String, "episode-uuid")
            XCTAssertEqual(notification.userInfo?[Constants.Notifications.upNextEpisodeAddedToTopKey] as? Bool, toTop)

            let roundTripped = try XCTUnwrap(UpNextEpisodeAdded.makeMessage(notification))
            XCTAssertEqual(roundTripped.uuid, "episode-uuid")
            XCTAssertEqual(roundTripped.addedToTop, toTop)
        }
    }

    func testEpisodeAddedBridgesFromBareStringPost() throws {
        // A legacy string-based post with no object/userInfo must still produce
        // a message, with nil uuid and addedToTop defaulting to false.
        let notification = Notification(name: Constants.Notifications.upNextEpisodeAdded)

        let message = try XCTUnwrap(UpNextEpisodeAdded.makeMessage(notification))
        XCTAssertNil(message.uuid)
        XCTAssertFalse(message.addedToTop)
    }

    // MARK: - UpNextEpisodeRemoved (uuid payload)

    func testEpisodeRemovedRoundTripsUuid() throws {
        let notification = UpNextEpisodeRemoved.makeNotification(UpNextEpisodeRemoved(uuid: "removed-uuid"))

        XCTAssertEqual(notification.name, Constants.Notifications.upNextEpisodeRemoved)
        XCTAssertEqual(notification.object as? String, "removed-uuid")

        let roundTripped = try XCTUnwrap(UpNextEpisodeRemoved.makeMessage(notification))
        XCTAssertEqual(roundTripped.uuid, "removed-uuid")
    }

    // MARK: - No-payload messages

    func testQueueChangedBridgesBothWays() {
        // String posts (e.g. PlaybackManager's, still unconverted) must reach
        // typed observers...
        XCTAssertNotNil(UpNextQueueChanged.makeMessage(Notification(name: Constants.Notifications.upNextQueueChanged)))
        // ...and typed posts must keep the legacy raw name for string observers.
        XCTAssertEqual(UpNextQueueChanged.makeNotification(UpNextQueueChanged()).name, Constants.Notifications.upNextQueueChanged)
    }

    func testShuffleToggledBridgesBothWays() {
        XCTAssertNotNil(UpNextShuffleToggled.makeMessage(Notification(name: Constants.Notifications.upNextShuffleToggle)))
        XCTAssertEqual(UpNextShuffleToggled.makeNotification(UpNextShuffleToggled()).name, Constants.Notifications.upNextShuffleToggle)
    }
}
