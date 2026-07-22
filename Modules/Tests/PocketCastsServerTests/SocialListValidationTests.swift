import XCTest
@testable import PocketCastsServer

final class SocialListValidationTests: XCTestCase {
    func testCreateRejectsInvalidEntryPositionsBeforeEnqueuingRequest() async {
        let negativeEntry = SharedListEntry(episodeUuid: "negative", position: -1)
        let overflowingEntry = SharedListEntry(episodeUuid: "overflow", position: Int.max)

        let negativeResult = await ApiServerHandler.shared.createSharedList(
            title: "List",
            entries: [negativeEntry]
        )
        XCTAssertNil(negativeResult)

        let overflowingResult = await ApiServerHandler.shared.createSharedList(
            title: "List",
            entries: [overflowingEntry]
        )
        XCTAssertNil(overflowingResult)
    }

    func testFetchRejectsInvalidPaginationBeforeEnqueuingRequest() async {
        let negativeLimit = await ApiServerHandler.shared.fetchSharedList(id: 1, limit: -1)
        XCTAssertNil(negativeLimit)

        let negativeOffset = await ApiServerHandler.shared.fetchSharedList(id: 1, offset: -1)
        XCTAssertNil(negativeOffset)

        let overflowingLimit = await ApiServerHandler.shared.fetchSharedList(id: 1, limit: Int.max)
        XCTAssertNil(overflowingLimit)

        let overflowingOffset = await ApiServerHandler.shared.fetchSharedList(id: 1, offset: Int.max)
        XCTAssertNil(overflowingOffset)
    }

    func testMoveRejectsInvalidPositionBeforeEnqueuingRequest() async {
        let entry = SharedListEntry(episodeUuid: "episode")

        let negativeResult = await ApiServerHandler.shared.sharedListEntryOp(
            listId: 1,
            op: .move,
            entry: entry,
            position: -1
        )
        XCTAssertFalse(negativeResult)

        let overflowingResult = await ApiServerHandler.shared.sharedListEntryOp(
            listId: 1,
            op: .move,
            entry: entry,
            position: Int.max
        )
        XCTAssertFalse(overflowingResult)
    }
}
