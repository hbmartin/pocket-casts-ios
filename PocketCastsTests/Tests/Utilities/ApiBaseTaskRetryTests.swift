import Foundation
import XCTest
@testable import PocketCastsServer
@testable import PocketCastsUtils

/// Covers the 429 Retry-After handling on ApiBaseTask's synchronous POST/GET paths (plan C.0-4).
final class ApiBaseTaskRetryTests: XCTestCase {
    // @unchecked Sendable: the counter is only mutated under its internal NSLock.
    private final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0

        func incrementAndRead() -> Int {
            lock.lock()
            defer { lock.unlock() }
            count += 1
            return count
        }

        var value: Int {
            lock.lock()
            defer { lock.unlock() }
            return count
        }
    }

    private let url = ServerConstants.Urls.api() + "user/update"

    func test429PostRetriesOnceAndSucceeds() {
        let requests = Counter()
        let task = ApiBaseTask(urlConnection: URLConnection { [url] request in
            XCTAssertEqual(request.url?.absoluteString, url)
            if requests.incrementAndRead() == 1 {
                return (nil, HTTPURLResponse(url: request.url!, statusCode: 429, httpVersion: nil, headerFields: ["Retry-After": "0"]))
            }
            return ("ok".data(using: .utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil))
        })

        let (data, statusCode) = task.postToServer(url: url, token: "token", data: Data())

        XCTAssertEqual(statusCode, 200)
        XCTAssertEqual(data, "ok".data(using: .utf8))
        XCTAssertEqual(requests.value, 2)
    }

    func test429PostSurfacesAfterSingleRetry() {
        let requests = Counter()
        let task = ApiBaseTask(urlConnection: URLConnection { request in
            _ = requests.incrementAndRead()
            return (nil, HTTPURLResponse(url: request.url!, statusCode: 429, httpVersion: nil, headerFields: ["Retry-After": "0"]))
        })

        let (data, statusCode) = task.postToServer(url: url, token: "token", data: Data())

        XCTAssertNil(data)
        XCTAssertEqual(statusCode, 429, "A persistent 429 must surface to the caller after one retry")
        XCTAssertEqual(requests.value, 2, "Exactly one retry — never a loop")
    }

    func test429GetRetriesOnceAndSucceeds() {
        let requests = Counter()
        let task = ApiBaseTask(urlConnection: URLConnection { request in
            if requests.incrementAndRead() == 1 {
                return (nil, HTTPURLResponse(url: request.url!, statusCode: 429, httpVersion: nil, headerFields: ["Retry-After": "0"]))
            }
            return ("ok".data(using: .utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil))
        })

        let (data, response) = task.getToServer(url: url, token: "token")

        XCTAssertEqual(response?.statusCode, 200)
        XCTAssertEqual(data, "ok".data(using: .utf8))
        XCTAssertEqual(requests.value, 2)
    }
}
