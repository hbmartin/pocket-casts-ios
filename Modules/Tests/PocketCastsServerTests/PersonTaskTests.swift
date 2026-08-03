@testable import PocketCastsServer
import XCTest

final class PersonTaskTests: XCTestCase {
    func testFollowCompletesWithFailureWhenTokenAcquisitionFails() {
        let task = PersonTask(request: .follow(personId: 42, unfollow: false))
        var result: Bool?
        task.completion = {
            guard case let .mutation(success) = $0 else { return }
            result = success
        }

        task.apiTokenAcquisitionFailed()

        XCTAssertEqual(result, false)
    }

    func testSearchCompletesWithNilWhenTokenAcquisitionFails() {
        let task = PersonTask(request: .search(query: "Ada"))
        var didComplete = false
        var result: [ServerPerson]?
        task.completion = {
            guard case let .persons(persons) = $0 else { return }
            didComplete = true
            result = persons
        }

        task.apiTokenAcquisitionFailed()

        XCTAssertTrue(didComplete)
        XCTAssertNil(result)
    }

    func testFollowedPersonsCompletesWithNilWhenTokenAcquisitionFails() {
        let task = PersonTask(request: .followedPersons)
        var didComplete = false
        var result: [ServerPerson]?
        task.completion = {
            guard case let .persons(persons) = $0 else { return }
            didComplete = true
            result = persons
        }

        task.apiTokenAcquisitionFailed()

        XCTAssertTrue(didComplete)
        XCTAssertNil(result)
    }
}
