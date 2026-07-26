import XCTest
@testable import PocketCastsServer

final class SocialInboxValidationTests: XCTestCase {
    func testSendSharedItemRejectsInvalidTimestampWithoutEnqueuingRequest() async {
        let handler = ApiServerHandler()
        handler.apiQueue.isSuspended = true
        defer { handler.apiQueue.cancelAllOperations() }

        let negativeResult = await handler.sendSharedItem(
            recipientHandle: "recipient",
            episodeUuid: "episode",
            podcastUuid: "podcast",
            episodeTitle: "Episode",
            podcastTitle: "Podcast",
            note: "",
            timestampSeconds: -1
        )
        XCTAssertFalse(negativeResult)

        let overflowingResult = await handler.sendSharedItem(
            recipientHandle: "recipient",
            episodeUuid: "episode",
            podcastUuid: "podcast",
            episodeTitle: "Episode",
            podcastTitle: "Podcast",
            note: "",
            timestampSeconds: Int.max
        )
        XCTAssertFalse(overflowingResult)
        XCTAssertEqual(handler.apiQueue.operationCount, 0)
    }

    func testFetchInboxRejectsInvalidPaginationWithoutEnqueuingRequest() async {
        let handler = ApiServerHandler()
        handler.apiQueue.isSuspended = true
        defer { handler.apiQueue.cancelAllOperations() }

        let negativeLimit = await handler.fetchInbox(limit: -1, offset: 0)
        XCTAssertNil(negativeLimit)

        let negativeOffset = await handler.fetchInbox(limit: 50, offset: -1)
        XCTAssertNil(negativeOffset)

        let overflowingLimit = await handler.fetchInbox(limit: Int.max, offset: 0)
        XCTAssertNil(overflowingLimit)

        let overflowingOffset = await handler.fetchInbox(limit: 50, offset: Int.max)
        XCTAssertNil(overflowingOffset)
        XCTAssertEqual(handler.apiQueue.operationCount, 0)
    }
}
