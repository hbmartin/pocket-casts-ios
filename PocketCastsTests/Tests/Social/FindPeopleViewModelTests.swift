@testable import PocketCastsServer
import XCTest

@testable import podcasts

@MainActor
final class FindPeopleViewModelTests: XCTestCase {
    func testEmptySearchIsAValidNoResultsState() async {
        let model = FindPeopleViewModel(searchPeople: { _ in .success([]) })

        await model.performSearch(query: "nobody")

        XCTAssertTrue(model.searchedWithNoResults)
        XCTAssertNil(model.loadError)
    }

    func testFailedSearchIsNotPresentedAsNoResults() async {
        let model = FindPeopleViewModel(searchPeople: { _ in .failure(.requestFailed(statusCode: 503)) })

        await model.performSearch(query: "offline")

        XCTAssertFalse(model.searchedWithNoResults)
        XCTAssertNotNil(model.loadError)
    }

    func testSuggestionFailureSurfacesErrorWhileSuccessfulCuratorsRemain() async {
        let curator = SocialProfileSummary(handle: "curator", displayName: "Curator")
        let model = FindPeopleViewModel(
            isJoined: { true },
            loadPeopleSuggestions: { .failure(.invalidResponse) },
            loadCurators: { .success([curator]) }
        )

        await model.loadSuggestions()

        XCTAssertEqual(model.curators, [curator])
        XCTAssertTrue(model.suggestions.isEmpty)
        XCTAssertNotNil(model.loadError)
    }

    func testContactMatchFailureIsNotPresentedAsAnEmptySuccess() async {
        let model = FindPeopleViewModel(
            matchContactHashes: { _ in .failure(.requestFailed(statusCode: 500)) }
        )

        await model.loadContactMatches([SocialContactHash(kind: .email, hash: "hash")])

        XCTAssertTrue(model.contactMatches.isEmpty)
        XCTAssertNotNil(model.loadError)
    }

    func testContactKindsMapOnlyToSupportedWireValues() {
        XCTAssertEqual(SocialContactHash.Kind.email.apiValue, .email)
        XCTAssertEqual(SocialContactHash.Kind.phone.apiValue, .phone)
    }
}
