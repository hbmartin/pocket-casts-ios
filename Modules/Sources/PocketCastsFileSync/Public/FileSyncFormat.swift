import Foundation

/// Constants describing the on-disk layout of the sync folder.
///
/// Layout (all paths relative to the sync root the user picked or the
/// iCloud container's Documents directory):
///
///     Sync/version.pb                              FormatVersion
///     Sync/devices/<deviceId>/device.pb            DeviceInfo
///     Sync/devices/<deviceId>/log-00000001.pcsync  length-delimited OpEnvelope
///     Sync/devices/<deviceId>/snapshot-<seq>.pcsnap Snapshot
///     Uploads/                                     user audio files
///     Podcast Mirrors/                             opt-in download mirrors
///
/// Each device only ever writes inside its own `devices/<deviceId>/`
/// directory, which is what makes the format safe on providers with no
/// merge support (Dropbox, Drive): concurrent writers never touch the same
/// file, so conflicted copies are impossible by construction.
public enum FileSyncFormat {
    /// Bump only for incompatible layout changes; readers refuse folders
    /// written by a newer version.
    public static let version: Int32 = 1

    public static let syncDirectory = "Sync"
    public static let devicesDirectory = "Sync/devices"
    public static let uploadsDirectory = "Uploads"
    public static let podcastMirrorsDirectory = "Podcast Mirrors"
    public static let versionFileName = "version.pb"
    public static let deviceInfoFileName = "device.pb"

    public static let logFileExtension = "pcsync"
    public static let snapshotFileExtension = "pcsnap"

    /// Rotate the active log once it holds this many ops…
    public static let maxOpsPerLogFile = 2000
    /// …or grows past this many bytes, whichever comes first.
    public static let maxLogFileBytes = 512 * 1024

    /// Write a fresh snapshot once un-snapshotted logs exceed this size.
    public static let snapshotAfterLogBytes = 2 * 1024 * 1024
    /// Or when the newest snapshot is older than this.
    public static let snapshotMaxAge: TimeInterval = 7 * 24 * 60 * 60

    /// Own logs fully covered by a snapshot are deleted after this grace
    /// period, giving other devices' cursors time to catch up.
    public static let logCompactionGracePeriod: TimeInterval = 7 * 24 * 60 * 60

    /// Tombstones older than this are dropped from snapshots. A device
    /// offline longer than this window can resurrect deletions when it
    /// rejoins — the inspector warns well before that.
    public static let tombstoneRetention: TimeInterval = 90 * 24 * 60 * 60

    /// The inspector flags devices not seen for this long as stale.
    public static let deviceStaleAfter: TimeInterval = 60 * 24 * 60 * 60

    public static func logFileName(index: UInt64) -> String {
        String(format: "log-%08llu.%@", index, logFileExtension)
    }

    public static func snapshotFileName(asOfSeq: UInt64) -> String {
        String(format: "snapshot-%llu.%@", asOfSeq, snapshotFileExtension)
    }

    public static func deviceDirectory(deviceID: String) -> String {
        "\(devicesDirectory)/\(deviceID)"
    }
}
