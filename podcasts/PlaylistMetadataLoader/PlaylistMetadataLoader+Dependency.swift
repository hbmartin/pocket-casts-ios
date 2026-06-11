import PocketCastsDependencyInjection

struct PlaylistMetadataLoaderKey: DependencyKey {
    static var currentValue = PlaylistMetadataLoader()
}

struct PlaylistCacheInvalidationCoordinatorKey: DependencyKey {
    static var currentValue = PlaylistCacheInvalidationCoordinator(
        playlistMetadataLoader: PlaylistMetadataLoaderKey.currentValue
    )
}

extension DefaultDependencyContainer {
    var playlistMetadataLoader: PlaylistMetadataLoader {
        get { Self[PlaylistMetadataLoaderKey.self] }
        nonmutating set { Self[PlaylistMetadataLoaderKey.self] = newValue }
    }

    var playlistCacheInvalidationCoordinator: PlaylistCacheInvalidationCoordinator {
        get { Self[PlaylistCacheInvalidationCoordinatorKey.self] }
        nonmutating set { Self[PlaylistCacheInvalidationCoordinatorKey.self] = newValue }
    }
}
