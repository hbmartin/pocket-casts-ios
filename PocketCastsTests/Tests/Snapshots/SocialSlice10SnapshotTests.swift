import PocketCastsServer
import SnapshotTesting
import SwiftUI
import XCTest

@testable import podcasts

/// Themed snapshot coverage for Slice 10 (discovery): the trending row inside
/// the Explore social section and the podcast-page proof line in its three
/// shapes (named, named+more, count-only).
@MainActor
final class SocialSlice10SnapshotTests: XCTestCase {
    func testFeedWithTrendingRow() {
        let trending = [
            TrendingPodcast(podcastUuid: "aaaaaaaa-0000-0000-0000-000000000002",
                            title: "Top Podcast", author: "An Author", listenerCount: 3),
            TrendingPodcast(podcastUuid: "aaaaaaaa-0000-0000-0000-000000000004",
                            title: "Another Show", author: "Someone Else", listenerCount: 1),
        ]
        assertAppThemedSnapshots(
            of: ScrollView { SocialFeedSection(viewModel: SocialFeedViewModel(fixture: [], trending: trending)) },
            layout: .fixed(width: 390, height: 380)
        )
    }

    func testProofLineShapes() {
        assertAppThemedSnapshots(
            of: VStack(spacing: 12) {
                PodcastProofLine(podcastUuid: "p1", fixture: PodcastProof(visibleHandles: ["snapshot_friend"], totalCount: 1))
                PodcastProofLine(podcastUuid: "p2", fixture: PodcastProof(visibleHandles: ["snapshot_friend", "another_friend"], totalCount: 5))
                PodcastProofLine(podcastUuid: "p3", fixture: PodcastProof(visibleHandles: [], totalCount: 3))
            }.padding(),
            layout: .fixed(width: 390, height: 220)
        )
    }
}
