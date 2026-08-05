import Foundation

/// Constants describing the on-disk layout of the sync folder.
///
/// Layout (all paths relative to the sync root the user picked or the
/// iCloud container's Documents directory):
///
///     Uploads/       user audio files (first-level subfolder = group)
///
/// Folders written before the sync engine was removed may also contain
/// `Sync/` and `Podcast Mirrors/` directories; both are obsolete debris and
/// safe for users to delete manually.
public enum FileSyncFormat {
    public static let uploadsDirectory = "Uploads"
}
