import UIKit
import PocketCastsServer

class ChaptersViewController: PlayerItemViewController {
    var isTogglingChapters = true

    var numberOfDeselectedChapters = 0

    @IBOutlet var chaptersTable: UITableView! {
        didSet {
            registerCells()
            chaptersTable.backgroundView = nil
        }
    }

    private(set) lazy var header: ChaptersHeader = {
        let header = ChaptersHeader()
        header.delegate = self
        header.isTogglingChapters = isTogglingChapters
        return header
    }()

    lazy var playbackManager = PlaybackManager.shared

    override func viewDidLoad() {
        super.viewDidLoad()
        registerForPreferredContentSizeCategoryChanges { $0.updateSize() }
        chaptersTable.sectionHeaderTopPadding = 0
    }

    override func willBeAddedToPlayer() {
        updateColors()
        header.update()
        addObservers()
    }

    override func willBeRemovedFromPlayer() {
        removeAllCustomObservers()
    }

    override func themeDidChange() {
        update()
    }

    func scrollToCurrentlyPlayingChapter(animated: Bool) {
        let currentChapter = PlaybackManager.shared.currentChapters()

        guard let index = playbackManager.index(for: currentChapter) else {
            return
        }

        // scroll far enough to at least see the current chapter + a few more
        chaptersTable.scrollToRow(at: IndexPath(item: index, section: 0), at: .middle, animated: animated)
    }

    private func addObservers() {
        addCustomObserver(Constants.Notifications.episodeDurationChanged, selector: #selector(update))
        addCustomObserver(Constants.Notifications.playbackStarted, selector: #selector(update))
        addCustomObserver(Constants.Notifications.playbackPaused, selector: #selector(update))
        addCustomObserver(Constants.Notifications.playbackTrackChanged, selector: #selector(update))
        addCustomObserver(Constants.Notifications.podcastChaptersDidUpdate, selector: #selector(update))
        addCustomObserver(Constants.Notifications.podcastChapterChanged, selector: #selector(update))
        addCustomObserver(UIApplication.willEnterForegroundNotification, selector: #selector(update))
    }

    @objc private func update() {
        chaptersTable.reloadData()
        updateColors()
        header.update()
    }

    private func updateColors() {
        view.backgroundColor = PlayerColorHelper.playerBackgroundColor01()
        chaptersTable.backgroundColor = PlayerColorHelper.playerBackgroundColor01()
        header.backgroundColor = PlayerColorHelper.playerBackgroundColor01()
    }
    func updateSize() {
        /// Forces headers & cells to recalculate their heights
        chaptersTable.beginUpdates()
        chaptersTable.endUpdates()
    }
}
