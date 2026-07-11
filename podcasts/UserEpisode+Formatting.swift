import Foundation
import PocketCastsDataModel
import PocketCastsUtils

nonisolated extension UserEpisode {
    // MARK: - Helpers

    func displayableInfo(includeSize: Bool = true) -> String {
        commonDisplayableInfo(includeSize: includeSize)
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
        Settings.userEpisodeRemoveFileAfterPlaying()
    }

    func urlForImage(size: Int = 280) -> URL {
        URL(fileURLWithPath: pathToLocalImage())
    }

    func pathToLocalImage() -> String {
        UserEpisodeArtwork.imagePath(forEpisodeUuid: uuid)
    }

    public func subTitle() -> String {
        L10n.customEpisode
    }
}
