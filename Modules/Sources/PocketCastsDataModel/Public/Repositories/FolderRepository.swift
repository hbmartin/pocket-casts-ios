import Foundation

/// Read and mutate podcast folders and their history snapshots.
///
/// `DataManager` is the production conformer; inject `any FolderRepository` (see
/// `Repositories+Dependency.swift`) so consumers can be tested with mocks and a
/// future persistence engine can ship as a second conformer.
public protocol FolderRepository: AnyObject {
    @discardableResult
    func save(folder: Folder) -> Folder
    func allFolders(includeDeleted: Bool) -> [Folder]
    func findFolder(uuid: String) -> Folder?
    func topPodcastsUuidInFolder(folder: Folder) -> [String]
    func allPodcastsInFolder(folder: Folder) -> [Podcast]
    func countOfPodcastsInFolder(folder: Folder) -> Int
    func countOfPodcastsInRootFolder() -> Int
    func saveSortOrders(folders: [Folder], syncModified: Int64)
    func updateFolderColor(folderUuid: String, color: Int32, syncModified: Int64)
    func updateFolderSyncModified(folderUuid: String, syncModified: Int64)
    func delete(folderUuid: String, markAsDeleted: Bool)
    func bulkSetSyncModified(_ syncModified: Int64, onFolders folderUuids: [String])
    func allUnsyncedFolders() -> [Folder]
    func markAllFoldersSynced()
    func clearAllFolderInformation()
    func deleteAllFoldersAndMarkSync()
    func snapshot(podcastsAndFolders: [String: String])
    func foldersHistoryEntries() -> [FolderHistoryManager.PodcastFoldersHistoryEntry]
    func folderHistory(entry: Date) -> [String: String]
}

public extension FolderRepository {
    // Conveniences mirroring DataManager's default arguments, which protocol
    // requirements cannot express.
    func allFolders() -> [Folder] {
        allFolders(includeDeleted: false)
    }
}

extension DataManager: FolderRepository {}
