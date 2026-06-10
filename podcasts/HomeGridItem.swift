import Foundation
import PocketCastsDataModel

struct HomeGridItem: Identifiable {
    let podcast: Podcast?
    let folder: Folder?

    enum ID: Hashable {
        case podcast(String)
        case folder(String)
        case empty
    }

    var id: ID {
        if let podcast {
            return .podcast(podcast.uuid)
        } else if let folder {
            return .folder(folder.uuid)
        }
        // Unreachable: both initializers guarantee a podcast or folder.
        return .empty
    }

    init(podcast: Podcast) {
        self.podcast = podcast
        folder = nil
    }

    init(folder: Folder) {
        self.folder = folder
        podcast = nil
    }
}
