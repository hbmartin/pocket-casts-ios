import PocketCastsServer
import SnapshotTesting
import SwiftUI
import XCTest

@testable import podcasts

/// Themed snapshot coverage for Slice 13 (Groups, ADR-0012): the Groups hub
/// (invites, mine, discover), a group's post feed with a nested reply and an
/// episode attachment, and the create sheet. Fixture VMs skip the network;
/// dates stay nil so no relative times render.
@MainActor
final class SocialSlice13SnapshotTests: XCTestCase {
    private static let phone = SwiftUISnapshotLayout.fixed(width: 390, height: 700)

    private static func group(id: Int64, title: String, isPublic: Bool, members: Int,
                              podcastTitle: String = "", role: GroupRole = .member) -> SocialGroup {
        SocialGroup(id: id, ownerHandle: "snapshot_friend", ownerDisplayName: "Snapshot Friend",
                    title: title, visibility: isPublic ? .public : .private,
                    podcastTitle: podcastTitle, memberCount: members, yourRole: role)
    }

    func testGroupsHub() {
        let mine = [
            Self.group(id: 1, title: "Saturday Run Club", isPublic: false, members: 4, role: .owner),
            Self.group(id: 2, title: "Fixture Fans", isPublic: true, members: 128,
                       podcastTitle: "Fixture Podcast"),
        ]
        let invites = [Self.group(id: 3, title: "True Crime Corner", isPublic: false, members: 12, role: .invited)]
        let discover = [Self.group(id: 4, title: "Swift Talk Listeners", isPublic: true, members: 87,
                                   podcastTitle: "Swift Talk", role: .none)]
        assertAppThemedSnapshots(
            of: NavigationView {
                SocialGroupsView(viewModel: SocialGroupsViewModel(fixture: mine, invites: invites, discover: discover))
            }.navigationViewStyle(.stack),
            layout: Self.phone
        )
    }

    func testGroupDetail() {
        let hub = Self.group(id: 2, title: "Fixture Fans", isPublic: true, members: 128, role: .member)
        let posts = [
            GroupPost(id: 1, groupId: 2, userId: "u1", handle: "snapshot_friend", displayName: "Snapshot Friend",
                      text: "This week's episode was wild — thoughts?",
                      episodeUuid: "e1", episodeTitle: "Episode 42: The Reveal", replyCount: 1),
            GroupPost(id: 3, groupId: 2, handle: "", displayName: "", text: "", removed: true),
        ]
        let children: [Int64: [GroupPost]] = [
            1: [GroupPost(id: 2, groupId: 2, parentId: 1, userId: "u2", handle: "another_friend",
                          displayName: "Another Friend", text: "Called it three episodes ago.")],
        ]
        assertAppThemedSnapshots(
            of: NavigationView {
                GroupDetailView(viewModel: GroupDetailViewModel(fixture: posts, group: hub,
                                                                children: children, expanded: [1]))
            }.navigationViewStyle(.stack),
            layout: Self.phone
        )
    }

    func testMilestoneFeedAndCelebration() {
        let items = [
            FeedItem(kind: .milestone, actorHandle: "snapshot_friend", actorDisplayName: "Snapshot Friend",
                     actorUserId: "u1", podcastUuid: "", podcastTitle: "", episodeUuid: "", episodeTitle: "",
                     targetHandle: "", reactionKind: nil, reviewExcerpt: "", eventAt: nil,
                     milestoneKind: 1, milestoneTier: 100),
            FeedItem(kind: .milestone, actorHandle: "another_friend", actorDisplayName: "Another Friend",
                     actorUserId: "u2", podcastUuid: "", podcastTitle: "", episodeUuid: "", episodeTitle: "",
                     targetHandle: "", reactionKind: nil, reviewExcerpt: "", eventAt: nil,
                     milestoneKind: 2, milestoneTier: 250),
        ]
        let viewModel = SocialFeedViewModel(fixture: items)
        viewModel.celebration = SocialMilestone(kind: .hours, tier: 100)
        assertAppThemedSnapshots(
            of: ScrollView { SocialFeedSection(viewModel: viewModel) },
            layout: .fixed(width: 390, height: 540)
        )
    }

    func testPodcastHubsSheet() {
        let hubs = [
            Self.group(id: 4, title: "Swift Talk Listeners", isPublic: true, members: 87, role: .none),
            Self.group(id: 5, title: "Weekly Watchers", isPublic: true, members: 12, role: .none),
        ]
        assertAppThemedSnapshots(
            of: NavigationView {
                PodcastHubsListView(podcastUuid: "fixture", podcastTitle: "Fixture Podcast", hubs: hubs)
            }.navigationViewStyle(.stack),
            layout: .fixed(width: 390, height: 480)
        )
    }

    func testCreateGroupSheet() {
        assertAppThemedSnapshots(
            of: NavigationView {
                CreateGroupView(onDone: { _ in
                    // Submission and dismissal are outside this static view snapshot.
                })
            }.navigationViewStyle(.stack),
            layout: .fixed(width: 390, height: 480)
        )
    }
}
