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

    /// True while a load for this episode is outstanding (between
    /// beginLoading and its commit/discard/invalidate).
    func isLoading(episodeUuid: String) -> Bool {
        loadTokens[episodeUuid] != nil
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

/// Starts one load chain for an episode's Moment pins unless one is already
/// in flight — update() fires in bursts, and every spare chain would re-fetch
/// each comment page before losing the commit race. Returns whether a load
/// was started.
@MainActor
@discardableResult
func loadMomentPinsIfIdle(
    cache: EpisodeMomentPinsCache,
    episodeUuid: String,
    duration: TimeInterval,
    fetchPage: @escaping @MainActor (_ limit: Int, _ offset: Int) async -> SocialCommentPage?,
    assign: @escaping @MainActor ([EpisodeMomentPin]) -> Void
) -> Bool {
    guard !cache.isLoading(episodeUuid: episodeUuid) else { return false }
    let loadToken = cache.beginLoading(episodeUuid: episodeUuid)
    Task { @MainActor in
        let comments = await fetchAllEpisodeComments(fetchPage: fetchPage)
        guard let comments else {
            cache.discard(loadToken)
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
        guard cache.commit(pins, for: loadToken) else { return }
        assign(pins)
    }
    return true
}

/// Moment pins on the player scrubber (Slice 6, ADR-0010): timestamped
/// top-level comments render as dots on the TimeSlider; tapping one opens the
/// episode's comment tree focused on that comment's subtree. The player is the
/// second lens over the same tree the episode page shows.
extension NowPlayingPlayerItemViewController {
    private static let momentPinsCache = EpisodeMomentPinsCache()

    /// The live player item, so a Moments mutation in the comments sheet can
    /// refresh the scrubber immediately instead of leaving a stale pin until
    /// the next unrelated update() event.
    private static weak var momentPinsController: NowPlayingPlayerItemViewController?

    static func invalidateMomentPins(for episodeUuid: String) {
        // invalidate() also clears the in-flight marker, so this refresh is
        // never suppressed by the load it just made stale.
        momentPinsCache.invalidate(episodeUuid: episodeUuid)
        guard let episode = PlaybackManager.shared.currentEpisode(), episode.uuid == episodeUuid else { return }
        momentPinsController?.refreshMomentPins(for: episode)
    }

    /// Loads (once per episode) the timestamped seeds and pins them.
    func refreshMomentPins(for episode: BaseEpisode) {
        Self.momentPinsController = self
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
        loadMomentPinsIfIdle(
            cache: Self.momentPinsCache,
            episodeUuid: uuid,
            duration: episode.duration,
            fetchPage: { limit, offset in
                await ApiServerHandler.shared.fetchEpisodeComments(
                    episodeUuid: uuid,
                    limit: limit,
                    offset: offset
                )
            },
            assign: { [weak self] pins in
                self?.timeSlider.momentPins = pins.map { ($0.id, $0.fraction) }
            }
        )
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
