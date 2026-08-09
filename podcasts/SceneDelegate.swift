import AVFoundation
import Combine
import JLRoutes
import UIKit
import PocketCastsDataModel
import PocketCastsReadAloud
import PocketCastsServer
import PocketCastsUtils

class SceneDelegate: UIResponder, UISceneDelegate, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = (scene as? UIWindowScene) else { return }

        let window = UIWindow(windowScene: windowScene)
        self.window = window
        window.rootViewController = MainTabBarController()

        // Capture the system style before applying any window-level override so the
        // initial value reflects the actual system, not our override.
        Theme.systemIsDark = (windowScene.traitCollection.userInterfaceStyle == .dark)
        window.applyInterfaceStyleForActiveTheme()
        themeToken = NotificationCenter.default.addObserver(for: ThemeChanged.self) { [weak self] _ in
            self?.window?.applyInterfaceStyleForActiveTheme()
        }

        window.makeKeyAndVisible()

        #if DEBUG
        UITestScenarioLauncher.publishReadinessMarker(in: window)
        UITestLogCapture.start(in: window)
        UITestScenarioLauncher.exerciseCannedRefreshIfRequested(in: window)
        PR263UITestHarness.exerciseIfRequested(in: window)
        PR264UITestHarness.exerciseIfRequested()
        MediaConcurrencyUITestHarness.exerciseIfRequested()
        ReadAloudIntentUITestHarness.exerciseIfRequested()
        #endif

        if let shortcutItem = connectionOptions.shortcutItem {
            appDelegate()?.handleShortcutItem(shortcutItem)
        }
        if let url = connectionOptions.urlContexts.first?.url, let rootViewController = window.rootViewController {
            _ = appDelegate()?.handleOpenUrl(url: url, rootViewController: rootViewController)
        }
        if let userActivity = connectionOptions.userActivities.first {
            appDelegate()?.handleContinue(userActivity)
        }
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        appDelegate()?.handleBecomeActive()
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        appDelegate()?.handleEnterBackground()
    }

    func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
        appDelegate()?.handleContinue(userActivity)
    }

    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        guard !URLContexts.isEmpty, let url = URLContexts.first?.url, let rootViewController = window?.rootViewController else {
            return
        }
        _ = appDelegate()?.handleOpenUrl(url: url, rootViewController: rootViewController)
    }

    func windowScene(_ windowScene: UIWindowScene,
                     performActionFor shortcutItem: UIApplicationShortcutItem,
                     completionHandler: @escaping (Bool) -> Void) {
        appDelegate()?.handleShortcutItem(shortcutItem)
    }

    private var themeToken: NotificationCenter.ObservationToken?

    deinit {
        let token = themeToken
        if let token {
            NotificationCenter.default.removeObserver(token)
        }
    }
}

#if DEBUG
@MainActor
enum UITestScenarioLauncher {
    private enum Scenario: String {
        case libraryWithQueue
        case playbackQueuePersistence
        case folderOrganizationPersistence
    }

    private enum LaunchMode: String {
        case seed
        case preserve
    }

    private static let scenarioEnvironment = "UI_TEST_SCENARIO"
    private static let launchModeEnvironment = "UI_TEST_SCENARIO_MODE"
    private static let cannedRefreshEnvironment = "POCKET_CASTS_UI_TEST_EXERCISE_CANNED_REFRESH"
    private static let readyIdentifier = "uiTestAppReady"
    private static weak var cannedRefreshWindow: UIWindow?

    private static var requestedScenario: Scenario? {
        ProcessInfo.processInfo.environment[scenarioEnvironment].flatMap(Scenario.init(rawValue:))
    }

    private static var launchMode: LaunchMode {
        ProcessInfo.processInfo.environment[launchModeEnvironment]
            .flatMap(LaunchMode.init(rawValue:)) ?? .seed
    }

    static func prepareIfRequested() {
        guard let scenario = requestedScenario else { return }

        _ = URLProtocol.registerClass(UITestCannedURLProtocol.self)
        configureStableUserState()
        if launchMode == .seed {
            resetDatabase()

            switch scenario {
            case .libraryWithQueue:
                seedLibraryWithQueue()
            case .playbackQueuePersistence:
                seedPlaybackQueuePersistence()
            case .folderOrganizationPersistence:
                seedFolderOrganizationPersistence()
            }
        }

        FileLog.shared.addMessage(
            "UI test scenario prepared: \(scenario.rawValue), mode: \(launchMode.rawValue)"
        )
    }

    static func publishReadinessMarker(in window: UIWindow) {
        guard let scenario = requestedScenario else { return }

        let dataManager = DataManager.sharedManager
        let podcasts = dataManager.allPodcasts(includeUnsubscribed: true)
        let episodes = podcasts.flatMap { podcast in
            dataManager.allEpisodesForPodcast(id: podcast.id)
        }
        let value = [
            scenario.rawValue,
            "mode=\(launchMode.rawValue)",
            "podcasts=\(podcasts.count)",
            "episodes=\(episodes.count)",
            "downloaded=\(episodes.filter { $0.episodeStatus == DownloadStatus.downloaded.rawValue }.count)",
            "upNext=\(dataManager.playlistEpisodeCount())",
            "folders=\(dataManager.allFolders().count)",
            "organized=\(podcasts.filter { $0.folderUuid != nil }.count)",
            "account=signedOut",
            "network=canned"
        ].joined(separator: "|")
        UITestAccessibilityMarker.add(identifier: readyIdentifier, value: value, to: window)
    }

    static func exerciseCannedRefreshIfRequested(in window: UIWindow) {
        guard requestedScenario != nil,
              ProcessInfo.processInfo.environment[cannedRefreshEnvironment] == "1" else { return }

        cannedRefreshWindow = window
        RefreshManager.shared.refreshPodcasts { result in
            let resultName: String
            switch result {
            case .newData:
                resultName = "newData"
            case .noData:
                resultName = "noData"
            case .failed:
                resultName = "failed"
            }

            Task { @MainActor in
                publishCannedRefreshResult(resultName)
            }
        }
    }

    private static func publishCannedRefreshResult(_ result: String) {
        guard let window = cannedRefreshWindow else { return }

        let dataManager = DataManager.sharedManager
        let episodes = dataManager.allPodcasts(includeUnsubscribed: true).flatMap { podcast in
            dataManager.allEpisodesForPodcast(id: podcast.id)
        }
        let value = [
            "result=\(result)",
            "episodes=\(episodes.count)",
            "archived=\(episodes.filter(\.archived).count)",
            "downloaded=\(episodes.filter { $0.episodeStatus == DownloadStatus.downloaded.rawValue }.count)"
        ].joined(separator: "|")
        UITestAccessibilityMarker.add(identifier: "uiTestCannedRefreshCompleted", value: value, to: window)
    }

    private static func configureStableUserState() {
        Settings.shouldShowInitialOnboardingFlow = false
        SyncManager.clearTokensFromKeyChain()
        ServerSettings.userId = nil
        ServerSettings.removePushToken()

        let overrides = FeatureFlagOverrideStore()
        overrides.resetOverrides()
        try? overrides.override(FeatureFlag.newSettingsStorage, withValue: false)
        try? overrides.override(FeatureFlag.useFollowNaming, withValue: false)

        Settings.setPrimaryRowAction(.stream)
        Settings.setLibraryType(.list)

        // The selected tab is persisted, and MainTabBarController restores it on
        // launch — so a test that navigates away leaves the *next* test starting
        // somewhere else, and every assertion about seeded content silently
        // looks at the wrong screen. Clearing it is what makes "seeded" mean the
        // same thing however the previous test ended.
        UserDefaults.standard.removeObject(forKey: Constants.UserDefaults.lastTabOpened)
    }

    private static func resetDatabase() {
        let dataManager = DataManager.sharedManager

        dataManager.deleteAllUpNextEpisodes()
        for playlist in dataManager.allPlaylists(includeDeleted: true) {
            dataManager.delete(playlist: playlist)
        }
        for userEpisode in dataManager.allUserEpisodes(sortedBy: .newestToOldest) {
            dataManager.delete(userEpisodeUuid: userEpisode.uuid)
        }
        for podcast in dataManager.allPodcasts(includeUnsubscribed: true) {
            dataManager.deleteAllEpisodesInPodcast(podcastId: podcast.id)
            dataManager.delete(podcast: podcast)
        }
        dataManager.clearAllFolderInformation()
        resetReadAloudLibrary(dataManager: dataManager)
    }

    /// Read Aloud documents survive the loop above — they are their own tables,
    /// and their episodes are user episodes that would already have been deleted
    /// out from under them, leaving narrations pointing at nothing. Goes through
    /// the importer so the retained source files and render workspaces go too,
    /// rather than accumulating on disk across every seeded run.
    private static func resetReadAloudLibrary(dataManager: DataManager) {
        let importer = NarrationImporter(dataManager: dataManager)
        for entry in dataManager.readAloud.library() {
            importer.delete(document: entry.document)
        }
    }

    private static func seedLibraryWithQueue() {
        let dataManager = DataManager.sharedManager

        let podcast = savePodcast(
            uuid: "ui-test-podcast",
            title: "UI Test Library",
            addedDate: Date(timeIntervalSince1970: 1_700_000_000)
        )

        let episodes = [
            makeEpisode(
                uuid: "ui-test-episode-one",
                title: "Queued Episode One",
                position: 0,
                podcast: podcast
            ),
            makeEpisode(
                uuid: "ui-test-episode-two",
                title: "Queued Episode Two",
                position: 1,
                podcast: podcast
            )
        ]

        for (episode, playlistEpisode) in episodes {
            dataManager.save(episode: episode)
            dataManager.save(playlistEpisode: playlistEpisode)
        }
    }

    private static func seedPlaybackQueuePersistence() {
        let dataManager = DataManager.sharedManager
        let podcast = savePodcast(
            uuid: "ui-test-playback-podcast",
            title: "UI Test Playback Podcast",
            addedDate: Date(timeIntervalSince1970: 1_700_001_000)
        )

        for (index, title) in [
            "Playback Episode One",
            "Queue Episode Two",
            "Spare Episode Three"
        ].enumerated() {
            var (episode, _) = makeEpisode(
                uuid: "ui-test-playback-episode-\(index + 1)",
                title: title,
                position: Int32(index),
                podcast: podcast
            )
            if index == 0 {
                episode.downloadUrl = "https://ui-test.pocketcasts.invalid/\(episode.uuid).wav"
                installDownloadedAudioFixture(for: episode)
                episode.episodeStatus = DownloadStatus.downloaded.rawValue
                episode.duration = 180
            }
            dataManager.save(episode: episode)
        }
    }

    private static func installDownloadedAudioFixture(for episode: Episode) {
        let destinationURL = URL(fileURLWithPath: DownloadManager.shared.pathForEpisode(episode))
        let fileManager = FileManager.default

        do {
            try fileManager.createDirectory(
                at: destinationURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            try silentWaveAudio().write(to: destinationURL, options: .atomic)
        } catch {
            preconditionFailure("Unable to install the UI test audio fixture: \(error)")
        }
    }

    private static func silentWaveAudio() -> Data {
        let sampleRate: UInt32 = 8_000
        let duration: UInt32 = 180
        let dataSize = sampleRate * duration

        var data = Data()
        data.append(contentsOf: "RIFF".utf8)
        appendLittleEndian(36 + dataSize, to: &data)
        data.append(contentsOf: "WAVEfmt ".utf8)
        appendLittleEndian(UInt32(16), to: &data)
        appendLittleEndian(UInt16(1), to: &data)
        appendLittleEndian(UInt16(1), to: &data)
        appendLittleEndian(sampleRate, to: &data)
        appendLittleEndian(sampleRate, to: &data)
        appendLittleEndian(UInt16(1), to: &data)
        appendLittleEndian(UInt16(8), to: &data)
        data.append(contentsOf: "data".utf8)
        appendLittleEndian(dataSize, to: &data)
        data.append(contentsOf: repeatElement(UInt8(128), count: Int(dataSize)))
        return data
    }

    private static func appendLittleEndian<Integer: FixedWidthInteger>(
        _ value: Integer,
        to data: inout Data
    ) {
        var value = value.littleEndian
        withUnsafeBytes(of: &value) { bytes in
            data.append(contentsOf: bytes)
        }
    }

    private static func seedFolderOrganizationPersistence() {
        savePodcast(
            uuid: "ui-test-organization-podcast-one",
            title: "Organization Podcast One",
            addedDate: Date(timeIntervalSince1970: 1_700_002_000)
        )
        savePodcast(
            uuid: "ui-test-organization-podcast-two",
            title: "Organization Podcast Two",
            addedDate: Date(timeIntervalSince1970: 1_700_002_100)
        )
    }

    @discardableResult
    private static func savePodcast(uuid: String, title: String, addedDate: Date) -> Podcast {
        let dataManager = DataManager.sharedManager

        var podcast = Podcast()
        podcast.addedDate = addedDate
        podcast.title = title
        podcast.author = "Pocket Casts Testing"
        podcast.uuid = uuid
        podcast.podcastUrl = "https://ui-test.pocketcasts.invalid/\(uuid).xml"
        podcast.subscribed = 1
        podcast.syncStatus = SyncStatus.synced.rawValue
        dataManager.save(podcast: podcast)
        return dataManager.allPodcasts(includeUnsubscribed: true, reloadFromDatabase: true)
            .first(where: { $0.uuid == uuid }) ?? podcast
    }

    private static func makeEpisode(
        uuid: String,
        title: String,
        position: Int32,
        podcast: Podcast
    ) -> (Episode, PlaylistEpisode) {
        var episode = Episode()
        episode.addedDate = Date(timeIntervalSince1970: 1_700_000_100 + Double(position))
        episode.publishedDate = episode.addedDate
        episode.title = title
        episode.uuid = uuid
        episode.podcastUuid = podcast.uuid
        episode.podcast_id = podcast.id
        episode.downloadUrl = "https://ui-test.pocketcasts.invalid/\(uuid).mp3"
        episode.episodeStatus = DownloadStatus.notDownloaded.rawValue
        episode.playingStatus = PlayingStatus.notPlayed.rawValue
        episode.duration = 1_800

        var playlistEpisode = PlaylistEpisode()
        playlistEpisode.episodePosition = position
        playlistEpisode.episodeUuid = uuid
        playlistEpisode.title = title
        playlistEpisode.podcastUuid = podcast.uuid
        return (episode, playlistEpisode)
    }
}

nonisolated final class UITestCannedURLProtocol: URLProtocol {
    private static let handledKey = "PocketCastsUITestCannedURLProtocolHandled"

    override class func canInit(with request: URLRequest) -> Bool {
        guard ProcessInfo.processInfo.environment["UI_TEST_SCENARIO"] != nil,
              URLProtocol.property(forKey: handledKey, in: request) == nil,
              let scheme = request.url?.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }

        let responseBody: Data
        let contentType: String
        switch url.pathExtension.lowercased() {
        case "jpg", "jpeg", "png":
            responseBody = Data(base64Encoded: Self.transparentPixel) ?? Data()
            contentType = "image/png"
        case "mp3", "m4a":
            responseBody = Data("ID3UI-TEST-AUDIO".utf8)
            contentType = "audio/mpeg"
        case _ where url.path.hasSuffix("/user/update"):
            // A successful refresh with no result leaves seeded episodes intact.
            // An empty result object is interpreted as an empty feed and archives them.
            responseBody = Data("{\"status\":\"ok\",\"result\":null}".utf8)
            contentType = "application/json"
            FileLog.shared.addMessage("UI test canned /user/update response served with result=null")
        default:
            responseBody = Data("{\"status\":\"ok\",\"result\":{}}".utf8)
            contentType = "application/json"
        }

        let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: [
                "Content-Type": contentType,
                "Content-Length": String(responseBody.count)
            ]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: responseBody)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static let transparentPixel =
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
}

@MainActor
enum UITestAccessibilityMarker {
    @discardableResult
    static func add(identifier: String, value: String? = nil, to window: UIWindow) -> UIView {
        if let existing = window.subviews.first(where: { $0.accessibilityIdentifier == identifier }) {
            existing.accessibilityValue = value
            return existing
        }

        let marker = UIView(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
        marker.isAccessibilityElement = true
        marker.accessibilityIdentifier = identifier
        marker.accessibilityLabel = identifier
        marker.accessibilityValue = value
        window.addSubview(marker)
        return marker
    }

    /// For harnesses that finish after launch and have no window in hand.
    static func addToKeyWindow(identifier: String, value: String? = nil) {
        guard let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap(\.windows)
            .first(where: \.isKeyWindow) else { return }
        add(identifier: identifier, value: value, to: window)
    }
}

@MainActor
enum UITestLogCapture {
    private static let captureEnvironment = "POCKET_CASTS_UI_TEST_CAPTURE_LOGS"
    private static let markerIdentifier = "uiTestCapturedLogs"
    private static let maximumCharacters = 16_000
    private static var capturedLogs = ""
    private static var cancellable: AnyCancellable?
    private static weak var marker: UIView?

    static func start(in window: UIWindow) {
        guard ProcessInfo.processInfo.environment[captureEnvironment] == "1" else { return }

        marker = UITestAccessibilityMarker.add(identifier: markerIdentifier, to: window)
        cancellable = FileLog.shared.publisher
            .receive(on: DispatchQueue.main)
            .sink { message in
                append(message)
            }

        Task {
            append(await FileLog.shared.logFileAsString())
        }
    }

    private static func append(_ message: String) {
        capturedLogs.append(message)
        capturedLogs.append("\n")
        if capturedLogs.count > maximumCharacters {
            capturedLogs = String(capturedLogs.suffix(maximumCharacters))
        }
        marker?.accessibilityValue = capturedLogs
    }
}

/// Deterministic integration coverage for the backup, restore, URL-redaction, and
/// mirror-path fixes exercised from XCUITest. The harness uses the seeded UI-test
/// database and publishes only a compact accessibility result marker.
@MainActor
enum PR263UITestHarness {
    private static let environment = "POCKET_CASTS_UI_TEST_EXERCISE_PR263_FIXES"
    private static let completedIdentifier = "pr263FixesCompleted"
    private static let failedIdentifier = "pr263FixesFailed"

    static func exerciseIfRequested(in window: UIWindow) {
        guard ProcessInfo.processInfo.environment[environment] == "1" else { return }

        do {
            let result = try exerciseFixes()
            UITestAccessibilityMarker.add(identifier: completedIdentifier, value: result, to: window)
        } catch {
            UITestAccessibilityMarker.add(
                identifier: failedIdentifier,
                value: error.localizedDescription,
                to: window
            )
        }
    }

    private static func exerciseFixes() throws -> String {
        let fileManager = FileManager.default
        let dataManager = DataManager.sharedManager
        let restoreURL = fileManager.temporaryDirectory
            .appendingPathComponent("pr263-restore-\(UUID().uuidString).sqlite3")
        defer { try? fileManager.removeItem(at: restoreURL) }

        try dataManager.backupDatabase(to: restoreURL.path)

        var folder = Folder()
        folder.uuid = "pr263-folder"
        folder.name = "Restore must remove this folder"
        folder.addedDate = Date()
        _ = dataManager.save(folder: folder)
        guard dataManager.findFolder(uuid: folder.uuid) != nil else {
            throw HarnessError.fixtureCreationFailed
        }

        guard dataManager.restoreAllData(fromPath: restoreURL.path),
              dataManager.findFolder(uuid: folder.uuid) == nil,
              !dataManager.allFolders(includeDeleted: true).contains(where: { $0.uuid == folder.uuid }) else {
            throw HarnessError.restoreDidNotReplaceCachedFolderState
        }

        let stagedBackup = try BackupRestoreView.stageBackupFolder()
        defer { try? fileManager.removeItem(at: stagedBackup) }
        let backupName = stagedBackup.lastPathComponent
        let backupNamePattern = /^Pocket Casts Backup \d{4}-\d{2}-\d{2} \d{2}\.\d{2}$/
        guard backupName.wholeMatch(of: backupNamePattern) != nil,
              fileManager.fileExists(atPath: stagedBackup.appendingPathComponent("library.sqlite3").path) else {
            throw HarnessError.invalidBackupFolder
        }

        return "restore=atomic|folderCache=refreshed|backupFolder=stable"
    }

    private enum HarnessError: LocalizedError {
        case fixtureCreationFailed
        case restoreDidNotReplaceCachedFolderState
        case invalidBackupFolder

        var errorDescription: String? {
            String(describing: self)
        }
    }
}

/// Deterministic app-process coverage for the three PR #264 concurrency fixes.
/// XCUITest selects one scenario per launch and observes the published result marker.
@MainActor
enum PR264UITestHarness {
    private static let environment = "POCKET_CASTS_UI_TEST_EXERCISE_PR264_FIX"
    private static let completedIdentifier = "pr264FixCompleted"
    private static let failedIdentifier = "pr264FixFailed"

    private enum Scenario: String, Sendable {
        case opmlImportState
    }

    static func exerciseIfRequested() {
        guard let rawScenario = ProcessInfo.processInfo.environment[environment],
              let scenario = Scenario(rawValue: rawScenario) else { return }

        Task { @concurrent in
            do {
                let result = try await exercise(scenario)
                await publish(identifier: completedIdentifier, value: result)
            } catch {
                await publish(
                    identifier: failedIdentifier,
                    value: "\(scenario.rawValue):\(error.localizedDescription)"
                )
            }
        }
    }

    nonisolated private static func exercise(_ scenario: Scenario) async throws -> String {
        switch scenario {
        case .opmlImportState:
            return try await exerciseOpmlImportState()
        }
    }

    nonisolated private static func exerciseOpmlImportState() async throws -> String {
        let state = OpmlImportState()
        let updateCount = 200

        await withTaskGroup(of: Void.self) { group in
            for index in 0..<updateCount {
                group.addTask {
                    state.recordResponse(pollUuids: ["poll-\(index)"], failedCount: 1)
                    _ = state.updateProgress(failed: true)
                }
            }
        }

        let pollUuids = state.takePollUuids() ?? []
        let expectedUuids = Set((0..<updateCount).map { "poll-\($0)" })
        guard Set(pollUuids) == expectedUuids,
              state.takePollUuids() == nil,
              state.updateProgress() == updateCount + 1,
              state.failureCount == updateCount * 2 else {
            throw HarnessError.opmlStateWasNotAtomic
        }

        return "opmlState=atomic|responses=\(updateCount)|failures=\(state.failureCount)"
    }

    private static func publish(identifier: String, value: String) {
        guard let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap(\.windows)
            .first(where: \.isKeyWindow) else { return }
        UITestAccessibilityMarker.add(identifier: identifier, value: value, to: window)
    }

    private enum HarnessError: LocalizedError {
        case opmlStateWasNotAtomic

        var errorDescription: String? {
            String(describing: self)
        }
    }
}

/// Debug-only app-side driver for deterministic XCUITest coverage of APIs that
/// are called by system frameworks from background threads.
@MainActor
enum MediaConcurrencyUITestHarness {
    private static let artworkEnvironment = "POCKET_CASTS_UI_TEST_EXERCISE_ARTWORK_HANDLERS"
    private static let audioSessionEnvironment = "POCKET_CASTS_UI_TEST_EXERCISE_AUDIO_SESSION_NOTIFICATIONS"
    private static let artworkCompletedIdentifier = "mediaConcurrencyArtworkHandlersCompleted"
    private static let artworkFailedIdentifier = "mediaConcurrencyArtworkHandlersFailed"
    private static let audioSessionCompletedIdentifier = "mediaConcurrencyAudioSessionNotificationsCompleted"
    private static var handledAudioSessionNotifications = Set<Notification.Name>()

    private static let expectedAudioSessionNotifications: Set<Notification.Name> = [
        AVAudioSession.routeChangeNotification,
        AVAudioSession.interruptionNotification,
        AVAudioSession.mediaServicesWereResetNotification
    ]

    static func exerciseIfRequested() {
        let environment = ProcessInfo.processInfo.environment

        if environment[artworkEnvironment] == "1" {
            NowPlayingHelper.exerciseArtworkRequestHandlersForUITesting()
        }

        if environment[audioSessionEnvironment] == "1" {
            // Initialize the live coordinator before posting its system notifications.
            _ = PlaybackManager.shared
            postAudioSessionNotificationsOffMain()
        }
    }

    static func artworkRequestHandlersCompleted(succeeded: Bool) {
        guard ProcessInfo.processInfo.environment[artworkEnvironment] == "1" else { return }
        addMarker(identifier: succeeded ? artworkCompletedIdentifier : artworkFailedIdentifier)
    }

    static func audioSessionNotificationHandled(_ name: Notification.Name) {
        guard ProcessInfo.processInfo.environment[audioSessionEnvironment] == "1" else { return }

        handledAudioSessionNotifications.insert(name)
        if expectedAudioSessionNotifications.isSubset(of: handledAudioSessionNotifications) {
            addMarker(identifier: audioSessionCompletedIdentifier)
        }
    }

    private static func postAudioSessionNotificationsOffMain() {
        let notificationCenter = NotificationCenter.default
        Task.detached {
            notificationCenter.post(name: AVAudioSession.routeChangeNotification, object: nil)
            notificationCenter.post(name: AVAudioSession.interruptionNotification, object: nil)
            notificationCenter.post(name: AVAudioSession.mediaServicesWereResetNotification, object: nil)
        }
    }

    private static func addMarker(identifier: String) {
        guard let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap(\.windows)
            .first(where: \.isKeyWindow),
              !window.subviews.contains(where: { $0.accessibilityIdentifier == identifier }) else { return }

        let marker = UIView(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
        marker.isAccessibilityElement = true
        marker.accessibilityIdentifier = identifier
        window.addSubview(marker)
    }
}

/// Debug-only driver for `CreateNarrationIntent`, which no UI can reach.
///
/// An App Intent is invoked by the Shortcuts app, out of process, so XCUITest
/// cannot drive it and a unit test cannot start it — but it is the one Read
/// Aloud entry point that can run with nobody watching, which is exactly why
/// its consent gate needs proving. This runs `perform()` in the live app and
/// publishes what it did.
@MainActor
enum ReadAloudIntentUITestHarness {
    private static let environment = "POCKET_CASTS_UI_TEST_EXERCISE_READ_ALOUD_INTENT"
    private static let completedIdentifier = "readAloudIntentCompleted"
    private static let failedIdentifier = "readAloudIntentFailed"

    static func exerciseIfRequested() {
        guard ProcessInfo.processInfo.environment[environment] == "1" else { return }

        Task { @MainActor in
            do {
                let result = try await exercise()
                UITestAccessibilityMarker.addToKeyWindow(identifier: completedIdentifier, value: result)
            } catch {
                UITestAccessibilityMarker.addToKeyWindow(
                    identifier: failedIdentifier,
                    value: String(describing: error)
                )
            }
        }
    }

    private static func exercise() async throws -> String {
        let paidUnconfirmed = await runPaid(confirmed: false)
        let paidConfirmed = await runPaid(confirmed: true)
        let free = await runFree()
        return "paidUnconfirmed=\(paidUnconfirmed)|paidConfirmed=\(paidConfirmed)|free=\(free)"
    }

    /// Points the intent at the paid engine with a key present, so the only
    /// thing separating the two runs is consent.
    ///
    /// With consent it is *expected* to fail later, at the voice list: the key
    /// is a placeholder and the catalog comes back empty. That later failure is
    /// the point — it proves the gate, and not something else, is what stopped
    /// the unconfirmed run.
    private static func runPaid(confirmed: Bool) async -> String {
        let previousKind = Settings.readAloudEngineKind()
        let previousKey = ProviderKeyStore.apiKey(providerId: ElevenLabsTTSEngine.providerId)
        defer {
            Settings.setReadAloudEngineKind(previousKind)
            ProviderKeyStore.setAPIKey(previousKey, providerId: ElevenLabsTTSEngine.providerId)
        }

        Settings.setReadAloudEngineKind(NarrationEngineKind.remoteProvider.rawValue)
        ProviderKeyStore.setAPIKey("ui-test-placeholder-key", providerId: ElevenLabsTTSEngine.providerId)

        return await outcome(text: "A paid narration nobody asked for.", confirmed: confirmed)
    }

    /// The built-in engine is free, so it must ignore the parameter entirely —
    /// otherwise the gate would have broken every shortcut that already exists.
    private static func runFree() async -> String {
        let previousKind = Settings.readAloudEngineKind()
        defer { Settings.setReadAloudEngineKind(previousKind) }

        Settings.setReadAloudEngineKind(NarrationEngineKind.appleBuiltIn.rawValue)
        return await outcome(text: "A free narration from a shortcut.", confirmed: false)
    }

    private static func outcome(text: String, confirmed: Bool) async -> String {
        let intent = CreateNarrationIntent()
        intent.text = text
        intent.title = "Intent Harness"
        intent.confirmPaidNarration = confirmed
        do {
            _ = try await intent.perform()
            return "enqueued"
        } catch let error as ReadAloudIntentError {
            return String(describing: error)
        } catch {
            return "unexpected"
        }
    }
}
#endif
