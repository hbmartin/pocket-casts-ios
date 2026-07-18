import XCTest
@testable import PocketCastsServer

/// Guards the fork-owned `custom_query = 1001` field on the shared upstream
/// playlist messages (Slice 7, ADR-0011) — the same regeneration tripwire
/// `ApiForkSettingsFieldsTests` covers for settings: if `mise run
/// generate:proto` ever runs against a proto missing the fork field, these
/// round-trips break loudly instead of custom playlists silently un-syncing.
final class ApiForkPlaylistFieldsTests: XCTestCase {
    func testSyncUserPlaylistCustomQueryBinaryRoundTrip() throws {
        var playlist = Api_SyncUserPlaylist()
        playlist.uuid = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
        playlist.customQuery.value = #"{"version":1,"mode":"sql"}"#

        let decoded = try Api_SyncUserPlaylist(serializedBytes: playlist.serializedData())
        XCTAssertTrue(decoded.hasCustomQuery)
        XCTAssertEqual(decoded.customQuery.value, #"{"version":1,"mode":"sql"}"#)
    }

    func testPlaylistSyncResponseCustomQueryBinaryRoundTrip() throws {
        var playlist = Api_PlaylistSyncResponse()
        playlist.uuid = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
        playlist.customQuery.value = "envelope"

        let decoded = try Api_PlaylistSyncResponse(serializedBytes: playlist.serializedData())
        XCTAssertTrue(decoded.hasCustomQuery)
        XCTAssertEqual(decoded.customQuery.value, "envelope")
    }

    func testAbsentCustomQueryStaysAbsent() throws {
        let playlist = Api_SyncUserPlaylist()
        let decoded = try Api_SyncUserPlaylist(serializedBytes: playlist.serializedData())
        XCTAssertFalse(decoded.hasCustomQuery, "absence must be distinguishable from empty — the import guard depends on it")
    }
}
