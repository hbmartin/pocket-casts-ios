import UIKit
import XCTest

@testable import podcasts

/// Progressive chapter metadata pushed mid-stream (AVPlayerItemMetadataOutput →
/// `ChapterManager.ingestStreamedMetadata`): synthetic chapter growth for
/// chapterless streams, boundary closing, re-announce dedupe and artwork/title
/// gap-filling.
@MainActor
final class ChapterManagerStreamedMetadataTests: XCTestCase {
    private var artworkData: Data {
        UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2)).pngData { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        }
    }

    func testSyntheticChaptersGrowAndCloseAtBoundaries() {
        let manager = ChapterManager()

        manager.ingestStreamedMetadata(title: "Intro", artworkData: nil, at: 0)
        manager.ingestStreamedMetadata(title: "Topic One", artworkData: nil, at: 60)
        manager.ingestStreamedMetadata(title: "Topic Two", artworkData: nil, at: 200)

        XCTAssertEqual(manager.visibleChapterCount(), 3)
        XCTAssertEqual(manager.chaptersOrigin, .streamedMetadata)
        XCTAssertEqual(manager.chapterAt(index: 0)?.title, "Intro")
        XCTAssertEqual(manager.chapterAt(index: 0)?.duration, 60, "The next boundary closes the open-ended chapter")
        XCTAssertEqual(manager.chapterAt(index: 1)?.duration, 140)
        XCTAssertEqual(manager.chapterAt(index: 2)?.duration, .greatestFiniteMagnitude, "The last chapter stays open-ended")
    }

    func testReAnnouncedBoundaryUpdatesInsteadOfAppending() {
        let manager = ChapterManager()

        manager.ingestStreamedMetadata(title: "Intro", artworkData: nil, at: 0)
        // Seeks and output resets re-push the current group at (nearly) the same time.
        manager.ingestStreamedMetadata(title: "Ignored", artworkData: artworkData, at: 0.2)

        XCTAssertEqual(manager.visibleChapterCount(), 1)
        XCTAssertEqual(manager.chapterAt(index: 0)?.title, "Intro", "An existing title is never overwritten")
        XCTAssertNotNil(manager.chapterAt(index: 0)?.image, "The re-announce may still fill missing artwork")
    }

    func testMetadataFillsGapsInTheChapterAtThatTime() {
        let manager = ChapterManager()
        manager.ingestStreamedMetadata(title: "", artworkData: nil, at: 0)

        XCTAssertEqual(manager.visibleChapterCount(), 0, "Groups with neither title nor artwork are ignored")

        manager.ingestStreamedMetadata(title: "Intro", artworkData: nil, at: 0)
        manager.ingestStreamedMetadata(title: nil, artworkData: artworkData, at: 30)

        XCTAssertEqual(manager.visibleChapterCount(), 1, "Mid-chapter artwork must not create a new boundary")
        XCTAssertNotNil(manager.chapterAt(index: 0)?.image)
    }

    func testOutOfOrderMetadataIsIgnoredForSyntheticLists() {
        let manager = ChapterManager()

        manager.ingestStreamedMetadata(title: "Late", artworkData: nil, at: 120)
        manager.ingestStreamedMetadata(title: "Earlier", artworkData: nil, at: 20)

        XCTAssertEqual(manager.visibleChapterCount(), 1, "A boundary before the last one must not append")
    }
}
