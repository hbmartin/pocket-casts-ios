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
    func log(error _: any Error, context _: [String: String]?) {
        // Intentionally ignored by this dependency-wiring test double.
    }
}

private final class TestServerSyncDelegate: ServerSyncDelegate, Sendable {
    func podcastUpdated(podcastUuid _: String) { /* Intentional protocol no-op. */ }
    func podcastAdded(podcastUuid _: String) { /* Intentional protocol no-op. */ }
    func checkForUnusedPodcasts() { /* Intentional protocol no-op. */ }
    func applyAutoArchivingToAllPodcasts() { /* Intentional protocol no-op. */ }
    func subscribedToPodcast() { /* Intentional protocol no-op. */ }
    func playlistChanged() { /* Intentional protocol no-op. */ }
    func episodeStarredChanged(episode _: Episode) { /* Intentional protocol no-op. */ }
    func archiveEpisodeExternal(episode _: Episode) { /* Intentional protocol no-op. */ }
    func markEpisodeAsPlayedExternal(episode _: Episode) { /* Intentional protocol no-op. */ }
    func deselectedChaptersChanged() { /* Intentional protocol no-op. */ }
    func episodeCanBeCleanedUp(episode _: Episode) -> Bool { false }
    func autoDownloadLatestEpisodes(uuids _: [String]) { /* Intentional protocol no-op. */ }
    func cleanupAllUnusedEpisodeBuffers() { /* Intentional protocol no-op. */ }
    func performActionsAfterSync() { /* Intentional protocol no-op. */ }
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
    func inUpNext(episode _: BaseEpisode?) -> Bool { false }
    func addToUpNext(episode _: BaseEpisode, ignoringQueueLimit _: Bool, toTop _: Bool) { /* Intentional protocol no-op. */ }
    func removeLastEpisodeFromUpNext() { /* Intentional protocol no-op. */ }
    func currentEpisode() -> BaseEpisode? { nil }
    func isNowPlayingEpisode(episodeUuid _: String?) -> Bool { false }
    func isActivelyPlaying(episodeUuid _: String?) -> Bool { false }
    func queuePersistLocalCopyAsReplace() { /* Intentional protocol no-op. */ }
    func queueRefreshList(checkForAutoDownload _: Bool) { /* Intentional protocol no-op. */ }
    func allEpisodesInQueue(includeNowPlaying _: Bool) -> [BaseEpisode] { [] }
    func playingEpisodeChangedExternally() { /* Intentional protocol no-op. */ }
    func upNextQueueChanged() { /* Intentional protocol no-op. */ }
    func upNextQueueCount() -> Int { 0 }
    func seekToFromSync(time _: TimeInterval, syncChanges _: Bool, startPlaybackAfterSeek _: Bool) { /* Intentional protocol no-op. */ }
}
