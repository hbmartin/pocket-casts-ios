import XCTest

@testable import podcasts

final class SpotlightReconciliationPlanTests: XCTestCase {

    func testDeletesOnlyIdentifiersNoLongerExpected() {
        let plan = SpotlightReconciliationPlan.make(
            expected: ["episode:a", "episode:b"],
            persisted: ["episode:b", "episode:c", "highlight:h1"]
        )
        XCTAssertEqual(plan.toDelete, ["episode:c", "highlight:h1"])
        XCTAssertEqual(plan.toIndex, ["episode:a", "episode:b"], "everything expected is re-indexed to refresh attributes")
    }

    func testEmptyExpectedDeletesEverythingPersisted() {
        let plan = SpotlightReconciliationPlan.make(expected: [], persisted: ["episode:a"])
        XCTAssertEqual(plan.toDelete, ["episode:a"])
        XCTAssertTrue(plan.toIndex.isEmpty)
    }

    func testFreshInstallIndexesEverythingAndDeletesNothing() {
        let plan = SpotlightReconciliationPlan.make(expected: ["episode:a"], persisted: [])
        XCTAssertTrue(plan.toDelete.isEmpty)
        XCTAssertEqual(plan.toIndex, ["episode:a"])
    }
}
