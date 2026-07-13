import Foundation
@testable import PocketCastsServer
import XCTest

final class RetryAfterTests: XCTestCase {
    private func response(retryAfter: String?) -> HTTPURLResponse {
        let url = URL(string: "https://api.pocketcasts.com/user/login")!
        var headers = [String: String]()
        if let retryAfter {
            headers["Retry-After"] = retryAfter
        }
        return HTTPURLResponse(url: url, statusCode: 429, httpVersion: nil, headerFields: headers)!
    }

    func testParsesDelaySeconds() {
        XCTAssertEqual(response(retryAfter: "5").retryAfterInterval(), 5)
        XCTAssertEqual(response(retryAfter: " 30 ").retryAfterInterval(), 30)
        XCTAssertEqual(response(retryAfter: "0").retryAfterInterval(), 0)
    }

    func testCapsDelaySeconds() {
        XCTAssertEqual(response(retryAfter: "3600").retryAfterInterval(), HTTPURLResponse.maximumRetryAfterDelay)
        XCTAssertEqual(response(retryAfter: "90").retryAfterInterval(maximum: 10), 10)
    }

    func testNegativeSecondsAreRejected() {
        XCTAssertNil(response(retryAfter: "-5").retryAfterInterval())
    }

    func testParsesHTTPDate() throws {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        let headerValue = formatter.string(from: Date(timeIntervalSinceNow: 30))

        let interval = try XCTUnwrap(response(retryAfter: headerValue).retryAfterInterval())
        // The formatted date drops sub-second precision, so allow generous slack.
        XCTAssertEqual(interval, 30, accuracy: 3)
    }

    func testPastHTTPDateClampsToZero() {
        XCTAssertEqual(response(retryAfter: "Wed, 21 Oct 2015 07:28:00 GMT").retryAfterInterval(), 0)
    }

    func testFarFutureHTTPDateIsCapped() {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        let headerValue = formatter.string(from: Date(timeIntervalSinceNow: 3600))

        XCTAssertEqual(response(retryAfter: headerValue).retryAfterInterval(), HTTPURLResponse.maximumRetryAfterDelay)
    }

    func testUnparseableAndAbsentHeadersReturnNil() {
        XCTAssertNil(response(retryAfter: "soon").retryAfterInterval())
        XCTAssertNil(response(retryAfter: "").retryAfterInterval())
        XCTAssertNil(response(retryAfter: nil).retryAfterInterval())
    }

    func testRetryDelayFallsBackToDefaultWhenHeaderMissing() {
        XCTAssertEqual(response(retryAfter: nil).tooManyRequestsRetryDelay(), HTTPURLResponse.defaultRetryAfterDelay)
        XCTAssertEqual(response(retryAfter: "7").tooManyRequestsRetryDelay(), 7)
    }
}
