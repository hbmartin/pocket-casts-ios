import PocketCastsServer
import SnapshotTesting
import SwiftUI
import XCTest

@testable import podcasts

/// Themed snapshots for the Slice-3 social surfaces: the episode reactions
/// row, the reviews list, and the two static share cards. All fixtures are
/// deterministic (fixture VMs skip network; fixed dates; the heatmap card is
/// excluded — its grid anchors to the current date).
@MainActor
final class SocialSlice3SnapshotTests: XCTestCase {
    func testReactionsRowStates() {
        // Gated (can't react yet), no counts.
        assertAppThemedSnapshots(
            of: EpisodeReactionsRowView(viewModel: EpisodeReactionsViewModel(
                episodeUuid: "e1", canReact: false,
                fixture: EpisodeReactions(counts: [:], yourReaction: nil))),
            layout: .fixed(width: 390, height: 160)
        )
    }

    func testReactionsRowWithCounts() {
        assertAppThemedSnapshots(
            of: EpisodeReactionsRowView(viewModel: EpisodeReactionsViewModel(
                episodeUuid: "e1", canReact: true,
                fixture: EpisodeReactions(counts: [.heart: 12, .mindBlown: 3, .fire: 1], yourReaction: .mindBlown))),
            layout: .fixed(width: 390, height: 140)
        )
    }

    func testReviewsList() {
        let page = PodcastReviewPage(
            reviews: [
                PodcastReview(userId: "00000000-0000-0000-0000-000000000001",
                              handle: "reviewer_one", displayName: "Reviewer One", rating: 5,
                              text: "A considered opinion about a fine podcast.",
                              createdAt: Date(timeIntervalSince1970: 1_750_000_000), updatedAt: nil),
                PodcastReview(userId: "00000000-0000-0000-0000-000000000002",
                              handle: "reviewer_two", displayName: "Reviewer Two", rating: 3,
                              text: "Mixed feelings, but the production is great.",
                              createdAt: Date(timeIntervalSince1970: 1_750_100_000), updatedAt: nil),
            ],
            total: 2,
            yourReview: nil
        )
        assertAppThemedSnapshots(
            of: NavigationView {
                PodcastReviewsView(viewModel: PodcastReviewsViewModel(podcastUuid: "p1", fixture: page))
            }.navigationViewStyle(.stack),
            layout: .fixed(width: 390, height: 700)
        )
    }

    func testStatsShareCard() {
        assertAppThemedSnapshots(
            of: StatsShareCardView(
                stats: ListeningStatsFixture(totalListened: 123 * 3600,
                                             timeSaved: 17 * 3600,
                                             since: Date(timeIntervalSince1970: 1_700_000_000)),
                footer: "@snapshot_person · Pocket Casts"),
            layout: .fixed(width: 340, height: 400)
        )
    }
}
