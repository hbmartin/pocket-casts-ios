import XCTest
@testable import PocketCastsDataModel
import PocketCastsUtils
@testable import podcasts

extension DownloadManager {
    /// Terminal: `invalidateAndCancel()` permanently kills the sessions and the lazy
    /// vars never rebuild (they're realized in `init`). Test-only on purpose — calling
    /// this on `DownloadManager.shared` would silently break all downloads for the
    /// rest of the process, so it must not exist in the app target.
    func invalidate() {
        wifiOnlyBackgroundSession.invalidateAndCancel()
        cellularBackgroundSession.invalidateAndCancel()
        cellularForegroundSession.invalidateAndCancel()
    }
}

class DBTestCase: XCTestCase {
    // We use a single DataManager instance for tests based on DBTestCase,
    // since some tests interact with the download logic.
    // Creating multiple DataManager instances cause the app delegate
    // to reference an outdated one with a closed database.
    // This issue is silently ignored when using FMDB, but GRDB surfaces an error.
    static var dataManager: DataManager!
    var dataManager: DataManager! {
        Self.dataManager
    }
    var downloadManager: DownloadManager!
    var podcast: Podcast!
    var episode: Episode!

    private var previousKeychainStore: KeychainStoring!

    private var trackedPodcasts: [Podcast] = []
    private var trackedEpisodes: [Episode] = []

    /// Register a podcast a test created beyond the base fixture so `tearDown`
    /// removes its row before the next test runs.
    func track(podcast: Podcast) {
        trackedPodcasts.append(podcast)
    }

    /// Register an episode a test created beyond the base fixture so `tearDown`
    /// removes its row and any downloaded file before the next test runs.
    func track(episode: Episode) {
        trackedEpisodes.append(episode)
    }

    override func setUp() async throws {
        try await super.setUp()
        // DB-backed tests shouldn't depend on real keychain state (which can fail
        // wholesale in CI). ServerSettingsPushTokenTests stays on the real keychain
        // as the integration canary.
        previousKeychainStore = KeychainHelper.store
        KeychainHelper.store = InMemoryKeychainStore()
        try setupData()
    }

    override func tearDown() async throws {
        // Cancel any download tasks the test queued and remove the rows it created,
        // so leftovers can't leak into later tests (e.g. checkForUnusedPodcasts
        // iterates all unsubscribed podcasts).
        if let episode {
            await downloadManager?.cancelTasks(for: [episode])
            removeDownloadAndRow(for: episode)
        }
        if let podcast {
            dataManager?.delete(podcast: podcast)
        }
        for episode in trackedEpisodes {
            removeDownloadAndRow(for: episode)
        }
        for podcast in trackedPodcasts {
            dataManager?.delete(podcast: podcast)
        }
        trackedEpisodes = []
        trackedPodcasts = []
        downloadManager?.invalidate()
        if let previousKeychainStore {
            KeychainHelper.store = previousKeychainStore
        }
        try await super.tearDown()
    }

    /// Removes an episode's downloaded file (if any) and its database row.
    private func removeDownloadAndRow(for episode: Episode) {
        if let path = downloadManager?.pathForEpisode(episode) {
            try? FileManager.default.removeItem(atPath: path)
        }
        dataManager?.delete(episodeUuid: episode.uuid)
    }

    private func setupDatabase() throws -> DataManager {
        DataManager.newTestDataManager()
    }

    private func setupData() throws {
        let dataManager = Self.dataManager == nil ? try setupDatabase() : Self.dataManager!
        // Each test gets its own DownloadManager, but background sessions are keyed
        // process-wide by identifier in nsurlsessiond. Reusing the production identifiers
        // across tests races tearDown's invalidate(): the next test's session can be born
        // invalidated ("Task created in a session that has been invalidated"). Unique
        // per-instance identifiers keep the sessions background-backed (so the daemon
        // canary tests still exercise it) without colliding.
        let downloadManager = DownloadManager(dataManager: dataManager, makeBaseConfiguration: { identifier in
            if let identifier {
                URLSessionConfiguration.background(withIdentifier: "\(identifier).\(UUID().uuidString)")
            } else {
                URLSessionConfiguration.default
            }
        })
        downloadManager.automaticallyStartDownloads = false
        DataManager.sharedManager = dataManager

        let podcast = Podcast()
        podcast.uuid = UUID().uuidString
        podcast.subscribed = 0
        podcast.addedDate = Date().addingTimeInterval(-1.week)
        podcast.syncStatus = SyncStatus.synced.rawValue

        dataManager.save(podcast: podcast)

        let episode = Episode()
        episode.uuid = UUID().uuidString
        episode.podcastUuid = podcast.uuid
        episode.podcast_id = podcast.id
        episode.addedDate = podcast.addedDate
        // RFC 5737 TEST-NET address: never routed publicly, so connection attempts hang
        // instead of succeeding or failing fast. That keeps queued download tasks in the
        // .running state long enough for cancellation tests, without real network traffic.
        episode.downloadUrl = "http://192.0.2.1/episode.mp3"
        episode.playingStatus = PlayingStatus.notPlayed.rawValue

        dataManager.save(episode: episode)
        Self.dataManager = dataManager
        self.downloadManager = downloadManager
        self.episode = episode
        self.podcast = podcast
    }

    func setUpQueuedDownload() async throws -> (PodcastManager, URLSessionTask) {
        let podcastManager = PodcastManager(dataManager: dataManager, downloadManager: downloadManager)
        episode.downloadUrl = "http://10.255.255.1/episode.mp3"
        dataManager.save(episode: episode)

        // Verify the podcast and episode exist in the data manager after being added in `setUp`
        XCTAssertEqual(dataManager.findPodcast(uuid: podcast.uuid, includeUnsubscribed: true), podcast)
        XCTAssertEqual(dataManager.findEpisode(uuid: episode.uuid), episode)

        // Add the episode to the download queue
        downloadManager.useForegroundSessionForDownloads = true
        downloadManager.automaticallyStartDownloads = true
        await downloadManager.performAddToQueue(
            episode: episode,
            url: episode.downloadUrl ?? "",
            previousDownloadFailed: false,
            fireNotification: false,
            autoDownloadStatus: .notSpecified
        )
        downloadManager.automaticallyStartDownloads = false
        downloadManager.useForegroundSessionForDownloads = false

        // Retrieve the download tasks for the episode
        let tasks = await downloadManager.tasks(for: [episode])

        // Ensure there is a task for the episode
        let task = try XCTUnwrap(tasks.first)

        // Check that the task is running to ensure it wasn't already cancelled somehow.
        XCTAssertEqual(task.state, URLSessionTask.State.running)

        return (podcastManager, task)
    }
}
