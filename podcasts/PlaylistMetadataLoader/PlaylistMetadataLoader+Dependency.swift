import Dependencies

nonisolated enum PlaylistMetadataLoaderKey: DependencyKey {
    static let liveValue = PlaylistMetadataLoader()
}

nonisolated enum PlaylistCacheInvalidationCoordinatorKey: DependencyKey {
    static let liveValue = PlaylistCacheInvalidationCoordinator(
        playlistMetadataLoader: PlaylistMetadataLoaderKey.liveValue
    )
}

nonisolated extension DependencyValues {
    var playlistMetadataLoader: PlaylistMetadataLoader {
        get { self[PlaylistMetadataLoaderKey.self] }
        set { self[PlaylistMetadataLoaderKey.self] = newValue }
    }

    var playlistCacheInvalidationCoordinator: PlaylistCacheInvalidationCoordinator {
        get { self[PlaylistCacheInvalidationCoordinatorKey.self] }
        set { self[PlaylistCacheInvalidationCoordinatorKey.self] = newValue }
    }
}
