import PocketCastsUtils
import XCTest

@testable import podcasts

/// Round-trip tests for the typed episode-status messages: each message must
/// bridge to a `Notification` that string-based observers understand (uuid in
/// `object`, legacy raw name) and back to an identical typed message, so
/// posters and observers can migrate independently.
@MainActor
final class EpisodeMessagesTests: XCTestCase {
    // MARK: - Uuid-carrying messages

    func testEpisodePlayStatusChangedRoundTrip() {
        assertUuidRoundTrip(EpisodePlayStatusChanged.self, expectedRawName: "SJEpPlayStatusChanged")
    }

    func testEpisodeArchiveStatusChangedRoundTrip() {
        assertUuidRoundTrip(EpisodeArchiveStatusChanged.self, expectedRawName: "SJEpArchiveStatusChanged")
    }

    func testEpisodeStarredChangedRoundTrip() {
        assertUuidRoundTrip(EpisodeStarredChanged.self, expectedRawName: "SJEpisodeStarredChanged")
    }

    func testEpisodeDownloadedRoundTrip() {
        assertUuidRoundTrip(EpisodeDownloaded.self, expectedRawName: "SJEpisodeDownloaded")
    }

    func testEpisodeDownloadStatusChangedRoundTrip() {
        assertUuidRoundTrip(EpisodeDownloadStatusChanged.self, expectedRawName: "SJEpisodeDownloadChanged")
    }

    func testEpisodeDurationChangedRoundTrip() {
        assertUuidRoundTrip(EpisodeDurationChanged.self, expectedRawName: "SJEpDurationChanged")
    }

    func testUserEpisodeUpdatedRoundTrip() {
        assertUuidRoundTrip(UserEpisodeUpdated.self, expectedRawName: "SJUserEpisodeUpdated")
    }

    func testDownloadProgressChangedRoundTrip() {
        assertUuidRoundTrip(DownloadProgressChanged.self, expectedRawName: "SJDwnProg")
    }

    // MARK: - Payload-free messages

    func testManyEpisodesChangedRoundTrip() throws {
        try assertPayloadFreeRoundTrip(ManyEpisodesChanged.self, expectedRawName: "SJManyEpisodesChanged")
    }

    func testListeningHistoryChangedRoundTrip() throws {
        try assertPayloadFreeRoundTrip(ListeningHistoryChanged.self, expectedRawName: "SJListeningHistoryChanged")
    }

    // MARK: - Helpers

    /// message -> Notification -> message preserves the uuid, the bridged
    /// Notification carries the uuid in `object` on the legacy raw name, and a
    /// nil uuid survives the same trip.
    private func assertUuidRoundTrip<M: UuidBridgedMessage>(_ type: M.Type, expectedRawName: String) {
        XCTAssertEqual(M.name.rawValue, expectedRawName, "raw names are effectively ABI and must never change")

        let uuid = UUID().uuidString
        let notification = M.makeNotification(M(uuid: uuid))
        XCTAssertEqual(notification.name, M.name)
        XCTAssertEqual(notification.object as? String, uuid, "string-based observers read the uuid from object")
        XCTAssertNil(notification.userInfo)

        let message = M.makeMessage(notification)
        XCTAssertEqual(message?.uuid, uuid)

        // nil uuid (bulk change) round trip
        let nilNotification = M.makeNotification(M(uuid: nil))
        XCTAssertEqual(nilNotification.name, M.name)
        XCTAssertNil(nilNotification.object)

        let nilMessage = M.makeMessage(nilNotification)
        XCTAssertNotNil(nilMessage)
        XCTAssertNil(nilMessage?.uuid)
    }

    /// message -> Notification -> message for payload-free names: the bridged
    /// Notification is bare (legacy raw name, no object/userInfo) and any
    /// Notification with the right name decodes to a message.
    private func assertPayloadFreeRoundTrip<M: NotificationCenter.MainActorMessage>(_ type: M.Type, expectedRawName: String) throws {
        XCTAssertEqual(M.name.rawValue, expectedRawName, "raw names are effectively ABI and must never change")

        let message = try XCTUnwrap(M.makeMessage(Notification(name: M.name)))
        let notification = M.makeNotification(message)
        XCTAssertEqual(notification.name, M.name)
        XCTAssertNil(notification.object)

        XCTAssertNotNil(M.makeMessage(notification))
    }
}
