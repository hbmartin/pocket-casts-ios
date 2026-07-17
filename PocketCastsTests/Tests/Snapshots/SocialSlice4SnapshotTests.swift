import PocketCastsServer
import SnapshotTesting
import SwiftUI
import XCTest

@testable import podcasts

/// Themed snapshots for the Slice-4 surfaces: the send-to-friend sheet and
/// the shared-item inbox. Deterministic fixtures (fixture VMs skip network;
/// fixed dates; recipient lookup staged via the internal setter).
@MainActor
final class SocialSlice4SnapshotTests: XCTestCase {
    private static let phone = SwiftUISnapshotLayout.fixed(width: 390, height: 700)

    private func sendViewModel(status: SendToFriendViewModel.RecipientStatus, handle: String) -> SendToFriendViewModel {
        let viewModel = SendToFriendViewModel(episodeUuid: "e1", podcastUuid: "p1",
                                              episodeTitle: "A Great Episode",
                                              podcastTitle: "A Great Podcast",
                                              timestampSeconds: 870)
        viewModel.handleInput = handle
        viewModel.recipientStatus = status
        return viewModel
    }

    func testSendSheetRecipientFound() {
        let viewModel = sendViewModel(status: .found(name: "A Friend"), handle: "friend")
        assertAppThemedSnapshots(
            of: SendToFriendView(viewModel: viewModel),
            layout: Self.phone
        )
    }

    func testSendSheetRecipientNotFound() {
        let viewModel = sendViewModel(status: .notFound, handle: "nobody")
        assertAppThemedSnapshots(
            of: SendToFriendView(viewModel: viewModel),
            layout: Self.phone
        )
    }

    func testInboxWithItems() {
        let page = SocialInboxPage(
            items: [
                SharedItem(id: 1, senderUserId: "u1", senderHandle: "sender_one", senderDisplayName: "Sender One",
                           episodeUuid: "e1", podcastUuid: "p1",
                           episodeTitle: "An Unread Episode", podcastTitle: "A Podcast",
                           note: "you'll love this bit",
                           timestampSeconds: 615, createdAt: Date(timeIntervalSince1970: 1_750_000_000), read: false),
                SharedItem(id: 2, senderUserId: "u2", senderHandle: "sender_two", senderDisplayName: "Sender Two",
                           episodeUuid: "e2", podcastUuid: "p2",
                           episodeTitle: "An Already-Read Episode", podcastTitle: "Another Podcast",
                           note: "", timestampSeconds: 0,
                           createdAt: Date(timeIntervalSince1970: 1_749_900_000), read: true),
            ],
            total: 2, unread: 1
        )
        assertAppThemedSnapshots(
            of: NavigationView {
                SocialInboxView(viewModel: SocialInboxViewModel(fixture: page))
            }.navigationViewStyle(.stack),
            layout: Self.phone
        )
    }

    func testInboxEmpty() {
        assertAppThemedSnapshots(
            of: NavigationView {
                SocialInboxView(viewModel: SocialInboxViewModel(fixture: SocialInboxPage(items: [], total: 0, unread: 0)))
            }.navigationViewStyle(.stack),
            layout: .fixed(width: 390, height: 300)
        )
    }
}
