import Foundation

/// Snapshot of uploads-folder state for the Settings inspector.
public struct FileSyncStatus: Sendable, Equatable {
    public var isEnabled: Bool
    public var folderKind: SyncFolderKind?
    public var lastScanDate: Date?
    public var lastError: String?

    public init(isEnabled: Bool = false, folderKind: SyncFolderKind? = nil,
                lastScanDate: Date? = nil, lastError: String? = nil) {
        self.isEnabled = isEnabled
        self.folderKind = folderKind
        self.lastScanDate = lastScanDate
        self.lastError = lastError
    }
}
