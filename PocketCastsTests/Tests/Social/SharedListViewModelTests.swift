import PocketCastsServer
import PocketCastsDataModel
import XCTest
@testable import podcasts

@MainActor
final class SharedListViewModelTests: XCTestCase {
    func testMoveSendsOneOperationForDraggedEntry() async {
        let recorder = SharedListRequestRecorder()
        let entries = (0 ..< 4).map(makeEntry)
        let model = SharedListDetailViewModel(
            fixture: SharedListPage(list: makeList(role: .owner, entryCount: entries.count),
                                    entries: entries,
                                    total: entries.count),
            entryOperation: { listId, operation, entry, position in
                recorder.recordOperation(listId: listId, operation: operation, entry: entry, position: position)
                return true
            }
        )

        await model.move(from: IndexSet(integer: 0), to: 3)

        XCTAssertEqual(recorder.operationCount, 1)
        XCTAssertEqual(recorder.lastOperationListId, model.listId)
        XCTAssertEqual(recorder.lastOperationRawValue, SharedListOp.move.rawValue)
        XCTAssertEqual(recorder.lastOperationEpisodeUuid, entries[0].episodeUuid)
        XCTAssertEqual(recorder.lastOperationPosition,
                       model.entries.firstIndex(where: { $0.id == entries[0].id }))
    }

    func testSubscribeReusesCompleteLoadedPageForMirrorAndUpdatesRole() async {
        let recorder = SharedListRequestRecorder()
        let entries = (0 ..< 3).map(makeEntry)
        let model = SharedListDetailViewModel(
            fixture: SharedListPage(list: makeList(role: .none, entryCount: entries.count),
                                    entries: entries,
                                    total: entries.count),
            subscribe: { id, subscribe in
                recorder.recordSubscription(listId: id, subscribe: subscribe)
                return true
            },
            rebuildMirror: { list, suppliedEntries in
                recorder.recordMirror(list: list, entries: suppliedEntries)
            }
        )

        await model.toggleSubscribe()

        XCTAssertEqual(recorder.subscriptionCount, 1)
        XCTAssertEqual(recorder.lastSubscriptionListId, model.listId)
        XCTAssertEqual(recorder.lastSubscriptionValue, true)
        XCTAssertEqual(model.page?.list.yourRole.rawValue, SharedListRole.subscriber.rawValue)
        XCTAssertEqual(recorder.mirrorEntries, entries)
    }

    func testSubscribeDoesNotReusePartialPageForMirror() async {
        let recorder = SharedListRequestRecorder()
        let entries = (0 ..< 2).map(makeEntry)
        let model = SharedListDetailViewModel(
            fixture: SharedListPage(list: makeList(role: .none, entryCount: 5),
                                    entries: entries,
                                    total: 5),
            subscribe: { _, _ in true },
            rebuildMirror: { list, suppliedEntries in
                recorder.recordMirror(list: list, entries: suppliedEntries)
            }
        )

        await model.toggleSubscribe()

        XCTAssertEqual(recorder.mirrorCount, 1)
        XCTAssertNil(recorder.mirrorEntries)
    }

    func testAcceptInviteUsesOverviewReturnedByMirrorRefresh() async {
        let recorder = SharedListRequestRecorder()
        let invite = makeList(id: 9, role: .invited, entryCount: 0)
        let refreshedList = makeList(id: 10, role: .collaborator, entryCount: 4)
        let model = SharedListsViewModel(
            fixture: [],
            invites: [invite],
            fetchLists: {
                recorder.recordOverviewFetch()
                return nil
            },
            respondToInvite: { _, _ in true },
            refreshMirrors: {
                SharedListsOverview(lists: [refreshedList], invites: [])
            }
        )

        await model.respond(to: invite, accept: true)

        XCTAssertEqual(model.lists, [refreshedList])
        XCTAssertTrue(model.invites.isEmpty)
        XCTAssertEqual(recorder.overviewFetchCount, 0)
    }

    func testPublishLoadsFullAllowedPlaylistSnapshot() async {
        let recorder = SharedListRequestRecorder()
        var playlist = EpisodeFilter()
        playlist.uuid = "playlist"
        playlist.playlistName = "List"
        let model = PublishListViewModel(
            playlist: playlist,
            loadEpisodes: { _, limit in
                recorder.recordPublishLimit(limit)
                return []
            },
            createList: { title, _, _, entries in
                SharedList(id: 22, title: title, entryCount: entries.count, yourRole: .owner)
            }
        )

        let published = await model.publish()

        XCTAssertTrue(published)
        XCTAssertEqual(recorder.publishLimit, PublishListViewModel.maximumPublishedEpisodes)
        XCTAssertEqual(recorder.publishLimit, 1000)
    }

    func testMirrorPlaylistNameUsesLocalizedFormat() {
        XCTAssertEqual(L10n.socialListMirrorName("Road Trip", "owner"), "Road Trip · @owner")
    }

    private func makeList(
        id: Int64 = 1,
        role: SharedListRole,
        entryCount: Int
    ) -> SharedList {
        SharedList(id: id,
                   ownerHandle: "owner",
                   ownerDisplayName: "Owner",
                   title: "List",
                   entryCount: entryCount,
                   yourRole: role)
    }

    private func makeEntry(position: Int) -> SharedListEntry {
        SharedListEntry(episodeUuid: "episode-\(position)", position: position)
    }
}

@MainActor
private final class SharedListRequestRecorder {
    private(set) var operationCount = 0
    private(set) var lastOperationListId: Int64?
    private(set) var lastOperationRawValue: Int?
    private(set) var lastOperationEpisodeUuid: String?
    private(set) var lastOperationPosition: Int?
    private(set) var subscriptionCount = 0
    private(set) var lastSubscriptionListId: Int64?
    private(set) var lastSubscriptionValue: Bool?
    private(set) var mirrorCount = 0
    private(set) var mirrorEntries: [SharedListEntry]?
    private(set) var overviewFetchCount = 0
    private(set) var publishLimit: Int?

    func recordOperation(listId: Int64, operation: SharedListOp, entry: SharedListEntry, position: Int) {
        operationCount += 1
        lastOperationListId = listId
        lastOperationRawValue = operation.rawValue
        lastOperationEpisodeUuid = entry.episodeUuid
        lastOperationPosition = position
    }

    func recordSubscription(listId: Int64, subscribe: Bool) {
        subscriptionCount += 1
        lastSubscriptionListId = listId
        lastSubscriptionValue = subscribe
    }

    func recordMirror(list _: SharedList, entries: [SharedListEntry]?) {
        mirrorCount += 1
        mirrorEntries = entries
    }

    func recordOverviewFetch() {
        overviewFetchCount += 1
    }

    func recordPublishLimit(_ limit: Int) {
        publishLimit = limit
    }
}
