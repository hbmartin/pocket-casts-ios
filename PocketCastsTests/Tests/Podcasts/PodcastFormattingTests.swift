import XCTest
@testable import podcasts
import PocketCastsDataModel
import PocketCastsUtils

/// Pure-logic tests for Podcast+Formatting.swift's `displayableFrequency()` and
/// `displayableExpiryLanguage(expiryDate:)`. These read only record properties (no DB/UI), so a plain
/// `Podcast()` with fields set is enough.
final class PodcastFormattingTests: XCTestCase {

    private func podcast(frequency: String?) -> Podcast {
        let podcast = Podcast()
        podcast.episodeFrequency = frequency
        return podcast
    }

    // MARK: - displayableFrequency

    func testDisplayableFrequency_translatesKnownFrequencies() {
        XCTAssertEqual(podcast(frequency: "hourly").displayableFrequency(), L10n.releaseFrequencyHourly.localizedCapitalized)
        XCTAssertEqual(podcast(frequency: "daily").displayableFrequency(), L10n.releaseFrequencyDaily.localizedCapitalized)
        XCTAssertEqual(podcast(frequency: "weekly").displayableFrequency(), L10n.releaseFrequencyWeekly.localizedCapitalized)
        XCTAssertEqual(podcast(frequency: "fortnightly").displayableFrequency(), L10n.releaseFrequencyFortnightly.localizedCapitalized)
        XCTAssertEqual(podcast(frequency: "monthly").displayableFrequency(), L10n.releaseFrequencyMonthly.localizedCapitalized)
    }

    func testDisplayableFrequency_isCaseInsensitive() {
        XCTAssertEqual(podcast(frequency: "DAILY").displayableFrequency(), L10n.releaseFrequencyDaily.localizedCapitalized)
    }

    func testDisplayableFrequency_returnsNilForUnknownNewOrMissing() {
        XCTAssertNil(podcast(frequency: nil).displayableFrequency())
        XCTAssertNil(podcast(frequency: "unknown").displayableFrequency())
        XCTAssertNil(podcast(frequency: "new").displayableFrequency())
    }

    func testDisplayableFrequency_capitalizesUnrecognizedServerValue() {
        XCTAssertEqual(podcast(frequency: "biweekly").displayableFrequency(), "biweekly".localizedCapitalized)
    }

    // MARK: - displayableExpiryLanguage

    func testDisplayableExpiryLanguage_deleteAfterExpiry() {
        let podcast = Podcast()
        podcast.licensing = PodcastLicensing.deleteEpisodesAfterExpiry.rawValue

        let future = Date().addingTimeInterval(30.days)
        let past = Date().addingTimeInterval(-30.days)
        let futureStr = DateFormatHelper.sharedHelper.longLocalizedFormat(future)
        let pastStr = DateFormatHelper.sharedHelper.longLocalizedFormat(past)

        XCTAssertEqual(podcast.displayableExpiryLanguage(expiryDate: future), L10n.podcastAccessEnds(futureStr))
        XCTAssertEqual(podcast.displayableExpiryLanguage(expiryDate: past), L10n.podcastAccessEnded(pastStr))
    }

    func testDisplayableExpiryLanguage_keepEpisodes() {
        let podcast = Podcast()
        podcast.licensing = PodcastLicensing.keepEpisodesAfterExpiry.rawValue

        let future = Date().addingTimeInterval(30.days)
        let futureStr = DateFormatHelper.sharedHelper.longLocalizedFormat(future)

        XCTAssertEqual(podcast.displayableExpiryLanguage(expiryDate: future), L10n.podcastUpdatesEnds(futureStr))
    }
}
