import XCTest
@testable import PocketCastsUtils

/// `SizeFormatter` wraps `ByteCountFormatter`, whose exact strings are locale-dependent. These tests
/// assert structural/relational properties that hold regardless of locale, plus a couple of unit-token
/// checks that hold on the en_US test simulator.
final class SizeFormatterTests: XCTestCase {

    private let sut = SizeFormatter.shared

    func testPlaceholderMatchesZeroBytesFormat() {
        XCTAssertFalse(sut.placeholder.isEmpty)
        XCTAssertEqual(sut.placeholder, sut.defaultFormat(bytes: 0))
    }

    func testDefaultFormatIsNonEmptyAndMonotonicAcrossMagnitudes() {
        let kb = sut.defaultFormat(bytes: 2_000)
        let mb = sut.defaultFormat(bytes: 5_000_000)
        let gb = sut.defaultFormat(bytes: 5_000_000_000)
        for s in [kb, mb, gb] { XCTAssertFalse(s.isEmpty) }
        XCTAssertNotEqual(kb, mb)
        XCTAssertNotEqual(mb, gb)
    }

    func testDefaultFormatUsesExpectedUnitTokens() {
        // en_US simulator; defaultFormat is restricted to GB/MB/KB.
        XCTAssertTrue(sut.defaultFormat(bytes: 5_000_000).contains("MB"))
        XCTAssertTrue(sut.defaultFormat(bytes: 5_000_000_000).contains("GB"))
    }

    func testNoDecimalFormatIsNonEmpty() {
        XCTAssertFalse(sut.noDecimalFormat(bytes: 0).isEmpty)
        XCTAssertFalse(sut.noDecimalFormat(bytes: 1_500_000).isEmpty)
    }
}
