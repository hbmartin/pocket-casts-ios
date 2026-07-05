import PocketCastsUtils
import PocketCastsDataModel
import UIKit

class PlayerChapterCell: UITableViewCell {
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

    override func awakeFromNib() {
        super.awakeFromNib()

        MainActor.assumeIsolated {
            NotificationCenter.default.addObserver(self, selector: #selector(progressUpdated), name: Constants.Notifications.playbackProgress, object: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(progressUpdated), name: Constants.Notifications.podcastChaptersDidUpdate, object: nil)
            contentView.backgroundColor = UIColor.clear
            backgroundColor = UIColor.clear
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
        self.chapter = chapter
        isPlayingView.backgroundColor = ThemeColor.playerContrast06()
        progressUpdated(animated: false)

        setUpSelectedChapterButton()

        toggleChapterButton.currentlyOn = chapter.shouldPlay

        isChapterToggleEnabled ? showSelectedChapterButton() : hideSelectedChapterButton()
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
                track(.deselectChaptersChapterSelected)
            } else {
                currentEpisode.deselect(chapterIndex: index)
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

    @objc func progressUpdated(animated: Bool = true) {
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
