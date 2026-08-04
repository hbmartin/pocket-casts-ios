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

    // MARK: - uniqueExactMatch

    func testUniqueExactMatchFoldsCaseAndDiacritics() {
        let match = ServerPerson.uniqueExactMatch(
            displayName: "Beyoncé Knowles",
            in: [ServerPerson(id: 1, displayName: "beyonce knowles"),
                 ServerPerson(id: 2, displayName: "Beyond Knowledge")]
        )

        XCTAssertEqual(match?.id, 1, "an exact folded match resolves despite case and diacritic differences")
    }

    func testUniqueExactMatchRejectsPrefixOnlyResults() {
        let match = ServerPerson.uniqueExactMatch(
            displayName: "John Smit",
            in: [ServerPerson(id: 1, displayName: "John Smithers")]
        )

        XCTAssertNil(match, "a prefix-only search result is a different person")
    }

    func testUniqueExactMatchReturnsNilForEmptyResults() {
        XCTAssertNil(ServerPerson.uniqueExactMatch(displayName: "Ada Lovelace", in: []))
    }

    func testUniqueExactMatchRejectsAmbiguousDuplicateNames() {
        let match = ServerPerson.uniqueExactMatch(
            displayName: "Alex Chen",
            in: [ServerPerson(id: 1, displayName: "Alex Chen"),
                 ServerPerson(id: 2, displayName: "alex chen")]
        )

        XCTAssertNil(match, "two exact matches can't be told apart — following either could bind the wrong person")
    }
}
