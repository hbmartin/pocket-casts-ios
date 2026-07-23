import Kingfisher
import PocketCastsUtils
import PocketCastsDataModel
import UIKit

class PlayerChapterCell: UITableViewCell {
    /// Chapter artwork shown in place of the chapter number when the chapter
    /// carries an image (embedded bytes or a fetched remote URL).
    private lazy var artworkView: UIImageView = {
        let imageView = UIImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFill
        imageView.layer.cornerRadius = 4
        imageView.clipsToBounds = true
        contentView.addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.centerXAnchor.constraint(equalTo: chapterNumber.centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: chapterNumber.centerYAnchor),
            imageView.widthAnchor.constraint(equalToConstant: 28),
            imageView.heightAnchor.constraint(equalToConstant: 28)
        ])
        return imageView
    }()
    @IBOutlet var chapterName: UILabel! {
        didSet {
            chapterName.font = .font(ofSize: 14, weight: .medium, scalingWith: .subheadline)
            chapterName.adjustsFontForContentSizeCategory = true
        }
    }
    @IBOutlet var chapterLength: UILabel! {
        didSet {
            chapterLength.font = .font(ofSize: 12, weight: .semibold, scalingWith: .caption1)
            chapterLength.adjustsFontForContentSizeCategory = true
        }
    }

    @IBOutlet var chapterNumber: UILabel! {
        didSet {
            chapterNumber.font = .font(ofSize: 12, weight: .semibold, scalingWith: .caption1)
            chapterNumber.adjustsFontForContentSizeCategory = true
        }
    }
    @IBOutlet var nowPlayingAnimation: NowPlayingAnimationView!
    @IBOutlet var linkAndTimeView: UIView! {
        didSet {
            let tap = UITapGestureRecognizer(target: self, action: #selector(linkTapped(_:)))
            linkAndTimeView.addGestureRecognizer(tap)
            linkAndTimeView.isUserInteractionEnabled = true
        }
    }

    @IBOutlet var linkView: UIView!
    @IBOutlet var seperatorView: UIView!
    @IBOutlet var progressViewWidth: NSLayoutConstraint!
    @IBOutlet var isPlayingView: UIView!
    @IBOutlet weak var toggleChapterButton: BouncyButton!
    @IBOutlet weak var chapterButtonWidth: NSLayoutConstraint!

    private var onLinkTapped: ((URL) -> Void)?
    private var chapter: ChapterInfo?

    enum ChapterPlayState { case played, currentlyPlaying, currentlyPaused, future }

    private var playState = ChapterPlayState.played

    private var circleCenter: CGPoint!
    var chapterPlayedTime: Int!

    private var isChapterToggleEnabled: Bool = false

    override nonisolated func awakeFromNib() {
        super.awakeFromNib()

        MainActor.assumeIsolated {
            messageTokens.append(NotificationCenter.default.addObserver(for: PlaybackProgressed.self) { [weak self] _ in
                self?.progressUpdated()
            })
            messageTokens.append(NotificationCenter.default.addObserver(for: PodcastChaptersDidUpdate.self) { [weak self] _ in
                self?.progressUpdated()
            })
            contentView.backgroundColor = UIColor.clear
            backgroundColor = UIColor.clear
        }
    }

    private var messageTokens = [NotificationCenter.ObservationToken]()

    deinit {
        // Property reads must precede any nonisolated work in deinit (Swift 6.2
        // isolated-deinit rule).
        let tokens = messageTokens
        for token in tokens {
            NotificationCenter.default.removeObserver(token)
        }
    }

    override func setSelected(_ selected: Bool, animated: Bool) {
        setSelectedState(selected: selected)
    }

    override func setHighlighted(_ highlighted: Bool, animated: Bool) {
        setSelectedState(selected: highlighted)
    }

    private func setSelectedState(selected: Bool) {
        switch playState {
        case .currentlyPlaying, .currentlyPaused:
            isPlayingView.backgroundColor = selected ? ThemeColor.playerContrast05() : ThemeColor.playerContrast06()
        case .played, .future:
            backgroundColor = selected ? ThemeColor.playerContrast05() : UIColor.clear
        }
    }

    func populateFrom(chapter: ChapterInfo, playState: ChapterPlayState, isChapterToggleEnabled: Bool, linkTapped: @escaping ((URL) -> Void)) {
        self.playState = playState
        self.isChapterToggleEnabled = isChapterToggleEnabled
        chapterName.text = chapter.title
        chapterLength.text = TimeFormatter.shared.singleUnitFormattedShortestTime(time: chapter.duration)
        chapterNumber.text = "\(chapter.index + 1)"
        // Assign before updateArtwork: a synchronously delivered artwork failure checks
        // `self.chapter === chapter` before applying the fallback UI.
        self.chapter = chapter
        updateArtwork(for: chapter)
        linkView.isHidden = (chapter.url == nil || isChapterToggleEnabled)

        nowPlayingAnimation.animating = false
        setColors(dim: playState == .played)
        if playState == .currentlyPlaying || playState == .currentlyPaused {
            isPlayingView.isHidden = false
        } else {
            isPlayingView.isHidden = true
            seperatorView.isHidden = true
        }

        onLinkTapped = linkTapped
        isPlayingView.backgroundColor = ThemeColor.playerContrast06()
        progressUpdated(animated: false)

        setUpSelectedChapterButton()

        toggleChapterButton.currentlyOn = chapter.shouldPlay

        isChapterToggleEnabled ? showSelectedChapterButton() : hideSelectedChapterButton()
    }

    /// Shows the chapter's artwork over the number when it has any: embedded
    /// bytes directly, remote URLs via Kingfisher (cached; reused cells cancel
    /// the previous load by setting a new source). No artwork → plain number.
    private func updateArtwork(for chapter: ChapterInfo) {
        if let image = chapter.image {
            artworkView.kf.cancelDownloadTask()
            artworkView.image = image
            artworkView.isHidden = false
            chapterNumber.alpha = 0
        } else if let imageURL = chapter.imageURL {
            artworkView.isHidden = false
            chapterNumber.alpha = 0
            artworkView.kf.setImage(with: imageURL, options: [.transition(.fade(Constants.Animation.defaultAnimationTime))]) { [weak self] result in
                switch result {
                case .success(let value):
                    chapter.image = value.image
                case .failure:
                    guard self?.chapter === chapter else { return }
                    self?.artworkView.isHidden = true
                    self?.chapterNumber.alpha = 1
                }
            }
        } else {
            artworkView.kf.cancelDownloadTask()
            artworkView.image = nil
            artworkView.isHidden = true
            chapterNumber.alpha = 1
        }
    }

    private func setUpSelectedChapterButton() {
        toggleChapterButton.onImage = UIImage(named: "rounded-selected")
        toggleChapterButton.offImage = UIImage(named: "rounded-deselected")
        toggleChapterButton.tintColor = .white
        toggleChapterButton.isUserInteractionEnabled = false
    }

    private func hideSelectedChapterButton() {
        toggleChapterButton.isHidden = true
        chapterButtonWidth.constant = 20
    }

    private func showSelectedChapterButton() {
        toggleChapterButton.isHidden = false
        chapterButtonWidth.constant = 48
        setColors(dim: chapter?.isPlayable() == false)
    }

    @IBAction func linkTapped(_ sender: Any) {
        guard let link = chapter?.url, let url = URL(string: link), let linkTapped = onLinkTapped else { return }
        PlaybackManager.shared.trackChapterEvent(.chapterLinkClicked)
        linkTapped(url)
    }


    @IBAction func toggleChapterTapped(_ sender: Any) {
        chapter?.shouldPlay.toggle()
        toggleChapterButton.currentlyOn.toggle()

        setColors(dim: chapter?.isPlayable() == false)

        if var currentEpisode = PlaybackManager.shared.currentEpisode(), let index = chapter?.index {
            if chapter?.shouldPlay == true {
                currentEpisode.select(chapterIndex: index)
                // Also exempt the chapter from smart-skip title rules for this session, otherwise
                // the next chapter reload would immediately re-deselect a rule-matched chapter
                PlaybackManager.shared.registerChapterSessionReEnable(chapterIndex: index, episodeUuid: currentEpisode.uuid)
                track(.deselectChaptersChapterSelected)
            } else {
                currentEpisode.deselect(chapterIndex: index)
                PlaybackManager.shared.unregisterChapterSessionReEnable(chapterIndex: index, episodeUuid: currentEpisode.uuid)
                track(.deselectChaptersChapterDeselected)
            }

            currentEpisode.deselectedChaptersModified = TimeFormatter.currentUTCTimeInMillis()

            Self.chapterSaveTask?.cancel()
            let boxedEpisode = PocketCastsUtils.UncheckedSendable(currentEpisode)
            Self.chapterSaveTask = Task {
                try? await Task.sleep(nanoseconds: Self.chapterSaveDelayNanoseconds)
                guard !Task.isCancelled else { return }

                await DataManager.sharedManager.saveAsync(episode: boxedEpisode.value)
                // value-type episodes: refresh playback's copy of the deselected chapters
                await MainActor.run { PlaybackManager.shared.forceUpdateChapterInfo() }
            }
        }
    }

    /// Debounces episode saves across all chapter cells: rapid toggles should persist
    /// the final shared episode state rather than queueing every intermediate state. If
    /// the app is terminated before the delay elapses, that pending save is lost. Cancelling
    /// a pending task also does not stop a save already in flight, so a tap landing mid-save
    /// can still race a property read on the shared mutable episode object.
    private static var chapterSaveTask: Task<Void, Never>?
    private static let chapterSaveDelayNanoseconds: UInt64 = 300_000_000

    func progressUpdated(animated: Bool = true) {
        guard let chapter, chapter == PlaybackManager.shared.currentChapters().visibleChapter else { return }

        layoutIfNeeded()

        let lapsedTime = PlaybackManager.shared.currentTime() - chapter.startTime.seconds
        let percentageLapsed = CGFloat(lapsedTime / chapter.duration.seconds)

        if percentageLapsed.isFinite, !percentageLapsed.isNaN {
            progressViewWidth.constant = percentageLapsed * isPlayingView.frame.width
        } else {
            progressViewWidth.constant = 0
        }

        if animated {
            UIView.animate(withDuration: 0.95) {
                self.layoutIfNeeded()
            }
        } else { layoutIfNeeded() }
    }

    private func setColors(dim shouldDim: Bool) {
        linkView.alpha = shouldDim ? 0.5 : 1
        chapterName.textColor = shouldDim ? ThemeColor.playerContrast02() : ThemeColor.playerContrast01()
        chapterNumber.textColor = chapterName.textColor
        chapterLength.textColor = chapterName.textColor
    }

    private func track(_ event: AnalyticsEvent) {
        PlaybackManager.shared.trackChapterEvent(event, properties: ["podcast_uuid": PlaybackManager.shared.currentPodcast?.uuid ?? "unknown", "episode_uuid": PlaybackManager.shared.currentEpisode()?.uuid ?? "unknown"])
    }
}
