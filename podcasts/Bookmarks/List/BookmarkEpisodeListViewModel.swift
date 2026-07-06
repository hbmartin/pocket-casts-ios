import Combine
import PocketCastsDataModel
import SwiftUI

class BookmarkEpisodeListViewModel: BookmarkListViewModel {
    var episode: BaseEpisode? = nil {
        didSet {
            reload()
        }
    }

    convenience init(episode: BaseEpisode, bookmarkManager: BookmarkManager, sortOption: Binding<BookmarkSortOption>) {
        self.init(bookmarkManager: bookmarkManager, sortOption: sortOption)

        self.episode = episode
        reload()
    }

    override func reload() {
        guard let episode else {
            items = []
            return
        }

        items = bookmarkManager.bookmarks(for: episode, sorted: sortOption)
    }

    override func addListeners() {
        super.addListeners()

        // receive(on:) must precede the filter: the manager sends off-main and this
        // closure reads main-actor state (self.episode), which traps a main-queue
        // assertion if it runs on the sending thread.
        bookmarkManager.onBookmarkCreated
            .receive(on: DispatchQueue.main)
            .filter { [weak self] event in
                self?.episode?.uuid == event.episode
            }
            .sink { [weak self] _ in
                self?.reload()
            }
            .store(in: &cancellables)
    }
}
