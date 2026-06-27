import XCTest
@testable import PocketCastsUtils

final class TimeFormatterTests: XCTestCase {

    private let sut = TimeFormatter.shared

    // MARK: - playTimeFormat (positional colon format — locale-independent)

    func testPlayTimeFormatUnderOneHour() {
        // The sub-hour formatter pads both units (zeroFormattingBehavior == .pad) -> "MM:SS".
        XCTAssertEqual(sut.playTimeFormat(time: 0), "00:00")
        XCTAssertEqual(sut.playTimeFormat(time: 5), "00:05")
        XCTAssertEqual(sut.playTimeFormat(time: 65), "01:05")
        XCTAssertEqual(sut.playTimeFormat(time: 90), "01:30")
        XCTAssertEqual(sut.playTimeFormat(time: 599), "09:59")
    }

    func testPlayTimeFormatOneHourAndOver() {
        XCTAssertEqual(sut.playTimeFormat(time: 3_600), "1:00:00")
        XCTAssertEqual(sut.playTimeFormat(time: 3_661), "1:01:01")
    }

    func testPlayTimeFormatHandlesNonFiniteInput() {
        XCTAssertEqual(sut.playTimeFormat(time: .nan), "0:00")
        XCTAssertEqual(sut.playTimeFormat(time: .infinity), "0:00")
    }

    // MARK: - non-finite guards return empty for the unit formatters

    func testUnitFormattersReturnEmptyForNonFiniteInput() {
        XCTAssertEqual(sut.singleUnitFormattedShortestTime(time: .nan), "")
        XCTAssertEqual(sut.multipleUnitFormattedShortTime(time: .nan), "")
        XCTAssertEqual(sut.multipleUnitFormattedSpokenTime(time: .infinity), "")
        XCTAssertEqual(sut.minutesHoursFormatted(time: .nan), "")
        XCTAssertEqual(sut.minutesFormatted(time: .nan), "")
    }

    func testUnitFormattersAreNonEmptyForValidInput() {
        // Exact strings are locale-dependent; assert they produce *something* for valid input.
        XCTAssertFalse(sut.singleUnitFormattedShortestTime(time: 90).isEmpty)
        XCTAssertFalse(sut.multipleUnitFormattedShortTime(time: 3_700).isEmpty)
        XCTAssertFalse(sut.minutesHoursFormatted(time: 3_700).isEmpty)
    }

    // MARK: - currentUTCTimeInMillis

    func testCurrentUTCTimeInMillisIsAroundNow() {
        let before = Int64(Date().timeIntervalSince1970 * 1000)
        let value = TimeFormatter.currentUTCTimeInMillis()
        let after = Int64(Date().timeIntervalSince1970 * 1000)
        XCTAssertGreaterThanOrEqual(value, before)
        XCTAssertLessThanOrEqual(value, after)
    }
}
