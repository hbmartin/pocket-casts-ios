import PocketCastsDataModel
import XCTest

@testable import podcasts

final class TranscriptWindowBuilderTests: XCTestCase {

    private func segment(_ index: Int, chars: Int, start: Double? = nil) -> TranscriptSearchSegment {
        TranscriptSearchSegment(
            index: index,
            text: String(repeating: "a", count: chars),
            startTime: start ?? Double(index) * 10,
            endTime: (start ?? Double(index) * 10) + 9
        )
    }

    func testEmptyInputProducesNoWindows() {
        XCTAssertTrue(TranscriptWindowBuilder.windows(from: []).isEmpty)
    }

    func testSegmentsAccumulateToTargetSize() {
        // 8 segments × 300 chars: each window takes ~4 segments to pass 1000.
        let segments = (0 ..< 8).map { segment($0, chars: 300) }
        let windows = TranscriptWindowBuilder.windows(from: segments)

        XCTAssertGreaterThan(windows.count, 1)
        for window in windows {
            XCTAssertGreaterThanOrEqual(window.text.count, TranscriptWindowBuilder.minimumCharacters)
        }
        XCTAssertEqual(windows.first?.startSegmentIndex, 0)
        XCTAssertEqual(windows.last?.endSegmentIndex, 7, "coverage reaches the final segment")
        XCTAssertEqual(windows.map(\.windowIndex), Array(0 ..< windows.count), "ordinals are dense")
    }

    func testConsecutiveWindowsOverlap() {
        let segments = (0 ..< 12).map { segment($0, chars: 300) }
        let windows = TranscriptWindowBuilder.windows(from: segments)
        guard windows.count >= 2 else {
            XCTFail("expected multiple windows")
            return
        }
        for (previous, next) in zip(windows, windows.dropFirst()) {
            XCTAssertLessThanOrEqual(next.startSegmentIndex, previous.endSegmentIndex,
                                     "each window re-covers the tail of its predecessor")
            XCTAssertGreaterThan(next.endSegmentIndex, previous.endSegmentIndex, "windows still make progress")
        }
    }

    func testSingleGiantSegmentIsOneWindow() {
        let windows = TranscriptWindowBuilder.windows(from: [segment(0, chars: 5000)])
        XCTAssertEqual(windows.count, 1)
        XCTAssertEqual(windows[0].startSegmentIndex, 0)
        XCTAssertEqual(windows[0].endSegmentIndex, 0)
    }

    func testRuntTailMergesIntoPreviousWindow() {
        // A full window followed by a tiny fragment: the fragment must not
        // stand alone.
        let segments = [segment(0, chars: 1100), segment(1, chars: 30)]
        let windows = TranscriptWindowBuilder.windows(from: segments)

        XCTAssertEqual(windows.count, 1)
        XCTAssertEqual(windows[0].endSegmentIndex, 1)
    }

    func testWindowTimesSpanTheirSegments() {
        let segments = (0 ..< 4).map { segment($0, chars: 400) }
        let windows = TranscriptWindowBuilder.windows(from: segments)
        let first = windows[0]
        XCTAssertEqual(first.startTime, 0)
        XCTAssertNotNil(first.endTime)
    }

    func testPreviewCutsAtWordBoundary() {
        let text = Array(repeating: "word", count: 100).joined(separator: " ")
        let preview = TranscriptWindowBuilder.preview(of: text)
        XCTAssertLessThanOrEqual(preview.count, TranscriptWindowBuilder.previewCharacters)
        XCTAssertTrue(preview.split(separator: " ").allSatisfy { $0 == "word" })
        XCTAssertEqual(TranscriptWindowBuilder.preview(of: "short"), "short")
    }
}
