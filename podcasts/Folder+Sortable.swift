import Foundation
import PocketCastsDataModel
import PocketCastsUtils

nonisolated extension Folder: @retroactive Sortable {
    public var itemUUID: String {
        uuid
    }

    public var itemTitle: String? {
        name
    }
}
