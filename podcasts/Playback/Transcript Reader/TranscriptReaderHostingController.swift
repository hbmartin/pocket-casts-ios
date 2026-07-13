import PocketCastsDataModel
import SwiftUI
import UIKit

/// Presents `TranscriptReaderView` full screen and routes its share actions
/// through UIKit (activity sheet for quotes, `SharingModal` for clips).
final class TranscriptReaderHostingController: ThemedHostingController<TranscriptReaderView> {

    private let router: TranscriptReaderActionRouter

    init(transcript: TranscriptModel,
         playbackManager: TranscriptPlaybackManaging,
         isGeneratedTranscript: Bool,
         isLocalTranscript: Bool = false,
         source: AnalyticsSource) {
        let episode = playbackManager.episodeUUID.flatMap { DataManager.sharedManager.findEpisode(uuid: $0) }
        let router = TranscriptReaderActionRouter(episode: episode, source: source)
        self.router = router

        let viewModel = TranscriptReaderViewModel(
            transcript: transcript,
            playback: playbackManager,
            isGeneratedTranscript: isGeneratedTranscript,
            isLocalTranscript: isLocalTranscript,
            episodeTitle: episode?.title,
            episodeShareURLString: episode?.shareURL
        )

        let rootView = TranscriptReaderView(
            viewModel: viewModel,
            // The clip-share flow needs the parent podcast for artwork/colors
            // (SharingModal force-unwraps it), so gate the action on it.
            canShareClip: episode?.parentPodcast() != nil,
            onShareQuote: { router.shareQuote($0) },
            onShareClip: { router.shareClip(start: $0, end: $1) },
            onClose: { router.close() }
        )

        super.init(rootView: rootView)
        router.host = self
        modalPresentationStyle = .fullScreen
    }

    @MainActor dynamic required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

/// Bridges reader actions that need a `UIViewController` to present from.
/// Created before the hosting controller exists, then pointed back at it.
@MainActor
final class TranscriptReaderActionRouter {

    weak var host: UIViewController?
    private let episode: Episode?
    private let source: AnalyticsSource

    init(episode: Episode?, source: AnalyticsSource) {
        self.episode = episode
        self.source = source
    }

    func shareQuote(_ text: String) {
        guard let host else { return }
        let activityViewController = UIActivityViewController(activityItems: [text], applicationActivities: nil)
        if let popover = activityViewController.popoverPresentationController {
            popover.sourceView = host.view
            popover.sourceRect = CGRect(x: host.view.bounds.midX, y: host.view.bounds.midY, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }
        host.present(activityViewController, animated: true)
    }

    /// Reuses the existing clip-share flow, pre-seeded with the cue's window.
    /// `.clipShare` already carries a `ClipTime`, so no new share option is
    /// needed; the user can still tap Edit there to fine-tune the trim.
    func shareClip(start: TimeInterval, end: TimeInterval) {
        guard let host, let episode, episode.parentPodcast() != nil else { return }
        let clipTime = ClipTime(start: start, end: end)
        SharingModal.show(option: .clipShare(episode, clipTime, .large), from: source, in: host)
    }

    func close() {
        host?.dismiss(animated: true)
    }
}
