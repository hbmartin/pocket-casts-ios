import Dependencies

// swift-dependencies registrations for the repository protocols. All keys
// default to the production `DataManager.sharedManager`; consumer tests
// override them with mocks (see PocketCastsDataModelTesting) via
// `withDependencies`, and a future persistence engine can be swapped in here
// without touching consumers.
//
// `testValue` mirrors `liveValue` deliberately: the app test suite swaps a
// fresh test `DataManager` into `sharedManager` and exercises these paths
// against it (the retired homegrown container behaved the same way), so an
// unimplemented-dependency failure here would be a behavior change, not a
// safety win.

enum UpNextRepositoryKey: DependencyKey {
    static var liveValue: any UpNextRepository { DataManager.sharedManager }
    static var testValue: any UpNextRepository { DataManager.sharedManager }
}

enum PodcastRepositoryKey: DependencyKey {
    static var liveValue: any PodcastRepository { DataManager.sharedManager }
    static var testValue: any PodcastRepository { DataManager.sharedManager }
}

enum EpisodeRepositoryKey: DependencyKey {
    static var liveValue: any EpisodeRepository { DataManager.sharedManager }
    static var testValue: any EpisodeRepository { DataManager.sharedManager }
}

enum UserEpisodeRepositoryKey: DependencyKey {
    static var liveValue: any UserEpisodeRepository { DataManager.sharedManager }
    static var testValue: any UserEpisodeRepository { DataManager.sharedManager }
}

enum PlaylistRepositoryKey: DependencyKey {
    static var liveValue: any PlaylistRepository { DataManager.sharedManager }
    static var testValue: any PlaylistRepository { DataManager.sharedManager }
}

enum FolderRepositoryKey: DependencyKey {
    static var liveValue: any FolderRepository { DataManager.sharedManager }
    static var testValue: any FolderRepository { DataManager.sharedManager }
}

enum DataMaintenanceKey: DependencyKey {
    static var liveValue: any DataMaintenance { DataManager.sharedManager }
    static var testValue: any DataMaintenance { DataManager.sharedManager }
}

public extension DependencyValues {
    var upNextRepository: any UpNextRepository {
        get { self[UpNextRepositoryKey.self] }
        set { self[UpNextRepositoryKey.self] = newValue }
    }

    var podcastRepository: any PodcastRepository {
        get { self[PodcastRepositoryKey.self] }
        set { self[PodcastRepositoryKey.self] = newValue }
    }

    var episodeRepository: any EpisodeRepository {
        get { self[EpisodeRepositoryKey.self] }
        set { self[EpisodeRepositoryKey.self] = newValue }
    }

    var userEpisodeRepository: any UserEpisodeRepository {
        get { self[UserEpisodeRepositoryKey.self] }
        set { self[UserEpisodeRepositoryKey.self] = newValue }
    }

    var playlistRepository: any PlaylistRepository {
        get { self[PlaylistRepositoryKey.self] }
        set { self[PlaylistRepositoryKey.self] = newValue }
    }

    var folderRepository: any FolderRepository {
        get { self[FolderRepositoryKey.self] }
        set { self[FolderRepositoryKey.self] = newValue }
    }

    var dataMaintenance: any DataMaintenance {
        get { self[DataMaintenanceKey.self] }
        set { self[DataMaintenanceKey.self] = newValue }
    }
}
