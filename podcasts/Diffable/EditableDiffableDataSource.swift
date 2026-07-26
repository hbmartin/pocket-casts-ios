import UIKit

/// `UITableViewDiffableDataSource` answers `false` to `tableView(_:canEditRowAt:)`,
/// unlike the classic `UITableViewDataSource` default of `true`. The multi-select
/// editing flows rely on rows being editable, so restore that default.
final class EditableDiffableDataSource<SectionIdentifierType: Hashable & Sendable, ItemIdentifierType: Hashable & Sendable>: UITableViewDiffableDataSource<SectionIdentifierType, ItemIdentifierType> {
    override func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        true
    }
}
