@testable import PocketCastsDataModel
@testable import PocketCastsUtils
import XCTest

/// Coverage for the Mentioned Entity substrate (migration 89, Highlights S10).
final class MentionedEntityDataManagerTests: DataManagerTestCase {
    private func record(kind: MentionedEntityKind = .book, name: String,
                        podcastUuid: String? = "pod-1", startTime: Double? = nil) -> MentionedEntityRecord {
        var record = MentionedEntityRecord()
        record.kind = kind.rawValue
        record.canonicalKey = name.foldedEntityKey
        record.displayName = name
        record.podcastUuid = podcastUuid
        record.startTime = startTime
        record.createdAt = 1000
        return record
    }

    func testAggregatesAcrossEpisodesAndShowsUnderOneFoldedKey() throws {
        try runWithBothImplementations { dataManager, impl in
            // Same book cited with different casing/diacritics across shows.
            dataManager.mentionedEntities.replace(episodeUuid: "ep-1", source: .mention,
                                                  entities: [record(name: "Thinking, Fast and Slow")])
            dataManager.mentionedEntities.replace(episodeUuid: "ep-2", source: .mention,
                                                  entities: [record(name: "THINKING, FAST AND SLOW", podcastUuid: "pod-2")])
            dataManager.mentionedEntities.replace(episodeUuid: "ep-3", source: .mention,
                                                  entities: [record(name: "Antifragile")])

            let books = dataManager.mentionedEntities.entitiesAcrossLibrary(kind: .book)

            XCTAssertEqual(books.count, 2, "\(impl): folded keys merge case variants")
            XCTAssertEqual(books.first?.canonicalKey, "thinking, fast and slow".foldedEntityKey, "\(impl)")
            XCTAssertEqual(books.first?.episodeCount, 2, "\(impl)")
            XCTAssertEqual(books.first?.podcastCount, 2, "\(impl)")
        }
    }

    func testReplaceIsScopedToEpisodeAndSource() throws {
        try runWithBothImplementations { dataManager, impl in
            dataManager.mentionedEntities.replace(episodeUuid: "ep-1", source: .credit,
                                                  entities: [record(kind: .person, name: "Ada Lovelace")])
            dataManager.mentionedEntities.replace(episodeUuid: "ep-1", source: .speaker,
                                                  entities: [record(kind: .person, name: "Ada Lovelace")])

            // Regenerating credits must not touch the speaker rows.
            dataManager.mentionedEntities.replace(episodeUuid: "ep-1", source: .credit, entities: [])

            let appearances = dataManager.mentionedEntities.appearances(
                kind: .person, canonicalKey: "Ada Lovelace".foldedEntityKey)
            XCTAssertEqual(appearances.map(\.source), [MentionedEntitySource.speaker.rawValue], "\(impl)")
        }
    }

    func testMostCitedIsPerShow() throws {
        try runWithBothImplementations { dataManager, impl in
            dataManager.mentionedEntities.replace(episodeUuid: "ep-1", source: .mention,
                                                  entities: [record(name: "Book A"), record(name: "Book B")])
            dataManager.mentionedEntities.replace(episodeUuid: "ep-2", source: .mention,
                                                  entities: [record(name: "Book A")])
            dataManager.mentionedEntities.replace(episodeUuid: "ep-9", source: .mention,
                                                  entities: [record(name: "Book C", podcastUuid: "pod-other")])

            let top = dataManager.mentionedEntities.mostCited(kind: .book, podcastUuid: "pod-1")

            XCTAssertEqual(top.map(\.displayName), ["Book A", "Book B"], "\(impl)")
            XCTAssertEqual(top.first?.episodeCount, 2, "\(impl)")
        }
    }

    func testShowsYouFollowMentioningLine() throws {
        try runWithBothImplementations { dataManager, impl in
            dataManager.mentionedEntities.replace(episodeUuid: "ep-1", source: .mention,
                                                  entities: [record(name: "Book A")])
            dataManager.mentionedEntities.replace(episodeUuid: "ep-2", source: .mention,
                                                  entities: [record(name: "Book A", podcastUuid: "pod-2")])

            let shows = dataManager.mentionedEntities.podcastUuidsMentioning(
                kind: .book, canonicalKey: "Book A".foldedEntityKey, within: ["pod-1", "pod-3"])

            XCTAssertEqual(shows, ["pod-1"], "\(impl): only shows in the given set count")
        }
    }

    func testFoldedEntityKeyRules() {
        XCTAssertEqual("  Ada  Lovelace ".foldedEntityKey, "ada lovelace")
        XCTAssertEqual("Ada Lovelace".foldedEntityKey, "ADA LOVELACE".foldedEntityKey)
        XCTAssertEqual("José Piñera".foldedEntityKey, "jose pinera")
        XCTAssertEqual("".foldedEntityKey, "")
    }
}
