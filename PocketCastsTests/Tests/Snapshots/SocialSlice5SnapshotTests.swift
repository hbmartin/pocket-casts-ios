import PocketCastsServer
import SnapshotTesting
import SwiftUI
import XCTest

@testable import podcasts

/// Themed snapshot coverage for Slice 5 (follow graph + activity feed): the
/// Explore feed section (one row per feed-item kind, empty state, join card),
/// the follow-button states on the public profile, the own follower/following
/// list, and the Inbox follow-requests section. Fixtures are deterministic:
/// fixture VMs skip the network and `eventAt`/dates are left nil so no
/// relative-time strings render.
@MainActor
final class SocialSlice5SnapshotTests: XCTestCase {
    private static let phone = SwiftUISnapshotLayout.fixed(width: 390, height: 700)

    private static func feedItem(kind: FeedItemKind, reaction: ReactionKind? = nil, excerpt: String = "") -> FeedItem {
        FeedItem(kind: kind,
                 actorHandle: "snapshot_friend",
                 actorDisplayName: "Snapshot Friend",
                 actorUserId: "00000000-0000-0000-0000-000000000003",
                 podcastUuid: "aaaaaaaa-0000-0000-0000-000000000002",
                 podcastTitle: "Top Podcast",
                 episodeUuid: "aaaaaaaa-0000-0000-0000-000000000003",
                 episodeTitle: "A Recent Episode",
                 targetHandle: "snapshot_person",
                 reactionKind: reaction,
                 reviewExcerpt: excerpt,
                 eventAt: nil)
    }

    func testFeedSectionAllKinds() {
        let items: [FeedItem] = [
            Self.feedItem(kind: .joined),
            Self.feedItem(kind: .followedPerson),
            Self.feedItem(kind: .followedShow),
            Self.feedItem(kind: .finishedEpisode),
            Self.feedItem(kind: .reviewed, excerpt: "A deterministic review excerpt."),
            Self.feedItem(kind: .reacted, reaction: .heart),
        ]
        assertAppThemedSnapshots(
            of: ScrollView { SocialFeedSection(viewModel: SocialFeedViewModel(fixture: items)) },
            layout: Self.phone
        )
    }

    func testFeedSectionEmpty() {
        assertAppThemedSnapshots(
            of: ScrollView { SocialFeedSection(viewModel: SocialFeedViewModel(fixture: [])) },
            layout: .fixed(width: 390, height: 220)
        )
    }

    func testFeedSectionJoinCard() {
        assertAppThemedSnapshots(
            of: ScrollView { SocialFeedSection(viewModel: SocialFeedViewModel(fixture: [], isJoined: false)) },
            layout: .fixed(width: 390, height: 260)
        )
    }

    func testPublicProfileFollowStates() {
        // A cached own profile (different userId) makes the follow button render.
        let previousProfile = SocialIdentityStore.cachedProfile
        SocialIdentityStore.cachedProfile = SocialProfile(userId: "00000000-0000-0000-0000-000000000001",
                                                          handle: "snapshot_owner",
                                                          displayName: "Snapshot Owner")
        defer { SocialIdentityStore.cachedProfile = previousProfile }

        for (state, name) in [(FollowState.none, "follow"), (.pending, "requested"), (.active, "following")] {
            let profile = SocialPublicProfile(userId: "00000000-0000-0000-0000-000000000002",
                                              handle: "snapshot_person",
                                              displayName: "Snapshot Person",
                                              bio: "A deterministic bio for image tests.",
                                              avatarURL: "",
                                              createdAt: nil,
                                              hasStats: false,
                                              followerCount: 12,
                                              followingCount: 34,
                                              yourFollowState: state)
            assertAppThemedSnapshots(
                of: NavigationView {
                    PublicProfileView(viewModel: PublicProfileViewModel(handle: "snapshot_person", fixture: .loaded(profile)))
                }.navigationViewStyle(.stack),
                layout: .fixed(width: 390, height: 400),
                testName: "testPublicProfileFollowStates_\(name)"
            )
        }
    }

    func testFollowList() {
        let list = FollowList(entries: [
            FollowEntry(handle: "snapshot_friend", displayName: "Snapshot Friend",
                        userId: "00000000-0000-0000-0000-000000000003", state: .active),
            FollowEntry(handle: "another_friend", displayName: "Another Friend",
                        userId: "00000000-0000-0000-0000-000000000004", state: .active),
        ], total: 2)
        assertAppThemedSnapshots(
            of: NavigationView {
                FollowListView(viewModel: FollowListViewModel(kind: .followers, fixture: list))
            }.navigationViewStyle(.stack),
            layout: .fixed(width: 390, height: 400)
        )
    }

    func testInboxWithFollowRequests() {
        let requests = [
            FollowEntry(handle: "snapshot_friend", displayName: "Snapshot Friend",
                        userId: "00000000-0000-0000-0000-000000000003", state: .pending),
        ]
        assertAppThemedSnapshots(
            of: NavigationView {
                SocialInboxView(viewModel: SocialInboxViewModel(fixture: SocialInboxPage(items: [], total: 0, unread: 0),
                                                                requests: requests))
            }.navigationViewStyle(.stack),
            layout: .fixed(width: 390, height: 400)
        )
    }
}
