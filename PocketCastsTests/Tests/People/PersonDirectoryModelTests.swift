import PocketCastsDataModel
import XCTest

@testable import podcasts

final class PersonDirectoryModelTests: XCTestCase {

    private func record(episode: String, podcast: String? = "pod-1", names: [String: String]?) -> EpisodeTranscriptionRecord {
        var record = EpisodeTranscriptionRecord()
        record.episodeUuid = episode
        record.podcastUuid = podcast
        record.status = TranscriptionStatus.completed.rawValue
        if let names,
           let data = try? JSONEncoder().encode(names) {
            record.speakerNames = String(data: data, encoding: .utf8)
        }
        return record
    }

    func testAggregatesRenamesByExactDisplayName() {
        let records = [
            record(episode: "ep-1", names: ["Speaker 1": "Alice", "Speaker 2": "Bob"]),
            record(episode: "ep-2", names: ["Speaker 3": "Alice "]),
            record(episode: "ep-3", names: ["Speaker 1": "Carol"])
        ]

        let entries = PersonDirectoryBuilder.entries(from: records, episodeExists: { _ in true })

        XCTAssertEqual(entries.map(\.displayName), ["Alice", "Bob", "Carol"],
                       "most appearances first, then alphabetical; whitespace-trimmed names merge")
        let alice = entries[0]
        XCTAssertEqual(alice.appearances.count, 2)
        XCTAssertEqual(Set(alice.appearances.map(\.episodeUuid)), ["ep-1", "ep-2"])
        XCTAssertEqual(alice.appearances.first { $0.episodeUuid == "ep-2" }?.canonicalSpeaker, "Speaker 3",
                       "the canonical label rides along for segment scoping")
    }

    func testDropsAppearancesWhoseEpisodeIsGone() {
        let records = [
            record(episode: "ep-live", names: ["Speaker 1": "Alice"]),
            record(episode: "ep-gone", names: ["Speaker 1": "Alice", "Speaker 2": "Ghost"])
        ]

        let entries = PersonDirectoryBuilder.entries(from: records, episodeExists: { $0 == "ep-live" })

        XCTAssertEqual(entries.map(\.displayName), ["Alice"])
        XCTAssertEqual(entries[0].appearances.map(\.episodeUuid), ["ep-live"])
    }

    func testIgnoresEmptyNamesAndRecordsWithoutRenames() {
        let records = [
            record(episode: "ep-1", names: ["Speaker 1": "  ", "Speaker 2": ""]),
            record(episode: "ep-2", names: nil)
        ]
        XCTAssertTrue(PersonDirectoryBuilder.entries(from: records, episodeExists: { _ in true }).isEmpty)
    }

    func testSameNameDifferentEpisodesShareOneEntry() {
        // The documented v1 trade-off: identity IS the display name.
        let records = [
            record(episode: "ep-1", podcast: "pod-a", names: ["Speaker 1": "John Smith"]),
            record(episode: "ep-2", podcast: "pod-b", names: ["Speaker 4": "John Smith"])
        ]
        let entries = PersonDirectoryBuilder.entries(from: records, episodeExists: { _ in true })
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(Set(entries[0].appearances.map(\.podcastUuid)), ["pod-a", "pod-b"])
    }
}
