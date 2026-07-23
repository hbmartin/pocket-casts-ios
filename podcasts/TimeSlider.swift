import PocketCastsUtils
import UIKit

struct MomentPinTouchTracker {
    static let tapTolerance: CGFloat = 16

    private(set) var candidate: Int64?
    private var startPoint: CGPoint?

    mutating func begin(candidate: Int64?, at point: CGPoint) {
        self.candidate = candidate
        startPoint = candidate == nil ? nil : point
    }

    mutating func move(to point: CGPoint) {
        guard let startPoint,
              hypot(point.x - startPoint.x, point.y - startPoint.y) > Self.tapTolerance else {
            return
        }
        cancel()
    }

    mutating func end() -> Int64? {
        defer { cancel() }
        return candidate
    }

    mutating func cancel() {
        candidate = nil
        startPoint = nil
    }
}

class TimeSlider: UIView {
    var sidePadding = 20 as CGFloat

    // MARK: - Public properties

    var totalDuration: TimeInterval = 1800 {
        didSet {
            updateMomentAccessibilityActions()
        }
    }
    var currentTime: TimeInterval = 900 {
        didSet {
            let animated = !draggingKnob && (abs(oldValue - currentTime) > 8)
            recalculatePositionRects(animated)
        }
    }

    weak var delegate: TimeSliderDelegate?

    var leftColor = UIColor.white {
        didSet {
            timeLayer().leftColor = leftColor.cgColor
        }
    }

    var animationColor = UIColor.white.withAlphaComponent(0.2) {
        didSet {
            timeLayer().animationColor = animationColor.cgColor
        }
    }

    var rightColor = UIColor(white: 1.0, alpha: 0.20)
    var circleColor = UIColor.white {
        didSet {
            timeLayer().circleColor = circleColor.cgColor
        }
    }

    var popupColor = UIColor(white: 1.0, alpha: 0.25)
    var popupTextColor = UIColor.white

    var topOffset = 20 as CGFloat
    var shouldPopupOnDrag = true

    /// Timestamped comments rendered as pins above the track (Slice 6). A tap
    /// near a pin (that isn't a knob drag) reports sliderDidTapMoment.
    var momentPins: [(id: Int64, fraction: Double)] = [] {
        didSet {
            timeLayer().momentFractions = momentPins.map { CGFloat($0.fraction) }
            timeLayer().setNeedsDisplay()
            updateMomentAccessibilityActions()
        }
    }

    // MARK: - private properties

    private var draggingKnob = false
    private var momentPinTouchTracker = MomentPinTouchTracker()
    private let textStyle = NSMutableParagraphStyle.default.mutableCopy() as! NSMutableParagraphStyle

    // MARK: - public methods

    func isScrubbing() -> Bool {
        draggingKnob
    }

    override var accessibilityValue: String? {
        get {
            let current = currentTime.accessibilityValue()
            let total = totalDuration.accessibilityValue()
            return L10n.accessibilityPlaybackProgress(current, total)
        }
        set {
            // No-op
        }
    }

    override func accessibilityIncrement() {
        currentTime += totalDuration.skipLength
        delegate?.sliderDidSlide(to: currentTime)
    }

    override func accessibilityDecrement() {
        currentTime -= totalDuration.skipLength
        delegate?.sliderDidSlide(to: currentTime)
    }

    // MARK: - View Methods

    override nonisolated func awakeFromNib() {
        // awakeFromNib is nonisolated in its ObjC declaration, but views always wake on the main thread
        MainActor.assumeIsolated {
            let tLayer = timeLayer()
            tLayer.contentsScale = UIScreen.main.scale
            tLayer.leftColor = leftColor.cgColor
            tLayer.rightColor = rightColor.cgColor
            tLayer.animationColor = animationColor.cgColor
            tLayer.circleColor = circleColor.cgColor
            tLayer.popupColor = popupColor
            tLayer.popupTextColor = popupTextColor
            tLayer.popupScale = 0
            textStyle.alignment = NSTextAlignment.center
            tLayer.textStyle = textStyle

            backgroundColor = UIColor.clear
            tLayer.backgroundColor = UIColor.clear.cgColor
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        recalculatePositionRects(false)
    }

    override nonisolated func prepareForInterfaceBuilder() {
        // prepareForInterfaceBuilder is nonisolated in its ObjC declaration but runs on the main thread
        MainActor.assumeIsolated {
            draggingKnob = true
            timeLayer().popupScale = 1.0
            timeLayer().popupValue = "12:42"
        }
        awakeFromNib()
    }

    // MARK: - Touch handling

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        if let firstTouch = touches.first {
            let touchPoint = firstTouch.location(in: self)
            momentPinTouchTracker.begin(candidate: momentPin(near: touchPoint), at: touchPoint)
            let slightlyBiggerKnobRect = timeLayer().knobRect.insetBy(dx: -20, dy: -20)
            if slightlyBiggerKnobRect.contains(touchPoint) {
                momentPinTouchTracker.cancel()
                draggingKnob = true
                if shouldPopupOnDrag {
                    timeLayer().popupScale = 1.0
                    timeLayer().popupValue = TimeFormatter.shared.playTimeFormat(time: currentTime) as NSString
                }
                recalculatePositionRects(true)

                if let delegate {
                    delegate.sliderDidBeginSliding()
                }
            }
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        momentPinTouchTracker.cancel()
        if draggingKnob {
            draggingKnob = false
            if shouldPopupOnDrag { timeLayer().popupScale = 0 }
            recalculatePositionRects(true)

            if let delegate {
                delegate.sliderDidEndSliding()
            }
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        if !draggingKnob, let pin = momentPinTouchTracker.end() {
            delegate?.sliderDidTapMoment(id: pin)
            return
        }
        momentPinTouchTracker.cancel()
        if draggingKnob {
            draggingKnob = false
            if shouldPopupOnDrag { timeLayer().popupScale = 0 }
            recalculatePositionRects(true)

            if let delegate {
                delegate.sliderDidSlide(to: currentTime)
                delegate.sliderDidEndSliding()
            }
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let firstTouch = touches.first else { return }
        let touchPoint = firstTouch.location(in: self)
        momentPinTouchTracker.move(to: touchPoint)
        if !draggingKnob { return }

        if touchPoint.x < sidePadding + (timeLayer().knobRect.width / 2) {
            currentTime = 0
        } else if touchPoint.x > (bounds.width - (timeLayer().knobRect.width / 2) - sidePadding) {
            currentTime = totalDuration
        } else {
            let percentage = TimeInterval((touchPoint.x - sidePadding) / (bounds.width - (sidePadding * 2)))
            currentTime = totalDuration * percentage
        }

        timeLayer().popupValue = TimeFormatter.shared.playTimeFormat(time: currentTime) as NSString
        recalculatePositionRects(false)
        if let delegate {
            delegate.sliderDidProvisionallySlide(to: currentTime)
        }
    }

    private func updateMomentAccessibilityActions() {
        accessibilityCustomActions = momentPins.enumerated().map { index, pin in
            let fraction = min(max(pin.fraction, 0), 1)
            let timestamp = TimeFormatter.shared.playTimeFormat(time: totalDuration * fraction)
            return UIAccessibilityCustomAction(
                name: L10n.accessibilityPlayerOpenMoment(index + 1, timestamp)
            ) { [weak self] _ in
                self?.activateMomentPin(id: pin.id) ?? false
            }
        }
    }

    @discardableResult
    func activateMomentPin(id: Int64) -> Bool {
        guard let delegate else { return false }
        delegate.sliderDidTapMoment(id: id)
        return true
    }

    /// The pin whose track position lies within 16pt of the touch, if any.
    private func momentPin(near point: CGPoint) -> Int64? {
        guard !momentPins.isEmpty else { return nil }
        let availableWidth = bounds.width - (sidePadding * 2)
        let trackY = (bounds.height / 2) + topOffset
        guard abs(point.y - trackY) < 30 else { return nil }
        var best: (id: Int64, distance: CGFloat)?
        for pin in momentPins {
            let x = sidePadding + CGFloat(pin.fraction) * availableWidth
            let distance = abs(point.x - x)
            if distance < 16, distance < (best?.distance ?? .greatestFiniteMagnitude) {
                best = (pin.id, distance)
            }
        }
        return best?.id
    }

    // MARK: - Position calculations

    private func recalculatePositionRects(_ animated: Bool) {
        let availableWidth = bounds.width - (sidePadding * 2)
        let progressSize = CGFloat(currentTime / totalDuration) * availableWidth
        let viewCenterWithOffset = (bounds.height / 2) + topOffset
        let knobWidth = draggingKnob ? 16 : 12 as CGFloat
        let lineHeight = draggingKnob ? 6 : 4 as CGFloat

        if !animated {
            CATransaction.begin()
            CATransaction.setValue(kCFBooleanTrue, forKey: kCATransactionDisableActions)
        }
        timeLayer().leftHalfRect = CGRect(x: sidePadding, y: viewCenterWithOffset - (lineHeight / 2), width: progressSize, height: lineHeight)
        timeLayer().rightHalfRect = CGRect(x: sidePadding + progressSize, y: viewCenterWithOffset - (lineHeight / 2), width: availableWidth - progressSize, height: lineHeight)

        var knobX = max(sidePadding, sidePadding + progressSize - (knobWidth / 2))
        knobX = min(knobX, sidePadding + availableWidth - knobWidth)
        timeLayer().knobRect = CGRect(x: knobX, y: viewCenterWithOffset - (knobWidth / 2), width: knobWidth, height: knobWidth)
        if !animated {
            CATransaction.commit()
        }
    }

    // MARK: - Layer methods

    private func timeLayer() -> TimeSliderLayer {
        layer as! TimeSliderLayer
    }

    override class var layerClass: AnyClass {
        TimeSliderLayer.self
    }

    var indeterminant: Bool = false {
        didSet {
            if self.window != nil {
                timeLayer().shouldAnimate = indeterminant
            }
        }
    }
}

private extension TimeInterval {
    /// Base value is the number of seconds which should be skipped from a given track length
    // nonisolated(unsafe): UnitConverterLinear is immutable after init and its conversion
    // methods are pure; the reference itself is a constant.
    nonisolated(unsafe) private static let secondsToSkipConverter = UnitConverterLinear(coefficient: 0.075, constant: 12)

    /// Calculates the skip time for a given total time in a track
    /// This is a linear equation which increases as time scales
    /// - Parameter length: The total length of time for the track
    /// - Returns: The time to skip by
    var skipLength: TimeInterval {
        TimeInterval.secondsToSkipConverter.baseUnitValue(fromValue: self)
    }
}

private extension TimeInterval {
    /// An accessibility string to be read by voice over. This will be a spelled out version of the TimeInterval.
    /// - Returns: A string to be read by voice over, a spelled out version of the interval with full units.
    func accessibilityValue() -> String {
        let origDate = Date()
        let date = Date(timeInterval: self, since: origDate)

        let dateRange = origDate..<date

        return dateRange.formatted(.components(style: .spellOut))
    }
}
