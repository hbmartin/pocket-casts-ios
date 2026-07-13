import Combine
import Foundation
import PackageDescription
import SwiftUI
import UIKit
import UserNotifications

let unsafePackageDependencies: [Package.Dependency] = [
    // ruleid: pocketcasts.spm-no-branch-dependencies
    .package(url: "https://example.com/mutable.git", branch: "main"),
    // ruleid: pocketcasts.spm-no-branch-dependencies
    .package(name: "NamedMutable", url: "https://example.com/named-mutable.git", branch: "main")
]

let safePackageDependencies: [Package.Dependency] = [
    // ok: pocketcasts.spm-no-branch-dependencies
    .package(url: "https://example.com/pinned.git", revision: "0123456789abcdef0123456789abcdef01234567"),
    // ok: pocketcasts.spm-no-branch-dependencies
    .package(url: "https://example.com/released.git", from: "1.0.0")
]

struct UnsafeStoriesView: View {
    @State private var timerSubscription: Cancellable?

    // ruleid: pocketcasts.swiftui-connectable-timer-publisher-must-be-state
    private let timer = Timer.publish(every: 0.02, on: .main, in: .common)

    var body: some View {
        Text("Unsafe")
            .onReceive(timer) { _ in }
    }
}

struct SafeStoriesView: View {
    @State private var timerSubscription: Cancellable?

    // ok: pocketcasts.swiftui-connectable-timer-publisher-must-be-state
    @State private var timer = Timer.publish(every: 0.02, on: .main, in: .common)

    var body: some View {
        Text("Safe")
            .onReceive(timer) { _ in }
    }
}

final class UnsafePodcastExistsHelper {
    private var checkedUuidsThatExist = Set<String>()
    private let lock = NSLock()

    func exists(uuid: String) -> Bool {
        // ruleid: pocketcasts.no-datamanager-query-while-holding-nslock
        lock.lock()
        defer { lock.unlock() }

        if checkedUuidsThatExist.contains(uuid) {
            return true
        }

        let exists = DataManager.sharedManager.findPodcast(uuid: uuid, includeUnsubscribed: true) != nil

        if exists {
            checkedUuidsThatExist.insert(uuid)
        }

        return exists
    }
}

final class UnsafeWithLockPodcastExistsHelper {
    private let lock = NSLock()

    func exists(uuid: String) -> Bool {
        // ruleid: pocketcasts.no-datamanager-query-while-holding-nslock
        lock.withLock {
            DataManager.sharedManager.findPodcast(uuid: uuid, includeUnsubscribed: true) != nil
        }
    }
}

final class SafePodcastExistsHelper {
    private var checkedUuidsThatExist = Set<String>()
    private let lock = NSLock()

    private func cachedExists(uuid: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        return checkedUuidsThatExist.contains(uuid)
    }

    func exists(uuid: String) -> Bool {
        if cachedExists(uuid: uuid) {
            return true
        }

        // ok: pocketcasts.no-datamanager-query-while-holding-nslock
        let exists = DataManager.sharedManager.findPodcast(uuid: uuid, includeUnsubscribed: true) != nil

        if exists {
            markExists(uuid: uuid)
        }

        return exists
    }

    private func markExists(uuid: String) {
        lock.lock()
        defer { lock.unlock() }

        checkedUuidsThatExist.insert(uuid)
    }
}

final class UnsafePlaylistSearchEscapingHelper {
    func operationSearch(searchTerm: String, playlist: EpisodeFilter) {
        // ruleid: pocketcasts.playlist-search-no-preescaped-like
        let escapedSearch = searchTerm.escapeLike(escapeChar: "\\")

        _ = PlaylistDetailFetchOperation(playlist: playlist, searchTerm: escapedSearch) { _, _ in }
    }

    func directSearch(searchTerm: String, playlist: EpisodeFilter, episodesDataManager: EpisodesDataManager) {
        // ruleid: pocketcasts.playlist-search-no-preescaped-like
        let escapedSearch = searchTerm.escapeLike(escapeChar: "\\")

        _ = episodesDataManager.playlistEpisodes(for: playlist, search: escapedSearch)
    }

    func operationSearchWithVar(searchTerm: String, playlist: EpisodeFilter) {
        // ruleid: pocketcasts.playlist-search-no-preescaped-like
        var escapedSearch = searchTerm.escapeLike(escapeChar: "\\")

        _ = PlaylistDetailFetchOperation(playlist: playlist, searchTerm: escapedSearch) { _, _ in }
    }

    func directSearchWithVar(searchTerm: String, playlist: EpisodeFilter, episodesDataManager: EpisodesDataManager) {
        // ruleid: pocketcasts.playlist-search-no-preescaped-like
        var escapedSearch = searchTerm.escapeLike(escapeChar: "\\")

        _ = episodesDataManager.playlistEpisodes(for: playlist, search: escapedSearch)
    }
}

final class SafePlaylistSearchEscapingHelper {
    func operationSearch(searchTerm: String, playlist: EpisodeFilter) {
        // ok: pocketcasts.playlist-search-no-preescaped-like
        _ = PlaylistDetailFetchOperation(playlist: playlist, searchTerm: searchTerm) { _, _ in }
    }

    func escapedForLegacyQuery(searchTerm: String) -> String {
        // ok: pocketcasts.playlist-search-no-preescaped-like
        searchTerm.escapeLike(escapeChar: "\\")
    }
}

final class UnsafeFileSyncUploadImportHelper {
    func relativePath(group: String?, fileName: String) -> String {
        // ruleid: pocketcasts.filesync-upload-group-must-be-validated
        let relative = group.flatMap { $0.isEmpty ? nil : "\($0)/\(fileName)" } ?? fileName
        return relative
    }
}

final class SafeFileSyncUploadImportHelper {
    func relativePath(group: String?, fileName: String) throws -> String {
        let group = try validate(group)
        // ok: pocketcasts.filesync-upload-group-must-be-validated
        return group.map { "\($0)/\(fileName)" } ?? fileName
    }

    private func validate(_ group: String?) throws -> String? {
        guard let group, !group.isEmpty else { return nil }
        guard group != ".", group != "..", !group.contains("/"), !group.contains("\\") else {
            throw NSError(domain: "test", code: 1)
        }
        return group
    }
}

final class UnsafeEpisodeTransferHelper {
    func prepare(episode: BaseEpisode) {
        // ruleid: pocketcasts.no-unsafe-transfer-episode
        _ = UnsafeTransfer(episode)
    }
}

final class UnsafeGenericEpisodeTransferHelper {
    func prepare(item: BaseEpisode) {
        // ruleid: pocketcasts.no-unsafe-transfer-episode
        _ = UnsafeTransfer(item)
    }
}

final class SafeEpisodeSnapshotHelper {
    func prepare(episode: BaseEpisode) {
        // ok: pocketcasts.no-unsafe-transfer-episode
        _ = EpisodeSnapshot(uuid: episode.uuid, duration: episode.duration)
    }

    private struct EpisodeSnapshot {
        let uuid: String
        let duration: Double
    }
}

final class UnsafeDisplayLinkOwner {
    private var displayLink: CADisplayLink?

    func start() {
        // ruleid: pocketcasts.cadisplaylink-no-self-target
        displayLink = CADisplayLink(target: self, selector: #selector(tick))
    }

    @objc private func tick() {}
}

final class SafeDisplayLinkOwner {
    private var displayLink: CADisplayLink?

    func start() {
        let target = DisplayLinkTarget {}
        // ok: pocketcasts.cadisplaylink-no-self-target
        displayLink = CADisplayLink(target: target, selector: #selector(DisplayLinkTarget.tick(_:)))
    }
}

private final class DisplayLinkTarget: NSObject {
    private let onTick: () -> Void

    init(onTick: @escaping () -> Void) {
        self.onTick = onTick
        super.init()
    }

    @objc func tick(_: CADisplayLink) {
        onTick()
    }
}

final class UnsafeKeychainGenericPasswordHelper {
    func query() -> [String: Any] {
        // ruleid: pocketcasts.keychain-generic-password-requires-account
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "au.com.shiftyjelly.podcasts.SJPushToken",
            kSecReturnData as String: kCFBooleanTrue as Any
        ]
    }
}

final class UnsafeReorderedKeychainGenericPasswordHelper {
    func query() -> [String: Any] {
        // ruleid: pocketcasts.keychain-generic-password-requires-account
        [
            kSecAttrService as String: "au.com.shiftyjelly.podcasts.SJPushToken",
            kSecClass as String: kSecClassGenericPassword,
            kSecReturnData as String: kCFBooleanTrue as Any
        ]
    }
}

final class SafeKeychainGenericPasswordHelper {
    func query() -> [String: Any] {
        // ok: pocketcasts.keychain-generic-password-requires-account
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "au.com.shiftyjelly.podcasts",
            kSecAttrAccount as String: "SJPushToken",
            kSecReturnData as String: kCFBooleanTrue as Any
        ]
    }
}

final class SafeReorderedKeychainGenericPasswordHelper {
    func query() -> [String: Any] {
        // ok: pocketcasts.keychain-generic-password-requires-account
        [
            kSecAttrService as String: "au.com.shiftyjelly.podcasts",
            kSecAttrAccount as String: "SJPushToken",
            kSecClass as String: kSecClassGenericPassword,
            kSecReturnData as String: kCFBooleanTrue as Any
        ]
    }
}

final class UnsafeServerCredentialsConfiguration {
    func setupSecrets() {
        // ruleid: pocketcasts.servercredentials-use-configure-sharing, pocketcasts.sharing-no-static-secret-signing
        ServerCredentials.sharing = "secret"
    }
}

final class SafeServerCredentialsConfiguration {
    func setupSecrets() {
        // ok: pocketcasts.servercredentials-use-configure-sharing
        ServerCredentials.configureSharing("secret")
    }
}

final class UnsafeNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    func openNotificationURL(url: URL) {
        // ruleid: pocketcasts.no-notificationdelegate-mainactor-assumeisolated
        MainActor.assumeIsolated {
            UIApplication.shared.open(url)
        }
    }
}

final class SafeNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    func openNotificationURL(url: URL) {
        Task { @MainActor in
            // ok: pocketcasts.no-notificationdelegate-mainactor-assumeisolated
            UIApplication.shared.open(url)
        }
    }
}

final class UnsafeBackgroundTaskExpirationHandler {
    func start() {
        var taskID: UIBackgroundTaskIdentifier = .invalid
        // ruleid: pocketcasts.background-task-expiration-main-thread
        taskID = UIApplication.shared.beginBackgroundTask(withName: "unsafe") {
            UIApplication.shared.endBackgroundTask(taskID)
            taskID = .invalid
        }
    }
}

final class SafeBackgroundTaskExpirationHandler {
    func start() {
        var taskID: UIBackgroundTaskIdentifier = .invalid
        taskID = UIApplication.shared.beginBackgroundTask(withName: "safe") {
            DispatchQueue.main.async {
                if taskID != .invalid {
                    // ok: pocketcasts.background-task-expiration-main-thread
                    UIApplication.shared.endBackgroundTask(taskID)
                    taskID = .invalid
                }
            }
        }
    }
}

final class UnsafeTimerRunLoopAssumption {
    private var timer: Timer?

    func startTimer() {
        timer = Timer(timeInterval: 1, repeats: false) { _ in
            MainActor.assumeIsolated {
                handleTick()
            }
        }

        // ruleid: pocketcasts.timer-assumeisolated-requires-main-runloop
        RunLoop.current.add(timer!, forMode: .default)
    }
}

final class SafeTimerRunLoopAssumption {
    private var timer: Timer?

    func startTimer() {
        timer = Timer(timeInterval: 1, repeats: false) { _ in
            MainActor.assumeIsolated {
                handleTick()
            }
        }

        // ok: pocketcasts.timer-assumeisolated-requires-main-runloop
        RunLoop.main.add(timer!, forMode: .default)
    }
}

final class UnsafePodcastSearchWait {
    private let dispatchGroup = DispatchGroup()

    func performSearch() -> Bool {
        // ruleid: pocketcasts.podcast-search-wait-timeout-result-required
        _ = dispatchGroup.wait(timeout: .now() + 15)
        return false
    }
}

final class SafePodcastSearchWait {
    private let dispatchGroup = DispatchGroup()

    func performSearch() -> Bool {
        let waitResult = dispatchGroup.wait(timeout: .now() + 15)
        guard waitResult == .success else {
            return false
        }

        // ok: pocketcasts.podcast-search-wait-timeout-result-required
        return true
    }
}

final class UnsafePodcastRetryBackoff {
    func retry(nextTry: Int) {
        // ruleid: pocketcasts.no-podcast-retry-thread-sleep
        Thread.sleep(forTimeInterval: nextTry.pollWaitingTime)
    }
}

final class SafePodcastRetryBackoff {
    func retry(nextTry: Int) {
        DispatchQueue.global().asyncAfter(deadline: .now() + nextTry.pollWaitingTime) {
            // ok: pocketcasts.no-podcast-retry-thread-sleep
            retryConnection()
        }
    }
}

final class UnsafeFuturePromiseCompletion {
    func logFileForUpload() -> AnyPublisher<String, Error> {
        Future { promise in
            do {
                try "log".write(toFile: "/tmp/log.txt", atomically: true, encoding: .utf8)
            } catch {
                // ruleid: pocketcasts.future-promise-failure-must-return-before-success
                promise.value(.failure(error))
            }

            promise.value(.success("/tmp/log.txt"))
        }
        .eraseToAnyPublisher()
    }
}

final class SafeFuturePromiseCompletion {
    func logFileForUpload() -> AnyPublisher<String, Error> {
        Future { promise in
            do {
                try "log".write(toFile: "/tmp/log.txt", atomically: true, encoding: .utf8)
            } catch {
                promise.value(.failure(error))
                return
            }

            // ok: pocketcasts.future-promise-failure-must-return-before-success
            promise.value(.success("/tmp/log.txt"))
        }
        .eraseToAnyPublisher()
    }
}

final class UnsafeReduceMotionAnimationView: UIView {
    private let iconLayer = CALayer()

    func spin() {
        let rotation = CABasicAnimation(keyPath: "transform.rotation.z")
        // ruleid: pocketcasts.core-animation-add-requires-reduce-motion-guard
        iconLayer.add(rotation, forKey: "spin")
    }
}

final class SafeReduceMotionAnimationView: UIView {
    private let iconLayer = CALayer()

    func spinWithGuard() {
        guard !UIAccessibility.isReduceMotionEnabled else { return }

        let rotation = CABasicAnimation(keyPath: "transform.rotation.z")
        // ok: pocketcasts.core-animation-add-requires-reduce-motion-guard
        iconLayer.add(rotation, forKey: "spin")
    }

    func spinWithIf() {
        let rotation = CABasicAnimation(keyPath: "transform.rotation.z")

        if !UIAccessibility.isReduceMotionEnabled {
            // ok: pocketcasts.core-animation-add-requires-reduce-motion-guard
            iconLayer.add(rotation, forKey: "spin")
        }
    }
}

final class UnsafeEpisodeListHeaderView {
    private var webURL: URL?

    @objc private func linkTapped() {
        guard let webURL else { return }

        // ruleid: pocketcasts.external-link-tap-requires-allowlist-guard
        URLHelper.open(
            webURL,
            context: .externalContent,
            options: .init()
        )
    }
}

final class SafeEpisodeListHeaderView {
    private var webURL: URL?

    @objc private func linkTapped() {
        guard let webURL, URLHelper.isAllowedExternalContentLink(webURL) else { return }

        // ok: pocketcasts.external-link-tap-requires-allowlist-guard
        URLHelper.open(
            webURL,
            context: .externalContent,
            options: .init()
        )
    }
}

final class UnsafeDatabaseSchemaResetHelper {
    // ruleid: pocketcasts.no-destructive-database-schema-reset
    private class func dropExistingSchema(db: PCDatabase) throws {
        try db.executeUpdate("DROP TABLE IF EXISTS SJPodcast;", values: nil)
    }
}

final class UnsafeSQLiteMasterBulkDropHelper {
    private class func resetTables(db: PCDatabase) throws {
        // ruleid: pocketcasts.no-destructive-database-schema-reset
        let resultSet = try db.executeQuery("""
            SELECT name FROM sqlite_master
            WHERE type = 'table'
        """, values: nil)

        while resultSet.next() {
            guard let table = resultSet.string(forColumn: "name") else { continue }
            try db.executeUpdate("DROP TABLE IF EXISTS \(table);", values: nil)
        }
    }
}

final class SafeDatabaseSchemaSetupHelper {
    private class func createCurrentSchema(db: PCDatabase) throws {
        // ok: pocketcasts.no-destructive-database-schema-reset
        try db.executeUpdate("CREATE TABLE SJPodcast (id INTEGER PRIMARY KEY);", values: nil)
    }
}

final class CredentialPlaceholderRegressionHelper {
    func isUnconfigured(_ id: String) -> Bool {
        // ruleid: pocketcasts.no-hardcoded-credential-placeholder-literal
        id == "%{telemetry_deck_app_id}"
    }

    func isUnconfiguredHyphenated(_ id: String) -> Bool {
        // ruleid: pocketcasts.no-hardcoded-credential-placeholder-literal
        id == "%{telemetry-deck-app-id}"
    }

    func isUnconfiguredPreferred(_ id: String) -> Bool {
        // ok: pocketcasts.no-hardcoded-credential-placeholder-literal
        id.isMissingOrPlaceholderCredential
    }
}

final class UnsafeNativeEmptyStateActionViewController {
    func refreshContentUnavailable() {
        _ = ContentUnavailableConfiguration.nativeEmptyState(
            title: "Empty",
            message: nil,
            image: nil,
            // ruleid: pocketcasts.native-empty-state-action-weak-self
            action: .init(title: "Add") {
                self.addPodcastsTapped(self)
            }
        )
    }

    func refreshContentUnavailableWithNestedScope() {
        _ = ContentUnavailableConfiguration.nativeEmptyState(
            title: "Empty",
            message: nil,
            image: nil,
            // ruleid: pocketcasts.native-empty-state-action-weak-self
            action: .init(title: "Add") {
                if Bool.random() {
                    handleNested()
                }

                self.addPodcastsTapped(self)
            }
        )
    }

    func addPodcastsTapped(_ sender: Any) {}
}

final class SafeNativeEmptyStateActionViewController {
    func refreshContentUnavailable() {
        _ = ContentUnavailableConfiguration.nativeEmptyState(
            title: "Empty",
            message: nil,
            image: nil,
            action: .init(title: "Add") { [weak self] in
                // ok: pocketcasts.native-empty-state-action-weak-self
                guard let self else { return }
                self.addPodcastsTapped(self)
            }
        )
    }

    func refreshContentUnavailableWithAdditionalCapture() {
        _ = ContentUnavailableConfiguration.nativeEmptyState(
            title: "Empty",
            message: nil,
            image: nil,
            action: .init(title: "Add") { [weak self, weak coordinator] in
                // ok: pocketcasts.native-empty-state-action-weak-self
                guard let self else { return }
                self.addPodcastsTapped(self)
            }
        )
    }

    func refreshContentUnavailableWithAdditionalCaptureAndParameter() {
        _ = ContentUnavailableConfiguration.nativeEmptyState(
            title: "Empty",
            message: nil,
            image: nil,
            action: .init(title: "Add") { [weak coordinator, weak self] sender in
                // ok: pocketcasts.native-empty-state-action-weak-self
                guard let self else { return }
                self.addPodcastsTapped(sender)
            }
        )
    }

    func addPodcastsTapped(_ sender: Any) {}
}

// ruleid: pocketcasts.public-protocol-no-mutable-combine-subject
public protocol UnsafeMutableSubjectLogging: Sendable {
    var publisher: PassthroughSubject<String, Never> { get }
}

// ok: pocketcasts.public-protocol-no-mutable-combine-subject
public protocol SafeErasedPublisherLogging: Sendable {
    var publisher: AnyPublisher<String, Never> { get }
}

final class UnsafeDownloadsViewControllerStrongNetworkPrompt {
    private func retryAllFailed() {
        // ruleid: pocketcasts.download-episode-requested-no-strong-self
        NetworkUtils.shared.downloadEpisodeRequested(autoDownloadStatus: .notSpecified, { later in
            if later {
                self.queueForLaterDownload()
            } else {
                self.addToQueue()
            }

            self.refreshView()
        }, disallowed: nil)
    }

    private func queueForLaterDownload() {}
    private func addToQueue() {}
    private func refreshView() {}
}

final class UnsafeDownloadsViewControllerInnerCapture {
    private let downloadManager = DownloadManager.shared

    func retry(episode: Episode) {
        _ = OptionAction(label: "Retry", icon: nil, action: {
            // ruleid: pocketcasts.download-episode-requested-no-strong-self
            NetworkUtils.shared.downloadEpisodeRequested(autoDownloadStatus: .notSpecified, { [downloadManager = self.downloadManager] later in
                if later {
                    downloadManager.queueForLaterDownload(episodeUuid: episode.uuid)
                } else {
                    downloadManager.addToQueue(episodeUuid: episode.uuid)
                }
            }, disallowed: nil)
        })
    }
}

final class SafeDownloadsViewControllerWeakNetworkPrompt {
    private func retryAllFailed() {
        // ok: pocketcasts.download-episode-requested-no-strong-self
        NetworkUtils.shared.downloadEpisodeRequested(autoDownloadStatus: .notSpecified, { [weak self] _ in
            guard let self else { return }
            self.refreshView()
        }, disallowed: nil)
    }

    private func refreshView() {}
}

final class SafeDownloadsViewControllerCapturedDependency {
    private let downloadManager = DownloadManager.shared

    func retry(episode: Episode) {
        _ = OptionAction(label: "Retry", icon: nil, action: { [downloadManager = self.downloadManager] in
            // ok: pocketcasts.download-episode-requested-no-strong-self
            NetworkUtils.shared.downloadEpisodeRequested(autoDownloadStatus: .notSpecified, { later in
                if later {
                    downloadManager.queueForLaterDownload(episodeUuid: episode.uuid)
                } else {
                    downloadManager.addToQueue(episodeUuid: episode.uuid)
                }
            }, disallowed: nil)
        })
    }
}

final class UnsafeListeningHistoryEmptyStateController {
    private var episodes = [String]()
    private var contentUnavailableConfiguration: UIContentConfiguration?

    private func refreshContentUnavailable() {
        var config: UIContentConfiguration?

        if episodes.isEmpty {
            config = ContentUnavailableConfiguration.empty()
            // ruleid: pocketcasts.content-unavailable-assigned-inside-empty-branch
            self.contentUnavailableConfiguration = config
        }
    }
}

final class SafeListeningHistoryEmptyStateController {
    private var episodes = [String]()
    private var contentUnavailableConfiguration: UIContentConfiguration?

    private func refreshContentUnavailable() {
        var config: UIContentConfiguration?

        if episodes.isEmpty {
            config = ContentUnavailableConfiguration.empty()
        }

        // ok: pocketcasts.content-unavailable-assigned-inside-empty-branch
        self.contentUnavailableConfiguration = config
    }
}

final class UnsafePlaylistCellViewModelFacadeBypass {
    private let episodesDataManager = EpisodesDataManager()
    private let playlist = EpisodeFilter()

    func loadListEpisodes() {
        // ruleid: pocketcasts.playlist-cell-bypass-datamanager-facade
        episodesDataManager.playlistFirstDistinctEpisodes(for: playlist, shouldShowArchived: true)
    }
}

final class SafePlaylistCellViewModelFacadeUse {
    private let dataManager = DataManager.sharedManager
    private let playlist = EpisodeFilter()

    func loadListEpisodes() {
        // ok: pocketcasts.playlist-cell-bypass-datamanager-facade
        dataManager.playlistFirstDistinctEpisodes(for: playlist, shouldShowArchived: true)
    }
}

final class UnsafePlaylistCellViewModelTaskGroupCapture {
    private let imageManager = ImageManager.sharedManager

    func loadImagesURLs(episodes: [Episode]) async throws -> [PlaylistArtworkView.ImageItem] {
        try await withThrowingTaskGroup(of: PlaylistArtworkView.ImageItem.self) { group in
            for episode in episodes {
                let podcastUuid = episode.podcastUuid
                // ruleid: pocketcasts.playlist-cell-task-group-image-manager-self-capture
                group.addTask {
                    let url = self.imageManager.podcastUrl(imageSize: .grid, uuid: podcastUuid)
                    return PlaylistArtworkView.ImageItem(id: podcastUuid, url: url)
                }
            }

            return []
        }
    }

    func loadNestedImagesURLs(episodes: [Episode]) async throws -> [PlaylistArtworkView.ImageItem] {
        try await withThrowingTaskGroup(of: PlaylistArtworkView.ImageItem.self) { group in
            for episode in episodes {
                let podcastUuid = episode.podcastUuid
                // ruleid: pocketcasts.playlist-cell-task-group-image-manager-self-capture
                group.addTask {
                    if Bool.random() {
                        handleNested()
                    }

                    let url = self.imageManager.podcastUrl(imageSize: .grid, uuid: podcastUuid)
                    return PlaylistArtworkView.ImageItem(id: podcastUuid, url: url)
                }
            }

            return []
        }
    }
}

final class SafePlaylistCellViewModelTaskGroupCapture {
    private let imageManager = ImageManager.sharedManager

    func loadImagesURLs(episodes: [Episode]) async throws -> [PlaylistArtworkView.ImageItem] {
        let imageManager = self.imageManager

        return try await withThrowingTaskGroup(of: PlaylistArtworkView.ImageItem.self) { group in
            for episode in episodes {
                let podcastUuid = episode.podcastUuid
                // ok: pocketcasts.playlist-cell-task-group-image-manager-self-capture
                group.addTask {
                    let url = imageManager.podcastUrl(imageSize: .grid, uuid: podcastUuid)
                    return PlaylistArtworkView.ImageItem(id: podcastUuid, url: url)
                }
            }

            return []
        }
    }
}

final class UnsafePlaylistCellViewModelEpisodeObjectCapture {
    private let imageManager = ImageManager.sharedManager

    func loadImagesURLs(episodes: [Episode]) async throws -> [PlaylistArtworkView.ImageItem] {
        let imageManager = self.imageManager

        return try await withThrowingTaskGroup(of: PlaylistArtworkView.ImageItem.self) { group in
            for episode in episodes {
                // ruleid: pocketcasts.playlist-cell-task-group-episode-object-capture
                group.addTask {
                    let url = imageManager.podcastUrl(imageSize: .grid, uuid: episode.podcastUuid)
                    return PlaylistArtworkView.ImageItem(id: episode.podcastUuid, url: url)
                }
            }

            return []
        }
    }

    func loadNestedImagesURLs(episodes: [Episode]) async throws -> [PlaylistArtworkView.ImageItem] {
        let imageManager = self.imageManager

        return try await withThrowingTaskGroup(of: PlaylistArtworkView.ImageItem.self) { group in
            for episode in episodes {
                // ruleid: pocketcasts.playlist-cell-task-group-episode-object-capture
                group.addTask {
                    if Bool.random() {
                        handleNested()
                    }

                    let url = imageManager.podcastUrl(imageSize: .grid, uuid: episode.uuid)
                    return PlaylistArtworkView.ImageItem(id: "nested", url: url)
                }
            }

            return []
        }
    }
}

final class SafePlaylistCellViewModelEpisodeObjectCapture {
    private let imageManager = ImageManager.sharedManager

    func loadImagesURLs(episodes: [Episode]) async throws -> [PlaylistArtworkView.ImageItem] {
        let imageManager = self.imageManager

        return try await withThrowingTaskGroup(of: PlaylistArtworkView.ImageItem.self) { group in
            for episode in episodes {
                let podcastUuid = episode.podcastUuid
                // ok: pocketcasts.playlist-cell-task-group-episode-object-capture
                group.addTask {
                    let url = imageManager.podcastUrl(imageSize: .grid, uuid: podcastUuid)
                    return PlaylistArtworkView.ImageItem(id: podcastUuid, url: url)
                }
            }

            return []
        }
    }
}

final class UnsafeClipExportToast {
    func show(error: Error) {
        // ruleid: pocketcasts.share-button-localized-clip-export-failure
        Toast.show("Failed clip export: \(error.localizedDescription)")
    }
}

final class SafeClipExportToast {
    func show(error: Error) {
        let format = L10n.localizedFormat("sharing_clip_export_failed", "Localizable", "Failed clip export: %@")
        // ok: pocketcasts.share-button-localized-clip-export-failure
        Toast.show(String(format: format, locale: Locale.current, error.localizedDescription))
    }
}

struct UnsafeNativeEmptyStateThemeColor {
    static func nativeEmptyState(title: String, message: String?, image: UIImage?) -> UIContentConfiguration {
        let themeType = Theme.sharedTheme.activeTheme
        var configuration = UIKit.UIContentUnavailableConfiguration.empty()
        // ruleid: pocketcasts.native-empty-state-themecolor-bypass
        configuration.imageProperties.tintColor = ThemeColor.primaryIcon01(for: themeType)
        return configuration
    }
}

struct SafeNativeEmptyStateThemeColor {
    static func nativeEmptyState(title: String, message: String?, image: UIImage?) -> UIContentConfiguration {
        let theme = Theme.sharedTheme
        var configuration = UIKit.UIContentUnavailableConfiguration.empty()
        // ok: pocketcasts.native-empty-state-themecolor-bypass
        configuration.imageProperties.tintColor = UIColor(AppTheme.color(for: .primaryIcon01, theme: theme))
        return configuration
    }
}

enum UnsafeFileManagerURLLookup {
    static var directory: URL {
        // ruleid: pocketcasts.filemanager-urls-no-force-index
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
}

enum UnsafeMultilineFileManagerURLLookup {
    static var directory: URL {
        // ruleid: pocketcasts.filemanager-urls-no-force-index
        FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        )[0]
    }
}

enum SafeFileManagerURLLookup {
    static var directory: URL {
        // ok: pocketcasts.filemanager-urls-no-force-index
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
    }
}

enum UnsafeOverlappingPointerUpdate {
    static func shiftLeft(_ data: UnsafeMutablePointer<Float32>, offset: Int, count: Int) {
        // ruleid: pocketcasts.unsafe-pointer-update-overlapping-source
        data.update(from: data + offset, count: count)
        // ruleid: pocketcasts.unsafe-pointer-update-overlapping-source
        data.update(from: data.advanced(by: offset), count: count)
    }

    static func shiftRight(_ data: UnsafeMutablePointer<Float32>, offset: Int, count: Int) {
        // ruleid: pocketcasts.unsafe-pointer-update-overlapping-source
        (data + offset).update(from: data, count: count)
        // ruleid: pocketcasts.unsafe-pointer-update-overlapping-source
        data.advanced(by: offset).update(from: data, count: count)
    }
}

enum SafePointerMove {
    static func copy(
        destination: UnsafeMutablePointer<Float32>,
        source: UnsafeMutablePointer<Float32>,
        count: Int
    ) {
        // ok: pocketcasts.unsafe-pointer-update-overlapping-source
        destination.update(from: source, count: count)
    }

    static func shift(_ data: UnsafeMutablePointer<Float32>, offset: Int, count: Int) {
        // ok: pocketcasts.unsafe-pointer-update-overlapping-source
        memmove(data, data + offset, count * MemoryLayout<Float32>.stride)
    }
}
