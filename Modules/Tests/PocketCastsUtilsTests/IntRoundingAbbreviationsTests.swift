import XCTest
@testable import PocketCastsUtils

final class IntRoundingAbbreviationsTests: XCTestCase {

    func testBelowThousandIsUnchanged() {
        XCTAssertEqual(0.abbreviated, "0")
        XCTAssertEqual(7.abbreviated, "7")
        XCTAssertEqual(999.abbreviated, "999")
    }

    func testThousandsAbbreviateWithOneDecimal() {
        XCTAssertEqual(1_000.abbreviated, "1.0K")
        XCTAssertEqual(1_234.abbreviated, "1.2K")
        XCTAssertEqual(1_250.abbreviated, "1.3K", "rounds to one decimal place")
        XCTAssertEqual(12_345.abbreviated, "12.3K")
        XCTAssertEqual(999_900.abbreviated, "999.9K", "stays in K just below a million")
    }

    func testMillionsAbbreviate() {
        XCTAssertEqual(1_000_000.abbreviated, "1.0M")
        XCTAssertEqual(1_500_000.abbreviated, "1.5M")
        XCTAssertEqual(1_234_567.abbreviated, "1.2M")
    }

    func testNegativeNumbersAreNotAbbreviated() {
        // The thresholds only match positive magnitudes, so negatives fall through unchanged.
        XCTAssertEqual((-5).abbreviated, "-5")
        XCTAssertEqual((-5_000).abbreviated, "-5000")
    }
}
