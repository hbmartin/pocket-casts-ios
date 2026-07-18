import PocketCastsServer
import SnapshotTesting
import SwiftUI
import XCTest

@testable import podcasts

/// Themed snapshot coverage for Slice 7 (shared lists, ADR-0011): the hub with
/// roles + invites, the list detail per role (owner with attributed entries vs
/// subscriber), and the profile Lists section. Deterministic: fixture VMs skip
/// the network; dates stay nil.
@MainActor
final class SocialSlice7SnapshotTests: XCTestCase {
    private static func list(id: Int64, title: String, role: SharedListRole, entries: Int = 3,
                             members: [SharedListMember] = []) -> SharedList {
        SharedList(id: id, ownerHandle: "snapshot_owner", ownerDisplayName: "Snapshot Owner",
                   title: title, description: "A deterministic description.",
                   visibility: .public, createdAt: nil, updatedAt: nil,
                   entryCount: entries, yourRole: role, members: members)
    }

    private static func entry(_ index: Int, addedBy: String = "snapshot_owner") -> SharedListEntry {
        SharedListEntry(episodeUuid: "ep-\(index)", podcastUuid: "pod-1",
                        episodeTitle: "Episode \(index)", podcastTitle: "A Podcast",
                        position: index, addedByHandle: addedBy, addedAt: nil)
    }

    func testSharedListsHub() {
        let lists = [
            Self.list(id: 1, title: "Road Trip", role: .owner),
            Self.list(id: 2, title: "Their Picks", role: .collaborator),
            Self.list(id: 3, title: "Weekend Queue", role: .subscriber),
        ]
        let invites = [Self.list(id: 4, title: "True Crime Deep Cuts", role: .invited)]
        assertAppThemedSnapshots(
            of: NavigationView {
                SharedListsView(viewModel: SharedListsViewModel(fixture: lists, invites: invites))
            }.navigationViewStyle(.stack),
            layout: .fixed(width: 390, height: 600)
        )
    }

    func testSharedListDetailOwner() {
        let page = SharedListPage(
            list: Self.list(id: 1, title: "Road Trip", role: .owner,
                            members: [SharedListMember(handle: "snapshot_friend", displayName: "Snapshot Friend", role: .collaborator)]),
            entries: [Self.entry(0), Self.entry(1, addedBy: "snapshot_friend"), Self.entry(2, addedBy: "")],
            total: 3
        )
        assertAppThemedSnapshots(
            of: NavigationView {
                SharedListDetailView(viewModel: SharedListDetailViewModel(fixture: page))
            }.navigationViewStyle(.stack),
            layout: .fixed(width: 390, height: 600)
        )
    }

    func testSharedListDetailViewer() {
        let page = SharedListPage(
            list: Self.list(id: 2, title: "Weekend Queue", role: .none),
            entries: [Self.entry(0), Self.entry(1)],
            total: 2
        )
        assertAppThemedSnapshots(
            of: NavigationView {
                SharedListDetailView(viewModel: SharedListDetailViewModel(fixture: page))
            }.navigationViewStyle(.stack),
            layout: .fixed(width: 390, height: 480)
        )
    }

    func testProfileListsSection() {
        let previousProfile = SocialIdentityStore.cachedProfile
        SocialIdentityStore.cachedProfile = SocialProfile(userId: "00000000-0000-0000-0000-000000000001",
                                                          handle: "snapshot_viewer",
                                                          displayName: "Snapshot Viewer")
        defer { SocialIdentityStore.cachedProfile = previousProfile }

        let profile = SocialPublicProfile(
            userId: "00000000-0000-0000-0000-000000000002",
            handle: "snapshot_owner", displayName: "Snapshot Owner",
            bio: "", avatarURL: "", createdAt: nil, hasStats: false,
            followerCount: 3, followingCount: 4,
            lists: [Self.list(id: 1, title: "Road Trip", role: .none),
                    Self.list(id: 2, title: "Weekend Queue", role: .none, entries: 12)]
        )
        assertAppThemedSnapshots(
            of: NavigationView {
                PublicProfileView(viewModel: PublicProfileViewModel(handle: "snapshot_owner", fixture: .loaded(profile)))
            }.navigationViewStyle(.stack),
            layout: .fixed(width: 390, height: 560)
        )
    }
}
