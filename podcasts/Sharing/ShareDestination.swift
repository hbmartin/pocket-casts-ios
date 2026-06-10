import SwiftUI
import PocketCastsDataModel
import Combine
import PocketCastsUtils
import EndOfYear

enum ShareDestination: Hashable {
    case copyLink
    case systemSheet(vc: UIViewController)

    var name: String {
        switch self {
        case .copyLink:
            L10n.shareCopyLink
        case .systemSheet:
            L10n.shareMoreActions
        }
    }

    var icon: Image {
        switch self {
        case .copyLink:
            Image("pocketcasts")
        case .systemSheet:
            Image(systemName: "ellipsis")
        }
    }

    enum ShareError: Error {
        case noMatchingItemIdentifier
        case loadFailed(Error?)
    }

    @MainActor
    func share(_ option: SharingModal.Option,
               style: ShareImageStyle,
               clipTime: ClipTime,
               clipUUID: String,
               progress: Binding<Float?>,
               presentFrom rect: CurrentValueSubject<CGRect, Never>,
               source: AnalyticsSource) async throws {
        switch self {
        case .copyLink:
            UIPasteboard.general.string = option.shareURL
            Toast.show(L10n.shareCopiedToClipboard)
            ShareDestination.logClipShared(option: option, style: style, clipUUID: clipUUID, source: source)
            ShareDestination.logPodcastShared(style: style, option: option, destination: self, source: source)
        case .systemSheet(let vc):
            let data = try await option.shareData(style: style, destination: self, clipUUID: clipUUID, progress: progress)
            let activityViewController = UIActivityViewController(activityItems: data, applicationActivities: nil)
            activityViewController.popoverPresentationController?.sourceView = vc.view
            activityViewController.popoverPresentationController?.sourceRect = rect.value
            let receiver = rect.sink { rect in
                activityViewController.popoverPresentationController?.sourceRect = rect
            }
            activityViewController.completionWithItemsHandler = { _, _, _, _ in
                receiver.cancel()
            }
            vc.presentedViewController?.present(activityViewController, animated: true, completion: {
                ShareDestination.logClipShared(option: option, style: style, clipUUID: clipUUID, source: source)
                ShareDestination.logPodcastShared(style: style, option: option, destination: self, source: source)
            })
        }
    }

    var analyticsDescription: String {
        switch self {
        case .copyLink:
            "url"
        case .systemSheet:
            "system_sheet"
        }
    }

    static func ==(lhs: ShareDestination, rhs: ShareDestination) -> Bool {
        lhs.name == rhs.name && lhs.icon == rhs.icon
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
    }
}

// MARK: Analytics

extension ShareDestination {
    private static func logClipShared(option: SharingModal.Option, style: ShareImageStyle, clipUUID: String, source: AnalyticsSource) {
        // This event is specifically for clip shares and not other shares. These are handled by `podcastShared`
        guard case let .clipShare(episode, clipTime, _) = option else {
            return
        }

        var properties: Dictionary<String, Any> = [:]

        properties["episode_uuid"] = episode.uuid
        properties["podcast_uuid"] = episode.parentPodcast()?.uuid ?? "unknown"
        properties["start"] = Int(clipTime.start)
        properties["end"] = Int(clipTime.end)
        properties["start_modified"] = clipTime.startChanged
        properties["end_modified"] = clipTime.endChanged
        properties["clip_uuid"] = clipUUID
        properties["type"] = shareType(style: style, option: option)
        properties["card_type"] = cardType(style: style)

        Analytics.track(.shareScreenClipShared, source: source, properties: properties)
    }

    private static func cardType(style: ShareImageStyle) -> String {
        switch style {
        case .large:
            "vertical"
        case .medium:
            "square"
        case .small:
            "horizontal"
        case .audio:
            "audio"
        }
    }

    private static func shareType(style: ShareImageStyle, option: SharingModal.Option) -> String {
        switch (style, option) {
        case (.audio, _):
            "audio"
        case (_, .clip), (_, .clipShare):
            "video"
        default:
            "link"
        }
    }

    private static func type(style: ShareImageStyle, option: SharingModal.Option, destination: Self) -> String {
        switch (style, option) {
        case (_, .podcast):
            return "podcast"
        case (_, .episode):
            return "episode"
        case (_, .currentPosition):
            return "current_time"
        case (_, .bookmark):
            return "bookmark_time"
        case (.audio, _):
            return "clip_audio"
        case (_, .clip), (_, .clipShare):
            if case .copyLink = destination {
                return "clip_link"
            } else {
                return "clip_video"
            }
        default:
            return "unknown"
        }
    }

    private static func logPodcastShared(style: ShareImageStyle, option: SharingModal.Option, destination: Self, source: AnalyticsSource) {
        let properties: [String: Any] = [
            "type": type(style: style, option: option, destination: destination),
            "action": destination.analyticsDescription,
            "card_type": cardType(style: style)
        ]

        Analytics.track(.podcastShared, source: source, properties: properties)
    }
}

extension ShareDestination {
    enum VideoExportError: Error {
        case failedToDownload
    }

    func export(info: ShareImageInfo, style: ShareImageStyle, episode: some BaseEpisode, startTime: CMTime, duration: CMTime, scale: CGFloat, progress: Progress, to url: URL) async throws -> URL {
        guard let playerItem = DownloadManager.shared.downloadParallelToStream(of: episode) else {
            throw VideoExportError.failedToDownload
        }

        func exportVideo() async throws -> URL {
            let size = CGSize(width: style.previewSize.width, height: style.previewSize.height)

            let parameters = await VideoExporter.Parameters(duration: CMTimeGetSeconds(duration), size: size, scale: scale, episodeAsset: playerItem.asset, audioStartTime: startTime, audioDuration: duration, fileType: .mp4)
            try await VideoExporter.export(view: AnimatedShareImageView(info: info, style: style, size: size), with: parameters, to: url, progress: progress)

            return url
        }

        switch style {
        case .audio:
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("audio_export-\(UUID().uuidString)", conformingTo: .m4a)
            try await AudioClipExporter.exportAudioClip(from: playerItem.asset, startTime: startTime, duration: duration, to: url, progress: progress)
            return url
        default:
            return try await exportVideo()
        }
    }
}
