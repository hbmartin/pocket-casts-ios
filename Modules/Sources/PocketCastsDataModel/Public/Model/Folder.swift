import Foundation
import GRDB
import GRDBMacros

@GRDBRecord(table: "Folder")
public struct Folder: Identifiable, Equatable, Sendable {
    public var uuid = ""
    public var name = ""
    public var color: Int32 = 0
    public var addedDate: Date?
    public var sortOrder: Int32 = 0
    public var sortType: Int32 = 0
    public var wasDeleted = false
    public var syncModified: Int64 = 0

    // transient not saved to database
    @GRDBIgnore
    public var cachedUnreadCount = 0

    /// Stable identity is the persisted `uuid` (was `ObjectIdentifier` when this was an NSObject).
    public var id: String { uuid }

    public init() {}

    func folderSort() -> FolderSort {
        FolderSort(rawValue: sortType) ?? .dateAddedNewestToOldest
    }
}

// This is the data side equivalent of LibrarySort
enum FolderSort: Int32 {
    case dateAddedNewestToOldest = 1, titleAtoZ = 2, episodeDateNewestToOldest = 5, custom = 6, recentlyPlayed = 7
}
