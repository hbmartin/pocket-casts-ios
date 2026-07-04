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

// @unchecked Sendable: repository dependency values must be Sendable. The
// production `DataManager` facade delegates storage to GRDB's thread-safe queue
// and sub-managers that serialize their mutable caches. Keep the unchecked
// promise here at the repository boundary instead of on the class declaration;
// subclasses that add mutable state must still avoid crossing concurrency
// domains unless they provide their own synchronization.
extension DataManager: @unchecked Sendable {}

protocol MirroredTestDependencyKey: DependencyKey {}

extension MirroredTestDependencyKey {
    static var testValue: Value { liveValue }
}

enum UpNextRepositoryKey: MirroredTestDependencyKey {
    static var liveValue: any UpNextRepository { DataManager.sharedManager }
}

enum PodcastRepositoryKey: MirroredTestDependencyKey {
    static var liveValue: any PodcastRepository { DataManager.sharedManager }
}

enum EpisodeRepositoryKey: MirroredTestDependencyKey {
    static var liveValue: any EpisodeRepository { DataManager.sharedManager }
}

enum UserEpisodeRepositoryKey: MirroredTestDependencyKey {
    static var liveValue: any UserEpisodeRepository { DataManager.sharedManager }
}

enum PlaylistRepositoryKey: MirroredTestDependencyKey {
    static var liveValue: any PlaylistRepository { DataManager.sharedManager }
}

enum FolderRepositoryKey: MirroredTestDependencyKey {
    static var liveValue: any FolderRepository { DataManager.sharedManager }
}

enum DataMaintenanceKey: MirroredTestDependencyKey {
    static var liveValue: any DataMaintenance { DataManager.sharedManager }
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
