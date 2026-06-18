import AVFoundation
import Dependencies
import Foundation
import PocketCastsDataModel

/// Consumer-facing surface of `DownloadManager`, registered in the dependency container as
/// `\.downloadManager` so consumers can be tested with a mock instead of the real download
/// pipeline. Covers the members call sites use today; extend it as adoption grows.
///
/// `Sendable` because the production conformer (`DownloadManager`) is an `@unchecked Sendable`
/// singleton already shared across threads; mocks must take the same responsibility.
protocol DownloadManaging: Sendable {
    var progressManager: DownloadProgressManager { get }
    var tempDownloadFolder: String { get }

    func addToQueue(episodeUuid: String, fireNotification: Bool, autoDownloadStatus: AutoDownloadStatus)
    func addToQueueForStreaming(episodeUuid: String)
    func queueForLaterDownload(episodeUuid: String, fireNotification: Bool, autoDownloadStatus: AutoDownloadStatus)
    func removeFromQueue(episodeUuid: String, fireNotification: Bool, userInitiated: Bool)
    func removeFromQueue(episode: BaseEpisode, fireNotification: Bool, userInitiated: Bool)
    func downloadParallelToStream(of episode: BaseEpisode) -> AVPlayerItem?
    func pathForEpisode(_ episode: BaseEpisode) -> String
    func addLocalFile(url: URL, uuid: String) throws -> URL?
    func updateProtectionPermissionsForAllExistingFiles() async
    func startAllQueued()
    func clearStuckDownloads() async
    func allTasks() async -> [URLSessionTask]
}

extension DownloadManaging {
    /// Protocols cannot declare default arguments; mirrors `DownloadManager.addToQueue(episodeUuid:autoDownloadStatus:)`.
    func addToQueue(episodeUuid: String, autoDownloadStatus: AutoDownloadStatus = .notSpecified) {
        addToQueue(episodeUuid: episodeUuid, fireNotification: true, autoDownloadStatus: autoDownloadStatus)
    }
}

extension DownloadManager: DownloadManaging { }

enum DownloadManagerKey: DependencyKey {
    static let liveValue: any DownloadManaging = DownloadManager.shared
}

extension DependencyValues {
    var downloadManager: any DownloadManaging {
        get { self[DownloadManagerKey.self] }
        set { self[DownloadManagerKey.self] = newValue }
    }
}
