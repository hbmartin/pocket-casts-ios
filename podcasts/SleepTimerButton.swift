import UIKit

class SleepTimerButton: UIButton {
    var scaleAmount: CGFloat = 1.5 {
        didSet {
            iconView.transform = CGAffineTransform(scaleX: scaleAmount, y: scaleAmount)
        }
    }

    var sleepTimerOn = false {
        didSet {
            // check for a state we're already in
            if sleepTimerOn == oldValue { return }

            if sleepTimerOn {
                animateToOn()
            } else {
                animateToOff()
            }
        }
    }

    private var iconView: SleepIconView

    override var tintColor: UIColor! {
        didSet {
            iconView.fillColor = tintColor
        }
    }

    override init(frame: CGRect) {
        iconView = SleepIconView(frame: .zero)
        iconView.isUserInteractionEnabled = false
        iconView.transform = CGAffineTransform(scaleX: scaleAmount, y: scaleAmount)

        super.init(frame: frame)
        setupObservers()
    }

    required init?(coder aDecoder: NSCoder) {
        iconView = SleepIconView(frame: .zero)
        iconView.isUserInteractionEnabled = false
        iconView.transform = CGAffineTransform(scaleX: scaleAmount, y: scaleAmount)

        super.init(coder: aDecoder)
        setupObservers()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func awakeFromNib() {
        super.awakeFromNib()

        setupAnimation()
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
        sleepTimerOn ? animateToOn() : animateToOff()
    }

    @objc private func applicationWillResignActive() {
        iconView.stopAnimating()
    }

    @objc private func applicationDidBecomeActive() {
        if sleepTimerOn {
            animateToOn()
        }
    }

    func setupAnimation() {
        iconView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(iconView)

        iconView.anchorToAllSidesOf(view: self)
    }

    private func animateToOn() {
        iconView.startAnimating()
    }

    private func animateToOff() {
        iconView.stopAnimating()
    }
}

/// Draws the "Zzz" sleep glyph (three Z letters rising diagonally) and gives them
/// a gentle staggered shimmer while the timer is active. Replaces the former
/// Lottie `sleep_button` animation; the Z geometry is taken directly from the
/// original `sleep_button.json` (authored in a 48×48 space).
class SleepIconView: UIView {
    private static let canvasSize: CGFloat = 48
    private static let pulseKey = "zzzPulse"

    /// The three Z outlines, in the original 48×48 coordinate space.
    private static let zShapes: [[CGPoint]] = [
        [CGPoint(x: 11.8, y: 28.2), CGPoint(x: 10.8, y: 27.3), CGPoint(x: 11.7, y: 26.2), CGPoint(x: 16.6, y: 25.8),
         CGPoint(x: 17.6, y: 27.4), CGPoint(x: 14.3, y: 32.0), CGPoint(x: 17.2, y: 31.8), CGPoint(x: 18.2, y: 32.7),
         CGPoint(x: 17.3, y: 33.8), CGPoint(x: 12.4, y: 34.2), CGPoint(x: 11.4, y: 32.6), CGPoint(x: 14.7, y: 28.0)],
        [CGPoint(x: 23.3, y: 21.8), CGPoint(x: 18.5, y: 22.7), CGPoint(x: 17.4, y: 21.8), CGPoint(x: 18.2, y: 20.7),
         CGPoint(x: 25.1, y: 19.5), CGPoint(x: 26.1, y: 21.0), CGPoint(x: 21.7, y: 28.2), CGPoint(x: 26.5, y: 27.3),
         CGPoint(x: 27.6, y: 28.2), CGPoint(x: 26.8, y: 29.3), CGPoint(x: 19.9, y: 30.5), CGPoint(x: 18.9, y: 29.0)],
        [CGPoint(x: 34.4, y: 17.4), CGPoint(x: 28.7, y: 16.4), CGPoint(x: 27.9, y: 15.2), CGPoint(x: 29.0, y: 14.4),
         CGPoint(x: 36.9, y: 15.8), CGPoint(x: 37.3, y: 17.5), CGPoint(x: 29.6, y: 23.6), CGPoint(x: 35.3, y: 24.6),
         CGPoint(x: 36.1, y: 25.8), CGPoint(x: 35.0, y: 26.6), CGPoint(x: 27.1, y: 25.2), CGPoint(x: 26.7, y: 23.5)]
    ]

    private var zLayers: [CAShapeLayer] = []

    var fillColor: UIColor = .white {
        didSet {
            zLayers.forEach { $0.fillColor = fillColor.cgColor }
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
        for _ in Self.zShapes {
            let z = CAShapeLayer()
            z.fillColor = fillColor.cgColor
            layer.addSublayer(z)
            zLayers.append(z)
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        let scaleX = bounds.width / Self.canvasSize
        let scaleY = bounds.height / Self.canvasSize

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (index, points) in Self.zShapes.enumerated() {
            let path = UIBezierPath()
            for (i, point) in points.enumerated() {
                let scaled = CGPoint(x: point.x * scaleX, y: point.y * scaleY)
                if i == 0 { path.move(to: scaled) } else { path.addLine(to: scaled) }
            }
            path.close()
            zLayers[index].frame = bounds
            zLayers[index].path = path.cgPath
        }
        CATransaction.commit()
    }

    func startAnimating() {
        guard !UIAccessibility.isReduceMotionEnabled else { return }

        // The Z's shimmer in sequence to suggest rising "Zzz".
        let cycle: CFTimeInterval = 0.6
        for (index, z) in zLayers.enumerated() {
            let pulse = CABasicAnimation(keyPath: "opacity")
            pulse.fromValue = 0.3
            pulse.toValue = 1.0
            pulse.duration = cycle
            pulse.autoreverses = true
            pulse.repeatCount = .infinity
            pulse.timeOffset = cycle * (2.0 / 3.0) * Double(index)
            pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            z.add(pulse, forKey: Self.pulseKey)
        }
    }

    func stopAnimating() {
        zLayers.forEach { $0.removeAnimation(forKey: Self.pulseKey) }
    }
}
