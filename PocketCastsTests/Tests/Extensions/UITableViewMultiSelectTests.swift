import UIKit
import XCTest

@testable import podcasts

/// Regression tests for the multi-select index-path helpers, which used to
/// build `0 ... count - 1` ClosedRanges that trapped whenever a section had
/// zero rows (reachable on the Files screen: every upload in a subfolder
/// leaves the storage-header section empty, and Select All crashed).
final class UITableViewMultiSelectTests: XCTestCase {
    private final class StubTableDataSource: NSObject, UITableViewDataSource {
        let rowCounts: [Int]

        init(rowCounts: [Int]) {
            self.rowCounts = rowCounts
        }

        func numberOfSections(in tableView: UITableView) -> Int {
            rowCounts.count
        }

        func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
            rowCounts[section]
        }

        func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
            UITableViewCell()
        }
    }

    private var dataSource: StubTableDataSource!

    private func makeTable(rowCounts: [Int]) -> UITableView {
        let table = UITableView(frame: CGRect(x: 0, y: 0, width: 320, height: 480), style: .plain)
        dataSource = StubTableDataSource(rowCounts: rowCounts)
        table.dataSource = dataSource
        table.allowsMultipleSelection = true
        table.reloadData()
        return table
    }

    private func selectedPaths(_ table: UITableView) -> Set<IndexPath> {
        Set(table.indexPathsForSelectedRows ?? [])
    }

    // MARK: - lastPopulatedIndexPath

    func testLastPopulatedIndexPathSkipsTrailingEmptySections() {
        let table = makeTable(rowCounts: [0, 3, 0])

        XCTAssertEqual(table.lastPopulatedIndexPath(), IndexPath(row: 2, section: 1))
    }

    func testLastPopulatedIndexPathNilWhenTableEmpty() {
        let table = makeTable(rowCounts: [0, 0])

        XCTAssertNil(table.lastPopulatedIndexPath())
    }

    // MARK: - selectAll

    func testSelectAllWithEmptyLeadingSection() {
        let table = makeTable(rowCounts: [0, 2])

        table.selectAll()

        XCTAssertEqual(selectedPaths(table), [IndexPath(row: 0, section: 1), IndexPath(row: 1, section: 1)])
    }

    func testSelectAllWithEmptyTrailingSection() {
        let table = makeTable(rowCounts: [2, 0])

        table.selectAll()

        XCTAssertEqual(selectedPaths(table), [IndexPath(row: 0, section: 0), IndexPath(row: 1, section: 0)])
    }

    func testSelectAllWithOnlyEmptySectionsDoesNothing() {
        let table = makeTable(rowCounts: [0, 0])

        table.selectAll()

        XCTAssertTrue(selectedPaths(table).isEmpty)
    }

    func testSelectAllSkipsEmptyMiddleSection() {
        let table = makeTable(rowCounts: [1, 0, 2])

        table.selectAll()

        XCTAssertEqual(selectedPaths(table), [
            IndexPath(row: 0, section: 0),
            IndexPath(row: 0, section: 2),
            IndexPath(row: 1, section: 2)
        ])
    }

    // MARK: - selectAllBelow / deselectAllBelow

    func testSelectAllBelowWithTrailingEmptySection() {
        let table = makeTable(rowCounts: [2, 0])

        table.selectAllBelow(fromIndexPath: IndexPath(row: 1, section: 0))

        XCTAssertEqual(selectedPaths(table), [IndexPath(row: 1, section: 0)])
    }

    func testDeselectAllBelowWithTrailingEmptySection() {
        let table = makeTable(rowCounts: [2, 0])
        table.selectAll()

        table.deselectAllBelow(indexPath: IndexPath(row: 0, section: 0))

        XCTAssertTrue(selectedPaths(table).isEmpty)
    }

    // MARK: - areSelected / allBelowAreSelected

    func testAreSelectedTreatsEmptySectionsAsVacuouslySelected() {
        let table = makeTable(rowCounts: [0, 1])
        table.selectRow(at: IndexPath(row: 0, section: 1), animated: false, scrollPosition: .none)

        XCTAssertTrue(table.areSelected(fromIndexPath: IndexPath(row: 0, section: 0), toIndexPath: IndexPath(row: 0, section: 1)))
    }

    func testAllBelowAreSelectedWithTrailingEmptySection() {
        let table = makeTable(rowCounts: [2, 0])
        table.selectAll()

        XCTAssertTrue(table.allBelowAreSelected(indexPath: IndexPath(row: 0, section: 0)))
    }

    func testAllBelowAreSelectedFalseWhenRowUnselected() {
        let table = makeTable(rowCounts: [2, 0])
        table.selectRow(at: IndexPath(row: 0, section: 0), animated: false, scrollPosition: .none)

        XCTAssertFalse(table.allBelowAreSelected(indexPath: IndexPath(row: 0, section: 0)))
    }
}
