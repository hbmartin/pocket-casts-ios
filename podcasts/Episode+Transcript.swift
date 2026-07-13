import PocketCastsDataModel
import PocketCastsUtils

extension Episode {
    func checkTranscriptAvailability() {
        Task {
            if let metadata = try? await ShowInfoCoordinator.shared.loadTranscriptsMetadata(podcastUuid: parentIdentifier(), episodeUuid: uuid) {
                NotificationCenter.postOnMainThread(EpisodeTranscriptAvailabilityChanged(
                    episodeUuid: uuid,
                    isAvailable: !metadata.transcripts.isEmpty,
                    hasGeneratedTranscripts: metadata.hasGeneratedTranscripts
                ))
            }
        }
    }
}
