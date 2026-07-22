import XCTest
import GRDB
@testable import PocketCastsDataModel

/// Exercises the SQL-mode validation pipeline end to end against a real database:
/// legitimate fragments (including subqueries) pass with a match count, and every
/// rejection class (empty, oversized, placeholders, syntax, statement smuggling,
/// non-read-only) maps to its `CustomQueryValidationError` case.
final class PlaylistQueryValidatorTests: DataManagerTestCase {

    private var dataManager: DataManager!

    override func setUpWithError() throws {
        try super.setUpWithError()
        dataManager = DataManager.newTestDataManager()

        let podcast = createTestPodcast(uuid: "podcast-v", title: "Validator Show", dataManager: dataManager)
        var long = createTestEpisode(uuid: "ep-long", podcast: podcast, title: "Long History Special", dataManager: dataManager)
        long.duration = 3600
        long = dataManager.save(episode: long)
        var short = createTestEpisode(uuid: "ep-short", podcast: podcast, title: "Short One", dataManager: dataManager)
        short.duration = 60
        short = dataManager.save(episode: short)
    }

    override func tearDown() {
        dataManager = nil
        super.tearDown()
    }

    // MARK: - Acceptance

    func testSimpleFragmentPassesAndReturnsMatchCount() throws {
        let result = dataManager.validateCustomQueryFragment("episode.duration > 1800")
        XCTAssertEqual(try result.get(), 1)
    }

    func testFragmentOverBothAliasesPasses() throws {
        let result = dataManager.validateCustomQueryFragment("episode.duration > 0 AND podcast.title LIKE '%Validator%'")
        XCTAssertEqual(try result.get(), 2)
    }

    func testSubqueryFragmentPasses() throws {
        let result = dataManager.validateCustomQueryFragment(
            "episode.uuid IN (SELECT uuid FROM SJEpisode WHERE duration > 1800)"
        )
        XCTAssertEqual(try result.get(), 1)
    }

    func testMatchAllFragmentCountsEveryEpisode() throws {
        let result = dataManager.validateCustomQueryFragment("1 = 1")
        XCTAssertEqual(try result.get(), 2)
    }

    // MARK: - Rejections

    func testEmptyAndWhitespaceFragmentsAreRejected() {
        XCTAssertEqual(dataManager.validateCustomQueryFragment(""), .failure(.empty))
        XCTAssertEqual(dataManager.validateCustomQueryFragment("   \n\t "), .failure(.empty))
    }

    func testOverLengthFragmentIsRejected() {
        let fragment = "episode.duration > " + String(repeating: "1", count: 4000)
        XCTAssertEqual(dataManager.validateCustomQueryFragment(fragment), .failure(.tooLong(limit: 4000)))
    }

    func testPlaceholdersAreRejected() {
        XCTAssertEqual(dataManager.validateCustomQueryFragment("episode.duration > ?"), .failure(.containsPlaceholders))
        XCTAssertEqual(dataManager.validateCustomQueryFragment("episode.duration > :cutoff"), .failure(.containsPlaceholders))
        XCTAssertEqual(dataManager.validateCustomQueryFragment("episode.duration > @cutoff"), .failure(.containsPlaceholders))
        XCTAssertEqual(dataManager.validateCustomQueryFragment("episode.duration > $cutoff"), .failure(.containsPlaceholders))
    }

    func testSyntaxErrorIsRejectedWithMessage() throws {
        let result = dataManager.validateCustomQueryFragment("episode.duration >>>> 5")
        guard case .failure(.syntax) = result else {
            XCTFail("Expected syntax failure, got \(result)")
            return
        }
    }

    func testUnknownColumnIsRejected() throws {
        let result = dataManager.validateCustomQueryFragment("episode.nonexistentColumn = 1")
        guard case .failure(let error) = result else {
            XCTFail("Expected failure, got \(result)")
            return
        }
        switch error {
        case .syntax, .executionFailed:
            break // prepare-time or runtime capture are both acceptable
        default:
            XCTFail("Expected syntax/executionFailed, got \(error)")
        }
    }

    func testStatementSeparatorScannerAcceptsSemicolonsInLiteralsAndComments() {
        let fragments = [
            "episode.title = 'Science; Vs'",
            "episode.title = 'It''s; complicated'",
            "episode.duration > 0 -- semicolon; and apostrophe don't alter state",
            "episode.duration > 0 /* semicolon; and apostrophe don't alter state */",
            "episode.duration > 0 -- comment;\nAND episode.title = 'It''s valid'",
        ]

        for fragment in fragments {
            XCTAssertFalse(
                PlaylistQueryValidator.containsStatementSeparator(fragment),
                "Expected a single SQL statement: \(fragment)"
            )
        }
    }

    func testStatementSeparatorScannerFindsSeparatorsAfterLiteralsAndComments() {
        let fragments = [
            "1=1; DROP TABLE SJEpisode",
            "episode.title = 'x'; DELETE FROM SJEpisode",
            "episode.title = 'It''s valid'; SELECT 2",
            "1 = 1 -- don't let this apostrophe hide the separator\n; SELECT 2",
            "1 = 1 /* don't let this apostrophe hide the separator */ ; SELECT 2",
        ]

        for fragment in fragments {
            XCTAssertTrue(
                PlaylistQueryValidator.containsStatementSeparator(fragment),
                "Expected a SQL statement separator: \(fragment)"
            )
        }
    }

    func testStatementSeparatorScannerFailsClosedForMalformedLexicalStates() {
        XCTAssertTrue(PlaylistQueryValidator.containsStatementSeparator("episode.title = 'unterminated; literal"))
        XCTAssertTrue(
            PlaylistQueryValidator.containsStatementSeparator("episode.duration > 0 /* unterminated; comment")
        )
    }

    func testLegitimateCommentsAndEscapedQuotesPassValidation() throws {
        let lineComment = "episode.duration > 0 -- semicolon; and apostrophe don't alter state\n"
        let blockComment = "episode.duration > 0 /* semicolon; and apostrophe don't alter state */"
        let escapedQuote = "episode.title = 'Long History Special' AND 'It''s; valid' != ''"

        XCTAssertEqual(
            try dataManager.validateCustomQueryFragment(lineComment).get(),
            2
        )
        XCTAssertEqual(
            try dataManager.validateCustomQueryFragment(blockComment).get(),
            2
        )
        XCTAssertEqual(
            try dataManager.validateCustomQueryFragment(escapedQuote).get(),
            1
        )
    }

    func testSeparatorAfterCommentApostropheIsRejectedByValidation() {
        let fragments = [
            "1 = 1 -- don't let this apostrophe hide the separator\n; SELECT 2",
            "1 = 1 /* don't let this apostrophe hide the separator */ ; SELECT 2",
        ]

        for fragment in fragments {
            switch dataManager.validateCustomQueryFragment(fragment) {
            case .failure(.syntax), .failure(.multipleStatements):
                break
            default:
                XCTFail("Expected statement separation to be rejected: \(fragment)")
            }
        }
    }

    func testStatementSmugglingIsRejectedAndTableSurvives() throws {
        let result = dataManager.validateCustomQueryFragment("1=1); DROP TABLE SJEpisode;--")
        switch result {
        case .failure(.syntax), .failure(.multipleStatements):
            break // the wrap leaves the smuggled `;` mid-statement: either rejection is fine
        default:
            XCTFail("Expected syntax/multipleStatements failure, got \(result)")
        }

        // The episode table is intact and still queryable.
        XCTAssertEqual(try dataManager.validateCustomQueryFragment("1 = 1").get(), 2)
    }

    func testNonReadOnlyStatementIsRejected() throws {
        // The expression-position wrap makes a non-SELECT unreachable from a fragment
        // (any DELETE in there is a syntax error), so exercise the read-only guard
        // directly with the statement shape it exists to block. Only the (Sendable)
        // error leaves the read closure; a prepared Statement must not.
        let error: CustomQueryValidationError? = try dataManager.dbQueue.dbPool.read { db in
            if case .failure(let error) = PlaylistQueryValidator.prepareReadOnlyStatement(sql: "DELETE FROM SJEpisode WHERE 1 = 1 RETURNING uuid", db: db) {
                return error
            }
            return nil
        }
        XCTAssertEqual(error, .notReadOnly)
    }

    func testDeleteReturningFragmentIsRejected() throws {
        let result = dataManager.validateCustomQueryFragment("DELETE FROM SJEpisode RETURNING uuid")
        guard case .failure(let error) = result else {
            XCTFail("Expected failure, got \(result)")
            return
        }
        switch error {
        case .syntax, .multipleStatements, .notReadOnly:
            break
        default:
            XCTFail("Expected a structural rejection, got \(error)")
        }
        XCTAssertEqual(try dataManager.validateCustomQueryFragment("1 = 1").get(), 2)
    }

    func testMultipleStatementsDetectedByPreparer() throws {
        let error: CustomQueryValidationError? = try dataManager.dbQueue.dbPool.read { db in
            if case .failure(let error) = PlaylistQueryValidator.prepareReadOnlyStatement(sql: "SELECT 1; SELECT 2", db: db) {
                return error
            }
            return nil
        }
        XCTAssertEqual(error, .multipleStatements)
    }
}
