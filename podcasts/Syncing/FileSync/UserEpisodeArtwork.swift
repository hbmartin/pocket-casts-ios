import Foundation
import PocketCastsUtils

/// Owns the on-device custom artwork directory for user episodes.
///
/// Historically this path lived on `UploadManager.customImageDirectory`
/// (the server upload stack); in the local-first model artwork storage must
/// not depend on the retired upload machinery, so the path is defined here
/// and both stacks resolve to the same directory.
enum UserEpisodeArtwork {
    /// `Documents/custom_images` — the same directory UploadManager uses,
    /// so existing artwork keeps resolving.
    static var directory: String {
        let directory = NSHomeDirectory() + "/Documents/custom_images"
        try? FileManager.default.createDirectory(
            atPath: directory, withIntermediateDirectories: true)
        return directory
    }

    static func imagePath(forEpisodeUuid uuid: String) -> String {
        directory + "/" + uuid + ".jpg"
    }
}
