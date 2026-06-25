import SnapshotTesting
import XCTest

import PocketCastsUtils

final class PocketCastsUtilsLogicSnapshotTests: XCTestCase {
    func testSignificantDigitsFormatStyleMatrix() {
        let locale = Locale(identifier: "en_US_POSIX")
        let values: [TimeInterval] = [
            0,
            0.012345,
            1.2345,
            12.345,
            1234.5,
            -98.765,
        ]

        let snapshot = [2, 3, 5]
            .map { digits -> String in
                let formatter = SignificantDigitsFormatStyle(significantDigits: digits, locale: locale)
                let formattedValues = values
                    .map { value in "\(value) -> \(formatter.format(value))" }
                    .joined(separator: "\n")

                return """
                \(digits) significant digits
                \(formattedValues)
                """
            }
            .joined(separator: "\n\n---\n\n")

        assertSnapshot(of: snapshot, as: .lines)
    }

    func testSignificantDigitsParsing() {
        let formatter = SignificantDigitsFormatStyle(significantDigits: 3)

        let snapshot = [
            describeParse("42", formatter: formatter),
            describeParse("-17.5", formatter: formatter),
            describeParse("not-a-number", formatter: formatter),
        ].joined(separator: "\n")

        assertSnapshot(of: snapshot, as: .lines)
    }

    private func describeParse(_ value: String, formatter: SignificantDigitsFormatStyle) -> String {
        do {
            return "\(value) -> \(try formatter.parse(value))"
        } catch {
            return "\(value) -> \(type(of: error))"
        }
    }
}

#if canImport(UIKit)
import UIKit

extension PocketCastsUtilsLogicSnapshotTests {
    func testUIColorHexAndOverlayMatrix() {
        let colors = [
            "#F30",
            "#8F30",
            "#336699",
            "#CC336699",
        ]
        .map { value -> String in
            let color = UIColor(hex: value)
            return "\(value) -> \(color.hexString()) \(describe(color.getRGBA()))"
        }

        let overlay = UIColor.calculateColor(
            orgColor: UIColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1),
            overlayColor: UIColor(red: 1, green: 0.1, blue: 0.1, alpha: 0.35)
        )

        let snapshot = """
        parsed colors
        \(colors.joined(separator: "\n"))

        overlay
        \(overlay.hexString()) \(describe(overlay.getRGBA()))
        """

        assertSnapshot(of: snapshot, as: .lines)
    }

    private func describe(_ components: [Double]) -> String {
        let values = components.map { String(format: "%.3f", $0) }
        return "[\(values.joined(separator: ", "))]"
    }
}
#endif
