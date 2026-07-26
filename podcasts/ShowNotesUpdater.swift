import Foundation
import PocketCastsServer
import PocketCastsUtils

nonisolated class ShowNotesUpdater {
    class func updateShowNotesInBackground(podcastUuid: String, episodeUuid: String) {
        Task {
            // Load the show notes and any available chapters
            _ = try? await ShowInfoCoordinator.shared.loadChapters(podcastUuid: podcastUuid, episodeUuid: episodeUuid)

            let transcriptManager = TranscriptManager(episodeUUID: episodeUuid, podcastUUID: podcastUuid)
            _ = try? await transcriptManager.loadTranscript()
        }
    }
}
