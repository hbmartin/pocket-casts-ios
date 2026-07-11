import Foundation
import PocketCastsDataModel
import PocketCastsFileSync
import PocketCastsUtils
import UIKit

nonisolated struct UserEpisodeManager {
    #if !os(tvOS)
        static func addUserEpisode(
            uuid: String,
            title: String,
            localFileUrl: URL,
            artwork: UIImage?,
            color: Int,
            fileSize: Int,
            duration: TimeInterval
        ) throws -> UserEpisode {
            var episode = UserEpisode()
            episode.title = title
            episode.addedDate = Date()
            episode.publishedDate = Date()
            episode.fileType = FileTypeUtil.typeForFileExtension(forExtension: localFileUrl.absoluteString)
            episode.duration = duration
            episode.uuid = uuid
            episode.sizeInBytes = Int64(fileSize)
            episode.episodeStatus = DownloadStatus.downloaded.rawValue

            if let artwork {
                episode.imageColor = 0
                let filePath = episode.urlForImage()
                try artwork.jpegData(compressionQuality: 1)?.write(to: filePath)
                episode.hasCustomImage = true
            } else {
                episode.imageColor = Int32(color)
                episode.hasCustomImage = false
            }

            episode = DataManager.sharedManager.save(episode: episode)

            if FeatureFlag.fileSync.enabled {
                let episodeUuid = episode.uuid
                Task {
                    do {
                        let relativePath = try await FileSyncManager.shared.importUpload(from: localFileUrl)
                        if var saved = DataManager.sharedManager.findUserEpisode(uuid: episodeUuid) {
                            saved.folderRelativePath = relativePath
                            saved.groupName = ""
                            saved.identity = .provisional
                            DataManager.sharedManager.save(episode: saved)
                            try await FileSyncManager.shared.materializeUpload(episodeUuid: episodeUuid)
                        }
                    } catch {
                        FileLog.shared.addMessage("FileSync: import into sync folder failed: \(error)")
                    }
                }
            }

            if Settings.userEpisodeAutoAddToUpNext() {
                PlaybackManager.onMainSync { $0.addToUpNext(episode: episode, userInitiated: false) }
            }

            return episode
        }
    #endif

    static func renameUserEpisode(title: String, userEpisode: UserEpisode) {
        var userEpisode = userEpisode
        userEpisode.title = title
        DataManager.sharedManager.save(episode: userEpisode)
    }

    // MARK: - Delete

    static func deleteFromDevice(userEpisode: UserEpisode, removeFromPlaybackQueue: Bool = true) {
        DownloadManager.shared.removeFromQueue(
            episodeUuid: userEpisode.uuid,
            fireNotification: false,
            userInitiated: true
        )
        if removeFromPlaybackQueue {
            PlaybackManager.onMainSync {
                $0.removeIfPlayingOrQueued(episode: userEpisode, fireNotification: true)
            }
        }
        EpisodeManager.deleteDownloadedFiles(episode: userEpisode)

        if FeatureFlag.fileSync.enabled, userEpisode.folderRelativePath != nil {
            DataManager.sharedManager.saveEpisode(
                downloadStatus: .notDownloaded,
                downloadTaskId: nil,
                episode: userEpisode
            )
            NotificationCenter.postOnMainThread(
                notification: Constants.Notifications.episodeDownloadStatusChanged,
                object: userEpisode.uuid
            )
            return
        }

        DataManager.sharedManager.delete(userEpisodeUuid: userEpisode.uuid)
        NotificationCenter.postOnMainThread(
            notification: Constants.Notifications.userEpisodeDeleted,
            object: userEpisode.uuid
        )
    }

    static func deleteFromEverywhere(userEpisode: UserEpisode, removeFromPlaybackQueue: Bool = true) {
        guard FeatureFlag.fileSync.enabled, userEpisode.folderRelativePath != nil else {
            deleteFromDevice(userEpisode: userEpisode, removeFromPlaybackQueue: removeFromPlaybackQueue)
            return
        }

        if removeFromPlaybackQueue {
            PlaybackManager.onMainSync {
                $0.removeIfPlayingOrQueued(episode: userEpisode, fireNotification: true)
            }
        }

        Task {
            do {
                try await FileSyncManager.shared.deleteUpload(episodeUuid: userEpisode.uuid)
            } catch {
                FileLog.shared.addMessage("FileSync: delete upload failed: \(error)")
            }
        }
    }

    static func removeOrphanedUserEpisodes() {
        DataManager.sharedManager.removeOrphanedUserEpisodes()
    }

    // MARK: - Update User Episode

    static func updateUserEpisode(uuid: String, title: String, color: Int) {
        guard var episode = DataManager.sharedManager.findUserEpisode(uuid: uuid) else { return }

        var episodeSyncRequired = false
        if episode.title != title {
            episode.title = title
            episode.titleModified = TimeFormatter.currentUTCTimeInMillis()
            episodeSyncRequired = true
        }
        if episode.imageColor != Int32(color) || episode.imageColorModified > 0 {
            episode.imageColor = Int32(color)
            episode.imageColorModified = TimeFormatter.currentUTCTimeInMillis()
            episodeSyncRequired = true
        }

        DataManager.sharedManager.save(episode: episode)
        NotificationCenter.postOnMainThread(
            notification: Constants.Notifications.userEpisodeUpdated,
            object: episode.uuid
        )

        if episodeSyncRequired, FeatureFlag.fileSync.enabled, episode.folderRelativePath != nil {
            DataManager.sharedManager.journalFileSyncUpsert(
                entityType: .userEpisode,
                uuid: episode.uuid,
                changedFields: ["uploadIdentity"]
            )
        }
    }

    #if !os(tvOS)
        @MainActor static func updateUserEpisodeImage(
            uuid: String,
            artwork: UIImage?,
            completion: @escaping () -> Void
        ) throws {
            guard let episode = DataManager.sharedManager.findUserEpisode(uuid: uuid) else { return }

            let imageUrl = episode.urlForImage()
            if imageUrl.isFileURL, FileManager.default.fileExists(atPath: imageUrl.path) {
                try FileManager.default.removeItem(at: imageUrl)
            }

            ImageManager.sharedManager.removeUserEpisodeImage(episode: episode) {
                var episode = episode
                episode.imageUrl = nil
                if episode.imageColor != 0 {
                    episode.imageColor = 0
                    episode.imageColorModified = TimeFormatter.currentUTCTimeInMillis()
                }

                if let artwork,
                   let imageData = artwork.jpegData(compressionQuality: 1) {
                    do {
                        try imageData.write(to: episode.urlForImage())
                        episode.imageModified = TimeFormatter.currentUTCTimeInMillis()
                        episode.hasCustomImage = true
                    } catch {
                        FileLog.shared.addMessage("User episode artwork save failed: \(error)")
                    }
                } else {
                    episode.hasCustomImage = false
                }

                DataManager.sharedManager.save(episode: episode)
                NotificationCenter.postOnMainThread(
                    notification: Constants.Notifications.userEpisodeUpdated,
                    object: episode.uuid
                )
                completion()
            }
        }
    #endif

    #if !os(tvOS)
        @MainActor
        static func presentDeleteOptions(
            episode: UserEpisode,
            from presenter: UIViewController,
            dismissCallback: (() -> Void)? = nil,
            actionCallback: ((Bool, Bool) -> Void)? = nil
        ) {
            let alert = UIAlertController(
                title: L10n.deleteFile,
                message: L10n.deleteFileMessage,
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: L10n.cancel, style: .cancel) { _ in
                dismissCallback?()
            })

            if FeatureFlag.fileSync.enabled, episode.folderRelativePath != nil {
                if episode.downloaded(pathFinder: DownloadManager.shared) {
                    alert.addAction(UIAlertAction(title: L10n.fileSyncRemoveDownload, style: .default) { _ in
                        Task {
                            await FileSyncManager.shared.evictUpload(episodeUuid: episode.uuid)
                            await MainActor.run { actionCallback?(true, false) }
                        }
                    })
                }
                alert.addAction(UIAlertAction(title: L10n.fileSyncDeleteEverywhere, style: .destructive) { _ in
                    deleteFromEverywhere(userEpisode: episode)
                    actionCallback?(true, true)
                })
            } else {
                alert.addAction(UIAlertAction(title: L10n.deleteFromDevice, style: .destructive) { _ in
                    deleteFromDevice(userEpisode: episode)
                    actionCallback?(true, false)
                })
            }

            presenter.present(alert, animated: true)
        }
    #endif
}
