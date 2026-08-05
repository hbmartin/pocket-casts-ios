import PocketCastsDataModel
import XCTest

@testable import podcasts

/// Truth table for the pure contribution-eligibility gate and the token-free
/// sighting URL rule (docs/TranscriptContributions.md §1).
final class TranscriptContributionEligibilityTests: XCTestCase {
    private func makePodcast() -> Podcast {
        var podcast = Podcast()
        podcast.uuid = "podcast-1"
        return podcast
    }

    private func makeEpisode() -> Episode {
        var episode = Episode()
        episode.uuid = "episode-1"
        episode.podcastUuid = "podcast-1"
        return episode
    }

    // MARK: - Episode eligibility

    func testPodcastEpisodeIsEligible() {
        XCTAssertTrue(TranscriptContributionEligibility.isEligible(episode: makeEpisode(), podcast: makePodcast()))
    }

    func testUserEpisodeIsNotEligible() {
        var uploaded = UserEpisode()
        uploaded.uuid = "user-episode-1"
        XCTAssertFalse(TranscriptContributionEligibility.isEligible(episode: uploaded, podcast: makePodcast()),
                       "Uploaded files are private by definition")
    }

    func testMissingEpisodeIsNotEligible() {
        XCTAssertFalse(TranscriptContributionEligibility.isEligible(episode: nil, podcast: makePodcast()))
    }

    func testMissingPodcastIsNotEligible() {
        XCTAssertFalse(TranscriptContributionEligibility.isEligible(episode: makeEpisode(), podcast: nil))
    }

    func testEpisodeFromDifferentPodcastIsNotEligible() {
        var podcast = makePodcast()
        podcast.uuid = "podcast-2"
        XCTAssertFalse(TranscriptContributionEligibility.isEligible(episode: makeEpisode(), podcast: podcast))
    }

    // MARK: - Token-free URL rule

    func testPlainURLIsTokenFree() {
        XCTAssertTrue(TranscriptContributionEligibility.isTokenFreeURL("https://example.com/podcast/ep1.vtt"))
    }

    func testShortBenignQueryItemsAreTokenFree() {
        XCTAssertTrue(TranscriptContributionEligibility.isTokenFreeURL("https://example.com/t.vtt?lang=en&v=2"))
    }

    func testUserinfoIsRejected() {
        XCTAssertFalse(TranscriptContributionEligibility.isTokenFreeURL("https://user:pass@example.com/t.vtt"))
        XCTAssertFalse(TranscriptContributionEligibility.isTokenFreeURL("https://user@example.com/t.vtt"))
    }

    func testTokenLikeQueryNamesAreRejected() {
        for url in ["https://example.com/t.vtt?token=a",
                    "https://example.com/t.vtt?sig=a",
                    "https://example.com/t.vtt?X-Amz-Signature=a",
                    "https://example.com/t.vtt?apikey=a",
                    "https://example.com/t.vtt?AUTH=a",
                    "https://example.com/t.vtt?session=a",
                    "https://example.com/t.vtt?Expires=1",
                    "https://example.com/t.vtt?Policy=a",
                    "https://example.com/t.vtt?access_token=a"] {
            XCTAssertFalse(TranscriptContributionEligibility.isTokenFreeURL(url), "Expected rejection: \(url)")
        }
    }

    func testLongOpaqueQueryValuesAreRejectedRegardlessOfName() {
        XCTAssertFalse(TranscriptContributionEligibility.isTokenFreeURL(
            "https://example.com/t.vtt?ref=abcdefghijklmnop"), "16-char value must be rejected")
        XCTAssertTrue(TranscriptContributionEligibility.isTokenFreeURL(
            "https://example.com/t.vtt?ref=abcdefghijklmno"), "15-char value is allowed")
    }

    func testUnparseableURLIsRejected() {
        // An unterminated IPv6 host fails even the lenient RFC 3986 parser.
        XCTAssertFalse(TranscriptContributionEligibility.isTokenFreeURL("https://[::1/t.vtt"))
    }
}
