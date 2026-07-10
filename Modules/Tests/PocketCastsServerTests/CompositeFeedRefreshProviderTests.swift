import PocketCastsDataModel
import PocketCastsUtils
import XCTest
@testable import PocketCastsServer

final class CompositeFeedRefreshProviderTests: XCTestCase {
    private final class StubProvider: FeedRefreshProviding, @unchecked Sendable {
        let response: PodcastRefreshResponse?
        private let lock = NSLock()
        private var received: [[Podcast]] = []

        var receivedBatches: [[Podcast]] {
            lock.lock()
            defer { lock.unlock() }
            return received
        }

        init(response: PodcastRefreshResponse?) {
            self.response = response
        }

        func refresh(podcasts: [Podcast], completion: @escaping @Sendable (PodcastRefreshResponse?) -> Void) {
            lock.lock()
            received.append(podcasts)
            lock.unlock()
            completion(response)
        }
    }

    private static func okResponse(updates: [String: [RefreshEpisode]]) -> PodcastRefreshResponse {
        var response = PodcastRefreshResponse()
        response.status = "ok"
        response.result = RefreshResult(podcastUpdates: updates)
        return response
    }

    private static func podcast(uuid: String, source: PodcastRefreshSource) -> Podcast {
        var podcast = Podcast()
        podcast.uuid = uuid
        podcast.feedRefreshSource = source
        return podcast
    }

    func testServerOnlyLibraryGoesStraightToServerProvider() {
        let server = StubProvider(response: Self.okResponse(updates: [:]))
        let local = StubProvider(response: Self.okResponse(updates: [:]))
        let composite = CompositeFeedRefreshProvider(serverProvider: server, localProvider: local)

        let podcasts = [Self.podcast(uuid: "s1", source: .server), Self.podcast(uuid: "s2", source: .server)]
        let expectation = expectation(description: "refresh completes")
        composite.refresh(podcasts: podcasts) { _ in expectation.fulfill() }
        wait(for: [expectation], timeout: 5)

        XCTAssertEqual(server.receivedBatches, [podcasts])
        XCTAssertTrue(local.receivedBatches.isEmpty)
    }

    func testLocalOnlyLibraryNeverTouchesServerProvider() {
        let server = StubProvider(response: Self.okResponse(updates: [:]))
        let local = StubProvider(response: Self.okResponse(updates: [:]))
        let composite = CompositeFeedRefreshProvider(serverProvider: server, localProvider: local)

        let podcasts = [Self.podcast(uuid: "l1", source: .localFeed)]
        let expectation = expectation(description: "refresh completes")
        composite.refresh(podcasts: podcasts) { _ in expectation.fulfill() }
        wait(for: [expectation], timeout: 5)

        XCTAssertTrue(server.receivedBatches.isEmpty)
        XCTAssertEqual(local.receivedBatches, [podcasts])
    }

    func testMixedLibraryPartitionsAndMergesUpdates() {
        var serverEpisode = RefreshEpisode()
        serverEpisode.uuid = "server-ep"
        var localEpisode = RefreshEpisode()
        localEpisode.uuid = "local-ep"

        let server = StubProvider(response: Self.okResponse(updates: ["s1": [serverEpisode]]))
        let local = StubProvider(response: Self.okResponse(updates: ["l1": [localEpisode]]))
        let composite = CompositeFeedRefreshProvider(serverProvider: server, localProvider: local)

        let serverPodcast = Self.podcast(uuid: "s1", source: .server)
        let localPodcast = Self.podcast(uuid: "l1", source: .localFeed)

        let received = UncheckedSendable(NSMutableArray())
        let expectation = expectation(description: "refresh completes")
        composite.refresh(podcasts: [serverPodcast, localPodcast]) { response in
            if let response { received.value.add(response) }
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 5)

        XCTAssertEqual(server.receivedBatches, [[serverPodcast]])
        XCTAssertEqual(local.receivedBatches, [[localPodcast]])

        let response = received.value.firstObject as? PodcastRefreshResponse
        XCTAssertEqual(response?.success(), true)
        let updates = response?.result?.podcastUpdates
        XCTAssertEqual(updates?["s1"]?.first?.uuid, "server-ep")
        XCTAssertEqual(updates?["l1"]?.first?.uuid, "local-ep")
    }

    func testOneRegimeFailingStillDeliversTheOther() {
        let merged = CompositeFeedRefreshProvider.merged([
            PodcastRefreshResponse.failedResponse(),
            Self.okResponse(updates: ["l1": []])
        ])

        XCTAssertTrue(merged.success())
        XCTAssertNotNil(merged.result?.podcastUpdates?["l1"])
    }

    func testAllRegimesFailingFailsTheRefresh() {
        let merged = CompositeFeedRefreshProvider.merged([PodcastRefreshResponse.failedResponse(), nil])

        XCTAssertFalse(merged.success())
    }
}
