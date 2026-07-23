import XCTest

@testable import podcasts

final class MetricKitCollectorTests: XCTestCase {
    func testPayloadFilenameUsesFullUUIDWhenIdentifiersShareFormerPrefix() throws {
        let firstIdentifier = try XCTUnwrap(UUID(uuidString: "ABCD0000-0000-0000-0000-000000000001"))
        let secondIdentifier = try XCTUnwrap(UUID(uuidString: "ABCDFFFF-0000-0000-0000-000000000002"))
        let date = Date(timeIntervalSince1970: 0)

        let first = MetricKitCollector.payloadFilename(
            prefix: "metrics",
            date: date,
            identifier: firstIdentifier
        )
        let second = MetricKitCollector.payloadFilename(
            prefix: "metrics",
            date: date,
            identifier: secondIdentifier
        )

        XCTAssertNotEqual(first, second)
        XCTAssertEqual(first, "metrics-19700101-000000-000-ABCD0000-0000-0000-0000-000000000001.json")
        XCTAssertEqual(second, "metrics-19700101-000000-000-ABCDFFFF-0000-0000-0000-000000000002.json")
    }

    func testRetentionOrderingRemainsChronologicalAcrossDSTFallback() throws {
        // In America/Los_Angeles these instants straddle the repeated 1 a.m.
        // hour. UTC filenames must still increase with absolute time.
        let beforeFallback = try date("2026-11-01T08:59:59Z")
        let afterFallback = try date("2026-11-01T09:00:00Z")
        let firstIdentifier = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        let secondIdentifier = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000002"))

        let older = MetricKitCollector.payloadFilename(
            prefix: "metrics",
            date: beforeFallback,
            identifier: firstIdentifier
        )
        let newer = MetricKitCollector.payloadFilename(
            prefix: "metrics",
            date: afterFallback,
            identifier: secondIdentifier
        )

        XCTAssertEqual(older, "metrics-20261101-085959-000-00000000-0000-0000-0000-000000000001.json")
        XCTAssertEqual(newer, "metrics-20261101-090000-000-00000000-0000-0000-0000-000000000002.json")
        XCTAssertLessThan(older, newer)
        XCTAssertEqual(
            MetricKitCollector.payloadNamesToPrune(
                [newer, "diagnostics-ignored.json", older],
                prefix: "metrics-",
                keepingNewest: 1
            ),
            [older]
        )
    }

    private func date(_ value: String) throws -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return try XCTUnwrap(formatter.date(from: value))
    }
}
