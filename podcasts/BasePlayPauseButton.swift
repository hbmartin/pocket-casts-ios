import UIKit

class BasePlayPauseButton: UIButton {
    private enum PlayState { case playing, paused, notSet }

    private var currentState = PlayState.notSet
    var iconView: PlayPauseIconView!

    var isPlaying = false {
        didSet {
            // check for a state we're already in
            if isPlaying, currentState == .playing { return }
            if !isPlaying, currentState == .paused { return }

            if currentState == .notSet {
                currentState = isPlaying ? .playing : .paused
                iconView.setShowingPause(isPlaying, animated: false)
            } else if isPlaying {
                animateToPlaying()
            } else {
                animateToPaused()
            }

            isAccessibilityElement = true
            accessibilityLabel = isPlaying ? L10n.pause : L10n.play
            accessibilityIdentifier = "play pause button"
        }
    }

    var playButtonColor: UIColor = .white {
        didSet {
            iconView.fillColor = playButtonColor
        }
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)

        iconView = PlayPauseIconView(frame: .zero)
        iconView.isUserInteractionEnabled = false
    }

    override func awakeFromNib() {
        super.awakeFromNib()

        place(icon: iconView)
    }

    func animationCenter() -> CGPoint {
        iconView.center
    }

    private func animateToPlaying() {
        currentState = .playing
        morph(toPause: true)
    }

    private func animateToPaused() {
        currentState = .paused
        morph(toPause: false)
    }

    func place(icon: UIView) {}

    private func morph(toPause: Bool) {
        // only run the animation if our app is foregrounded, otherwise just change the state
        let animated = UIApplication.shared.applicationState == .active
        iconView.setShowingPause(toPause, animated: animated)
    }
}

/// Draws a play triangle / pause bars icon and morphs smoothly between the two
/// states. Replaces the former Lottie `player_play_button` animation with a
/// single `CAShapeLayer` whose path is interpolated by `CABasicAnimation`.
///
/// Both the play and pause states are described as two four-point subpaths so
/// the path structures match and Core Animation can interpolate between them.
/// In the play state the right subpath collapses to the triangle's tip; morphing
/// to pause "opens" it into the right bar.
class PlayPauseIconView: UIView {
    private static let morphDuration: CFTimeInterval = 0.3
    private static let morphKey = "playPauseMorph"
    private static let scaleKey = "playPauseScale"

    private let shapeLayer = CAShapeLayer()

    /// `true` shows the pause (two bars) icon, used while audio is playing.
    private var showingPause = false

    var fillColor: UIColor = .white {
        didSet {
            shapeLayer.fillColor = fillColor.cgColor
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        isUserInteractionEnabled = false
        shapeLayer.fillColor = fillColor.cgColor
        layer.addSublayer(shapeLayer)
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        // Keep the path in sync with the current size without animating the resize.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        shapeLayer.frame = bounds
        shapeLayer.path = currentPath()
        CATransaction.commit()
    }

    func setShowingPause(_ pause: Bool, animated: Bool) {
        showingPause = pause

        // Bounds aren't known yet (e.g. set before the first layout); the path
        // will be drawn correctly in `layoutSubviews`.
        guard bounds.width > 0, bounds.height > 0 else { return }

        let target = currentPath()
        let fromPath = shapeLayer.presentation()?.path ?? shapeLayer.path

        // Set the model value without an implicit animation; an explicit morph
        // (below) drives the visible transition when animating.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        shapeLayer.path = target
        CATransaction.commit()

        guard animated else { return }
        guard !UIAccessibility.isReduceMotionEnabled else { return }

        if let fromPath {
            let morph = CABasicAnimation(keyPath: "path")
            morph.duration = Self.morphDuration
            morph.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            morph.fromValue = fromPath
            morph.toValue = target
            shapeLayer.add(morph, forKey: Self.morphKey)
        }

        let scale = CAKeyframeAnimation(keyPath: "transform.scale")
        scale.values = [0.86, 1.0]
        scale.keyTimes = [0, 1]
        scale.duration = Self.morphDuration
        scale.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer.add(scale, forKey: Self.scaleKey)
    }

    private func currentPath() -> CGPath {
        showingPause ? pausePath() : playPath()
    }

    private func quads(_ first: [CGPoint], _ second: [CGPoint]) -> CGPath {
        let path = CGMutablePath()
        for quad in [first, second] {
            path.move(to: quad[0])
            path.addLine(to: quad[1])
            path.addLine(to: quad[2])
            path.addLine(to: quad[3])
            path.closeSubpath()
        }
        return path
    }

    private func playPath() -> CGPath {
        let w = bounds.width, h = bounds.height
        let top = h * 0.24, bottom = h * 0.76
        let apex = CGPoint(x: w * 0.74, y: h * 0.5)
        // Split the triangle vertically; the top/bottom edges meet the split line.
        let splitX = w * 0.52
        let topAtSplit = CGPoint(x: splitX, y: h * 0.37)
        let bottomAtSplit = CGPoint(x: splitX, y: h * 0.63)

        let left = [
            CGPoint(x: w * 0.30, y: top),
            topAtSplit,
            bottomAtSplit,
            CGPoint(x: w * 0.30, y: bottom)
        ]
        // Right half is a triangle expressed as a degenerate quad (apex twice).
        let right = [topAtSplit, apex, apex, bottomAtSplit]
        return quads(left, right)
    }

    private func pausePath() -> CGPath {
        let w = bounds.width, h = bounds.height
        let top = h * 0.24, bottom = h * 0.76
        let barWidth = w * 0.14
        let leftCenter = w * 0.40, rightCenter = w * 0.60

        let left = [
            CGPoint(x: leftCenter - barWidth / 2, y: top),
            CGPoint(x: leftCenter + barWidth / 2, y: top),
            CGPoint(x: leftCenter + barWidth / 2, y: bottom),
            CGPoint(x: leftCenter - barWidth / 2, y: bottom)
        ]
        let right = [
            CGPoint(x: rightCenter - barWidth / 2, y: top),
            CGPoint(x: rightCenter + barWidth / 2, y: top),
            CGPoint(x: rightCenter + barWidth / 2, y: bottom),
            CGPoint(x: rightCenter - barWidth / 2, y: bottom)
        ]
        return quads(left, right)
    }
}
