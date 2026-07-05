import Combine
import PocketCastsDataModel
import PocketCastsServer
import UIKit

class PlayPauseLabeledButton: BasePlayPauseButton {
    private var cancellables = Set<AnyCancellable>()
    private let label: UILabel = {
        let label = UILabel()
        label.font = UIFont.font(ofSize: 13, weight: .semibold, scalingWith: .largeTitle)
        label.adjustsFontForContentSizeCategory = true
        label.isUserInteractionEnabled = false
        return label
    }()

    public var text: String? {
        get {
            label.text
        }
        set {
            label.text = newValue
        }
    }

    public var episodeUUID: String? {
        didSet {
            updatePlayingState()
        }
    }

    var colors: PodcastCollectionColors? {
        didSet {
            updateTheme()
        }
    }

    var defaultStyle: ThemeStyle = .support02 {
        didSet {
            updateTheme()
        }
    }

    override func awakeFromNib() {
        super.awakeFromNib()
        MainActor.assumeIsolated {
            layer.borderWidth = 1.5
            backgroundColor = .clear

            Theme.sharedTheme.activeThemePublisher
                .receive(on: RunLoop.main)
                .sink(receiveValue: { [unowned self] _ in
                    self.updateTheme()
                })
                .store(in: &cancellables)

            Publishers.Merge3(
                NotificationCenter.default.publisher(for: Constants.Notifications.playbackStarted),
                NotificationCenter.default.publisher(for: Constants.Notifications.playbackPaused),
                NotificationCenter.default.publisher(for: Constants.Notifications.playbackEnded)
            )
            .receive(on: RunLoop.main)
            .sink { [unowned self] _ in
                self.updatePlayingState()
            }
            .store(in: &cancellables)
        }
    }

    private func updatePlayingState() {
        isPlaying = PlaybackManager.shared.isActivelyPlaying(episodeUuid: episodeUUID)
    }

    override public func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = frame.size.height / 2
    }

    override func place(icon: UIView) {
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.isUserInteractionEnabled = false
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(icon)
        addSubview(label)
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.heightAnchor.constraint(equalTo: heightAnchor, multiplier: 0.6),
            icon.heightAnchor.constraint(equalTo: icon.widthAnchor),
            label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 5),
            label.topAnchor.constraint(equalTo: topAnchor),
            label.bottomAnchor.constraint(equalTo: bottomAnchor),
            label.topAnchor.constraint(equalTo: topAnchor),
            trailingAnchor.constraint(equalTo: label.trailingAnchor, constant: 15)
        ])
    }

    private func updateTheme() {
        let color = colors?.activeThemeColor ?? AppTheme.colorForStyle(defaultStyle)
        layer.borderColor = color.cgColor
        playButtonColor = color
        label.textColor = color
    }

    private let alphaAdjustForTouch = 0.6
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        alpha = isTouchInside ? alphaAdjustForTouch : 1
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        alpha = 1
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesMoved(touches, with: event)
        alpha = isTouchInside ? alphaAdjustForTouch : 1
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesCancelled(touches, with: event)
        alpha = 1
    }
}
