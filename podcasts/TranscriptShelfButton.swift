import UIKit
import PocketCastsDataModel

class TranscriptShelfButton: UIButton, CheckTranscriptAvailability {
    var hasGeneratedTranscripts: Bool = false
    var isTranscriptEnabled: Bool {
        didSet {
            imageView?.tintColor = isTranscriptEnabled ? ThemeColor.playerContrast02() : ThemeColor.playerContrast06()
        }
    }

    override init(frame: CGRect) {
        isTranscriptEnabled = false
        super.init(frame: frame)
        addObservers()
        checkTranscriptAvailability()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func addObservers() {
        addTranscriptObservers()
    }
}

@MainActor
protocol CheckTranscriptAvailability: AnyObject {
    var isTranscriptEnabled: Bool { get set }
    var hasGeneratedTranscripts: Bool { get set }

    func addTranscriptObservers()
    func checkTranscriptAvailability()
}

extension CheckTranscriptAvailability where Self: Sendable {
    func addTranscriptObservers() {
        NotificationCenter.default.addObserver(forName: Constants.Notifications.episodeTranscriptAvailabilityChanged, object: nil, queue: .main) { [weak self] notification in
            guard let episodeUuid = notification.userInfo?["episodeUuid"] as? String,
                  let isAvailable = notification.userInfo?["isAvailable"] as? Bool,
                  let hasGeneratedTranscripts = notification.userInfo?["hasGeneratedTranscripts"] as? Bool else {
                return
            }

            Task { @MainActor [weak self] in
                guard episodeUuid == PlaybackManager.shared.currentEpisode()?.uuid else { return }
                self?.isTranscriptEnabled = isAvailable
                self?.hasGeneratedTranscripts = hasGeneratedTranscripts
            }
        }

        NotificationCenter.default.addObserver(forName: Constants.Notifications.playbackTrackChanged, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.checkTranscriptAvailability()
            }
        }
    }

    func checkTranscriptAvailability() {
        isTranscriptEnabled = false
        hasGeneratedTranscripts = false
        let currentEpisode = PlaybackManager.shared.currentEpisode() as? Episode
        currentEpisode?.checkTranscriptAvailability()
    }
}
