@testable import PocketCastsServer
import XCTest

final class RefreshManagerTests: XCTestCase {

    // Regression: a refresh that succeeds but carries no `result` must still fire its
    // completion (with `.noData`). Callers that depend on the callback — background-fetch and
    // notification handlers that must call their own completion handler — otherwise hang
    // forever waiting for a call that never comes.
    func testProcessResponseFiresNoDataWhenSuccessfulButResultMissing() {
        var response = PodcastRefreshResponse()
        response.status = "ok" // success() == true...
        response.result = nil // ...but there is nothing to process.

        let expectation = expectation(forNotification: ServerNotifications.podcastsRefreshed, object: nil)
        var received: RefreshFetchResult?
        RefreshManager.shared.processPodcastRefreshResponse(response) { result in
            received = result
        }

        XCTAssertEqual(received, .noData)
        wait(for: [expectation], timeout: 0)
    }
}
