import Foundation

enum UserEpisodeArtwork {
    nonisolated static var directory: String {
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let directoryURL = documentsURL.appendingPathComponent("custom_images")
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        return directoryURL.path
    }

    nonisolated static func imagePath(forEpisodeUuid uuid: String) -> String {
        directory + "/" + uuid + ".jpg"
    }
}
