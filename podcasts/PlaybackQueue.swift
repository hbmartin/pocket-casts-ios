import PocketCastsDataModel
import PocketCastsServer
import PocketCastsUtils
import UIKit

@MainActor
class PlaybackQueue: NSObject {
    // Explicitly nonisolated: default-MainActor synthesized deinits hop executors and crash sync XCTests (swiftlang/swift#87316).
    nonisolated deinit {}
    // we get asked for this a lot, so might as well cache it
    private var topEpisode: BaseEpisode?

    private let syncTimerDelay: TimeInterval = 5
    private let interactionGracePeriod: TimeInterval = 10
    private var syncTimer: Timer?
    private var lastUserInteractionTime: Date?

    // MARK: - User Interaction Tracking

    func recordUpNextUserInteraction(at date: Date = Date()) {
        lastUserInteractionTime = date
    }

    func recentUserInteraction(now: Date = Date()) -> Bool {
        remainingInteractionDelay(now: now) != nil
    }

    private func remainingInteractionDelay(now: Date = Date()) -> TimeInterval? {
        guard let lastUserInteractionTime else { return nil }

        let elapsed = now.timeIntervalSince(lastUserInteractionTime)
        let remaining = interactionGracePeriod - elapsed

        return remaining > 0 ? remaining : nil
    }

    // MARK: - Editing

    func remove(episode: BaseEpisode, fireNotification: Bool) {
        guard let episodeToRemove = DataManager.sharedManager.findPlaylistEpisode(uuid: episode.uuid) else { return }

        FileLog.shared.addMessage("PlaybackQueue: removing \(episode.title ?? "Untitled") episode")
        DataManager.sharedManager.delete(playlistEpisode: episodeToRemove)
        if SyncManager.isUserLoggedIn() {
            DataManager.sharedManager.saveUpNextRemove(episodeUuid: episode.uuid)
            SyncManager.syncReason = .remove
            startSyncTimer()
        }

        refreshAppFiring(fireNotification ? UpNextEpisodeRemoved(uuid: episode.uuid) : nil)
    }

    func remove(uuid: String, fireNotification: Bool) {
        guard let episodeToRemove = DataManager.sharedManager.findPlaylistEpisode(uuid: uuid) else { return }

        FileLog.shared.addMessage("PlaybackQueue: removing \(episodeToRemove.title) episode")
        DataManager.sharedManager.delete(playlistEpisode: episodeToRemove)
        if SyncManager.isUserLoggedIn() {
            DataManager.sharedManager.saveUpNextRemove(episodeUuid: uuid)
            SyncManager.syncReason = .remove
            startSyncTimer()
        }

        refreshAppFiring(fireNotification ? UpNextEpisodeRemoved(uuid: uuid) : nil)
    }

    func removeTopEpisode(fireNotification: Bool) {
        guard let topEpisode else { return }

        FileLog.shared.addMessage("Remove Top Episode \(topEpisode.title ?? "Untitled")")
        remove(episode: topEpisode, fireNotification: fireNotification)
    }

    func add(episode: BaseEpisode, fireNotification: Bool, partOfBulkAdd: Bool = false, toTop: Bool = false) {
        if var existingEpisode = DataManager.sharedManager.findPlaylistEpisode(uuid: episode.uuid) {
            existingEpisode.episodePosition = DataManager.sharedManager.positionForPlaylistEpisode(bottomOfList: !toTop)
            DataManager.sharedManager.save(playlistEpisode: existingEpisode)
        } else {
            var newEpisode = PlaylistEpisode()
            newEpisode.episodeUuid = episode.uuid
            newEpisode.episodePosition = DataManager.sharedManager.positionForPlaylistEpisode(bottomOfList: !toTop)
            newEpisode.title = episode.displayableTitle()
            newEpisode.podcastUuid = episode.parentIdentifier()

            DataManager.sharedManager.save(playlistEpisode: newEpisode)
        }

        if !partOfBulkAdd, SyncManager.isUserLoggedIn() {
            if toTop {
                DataManager.sharedManager.saveUpNextAddToTop(episodeUuid: episode.uuid)
            } else {
                DataManager.sharedManager.saveUpNextAddToBottom(episodeUuid: episode.uuid)
            }

            SyncManager.syncReason = .add
            startSyncTimer()
        }

        // don't update until this bulk operation is complete
        if partOfBulkAdd { return }

        FileLog.shared.addMessage("PlaybackQueue: added single episode \(episode.title ?? "Untitled")")

        refreshAppFiring(fireNotification ? UpNextEpisodeAdded(uuid: episode.uuid, addedToTop: toTop) : nil)
    }

    func bulkOperationDidComplete() {
        saveReplaceIfRequired()

        FileLog.shared.addMessage("PlaybackQueue: finished bulk add")

        refreshAppFiring(UpNextQueueChanged())
    }

    func bulkDelete(uuids: [String]) {
        DataManager.sharedManager.deleteAllUpNextEpisodesIn(uuids: uuids)
        saveReplaceIfRequired()
        refreshAppFiring(UpNextQueueChanged())
    }

    func bulkAdd(_ episodes: [BaseEpisode], toTop: Bool = false) {
        let topPosition = DataManager.sharedManager.positionForPlaylistEpisode(bottomOfList: !toTop)
        var playlistEpisodes = [PlaylistEpisode]()
        for (index, episode) in episodes.enumerated() {
            if var existingEpisode = DataManager.sharedManager.findPlaylistEpisode(uuid: episode.uuid) {
                existingEpisode.episodePosition = topPosition + Int32(index)
                playlistEpisodes.append(existingEpisode)
            } else {
                var newEpisode = PlaylistEpisode()
                newEpisode.episodeUuid = episode.uuid
                newEpisode.episodePosition = topPosition + Int32(index)
                newEpisode.title = episode.displayableTitle()
                newEpisode.podcastUuid = episode.parentIdentifier()
                playlistEpisodes.append(newEpisode)
            }
        }
        DataManager.sharedManager.save(playlistEpisodes: playlistEpisodes)

        bulkOperationDidComplete()
    }

    func bulkMove(_ playlistEpisodes: [PlaylistEpisode], toTop: Bool) {
        let firstIndex = DataManager.sharedManager.positionForPlaylistEpisode(bottomOfList: !toTop)
        var playlistEpisodes = playlistEpisodes
        for index in playlistEpisodes.indices {
            playlistEpisodes[index].episodePosition = Int32(index) + firstIndex
        }

        DataManager.sharedManager.save(playlistEpisodes: playlistEpisodes)

        bulkOperationDidComplete()
    }

    func persistLocalCopyAsReplace() {
        saveReplaceIfRequired()
        startSyncTimer()
    }

    func pushNewCurrentlyPlaying(episode: BaseEpisode) {
        if let existingEpisode = DataManager.sharedManager.findPlaylistEpisode(uuid: episode.uuid) {
            DataManager.sharedManager.movePlaylistEpisode(from: Int(existingEpisode.episodePosition), to: 0)
        } else {
            var newEpisode = PlaylistEpisode()
            newEpisode.episodeUuid = episode.uuid
            newEpisode.episodePosition = -1
            newEpisode.title = episode.displayableTitle()
            newEpisode.podcastUuid = episode.parentIdentifier()

            DataManager.sharedManager.save(playlistEpisode: newEpisode)
            DataManager.sharedManager.movePlaylistEpisode(from: -1, to: 0)
        }

        if SyncManager.isUserLoggedIn() {
            DataManager.sharedManager.saveUpNextAddNowPlaying(episodeUuid: episode.uuid)
            startSyncTimer()
        }

        refreshAppFiring(UpNextQueueChanged())
    }

    func moveEpisode(from: Int, to: Int) {
        // externally to the rest of the app, the now playing episode isn't in up next, so we need to increment these indexes
        DataManager.sharedManager.movePlaylistEpisode(from: from + 1, to: to + 1)

        saveReplaceIfRequired()

        refreshAppFiring(UpNextQueueChanged())
    }

    /// Reorders the Up Next queue to match `sortedEpisodes` (the queued episodes excluding now playing, which stays pinned at the top).
    func reorderUpNext(sortedEpisodes: [BaseEpisode]) {
        guard sortedEpisodes.count > 1 else { return }

        // Up Next playlist entries, excluding the now playing episode at index 0.
        var remaining = Array(DataManager.sharedManager.allUpNextPlaylistEpisodes().dropFirst())
        var ordered = [PlaylistEpisode]()

        // Match the sorted episodes back to their playlist entries...
        for episode in sortedEpisodes {
            if let index = remaining.firstIndex(where: { $0.episodeUuid == episode.uuid }) {
                ordered.append(remaining.remove(at: index))
            }
        }
        // ...and keep any entries without metadata (e.g. not-yet-synced episodes) at the bottom.
        ordered.append(contentsOf: remaining)

        for index in ordered.indices {
            // position 0 is the now playing episode, so the queue starts at 1
            ordered[index].episodePosition = Int32(index + 1)
        }
        DataManager.sharedManager.save(playlistEpisodes: ordered)

        saveReplaceIfRequired()

        refreshAppFiring(UpNextQueueChanged())
    }

    func insert(episode: BaseEpisode, position: Int) {
        let existingEpisode = contains(episode: episode)

        if existingEpisode {
            move(episode: episode, to: position)
        } else {
            var newEpisode = PlaylistEpisode()
            newEpisode.episodeUuid = episode.uuid
            newEpisode.episodePosition = Int32(position + 1)
            newEpisode.title = episode.displayableTitle()
            newEpisode.podcastUuid = episode.parentIdentifier()

            DataManager.sharedManager.save(playlistEpisode: newEpisode)
            saveReplaceIfRequired()
        }

        refreshAppFiring(UpNextQueueChanged())
    }

    func move(episode: BaseEpisode, to: Int, fireNotification: Bool = true) {
        guard let episodeToMove = DataManager.sharedManager.findPlaylistEpisode(uuid: episode.uuid) else { return }

        // externally to the rest of the app, the now playing episode isn't in up next, so we need to increment this index
        DataManager.sharedManager.movePlaylistEpisode(from: Int(episodeToMove.episodePosition), to: to + 1)

        saveReplaceIfRequired()

        refreshAppFiring(fireNotification ? UpNextQueueChanged() : nil)
    }

    func overrideAllEpisodesWith(episode: BaseEpisode) {
        FileLog.shared.addMessage("PlaybackQueue: overrideAllEpisodesWith with \(episode.title ?? "Untitled")")

        let upNext = DataManager.sharedManager.allUpNextEpisodes()
        let shouldRemoveInsteadOfReplace = upNext.count == 1

        if shouldRemoveInsteadOfReplace {
            if let episode = upNext.first {
                remove(episode: episode, fireNotification: false)
            }
        }

        DataManager.sharedManager.deleteAllUpNextEpisodes()
        if !shouldRemoveInsteadOfReplace {
            saveReplaceIfRequired(episodeList: [episode.uuid])
        }

        pushNewCurrentlyPlaying(episode: episode)
    }

    func removeAllEpisodes() {
        DataManager.sharedManager.snapshotUpNext()

        FileLog.shared.addMessage("PlaybackQueue: removeAllEpisodes called, clearing list")

        DataManager.sharedManager.deleteAllUpNextEpisodes()

        topEpisode = nil
        saveReplaceIfRequired()

        NotificationCenter.postOnMainThread(UpNextQueueChanged())
    }

    func clearUpNextList() {
        guard let topEpisode else { return }

        DataManager.sharedManager.snapshotUpNext()

        DataManager.sharedManager.deleteAllUpNextEpisodesExcept(episodeUuid: topEpisode.uuid)
        FileLog.shared.addMessage("PlaybackQueue: clearUpNextList called, clearing list")

        saveReplaceIfRequired()

        NotificationCenter.postOnMainThread(UpNextQueueChanged())
    }

    func refreshList(checkForAutoDownload: Bool) {
        cacheTopEpisode()
        updateUpNextInfo()

        if checkForAutoDownload {
            checkAllForAutoDownload()
        }
    }

    func nowPlayingEpisodeChanged() {
        cacheTopEpisode()
        NotificationCenter.postOnMainThread(CurrentlyPlayingEpisodeUpdated())
    }

    // MARK: - Querying

    func contains(episode: BaseEpisode) -> Bool {
        contains(episodeUuid: episode.uuid)
    }

    func contains(episodeUuid: String) -> Bool {
        DataManager.sharedManager.upNextPlayListContains(episodeUuid: episodeUuid)
    }

    func allEpisodes(includeNowPlaying: Bool = true) -> [BaseEpisode] {
        Self.allUpNextEpisodesFromDatabase(includeNowPlaying: includeNowPlaying)
    }

    /// Pure DB query; nonisolated for the background auto-download sweep.
    nonisolated static func allUpNextEpisodesFromDatabase(includeNowPlaying: Bool) -> [BaseEpisode] {
        if includeNowPlaying { return DataManager.sharedManager.allUpNextEpisodes() }

        var episodes = DataManager.sharedManager.allUpNextEpisodes()
        if episodes.isEmpty { return episodes }

        episodes.removeFirst()

        return episodes
    }

    func allEpisodeUuids() -> [BaseEpisode] {
        var episodes = DataManager.sharedManager.allUpNextEpisodeUuids()
        if episodes.isEmpty { return episodes }

        episodes.removeFirst()

        return episodes
    }

    func currentEpisode() -> BaseEpisode? {
        topEpisode
    }

    func upNextCount() -> Int {
        Self.currentUpNextCount()
    }

    /// Pure DB query; nonisolated so background callers (autoplay) can read the count.
    nonisolated static func currentUpNextCount() -> Int {
        // the data manager counts the current episode, so we remove it here, since we don't expose that info to the rest of the app
        max(0, DataManager.sharedManager.playlistEpisodeCount() - 1)
    }

    func episodeAt(index: Int) -> BaseEpisode? {
        let actualIndex = index + 1 // the rest of the app doesn't treat the current episode as being at position 0
        if actualIndex < 0 { return nil }

        if let episode = DataManager.sharedManager.episodeInUpNextAt(index: actualIndex) {
            return episode
        }

        guard let playlistEpisode = DataManager.sharedManager.playlistEpisodeAt(index: actualIndex) else { return nil }

        var missingEpisode = UserEpisode()
        missingEpisode.title = playlistEpisode.title
        missingEpisode.uuid = playlistEpisode.episodeUuid
        missingEpisode.episodeStatus = DownloadStatus.downloadFailed.rawValue
        missingEpisode.imageColor = 1

        return missingEpisode
    }

    func upNextTotalDuration(includePlayingEpisode: Bool) -> TimeInterval {
        let episodes = allEpisodes(includeNowPlaying: includePlayingEpisode)

        return episodes.map { $0.duration - $0.playedUpTo }.reduce(0, +)
    }

    // MARK: - Persistence

    func loadPersistedQueue() {
        cacheTopEpisode()
    }

    // MARK: - Private Helpers

    func updateUpNextInfo() {
            WidgetHelper.shared.updateSharedUpNext()
    }

    private func checkAllForAutoDownload() {
        if !Settings.downloadUpNextEpisodes() { return }

        DispatchQueue.global().async {
            let episodes = Self.allUpNextEpisodesFromDatabase(includeNowPlaying: false)
            for episode in episodes {
                Self.autoDownloadIfRequired(episode: episode)
            }
        }
    }

    nonisolated private static func autoDownloadIfRequired(episode: BaseEpisode) {
        if !Settings.downloadUpNextEpisodes() || episode.queued() || episode.downloaded(pathFinder: DownloadManager.shared) { return }

        if Settings.autoDownloadMobileDataAllowed() || NetworkUtils.shared.isConnectedToUnexpensiveConnection() {
            DownloadManager.shared.addToQueue(episodeUuid: episode.uuid, autoDownloadStatus: .autoDownloaded)
        } else {
            DownloadManager.shared.queueForLaterDownload(episodeUuid: episode.uuid, fireNotification: true, autoDownloadStatus: .autoDownloaded)
        }
    }

    private func cacheTopEpisode() {
        topEpisode = episodeAt(index: -1)
    }

    /// Refreshes the queue, posts `message` (when non-nil) and kicks the sync timer.
    /// `final` because generic methods on non-final classes trip a vtable-mangling compiler bug.
    private final func refreshAppFiring<M: NotificationCenter.MainActorMessage & Sendable>(_ message: M?) {
        refreshList(checkForAutoDownload: true)

        if let message {
            NotificationCenter.postOnMainThread(message)
        }

        startSyncTimer()
    }

    private func saveReplaceIfRequired(episodeList: [String]? = nil) {
        if !SyncManager.isUserLoggedIn() { return }

        var episodeUuids = [String]()
        if let episodeList {
            episodeUuids = episodeList
        } else {
            for playlistEpisode in DataManager.sharedManager.allUpNextPlaylistEpisodes() {
                episodeUuids.append(playlistEpisode.episodeUuid)
            }
        }

        FileLog.shared.addMessage("PlaybackQueue: Saving replace of \(upNextCount()) with \(episodeUuids.count) episodes")

        DataManager.sharedManager.saveReplace(episodeList: episodeUuids)

        SyncManager.syncReason = .replace

        startSyncTimer()
    }

    // MARK: - Sync Timer

    private func cancelSyncTimer() {
        syncTimer?.invalidate()
        syncTimer = nil
    }

    private func startSyncTimer(after delay: TimeInterval? = nil) {
        cancelSyncTimer()
        scheduleSyncTimer(after: delay ?? syncTimerDelay)
    }

    private func scheduleSyncTimer(after delay: TimeInterval) {
        let scheduleTimer: () -> Void = { [weak self] in
            guard let self else { return }

            self.syncTimer = Timer.scheduledTimer(timeInterval: delay, target: self, selector: #selector(self.syncTimerFired), userInfo: nil, repeats: false)
        }

        // schedule the timer on a thread that has a run loop, the main thread being a good option
        if Thread.isMainThread {
            scheduleTimer()
        } else {
            let boxed = PocketCastsUtils.UncheckedSendable(scheduleTimer)
            DispatchQueue.main.sync {
                boxed.value()
            }
        }
    }

    @objc private func syncTimerFired() {
        if let remainingDelay = remainingInteractionDelay() {
            FileLog.shared.addMessage("PlaybackQueue: Delaying Up Next sync for \(Int(remainingDelay.rounded(.up))) seconds due to recent interaction")
            startSyncTimer(after: remainingDelay)
            return
        }

        RefreshManager.shared.syncUpNext()
    }
}
