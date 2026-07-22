import AVFoundation
import Dependencies
import PocketCastsDataModel
import XCTest

@testable import podcasts

final class DownloadManagerDependencyTests: XCTestCase {
    func testDefaultValueIsSharedDownloadManager() {
        withDependencies {
            $0.context = .live
        } operation: {
            @Dependency(\.downloadManager) var downloadManager
            XCTAssertTrue((downloadManager as AnyObject) === DownloadManager.shared)
        }
    }

    func testOverridingWithMockInterceptsQueueing() {
        let mock = DownloadManagingMock()
        withDependencies {
            $0.downloadManager = mock
        } operation: {
            @Dependency(\.downloadManager) var downloadManager
            downloadManager.addToQueue(episodeUuid: "episode-uuid")

            XCTAssertEqual(mock.queuedEpisodeUuids, ["episode-uuid"])
            XCTAssertTrue((downloadManager as AnyObject) === mock)
        }
    }
}

// `queued` is guarded by `lock`. `tempDownloadFolder` is an immutable value and
// `progressManager` is an immutable `let` binding — its `DownloadProgressManager` has internal mutable
// @unchecked Sendable: remaining mutable state belongs to this single-threaded test double.
private final class DownloadManagingMock: DownloadManaging, @unchecked Sendable {
    private let lock = NSLock()
    private var queued: [String] = []

    var queuedEpisodeUuids: [String] {
        lock.lock()
        defer { lock.unlock() }
        return queued
    }

    let progressManager = DownloadProgressManager()
    let tempDownloadFolder = ""

    func addToQueue(episodeUuid: String, fireNotification: Bool, autoDownloadStatus: AutoDownloadStatus) {
        lock.lock()
        defer { lock.unlock() }
        queued.append(episodeUuid)
    }

    func addToQueueForStreaming(episodeUuid: String) { }
    func queueForLaterDownload(episodeUuid: String, fireNotification: Bool, autoDownloadStatus: AutoDownloadStatus) { }
    func removeFromQueue(episodeUuid: String, fireNotification: Bool, userInitiated: Bool) { }
    func removeFromQueue(episode: BaseEpisode, fireNotification: Bool, userInitiated: Bool) { }
    func downloadParallelToStream(of episode: BaseEpisode) -> AVPlayerItem? { nil }
    func pathForEpisode(_ episode: BaseEpisode) -> String { "" }
    func addLocalFile(url: URL, uuid: String) throws -> URL? { nil }
    func updateProtectionPermissionsForAllExistingFiles() async { }
    func startAllQueued() { }
    func clearStuckDownloads() async { }
    func allTasks() async -> [URLSessionTask] { [] }
}
