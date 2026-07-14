import UIKit
import XCTest

@testable import podcasts

/// Remote chapter artwork resolution (P2-21): fetch attempts are deduped by
/// URL, so a successful fetch must land in every chapter sharing that URL —
/// filling only the chapter that triggered the fetch leaves later same-URL
/// chapters imageless forever (the URL is already in the attempted set and is
/// never retried).
@MainActor
final class ChapterManagerArtworkTests: XCTestCase {
    private func makeImage(_ color: UIColor) -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2)).image { context in
            color.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        }
    }

    /// Grows a synthetic chapter list (no artwork URLs of its own) and stamps
    /// the given artwork URLs onto it, chapter by chapter.
    private func makeManager(imageURLs: [URL?]) -> ChapterManager {
        let manager = ChapterManager()
        for (index, url) in imageURLs.enumerated() {
            manager.ingestStreamedMetadata(title: "Chapter \(index)", artworkData: nil, at: TimeInterval(index) * 100)
            manager.chapterAt(index: index)?.imageURL = url
        }
        return manager
    }

    func testFetchedArtworkFillsEveryChapterSharingTheURL() throws {
        let shared = try XCTUnwrap(URL(string: "https://example.com/art.jpg"))
        let other = try XCTUnwrap(URL(string: "https://example.com/other.jpg"))
        let manager = makeManager(imageURLs: [shared, shared, other])

        manager.applyFetchedArtwork(makeImage(.red), for: shared)

        XCTAssertNotNil(manager.chapterAt(index: 0)?.image)
        XCTAssertNotNil(manager.chapterAt(index: 1)?.image,
                        "Later chapters sharing the URL must be filled too — their fetch is deduped away")
        XCTAssertNil(manager.chapterAt(index: 2)?.image, "Chapters with a different artwork URL are untouched")
    }

    func testFetchedArtworkDoesNotOverwriteExistingImages() throws {
        let url = try XCTUnwrap(URL(string: "https://example.com/art.jpg"))
        let manager = makeManager(imageURLs: [url, url])

        let embedded = makeImage(.blue)
        manager.chapterAt(index: 0)?.image = embedded

        manager.applyFetchedArtwork(makeImage(.red), for: url)

        XCTAssertTrue(manager.chapterAt(index: 0)?.image === embedded,
                      "Embedded/previously fetched artwork always wins over a remote fetch")
        XCTAssertNotNil(manager.chapterAt(index: 1)?.image)
    }
}
