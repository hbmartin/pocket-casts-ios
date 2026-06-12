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

private final class DownloadManagingMock: DownloadManaging {
    private(set) var queuedEpisodeUuids: [String] = []

    var progressManager = DownloadProgressManager()
    var tempDownloadFolder = ""

    func addToQueue(episodeUuid: String, fireNotification: Bool, autoDownloadStatus: AutoDownloadStatus) {
        queuedEpisodeUuids.append(episodeUuid)
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
