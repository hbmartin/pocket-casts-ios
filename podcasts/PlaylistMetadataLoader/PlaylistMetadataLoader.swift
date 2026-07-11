import Combine
import Foundation
import PocketCastsDataModel
import PocketCastsUtils

// MARK: - PlaylistMetadataLoader

actor PlaylistMetadataLoader {

    // MARK: - Update Types

    /// Represents an update to a playlist's metadata
    enum MetadataUpdate: Sendable {
        case count(playlistID: String, count: Int)
        case images(playlistID: String, images: [PlaylistArtworkView.ImageItem])
    }

    /// Represents the cache state for a playlist's count
    enum CountCacheState: Sendable, Equatable {
        case valid(count: Int)
        case stale(previousCount: Int)

        var count: Int {
            switch self {
            case .valid(let count):
                return count
            case .stale(let previousCount):
                return previousCount
            }
        }

        var isStale: Bool {
            if case .stale = self { return true }
            return false
        }
    }

    // MARK: - Publisher

    /// Thread-safe subject for publishing metadata updates.
    /// Access via `updatesPublisher` for subscribing to changes.
    /// Marked nonisolated(unsafe) because PassthroughSubject is internally thread-safe.
    nonisolated(unsafe) private let updatesSubject = PassthroughSubject<MetadataUpdate, Never>()

    /// Publisher that emits metadata updates when counts or images change.
    /// Subscribe to receive updates for specific playlists.
    nonisolated var updatesPublisher: AnyPublisher<MetadataUpdate, Never> {
        updatesSubject.eraseToAnyPublisher()
    }

    /// Convenience publisher for count updates only.
    /// Emits (playlistID, count) tuples when a playlist's count changes.
    nonisolated var countUpdatesPublisher: AnyPublisher<(playlistID: String, count: Int), Never> {
        updatesSubject
            .compactMap { update in
                if case .count(let playlistID, let count) = update {
                    return (playlistID, count)
                }
                return nil
            }
            .eraseToAnyPublisher()
    }

    /// Convenience publisher for image updates only.
    nonisolated var imageUpdatesPublisher: AnyPublisher<(playlistID: String, images: [PlaylistArtworkView.ImageItem]), Never> {
        updatesSubject
            .compactMap { update in
                if case .images(let playlistID, let images) = update {
                    return (playlistID, images)
                }
                return nil
            }
            .eraseToAnyPublisher()
    }

    /// Subject for publishing when playlists become stale and need refresh.
    /// Marked nonisolated(unsafe) because PassthroughSubject is internally thread-safe.
    nonisolated(unsafe) private let stalePlaylistsSubject = PassthroughSubject<Set<String>, Never>()

    /// Publisher that emits sets of playlist IDs that have become stale.
    /// Subscribe to trigger refresh of visible playlists.
    nonisolated var stalePlaylistsPublisher: AnyPublisher<Set<String>, Never> {
        stalePlaylistsSubject.eraseToAnyPublisher()
    }

    // MARK: - Cache

    private struct Cache {
        var counts: [String: CountCacheState] = [:] {
            didSet {
                lastUpdate = Date()
            }
        }
        var images: [String: [PlaylistArtworkView.ImageItem]] = [:] {
            didSet {
                lastUpdate = Date()
            }
        }
        var lastUpdate: Date?

        mutating func clear() {
            counts.removeAll()
            images.removeAll()
            lastUpdate = nil
        }
    }

    private var cache = Cache()

    private var countTasks: [String: Task<Int, Never>] = [:]
    private var imagesTasks: [String: Task<[PlaylistArtworkView.ImageItem], Never>] = [:]

    private let dataManager: DataManager
    private let episodesDataManager: EpisodesDataManager

    init(
        dataManager: DataManager = .sharedManager,
        episodesDataManager: EpisodesDataManager = .init()
    ) {
        self.dataManager = dataManager
        self.episodesDataManager = episodesDataManager
    }

    func cachedCount(for playlistID: String) -> Int? {
        return cache.counts[playlistID]?.count
    }

    func cachedCountState(for playlistID: String) -> CountCacheState? {
        return cache.counts[playlistID]
    }

    func cachedImages(for playlistID: String) -> [PlaylistArtworkView.ImageItem]? {
        return cache.images[playlistID]
    }

    /// Checks if a playlist's cached count is stale
    func isStale(playlistID: String) -> Bool {
        return cache.counts[playlistID]?.isStale ?? false
    }

    func loadCount(for playlist: EpisodeFilter) async -> Int {
        let playlistID = playlist.uuid

        // Avoid duplicate fetches
        if let task = countTasks[playlistID] {
            return await task.value
        }

        // Start new fetch task
        let task = Task {
            let newCount = await getEpisodesCount(for: playlist)

            countTasks[playlistID] = nil

            // Check if the count actually changed
            if let cached = cache.counts[playlistID], cached.count == newCount {
                // Update to valid state if it was stale
                if cached.isStale {
                    cache.counts[playlistID] = .valid(count: newCount)
                }
                return newCount
            }

            cache.counts[playlistID] = .valid(count: newCount)

            // Publish the update for subscribers
            updatesSubject.send(.count(playlistID: playlistID, count: newCount))

            return newCount
        }
        countTasks[playlistID] = task
        return await task.value
    }

    func loadImages(for playlist: EpisodeFilter) async -> [PlaylistArtworkView.ImageItem] {
        let playlistID = playlist.uuid

        // Avoid duplicate fetches
        if let task = imagesTasks[playlistID] {
            return await task.value
        }

        // Start new fetch task
        let task = Task {
            defer {
                imagesTasks[playlistID] = nil
            }
            let episodes = await loadListEpisodes(for: playlist)
            let distinctEpisodes = firstDistinctPodcasts(from: episodes)

            do {
                let items = try await loadImagesURLs(episodes: distinctEpisodes)

                if let cached = cache.images[playlistID], cached == items {
                    return cached
                }

                cache.images[playlistID] = items

                // Publish the update for subscribers
                updatesSubject.send(.images(playlistID: playlistID, images: items))

                return items
            } catch {
                return cache.images[playlistID] ?? []
            }
        }
        imagesTasks[playlistID] = task
        return await task.value
    }

    func cancelLoadCount(for playlistID: String) {
        countTasks[playlistID]?.cancel()
        countTasks[playlistID] = nil
    }

    func cancelLoadImages(for playlistID: String) {
        imagesTasks[playlistID]?.cancel()
        imagesTasks[playlistID] = nil
    }

    /// Invalidates the cache if it's older than the specified threshold.
    /// Call this when the view appears to ensure fresh data after the threshold.
    /// - Parameter threshold: Time interval after which cache is considered stale. Defaults to 30 seconds.
    /// - Returns: Whether the cache was invalidated.
    @discardableResult
    func invalidateCacheIfStale(threshold: TimeInterval = 30) -> Bool {
        guard let lastUpdate = cache.lastUpdate else {
            // No cache yet, nothing to invalidate
            return false
        }

        let elapsed = Date().timeIntervalSince(lastUpdate)
        if elapsed > threshold {
            cache.clear()
            return true
        }
        return false
    }

    // MARK: - Stale Marking

    /// Marks playlists as stale based on an episode change.
    /// Only marks playlists that would be affected by the change type and podcast.
    ///
    /// - Parameters:
    ///   - changeType: The type of episode change that occurred
    ///   - podcastUuid: The UUID of the podcast the episode belongs to (nil for bulk changes)
    ///   - playlists: The playlists to check against
    func markStaleIfAffected(
        by changeType: EpisodeChangeType,
        podcastUuid: String?,
        playlists: [EpisodeFilter]
    ) {
        var stalePlaylists = Set<String>()

        for playlist in playlists {
            let isAffected: Bool
            if let podcastUuid {
                isAffected = playlist.isAffected(by: changeType, podcastUuid: podcastUuid)
            } else {
                isAffected = playlist.isAffected(by: changeType)
            }

            if isAffected {
                markStale(playlistID: playlist.uuid)
                stalePlaylists.insert(playlist.uuid)
            }
        }

        if !stalePlaylists.isEmpty {
            stalePlaylistsSubject.send(stalePlaylists)
        }
    }

    /// Marks a specific playlist as stale, preserving its previous count.
    private func markStale(playlistID: String) {
        guard let currentState = cache.counts[playlistID] else {
            // No cached value, nothing to mark as stale
            return
        }

        // Only mark as stale if currently valid
        if case .valid(let count) = currentState {
            cache.counts[playlistID] = .stale(previousCount: count)
        }
    }

    /// Marks all cached playlists as stale.
    func markAllStale() {
        var stalePlaylists = Set<String>()

        for (playlistID, state) in cache.counts {
            if case .valid(let count) = state {
                cache.counts[playlistID] = .stale(previousCount: count)
                stalePlaylists.insert(playlistID)
            }
        }

        if !stalePlaylists.isEmpty {
            stalePlaylistsSubject.send(stalePlaylists)
        }
    }

    private func getEpisodesCount(for playlist: EpisodeFilter) async -> Int {
        let playlist = playlist
        let dataManager = self.dataManager

        return await Task(priority: FeatureFlag.playlistDataCacheBeforeQuery.enabled ? .medium : .userInitiated) {
            dataManager.allPlaylistEpisodeCount(
                for: playlist,
                episodeUuidToAdd: playlist.episodeUuidToAddToQueries(),
                includingArchivedEpisodes: playlist.manual
            )
        }.value
    }

    private func loadListEpisodes(for playlist: EpisodeFilter) async -> [ListEpisode] {
        // The playlist and data manager cross into the worker task boxed; the fresh
        // list crosses back the same way
        let boxed = PocketCastsUtils.UncheckedSendable((playlist, episodesDataManager))
        let resultBox: PocketCastsUtils.UncheckedSendable<[ListEpisode]> = await Task(priority: FeatureFlag.playlistDataCacheBeforeQuery.enabled ? .medium : .userInitiated) {
            let (playlist, episodesDataManager) = boxed.value
            return PocketCastsUtils.UncheckedSendable(episodesDataManager.playlistFirstDistinctEpisodes(
                for: playlist,
                shouldShowArchived: playlist.showArchivedEpisodes
            ))
        }.value
        return resultBox.value
    }

    private func loadImagesURLs(episodes: [ListEpisode], includingEpisodeArtwork: Bool = false) async throws -> [PlaylistArtworkView.ImageItem] {
        let fallbackImageSize = await MainActor.run {
            ImageManager.sizeFor(imageSize: .grid)
        }

        return try await withThrowingTaskGroup(of: PlaylistArtworkView.ImageItem.self) { group in
            for episode in episodes {
                let podcastUuid = episode.episode.podcastUuid
                let episodeUuid = episode.episode.uuid
                group.addTask {
                    if includingEpisodeArtwork,
                       let url = try await ShowInfoCoordinator.shared.loadEpisodeArtworkUrl(podcastUuid: podcastUuid, episodeUuid: episodeUuid) {
                        return PlaylistArtworkView.ImageItem(id: episodeUuid, url: url)
                    }
                    let url = ImageManager.podcastUrl(sizeRequired: fallbackImageSize, uuid: podcastUuid)
                    return PlaylistArtworkView.ImageItem(id: podcastUuid, url: url)
                }
            }
            var results: [PlaylistArtworkView.ImageItem] = []
            for try await item in group {
                results.append(item)
            }

            let mapEpisodes = Dictionary(uniqueKeysWithValues: episodes.enumerated().map { ($1.episode.uuid, $0) })
            let mapPodcasts = Dictionary(uniqueKeysWithValues: episodes.enumerated().map { ($1.episode.podcastUuid, $0) })

            return results.sorted { lhs, rhs in
                let lhsIndex = (mapEpisodes[lhs.id] ?? mapPodcasts[lhs.id]) ?? Int.max
                let rhsIndex = (mapEpisodes[rhs.id] ?? mapPodcasts[rhs.id]) ?? Int.max
                return lhsIndex < rhsIndex
            }
        }
    }

    private func firstDistinctPodcasts(
        from episodes: [ListEpisode],
        limit: Int = 4
    ) -> [ListEpisode] {
        PlaylistArtworkHelper.distinctPodcasts(from: episodes, limit: limit) { $0.episode.podcastUuid }
    }
}
