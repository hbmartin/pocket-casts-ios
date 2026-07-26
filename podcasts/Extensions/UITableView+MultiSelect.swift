import Foundation

extension UITableView {
    func previousIndexPath(from indexPath: IndexPath) -> IndexPath? {
        // Case 1: There is a previous row in the same section
        if indexPath.row > 0 {
            return IndexPath(row: indexPath.row - 1, section: indexPath.section)
        }

        // Case 2: We’re at the first row of a section, try the previous section
        let currentSection = indexPath.section
        guard currentSection > 0 else {
            // We’re at section 0, row 0 — no previous
            return nil
        }

        // Find the last non-empty previous section
        var previousSection = currentSection - 1
        while previousSection >= 0 {
            let rows = numberOfRows(inSection: previousSection)
            if rows > 0 {
                return IndexPath(row: rows - 1, section: previousSection)
            }
            previousSection -= 1
        }

        // No previous section with rows
        return nil
    }

    func nextIndexPath(from indexPath: IndexPath) -> IndexPath? {
        let currentSection = indexPath.section
        let currentRow = indexPath.row

        // Case 1: There is a next row in the same section
        let rowsInCurrentSection = numberOfRows(inSection: currentSection)
        if currentRow + 1 < rowsInCurrentSection {
            return IndexPath(row: currentRow + 1, section: currentSection)
        }

        // Case 2: Move to the first row of the next non-empty section
        let lastSectionIndex = numberOfSections - 1
        guard currentSection < lastSectionIndex else {
            // We’re at the last section already — no next
            return nil
        }

        var nextSection = currentSection + 1
        while nextSection <= lastSectionIndex {
            let rows = numberOfRows(inSection: nextSection)
            if rows > 0 {
                return IndexPath(row: 0, section: nextSection)
            }
            nextSection += 1
        }

        // No subsequent section with rows
        return nil
    }

    func selectIndexPath(_ indexPath: IndexPath) {
        selectRow(at: indexPath, animated: false, scrollPosition: .none)
        delegate?.tableView?(self, didSelectRowAt: indexPath)
    }

    func deselectIndexPath(_ indexPath: IndexPath) {
        deselectRow(at: indexPath, animated: false)
        delegate?.tableView?(self, didDeselectRowAt: indexPath)
    }

    /// The last index path in the table that actually has a row, walking back
    /// over trailing empty sections. nil when the table has no rows at all.
    func lastPopulatedIndexPath() -> IndexPath? {
        var section = numberOfSections - 1
        while section >= 0 {
            let rows = numberOfRows(inSection: section)
            if rows > 0 {
                return IndexPath(row: rows - 1, section: section)
            }
            section -= 1
        }
        return nil
    }

    func selectAll() {
        guard let lastIndexPath = lastPopulatedIndexPath() else { return }

        selectAllFrom(fromIndexPath: IndexPath(row: 0, section: 0), toIndexPath: lastIndexPath)
    }

    func deselectAll() {
        indexPathsForSelectedRows?.forEach {
            deselectRow(at: $0, animated: true)
            delegate?.tableView?(self, didDeselectRowAt: $0)
        }
    }

    func selectAllAbove(fromIndexPath: IndexPath, to indexPath: IndexPath) {
        selectAllFrom(fromIndexPath: fromIndexPath, toIndexPath: indexPath)
    }

    func selectAllBelow(fromIndexPath: IndexPath) {
        guard let lastIndexPath = lastPopulatedIndexPath() else { return }
        selectAllFrom(fromIndexPath: fromIndexPath, toIndexPath: lastIndexPath)
    }

    func selectAllFrom(fromIndexPath: IndexPath, toIndexPath: IndexPath) {
        guard fromIndexPath.section <= toIndexPath.section else { return }
        for section in fromIndexPath.section ... toIndexPath.section {
            let startingRow = fromIndexPath.section == section ? fromIndexPath.row : 0
            let endingRow = toIndexPath.section == section ? toIndexPath.row : numberOfRows(inSection: section) - 1
            // empty sections (endingRow == -1) have nothing to select
            guard startingRow <= endingRow else { continue }
            for row in startingRow ... endingRow {
                let thisPath = IndexPath(row: row, section: section)
                selectIndexPath(thisPath)
            }
        }
    }

    func deselectAllAbove(fromIndexPath: IndexPath, to indexPath: IndexPath) {
        deselectAllFrom(fromIndexPath: fromIndexPath, toIndexPath: indexPath)
    }

    func deselectAllBelow(indexPath: IndexPath) {
        guard let lastIndexPath = lastPopulatedIndexPath() else { return }
        deselectAllFrom(fromIndexPath: indexPath, toIndexPath: lastIndexPath)
    }

    func deselectAllFrom(fromIndexPath: IndexPath, toIndexPath: IndexPath) {
        guard fromIndexPath.section <= toIndexPath.section else { return }
        for section in fromIndexPath.section ... toIndexPath.section {
            let startingRow = fromIndexPath.section == section ? fromIndexPath.row : 0
            let endingRow = toIndexPath.section == section ? toIndexPath.row : numberOfRows(inSection: section) - 1
            // empty sections (endingRow == -1) have nothing to deselect
            guard startingRow <= endingRow else { continue }
            for row in startingRow ... endingRow {
                let thisPath = IndexPath(row: row, section: section)
                deselectIndexPath(thisPath)
            }
        }
    }

    func allAboveAreSelected(fromIndexPath: IndexPath, to indexPath: IndexPath) -> Bool {
        areSelected(fromIndexPath: fromIndexPath, toIndexPath: indexPath)
    }

    func allBelowAreSelected(indexPath: IndexPath) -> Bool {
        guard let lastIndexPath = lastPopulatedIndexPath() else { return false }
        return areSelected(fromIndexPath: indexPath, toIndexPath: lastIndexPath)
    }

    func areSelected(
        fromIndexPath: IndexPath,
        toIndexPath: IndexPath
    ) -> Bool {
        guard fromIndexPath.section <= toIndexPath.section else { return true }
        for section in fromIndexPath.section ... toIndexPath.section {
            let startingRow = fromIndexPath.section == section ? fromIndexPath.row : 0
            let endingRow = toIndexPath.section == section ? toIndexPath.row : numberOfRows(inSection: section) - 1
            // empty sections (endingRow == -1) are vacuously selected
            guard startingRow <= endingRow else { continue }
            for row in startingRow ... endingRow {
                let thisPath = IndexPath(row: row, section: section)
                if indexPathsForSelectedRows?.contains(thisPath) != true {
                    return false
                }
            }
        }
        return true
    }

    // Returns the first index path in the table, excluding any cells matching the provided types
    func firstIndexPath(
        section: Int,
        excludingCellTypes: [UITableViewCell.Type]? = nil
    ) -> IndexPath? {
        guard numberOfSections > 0 else { return nil }
        return firstIndexPath(from: IndexPath(row: 0, section: section), excludingCellTypes: excludingCellTypes)
    }

    // Returns the first index path starting from a given index path (inclusive),
    // excluding any cells matching the provided types
    func firstIndexPath(
        from startIndexPath: IndexPath,
        excludingCellTypes: [UITableViewCell.Type]?
    ) -> IndexPath? {
        guard numberOfSections > 0 else { return nil }

        let lastSection = numberOfSections - 1
        var section = startIndexPath.section
        while section <= lastSection {
            let rows = numberOfRows(inSection: section)
            if rows > 0 {
                let startRow = (section == startIndexPath.section) ? startIndexPath.row : 0
                var row = startRow
                while row < rows {
                    let path = IndexPath(row: row, section: section)
                    if let types = excludingCellTypes, !types.isEmpty,
                       let cell = self.cellForRow(at: path),
                       types.contains(where: { cell.isKind(of: $0) }) {
                        // skip excluded types
                    } else {
                        return path
                    }
                    row += 1
                }
            }
            section += 1
        }
        return nil
    }
}
