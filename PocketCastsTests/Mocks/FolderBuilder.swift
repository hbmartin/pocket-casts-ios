import Foundation

@testable import PocketCastsDataModel

/// Creates a Folder with a random `uuid`
class FolderBuilder {
    var folder: Folder

    init() {
        folder = Folder()
        folder.uuid = NSUUID().uuidString
    }

    func with(name: String) -> Self {
        folder.name = name
        return self
    }

    func build() -> Folder {
        folder
    }
}
