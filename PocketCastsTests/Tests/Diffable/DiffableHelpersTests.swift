import UIKit
import XCTest

@testable import podcasts

final class DiffableHelpersTests: XCTestCase {
    func testSnapshotPreservesSectionAndItemOrder() {
        let snapshot = DiffableHelpers.snapshot(sections: [
            (section: "A", items: ["1", "2"]),
            (section: "B", items: ["3"])
        ])

        XCTAssertEqual(snapshot.sectionIdentifiers, ["A", "B"])
        XCTAssertEqual(snapshot.itemIdentifiers(inSection: "A"), ["1", "2"])
        XCTAssertEqual(snapshot.itemIdentifiers(inSection: "B"), ["3"])
    }

    /// Duplicate item identifiers crash apply(); the first occurrence wins.
    func testSnapshotDropsDuplicateItems() {
        let snapshot = DiffableHelpers.snapshot(sections: [
            (section: "A", items: ["1", "2", "1"]),
            (section: "B", items: ["2", "4"])
        ])

        XCTAssertEqual(snapshot.itemIdentifiers(inSection: "A"), ["1", "2"])
        XCTAssertEqual(snapshot.itemIdentifiers(inSection: "B"), ["4"])
    }

    /// Duplicate section identifiers also crash apply(); their items merge into
    /// the first occurrence.
    func testSnapshotMergesDuplicateSections() {
        let snapshot = DiffableHelpers.snapshot(sections: [
            (section: "A", items: ["1"]),
            (section: "A", items: ["2"])
        ])

        XCTAssertEqual(snapshot.sectionIdentifiers, ["A"])
        XCTAssertEqual(snapshot.itemIdentifiers(inSection: "A"), ["1", "2"])
    }

    func testSnapshotWithEmptySectionKeepsSection() {
        let snapshot = DiffableHelpers.snapshot(sections: [
            (section: "root", items: [String]()),
            (section: "group", items: ["1"])
        ])

        XCTAssertEqual(snapshot.sectionIdentifiers, ["root", "group"])
        XCTAssertEqual(snapshot.itemIdentifiers(inSection: "root"), [])
    }

    /// Only identifiers present in both maps with differing fingerprints are
    /// reconfigure candidates — inserts and deletes are the diff's job.
    func testChangedIDsReturnsOnlySurvivingChangedIdentifiers() {
        let old = ["a": 1, "b": 2, "c": 3]
        let new = ["a": 1, "b": 5, "d": 9]

        XCTAssertEqual(DiffableHelpers.changedIDs(old: old, new: new), ["b"])
    }

    func testChangedIDsEmptyWhenNothingChanged() {
        let fingerprints = ["a": 1, "b": 2]

        XCTAssertTrue(DiffableHelpers.changedIDs(old: fingerprints, new: fingerprints).isEmpty)
        XCTAssertTrue(DiffableHelpers.changedIDs(old: [:], new: fingerprints).isEmpty)
        XCTAssertTrue(DiffableHelpers.changedIDs(old: fingerprints, new: [:]).isEmpty)
    }
}
