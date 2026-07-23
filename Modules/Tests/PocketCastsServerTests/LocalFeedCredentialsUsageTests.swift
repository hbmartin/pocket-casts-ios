import Foundation
import GRDB
import Synchronization
import Testing
@testable import PocketCastsDataModel
@testable import PocketCastsServer
@testable import PocketCastsUtils

/// Covers the credential lifecycle around an existing podcast row: the resubscribe
/// dedup path capturing freshly re-entered userinfo, and the media (download/playback)
/// authorization helper's same-origin gate.
extension GlobalSeamSerializedTests {
@Suite("LocalFeedCredentials usage", .serialized)
struct LocalFeedCredentialsUsageTests {
    private let credentialedFeedURL = "https://user:newpass@example.com/feed.xml" // NOSONAR - fake test credential

    private func makeDataManager() -> DataManager {
        DataManager(dbQueue: GRDBQueue(dbPool: try! DatabasePool(path: NSTemporaryDirectory().appending("\(UUID().uuidString).sqlite"))))
    }

    @discardableResult
    private func seedLocalFeedPodcast(
        uuid: String,
        feedURL: String?,
        refreshSource: PodcastRefreshSource = .localFeed,
        subscribed: Bool = true,
        dataManager: DataManager
    ) -> Podcast {
        var podcast = Podcast()
        podcast.uuid = uuid
        podcast.subscribed = subscribed ? 1 : 0
        podcast.addedDate = Date()
        podcast.syncStatus = SyncStatus.synced.rawValue
        podcast.podcastUrl = feedURL
        podcast.feedRefreshSource = refreshSource
        return dataManager.save(podcast: podcast)
    }

    // FIX for: unsubscribe/resubscribe silently discarding re-entered credentials.
    @Test("addLocalFeed dedup saves freshly re-entered userinfo credentials for the existing row")
    func dedupSavesReenteredCredentials() throws {
        let previousStore = KeychainHelper.store
        defer { KeychainHelper.store = previousStore }
        KeychainHelper.store = InMemoryKeychainStore()

        let previousShared = DataManager.sharedManager
        defer { DataManager.sharedManager = previousShared }
        let dataManager = makeDataManager()
        DataManager.sharedManager = dataManager

        seedLocalFeedPodcast(uuid: "local-pod", feedURL: "https://example.com/feed.xml", dataManager: dataManager)

        // The dedup match strips userinfo, so this hits the existing row.
        let succeeded = Mutex<Bool?>(nil)
        ServerPodcastManager.shared.addLocalFeed(feedURL: credentialedFeedURL, subscribe: true) { success in
            succeeded.withLock { $0 = success }
        }

        #expect(succeeded.withLock { $0 } == true, "the dedup branch completes synchronously")
        let stored = try #require(LocalFeedCredentials.credentials(podcastUuid: "local-pod"))
        #expect(stored.user == "user")
        #expect(stored.password == "newpass")
    }

    @Test("addLocalFeed dedup aborts resubscribe when re-entered credentials cannot be stored")
    func dedupCredentialSaveFailureAbortsResubscribe() throws {
        let previousStore = KeychainHelper.store
        defer { KeychainHelper.store = previousStore }
        KeychainHelper.store = RejectingLocalFeedKeychainStore()

        let previousShared = DataManager.sharedManager
        defer { DataManager.sharedManager = previousShared }
        let dataManager = makeDataManager()
        DataManager.sharedManager = dataManager

        seedLocalFeedPodcast(
            uuid: "local-pod",
            feedURL: "https://example.com/feed.xml",
            subscribed: false,
            dataManager: dataManager
        )

        let succeeded = Mutex<Bool?>(nil)
        ServerPodcastManager.shared.addLocalFeed(feedURL: credentialedFeedURL, subscribe: true) { success in
            succeeded.withLock { $0 = success }
        }

        #expect(succeeded.withLock { $0 } == false)
        let podcast = try #require(dataManager.findPodcast(uuid: "local-pod", includeUnsubscribed: true))
        #expect(!podcast.isSubscribed(), "a row without its required credential must not be resubscribed")
        #expect(LocalFeedCredentials.credentials(podcastUuid: "local-pod") == nil)
    }

    @Test("addLocalFeed dedup keeps an already-subscribed row successful when the credential save fails")
    func dedupCredentialSaveFailureOnSubscribedRowLogsAndSucceeds() throws {
        let previousStore = KeychainHelper.store
        defer { KeychainHelper.store = previousStore }
        KeychainHelper.store = RejectingLocalFeedKeychainStore()

        let previousShared = DataManager.sharedManager
        defer { DataManager.sharedManager = previousShared }
        let dataManager = makeDataManager()
        DataManager.sharedManager = dataManager

        seedLocalFeedPodcast(
            uuid: "local-pod",
            feedURL: "https://example.com/feed.xml",
            subscribed: true,
            dataManager: dataManager
        )

        let succeeded = Mutex<Bool?>(nil)
        ServerPodcastManager.shared.addLocalFeed(feedURL: credentialedFeedURL, subscribe: true) { success in
            succeeded.withLock { $0 = success }
        }

        #expect(succeeded.withLock { $0 } == true,
                "an already-subscribed row does not depend on the fresh credential — log and succeed")
        let podcast = try #require(dataManager.findPodcast(uuid: "local-pod", includeUnsubscribed: true))
        #expect(podcast.isSubscribed())
    }

    @Test("resubscribing an existing local-feed row keeps it out of server sync")
    func localFeedResubscribeDerivesSyncStatusFromFinalSource() throws {
        let previousShared = DataManager.sharedManager
        defer { DataManager.sharedManager = previousShared }
        let dataManager = makeDataManager()
        DataManager.sharedManager = dataManager

        seedLocalFeedPodcast(
            uuid: "local-pod",
            feedURL: "https://example.com/feed.xml",
            subscribed: false,
            dataManager: dataManager
        )

        let succeeded = Mutex<Bool?>(nil)
        ServerPodcastManager.shared.addLocalFeed(feedURL: "https://example.com/feed.xml", subscribe: true) { success in
            succeeded.withLock { $0 = success }
        }

        #expect(succeeded.withLock { $0 } == true)
        let podcast = try #require(dataManager.findPodcast(uuid: "local-pod", includeUnsubscribed: true))
        #expect(podcast.isSubscribed())
        #expect(podcast.syncStatus == SyncStatus.synced.rawValue)
    }

    @Test("addFromJson resubscribe of an existing unsubscribed local-feed row derives synced from the final source")
    func addFromJsonResubscribeDerivesSyncStatusFromFinalSource() async throws {
        let previousShared = DataManager.sharedManager
        defer { DataManager.sharedManager = previousShared }
        let dataManager = makeDataManager()
        DataManager.sharedManager = dataManager

        seedLocalFeedPodcast(
            uuid: "local-pod",
            feedURL: "https://example.com/feed.xml",
            subscribed: false,
            dataManager: dataManager
        )

        let podcastInfo: [String: Any] = ["podcast": ["uuid": "local-pod"]]
        let added = await withCheckedContinuation { continuation in
            ServerPodcastManager.shared.addFromJson(lastModified: nil, podcastInfo: podcastInfo, subscribe: true, autoDownloads: 0, refreshSource: .localFeed) { success in
                continuation.resume(returning: success)
            }
        }

        #expect(added == true)
        let podcast = try #require(dataManager.findPodcast(uuid: "local-pod", includeUnsubscribed: true))
        #expect(podcast.isSubscribed())
        #expect(podcast.syncStatus == SyncStatus.synced.rawValue,
                "existing local-feed rows must never queue for account sync, even via the addPodcast path")
    }

    // FIX for: stored credentials never reaching media downloads/playback.
    @Test("media authorization header applies only to same-origin media of a localFeed podcast")
    func mediaAuthorizationHeaderSameOriginGate() throws {
        let previousStore = KeychainHelper.store
        defer { KeychainHelper.store = previousStore }
        KeychainHelper.store = InMemoryKeychainStore()

        let previousShared = DataManager.sharedManager
        defer { DataManager.sharedManager = previousShared }
        let dataManager = makeDataManager()
        DataManager.sharedManager = dataManager

        seedLocalFeedPodcast(uuid: "local-pod", feedURL: "https://example.com/feed.xml", dataManager: dataManager)
        LocalFeedCredentials.save(user: "user", password: "pass", podcastUuid: "local-pod")

        var episode = Episode()
        episode.uuid = "ep-1"
        episode.podcastUuid = "local-pod"

        let expectedHeader = "Basic \(Data("user:pass".utf8).base64EncodedString())"
        let sameOrigin = try #require(URL(string: "https://example.com/media/ep-1.mp3"))
        #expect(LocalFeedCredentials.mediaAuthorizationHeader(for: episode, mediaURL: sameOrigin) == expectedHeader)

        let crossOrigin = try #require(URL(string: "https://cdn.example.com/media/ep-1.mp3"))
        #expect(LocalFeedCredentials.mediaAuthorizationHeader(for: episode, mediaURL: crossOrigin) == nil,
                "credentials must never leak to third-party hosts such as CDNs")

        let localFile = try #require(URL(string: "file:///downloads/ep-1.mp3"))
        #expect(LocalFeedCredentials.mediaAuthorizationHeader(for: episode, mediaURL: localFile) == nil)
    }

    @Test("media authorization header is nil without a localFeed podcast or stored credential")
    func mediaAuthorizationHeaderRequiresLocalFeedAndCredential() throws {
        let previousStore = KeychainHelper.store
        defer { KeychainHelper.store = previousStore }
        KeychainHelper.store = InMemoryKeychainStore()

        let previousShared = DataManager.sharedManager
        defer { DataManager.sharedManager = previousShared }
        let dataManager = makeDataManager()
        DataManager.sharedManager = dataManager

        seedLocalFeedPodcast(uuid: "server-pod", feedURL: "https://example.com/feed.xml", refreshSource: .server, dataManager: dataManager)
        LocalFeedCredentials.save(user: "user", password: "pass", podcastUuid: "server-pod")
        seedLocalFeedPodcast(uuid: "credential-less-pod", feedURL: "https://example.com/other.xml", dataManager: dataManager)

        let mediaURL = try #require(URL(string: "https://example.com/media/ep.mp3"))

        var serverEpisode = Episode()
        serverEpisode.uuid = "ep-server"
        serverEpisode.podcastUuid = "server-pod"
        #expect(LocalFeedCredentials.mediaAuthorizationHeader(for: serverEpisode, mediaURL: mediaURL) == nil,
                "server-sourced podcasts have no private-feed credential to attach")

        var credentialLessEpisode = Episode()
        credentialLessEpisode.uuid = "ep-credential-less"
        credentialLessEpisode.podcastUuid = "credential-less-pod"
        #expect(LocalFeedCredentials.mediaAuthorizationHeader(for: credentialLessEpisode, mediaURL: mediaURL) == nil)

        var orphanEpisode = Episode()
        orphanEpisode.uuid = "ep-orphan"
        orphanEpisode.podcastUuid = "missing-pod"
        #expect(LocalFeedCredentials.mediaAuthorizationHeader(for: orphanEpisode, mediaURL: mediaURL) == nil)
    }
}
}

private struct RejectingLocalFeedKeychainStore: KeychainStoring {
    func save(value: String?, key: String, accessibility: CFTypeRef) -> Bool { false }
    func string(for key: String) throws -> String? { nil }
}
