import AVFoundation
import PocketCastsDataModel
import PocketCastsDependencyInjection
import XCTest

@testable import podcasts

final class DownloadManagerDependencyTests: XCTestCase {
    func testDefaultValueIsSharedDownloadManager() {
        let downloadManager = DefaultDependencyContainer.current.downloadManager

        XCTAssertTrue((downloadManager as AnyObject) === DownloadManager.shared)
    }

    func testOverridingWithMockInterceptsQueueing() {
        let original = DefaultDependencyContainer.current.downloadManager
        defer { DefaultDependencyContainer.current.downloadManager = original }

        let mock = DownloadManagingMock()
        DefaultDependencyContainer.current.downloadManager = mock

        DefaultDependencyContainer.current.downloadManager.addToQueue(episodeUuid: "episode-uuid")

        XCTAssertEqual(mock.queuedEpisodeUuids, ["episode-uuid"])
        XCTAssertTrue((DefaultDependencyContainer.current.downloadManager as AnyObject) === mock)
    }
}

// @unchecked Sendable: `queued` is guarded by `lock`. `tempDownloadFolder` is an immutable value and
// `progressManager` is an immutable `let` binding — its `DownloadProgressManager` has internal mutable
// state that isn't further synchronized here, which is acceptable for this single-threaded test double.
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
