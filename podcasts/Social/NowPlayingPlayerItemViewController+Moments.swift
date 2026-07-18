import PocketCastsDataModel
import PocketCastsServer
import PocketCastsUtils
import UIKit

/// Moment pins on the player scrubber (Slice 6, ADR-0010): timestamped
/// top-level comments render as dots on the TimeSlider; tapping one opens the
/// episode's comment tree focused on that comment's subtree. The player is the
/// second lens over the same tree the episode page shows.
extension NowPlayingPlayerItemViewController {
    private static var momentsEpisodeUuid: String?
    private static var momentPinsCache: [(id: Int64, fraction: Double, seconds: Int)] = []

    /// Loads (once per episode) the timestamped seeds and pins them.
    func refreshMomentPins(for episode: BaseEpisode) {
        guard FeatureFlag.socialProfiles.enabled, episode.duration > 0 else {
            timeSlider.momentPins = []
            return
        }
        if Self.momentsEpisodeUuid == episode.uuid {
            timeSlider.momentPins = Self.momentPinsCache.map { ($0.id, $0.fraction) }
            return
        }
        Self.momentsEpisodeUuid = episode.uuid
        Self.momentPinsCache = []
        timeSlider.momentPins = []

        let uuid = episode.uuid
        let duration = episode.duration
        Task { @MainActor [weak self] in
            guard let page = await ApiServerHandler.shared.fetchEpisodeComments(episodeUuid: uuid, limit: 50) else { return }
            let pins = page.comments.compactMap { comment -> (Int64, Double, Int)? in
                guard !comment.removed, let seconds = comment.timestampSeconds, seconds >= 0,
                      TimeInterval(seconds) <= duration else { return nil }
                return (comment.id, TimeInterval(seconds) / duration, seconds)
            }
            Self.momentPinsCache = pins
            guard let self, Self.momentsEpisodeUuid == uuid else { return }
            self.timeSlider.momentPins = pins.map { ($0.0, $0.1) }
        }
    }

    /// TimeSliderDelegate (optional member): open the tree at this Moment.
    func sliderDidTapMoment(id: Int64) {
        guard let episode = PlaybackManager.shared.currentEpisode() else { return }
        let duration = episode.duration
        let canSeed = duration > 0 && episode.playedUpTo >= duration * 0.25
        let viewModel = EpisodeCommentsViewModel(episodeUuid: episode.uuid,
                                                 podcastUuid: episode.parentIdentifier(),
                                                 episodeTitle: episode.displayableTitle(),
                                                 podcastTitle: (episode as? Episode)?.parentPodcast()?.title ?? "",
                                                 canSeed: canSeed,
                                                 focusCommentId: id)
        let hosting = ThemedHostingController(rootView: EpisodeCommentsView(viewModel: viewModel))
        present(UINavigationController(rootViewController: hosting), animated: true)
    }
}
