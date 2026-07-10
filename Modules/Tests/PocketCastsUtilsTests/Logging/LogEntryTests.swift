import Foundation
import XCTest
@testable import PocketCastsUtils

final class LogEntryTests: XCTestCase {
    func testFormattedForLogPrefixesLocalTimestamp() {
        let timestamp = Date(timeIntervalSince1970: 1_460_630_640)
        let entry = LogEntry("hello world", timestamp: timestamp)

        let expectedPrefix = DateFormatHelper.sharedHelper.localTimeJsonFormat(timestamp)
        XCTAssertEqual(entry.formattedForLog, "\(expectedPrefix) hello world")
    }
}
