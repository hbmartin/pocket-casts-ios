import Foundation
import PocketCastsDataModel
import PocketCastsReadAloud
import PocketCastsUtils

/// Turns finished narration audio into a playable episode. A seam so the queue
/// can be tested without `DownloadManager`, `PlaybackManager` or a real episode
/// store.
nonisolated protocol NarrationMaterializing: Sendable {
    /// - Returns: the uuid of the created episode.
    func materialize(
        document: ReadAloudDocumentRecord,
        narration: NarrationRecord,
        audioURL: URL,
        duration: TimeInterval,
        sizeInBytes: Int64
    ) async throws -> String
}

/// Production materialization: move the rendered file into the download cache,
/// then create the `UserEpisode` around it.
nonisolated struct NarrationMaterializer: NarrationMaterializing {
    /// Files-screen section for narrated documents. A stored literal, not an
    /// `L10n` lookup: `groupName` is persisted per row and every other value it
    /// takes is a literal folder name, so localizing it would fork the section
    /// in two the first time someone changes their language.
    static let groupName = "Read Aloud"

    /// Tile colour for generated episodes. Fixed rather than user-chosen — the
    /// import sheet has enough decisions in it, and the episode can be recoloured
    /// afterwards like any other file.
    private static let imageColor = 3

    func materialize(
        document: ReadAloudDocumentRecord,
        narration: NarrationRecord,
        audioURL: URL,
        duration: TimeInterval,
        sizeInBytes: Int64
    ) async throws -> String {
        let episodeUuid = UUID().uuidString.lowercased()

        // `addUserEpisode` expects the audio to already sit in the download
        // cache under `<uuid>.<ext>`; `addLocalFile` is what puts it there.
        guard let cachedURL = try? DownloadManager.shared.addLocalFile(url: audioURL, uuid: episodeUuid) else {
            throw ReadAloudError.assemblyFailed
        }

        do {
            _ = try UserEpisodeManager.addUserEpisode(
                uuid: episodeUuid,
                title: document.title,
                localFileUrl: cachedURL,
                artwork: nil,
                color: Self.imageColor,
                fileSize: Int(sizeInBytes),
                duration: duration,
                // ADR-0019: never enters the Uploads folder.
                storage: .deviceLocal(groupName: Self.groupName)
            )
        } catch {
            try? FileManager.default.removeItem(at: cachedURL)
            throw ReadAloudError.assemblyFailed
        }

        return episodeUuid
    }
}
