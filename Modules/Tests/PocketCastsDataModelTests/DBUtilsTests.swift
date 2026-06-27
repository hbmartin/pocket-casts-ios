import XCTest
@testable import PocketCastsDataModel

final class DBUtilsTests: XCTestCase {

    // MARK: - placeholders

    func testPlaceholders() {
        XCTAssertEqual(DBUtils.placeholders(amount: 0), "")
        XCTAssertEqual(DBUtils.placeholders(amount: 1), "?")
        XCTAssertEqual(DBUtils.placeholders(amount: 3), "?,?,?")
        XCTAssertEqual(DBUtils.placeholders(amount: -2), "", "negative amounts are treated as zero")
    }

    // MARK: - valuesQuestionMarks

    func testValuesQuestionMarks() {
        XCTAssertEqual(DBUtils.valuesQuestionMarks(amount: 0), "")
        XCTAssertEqual(DBUtils.valuesQuestionMarks(amount: 1), "(?)")
        XCTAssertEqual(DBUtils.valuesQuestionMarks(amount: 2), "(?,? )")
        XCTAssertEqual(DBUtils.valuesQuestionMarks(amount: 3), "(?,? ,? )")
    }

    // MARK: - convertDate

    func testConvertDate() {
        XCTAssertNil(DBUtils.convertDate(value: nil))
        XCTAssertNil(DBUtils.convertDate(value: 0), "zero is treated as no date")
        XCTAssertNil(DBUtils.convertDate(value: -10), "negative is treated as no date")
        XCTAssertEqual(DBUtils.convertDate(value: 1_000), Date(timeIntervalSince1970: 1_000))
    }

    // MARK: - null helpers

    func testNullIfNil() {
        XCTAssertTrue(DBUtils.nullIfNil(value: nil) is NSNull)
        XCTAssertEqual(DBUtils.nullIfNil(value: 5) as? Int, 5)
    }

    func testReplaceNilWithNull() {
        XCTAssertTrue(DBUtils.replaceNilWithNull(value: nil) is NSNull)
        XCTAssertEqual(DBUtils.replaceNilWithNull(value: "x") as? String, "x")
    }

    // MARK: - generateUniqueId

    func testGenerateUniqueIdIsPositiveAndDistinct() {
        let a = DBUtils.generateUniqueId()
        let b = DBUtils.generateUniqueId()
        XCTAssertGreaterThanOrEqual(a, 0, "the sign bit is masked off")
        XCTAssertGreaterThanOrEqual(b, 0)
        XCTAssertNotEqual(a, b, "consecutive ids should differ")
    }

    // MARK: - currentUTCTimeInMillis

    func testCurrentUTCTimeInMillisIsAroundNow() {
        let before = Int64(Date().timeIntervalSince1970 * 1000)
        let value = DBUtils.currentUTCTimeInMillis()
        let after = Int64(Date().timeIntervalSince1970 * 1000)
        XCTAssertGreaterThanOrEqual(value, before)
        XCTAssertLessThanOrEqual(value, after)
    }

    // MARK: - Array helpers

    func testDatabaseValuesReplacesNilWithNSNull() {
        let array: [Any?] = [1, nil, "x"]
        let values = array.databaseValues
        XCTAssertEqual(values.count, 3)
        XCTAssertEqual(values[0] as? Int, 1)
        XCTAssertTrue(values[1] is NSNull)
        XCTAssertEqual(values[2] as? String, "x")
    }

    func testColumnString() {
        XCTAssertEqual(["a", "b", "c"].columnString, "a,b,c")
        XCTAssertEqual(["only"].columnString, "only")
    }
}
