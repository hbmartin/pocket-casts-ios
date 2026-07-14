import UIKit

class SkipButton: UIButton {
    private static let buttonPadding: CGFloat = 20

    var skipBack = false {
        didSet {
            if skipBack {
                iconView.transform = CGAffineTransform.identity
            } else {
                iconView.transform = iconView.transform.scaledBy(x: -1, y: 1)
            }
        }
    }

    var skipAmount = 0 {
        didSet {
            skipLabel.text = "\(skipAmount)"
        }
    }

    var longPressed: (() -> Void)?

    override var tintColor: UIColor! {
        didSet {
            skipLabel.textColor = tintColor
            iconView.strokeColor = tintColor
        }
    }

    private var iconView: SkipIconView
    private let skipLabel: UILabel

    private var currentSize: Size = .large

    private lazy var animationHeightAnchor = iconView.heightAnchor.constraint(equalToConstant: Size.large.sizes.height)
    private lazy var animationWidthAnchor = iconView.widthAnchor.constraint(equalToConstant: Size.large.sizes.width)
    private lazy var skipLabelCenterYAnchor = skipLabel.centerYAnchor.constraint(equalTo: centerYAnchor, constant: Size.large.sizes.topPadding / 2)
    private lazy var skipLabelXConstraint = skipBack ? trailingAnchor.constraint(equalTo: skipLabel.trailingAnchor, constant: SkipButton.buttonPadding) : skipLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: SkipButton.buttonPadding)

    required init?(coder aDecoder: NSCoder) {
        iconView = SkipIconView(frame: .zero)
        skipLabel = UILabel()

        super.init(coder: aDecoder)

        iconView.isUserInteractionEnabled = false
        iconView.clipsToBounds = false

        skipLabel.textAlignment = .center
        skipLabel.font = UIFont.systemFont(ofSize: Size.large.sizes.fontSize, weight: .medium)
        skipLabel.textColor = UIColor.white

        addTarget(self, action: #selector(playAnimation), for: .touchUpInside)

        let longPressGesture = UILongPressGestureRecognizer(target: self, action: #selector(buttonLongPressed(_:)))
        addGestureRecognizer(longPressGesture)
    }

    override nonisolated func awakeFromNib() {
        super.awakeFromNib()

        // awakeFromNib is nonisolated in its ObjC declaration, but views always wake on the main thread
        MainActor.assumeIsolated {
            setupViews()
        }
    }

    func setupViews() {
        iconView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(iconView)

        let xConstraint = skipBack ? trailingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: SkipButton.buttonPadding) : iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: SkipButton.buttonPadding)
        NSLayoutConstraint.activate([
            animationHeightAnchor,
            animationWidthAnchor,
            xConstraint,
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])

        addSubview(skipLabel)
        skipLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            skipLabel.heightAnchor.constraint(equalToConstant: Size.large.sizes.height),
            skipLabel.widthAnchor.constraint(equalToConstant: Size.large.sizes.width),
            skipLabelXConstraint,
            skipLabelCenterYAnchor
        ])
    }

    @objc private func buttonLongPressed(_ recognizer: UILongPressGestureRecognizer) {
        guard recognizer.state == .began else { return }

        longPressed?()
    }

    @objc private func playAnimation() {
        iconView.spin()
    }

    func changeSize(to size: Size) {
        currentSize = size
        let sizes = currentSize.sizes
        animationHeightAnchor.constant = sizes.height
        animationWidthAnchor.constant = sizes.width
        skipLabelCenterYAnchor.constant = sizes.topPadding / 2

        let labelScale = UIFont.systemFont(ofSize: sizes.fontSize, weight: .medium).pointSize / skipLabel.font.pointSize
        skipLabel.transform = .init(scaleX: labelScale, y: labelScale)

        let subtract = currentSize == .small ? (Size.large.sizes.width - Size.small.sizes.width) / 2 : 0
        skipLabelXConstraint.constant = SkipButton.buttonPadding - subtract
    }

    // The icon resizes via Auto Layout during the transcript/zoom transitions.
    // Snapshotting the current rendering and scaling that bitmap keeps the resize
    // smooth while the live icon reflows underneath.
    func prepareForAnimateTransition(withBackground: UIColor?) {
        guard let snapshot = iconView.snapshotView(afterScreenUpdates: false) else { return }

        let multiplier = currentSize == .large ? Size.large.sizes.width / Size.large.sizes.height : Size.large.sizes.height / Size.large.sizes.width

        snapshot.translatesAutoresizingMaskIntoConstraints = false
        snapshot.backgroundColor = withBackground
        iconView.addSubview(snapshot)
        NSLayoutConstraint.activate([
            snapshot.widthAnchor.constraint(equalTo: iconView.widthAnchor, multiplier: multiplier),
            snapshot.heightAnchor.constraint(equalTo: iconView.heightAnchor),
            snapshot.centerXAnchor.constraint(equalTo: iconView.centerXAnchor),
            snapshot.centerYAnchor.constraint(equalTo: iconView.centerYAnchor)
        ])

        iconView.clipsToBounds = true
    }

    func finishedTransition() {
        iconView.clipsToBounds = false
        iconView.subviews.first?.removeFromSuperview()
    }

    enum Size {
        case small
        case large

        var sizes: (width: CGFloat, height: CGFloat, fontSize: CGFloat, topPadding: CGFloat) {
            self == .small ? (32, 32, 10, 5) : (45, 53, 14, 8)
        }
    }
}

/// Draws a circular "skip" arrow (a stroked arc with a chevron arrowhead) and
/// spins once when tapped. Replaces the former Lottie `skip_button` animation.
/// The base drawing points counter-clockwise (skip-back); the owning `SkipButton`
/// mirrors this view horizontally for skip-forward, and the seconds value is
/// rendered separately by `SkipButton`'s label in the centre.
class SkipIconView: UIView {
    private static let spinKey = "skipSpin"
    private static let scaleKey = "skipScale"

    private let arcLayer = CAShapeLayer()

    var strokeColor: UIColor = .white {
        didSet {
            arcLayer.strokeColor = strokeColor.cgColor
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
        arcLayer.fillColor = UIColor.clear.cgColor
        arcLayer.strokeColor = strokeColor.cgColor
        arcLayer.lineCap = .round
        arcLayer.lineJoin = .round
        layer.addSublayer(arcLayer)
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        arcLayer.frame = bounds
        arcLayer.lineWidth = max(1.5, min(bounds.width, bounds.height) * 0.09)
        arcLayer.path = arrowPath()
        CATransaction.commit()
    }

    /// Plays a single rotation to acknowledge a tap.
    func spin() {
        guard !UIAccessibility.isReduceMotionEnabled else {
            acknowledgeTapWithoutMotion()
            return
        }

        let rotation = CABasicAnimation(keyPath: "transform.rotation.z")
        rotation.fromValue = 0
        rotation.toValue = 2 * CGFloat.pi
        rotation.duration = 0.4
        rotation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        arcLayer.add(rotation, forKey: Self.spinKey)

        let scale = CAKeyframeAnimation(keyPath: "transform.scale")
        scale.values = [1.0, 0.85, 1.0]
        scale.keyTimes = [0, 0.4, 1]
        scale.duration = 0.4
        scale.timingFunctions = [
            CAMediaTimingFunction(name: .easeInEaseOut),
            CAMediaTimingFunction(name: .easeInEaseOut),
        ]
        layer.add(scale, forKey: Self.scaleKey)
    }

    /// Reduce Motion alternative to `spin()`: a brief opacity dip so taps still
    /// get visual acknowledgement without any movement.
    private func acknowledgeTapWithoutMotion() {
        alpha = 1.0
        UIView.animate(withDuration: 0.1, animations: {
            self.alpha = 0.5
        }, completion: { _ in
            UIView.animate(withDuration: 0.2) {
                self.alpha = 1.0
            }
        })
    }

    private func arrowPath() -> CGPath {
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let radius = min(bounds.width, bounds.height) * 0.34
        guard radius > 0 else { return CGMutablePath() }

        // Near-complete circle with a small gap at the top, drawn counter-clockwise
        // so the stroke ends at the right edge of the gap. This base orientation is
        // the skip-back arrow; `SkipButton` mirrors the view for skip-forward.
        let gapHalf: CGFloat = 0.55
        let topAngle = -CGFloat.pi / 2
        let start = topAngle - gapHalf
        let end = topAngle + gapHalf

        let path = UIBezierPath(arcCenter: center, radius: radius, startAngle: start, endAngle: end, clockwise: false)

        // Chevron arrowhead straddling the end of the stroke, with its tip ahead of
        // the arc end so it points counter-clockwise across the gap.
        let endPoint = CGPoint(x: center.x + radius * cos(end), y: center.y + radius * sin(end))
        let direction = CGVector(dx: sin(end), dy: -cos(end)) // counter-clockwise tangent
        let perpendicular = CGVector(dx: -direction.dy, dy: direction.dx)
        let headLength = radius * 0.45
        let headHalfWidth = radius * 0.38
        let tip = CGPoint(x: endPoint.x + direction.dx * headLength, y: endPoint.y + direction.dy * headLength)
        path.move(to: CGPoint(x: endPoint.x + perpendicular.dx * headHalfWidth, y: endPoint.y + perpendicular.dy * headHalfWidth))
        path.addLine(to: tip)
        path.addLine(to: CGPoint(x: endPoint.x - perpendicular.dx * headHalfWidth, y: endPoint.y - perpendicular.dy * headHalfWidth))

        return path.cgPath
    }
}
