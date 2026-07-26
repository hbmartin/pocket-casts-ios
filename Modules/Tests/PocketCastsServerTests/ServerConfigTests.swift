import PocketCastsDataModel
import Synchronization
@testable import PocketCastsServer
import XCTest

final class ServerConfigTests: XCTestCase {
    func testConfigurePublishesAllDependenciesTogether() {
        let config = ServerConfig()
        let syncDelegate = TestServerSyncDelegate()
        let playbackDelegate = TestServerPlaybackDelegate()
        let logger = TestServerErrorLogger()

        XCTAssertFalse(config.isConfigured)

        XCTAssertTrue(config.configure(
            syncDelegate: syncDelegate,
            playbackDelegate: playbackDelegate,
            errorLogger: logger
        ))

        XCTAssertTrue(config.isConfigured)
        XCTAssertTrue((config.syncDelegate as AnyObject?) === syncDelegate)
        XCTAssertTrue((config.playbackDelegate as AnyObject?) === playbackDelegate)
        XCTAssertTrue((config.errorLogger as AnyObject?) === logger)

        XCTAssertFalse(config.configure(
            syncDelegate: TestServerSyncDelegate(),
            playbackDelegate: TestServerPlaybackDelegate(),
            errorLogger: TestServerErrorLogger()
        ))
        XCTAssertTrue((config.syncDelegate as AnyObject?) === syncDelegate)
        XCTAssertTrue((config.playbackDelegate as AnyObject?) === playbackDelegate)
        XCTAssertTrue((config.errorLogger as AnyObject?) === logger)
    }

    func testConfiguredDependenciesSupportConcurrentReads() {
        let config = ServerConfig()
        let syncDelegate = TestServerSyncDelegate()
        let playbackDelegate = TestServerPlaybackDelegate()
        let logger = TestServerErrorLogger()
        config.configure(
            syncDelegate: syncDelegate,
            playbackDelegate: playbackDelegate,
            errorLogger: logger
        )
        let successfulReads = Mutex(0)

        DispatchQueue.concurrentPerform(iterations: 100) { _ in
            let allMatch = (config.syncDelegate as AnyObject?) === syncDelegate
                && (config.playbackDelegate as AnyObject?) === playbackDelegate
                && (config.errorLogger as AnyObject?) === logger
            if allMatch {
                successfulReads.withLock { $0 += 1 }
            }
        }

        XCTAssertEqual(successfulReads.withLock { $0 }, 100)
    }
}

private final class TestServerErrorLogger: ErrorLogger, Sendable {
    func log(error: any Error, context: [String: String]?) {}
}

private final class TestServerSyncDelegate: ServerSyncDelegate, Sendable {
    func podcastUpdated(podcastUuid: String) {}
    func podcastAdded(podcastUuid: String) {}
    func checkForUnusedPodcasts() {}
    func applyAutoArchivingToAllPodcasts() {}
    func subscribedToPodcast() {}
    func playlistChanged() {}
    func episodeStarredChanged(episode: Episode) {}
    func archiveEpisodeExternal(episode: Episode) {}
    func markEpisodeAsPlayedExternal(episode: Episode) {}
    func deselectedChaptersChanged() {}
    func episodeCanBeCleanedUp(episode: Episode) -> Bool { false }
    func autoDownloadLatestEpisodes(uuids: [String]) {}
    func cleanupAllUnusedEpisodeBuffers() {}
    func performActionsAfterSync() {}
    func isPushEnabled() -> Bool { false }
    func defaultPodcastGrouping() -> Int32 { 0 }
    func defaultShowArchived() -> Bool { false }
    func uniqueAppId() -> String { "test" }
    func appVersion() -> String { "test" }
    func privateUserAgent() -> String { "test" }
    func minTimeBetweenProgressSaves() -> Double { 0 }
    func production() -> Bool { false }
}

private final class TestServerPlaybackDelegate: ServerPlaybackDelegate, Sendable {
    func playing() -> Bool { false }
    func inUpNext(episode: BaseEpisode?) -> Bool { false }
    func addToUpNext(episode: BaseEpisode, ignoringQueueLimit: Bool, toTop: Bool) {}
    func removeLastEpisodeFromUpNext() {}
    func currentEpisode() -> BaseEpisode? { nil }
    func isNowPlayingEpisode(episodeUuid: String?) -> Bool { false }
    func isActivelyPlaying(episodeUuid: String?) -> Bool { false }
    func queuePersistLocalCopyAsReplace() {}
    func queueRefreshList(checkForAutoDownload: Bool) {}
    func allEpisodesInQueue(includeNowPlaying: Bool) -> [BaseEpisode] { [] }
    func playingEpisodeChangedExternally() {}
    func upNextQueueChanged() {}
    func upNextQueueCount() -> Int { 0 }
    func seekToFromSync(time: TimeInterval, syncChanges: Bool, startPlaybackAfterSeek: Bool) {}
}
