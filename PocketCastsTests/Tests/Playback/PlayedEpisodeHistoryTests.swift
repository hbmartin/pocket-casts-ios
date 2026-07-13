import XCTest

@testable import podcasts

@MainActor
final class PlayedEpisodeHistoryTests: XCTestCase {
    func testPopReturnsMostRecentFirst() {
        var history = PlayedEpisodeHistory()

        history.record(uuid: "a")
        history.record(uuid: "b")
        history.record(uuid: "c")

        XCTAssertEqual(history.popPrevious(), "c")
        XCTAssertEqual(history.popPrevious(), "b")
        XCTAssertEqual(history.popPrevious(), "a")
        XCTAssertNil(history.popPrevious())
    }

    func testConsecutiveDuplicatesAreCollapsed() {
        var history = PlayedEpisodeHistory()

        history.record(uuid: "a")
        history.record(uuid: "a")
        history.record(uuid: "b")
        history.record(uuid: "b")

        XCTAssertEqual(history.uuids, ["a", "b"])
    }

    func testNonConsecutiveDuplicatesAreKept() {
        var history = PlayedEpisodeHistory()

        history.record(uuid: "a")
        history.record(uuid: "b")
        history.record(uuid: "a")

        XCTAssertEqual(history.uuids, ["a", "b", "a"])
    }

    func testCapacityDropsOldestEntries() {
        var history = PlayedEpisodeHistory(capacity: 20)

        for index in 0..<25 {
            history.record(uuid: "episode-\(index)")
        }

        XCTAssertEqual(history.uuids.count, 20)
        XCTAssertEqual(history.popPrevious(), "episode-24", "Most recent entry should survive")
        XCTAssertEqual(history.uuids.first, "episode-5", "The oldest entries should have been dropped")
    }

    func testRemoveAllEmptiesTheHistory() {
        var history = PlayedEpisodeHistory()

        history.record(uuid: "a")
        history.record(uuid: "b")
        history.removeAll()

        XCTAssertTrue(history.isEmpty)
        XCTAssertNil(history.popPrevious())
    }

    func testDefaultCapacityIsTwenty() {
        XCTAssertEqual(PlayedEpisodeHistory().capacity, 20)
    }
}
