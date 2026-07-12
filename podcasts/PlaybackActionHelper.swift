import Foundation
import PocketCastsDataModel
import PocketCastsFileSync
import PocketCastsServer
import PocketCastsUtils

@MainActor
class PlaybackActionHelper {
    class func play(episode: BaseEpisode, playlist: AutoplayHelper.Playlist? = nil) {
        HapticsHelper.triggerPlayPauseHaptic()

        AutoplayHelper.shared.playedFrom(playlist: playlist)

        if !episode.downloaded(pathFinder: DownloadManager.shared) {
            NetworkUtils.shared.streamEpisodeRequested({
                performPlay(episode: episode)
            }, disallowed: nil)
        } else {
            performPlay(episode: episode)
        }
    }

    class func pause() {
        HapticsHelper.triggerPlayPauseHaptic()
        PlaybackManager.shared.pause()
    }

    class func playPause() {
        HapticsHelper.triggerPlayPauseHaptic()
        PlaybackManager.shared.playPause()
    }

    class func download(episodeUuid: String) {
        AnalyticsEpisodeHelper.shared.downloaded(episodeUUID: episodeUuid)

        if let userEpisode = DataManager.sharedManager.findUserEpisode(uuid: episodeUuid),
           userEpisode.folderRelativePath != nil {
            Task {
                do {
                    try await FileSyncManager.shared.materializeUpload(episodeUuid: episodeUuid)
                    NotificationCenter.postOnMainThread(EpisodeDownloadStatusChanged(uuid: episodeUuid))
                } catch {
                    FileLog.shared.addMessage("FileSync: materialize upload failed: \(error)")
                }
            }
            return
        }

        NetworkUtils.shared.downloadEpisodeRequested(autoDownloadStatus: .notSpecified, { later in
            if later {
                DownloadManager.shared.queueForLaterDownload(episodeUuid: episodeUuid, fireNotification: true, autoDownloadStatus: .notSpecified)
            } else {
                DownloadManager.shared.addToQueue(episodeUuid: episodeUuid)
            }
        }, disallowed: nil)
    }

    class func stopDownload(episodeUuid: String) {
        DownloadManager.shared.removeFromQueue(episodeUuid: episodeUuid, fireNotification: true, userInitiated: true)

        AnalyticsEpisodeHelper.shared.downloadCancelled(episodeUUID: episodeUuid)
    }

    class func overrideWaitingForWifi(episodeUuid: String, autoDownloadStatus: AutoDownloadStatus) {
        NetworkUtils.shared.downloadEpisodeRequested(autoDownloadStatus: autoDownloadStatus, { later in
            if later {
                DownloadManager.shared.queueForLaterDownload(episodeUuid: episodeUuid, fireNotification: true, autoDownloadStatus: autoDownloadStatus)
            } else {
                DownloadManager.shared.addToQueue(episodeUuid: episodeUuid)
            }
        }, disallowed: nil)
    }

    private class func performPlay(episode: BaseEpisode) {
        if PlaybackManager.shared.isNowPlayingEpisode(episodeUuid: episode.uuid) {
            PlaybackManager.shared.play()
        } else {
            if episode.archived, let episode = episode as? Episode {
                DataManager.sharedManager.saveEpisode(archived: false, episode: episode, updateSyncFlag: SyncManager.isUserLoggedIn())
            }

            if episode is Episode { // only record play stats for Episodes, not UserEpisodes
                AnalyticsHelper.playedEpisode()
            }

            PlaybackManager.shared.load(episode: episode, autoPlay: true, overrideUpNext: false)
        }
    }
}
