import XCTest
import GRDB
@testable import PocketCastsDataModel
import PocketCastsUtils

/// Exercises the SQL-mode validation pipeline end to end against a real database:
/// legitimate fragments (including subqueries) pass with a match count, and every
/// rejection class (empty, oversized, placeholders, syntax, statement smuggling,
/// non-read-only) maps to its `CustomQueryValidationError` case.
final class PlaylistQueryValidatorTests: DataManagerTestCase {

    private var dataManager: DataManager { DataManager.sharedManager }
    private var originalSharedManager: DataManager!

    override func setUpWithError() throws {
        try super.setUpWithError()
        originalSharedManager = DataManager.sharedManager
        DataManager.sharedManager = DataManager.newTestDataManager()

        let podcast = createTestPodcast(uuid: "podcast-v", title: "Validator Show", dataManager: dataManager)
        var long = createTestEpisode(uuid: "ep-long", podcast: podcast, title: "Long History Special", dataManager: dataManager)
        long.duration = 3600
        long = dataManager.save(episode: long)
        var short = createTestEpisode(uuid: "ep-short", podcast: podcast, title: "Short One", dataManager: dataManager)
        short.duration = 60
        short = dataManager.save(episode: short)
    }

    override func tearDown() {
        DataManager.sharedManager = originalSharedManager
        originalSharedManager = nil
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
            "\"a;b\" = episode.title",
            "`a;b` = episode.title",
            "[a;b] = episode.title",
            // SQLite ends a `--` comment only at '\n'; the '\r' and the ';' after it
            // are comment text.
            "episode.duration > 0 -- comment\rstill the same comment; not a separator",
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
            // The apostrophe inside the quoted identifier must not desync the
            // scanner into treating the real separator as string content.
            "\"a'b\" = 'x' ; DROP TABLE SJEpisode --'",
            // A lone '\r' does not end the comment; the '\n' does, so the ';' after
            // it is a real separator (matching SQLite's lexer).
            "1 = 1 -- comment\r 'a\n; DROP TABLE SJEpisode --'",
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
        XCTAssertTrue(PlaylistQueryValidator.containsStatementSeparator("episode.title = \"unterminated; identifier"))
        XCTAssertTrue(PlaylistQueryValidator.containsStatementSeparator("episode.title = `unterminated; identifier"))
        XCTAssertTrue(PlaylistQueryValidator.containsStatementSeparator("episode.title = [unterminated; identifier"))
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

    func testDoubleCloseStatementSmugglingIsRejected() {
        let result = dataManager.validateCustomQueryFragment("1=1)); SELECT randomblob(1);--")
        switch result {
        case .failure(.syntax), .failure(.multipleStatements):
            break
        default:
            XCTFail("Expected double-close smuggling to fail, got \(result)")
        }
    }

    func testValidatorCountShapeExactlyMatchesRuntimeSqlModeCountShape() throws {
        let featureFlags = FeatureFlagOverrideStore()
        defer { featureFlags.resetOverrides() }
        try featureFlags.override(FeatureFlag.customPlaylists, withValue: true)
        let fragment = "episode.duration > 1800"
        var playlist = EpisodeFilter()
        playlist.manual = false
        playlist.customQuery = try CustomPlaylistQuery(sql: fragment).envelopeJSON()

        let runtime = PlaylistQueryBuilder.fragment(
            clause: .episodeCount,
            for: playlist,
            episodeUuidToAdd: nil,
            searchTerm: nil,
            limit: 0,
            shouldShowArchived: false,
            sortType: nil
        )
        let validator = PlaylistQueryBuilder.smartCountFragment(
            shouldShowArchived: false,
            allEpisodesCount: false,
            whereFragment: PlaylistQueryBuilder.sqlModeWhereFragment(fragment)
        )

        try dataManager.dbQueue.dbPool.read { db in
            let runtimeBuilt = try runtime.build(db)
            let validatorBuilt = try validator.build(db)
            XCTAssertEqual(runtimeBuilt.sql, validatorBuilt.sql)
            XCTAssertEqual(String(describing: runtimeBuilt.arguments), String(describing: validatorBuilt.arguments))
        }
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
