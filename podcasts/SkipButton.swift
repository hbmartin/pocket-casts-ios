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

    deinit {
        removeTarget(self, action: #selector(playAnimation), for: .touchUpInside)
    }

    override func awakeFromNib() {
        super.awakeFromNib()

        setupViews()
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
/// The owning `SkipButton` mirrors this view horizontally for skip-back, and the
/// seconds value is rendered separately by `SkipButton`'s label in the centre.
class SkipIconView: UIView {
    private static let spinKey = "skipSpin"

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
        let rotation = CABasicAnimation(keyPath: "transform.rotation.z")
        rotation.fromValue = 0
        rotation.toValue = 2 * CGFloat.pi
        rotation.duration = 0.4
        rotation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        arcLayer.add(rotation, forKey: Self.spinKey)
    }

    private func arrowPath() -> CGPath {
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let radius = min(bounds.width, bounds.height) * 0.34
        guard radius > 0 else { return CGMutablePath() }

        // Near-complete circle with a small gap at the top.
        let gapHalf: CGFloat = 0.55
        let topAngle = -CGFloat.pi / 2
        let start = topAngle + gapHalf
        let end = start + (2 * .pi - 2 * gapHalf)

        let path = UIBezierPath(arcCenter: center, radius: radius, startAngle: start, endAngle: end, clockwise: true)

        // Chevron arrowhead at the start of the arc, pointing clockwise.
        let tip = CGPoint(x: center.x + radius * cos(start), y: center.y + radius * sin(start))
        let tangent = CGVector(dx: -sin(start), dy: cos(start)) // clockwise direction
        let arrowLen = radius * 0.55
        func barb(_ angle: CGFloat) -> CGPoint {
            // Rotate the reverse-tangent by `angle` to splay the barbs backwards.
            let dx = -tangent.dx, dy = -tangent.dy
            let rx = dx * cos(angle) - dy * sin(angle)
            let ry = dx * sin(angle) + dy * cos(angle)
            return CGPoint(x: tip.x + rx * arrowLen, y: tip.y + ry * arrowLen)
        }
        path.move(to: barb(0.6))
        path.addLine(to: tip)
        path.addLine(to: barb(-0.6))

        return path.cgPath
    }
}
