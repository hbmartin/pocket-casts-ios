import Foundation
import XCTest
@testable import PocketCastsUtils

final class DateFormatHelperTests: XCTestCase {

    private let sut = DateFormatHelper.sharedHelper

    /// 2016-04-14 10:44:00 UTC — a fixed, non-current-year instant so the GMT-pinned
    /// formatters can assert exact output.
    private let referenceDate = Date(timeIntervalSince1970: 1_460_630_640)

    // MARK: - nil handling

    func testNilInputProducesEmptyOutput() {
        XCTAssertEqual(sut.longLocalizedFormat(nil), "")
        XCTAssertEqual(sut.shortLocalizedFormat(nil), "")
        XCTAssertEqual(sut.aboutPageFormat(nil), "")
        XCTAssertEqual(sut.tinyLocalizedFormat(nil), "")
        XCTAssertEqual(sut.justDayFormat(nil), "")
        XCTAssertEqual(sut.monthYearFormat(nil), "")
        XCTAssertEqual(sut.localTimeJsonFormat(nil), "")
        XCTAssertEqual(sut.jsonFormat(nil), "")
        XCTAssertNil(sut.jsonDate(nil))
        XCTAssertNil(sut.httpDate(nil))
    }

    // MARK: - JSON (GMT + en_US_POSIX, so output is locale-independent)

    func testJsonFormatProducesGMTTimestamp() {
        XCTAssertEqual(sut.jsonFormat(referenceDate), "2016-04-14 10:44:00")
    }

    func testJsonDateParsesGMTTimestamp() {
        XCTAssertEqual(sut.jsonDate("2016-04-14 10:44:00"), referenceDate)
    }

    func testJsonRoundTripPreservesWholeSeconds() {
        XCTAssertEqual(sut.jsonDate(sut.jsonFormat(referenceDate)), referenceDate)
    }

    func testJsonDateRejectsMalformedInput() {
        XCTAssertNil(sut.jsonDate("not a date"))
    }

    // MARK: - HTTP (RFC 1123, GMT + en_US_POSIX)

    func testHttpDateParsesRFC1123() {
        XCTAssertEqual(sut.httpDate("Thu, 14 Apr 2016 10:44:00 GMT"), referenceDate)
    }

    func testHttpDateRejectsMalformedInput() {
        XCTAssertNil(sut.httpDate("yesterday-ish"))
    }

    // MARK: - localTimeJsonFormat (fixed pattern, rendered in the current time zone)

    func testLocalTimeJsonFormatUsesCurrentTimeZone() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: referenceDate)
        let expected = String(format: "%04d-%02d-%02d %02d:%02d:%02d", c.year!, c.month!, c.day!, c.hour!, c.minute!, c.second!)
        XCTAssertEqual(sut.localTimeJsonFormat(referenceDate), expected)
    }

    // MARK: - Localized formatters (exact strings are locale-dependent; assert invariants)

    func testJustDayFormatCyclesWeekly() {
        let calendar = Calendar.current
        let nextDay = calendar.date(byAdding: .day, value: 1, to: referenceDate)!
        let sameWeekdayNextWeek = calendar.date(byAdding: .day, value: 7, to: referenceDate)!

        XCTAssertFalse(sut.justDayFormat(referenceDate).isEmpty)
        XCTAssertEqual(sut.justDayFormat(referenceDate), sut.justDayFormat(sameWeekdayNextWeek))
        XCTAssertNotEqual(sut.justDayFormat(referenceDate), sut.justDayFormat(nextDay))
    }

    func testMonthYearFormatReflectsMonthAndYearButNotDay() {
        let calendar = Calendar.current
        let laterSameMonth = calendar.date(byAdding: .day, value: 10, to: referenceDate)!
        let nextMonth = calendar.date(byAdding: .month, value: 1, to: referenceDate)!
        let nextYear = calendar.date(byAdding: .year, value: 1, to: referenceDate)!

        XCTAssertFalse(sut.monthYearFormat(referenceDate).isEmpty)
        XCTAssertEqual(sut.monthYearFormat(referenceDate), sut.monthYearFormat(laterSameMonth))
        XCTAssertNotEqual(sut.monthYearFormat(referenceDate), sut.monthYearFormat(nextMonth))
        XCTAssertNotEqual(sut.monthYearFormat(referenceDate), sut.monthYearFormat(nextYear))
    }

    func testLongLocalizedFormatDistinguishesYears() {
        let nextYear = Calendar.current.date(byAdding: .year, value: 1, to: referenceDate)!
        XCTAssertFalse(sut.longLocalizedFormat(referenceDate).isEmpty)
        XCTAssertNotEqual(sut.longLocalizedFormat(referenceDate), sut.longLocalizedFormat(nextYear))
    }

    func testShortLocalizedFormatDistinguishesDays() {
        let nextDay = Calendar.current.date(byAdding: .day, value: 1, to: referenceDate)!
        XCTAssertFalse(sut.shortLocalizedFormat(referenceDate).isEmpty)
        XCTAssertNotEqual(sut.shortLocalizedFormat(referenceDate), sut.shortLocalizedFormat(nextDay))
    }

    // MARK: - aboutPageFormat branch selection

    func testAboutPageFormatUsesFullDateForPastYears() {
        XCTAssertEqual(sut.aboutPageFormat(referenceDate), sut.longLocalizedFormat(referenceDate))
    }

    func testAboutPageFormatDropsYearWithinCurrentYear() {
        let now = Date()
        XCTAssertFalse(sut.aboutPageFormat(now).isEmpty)
        XCTAssertNotEqual(sut.aboutPageFormat(now), sut.longLocalizedFormat(now))
    }

    // MARK: - tinyLocalizedFormat branch selection

    func testTinyLocalizedFormatUsesFullDateForPastYears() {
        XCTAssertEqual(sut.tinyLocalizedFormat(referenceDate), sut.longLocalizedFormat(referenceDate))
    }

    func testTinyLocalizedFormatUsesWeekdayNameWithinTheLastWeek() {
        // One day away from now, constrained to the current year so the test doesn't
        // flip into the past-year branch when run on Jan 1 / Dec 31.
        let calendar = Calendar.current
        let now = Date()
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now)!
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: now)!
        let target = calendar.isDate(yesterday, equalTo: now, toGranularity: .year) ? yesterday : tomorrow

        XCTAssertEqual(sut.tinyLocalizedFormat(target), sut.justDayFormat(target))
    }

    func testTinyLocalizedFormatUsesMonthDayBeyondOneWeekInCurrentYear() {
        // Feb 1 and Jul 1 of the current year can't both be within a week of now.
        let calendar = Calendar.current
        let year = calendar.component(.year, from: Date())
        let target = [DateComponents(year: year, month: 2, day: 1, hour: 12),
                      DateComponents(year: year, month: 7, day: 1, hour: 12)]
            .compactMap { calendar.date(from: $0) }
            .first { abs($0.timeIntervalSinceNow) > 7.days }!

        let result = sut.tinyLocalizedFormat(target)
        XCTAssertFalse(result.isEmpty)
        XCTAssertNotEqual(result, sut.justDayFormat(target))
        XCTAssertNotEqual(result, sut.longLocalizedFormat(target))
    }

    // MARK: - Elapsed-time formatters

    func testElapsedTimeFormattersProduceOutputForValidInput() {
        // Exact strings are locale-dependent; assert they produce *something*.
        XCTAssertFalse(sut.longElapsedTime(150).isEmpty)
        XCTAssertFalse(sut.shortTimeRemaining(90).isEmpty)
    }

    // MARK: - Concurrent access (backs the checked Sendable conformance)

    func testConcurrentFormattingIsStable() {
        let sut = self.sut
        let date = referenceDate
        let expected = sut.jsonFormat(date)

        DispatchQueue.concurrentPerform(iterations: 100) { _ in
            XCTAssertEqual(sut.jsonFormat(date), expected)
            XCTAssertEqual(sut.jsonDate(expected), date)
        }
    }
}
