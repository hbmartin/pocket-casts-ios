import AVFoundation
import UIKit

class VideoPlayerView: UIView {
    var gravity = AVLayerVideoGravity.resizeAspect {
        didSet {
            playerLayer.videoGravity = gravity
        }
    }

    var player: AVPlayer? {
        didSet {
            playerLayer.player = player
        }
    }

    var videoSizeKnown: ((CGSize) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)

        listenForVideoSize()
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)

        listenForVideoSize()
    }

    // nonisolated(unsafe): cleanup-only reference for deinit, which may run off the main actor
    nonisolated(unsafe) private var observedLayer: AVPlayerLayer?

    private func listenForVideoSize() {
        let layer = playerLayer
        observedLayer = layer
        layer.addObserver(self, forKeyPath: "videoRect", options: .new, context: nil)
    }

    deinit {
        observedLayer?.removeObserver(self, forKeyPath: "videoRect")
    }

    override nonisolated func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
        Task { @MainActor [weak self] in
            guard let self, keyPath == "videoRect", self.playerLayer.videoRect.size != CGSize.zero else { return }

            if let videoSizeKnown = self.videoSizeKnown, self.player != nil {
                videoSizeKnown(self.playerLayer.videoRect.size)
            }
        }
    }

    var playerLayer: AVPlayerLayer {
        layer as! AVPlayerLayer
    }

    override class var layerClass: AnyClass {
        AVPlayerLayer.self
    }
}
