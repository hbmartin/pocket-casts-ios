import PocketCastsDataModel
import PocketCastsServer
import PocketCastsUtils
import UIKit

struct EpisodeMomentPin: Equatable {
    let id: Int64
    let fraction: Double
    let seconds: Int
}

/// Keeps Moment pin results scoped to the episode and request that produced
/// them. A late page load can never overwrite the active episode's pins.
@MainActor
final class EpisodeMomentPinsCache {
    struct LoadToken: Equatable {
        fileprivate let id = UUID()
        fileprivate let episodeUuid: String
    }

    private var activeEpisodeUuid: String?
    private var pinsByEpisode: [String: [EpisodeMomentPin]] = [:]
    private var loadTokens: [String: LoadToken] = [:]

    func cachedPins(activating episodeUuid: String) -> [EpisodeMomentPin]? {
        activeEpisodeUuid = episodeUuid
        return pinsByEpisode[episodeUuid]
    }

    func beginLoading(episodeUuid: String) -> LoadToken {
        activeEpisodeUuid = episodeUuid
        let token = LoadToken(episodeUuid: episodeUuid)
        loadTokens[episodeUuid] = token
        return token
    }

    @discardableResult
    func commit(_ pins: [EpisodeMomentPin], for token: LoadToken) -> Bool {
        guard loadTokens[token.episodeUuid] == token else { return false }
        loadTokens[token.episodeUuid] = nil
        guard activeEpisodeUuid == token.episodeUuid else { return false }
        pinsByEpisode[token.episodeUuid] = pins
        return true
    }

    func invalidate(episodeUuid: String) {
        pinsByEpisode[episodeUuid] = nil
        loadTokens[episodeUuid] = nil
    }

    func discard(_ token: LoadToken) {
        guard loadTokens[token.episodeUuid] == token else { return }
        loadTokens[token.episodeUuid] = nil
    }

    func deactivate() {
        activeEpisodeUuid = nil
    }
}

/// Loads a complete, internally consistent comment listing. Returning nil for
/// an incomplete later page prevents a partial set of Moment pins being cached.
@MainActor
func fetchAllEpisodeComments(
    pageSize: Int = 50,
    fetchPage: (_ limit: Int, _ offset: Int) async -> SocialCommentPage?
) async -> [SocialComment]? {
    guard let firstPage = await fetchPage(pageSize, 0) else { return nil }
    var comments = firstPage.comments
    let expectedTotal = firstPage.total

    while comments.count < expectedTotal {
        guard let page = await fetchPage(pageSize, comments.count) else { return nil }
        guard !page.comments.isEmpty else { return nil }
        comments.append(contentsOf: page.comments)
    }
    return comments
}

/// Moment pins on the player scrubber (Slice 6, ADR-0010): timestamped
/// top-level comments render as dots on the TimeSlider; tapping one opens the
/// episode's comment tree focused on that comment's subtree. The player is the
/// second lens over the same tree the episode page shows.
extension NowPlayingPlayerItemViewController {
    private static let momentPinsCache = EpisodeMomentPinsCache()

    static func invalidateMomentPins(for episodeUuid: String) {
        momentPinsCache.invalidate(episodeUuid: episodeUuid)
    }

    /// Loads (once per episode) the timestamped seeds and pins them.
    func refreshMomentPins(for episode: BaseEpisode) {
        guard FeatureFlag.socialProfiles.enabled, episode.duration > 0 else {
            Self.momentPinsCache.deactivate()
            timeSlider.momentPins = []
            return
        }
        if let pins = Self.momentPinsCache.cachedPins(activating: episode.uuid) {
            timeSlider.momentPins = pins.map { ($0.id, $0.fraction) }
            return
        }
        timeSlider.momentPins = []

        let uuid = episode.uuid
        let duration = episode.duration
        let loadToken = Self.momentPinsCache.beginLoading(episodeUuid: uuid)
        Task { @MainActor [weak self] in
            let comments = await fetchAllEpisodeComments(fetchPage: { limit, offset in
                await ApiServerHandler.shared.fetchEpisodeComments(
                    episodeUuid: uuid,
                    limit: limit,
                    offset: offset
                )
            })
            guard let comments else {
                Self.momentPinsCache.discard(loadToken)
                return
            }
            let pins = comments.compactMap { comment -> EpisodeMomentPin? in
                guard !comment.removed, let seconds = comment.timestampSeconds, seconds >= 0,
                      TimeInterval(seconds) <= duration else { return nil }
                return EpisodeMomentPin(
                    id: comment.id,
                    fraction: TimeInterval(seconds) / duration,
                    seconds: seconds
                )
            }
            guard Self.momentPinsCache.commit(pins, for: loadToken), let self else { return }
            self.timeSlider.momentPins = pins.map { ($0.id, $0.fraction) }
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
