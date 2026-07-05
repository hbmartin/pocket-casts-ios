import Foundation
import PocketCastsDataModel

/// Generated protocol mock for `FolderRepository`. Stub return values by selector:
/// `mock.stub("findPodcast(uuid:includeUnsubscribed:)", with: podcast)`.
// @unchecked Sendable: restates RepositoryMock's conformance, as Swift requires of subclasses; state stays lock-guarded in the base class.
public final class FolderRepositoryMock: RepositoryMock, FolderRepository, @unchecked Sendable {
    @discardableResult
    public func save(folder: Folder) -> Folder {
        record("save(folder:)")
        return stubs["save(folder:)"] as? Folder ?? folder
    }

    public func allFolders(includeDeleted: Bool) -> [Folder] {
        record("allFolders(includeDeleted:)")
        return stubs["allFolders(includeDeleted:)"] as? [Folder] ?? []
    }

    public func findFolder(uuid: String) -> Folder? {
        record("findFolder(uuid:)")
        return stubs["findFolder(uuid:)"] as? Folder
    }

    public func topPodcastsUuidInFolder(folder: Folder) -> [String] {
        record("topPodcastsUuidInFolder(folder:)")
        return stubs["topPodcastsUuidInFolder(folder:)"] as? [String] ?? []
    }

    public func allPodcastsInFolder(folder: Folder) -> [Podcast] {
        record("allPodcastsInFolder(folder:)")
        return stubs["allPodcastsInFolder(folder:)"] as? [Podcast] ?? []
    }

    public func countOfPodcastsInFolder(folder: Folder) -> Int {
        record("countOfPodcastsInFolder(folder:)")
        return stubs["countOfPodcastsInFolder(folder:)"] as? Int ?? 0
    }

    public func countOfPodcastsInRootFolder() -> Int {
        record("countOfPodcastsInRootFolder()")
        return stubs["countOfPodcastsInRootFolder()"] as? Int ?? 0
    }

    public func saveSortOrders(folders: [Folder], syncModified: Int64) {
        record("saveSortOrders(folders:syncModified:)")
    }

    public func updateFolderColor(folderUuid: String, color: Int32, syncModified: Int64) {
        record("updateFolderColor(folderUuid:color:syncModified:)")
    }

    public func updateFolderSyncModified(folderUuid: String, syncModified: Int64) {
        record("updateFolderSyncModified(folderUuid:syncModified:)")
    }

    public func delete(folderUuid: String, markAsDeleted: Bool) {
        record("delete(folderUuid:markAsDeleted:)")
    }

    public func bulkSetSyncModified(_ syncModified: Int64, onFolders folderUuids: [String]) {
        record("bulkSetSyncModified(_:onFolders:)")
    }

    public func allUnsyncedFolders() -> [Folder] {
        record("allUnsyncedFolders()")
        return stubs["allUnsyncedFolders()"] as? [Folder] ?? []
    }

    public func markAllFoldersSynced() {
        record("markAllFoldersSynced()")
    }

    public func clearAllFolderInformation() {
        record("clearAllFolderInformation()")
    }

    public func deleteAllFoldersAndMarkSync() {
        record("deleteAllFoldersAndMarkSync()")
    }

    public func snapshot(podcastsAndFolders: [String: String]) {
        record("snapshot(podcastsAndFolders:)")
    }

    public func foldersHistoryEntries() -> [FolderHistoryManager.PodcastFoldersHistoryEntry] {
        record("foldersHistoryEntries()")
        return stubs["foldersHistoryEntries()"] as? [FolderHistoryManager.PodcastFoldersHistoryEntry] ?? []
    }

    public func folderHistory(entry: Date) -> [String: String] {
        record("folderHistory(entry:)")
        return stubs["folderHistory(entry:)"] as? [String: String] ?? [:]
    }
}
