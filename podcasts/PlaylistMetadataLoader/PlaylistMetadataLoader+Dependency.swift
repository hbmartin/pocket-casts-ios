import Dependencies

enum PlaylistMetadataLoaderKey: DependencyKey {
    static let liveValue = PlaylistMetadataLoader()
}

enum PlaylistCacheInvalidationCoordinatorKey: DependencyKey {
    static let liveValue = PlaylistCacheInvalidationCoordinator(
        playlistMetadataLoader: PlaylistMetadataLoaderKey.liveValue
    )
}

extension DependencyValues {
    var playlistMetadataLoader: PlaylistMetadataLoader {
        get { self[PlaylistMetadataLoaderKey.self] }
        set { self[PlaylistMetadataLoaderKey.self] = newValue }
    }

    var playlistCacheInvalidationCoordinator: PlaylistCacheInvalidationCoordinator {
        get { self[PlaylistCacheInvalidationCoordinatorKey.self] }
        set { self[PlaylistCacheInvalidationCoordinatorKey.self] = newValue }
    }
}
