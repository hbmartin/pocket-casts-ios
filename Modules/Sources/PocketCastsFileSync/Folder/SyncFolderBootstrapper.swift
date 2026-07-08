import Foundation
import SwiftProtobuf

/// Prepares a sync folder for use: creates the fixed layout, writes or
/// verifies the format version marker, and registers this device's
/// directory.
public enum SyncFolderBootstrapper {
    /// Ensures the folder is usable by this app version and that this
    /// device's directory exists. Throws `SyncFolderError.formatTooNew`
    /// when another device has upgraded the folder beyond what this build
    /// understands.
    public static func prepare(folder: some SyncFolder, deviceID: String) async throws {
        // Version marker: first writer stamps it; later readers verify.
        let versionPath = "\(FileSyncFormat.syncDirectory)/\(FileSyncFormat.versionFileName)"
        let existingVersion: Filesync_FormatVersion? = try? await folder.coordinatedRead(versionPath) { url in
            guard let data = try? Data(contentsOf: url) else { return nil }
            return try? Filesync_FormatVersion(serializedBytes: data)
        }

        if let existingVersion {
            guard existingVersion.version <= FileSyncFormat.version else {
                throw SyncFolderError.formatTooNew(
                    found: existingVersion.version, supported: FileSyncFormat.version)
            }
        } else {
            var version = Filesync_FormatVersion()
            version.version = FileSyncFormat.version
            try await folder.coordinatedWrite(versionPath, data: version.serializedData())
        }

        // Fixed layout. Directory creation is idempotent; the uploads and
        // mirrors directories are what users see in the Files app, so they
        // must exist from day one.
        for directory in [FileSyncFormat.syncDirectory,
                          FileSyncFormat.uploadsDirectory,
                          FileSyncFormat.podcastMirrorsDirectory,
                          FileSyncFormat.deviceDirectory(deviceID: deviceID)] {
            try await folder.createDirectory(directory)
        }
    }

    /// Writes this device's presence/freshness marker.
    public static func writeDeviceInfo(
        folder: some SyncFolder, deviceID: String, name: String, model: String,
        appVersion: String, headSeq: UInt64, nowMs: Int64
    ) async throws {
        var info = Filesync_DeviceInfo()
        info.deviceID = deviceID
        info.name = name
        info.model = model
        info.appVersion = appVersion
        info.lastSeenMs = nowMs
        info.headSeq = headSeq
        info.formatVersion = FileSyncFormat.version
        let path = "\(FileSyncFormat.deviceDirectory(deviceID: deviceID))/\(FileSyncFormat.deviceInfoFileName)"
        try await folder.coordinatedWrite(path, data: info.serializedData())
    }

    /// Lists peer device directories (excluding this device).
    public static func peerDeviceIDs(folder: some SyncFolder, ownDeviceID: String) async throws -> [String] {
        let entries = try await folder.list(FileSyncFormat.devicesDirectory)
        return entries
            .filter { $0.isDirectory }
            .map(\.fileName)
            .filter { $0 != ownDeviceID && !$0.hasPrefix(".") }
            .sorted()
    }
}
