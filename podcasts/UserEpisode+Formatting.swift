import Foundation
import PocketCastsDataModel
import PocketCastsServer
import PocketCastsUtils

nonisolated extension UserEpisode {
    // MARK: - Helpers

    func displayableInfo(includeSize: Bool = true) -> String {
        if uploading() {
            let progress = UploadManager.shared.progressManager.progressForEpisode(uuid)?.percentageProgressAsString() ?? ""
            return L10n.podcastUploading(progress).trimmingCharacters(in: .whitespaces)
        } else if uploadWaitingForWifi() {
            return L10n.podcastWaitingUpload
        } else if uploadFailed() {
            return L10n.podcastFailedUpload
        } else {
            return commonDisplayableInfo(includeSize: includeSize)
        }
    }

    func displayableDuration(includeSize: Bool = true) -> String {
        var informationLabelStr = duration > 0 ? displayableTimeLeft() : L10n.unknownDuration

        if includeSize, sizeInBytes > 0 {
            if informationLabelStr.isEmpty {
                informationLabelStr = SizeFormatter.shared.noDecimalFormat(bytes: sizeInBytes)
            } else {
                informationLabelStr += " • \(SizeFormatter.shared.noDecimalFormat(bytes: sizeInBytes))"
            }
        }

        return informationLabelStr
    }

    public func shouldArchiveOnCompletion() -> Bool {
        Settings.userEpisodeRemoveFileAfterPlaying() || Settings.userEpisodeRemoveFromCloudAfterPlaying()
    }

    func urlForImage(size: Int = 280) -> URL {
        if imageColor > 0 {
            if FeatureFlag.fileSync.enabled {
                // Local-first: color placeholders render on device
                // (ImageManager.imageForUserEpisodeColor's fallback path)
                // instead of fetching a server-generated image; a local
                // file URL that doesn't exist routes callers there.
                return URL(fileURLWithPath: pathToLocalImage())
            }
            return ServerHelper.userEpisodeDefaultImageUrl(isDark: Theme.isDarkTheme(), color: Int(imageColor), size: size)
        }

        if let serverImageLocation = imageUrl, let serverURL = URL(string: serverImageLocation) {
            return serverURL
        }
            let path = pathToLocalImage()
            return URL(fileURLWithPath: path)
    }

    func pathToLocalImage() -> String {
        UserEpisodeArtwork.imagePath(forEpisodeUuid: uuid)
    }

    public func subTitle() -> String {
        uploadStatus == UploadStatus.missing.rawValue ? L10n.downloadErrorNotUploaded : L10n.customEpisode
    }
}
