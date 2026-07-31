@testable import PocketCastsServer
import XCTest

final class SuggestedFoldersRepairTests: XCTestCase {
    func testRepairsDuplicateNamesInventedDuplicateAndMissingUUIDs() {
        let repaired = SuggestedFoldersResponse.repaired(
            [
                "Technology": ["a", "b", "invented"],
                "technology": ["c"],
                "News": ["d", "d"],
            ],
            submittedUUIDs: ["a", "b", "c", "d", "e"],
            otherName: "Other"
        ).suggestions

        XCTAssertEqual(Set(repaired["Technology"] ?? []), ["a", "b", "c"])
        XCTAssertEqual(Set(repaired["Other"] ?? []), ["d", "e"])
        XCTAssertNil(repaired["News"])
        XCTAssertEqual(Set(repaired.values.flatMap { $0 }), ["a", "b", "c", "d", "e"])
    }

    func testMergesSmallGroupsAndCapsAtEightFolders() {
        var raw: [String: [String]] = [:]
        var submitted: [String] = []
        for index in 0 ..< 10 {
            let values = ["\(index)-a", "\(index)-b"]
            raw["Folder \(index)"] = values
            submitted.append(contentsOf: values)
        }
        raw["Tiny"] = ["tiny"]
        submitted.append("tiny")

        let repaired = SuggestedFoldersResponse.repaired(raw, submittedUUIDs: submitted, otherName: "Other").suggestions
        XCTAssertLessThanOrEqual(repaired.count, 8)
        XCTAssertEqual(Set(repaired.values.flatMap { $0 }), Set(submitted))
        XCTAssertTrue((repaired["Other"] ?? []).contains("tiny"))
    }

    func testIgnoresRepeatedUUIDsWithinOneLogicalFolder() {
        let repaired = SuggestedFoldersResponse.repaired(
            [
                "Technology": ["a", "a"],
                "technology": ["b", "b"],
            ],
            submittedUUIDs: ["a", "b"],
            otherName: "Other"
        ).suggestions

        XCTAssertEqual(repaired["Technology"], ["a", "b"])
        XCTAssertNil(repaired["Other"])
    }
}
