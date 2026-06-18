import XCTest

@testable import PocketCastsDataModel
@testable import podcasts

final class HomeGridItemTests: XCTestCase {
    func testPodcastItemID() {
        let podcast = PodcastBuilder().build()
        XCTAssertEqual(HomeGridItem(podcast: podcast).id, .podcast(podcast.uuid))
    }

    func testFolderItemID() {
        let folder = FolderBuilder().build()
        XCTAssertEqual(HomeGridItem(folder: folder).id, .folder(folder.uuid))
    }

    func testSameUUIDAcrossKindsYieldsDistinctIDs() {
        let uuid = NSUUID().uuidString
        let podcast = PodcastBuilder().build()
        podcast.uuid = uuid
        var folder = FolderBuilder().build()
        folder.uuid = uuid

        XCTAssertNotEqual(HomeGridItem(podcast: podcast).id, HomeGridItem(folder: folder).id)
    }

    func testDifferentPodcastsYieldDistinctIDs() {
        let first = PodcastBuilder().build()
        let second = PodcastBuilder().build()

        XCTAssertNotEqual(HomeGridItem(podcast: first).id, HomeGridItem(podcast: second).id)
    }
}
