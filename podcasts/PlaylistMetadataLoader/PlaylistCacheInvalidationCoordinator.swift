import Combine
import PocketCastsDataModel

/// Coordinates playlist cache invalidation in response to episode changes.
/// Subscribes to episode change notifications, determines which playlists are affected,
/// and triggers stale marking with debounced refresh.
/// Pending changes are guarded by pendingChangesLock; observers/cancellable are
/// configured once at start-up.
/// @unchecked Sendable: pendingChanges is pendingChangesLock-guarded; observers and the cancellable are configured once at start-up.
nonisolated final class PlaylistCacheInvalidationCoordinator: @unchecked Sendable {

    private let playlistMetadataLoader: PlaylistMetadataLoader
    private let dataManager: DataManager
    private var messageTokens: [NotificationCenter.ObservationToken] = []

    /// Subject for debouncing change processing
    private let changeSubject = PassthroughSubject<Void, Never>()
    private var debounceCancellable: AnyCancellable?

    /// Pending changes to coalesce before processing
    private var pendingChanges: [(changeType: EpisodeChangeType, podcastUuid: String?)] = []
    private let pendingChangesLock = NSLock()

    init(
        playlistMetadataLoader: PlaylistMetadataLoader,
        dataManager: DataManager = .sharedManager,
        debounceDelay: TimeInterval = 0.3
    ) {
        self.playlistMetadataLoader = playlistMetadataLoader
        self.dataManager = dataManager

        debounceCancellable = changeSubject
            .debounce(for: .seconds(debounceDelay), scheduler: DispatchQueue.global(qos: .userInitiated))
            .sink { [weak self] in
                self?.processPendingChanges()
            }
    }

    deinit {
        stopObserving()
    }

    /// Starts observing episode change notifications.
    ///
    /// Per-episode messages carry only the episode uuid, from which the legacy
    /// observers never recovered a podcast uuid (extractPodcastUuid only read
    /// userInfo["podcastUuid"] or an Episode object, and posters send neither) —
    /// `podcastUuid: nil` preserves that exactly.
    func startObserving() {
        guard messageTokens.isEmpty else { return }

        let center = NotificationCenter.default

        // Play status changes
        messageTokens.append(center.addObserver(for: EpisodePlayStatusChanged.self) { [weak self] _ in
            self?.handleChange(.playStatus, podcastUuid: nil)
        })

        // Download status changes
        messageTokens.append(center.addObserver(for: EpisodeDownloadStatusChanged.self) { [weak self] _ in
            self?.handleChange(.downloadStatus, podcastUuid: nil)
        })

        // Starred status changes
        messageTokens.append(center.addObserver(for: EpisodeStarredChanged.self) { [weak self] _ in
            self?.handleChange(.starred, podcastUuid: nil)
        })

        // Archive status changes
        messageTokens.append(center.addObserver(for: EpisodeArchiveStatusChanged.self) { [weak self] _ in
            self?.handleChange(.archived, podcastUuid: nil)
        })

        // Bulk changes (many episodes changed)
        messageTokens.append(center.addObserver(for: ManyEpisodesChanged.self) { [weak self] _ in
            self?.handleChange(.bulkChange, podcastUuid: nil)
        })
    }

    /// Stops observing episode change notifications.
    func stopObserving() {
        let center = NotificationCenter.default
        messageTokens.forEach { center.removeObserver($0) }
        messageTokens.removeAll()
    }

    // MARK: - Private

    private func handleChange(_ changeType: EpisodeChangeType, podcastUuid: String?) {
        pendingChangesLock.lock()
        pendingChanges.append((changeType, podcastUuid))
        pendingChangesLock.unlock()

        changeSubject.send()
    }

    private func processPendingChanges() {
        pendingChangesLock.lock()
        let changes = pendingChanges
        pendingChanges.removeAll()
        pendingChangesLock.unlock()

        guard !changes.isEmpty else { return }

        // Check if any change is a bulk change - if so, mark all stale
        if changes.contains(where: { $0.changeType == .bulkChange }) {
            Task { [playlistMetadataLoader] in
                await playlistMetadataLoader.markAllStale()
            }
            return
        }

        // Group changes by type and collect unique podcast UUIDs
        var changesByType: [EpisodeChangeType: Set<String>] = [:]
        for (changeType, podcastUuid) in changes {
            if changesByType[changeType] == nil {
                changesByType[changeType] = []
            }
            if let uuid = podcastUuid {
                changesByType[changeType]?.insert(uuid)
            }
        }

        // Keep playlist fetching off the main actor; markStaleIfAffected is actor-isolated.
        Task.detached { [changesByType, dataManager, playlistMetadataLoader] in
            // Fetch all playlists on background thread to avoid blocking main
            let playlists = dataManager.allPlaylists(includeDeleted: false)

            for (changeType, podcastUuids) in changesByType {
                if podcastUuids.isEmpty {
                    // No specific podcast, check all
                    await playlistMetadataLoader.markStaleIfAffected(
                        by: changeType,
                        podcastUuid: nil,
                        playlists: playlists
                    )
                } else {
                    // Check each podcast
                    for podcastUuid in podcastUuids {
                        await playlistMetadataLoader.markStaleIfAffected(
                            by: changeType,
                            podcastUuid: podcastUuid,
                            playlists: playlists
                        )
                    }
                }
            }
        }
    }
}
