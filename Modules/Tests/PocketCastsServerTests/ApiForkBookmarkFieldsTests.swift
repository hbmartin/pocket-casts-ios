import XCTest
import SwiftProtobuf

@testable import PocketCastsServer

/// Guards for the fork bookmark fields in api.pb.swift (ADR-0016):
/// `Api_SyncUserBookmark` excerpt=1001, end_time=1002, trim_modified=1003,
/// tags=1004, tags_modified=1005, and the matching `Api_BookmarkResponse`
/// fork block (1001-1005).
///
/// Like `ApiForkSettingsFieldsTests`, `jsonString()` fails loudly on any
/// nameMap mistake, so these are the tripwire for regressions when the
/// generated file is regenerated or edited.
final class ApiForkBookmarkFieldsTests: XCTestCase {

    // MARK: - JSON encoding (nameMap guards)

    func testSyncUserBookmarkForkFieldsEncodeToJSON() throws {
        var bookmark = Api_SyncUserBookmark()
        bookmark.bookmarkUuid = "bm-1"
        bookmark.excerpt.value = "quoted words"
        bookmark.endTime.value = 62.5
        bookmark.trimModified.value = 2000
        bookmark.tags = ["ai", "investing"]
        bookmark.tagsModified.value = 3000

        let json = try bookmark.jsonString()

        XCTAssertTrue(json.contains("excerpt"), json)
        XCTAssertTrue(json.contains("endTime"), json)
        XCTAssertTrue(json.contains("trimModified"), json)
        XCTAssertTrue(json.contains("tags"), json)
        XCTAssertTrue(json.contains("tagsModified"), json)
    }

    func testBookmarkResponseForkFieldsEncodeToJSON() throws {
        var response = Api_BookmarkResponse()
        response.bookmarkUuid = "bm-1"
        response.excerpt = "quoted words"
        response.endTime = 62.5
        response.trimModified = 2000
        response.tags = ["ai"]
        response.tagsModified = 3000

        let json = try response.jsonString()

        XCTAssertTrue(json.contains("excerpt"), json)
        XCTAssertTrue(json.contains("endTime"), json)
        XCTAssertTrue(json.contains("trimModified"), json)
        XCTAssertTrue(json.contains("tagsModified"), json)
    }

    // MARK: - Binary round-trips

    func testSyncUserBookmarkForkFieldsBinaryRoundTrip() throws {
        var bookmark = Api_SyncUserBookmark()
        bookmark.bookmarkUuid = "bm-1"
        bookmark.title.value = "Title"
        bookmark.excerpt.value = "quoted words"
        bookmark.endTime.value = 62.5
        bookmark.trimModified.value = 2000
        bookmark.tags = ["ai", "investing"]
        bookmark.tagsModified.value = 3000

        let decoded = try Api_SyncUserBookmark(serializedBytes: bookmark.serializedData())

        XCTAssertTrue(decoded.hasExcerpt)
        XCTAssertEqual(decoded.excerpt.value, "quoted words")
        XCTAssertEqual(decoded.endTime.value, 62.5)
        XCTAssertTrue(decoded.hasTrimModified)
        XCTAssertEqual(decoded.trimModified.value, 2000)
        XCTAssertEqual(decoded.tags, ["ai", "investing"])
        XCTAssertTrue(decoded.hasTagsModified)
        XCTAssertEqual(decoded.tagsModified.value, 3000)
        XCTAssertEqual(decoded, bookmark, "Equality must consider the fork fields")
    }

    func testBookmarkResponseForkFieldsBinaryRoundTrip() throws {
        var response = Api_BookmarkResponse()
        response.bookmarkUuid = "bm-1"
        response.excerpt = "quoted words"
        response.endTime = 62.5
        response.trimModified = 2000
        response.tags = ["ai", "investing"]
        response.tagsModified = 3000

        let decoded = try Api_BookmarkResponse(serializedBytes: response.serializedData())

        XCTAssertEqual(decoded.excerpt, "quoted words")
        XCTAssertEqual(decoded.endTime, 62.5)
        XCTAssertEqual(decoded.trimModified, 2000)
        XCTAssertEqual(decoded.tags, ["ai", "investing"])
        XCTAssertEqual(decoded.tagsModified, 3000)
        XCTAssertEqual(decoded, response, "Equality must consider the fork fields")
    }

    // MARK: - Absence semantics

    func testUnsetForkFieldsStayAbsent() throws {
        var bookmark = Api_SyncUserBookmark()
        bookmark.bookmarkUuid = "bm-plain"

        let decoded = try Api_SyncUserBookmark(serializedBytes: bookmark.serializedData())

        XCTAssertFalse(decoded.hasExcerpt)
        XCTAssertFalse(decoded.hasEndTime)
        XCTAssertFalse(decoded.hasTrimModified)
        XCTAssertTrue(decoded.tags.isEmpty)
        XCTAssertFalse(decoded.hasTagsModified)
    }
}
