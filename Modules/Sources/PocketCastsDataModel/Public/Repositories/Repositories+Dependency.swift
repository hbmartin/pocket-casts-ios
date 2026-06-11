import PocketCastsDependencyInjection

// Dependency-container registrations for the repository protocols. All keys
// default to the production `DataManager.sharedManager`; tests override them
// with mocks (see PocketCastsDataModelTesting), and a future persistence
// engine can be swapped in here without touching consumers.

struct UpNextRepositoryKey: DependencyKey {
    static var currentValue: any UpNextRepository = DataManager.sharedManager
}

struct PodcastRepositoryKey: DependencyKey {
    static var currentValue: any PodcastRepository = DataManager.sharedManager
}

struct EpisodeRepositoryKey: DependencyKey {
    static var currentValue: any EpisodeRepository = DataManager.sharedManager
}

struct UserEpisodeRepositoryKey: DependencyKey {
    static var currentValue: any UserEpisodeRepository = DataManager.sharedManager
}

struct PlaylistRepositoryKey: DependencyKey {
    static var currentValue: any PlaylistRepository = DataManager.sharedManager
}

struct FolderRepositoryKey: DependencyKey {
    static var currentValue: any FolderRepository = DataManager.sharedManager
}

struct DataMaintenanceKey: DependencyKey {
    static var currentValue: any DataMaintenance = DataManager.sharedManager
}

public extension DefaultDependencyContainer {
    var upNextRepository: any UpNextRepository {
        get { Self[UpNextRepositoryKey.self] }
        set { Self[UpNextRepositoryKey.self] = newValue }
    }

    var podcastRepository: any PodcastRepository {
        get { Self[PodcastRepositoryKey.self] }
        set { Self[PodcastRepositoryKey.self] = newValue }
    }

    var episodeRepository: any EpisodeRepository {
        get { Self[EpisodeRepositoryKey.self] }
        set { Self[EpisodeRepositoryKey.self] = newValue }
    }

    var userEpisodeRepository: any UserEpisodeRepository {
        get { Self[UserEpisodeRepositoryKey.self] }
        set { Self[UserEpisodeRepositoryKey.self] = newValue }
    }

    var playlistRepository: any PlaylistRepository {
        get { Self[PlaylistRepositoryKey.self] }
        set { Self[PlaylistRepositoryKey.self] = newValue }
    }

    var folderRepository: any FolderRepository {
        get { Self[FolderRepositoryKey.self] }
        set { Self[FolderRepositoryKey.self] = newValue }
    }

    var dataMaintenance: any DataMaintenance {
        get { Self[DataMaintenanceKey.self] }
        set { Self[DataMaintenanceKey.self] = newValue }
    }
}
