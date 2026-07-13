import XCTest
import PocketCastsServer

@testable import podcasts

@MainActor
final class HeadphoneEpisodeActionTests: XCTestCase {
    private let allActions: [HeadphoneControlAction] = [
        .skipBack, .skipForward, .previousChapter, .nextChapter, .addBookmark, .nextEpisode, .previousEpisode
    ]

    func testHeadphoneControlRawValuesAreStable() {
        // Fork-invented sync values; changing them would corrupt saved settings.
        XCTAssertEqual(HeadphoneControl.nextEpisode.rawValue, 5)
        XCTAssertEqual(HeadphoneControl.previousEpisode.rawValue, 6)
    }

    func testHeadphoneControlActionMappingRoundTripsForAllCases() {
        for action in allActions {
            XCTAssertEqual(HeadphoneControl(action: action).action, action, "\(action) should survive the HeadphoneControl mapping round-trip")
        }
    }

    func testNewActionsEncodeAndDecodeAsJSON() throws {
        for action in [HeadphoneControlAction.nextEpisode, .previousEpisode] {
            let data = try XCTUnwrap(action.jsonData, "\(action) should encode")
            let decoded = try HeadphoneControlAction.encodedObject(HeadphoneControlAction.self, from: data)
            XCTAssertEqual(decoded, action)
        }
    }

    func testDecodingUnknownActionFails() {
        // Older builds decode-fail on the new case names and fall back to the setting default.
        let unknown = Data(#"{"someFutureAction":{}}"#.utf8)
        XCTAssertThrowsError(try HeadphoneControlAction.encodedObject(HeadphoneControlAction.self, from: unknown))
    }
}
