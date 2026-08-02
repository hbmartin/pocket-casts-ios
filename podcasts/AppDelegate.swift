@preconcurrency import BackgroundTasks
import Capture
import Foundation
import PocketCastsDataModel
import PocketCastsServer
import PocketCastsUtils
import Combine
import TelemetryDeck
import TipKit

class AppDelegate: UIResponder, UIApplicationDelegate {
    private static let initialRefreshDelay = 2.seconds
    private static let minTimeBetweenRefreshes = 5.minutes

    private let shortcutManager = ShortcutManager()
    private let badgeHelper = BadgeHelper()
    private let fileSyncCoordinator = FileSyncCoordinator()

    @objc var backgroundSessionCompletionHandler: (() -> Void)?

    var window: UIWindow?
    var progressDialog: ShiftyLoadingAlert?
    var modalController: UINavigationController?

    lazy var lenticularFilter: LenticularFilter = .init()
    lazy var appLifecycleAnalytics = AppLifecycleAnalytics()

    private var backgroundSignOutListener: BackgroundSignOutListener?
    private(set) var appInstallState: AppLifecycleAnalytics.AppInstallState?
    var defaultsMigrationRetryObserver: ProtectedDataMigrationRetryObserver?
    nonisolated let defaultsMigrationQueue = DispatchQueue(label: "au.com.shiftyjelly.podcasts.defaults-migration")

    // MARK: - App Lifecycle

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        #if DEBUG
        // Destructive: when UI_TEST_SCENARIO is set this wipes the shared library,
        // clears keychain tokens, and signs the user out before seeding fixtures.
        // It no-ops without that env var, but a DEBUG build launched with it set in
        // the scheme will lose local data — keep it gated and opt-in.
        UITestScenarioLauncher.prepareIfRequested()
        #endif

        ImageManager.refreshScreenMetrics()
        configureBitdrift()
        configureTelemetryDeck()
        configureMetricKit()
        addAnalyticsObservers()
        setupAnalytics()

        DataManager.logger = BitdriftErrorLogger(category: "grdb")
        ServerConfig.shared.configure(
            syncDelegate: ServerSyncManager.shared,
            playbackDelegate: PlaybackServerAdapter(),
            errorLogger: BitdriftErrorLogger(category: "sync")
        )
        ServerConfig.shared.warmProtectedDataAvailabilityCache()

        configureTipKit()

        appInstallState = appLifecycleAnalytics.checkApplicationInstalledOrUpgraded()

        if let appInstallState {
            switch appInstallState {
            case .updated:
                Settings.notificationsNewEpisodes = UserDefaults.standard.bool(forKey: Constants.UserDefaults.pushEnabled)

                // Upgraders have already used playlists; never show them the new-user playlist tips
                NewFilterTip().invalidate(reason: .actionPerformed)
                NewFilterCreationTip().invalidate(reason: .actionPerformed)
            case .installed:
                // Never show the "here's what changed" tips for a fresh install
                PodcastFeedReloadTip().invalidate(reason: .actionPerformed)
                PodcastViewChangesTip().invalidate(reason: .actionPerformed)
                RecentlyPlayedSortingTip().invalidate(reason: .actionPerformed)
                Settings.shouldShowPlaylistsOnboarding = false
            case .sameVersion:
                break
            }
        }

        migrateLegacyTipFlags()

        let defaults = UserDefaults.standard

        // check to see that this app has a unique ID, if not create one
        let uniqueId = defaults.string(forKey: Constants.UserDefaults.appId)
        if uniqueId?.count ?? 0 < 1 {
            let uuid = UUID().uuidString
            defaults.set(uuid, forKey: Constants.UserDefaults.appId)
            defaults.synchronize()
        }

        setupRoutes()

        // start observing episode downloads so loudness gets measured in the background
        _ = EpisodeLoudnessScanner.shared

        // start observing episode downloads so every episode gains a transcript:
        // the feed-provided one is indexed when the show publishes one, otherwise
        // a transcription job is enqueued (flags re-checked per download)
        _ = TranscriptAcquisitionCoordinator.shared

        // mirror downloaded episodes and highlights into iOS Spotlight (flag
        // re-checked per event); the launch reconciliation is throttled to once a day
        SpotlightIndexCoordinator.shared.start()
        SpotlightIndexCoordinator.shared.startBookmarkObservations(bookmarkManager: PlaybackManager.shared.bookmarkManager)
        Task(priority: .utility) {
            await SpotlightIndexCoordinator.shared.reconcileIfDue()
        }
        // embed any indexed transcripts that don't have current-model vectors
        // yet (also the lazy re-embed path after an OS model bump)
        TranscriptEmbeddingBackfill.shared.kickAfterLaunch()

        // Markdown folder auto-export (Highlights S5): observe highlight
        // changes once a folder has been picked; no-op otherwise.
        HighlightFolderExporter.shared.startObservingIfNeeded()

        NotificationsHelper.shared.register(checkToken: false)

        DispatchQueue.global().async { [weak self] in
            guard let self else {
                return
            }

            checkDefaults()

            logActiveDownloadTasks()
            logStaleDownloads()
            postLaunchSetup()
            checkIfRestoreCleanupRequired()

            ImageManager.sharedManager.updatePodcastImagesIfRequired()
            WidgetHelper.shared.cleanupAppGroupImages()

            DownloadManager.shared.startAllQueued()

            LocalizationHelper.provider = InternationalizationProvider(userRegion: Settings.userRegion())
        }

        badgeHelper.setup()
        shortcutManager.listenForShortcutChanges()
        fileSyncCoordinator.setup()
        NowPlayingLiveActivityManager.shared.setup()

        setupBackgroundRefresh()

        setupSignOutListener()

        if FeatureFlag.diarizedTranscription.enabled {
            // Battery monitoring, power observers, pending-job restore and BG
            // scheduling. Idempotent — TranscriptAcquisitionCoordinator also
            // invokes it lazily on the feature's first use, so a Beta-menu
            // toggle mid-session gets working infrastructure without a relaunch.
            TranscriptionQueueManager.ensureRuntimeInfrastructure()
        }

        // Resume pending transcript contribution/sighting uploads. Deliberately
        // not behind the diarizedTranscription flag: sighting rows come from
        // plain transcript viewing (docs/TranscriptContributions.md §2 — no
        // client feature flag; operator control is server-side).
        TranscriptContributionManager.kickShared()

        return true
    }

    // MARK: - TipKit

    private func configureTipKit() {
        do {
            try Tips.configure()
        } catch {
            FileLog.shared.addMessage("TipKit configuration failed: \(error)")
        }
    }

    /// One-time migration of the pre-TipKit tip booleans into TipKit's datastore.
    ///
    /// If the old system recorded a tip as already seen/consumed, invalidate the TipKit
    /// equivalent so existing users don't see it again, then drop the legacy key.
    /// The key strings are inlined because their `Constants.UserDefaults` entries were
    /// removed together with the booleans they backed.
    private func migrateLegacyTipFlags() {
        let defaults = UserDefaults.standard

        // For these keys false used to mean "the tip was shown/dismissed, don't show it again"
        let legacyShowTipFlags: [(key: String, tip: any Tip)] = [
            ("podcastFeedReload.showtip", PodcastFeedReloadTip()),
            ("podcastViewChanges.showtip", PodcastViewChangesTip()),
            ("ShouldShowRecentlyPlayedSortingTip", RecentlyPlayedSortingTip()),
            ("NewFilterTip", NewFilterTip()),
            ("NewFilterTipCreationView", NewFilterCreationTip())
        ]
        for (key, tip) in legacyShowTipFlags {
            guard let shouldShow = defaults.value(forKey: key) as? Bool else { continue }
            if !shouldShow {
                tip.invalidate(reason: .tipClosed)
            }
            defaults.removeObject(forKey: key)
        }

        // The drag & drop tip used to be armed by creating a manual playlist…
        if defaults.value(forKey: "PlaylistDragAndDropTip") as? Bool == true {
            PlaylistDragAndDropTip.didCreateManualPlaylist.sendDonation()
        }
        defaults.removeObject(forKey: "PlaylistDragAndDropTip")

        // …and FirstTimePlaylistCreated flipped to false once that tip had been shown
        if defaults.value(forKey: "FirstTimePlaylistCreated") as? Bool == false {
            PlaylistDragAndDropTip().invalidate(reason: .tipClosed)
        }
        defaults.removeObject(forKey: "FirstTimePlaylistCreated")
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        handleEnterBackground()
    }

    func handleEnterBackground() {
        scheduleNextBackgroundRefresh()
        if FeatureFlag.diarizedTranscription.enabled {
            Task.detached(priority: .utility) {
                TranscriptionQueueManager.scheduleProcessingTaskIfNeeded()
            }
        }
        FileLog.shared.forceFlush()

        UserDefaults.standard.set(Date(), forKey: Constants.UserDefaults.lastAppCloseDate)
        badgeHelper.updateBadge()

        appLifecycleAnalytics.didEnterBackground()
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        handleBecomeActive()
    }

    func handleBecomeActive() {
        setupSignOutListener()
        appLifecycleAnalytics.didBecomeActive()

        // give the network a few seconds to come up before refreshing, also only refresh if the last refresh was more than 5 minutes ago
        let lastUpdateTime = ServerSettings.lastRefreshEndTime()
        if DateUtil.hasEnoughTimePassed(since: lastUpdateTime, time: AppDelegate.minTimeBetweenRefreshes) {
            Timer.scheduledTimer(withTimeInterval: AppDelegate.initialRefreshDelay, repeats: false, block: { _ in
                RefreshManager.shared.refreshPodcasts()
            })
        } else {
            DispatchQueue.global(qos: .userInitiated).async {
                PodcastManager.shared.checkForPendingAndAutoDownloads()
            }
        }
        fileSyncCoordinator.handleAppBecameActive()
        PlaybackManager.shared.updateIdleTimer()
    }

    func application(_ application: UIApplication, handleEventsForBackgroundURLSession identifier: String, completionHandler: @escaping () -> Void) {
        backgroundSessionCompletionHandler = completionHandler
    }

    // This method will be invoked even if the application was launched or resumed because of the remote notification. The respective delegate methods will be invoked first. Note that this behavior is in contrast to application:didReceiveRemoteNotification:, which is not called in those cases, and which will not be invoked if this method is implemented.
    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any], fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        let handler = PocketCastsUtils.UncheckedSendable(completionHandler)
        RefreshManager.shared.refreshPodcasts(completion: { refreshFetchResult in
            handler.value(self.convertRefreshResult(result: refreshFetchResult))
        })
        badgeHelper.updateBadge()
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let token = deviceToken.reduce(into: "") { $0 += String(format: "%02X", $1) }

        PodcastManager.shared.didReceiveToken(token)
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        ServerSettings.removePushToken()
    }

    func application(_ application: UIApplication, didChangeStatusBarFrame oldStatusBarFrame: CGRect) {
        ImageManager.refreshScreenMetrics()
    }

    func applicationWillTerminate(_ application: UIApplication) {
        RefreshManager.shared.cancelAllRefreshes()

        badgeHelper.teardown()
        shortcutManager.stopListeningForShortcutChanges()

        UIApplication.shared.endReceivingRemoteControlEvents()
    }

    @objc func miniPlayer() -> MiniPlayerViewController? {
        NavigationManager.sharedManager.miniPlayer
    }

    func openEpisode(_ episodeUuid: String, from podcast: Podcast, timestamp: TimeInterval? = nil, quote: String? = nil) {
        DispatchQueue.main.async {
            self.hideProgressDialog()

            guard let episode = DataManager.sharedManager.findEpisode(uuid: episodeUuid) else {
                // for some reason we can't find this episode, so open the podcast instead
                FileLog.shared.addMessage("Unable to find episode with uuid \(episodeUuid), opening podcast `\(podcast.title ?? "")` instead")
                NavigationManager.sharedManager.navigateTo(NavigationManager.podcastPageKey, data: [NavigationManager.podcastKey: podcast])

                return
            }
            var data: [String: Any] = [NavigationManager.episodeUuidKey: episode.uuid]
            if let timestamp {
                data[NavigationManager.episodeTimestamp] = timestamp
            }
            if let quote {
                data[NavigationManager.episodeQuote] = quote
            }

            NavigationManager.sharedManager.navigateTo(NavigationManager.episodePageKey, data: data as NSDictionary)
        }
    }

    func hideProgressDialog() {
        if Thread.current.isMainThread {
            progressDialog?.hideAlert(false)
            progressDialog = nil
        } else {
            DispatchQueue.main.async {
                self.progressDialog?.hideAlert(false)
                self.progressDialog = nil
            }
        }
    }

    func openPlayerWhenReadyFromExternalEvent() {
        guard miniPlayer()?.playerOpenState != .open, miniPlayer()?.playerOpenState != .animating else { return }

        // when opening from an external event, we need to give the app time to set itself up and launch. As dodgy as this is, it means waiting a bit before launching the player
        SwiftUtils.performAfterDelayOnMainThread(1.0, closure: {
            guard let miniPlayer = self.miniPlayer(), miniPlayer.playerOpenState != .animating, miniPlayer.playerOpenState != .open else { return }

            miniPlayer.openFullScreenPlayer()
        })
    }


    private func setupBackgroundRefresh() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Constants.Values.refreshTaskId, using: nil) { task in
            FileLog.shared.addMessage("Background refresh called")
            let boxedTask = PocketCastsUtils.UncheckedSendable(task)
            Task { @MainActor in
                self.handleAppRefresh(task: boxedTask.value)
            }
        }

        // Registered unconditionally: BGTaskScheduler only accepts registrations
        // before launch ends, so a Beta-menu flag toggle mid-session must not
        // leave a scheduled transcription task without a handler until the next
        // cold launch. The handler itself checks the feature flag.
        TranscriptionQueueManager.registerBackgroundTask()
    }

    private func scheduleNextBackgroundRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: Constants.Values.refreshTaskId)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 30.minutes)

        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            FileLog.shared.addMessage("Could not schedule app refresh: \(error.localizedDescription)")
        }
    }

    private func handleAppRefresh(task: BGTask) {
        scheduleNextBackgroundRefresh()

        task.expirationHandler = {
            FileLog.shared.addMessage("Background refresh timed out")
        }

        let boxedTask = PocketCastsUtils.UncheckedSendable(task)
        let syncCoordinator = fileSyncCoordinator
        RefreshManager.shared.refreshPodcasts(completion: { refreshFetchResult in
            let refreshSucceeded = refreshFetchResult != .failed
            Task { [boxedTask, refreshSucceeded, syncCoordinator] in
                await syncCoordinator.performBackgroundSync()
                boxedTask.value.setTaskCompleted(success: refreshSucceeded)
            }
        })
        badgeHelper.updateBadge()
    }

    nonisolated private func postLaunchSetup() {
        if !UserDefaults.standard.bool(forKey: "CreatedDefPlaylistsV2") {
            PlaylistManager.createDefaultPlaylists()
            UserDefaults.standard.set(true, forKey: "CreatedDefPlaylistsV2")
        }
        Task {
            await DownloadManager.shared.clearStuckDownloads()
        }
    }

    nonisolated private func checkIfRestoreCleanupRequired() {
        let dataManager = DataManager.sharedManager

        // find the oldest episode in our database listed as being downloaded
        let query = "episodeStatus = \(DownloadStatus.downloaded.rawValue) ORDER BY publishedDate ASC, addedDate ASC LIMIT 1"
        guard let oldestEpisode = dataManager.findEpisodeWhere(customWhere: query, arguments: nil), !oldestEpisode.downloaded(pathFinder: DownloadManager.shared) else { return }

        // if we get here then we have at least one episode that is listed as downloaded that's actually not, so we need to go through and check them all
        FileLog.shared.addMessage("Detected restore cleanup required")
        let allQuery = "episodeStatus = \(DownloadStatus.downloaded.rawValue)"
        let downloadedEpisodes = dataManager.findEpisodesWhere(customWhere: allQuery, arguments: nil)
        for episode in downloadedEpisodes {
            if !episode.downloaded(pathFinder: DownloadManager.shared) {
                // episode is listed as downloaded, but the file isn't there, fix this
                dataManager.saveEpisode(downloadStatus: .notDownloaded, episode: episode)
                dataManager.clearCachedAudioMetadata(episode: episode)
            }
        }

        NotificationCenter.postOnMainThread(ManyEpisodesChanged())
    }

    nonisolated private func convertRefreshResult(result: RefreshFetchResult) -> UIBackgroundFetchResult {
        switch result {
        case .failed:
            return UIBackgroundFetchResult.failed
        case .newData:
            return UIBackgroundFetchResult.newData
        case .noData:
            return UIBackgroundFetchResult.noData
        }
    }

    // MARK: UISceneSession Lifecycle

    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let role = connectingSceneSession.role

        return UISceneConfiguration(name: "Default Configuration", sessionRole: role)
    }

    // MARK: Secrets

    private func configureBitdrift() {
        // Dev tooling and TestFlight diagnostics: never start instrumentation in
        // App Store builds. TestFlight sessions feed shake-to-report (the report
        // attaches the session ID). The Capture.Logger.logX call sites are safe
        // no-ops when start was skipped (the credential-less configuration
        // already exercises that path).
        guard BuildEnvironment.current != .appStore else { return }
        // Respect the analytics opt-out, mirroring configureTelemetryDeck. Capture
        // exposes no API to stop an already-started logger, so a mid-session
        // opt-out takes effect at the next launch; until then the direct
        // Capture.Logger call sites (BitdriftErrorLogger, TranscriptManager)
        // check the opt-out themselves.
        guard !Settings.analyticsOptOut() else {
            FileLog.shared.addMessage("Analytics opt-out enabled; skipping Bitdrift startup")
            return
        }
        guard !ApiCredentials.bitdriftSDKKey.isMissingOrPlaceholderCredential else {
            FileLog.shared.addMessage("Bitdrift SDK key is not configured; skipping Bitdrift startup")
            return
        }

        Capture.Logger.start(
            withAPIKey: ApiCredentials.bitdriftSDKKey,
            sessionStrategy: .fixed()
        )
    }

    private func configureMetricKit() {
        // Payload persistence is unconditional (local ring buffer for the Beta
        // viewer); the analytics summaries respect the opt-out via the adapter
        // fan-out at track time, so a mid-session opt-in needs no re-registration.
        MetricKitCollector.shared.start()
    }

    @discardableResult
    func configureTelemetryDeck() -> Bool {
        guard !Settings.analyticsOptOut() else {
            FileLog.shared.addMessage("Analytics opt-out enabled; skipping TelemetryDeck startup")
            return false
        }

        let telemetryDeckAppID = ApiCredentials.telemetryDeckAppID

        guard !telemetryDeckAppID.isMissingOrPlaceholderCredential else {
            FileLog.shared.addMessage("TelemetryDeck App ID is not configured; skipping TelemetryDeck startup")
            return false
        }

        guard !TelemetryManager.isInitialized else {
            return true
        }

        TelemetryDeck.initialize(config: TelemetryDeck.Config(appID: telemetryDeckAppID))
        return true
    }

    private func setupSignOutListener() {
        guard backgroundSignOutListener == nil else {
            return
        }

        backgroundSignOutListener = BackgroundSignOutListener(presentingViewController: SceneHelper.rootViewController())
    }
}

nonisolated struct BitdriftErrorLogger: ErrorLogger {
    let category: String

    func log(error: Error, context: [String: String]?) {
        // Wired unconditionally as DataManager.logger / ServerConfig.errorLogger,
        // so honor the analytics opt-out here — this also silences a mid-session
        // opt-out, since the already-started Capture logger can't be stopped.
        guard !Settings.analyticsOptOut() else { return }

        var fields = (context ?? [:]).reduce(into: Fields()) { result, entry in
            result[entry.key] = entry.value
        }
        fields["category"] = category

        Capture.Logger.logWarning(
            "Pocket Casts error: \(error.localizedDescription)",
            fields: fields,
            error: error
        )
    }
}
