import Foundation

enum UserEpisodeArtwork {
    nonisolated static var directory: String {
        let directory = NSHomeDirectory() + "/Documents/custom_images"
        try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        return directory
    }

    nonisolated static func imagePath(forEpisodeUuid uuid: String) -> String {
        directory + "/" + uuid + ".jpg"
    }
}
