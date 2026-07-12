import PocketCastsDataModel
import PocketCastsUtils
import XCTest

@testable import podcasts

/// Round-trip tests for the typed podcast/folder/filter/discover messages: each
/// message must bridge to a `Notification` that string-based observers
/// understand (payload in `object`, legacy raw name) and back to an identical
/// typed message, so posters and observers can migrate independently.
@MainActor
final class PodcastMessagesTests: XCTestCase {
    // MARK: - Uuid-carrying messages

    func testPodcastUpdatedRoundTrip() {
        assertUuidRoundTrip(PodcastUpdated.self, expectedRawName: "SJPodcastUpdated")
    }

    func testPodcastAddedRoundTrip() {
        assertUuidRoundTrip(PodcastAdded.self, expectedRawName: "SJPodcastAdded")
    }

    func testPodcastDeletedRoundTrip() {
        assertUuidRoundTrip(PodcastDeleted.self, expectedRawName: "SJPodDeleted")
    }

    func testPodcastColorsDownloadedRoundTrip() {
        assertUuidRoundTrip(PodcastColorsDownloaded.self, expectedRawName: "SJPodcastColorsReady")
    }

    func testFolderChangedRoundTrip() {
        assertUuidRoundTrip(FolderChanged.self, expectedRawName: "SJFolderChanged")
    }

    func testFolderDeletedRoundTrip() {
        assertUuidRoundTrip(FolderDeleted.self, expectedRawName: "SJFolderDeleted")
    }

    func testFolderEditedRoundTrip() {
        assertUuidRoundTrip(FolderEdited.self, expectedRawName: "SJFolderEdited")
    }

    // MARK: - Playlist (episode filter) payload

    func testPlaylistChangedRoundTrip() throws {
        XCTAssertEqual(PlaylistChanged.name.rawValue, "FilterChanged", "raw names are effectively ABI and must never change")

        var playlist = EpisodeFilter()
        playlist.uuid = UUID().uuidString
        playlist.playlistName = "Round Trip"

        let notification = PlaylistChanged.makeNotification(PlaylistChanged(playlist: playlist))
        XCTAssertEqual(notification.name, PlaylistChanged.name)
        XCTAssertEqual(notification.object as? EpisodeFilter, playlist, "string-based observers read the filter from object")
        XCTAssertNil(notification.userInfo)

        let message = try XCTUnwrap(PlaylistChanged.makeMessage(notification))
        XCTAssertEqual(message.playlist, playlist)

        // nil playlist (bulk change) round trip
        let nilNotification = PlaylistChanged.makeNotification(PlaylistChanged(playlist: nil))
        XCTAssertEqual(nilNotification.name, PlaylistChanged.name)
        XCTAssertNil(nilNotification.object)

        let nilMessage = try XCTUnwrap(PlaylistChanged.makeMessage(nilNotification))
        XCTAssertNil(nilMessage.playlist)
    }

    // MARK: - Search term payload

    func testPodcastSearchRequestedRoundTrip() throws {
        XCTAssertEqual(PodcastSearchRequested.name.rawValue, "PodcastSearchRequest", "raw names are effectively ABI and must never change")

        let term = "science friday"
        let notification = PodcastSearchRequested.makeNotification(PodcastSearchRequested(term: term))
        XCTAssertEqual(notification.name, PodcastSearchRequested.name)
        XCTAssertEqual(notification.object as? String, term, "string-based observers read the term from object")
        XCTAssertNil(notification.userInfo)

        let message = try XCTUnwrap(PodcastSearchRequested.makeMessage(notification))
        XCTAssertEqual(message.term, term)

        let nilNotification = PodcastSearchRequested.makeNotification(PodcastSearchRequested(term: nil))
        XCTAssertNil(nilNotification.object)
        let nilMessage = try XCTUnwrap(PodcastSearchRequested.makeMessage(nilNotification))
        XCTAssertNil(nilMessage.term)
    }

    // MARK: - Payload-free messages

    func testPodcastImageReCacheRequiredRoundTrip() throws {
        try assertPayloadFreeRoundTrip(PodcastImageReCacheRequired.self, expectedRawName: "PCPodcastImageReCacheRequired")
    }

    func testOpmlImportCompletedRoundTrip() throws {
        try assertPayloadFreeRoundTrip(OpmlImportCompleted.self, expectedRawName: "SJOpmlImportCompleted")
    }

    func testOpmlImportFailedRoundTrip() throws {
        try assertPayloadFreeRoundTrip(OpmlImportFailed.self, expectedRawName: "SJOpmlImportFailed")
    }

    func testChartRegionChangedRoundTrip() throws {
        try assertPayloadFreeRoundTrip(ChartRegionChanged.self, expectedRawName: "SJChartRegionChanged")
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
