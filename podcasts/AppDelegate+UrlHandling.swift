import CoreServices
import CoreSpotlight
import Foundation
import UniformTypeIdentifiers
import JLRoutes
import PocketCastsDataModel
import PocketCastsServer
import PocketCastsUtils

nonisolated enum InboundAction: Equatable, Sendable {
    case route(URL)
    case importOpml(URL)
    case importArchive(URL)
    case uploadMedia(URL)
    case unsupported
}

/// Classifies external URLs without touching UIKit, JLRoutes, or global app state.
/// AppDelegate performs the resulting action; tests can exercise this boundary in
/// parallel using isolated databases and directories.
nonisolated enum InboundActionRouter {
    static func action(for url: URL) -> InboundAction {
        guard url.isFileURL else {
            return url.scheme?.lowercased() == "thcast" ? .route(url) : .unsupported
        }

        guard let type = UTType(filenameExtension: url.pathExtension) else {
            return .unsupported
        }

        if let extensionName = UTType.pcasts.preferredFilenameExtension,
           let archiveType = UTType(filenameExtension: extensionName),
           type.conforms(to: archiveType) {
            return .importArchive(url)
        }

        let opmlTypes: [UTType] = [.xml, UTType("public.opml"), UTType("unofficial.opml")].compactMap { $0 }
        if opmlTypes.contains(where: { type.conforms(to: $0) }) {
            return .importOpml(url)
        }

        if type.conforms(to: .audio) || type.conforms(to: .movie) {
            return .uploadMedia(url)
        }

        return .unsupported
    }

    static func shortcutURL(from urlString: String?) -> URL? {
        urlString.flatMap(URL.init(string:))
    }
}

extension AppDelegate {
    func application(_ application: UIApplication, performActionFor shortcutItem: UIApplicationShortcutItem, completionHandler: @escaping (Bool) -> Void) {
        appDelegate()?.handleShortcutItem(shortcutItem)
    }

    func handleShortcutItem(_ shortcutItem: UIApplicationShortcutItem) {
        if let url = InboundActionRouter.shortcutURL(from: shortcutItem.userInfo?["url"] as? String) {
            JLRoutes.routeURL(url)
        }
    }

    func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        guard let progressViewController = SceneHelper.rootViewController() else { return false }
        return handleOpenUrl(url: url, rootViewController: progressViewController)
    }

    func handleOpenUrl(url: URL, rootViewController: UIViewController) -> Bool {
        switch InboundActionRouter.action(for: url) {
        case .importArchive:
            let alert = UIAlertController(title: "Import Podcasts and Settings", message: "Do you want to reset your podcasts and settings to this file?", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Import", style: .default) { _ in
                Task {
                    do {
                        let fileWrapper = try FileWrapper(url: url)
                        try PCBundleDoc.performImport(from: fileWrapper)
                    } catch {
                        FileLog.shared.addMessage("File Import failed with error \(error)")
                    }
                }
            })
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
            rootViewController.present(alert, animated: true)
        case .importOpml:
            progressDialog = ShiftyLoadingAlert(title: L10n.opmlImporting)
            rootViewController.dismiss(animated: false, completion: nil)
            progressDialog?.showAlert(rootViewController, hasProgress: false, completion: { [weak self] in
                if let progressDialog = self?.progressDialog {
                    PodcastManager.shared.importPodcastsFromOpml(url, progressWindow: progressDialog)
                }
            })
        case .uploadMedia:
            NavigationManager.sharedManager.navigateTo(NavigationManager.uploadedPageKey, data: [NavigationManager.uploadFileKey: url])
        case .route:
            JLRoutes.routeURL(url)
        case .unsupported:
            // Report "not handled" so callers (application(_:open:) and the JLRoutes
            // /import-file route) can fall through instead of swallowing the URL.
            return false
        }
        return true
    }

    func setupRoutes() {
        // 3D touch shortcuts
        JLRoutes.global().addRoute("/shortcuts/:shortcut") { [weak self] parameters -> Bool in
            guard let strongSelf = self, let shortcut = parameters["shortcut"] as? String else { return false }

            if shortcut == "pause" {
                AnalyticsPlaybackHelper.shared.currentSource = .appIconMenu
                PlaybackManager.shared.pause()
                strongSelf.openPlayerWhenReadyFromExternalEvent()
                AnalyticsHelper.forceTouchPause()
            } else if shortcut == "play" {
                AnalyticsPlaybackHelper.shared.currentSource = .appIconMenu
                PlaybackManager.shared.play()
                strongSelf.openPlayerWhenReadyFromExternalEvent()
                AnalyticsHelper.forceTouchPlay()
            } else if shortcut == "markAsPlayed" {
                if let episode = PlaybackManager.shared.currentEpisode() {
                    AnalyticsEpisodeHelper.shared.currentSource = .appIconMenu
                    EpisodeManager.markAsPlayed(episode: episode, fireNotification: true)
                    AnalyticsHelper.forceTouchMarkPlayed()
                }
            } else if shortcut == "discover" {
                NavigationManager.sharedManager.navigateTo(NavigationManager.explorePageKey, data: nil)
                AnalyticsHelper.forceTouchDiscover()
            }

            return true
        }

        // open a public social profile from a Profile Link
        // (thcast://profile/<handle>, ADR-0008)
        JLRoutes.global().addRoute("/profile/:handle") { parameters -> Bool in
            guard FeatureFlag.socialProfiles.enabled, let handle = parameters["handle"] as? String, !handle.isEmpty else { return false }
            SocialCoordinator.openPublicProfile(handle: handle)
            return true
        }

        // open a playlist from a shortcut
        JLRoutes.global().addRoute("/shortcuts/filter/:filterId") { parameters -> Bool in
            guard let playlistId = parameters["filterId"] as? String, let playlist = DataManager.sharedManager.findPlaylist(uuid: playlistId) else { return false }

            NavigationManager.sharedManager.navigateTo(NavigationManager.filterPageKey, data: [NavigationManager.filterUuidKey: playlist.uuid])
            AnalyticsHelper.forceTouchTopFilter()

            return true
        }

        // open a podcast from a shortcut
        JLRoutes.global().addRoute("/shortcuts/podcast/:podcastUuid") { parameters -> Bool in
            guard let podcastUuid = parameters["podcastUuid"] as? String, let podcast = DataManager.sharedManager.findPodcast(uuid: podcastUuid) else { return false }

            NavigationManager.sharedManager.navigateTo(NavigationManager.podcastPageKey, data: [NavigationManager.podcastKey: podcast])
            AnalyticsHelper.forceTouchPodcast()

            return true
        }

        // share list page opened
        JLRoutes.global().addRoute("/sharelist/*") { parameters -> Bool in
            guard let pathComponents = parameters[JLRouteWildcardComponentsKey] as? [String] else { return false }

            let sharePath = pathComponents.joined(separator: "/")

            let jsonFileLocation = "http://\(sharePath).json"
            let listController = IncomingShareListViewController(jsonLocation: jsonFileLocation)
            let navController = SJUIUtils.popupNavController(for: listController)

            SceneHelper.rootViewController()?.present(navController, animated: true, completion: nil)

            return true
        }

        // URL schemes for open, play, pause
        JLRoutes.global().addRoute("/open") { _ -> Bool in
            true
        }
        JLRoutes.global().addRoute("/play") { _ -> Bool in
            PlaybackManager.shared.play()

            return true
        }
        JLRoutes.global().addRoute("/pause") { _ -> Bool in
            PlaybackManager.shared.pause()

            return true
        }

        // Open to discover
        JLRoutes.global().addRoute("/discover/*") { paramDict -> Bool in
            if let sourceString = paramDict["source"] as? String, sourceString == "widget" {
                Analytics.track(.widgetInteraction, properties: ["action": "discover"])
            }

            NavigationManager.sharedManager.navigateTo(NavigationManager.explorePageKey, data: nil)

            return true
        }
        // Support for subscribing to a feed URL
        JLRoutes.global().addRoute("/subscribe/*") { [weak self] parameters -> Bool in
            guard
                let strongSelf = self,
                let rootController = SceneHelper.rootViewController(includeTopMost: false), //I don't want to consider the top most presented but the main root instead
                let subscribeUrl = (parameters[JLRouteURLKey] as? URL)?.absoluteString
            else {
                return false
            }

            let prefix = "thcast://subscribe/"
            if prefix.count >= subscribeUrl.count { return true } // this request is missing a URL

            let feedUrl = subscribeUrl.replacingOccurrences(of: prefix, with: "")

            let searchTerm = !feedUrl.hasPrefix("http://") && !feedUrl.hasPrefix("https://") ? "http://\(feedUrl)" : feedUrl

            strongSelf.progressDialog = ShiftyLoadingAlert(title: L10n.podcastLoading)
            rootController.dismiss(animated: false, completion: nil)
            strongSelf.progressDialog?.showAlert(rootController, hasProgress: false, completion: {
                MainServerHandler.shared.podcastSearch(searchTerm: searchTerm) { [weak self] response in
                    guard let uuid = response?.result?.podcast?.uuid else {
                        DispatchQueue.main.async {
                            self?.hideProgressDialog()

                            SJUIUtils.showAlert(title: L10n.error, message: L10n.errorGeneralPodcastNotFound, from: SceneHelper.rootViewController())
                        }

                        return
                    }
                    ServerPodcastManager.shared.addFromUuidWithRetries(podcastUuid: uuid, subscribe: false) { success in
                        DispatchQueue.main.async {
                            self?.hideProgressDialog()

                            if success {
                                NavigationManager.sharedManager.navigateTo(NavigationManager.podcastPageKey, data: [NavigationManager.podcastKey: uuid])
                            } else {
                                SJUIUtils.showAlert(title: L10n.error, message: L10n.errorGeneralPodcastNotFound, from: SceneHelper.rootViewController())
                            }
                        }
                    }
                }
            })

            return true
        }

        // Today Centre Widget thingy
        JLRoutes.global().addRoute("/widget/*") { [weak self] parameters -> Bool in
            guard let strongSelf = self, let pathComponents = parameters[JLRouteWildcardComponentsKey] as? [String], let episodeUuid = pathComponents[safe: 0] else { return false }

            guard let episode = DataManager.sharedManager.findEpisode(uuid: episodeUuid) else { return true }

            strongSelf.openPlayerWhenReadyFromExternalEvent()

            if PlaybackManager.shared.isNowPlayingEpisode(episodeUuid: episode.uuid) {
                if !PlaybackManager.shared.playing() {
                    PlaybackManager.shared.play()
                }
            } else {
                PlaybackManager.shared.load(episode: episode, autoPlay: true, overrideUpNext: false)
            }

            return true
        }

        // Home screen Widget
        JLRoutes.global().addRoute("/widget-episode/*") { [weak self] parameters -> Bool in
            guard let strongSelf = self, let pathComponents = parameters[JLRouteWildcardComponentsKey] as? [String], let episodeUuid = pathComponents[safe: 0] else { return false }

            guard let baseEpisode = DataManager.sharedManager.findBaseEpisode(uuid: episodeUuid) else { return true }

            if PlaybackManager.shared.isNowPlayingEpisode(episodeUuid: baseEpisode.uuid) {
                strongSelf.openPlayerWhenReadyFromExternalEvent()
                Analytics.track(.widgetInteraction, properties: ["action": "now_playing"])
            } else {
                Analytics.track(.widgetInteraction, properties: ["action": "episode"])
                if let episode = baseEpisode as? Episode {
                    NavigationManager.sharedManager.navigateTo(NavigationManager.episodePageKey, data: [NavigationManager.episodeUuidKey: episode.uuid])
                } else if baseEpisode is UserEpisode {
                    NavigationManager.sharedManager.navigateTo(NavigationManager.filesPageKey, data: nil)
                }
            }
            return true
        }

        JLRoutes.global().addRoute("/last_opened/*") { _ in
            Analytics.track(.widgetInteraction, properties: ["action": "open_app"])
            return true
        }

        JLRoutes.global().addRoute("/show_player") { [weak self] _ -> Bool in
            Analytics.track(.widgetInteraction, properties: ["action": "now_playing"])
            self?.openPlayerWhenReadyFromExternalEvent()
            return true
        }

        JLRoutes.global().addRoute("social/share/:showOrPrivate/:sharingId") { [weak self] parameters -> Bool in
            guard let strongSelf = self, let folder = parameters["showOrPrivate"] as? String, let sharingId = parameters["sharingId"] as? String, let controller = SceneHelper.rootViewController() else { return false }
            var sharePath = "social/share/\(folder)/\(sharingId)"
            var querySeparator = "/?"
            if let timestamp = parameters["t"] as? String {
                sharePath = sharePath + "\(querySeparator)t=\(timestamp)"
                querySeparator = "&"
            }
            // JLRoutes hands query values decoded; re-encode so the reconstructed
            // path survives the URLComponents round-trip in openSharePath.
            if let quote = parameters["q"] as? String {
                sharePath = sharePath + "\(querySeparator)q=\(ShareQuoteBuilder.percentEncodedURLQuote(quote))"
            }
            FileLog.shared.addMessage("Opening share link, path: \(folder)/\(sharingId)")
            strongSelf.openSharePath(sharePath, controller: controller, onErrorOpen: nil)
            return true
        }

        JLRoutes.global().addRoute("/upnext/*") { [weak self] paramDict -> Bool in
            var source: UpNextViewSource = .unknown
            var showFromMiniPlayer: Bool = true
            if let location = paramDict["location"] as? String, location == "tab" {
                showFromMiniPlayer = false
            }
            if let sourceString = paramDict["source"] as? String {
                Analytics.track(.widgetInteraction, properties: ["action": "up_next"])
                source = UpNextViewSource(rawValue: sourceString) ?? .unknown
            }
            if showFromMiniPlayer {
                self?.miniPlayer()?.showUpNext(from: source)
            } else {
                NavigationManager.sharedManager.navigateTo(NavigationManager.upNextPageKey)
            }

            return true
        }

        // Import OMPL extension
        JLRoutes.global().addRoute("/import-file/*") { [weak self] parameters -> Bool in
            guard let self,
                  let rootViewController = SceneHelper.rootViewController(),
                  let originalUrl = parameters[JLRouteURLKey] as? URL else { return false }

            let fileURLString = originalUrl.absoluteString.replacingOccurrences(of: "thcast://import-file/", with: "")

            guard let fileURL = URL(string: fileURLString) else {
                return true
            }

            return self.handleOpenUrl(url: fileURL, rootViewController: rootViewController)
        }

        setupOnboardingRoutes()
        setupNewFeaturesRoutes()
        setupProfileRoutes()
    }

    func setupOnboardingRoutes() {
        JLRoutes.global().addRoute("/settings/themes") {[weak self] _ -> Bool in
            guard self != nil else { return false }
            NavigationManager.sharedManager.navigateTo(NavigationManager.settingsAppearanceKey, data: [NavigationManager.settingsAppearanceShowThemeKey: true])
            return true
        }

        JLRoutes.global().addRoute("/signup") {[weak self] _ -> Bool in
            guard self != nil else { return false }
            NavigationManager.sharedManager.navigateTo(NavigationManager.signUpPageKey)
            return true
        }

        JLRoutes.global().addRoute("/settings/import") {[weak self] _ -> Bool in
            guard self != nil else { return false }
            NavigationManager.sharedManager.navigateTo(NavigationManager.settingsPageKey, data: [NavigationManager.settingsRowKey: SettingsViewController.TableRow.importSteps])
            return true
        }

        JLRoutes.global().addRoute("/settings/storage-and-data") {[weak self] _ -> Bool in
            guard self != nil else { return false }
            NavigationManager.sharedManager.navigateTo(NavigationManager.settingsPageKey, data: [NavigationManager.settingsRowKey: SettingsViewController.TableRow.storageAndDataUse])
            return true
        }

        JLRoutes.global().addRoute("/files") { _ -> Bool in
            NavigationManager.sharedManager.navigateTo(NavigationManager.filesPageKey, data: nil)
            return true
        }

        JLRoutes.global().addRoute("/filters") {[weak self] _ -> Bool in
            guard self != nil else { return false }
            NavigationManager.sharedManager.navigateTo(NavigationManager.filterPageKey)
            return true
        }
    }

    func setupNewFeaturesRoutes() {
        JLRoutes.global().addRoute("/features/*") {[weak self] parameters -> Bool in
            guard self != nil,
                  let pathComponents = parameters[JLRouteWildcardComponentsKey] as? [String],
                  let feature = pathComponents.first
            else {
                return false
            }
            NavigationManager.sharedManager.navigateTo(NavigationManager.featurePageKey, data: [NavigationManager.featureKey: feature])
            return true
        }
    }

    func setupProfileRoutes() {
        JLRoutes.global().addRoute("/profile/*") { [weak self] parameters -> Bool in
            guard self != nil,
                  let pathComponents = parameters[JLRouteWildcardComponentsKey] as? [String],
                  let row = pathComponents.first
            else {
                NavigationManager.sharedManager.navigateTo(NavigationManager.settingsProfileKey, data: [:])
                return true
            }
            NavigationManager.sharedManager.navigateTo(NavigationManager.settingsProfileKey, data: [NavigationManager.profileRowKey: row])
            return true
        }
    }

    func openSharePath(_ path: String, controller: UIViewController, onErrorOpen: URL?) {
        progressDialog = ShiftyLoadingAlert(title: L10n.sharedItemLoading)
        progressDialog?.showAlert(controller, hasProgress: false) {
            // Parse the URL into path and query components so that any query parameters
            // (e.g. ?t=123&q=quote) do not interfere with UUID extraction.
            let urlComponents = URLComponents(string: path)
            let cleanPath = urlComponents?.path.isEmpty == false ? urlComponents!.path : path
            let (timestamp, quote) = ShareLinkQueryParser.timestampAndQuote(from: path)
            if quote != nil {
                Analytics.track(.deepLinkQuoteOpened, properties: ["has_timestamp": timestamp != nil])
            }

            // URLs that are already in the format https://pca.st/podcast/da3271a0-69e7-0132-d9fd-5f4c86fd3263 (or /private/) have the podcast UUID in them already so no need to ask the refresh server for it
            // Also handles new format: /podcast/{podcastSlug}/{podcastUuid}/{episodeSlug}/{episodeUuid}
            if cleanPath.contains("/podcast/") || cleanPath.contains("/private/") {
                // Check for new format with episode: /podcast/{slug}/{podcastUuid}/{episodeSlug}/{episodeUuid}
                if let podcastRange = cleanPath.range(of: "/podcast/") ?? cleanPath.range(of: "/private/") {
                    let afterPodcast = String(cleanPath[podcastRange.upperBound...])
                    let components = afterPodcast.split(separator: "/").map(String.init)

                    // New format: 4 components = podcastSlug, podcastUuid, episodeSlug, episodeUuid
                    if components.count == 4 {
                        let podcastUuid = components[1]
                        let episodeUuid = components[3]
                        self.loadAndShowEpisode(episodeUuid: episodeUuid, podcastUuid: podcastUuid, timestamp: timestamp, quote: quote)
                        return
                    }
                }

                // Original format: just podcast UUID as last component
                if let lastSlashIndex = cleanPath.lastIndex(of: "/") {
                    let startIndex = cleanPath.index(lastSlashIndex, offsetBy: 1)
                    let uuid = cleanPath.suffix(from: startIndex)
                    let podcastHeader = PodcastHeader(uuid: String(uuid))
                    DispatchQueue.main.async {
                        self.hideProgressDialog()
                        NavigationManager.sharedManager.navigateTo(NavigationManager.podcastPageKey, data: [NavigationManager.podcastKey: podcastHeader])
                    }

                    return
                }
            }

            PodcastManager.shared.importSharedItemFromUrl(path) { item in
                guard let item else {
                    self.hideProgressDialog()
                    FileLog.shared.addMessage("Unable to load shared item \(path)")
                    if let onErrorOpen {
                        UIApplication.shared.open(onErrorOpen, options: [:], completionHandler: nil)
                    }

                    return
                }

                if item.isPodcastOnly() {
                    guard let podcastHeader = item.podcastHeader else {
                        self.hideProgressDialog()

                        return
                    }

                    DispatchQueue.main.async {
                        self.hideProgressDialog()
                        NavigationManager.sharedManager.navigateTo(NavigationManager.podcastPageKey, data: [NavigationManager.podcastKey: podcastHeader])
                    }
                } else if let episodeUuid = item.episodeHeader?.uuid, let podcastUuid = item.podcastHeader?.uuid {
                    let timestamp = item.fromTime?.toDouble()
                    self.loadAndShowEpisode(episodeUuid: episodeUuid, podcastUuid: podcastUuid, timestamp: timestamp, quote: quote)
                }
            }
        }
    }

    private func loadAndShowEpisode(episodeUuid: String, podcastUuid: String, timestamp: TimeInterval? = nil, quote: String? = nil) {
        if let podcast = DataManager.sharedManager.findPodcast(uuid: podcastUuid, includeUnsubscribed: true) {
            // if we're subscribed to the podcast, we'll likely have this episode, just open it
            if podcast.isSubscribed() {
                openEpisode(episodeUuid, from: podcast, timestamp: timestamp, quote: quote)
            } else { // if we're not subscribed, than it's possible our local copy is out of date, so we'll need to update it first
                ServerPodcastManager.shared.updatePodcastIfRequired(podcast: podcast) { _ in
                    Task { @MainActor in
                        self.openEpisode(episodeUuid, from: podcast, timestamp: timestamp, quote: quote)
                    }
                }
            }

            return
        }

        ServerPodcastManager.shared.addFromUuid(podcastUuid: podcastUuid, subscribe: false, completion: { success in
            if success, let podcast = DataManager.sharedManager.findPodcast(uuid: podcastUuid, includeUnsubscribed: true) {
                self.openEpisode(episodeUuid, from: podcast, timestamp: timestamp, quote: quote)
            } else {
                DispatchQueue.main.async {
                    self.hideProgressDialog()
                    SJUIUtils.showAlert(title: L10n.podcastShareErrorTitle, message: L10n.podcastShareErrorMsg, from: SceneHelper.rootViewController())
                }
            }
        })
    }

    // MARK: - NSUserActivity (universal links / Handoff)

    func application(_ application: UIApplication, continue userActivity: NSUserActivity, restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void) -> Bool {
        handleContinue(userActivity)

        return true
    }

    func handleContinue(_ userActivity: NSUserActivity) {
        if userActivity.activityType == "au.com.shiftyjelly.podcasts" {
            let info = userActivity.userInfo
            if let urlString = info?["url"] as? String, let url = URL(string: urlString) {
                JLRoutes.routeURL(url)
            }
        } else if userActivity.activityType == CSSearchableItemActionType {
            handleSpotlightItem(userActivity)
        } else if userActivity.activityType == NSUserActivityTypeBrowsingWeb {
            guard
                let incomingURL = userActivity.webpageURL,
                let components = NSURLComponents(url: incomingURL, resolvingAgainstBaseURL: true),
                let path = components.path,
                let controller = SceneHelper.rootViewController(),
                path != "/get",
                path != "/get/"
            else { return }

            // If path is just the base share URL let's return
            if path.isEmpty || path == "/", URL(string: ServerConstants.Urls.share())?.host == incomingURL.host {
                return
            }

            if path == "/discover" || path.startsWith(string: "/discover/") {
                if let url = URL(string: "thcast:/\(path)") {
                    NavigationManager.sharedManager.dismissPresentedViewController()
                    JLRoutes.routeURL(url)
                }
                return
            }

            // Also pass any query params from the share URL to the server to allow support for episode position handling
            // Ex: ?t=123
            let query = components.query.map { "?\($0)" } ?? ""
            let sharePath = "\(path)\(query)"

            FileLog.shared.addMessage("Opening universal link, path: \(sharePath)")
            openSharePath("social/share/show\(sharePath)", controller: controller, onErrorOpen: incomingURL)
        }
    }

    /// A Spotlight result was tapped. Episodes open their card; highlight items
    /// (added with the transcript/highlight indexing slice) seek-and-play.
    private func handleSpotlightItem(_ userActivity: NSUserActivity) {
        guard let identifier = userActivity.userInfo?[CSSearchableItemActivityIdentifier] as? String,
              let target = SpotlightItemBuilder.parse(identifier: identifier) else {
            return
        }

        switch target {
        case .episode(let uuid):
            Analytics.track(.spotlightItemOpened, properties: ["type": "episode"])
            guard let episode = DataManager.sharedManager.findEpisode(uuid: uuid) else {
                FileLog.shared.addMessage("[Spotlight] tapped episode \(uuid) no longer exists")
                return
            }
            NavigationManager.sharedManager.navigateTo(NavigationManager.episodePageKey, data: [NavigationManager.episodeUuidKey: episode.uuid])
        case .highlight(let bookmarkUuid):
            Analytics.track(.spotlightItemOpened, properties: ["type": "highlight"])
            guard let bookmark = DataManager.sharedManager.bookmarks.bookmark(for: bookmarkUuid),
                  let episode = DataManager.sharedManager.findEpisode(uuid: bookmark.episodeUuid) else {
                FileLog.shared.addMessage("[Spotlight] tapped highlight \(bookmarkUuid) no longer resolves")
                return
            }
            PlaybackManager.shared.play(episodeUuid: episode.uuid, podcastUuid: episode.podcastUuid, at: bookmark.time)
        }
    }
}
