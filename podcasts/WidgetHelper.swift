
import PocketCastsDataModel
import PocketCastsServer
import PocketCastsUtils
import WidgetKit

nonisolated final class WidgetHelper: Sendable {
    static let shared = WidgetHelper()
    static let appGroupId = SharedConstants.GroupUserDefaults.groupContainerId
    static let maxUpNextToPublish = 10
    static let maxFilterToPublish = 5

    /// Typed-notification tokens.
    // nonisolated(unsafe): written exactly once, at the end of `init` (before `self`
    // can be visible to any other thread), then only read in `deinit` — no concurrent
    // access is possible despite the `Sendable` conformance.
    nonisolated(unsafe) private var messageTokens: [NotificationCenter.ObservationToken] = []

    init() {
        messageTokens = [
            NotificationCenter.default.addObserver(for: PlaybackStarted.self) { [weak self] _ in
                self?.updateFromNotification()
            },
            NotificationCenter.default.addObserver(for: PlaybackEnded.self) { [weak self] _ in
                self?.updateFromNotification()
            },
            NotificationCenter.default.addObserver(for: PlaybackTrackChanged.self) { [weak self] _ in
                self?.updateFromNotification()
            },
            NotificationCenter.default.addObserver(for: PlaybackPaused.self) { [weak self] _ in
                self?.updateFromNotification()
            },
            NotificationCenter.default.addObserver(for: CurrentlyPlayingEpisodeUpdated.self) { [weak self] _ in
                self?.updateFromNotification()
            },
            NotificationCenter.default.addObserver(for: PlaylistChanged.self) { [weak self] _ in
                self?.handleFilterChanged()
            },
            NotificationCenter.default.addObserver(for: PodcastAdded.self) { [weak self] _ in
                self?.handleFilterChanged()
            },
            NotificationCenter.default.addObserver(for: UpNextQueueChanged.self) { [weak self] _ in
                self?.updateSharedUpNext()
            },
            NotificationCenter.default.addObserver(for: UpNextEpisodeRemoved.self) { [weak self] _ in
                self?.updateSharedUpNext()
            }
        ]
    }

    deinit {
        for token in messageTokens {
            NotificationCenter.default.removeObserver(token)
        }
    }

    func updateAllWidgets() {
        WidgetCenter.shared.getCurrentConfigurations { result in
            guard case .success = result, let widgets = try? result.get(), !widgets.isEmpty else { return }

            if widgets.contains(where: { $0.kind == "Now_Playing_Widget" }) {
                self.publishAppIcon()
            }
            if widgets.contains(where: { $0.kind == "Up_Next_Widget" }), PlaybackManager.onMainSync({ $0.currentEpisode() }) == nil, PlaybackManager.onMainSync({ $0.upNextCount() }) == 0 {
                self.publishTopFilterInfo()
            }
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    func updateFromNotification() {
        updateSharedUpNext()
    }

    func updateSharedUpNext() {
            publishUpNextInfo()
            updateAllWidgets()
    }

    func updateUpNextWidgets() {
        WidgetCenter.shared.getCurrentConfigurations { result in
            guard case .success = result else { return }
            WidgetCenter.shared.reloadTimelines(ofKind: "Up_Next_Widget")
        }
    }

    func updateWidgetAppIcon() {
        WidgetCenter.shared.getCurrentConfigurations { result in
            guard case .success = result, let widgets = try? result.get() else { return }
            if widgets.contains(where: { $0.kind == "Now_Playing_Widget" }) {
                self.publishAppIcon()
                WidgetCenter.shared.reloadTimelines(ofKind: "Now_Playing_Widget")
            }
        }
    }

    func handleFilterChanged() {
        guard PlaybackManager.onMainSync({ $0.currentEpisode() }) == nil else {
            return
        }
        updateSharedUpNext()
    }

    // MARK: - Up Next Widget

    private func publishUpNextInfo() {
        guard let sharedDefaults = UserDefaults(suiteName: SharedConstants.GroupUserDefaults.groupContainerId) else { return }

        let allUpNextPlaylistEpisodes = DataManager.sharedManager.allUpNextPlaylistEpisodes()
        var upNextItems = [CommonUpNextItem]()
        for (index, playlistEpisode) in allUpNextPlaylistEpisodes.enumerated() {
            if index > WidgetHelper.maxUpNextToPublish { break }

            if let episode = DataManager.sharedManager.findBaseEpisode(uuid: playlistEpisode.episodeUuid), let upNextItem = convertToWidgetItem(episode: episode) {
                upNextItems.append(upNextItem)
            }
        }

        do {
            let serializedItems = try JSONEncoder().encode(upNextItems)
            sharedDefaults.set(serializedItems, forKey: SharedConstants.GroupUserDefaults.upNextItems)
            sharedDefaults.set(max(allUpNextPlaylistEpisodes.count - 1, 0), forKey: SharedConstants.GroupUserDefaults.upNextItemsCount)
            sharedDefaults.removeObject(forKey: SharedConstants.GroupUserDefaults.topFilterItems)
            sharedDefaults.removeObject(forKey: SharedConstants.GroupUserDefaults.topFilterName)
            let playingStatus = PlaybackManager.onMainSync { $0.playing() }
            sharedDefaults.set(playingStatus, forKey: SharedConstants.GroupUserDefaults.isPlaying)

            sharedDefaults.synchronize()
        } catch {
            FileLog.shared.addMessage("Unable to encode data for Up Next Widget: \(error.localizedDescription)")
        }
    }

    private func publishTopFilterInfo() {
        guard let sharedDefaults = UserDefaults(suiteName: SharedConstants.GroupUserDefaults.groupContainerId) else { return }

        var filterItems = [CommonUpNextItem]()
        var filterName: String?
        if let topFilter = DataManager.sharedManager.allPlaylists(includeDeleted: false).first {
            filterName = topFilter.playlistName
            let request = PlaylistQueryBuilder.filterEpisodesRequest(for: topFilter, episodeUuidToAdd: topFilter.episodeUuidToAddToQueries(), limit: WidgetHelper.maxFilterToPublish)

            let loadedEpisodes = DataManager.sharedManager.episodes(matching: request)
            for (index, playlistEpisode) in loadedEpisodes.enumerated() {
                if index >= WidgetHelper.maxFilterToPublish { break }

                if let episode = DataManager.sharedManager.findBaseEpisode(uuid: playlistEpisode.uuid), let item = convertToWidgetItem(episode: episode) {
                    filterItems.append(item)
                }
            }
        }
        do {
            let serializedItems = try JSONEncoder().encode(filterItems)
            sharedDefaults.set(serializedItems, forKey: SharedConstants.GroupUserDefaults.topFilterItems)
            sharedDefaults.set(filterName, forKey: SharedConstants.GroupUserDefaults.topFilterName)
            sharedDefaults.set(false, forKey: SharedConstants.GroupUserDefaults.isPlaying)
            sharedDefaults.removeObject(forKey: SharedConstants.GroupUserDefaults.upNextItems)
            sharedDefaults.synchronize()
        } catch {
            FileLog.shared.addMessage("Unable to encode top filter data  Widget: \(error.localizedDescription)")
        }
    }

    private func convertToWidgetItem(episode: BaseEpisode) -> CommonUpNextItem? {
        let episodeTitle = episode.title ?? ""
        var duration = episode.duration
        var isPlaying = false
        let currentTime = PlaybackManager.onMainSync { $0.currentTime() }

        if episode.uuid == PlaybackManager.onMainSync({ $0.currentEpisode() })?.uuid, currentTime.isFinite {
            duration = duration - currentTime
            isPlaying = PlaybackManager.onMainSync { $0.playing() }
        }
        let podcastColor: UIColor = ColorManager.backgroundColorForPodcastUuid(episode.parentIdentifier())
        var imageUrl = ""

        if let episode = episode as? Episode {
            imageUrl = ServerHelper.image(podcastUuid: episode.parentIdentifier(), size: 340)
        } else if let userEpisode = episode as? UserEpisode {
            imageUrl = userEpisodeImageString(userEpisode)
        }

        return CommonUpNextItem(episodeUuid: episode.uuid, imageUrl: imageUrl, episodeTitle: episodeTitle, podcastName: episode.subTitle(), podcastColor: podcastColor.hexString(), duration: duration, isPlaying: isPlaying)
    }

    func publishAppIcon() {
        guard let sharedDefaults = UserDefaults(suiteName: SharedConstants.GroupUserDefaults.groupContainerId) else { return }
        let sharedAppIcon = sharedDefaults.object(forKey: SharedConstants.GroupUserDefaults.appIcon) as? String
        // UserDefaults is thread-safe; boxed so the main-actor hop can write back
        let boxedDefaults = PocketCastsUtils.UncheckedSendable(sharedDefaults)
        Task { @MainActor in
            let currentAppIcon = UIApplication.shared.alternateIconName

            if currentAppIcon != sharedAppIcon {
                boxedDefaults.value.set(currentAppIcon, forKey: SharedConstants.GroupUserDefaults.appIcon)
                boxedDefaults.value.synchronize()
            }
        }
    }

    func updateCustomImage(userEpisode: UserEpisode) {
        guard PlaybackManager.episodeIsInUpNext(uuid: userEpisode.uuid), userEpisode.urlForImage().isFileURL, let sharedPath = sharedWidgetImagePathFor(userEpisode) else { return }
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: sharedPath.path) {
            do {
                try fileManager.removeItem(atPath: sharedPath.path)
            } catch {}
        }
        updateSharedUpNext()
    }

    private func sharedWidgetImagePathFor(_ userEpisode: UserEpisode) -> URL? {
        let sharedDirectory = sharedWidgetImageDirectory()
        let fileName = "\(userEpisode.uuid).jpg"
        return sharedDirectory?.appendingPathComponent(fileName)
    }

    private func sharedWidgetImageDirectory() -> URL? {
        let fileManager = FileManager.default
        guard let container = fileManager.containerURL(forSecurityApplicationGroupIdentifier: WidgetHelper.appGroupId) else {
            return nil
        }
        return container.appendingPathComponent("widget_images")
    }

    private func userEpisodeImageString(_ userEpisode: UserEpisode) -> String {
        let imageUrl = userEpisode.urlForImage().absoluteString
        guard imageUrl.hasPrefix("file"), let path = URL(string: imageUrl), let sharedDirectory = sharedWidgetImageDirectory(), let sharedPath = sharedWidgetImagePathFor(userEpisode) else {
            return imageUrl
        }
        do {
            let fileManager = FileManager.default
            var isDir: ObjCBool = false
            if !fileManager.fileExists(atPath: sharedDirectory.path, isDirectory: &isDir) {
                try fileManager.createDirectory(at: sharedDirectory, withIntermediateDirectories: false, attributes: nil)
            }
            if !fileManager.fileExists(atPath: sharedPath.path),
               let customImage = UIImage(contentsOfFile: path.path), let downsized = customImage.resized(to: CGSize(width: 280, height: 280)) {
                try downsized.jpegData(compressionQuality: 1)?.write(to: sharedPath)
            }
            return sharedPath.absoluteString
        } catch let error as NSError {
            FileLog.shared.addMessage("Failed to copy custom file image to app group \(error.localizedDescription)")
        }
        return ""
    }

    func cleanupAppGroupImages() {
        guard let imageDirectory = sharedWidgetImageDirectory() else { return }

        let fileManager = FileManager.default

        // don't bother cleaning the folder if it hasn't been created
        guard fileManager.fileExists(atPath: imageDirectory.absoluteString) else { return }

        do {
            var upNextUuids = [String]()
            let upNextEpisodes = PlaybackManager.onMainSync { $0.allEpisodesInQueue(includeNowPlaying: true) }
            if !upNextEpisodes.isEmpty {
                let numUpNextUuids = max(0, min(WidgetHelper.maxUpNextToPublish, upNextEpisodes.count - 1))
                upNextUuids = upNextEpisodes[0 ... numUpNextUuids].map(\.uuid)
            }

            let fileURLs = try fileManager.contentsOfDirectory(at: imageDirectory, includingPropertiesForKeys: nil)
            for file in fileURLs {
                let uuid = file.lastPathComponent.replacingOccurrences(of: ".jpg", with: "")
                if !upNextUuids.contains(uuid) {
                    try fileManager.removeItem(atPath: file.path)
                }
            }
        } catch let error as NSError {
            FileLog.shared.addMessage("Failed to clean up custom images from app group: \(error.localizedDescription)")
        }
    }
}
