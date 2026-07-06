import Foundation
import PocketCastsDataModel
import PocketCastsServer
import PocketCastsUtils

/// Bridges the nonisolated `ServerPlaybackDelegate` surface — called synchronously
/// from server refresh/sync operations on background queues — onto the `@MainActor`
/// `PlaybackManager` (Phase 5, docs/Phase5-PlaybackModernization.md D2).
///
/// Every call executes synchronously on the main actor so the server's
/// read-after-write sequences (e.g. `RefreshOperation`'s auto-add-to-Up-Next loop,
/// which re-reads `upNextQueueCount()` after each `addToUpNext`) keep their exact
/// semantics. Blocking the operation queue on main is safe here because the main
/// thread never synchronously waits on those operation queues.
nonisolated final class PlaybackServerAdapter: ServerPlaybackDelegate, Sendable {
    private func onMain<T>(_ body: @MainActor (PlaybackManager) -> T) -> T {
        PlaybackManager.onMainSync(body)
    }

    func playing() -> Bool {
        onMain { $0.playing() }
    }

    func inUpNext(episode: BaseEpisode?) -> Bool {
        let boxed = PocketCastsUtils.UncheckedSendable(episode)
        return onMain { $0.inUpNext(episode: boxed.value) }
    }

    func addToUpNext(episode: BaseEpisode, ignoringQueueLimit: Bool, toTop: Bool) {
        let boxed = PocketCastsUtils.UncheckedSendable(episode)
        onMain { $0.addToUpNext(episode: boxed.value, ignoringQueueLimit: ignoringQueueLimit, toTop: toTop) }
    }

    func removeLastEpisodeFromUpNext() {
        onMain { $0.removeLastEpisodeFromUpNext() }
    }

    func currentEpisode() -> BaseEpisode? {
        onMain { $0.currentEpisode() }
    }

    func isNowPlayingEpisode(episodeUuid: String?) -> Bool {
        onMain { $0.isNowPlayingEpisode(episodeUuid: episodeUuid) }
    }

    func isActivelyPlaying(episodeUuid: String?) -> Bool {
        onMain { $0.isActivelyPlaying(episodeUuid: episodeUuid) }
    }

    func queuePersistLocalCopyAsReplace() {
        onMain { $0.queuePersistLocalCopyAsReplace() }
    }

    func queueRefreshList(checkForAutoDownload: Bool) {
        onMain { $0.queueRefreshList(checkForAutoDownload: checkForAutoDownload) }
    }

    func allEpisodesInQueue(includeNowPlaying: Bool) -> [BaseEpisode] {
        onMain { $0.allEpisodesInQueue(includeNowPlaying: includeNowPlaying) }
    }

    func playingEpisodeChangedExternally() {
        onMain { $0.playingEpisodeChangedExternally() }
    }

    func upNextQueueChanged() {
        onMain { $0.upNextQueueChanged() }
    }

    func upNextQueueCount() -> Int {
        onMain { $0.upNextQueueCount() }
    }

    func seekToFromSync(time: TimeInterval, syncChanges: Bool, startPlaybackAfterSeek: Bool) {
        onMain { $0.seekToFromSync(time: time, syncChanges: syncChanges, startPlaybackAfterSeek: startPlaybackAfterSeek) }
    }
}
