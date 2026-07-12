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
        addCustomObserver(EpisodeDurationChanged.self) { [weak self] _ in
            self?.update()
        }
        addCustomObserver(PlaybackStarted.self) { [weak self] _ in
            self?.update()
        }
        addCustomObserver(PlaybackPaused.self) { [weak self] _ in
            self?.update()
        }
        addCustomObserver(PlaybackTrackChanged.self) { [weak self] _ in
            self?.update()
        }
        addCustomObserver(PodcastChaptersDidUpdate.self) { [weak self] _ in
            self?.update()
        }
        addCustomObserver(PodcastChapterChanged.self) { [weak self] _ in
            self?.update()
        }
        addCustomObserver(UIApplication.WillEnterForegroundMessage.self) { [weak self] _ in
            self?.update()
        }
    }

    private func update() {
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
