import PocketCastsDataModel
import XCTest

@testable import podcasts

/// Covers `PlaylistPromptDraft.applied(to:podcasts:)`: rule mapping onto
/// `EpisodeFilter` fields and fuse-swift fuzzy matching of mentioned show names.
final class PlaylistPromptDraftApplicationTests: XCTestCase {

    private let candidates: [PodcastMatchCandidate] = [
        PodcastMatchCandidate(uuid: "uuid-daily", title: "The Daily"),
        PodcastMatchCandidate(uuid: "uuid-hardfork", title: "Hard Fork"),
        PodcastMatchCandidate(uuid: "uuid-acquired", title: "Acquired"),
        PodcastMatchCandidate(uuid: "uuid-99pi", title: "99% Invisible")
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

    private func draft(
        playedState: PlaylistPromptDraft.PlayedState = .any,
        downloadState: PlaylistPromptDraft.DownloadState = .any,
        mediaType: PlaylistPromptDraft.MediaKind = .any,
        starredOnly: Bool = false,
        longerThanMinutes: Int? = nil,
        shorterThanMinutes: Int? = nil,
        releaseWindowHours: Int? = nil,
        podcastNames: [String] = [],
        suggestedName: String? = nil
    ) -> PlaylistPromptDraft {
        PlaylistPromptDraft(
            playedState: playedState,
            downloadState: downloadState,
            mediaType: mediaType,
            starredOnly: starredOnly,
            longerThanMinutes: longerThanMinutes,
            shorterThanMinutes: shorterThanMinutes,
            releaseWindowHours: releaseWindowHours,
            podcastNames: podcastNames,
            suggestedName: suggestedName
        )
    }

    // MARK: - Fuzzy matching fixtures

    func testExactTitleMatchIsCaseInsensitive() {
        let application = draft(podcastNames: ["the daily"]).applied(to: baseFilter(), podcasts: candidates)

        XCTAssertEqual(application.filter.podcastUuids, "uuid-daily")
        XCTAssertFalse(application.filter.filterAllPodcasts)
        XCTAssertTrue(application.filter.podcastSmartRuleApplied)
        XCTAssertTrue(application.unmatchedPodcastNames.isEmpty)
    }

    func testPartialNameMatchesContainingTitle() {
        let application = draft(podcastNames: ["Daily"]).applied(to: baseFilter(), podcasts: candidates)

        XCTAssertEqual(application.filter.podcastUuids, "uuid-daily")
    }

    func testMisspelledNamesFuzzyMatch() {
        let application = draft(podcastNames: ["The Dialy", "Aquired"]).applied(to: baseFilter(), podcasts: candidates)

        XCTAssertEqual(application.filter.podcastUuids, "uuid-daily,uuid-acquired")
        XCTAssertTrue(application.unmatchedPodcastNames.isEmpty)
    }

    func testUnmatchedNamesAreSurfacedAndAllPodcastsKept() {
        let application = draft(podcastNames: ["Zebra Quantum Xylophone"]).applied(to: baseFilter(), podcasts: candidates)

        XCTAssertEqual(application.unmatchedPodcastNames, ["Zebra Quantum Xylophone"])
        XCTAssertTrue(application.filter.filterAllPodcasts, "no matches leaves the all-podcasts default")
        XCTAssertEqual(application.filter.podcastUuids, "")
        XCTAssertFalse(application.filter.podcastSmartRuleApplied)
    }

    func testMixedMatchAppliesMatchesAndSurfacesTheRest() {
        let application = draft(podcastNames: ["Hard Fork", "Zebra Quantum Xylophone"])
            .applied(to: baseFilter(), podcasts: candidates)

        XCTAssertEqual(application.filter.podcastUuids, "uuid-hardfork")
        XCTAssertFalse(application.filter.filterAllPodcasts)
        XCTAssertEqual(application.unmatchedPodcastNames, ["Zebra Quantum Xylophone"])
    }

    func testDuplicateNamesDeduplicateInTheCSV() {
        let application = draft(podcastNames: ["The Daily", "the daily"]).applied(to: baseFilter(), podcasts: candidates)

        XCTAssertEqual(application.filter.podcastUuids, "uuid-daily")
    }

    func testEmptyLibraryLeavesEveryNameUnmatched() {
        let application = draft(podcastNames: ["The Daily"]).applied(to: baseFilter(), podcasts: [])

        XCTAssertEqual(application.unmatchedPodcastNames, ["The Daily"])
        XCTAssertTrue(application.filter.filterAllPodcasts)
    }

    // MARK: - Rule mapping

    func testDurationWithOnlyUpperBoundKeepsZeroLowerBound() {
        let filter = draft(shorterThanMinutes: 30).applied(to: baseFilter(), podcasts: []).filter

        XCTAssertTrue(filter.filterDuration)
        XCTAssertEqual(filter.longerThan, 0)
        XCTAssertEqual(filter.shorterThan, 30)
    }

    func testDurationWithOnlyLowerBoundUsesTenHourCap() {
        let filter = draft(longerThanMinutes: 45).applied(to: baseFilter(), podcasts: []).filter

        XCTAssertTrue(filter.filterDuration)
        XCTAssertEqual(filter.longerThan, 45)
        XCTAssertEqual(filter.shorterThan, Int32(PlaylistPromptDraft.maxDurationMinutes))
    }

    func testReleaseWindowSnapsToNearestBucketOnApplication() {
        let filter = draft(releaseWindowHours: 100).applied(to: baseFilter(), podcasts: []).filter

        XCTAssertEqual(filter.filterHours, 72, "100h is nearer the 3-day bucket than the week bucket")
        XCTAssertTrue(filter.releaseDateSmartRuleApplied)
    }

    func testAppliedRuleCountCountsEachRuleGroupOnce() {
        let application = draft(
            playedState: .unplayed,
            downloadState: .downloaded,
            mediaType: .audio,
            starredOnly: true,
            longerThanMinutes: 10,
            shorterThanMinutes: 30,
            releaseWindowHours: 168,
            podcastNames: ["The Daily"]
        ).applied(to: baseFilter(), podcasts: candidates)

        XCTAssertEqual(application.appliedRuleCount, 7)
    }

    func testAllInclusiveDraftChangesNothing() {
        let base = baseFilter()
        let application = draft().applied(to: base, podcasts: candidates)

        XCTAssertEqual(application.appliedRuleCount, 0)
        XCTAssertEqual(application.filter.filterAllPodcasts, base.filterAllPodcasts)
        XCTAssertEqual(application.filter.filterUnplayed, base.filterUnplayed)
        XCTAssertEqual(application.filter.filterPartiallyPlayed, base.filterPartiallyPlayed)
        XCTAssertEqual(application.filter.filterFinished, base.filterFinished)
        XCTAssertEqual(application.filter.filterDownloaded, base.filterDownloaded)
        XCTAssertEqual(application.filter.filterNotDownloaded, base.filterNotDownloaded)
        XCTAssertFalse(application.filter.filterDuration)
        XCTAssertFalse(application.filter.filterStarred)
        XCTAssertEqual(application.filter.filterHours, 0)
    }
}
