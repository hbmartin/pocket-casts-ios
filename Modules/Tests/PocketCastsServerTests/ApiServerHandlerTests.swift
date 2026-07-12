import PocketCastsDataModel
@testable import PocketCastsServer
import XCTest

final class ApiServerHandlerTests: XCTestCase {
    func testUserEpisodeDoesNotThrottleRegularEpisodeProgressSave() {
        let handler = ApiServerHandler()
        handler.apiQueue.isSuspended = true
        defer { handler.apiQueue.cancelAllOperations() }

        handler.saveUpTo(time: 10, duration: 100, episode: UserEpisode(), minTimeBetweenProgressSaves: 60)
        handler.saveUpTo(time: 10, duration: 100, episode: Episode(), minTimeBetweenProgressSaves: 60)

        XCTAssertEqual(handler.apiQueue.operationCount, 1)
    }
}
