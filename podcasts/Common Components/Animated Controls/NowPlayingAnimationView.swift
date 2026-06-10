import UIKit

/// A small three-bar "equalizer" indicator shown next to the episode that is
/// currently playing. Recreates the former Lottie `nowplaying` animation using
/// Core Animation: three rounded bars anchored at their bottom edge that bounce
/// up and down out of phase while `animating` is `true`.
class NowPlayingAnimationView: UIView {
    var animating = false {
        didSet {
            // check for a state we're already in
            if animating == oldValue { return }

            if animating {
                animateToOn()
            } else {
                animateToOff()
            }
        }
    }

    private static let barCount = 3
    private static let animationKey = "nowPlayingBounce"

    /// Resting height of each bar as a fraction of the view's height. Mirrors the
    /// differing bar heights in the original `nowplaying.json`.
    private static let barHeightFactors: [CGFloat] = [1.0, 0.6, 0.8]

    /// Per-bar durations (seconds) chosen so the bars bounce out of phase, as in
    /// the original ~0.67s looping animation.
    private static let barDurations: [CFTimeInterval] = [0.62, 0.5, 0.56]

    private static let minScale: CGFloat = 0.35

    private var bars: [CALayer] = []
    private var fillColor: UIColor = .white

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        setupBars()
        setupObservers()
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupBars()
        setupObservers()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func setupObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(reduceMotionStatusDidChange),
            name: UIAccessibility.reduceMotionStatusDidChangeNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationWillResignActive),
            name: UIApplication.willResignActiveNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
    }

    @objc private func reduceMotionStatusDidChange() {
        animating ? animateToOn() : animateToOff()
    }

    @objc private func applicationWillResignActive() {
        removeBarAnimations()
    }

    @objc private func applicationDidBecomeActive() {
        if window != nil, animating {
            animateToOn()
        }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()

        guard window != nil else {
            removeBarAnimations()
            return
        }

        if animating {
            animateToOn()
        }
    }

    private func setupBars() {
        isUserInteractionEnabled = false

        for _ in 0..<Self.barCount {
            let bar = CALayer()
            bar.backgroundColor = fillColor.cgColor
            // Anchor at the bottom centre so scaling grows the bar upwards.
            bar.anchorPoint = CGPoint(x: 0.5, y: 1.0)
            bar.isHidden = true
            layer.addSublayer(bar)
            bars.append(bar)
        }
    }

    func setFillColor(_ color: UIColor) {
        fillColor = color
        bars.forEach { $0.backgroundColor = color.cgColor }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layoutBars()
    }

    private func layoutBars() {
        guard bounds.width > 0, bounds.height > 0 else { return }

        let slot = bounds.width / CGFloat(Self.barCount)
        let barWidth = slot * 0.5
        let cornerRadius = barWidth / 2

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (index, bar) in bars.enumerated() {
            let centerX = slot * (CGFloat(index) + 0.5)
            let height = bounds.height * Self.barHeightFactors[index]
            bar.bounds = CGRect(x: 0, y: 0, width: barWidth, height: height)
            bar.position = CGPoint(x: centerX, y: bounds.height)
            bar.cornerRadius = cornerRadius
        }
        CATransaction.commit()
    }

    private func animateToOn() {
        guard window != nil else {
            removeBarAnimations()
            return
        }

        bars.forEach {
            $0.removeAnimation(forKey: Self.animationKey)
            $0.isHidden = false
        }

        // Respect Reduce Motion: show the bars at rest without bouncing.
        guard !UIAccessibility.isReduceMotionEnabled else { return }

        for (index, bar) in bars.enumerated() {
            let duration = Self.barDurations[index]
            let bounce = CABasicAnimation(keyPath: "transform.scale.y")
            bounce.fromValue = Self.minScale
            bounce.toValue = 1.0
            bounce.duration = duration
            bounce.autoreverses = true
            bounce.repeatCount = .infinity
            bounce.timeOffset = duration * Double(index) * 0.5
            bounce.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            bar.add(bounce, forKey: Self.animationKey)
        }
    }

    private func animateToOff() {
        bars.forEach {
            $0.removeAnimation(forKey: Self.animationKey)
            $0.isHidden = true
        }
    }

    private func removeBarAnimations() {
        bars.forEach { $0.removeAnimation(forKey: Self.animationKey) }
    }
}
