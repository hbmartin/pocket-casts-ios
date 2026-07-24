import PocketCastsServer
import PocketCastsDataModel
import PocketCastsUtils
import TelemetryDeck

extension AppDelegate {
    private var shouldRegisterAdapters: Bool {
        UIApplication.shared.isProtectedDataAvailable && !Analytics.shared.adaptersRegistered
    }

    func setupAnalytics() {
        guard shouldRegisterAdapters else {
            return
        }

        var adapters: [AnalyticsAdapter] = []

        // Only setup if protected data is available, the user hasn't opted out, and we aren't already registered
        if !Settings.analyticsOptOut() {
            adapters = [AnalyticsLoggingAdapter(), BitdriftAnalyticsAdapter()]

            if TelemetryManager.isInitialized {
                adapters.append(TelemetryDeckAnalyticsAdapter())
            }
        }

        adapters.append(NotificationsCoordinator.shared)

        Analytics.register(adapters: adapters)
        Analytics.add(analyticsAppThemeProvider: AnalyticsAppThemeProvider())
    }

    nonisolated func logActiveDownloadTasks() {
        Task {
            let tasks = await DownloadManager.shared.allTasks()

            let properties: [String: Any?] =  ["tasks_count": tasks.count]

            Analytics.track(.episodeDownloadTasks, properties: properties.compactMapValues({ $0 }))
        }
    }

    nonisolated func logStaleDownloads() {
        let failedDownloadCount = DataManager.sharedManager.failedDownloadedEpisodesCount()

        guard failedDownloadCount > 0 else {
            return
        }

        let oldestFailedDownload = DataManager.sharedManager.oldestFailedEpisodeDownload()
        let newestFailedDownload = DataManager.sharedManager.newestFailedEpisodeDownload()

        let properties: [String: Any?] =  ["failed_download_count": failedDownloadCount,
                                           "oldest_failed_download": oldestFailedDownload?.formatted(.iso8601),
                                           "newest_failed_download": newestFailedDownload?.formatted(.iso8601)]

        Analytics.track(.episodeDownloadsStale, properties: properties.compactMapValues({ $0 }))
    }

    func addAnalyticsObservers() {
        // Signed out events. App-lifetime observation; the token is deliberately
        // not retained for removal, matching the previous string observer.
        _ = NotificationCenter.default.addObserver(for: UserWillBeSignedOut.self) { message in
            Analytics.track(.userSignedOut, properties: ["user_initiated": message.userInitiated])
        }

        let protectedDataObserver = ProtectedDataMigrationRetryObserver { [weak self] in
            self?.setupAnalytics()
            DispatchQueue.global(qos: .utility).async { [weak self] in
                self?.checkDefaults()
            }
        }
        protectedDataObserver.start()
        defaultsMigrationRetryObserver = protectedDataObserver
    }

    /// Checks if we're missing the userId saved in the defaults, and retrieves it from the server if needed
    /// This should only need to be ran once.
    nonisolated func retrieveUserIdIfNeeded() {
        guard
            let username = ServerSettings.syncingEmail(),
            let password = ServerSettings.syncingPassword(),
            ServerSettings.userId == nil
        else {
            return
        }

        FileLog.shared.addMessage("Missing User ID - Retrieving from the server")

        // Refresh the login, but only retrieve the userId
        ApiServerHandler.shared.validateLogin(username: username, password: password) { success, userId, _ in
            guard success, let userId else {
                return
            }

            ServerSettings.userId = userId
            NotificationCenter.postOnMainThread(UserLoginDidChange())
        }
    }
}
