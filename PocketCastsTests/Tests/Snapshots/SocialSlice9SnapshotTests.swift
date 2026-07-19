import PocketCastsServer
import SnapshotTesting
import SwiftUI
import XCTest

@testable import podcasts

/// Themed snapshot coverage for Slice 9 (find people): search results,
/// contact matches, suggestions with count-only copy, and the action rows.
/// Fixture VMs never touch the network or Contacts.
@MainActor
final class SocialSlice9SnapshotTests: XCTestCase {
    private static func person(_ handle: String, name: String, state: FollowState = .none, mutual: Int = 0) -> SocialProfileSummary {
        SocialProfileSummary(handle: handle, displayName: name, yourFollowState: state, mutualCount: mutual)
    }

    func testFindPeoplePopulated() {
        let viewModel = FindPeopleViewModel(
            fixtureResults: [Self.person("snapshot_person", name: "Snapshot Person", state: .active)],
            suggestions: [Self.person("suggested_friend", name: "Suggested Friend", mutual: 3),
                          Self.person("another_suggestion", name: "Another Suggestion", mutual: 1)],
            contactMatches: [Self.person("from_contacts", name: "From Contacts")],
            curators: [SocialProfileSummary(handle: "taste_maker", displayName: "Taste Maker",
                                            curator: true, followerCount: 128),
                       SocialProfileSummary(handle: "deep_cuts", displayName: "Deep Cuts",
                                            yourFollowState: .active, curator: true, followerCount: 41)]
        )
        assertAppThemedSnapshots(
            of: NavigationView {
                FindPeopleView(viewModel: viewModel)
            }.navigationViewStyle(.stack),
            layout: .fixed(width: 390, height: 700)
        )
    }

    func testFindPeopleEmpty() {
        assertAppThemedSnapshots(
            of: NavigationView {
                FindPeopleView(viewModel: FindPeopleViewModel(fixtureResults: []))
            }.navigationViewStyle(.stack),
            layout: .fixed(width: 390, height: 420)
        )
    }
}
