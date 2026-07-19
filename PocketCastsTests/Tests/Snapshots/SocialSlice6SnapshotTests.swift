import PocketCastsServer
import SnapshotTesting
import SwiftUI
import XCTest

@testable import podcasts

/// Themed snapshot coverage for Slice 6 (episode comment tree, ADR-0010): the
/// thread screen (nested replies, Moment chip, tombstone, edited marker), the
/// gated composer state, the episode-card entry row, and the Inbox Replies
/// section. Deterministic: fixture VMs skip the network and dates stay nil so
/// no relative times render.
@MainActor
final class SocialSlice6SnapshotTests: XCTestCase {
    private static let phone = SwiftUISnapshotLayout.fixed(width: 390, height: 700)

    private static func comment(id: Int64, parentId: Int64 = 0, handle: String = "snapshot_friend",
                                name: String = "Snapshot Friend", text: String, ts: Int? = nil,
                                quote: String = "", edited: Bool = false, removed: Bool = false,
                                replyCount: Int = 0) -> SocialComment {
        SocialComment(id: id, parentId: parentId, userId: "00000000-0000-0000-0000-000000000003",
                      handle: handle, displayName: name, text: text, timestampSeconds: ts,
                      quote: quote, createdAt: nil, edited: edited, removed: removed, replyCount: replyCount)
    }

    func testCommentsThread() {
        let fixture = [
            Self.comment(id: 1, text: "A Moment at two minutes — this bit is great.", ts: 125, replyCount: 2),
            Self.comment(id: 7, handle: "quoting_friend", name: "Quoting Friend",
                         text: "Exactly the moment I meant.", ts: 210,
                         quote: "so we shipped it on a friday and nothing broke"),
            Self.comment(id: 4, text: "", removed: true, replyCount: 1),
            Self.comment(id: 6, handle: "another_friend", name: "Another Friend",
                         text: "Plain thread comment, no timestamp.", edited: true),
        ]
        let children: [Int64: [SocialComment]] = [
            1: [
                Self.comment(id: 2, parentId: 1, handle: "another_friend", name: "Another Friend",
                             text: "Agreed — a reply.", replyCount: 1),
                Self.comment(id: 3, parentId: 1, text: "Second reply."),
            ],
            2: [
                Self.comment(id: 5, parentId: 2, text: "A nested reply to the reply."),
            ],
        ]
        assertAppThemedSnapshots(
            of: NavigationView {
                EpisodeCommentsView(viewModel: EpisodeCommentsViewModel(fixture: fixture, children: children, expanded: [1, 2]))
            }.navigationViewStyle(.stack),
            layout: Self.phone
        )
    }

    func testCommentsEmptyGated() {
        assertAppThemedSnapshots(
            of: NavigationView {
                EpisodeCommentsView(viewModel: EpisodeCommentsViewModel(fixture: [], canSeed: false))
            }.navigationViewStyle(.stack),
            layout: .fixed(width: 390, height: 420)
        )
    }

    func testCommentsRow() {
        assertAppThemedSnapshots(
            of: VStack(spacing: 0) {
                EpisodeCommentsRowView(viewModel: EpisodeCommentsRowViewModel(fixtureCount: 12))
                EpisodeCommentsRowView(viewModel: EpisodeCommentsRowViewModel(fixtureCount: nil))
            },
            layout: .fixed(width: 390, height: 120)
        )
    }

    func testInboxWithReplies() {
        let replies = [
            SocialComment(id: 9, parentId: 1, userId: "00000000-0000-0000-0000-000000000003",
                          handle: "snapshot_friend", displayName: "Snapshot Friend",
                          text: "Replying to your take!", timestampSeconds: nil, createdAt: nil,
                          edited: false, removed: false, replyCount: 0,
                          episodeUuid: "aaaaaaaa-0000-0000-0000-000000000003", podcastUuid: "",
                          episodeTitle: "A Recent Episode", podcastTitle: "Top Podcast"),
        ]
        assertAppThemedSnapshots(
            of: NavigationView {
                SocialInboxView(viewModel: SocialInboxViewModel(fixture: SocialInboxPage(items: [], total: 0, unread: 0),
                                                                replies: replies))
            }.navigationViewStyle(.stack),
            layout: .fixed(width: 390, height: 400)
        )
    }

    func testFeedCommentedRow() {
        let item = FeedItem(kind: .commented,
                            actorHandle: "snapshot_friend",
                            actorDisplayName: "Snapshot Friend",
                            actorUserId: "00000000-0000-0000-0000-000000000003",
                            podcastUuid: "aaaaaaaa-0000-0000-0000-000000000002",
                            podcastTitle: "Top Podcast",
                            episodeUuid: "aaaaaaaa-0000-0000-0000-000000000003",
                            episodeTitle: "A Recent Episode",
                            targetHandle: "",
                            reactionKind: nil,
                            reviewExcerpt: "A deterministic comment excerpt.",
                            eventAt: nil)
        assertAppThemedSnapshots(
            of: ScrollView { SocialFeedSection(viewModel: SocialFeedViewModel(fixture: [item])) },
            layout: .fixed(width: 390, height: 260)
        )
    }
}
