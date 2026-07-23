import PocketCastsServer
import XCTest
@testable import podcasts

@MainActor
final class SocialInboxViewModelTests: XCTestCase {
    func testLoadMoreCoalescesConcurrentRequestsAndPublishesLoadingState() async {
        let gate = InboxFetchGate()
        let firstItem = makeItem(id: 1)
        let secondItem = makeItem(id: 2)
        let model = SocialInboxViewModel(
            fixture: SocialInboxPage(items: [firstItem], total: 2, unread: 0),
            fetchInbox: { limit, offset in
                await gate.fetch(limit: limit, offset: offset)
            }
        )

        let firstLoad = Task { await model.loadMore() }
        await gate.waitUntilEntered()
        XCTAssertTrue(model.isLoadingMore)

        let duplicateLoad = Task { await model.loadMore() }
        await duplicateLoad.value
        XCTAssertEqual(gate.fetchCount, 1)

        gate.release(with: SocialInboxPage(items: [secondItem], total: 2, unread: 0))
        await firstLoad.value

        XCTAssertFalse(model.isLoadingMore)
        XCTAssertEqual(model.items, [firstItem, secondItem])
        XCTAssertEqual(gate.requestedLimit, 50)
        XCTAssertEqual(gate.requestedOffset, 1)
    }

    func testDeleteRestoresOnlyRowsWhoseServerDeletionFails() async {
        let firstItem = makeItem(id: 1)
        let secondItem = makeItem(id: 2)
        let model = SocialInboxViewModel(
            fixture: SocialInboxPage(items: [firstItem, secondItem], total: 2, unread: 0),
            deleteInboxItem: { id in id == secondItem.id }
        )

        await model.delete(at: IndexSet([0, 1]))

        XCTAssertEqual(model.items, [firstItem])
        XCTAssertEqual(model.total, 1)
    }

    func testDeleteRestoreNeverInflatesAnUndercountedServerTotal() async {
        let firstItem = makeItem(id: 1)
        let secondItem = makeItem(id: 2)
        let model = SocialInboxViewModel(
            fixture: SocialInboxPage(items: [firstItem, secondItem], total: 1, unread: 0),
            deleteInboxItem: { _ in false }
        )

        await model.delete(at: IndexSet([0, 1]))

        XCTAssertEqual(model.items, [firstItem, secondItem])
        XCTAssertEqual(model.total, 1)
    }

    func testBadgeChangePostsUpdateMessage() async {
        let previousValue = SocialInboxBadge.unreadCount
        let newValue = previousValue == Int.max ? previousValue - 1 : previousValue + 1
        let updated = expectation(description: "badge update posted")
        let token = NotificationCenter.default.addObserver(for: SocialInboxBadgeUpdated.self) { _ in
            updated.fulfill()
        }

        SocialInboxBadge.unreadCount = newValue
        await fulfillment(of: [updated], timeout: 1)

        NotificationCenter.default.removeObserver(token)
        SocialInboxBadge.unreadCount = previousValue
    }

    private func makeItem(id: Int64) -> SharedItem {
        SharedItem(
            id: id,
            senderUserId: "sender-id",
            senderHandle: "sender",
            senderDisplayName: "Sender",
            episodeUuid: "episode-\(id)",
            podcastUuid: "podcast",
            episodeTitle: "Episode \(id)",
            podcastTitle: "Podcast",
            note: "",
            timestampSeconds: 0,
            createdAt: nil,
            read: false
        )
    }
}

@MainActor
private final class InboxFetchGate {
    private(set) var fetchCount = 0
    private(set) var requestedLimit: Int?
    private(set) var requestedOffset: Int?
    private var entered = false
    private var enteredContinuations: [CheckedContinuation<Void, Never>] = []
    private var releaseContinuation: CheckedContinuation<SocialInboxPage?, Never>?

    func fetch(limit: Int, offset: Int) async -> SocialInboxPage? {
        fetchCount += 1
        requestedLimit = limit
        requestedOffset = offset
        entered = true
        enteredContinuations.forEach { $0.resume() }
        enteredContinuations.removeAll()
        return await withCheckedContinuation { releaseContinuation = $0 }
    }

    func waitUntilEntered() async {
        guard !entered else { return }
        await withCheckedContinuation { enteredContinuations.append($0) }
    }

    func release(with page: SocialInboxPage?) {
        releaseContinuation?.resume(returning: page)
        releaseContinuation = nil
    }
}
