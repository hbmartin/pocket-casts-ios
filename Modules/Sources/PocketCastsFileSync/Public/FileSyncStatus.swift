import Foundation

/// Snapshot of file-sync state for the Settings → Sync inspector.
public struct FileSyncStatus: Sendable, Equatable {
    public struct Device: Sendable, Equatable, Identifiable {
        public let deviceID: String
        public let name: String
        public let model: String
        public let appVersion: String
        public let lastSeen: Date?
        public let isThisDevice: Bool

        public var id: String { deviceID }

        public var isStale: Bool {
            guard let lastSeen else { return false }
            return Date().timeIntervalSince(lastSeen) > FileSyncFormat.deviceStaleAfter
        }

        public init(deviceID: String, name: String, model: String, appVersion: String,
                    lastSeen: Date?, isThisDevice: Bool) {
            self.deviceID = deviceID
            self.name = name
            self.model = model
            self.appVersion = appVersion
            self.lastSeen = lastSeen
            self.isThisDevice = isThisDevice
        }
    }

    public var isEnabled: Bool
    public var folderKind: SyncFolderKind?
    public var pendingOpCount: Int
    public var lastScanDate: Date?
    public var lastError: String?
    public var devices: [Device]

    public init(isEnabled: Bool = false, folderKind: SyncFolderKind? = nil,
                pendingOpCount: Int = 0, lastScanDate: Date? = nil,
                lastError: String? = nil, devices: [Device] = []) {
        self.isEnabled = isEnabled
        self.folderKind = folderKind
        self.pendingOpCount = pendingOpCount
        self.lastScanDate = lastScanDate
        self.lastError = lastError
        self.devices = devices
    }
}
