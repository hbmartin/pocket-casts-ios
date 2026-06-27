import XCTest
@testable import podcasts

@MainActor
final class PlaylistCellViewModelTests: XCTestCase {

    // distinctPodcasts keeps the first episode of each distinct podcast up to `limit`. If there are
    // fewer distinct podcasts than the limit (but at least one), it collapses to just the first.

    func testReturnsLimitWhenMoreDistinctThanLimit() {
        let result = PlaylistCellViewModel.distinctPodcasts(from: ["A", "B", "C", "D", "E"], limit: 4) { $0 }
        XCTAssertEqual(result, ["A", "B", "C", "D"])
    }

    func testReturnsAllWhenExactlyLimitDistinct() {
        let result = PlaylistCellViewModel.distinctPodcasts(from: ["A", "B", "C", "D"], limit: 4) { $0 }
        XCTAssertEqual(result, ["A", "B", "C", "D"])
    }

    func testDeduplicatesKeepingFirstOccurrence() {
        let result = PlaylistCellViewModel.distinctPodcasts(from: ["A", "A", "B", "C", "D", "E"], limit: 4) { $0 }
        XCTAssertEqual(result, ["A", "B", "C", "D"], "duplicates collapse, first occurrence wins")
    }

    func testCollapsesToFirstWhenFewerDistinctThanLimit() {
        XCTAssertEqual(PlaylistCellViewModel.distinctPodcasts(from: ["A", "A", "B"], limit: 4) { $0 }, ["A"])
        XCTAssertEqual(PlaylistCellViewModel.distinctPodcasts(from: ["A", "B", "C"], limit: 4) { $0 }, ["A"])
    }

    func testEmptyReturnsEmpty() {
        XCTAssertEqual(PlaylistCellViewModel.distinctPodcasts(from: [String](), limit: 4) { $0 }, [])
    }

    func testLimitOfOne() {
        XCTAssertEqual(PlaylistCellViewModel.distinctPodcasts(from: ["A", "B"], limit: 1) { $0 }, ["A"])
    }

    func testUsesPodcastUuidKeyForCustomType() {
        struct Ep { let id: String; let podcast: String }
        let episodes = [
            Ep(id: "e1", podcast: "P1"),
            Ep(id: "e2", podcast: "P1"),
            Ep(id: "e3", podcast: "P2"),
            Ep(id: "e4", podcast: "P3"),
            Ep(id: "e5", podcast: "P4"),
            Ep(id: "e6", podcast: "P5"),
        ]
        let result = PlaylistCellViewModel.distinctPodcasts(from: episodes, limit: 4) { $0.podcast }
        XCTAssertEqual(result.map(\.id), ["e1", "e3", "e4", "e5"], "first episode of each of the first 4 distinct podcasts")
    }
}
