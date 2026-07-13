import PocketCastsDataModel
import XCTest

@testable import podcasts

/// Table-driven coverage of the deterministic prompt parser: each phrase runs
/// through `PlaylistPromptRuleParser` and `applied(to:podcasts:)`, and the
/// resulting `EpisodeFilter` fields are compared against expectations.
final class PlaylistPromptRuleParserTests: XCTestCase {

    private let candidates: [PodcastMatchCandidate] = [
        PodcastMatchCandidate(uuid: "uuid-daily", title: "The Daily"),
        PodcastMatchCandidate(uuid: "uuid-hardfork", title: "Hard Fork"),
        PodcastMatchCandidate(uuid: "uuid-acquired", title: "Acquired")
    ]

    /// Mirrors the `PlaylistManager.createNewPlaylist()` all-inclusive defaults
    /// without touching the database.
    private func baseFilter() -> EpisodeFilter {
        var filter = EpisodeFilter()
        filter.uuid = "base-uuid"
        filter.filterAllPodcasts = true
        filter.filterUnplayed = true
        filter.filterPartiallyPlayed = true
        filter.filterFinished = true
        filter.filterDownloaded = true
        filter.filterNotDownloaded = true
        filter.filterAudioVideoType = AudioVideoFilter.all.rawValue
        return filter
    }

    /// Expected `EpisodeFilter` fields; defaults match the all-inclusive base.
    private struct Expected {
        var unplayed = true
        var partiallyPlayed = true
        var finished = true
        var downloaded = true
        var notDownloaded = true
        var audioVideoType = AudioVideoFilter.all.rawValue
        var starred = false
        var filterDuration = false
        var longerThan: Int32 = 0
        var shorterThan: Int32 = 0
        var filterHours: Int32 = 0
        var allPodcasts = true
        var podcastUuids = ""
    }

    func testPhraseTable() {
        struct Row {
            let phrase: String
            let expected: Expected
        }

        let rows: [Row] = [
            // Play state
            Row(phrase: "unplayed episodes",
                expected: Expected(unplayed: true, partiallyPlayed: false, finished: false)),
            Row(phrase: "episodes I haven't listened to",
                expected: Expected(unplayed: true, partiallyPlayed: false, finished: false)),
            Row(phrase: "episodes in progress",
                expected: Expected(unplayed: false, partiallyPlayed: true, finished: false)),
            Row(phrase: "finished episodes",
                expected: Expected(unplayed: false, partiallyPlayed: false, finished: true)),
            Row(phrase: "episodes I already played",
                expected: Expected(unplayed: false, partiallyPlayed: false, finished: true)),

            // Download state
            Row(phrase: "downloaded episodes",
                expected: Expected(downloaded: true, notDownloaded: false)),
            Row(phrase: "episodes not downloaded yet",
                expected: Expected(downloaded: false, notDownloaded: true)),

            // Media type
            Row(phrase: "video episodes",
                expected: Expected(audioVideoType: AudioVideoFilter.videoOnly.rawValue)),
            Row(phrase: "audio only episodes",
                expected: Expected(audioVideoType: AudioVideoFilter.audioOnly.rawValue)),

            // Starred
            Row(phrase: "starred episodes",
                expected: Expected(starred: true)),
            Row(phrase: "my favorites",
                expected: Expected(starred: true)),

            // Duration ("under N min" / "over N min" per the plan's keyword table)
            Row(phrase: "episodes under 30 minutes",
                expected: Expected(filterDuration: true, longerThan: 0, shorterThan: 30)),
            Row(phrase: "episodes over 1 hour",
                expected: Expected(filterDuration: true, longerThan: 60, shorterThan: 600)),
            Row(phrase: "episodes between 20 and 40 minutes",
                expected: Expected(filterDuration: true, longerThan: 20, shorterThan: 40)),
            Row(phrase: "episodes shorter than half an hour",
                expected: Expected(filterDuration: true, longerThan: 0, shorterThan: 30)),

            // Release window ("today/this week/past month" -> nearest bucket)
            Row(phrase: "episodes from today",
                expected: Expected(filterHours: 24)),
            Row(phrase: "new episodes from this week",
                expected: Expected(filterHours: 168)),
            Row(phrase: "episodes from the past month",
                expected: Expected(filterHours: 744)),
            // 240h snaps to the nearest ReleaseDateFilterOption bucket (168)
            Row(phrase: "episodes from the last 10 days",
                expected: Expected(filterHours: 168)),

            // Podcast names (quoted and unquoted)
            Row(phrase: "episodes from \"The Daily\"",
                expected: Expected(allPodcasts: false, podcastUuids: "uuid-daily")),
            Row(phrase: "unplayed episodes under 30 minutes from The Daily this week",
                expected: Expected(
                    unplayed: true, partiallyPlayed: false, finished: false,
                    filterDuration: true, longerThan: 0, shorterThan: 30,
                    filterHours: 168,
                    allPodcasts: false, podcastUuids: "uuid-daily"
                )),

            // Ambiguity -> all-inclusive defaults
            Row(phrase: "play me something fun",
                expected: Expected())
        ]

        XCTAssertGreaterThanOrEqual(rows.count, 15, "the plan requires at least 15 table rows")

        let parser = PlaylistPromptRuleParser()
        for row in rows {
            let draft = parser.draft(from: row.phrase)
            let filter = draft.applied(to: baseFilter(), podcasts: candidates).filter
            let expected = row.expected

            XCTAssertEqual(filter.filterUnplayed, expected.unplayed, "\(row.phrase): filterUnplayed")
            XCTAssertEqual(filter.filterPartiallyPlayed, expected.partiallyPlayed, "\(row.phrase): filterPartiallyPlayed")
            XCTAssertEqual(filter.filterFinished, expected.finished, "\(row.phrase): filterFinished")
            XCTAssertEqual(filter.filterDownloaded, expected.downloaded, "\(row.phrase): filterDownloaded")
            XCTAssertEqual(filter.filterNotDownloaded, expected.notDownloaded, "\(row.phrase): filterNotDownloaded")
            XCTAssertEqual(filter.filterAudioVideoType, expected.audioVideoType, "\(row.phrase): filterAudioVideoType")
            XCTAssertEqual(filter.filterStarred, expected.starred, "\(row.phrase): filterStarred")
            XCTAssertEqual(filter.filterDuration, expected.filterDuration, "\(row.phrase): filterDuration")
            XCTAssertEqual(filter.longerThan, expected.longerThan, "\(row.phrase): longerThan")
            XCTAssertEqual(filter.shorterThan, expected.shorterThan, "\(row.phrase): shorterThan")
            XCTAssertEqual(filter.filterHours, expected.filterHours, "\(row.phrase): filterHours")
            XCTAssertEqual(filter.filterAllPodcasts, expected.allPodcasts, "\(row.phrase): filterAllPodcasts")
            XCTAssertEqual(filter.podcastUuids, expected.podcastUuids, "\(row.phrase): podcastUuids")
        }
    }

    // MARK: - Smart rule chip flags

    func testTransientSmartRuleFlagsFollowParsedRules() {
        let parser = PlaylistPromptRuleParser()
        let phrase = "unplayed downloaded audio episodes under 30 minutes from \"The Daily\" this week"
        let filter = parser.draft(from: phrase).applied(to: baseFilter(), podcasts: candidates).filter

        XCTAssertTrue(filter.episodesSmartRuleApplied)
        XCTAssertTrue(filter.downloadStatusSmartRuleApplied)
        XCTAssertTrue(filter.mediaTypeSmartRuleApplied)
        XCTAssertTrue(filter.releaseDateSmartRuleApplied)
        XCTAssertTrue(filter.podcastSmartRuleApplied)
        XCTAssertTrue(filter.filterDuration)
    }

    func testAmbiguousPromptAppliesNoSmartRules() {
        let parser = PlaylistPromptRuleParser()
        let application = parser.draft(from: "surprise me").applied(to: baseFilter(), podcasts: candidates)

        XCTAssertEqual(application.appliedRuleCount, 0)
        XCTAssertFalse(application.filter.episodesSmartRuleApplied)
        XCTAssertFalse(application.filter.downloadStatusSmartRuleApplied)
        XCTAssertFalse(application.filter.mediaTypeSmartRuleApplied)
        XCTAssertFalse(application.filter.releaseDateSmartRuleApplied)
        XCTAssertFalse(application.filter.podcastSmartRuleApplied)
    }

    // MARK: - Name extraction details

    func testQuotedNamesWinOverAttributedDuplicates() {
        let draft = PlaylistPromptRuleParser().draft(from: "episodes from \"Hard Fork\" and from hard fork")
        XCTAssertEqual(draft.podcastNames, ["Hard Fork"], "case-insensitive duplicate collapses onto the quoted form")
    }

    func testMultipleAttributedNamesSplitOnAnd() {
        let draft = PlaylistPromptRuleParser().draft(from: "episodes from The Daily and Hard Fork")
        XCTAssertEqual(draft.podcastNames, ["The Daily", "Hard Fork"])
    }

    func testTimeExpressionsAreNotPodcastNames() {
        let draft = PlaylistPromptRuleParser().draft(from: "episodes from this week and from the past month")
        XCTAssertEqual(draft.podcastNames, [])
        XCTAssertEqual(draft.releaseWindowHours, 168, "the first window mention wins")
    }
}
