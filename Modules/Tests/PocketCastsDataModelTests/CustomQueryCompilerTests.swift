import XCTest
import GRDB
@testable import PocketCastsDataModel

/// Golden (sql, arguments) coverage for `CustomQueryCompiler`: every operator per
/// field kind, nesting, the size caps, LIKE escaping and relative-date resolution
/// with an injected `now`. These pin the compiled shapes: change them deliberately,
/// because persisted builder envelopes recompile against whatever ships here.
final class CustomQueryCompilerTests: XCTestCase {

    /// 2026-01-01 00:00:00 UTC — fixed so relative dates are deterministic.
    private let now = Date(timeIntervalSince1970: 1_767_225_600)

    private func compile(_ node: CustomQueryNode) throws -> (sql: String, arguments: [DatabaseValue]) {
        try CustomQueryCompiler.compile(root: node, now: now)
    }

    private func condition(
        _ field: CustomQueryField,
        _ op: CustomQueryOperator,
        _ value: CustomQueryValue? = nil,
        _ secondValue: CustomQueryValue? = nil
    ) -> CustomQueryNode {
        .condition(CustomQueryCondition(field: field, op: op, value: value, secondValue: secondValue))
    }

    // MARK: - Text operators

    func testTextContainsEscapesLikeWildcards() throws {
        let compiled = try compile(condition(.episodeTitle, .contains, .string("Interview 100%_\\")))
        XCTAssertEqual(compiled.sql, "(UPPER(episode.title) LIKE ? ESCAPE '\\')")
        XCTAssertEqual(compiled.arguments, ["%INTERVIEW 100\\%\\_\\\\%".databaseValue])
    }

    func testTextNotContainsTreatsNullAsNotContaining() throws {
        let compiled = try compile(condition(.podcastTitle, .notContains, .string("history")))
        XCTAssertEqual(compiled.sql, "(podcast.title IS NULL OR UPPER(podcast.title) NOT LIKE ? ESCAPE '\\')")
        XCTAssertEqual(compiled.arguments, ["%HISTORY%".databaseValue])
    }

    func testTextEqualsIsCaseInsensitive() throws {
        let compiled = try compile(condition(.episodeTitle, .equals, .string("Bonus Episode")))
        XCTAssertEqual(compiled.sql, "(UPPER(episode.title) = ?)")
        XCTAssertEqual(compiled.arguments, ["BONUS EPISODE".databaseValue])
    }

    func testTextNotEqualsIncludesNull() throws {
        let compiled = try compile(condition(.episodeDescription, .notEquals, .string("x")))
        XCTAssertEqual(compiled.sql, "(episode.episodeDescription IS NULL OR UPPER(episode.episodeDescription) <> ?)")
        XCTAssertEqual(compiled.arguments, ["X".databaseValue])
    }

    func testTextStartsWithAndEndsWithPatterns() throws {
        let starts = try compile(condition(.episodeTitle, .startsWith, .string("The_Daily")))
        XCTAssertEqual(starts.sql, "(UPPER(episode.title) LIKE ? ESCAPE '\\')")
        XCTAssertEqual(starts.arguments, ["THE\\_DAILY%".databaseValue])

        let ends = try compile(condition(.episodeTitle, .endsWith, .string("finale")))
        XCTAssertEqual(ends.arguments, ["%FINALE".databaseValue])
    }

    // MARK: - Number operators

    func testNumberComparisons() throws {
        let cases: [(CustomQueryOperator, String)] = [
            (.equals, "="),
            (.notEquals, "<>"),
            (.greaterThan, ">"),
            (.greaterThanOrEqual, ">="),
            (.lessThan, "<"),
            (.lessThanOrEqual, "<=")
        ]
        for (op, symbol) in cases {
            let compiled = try compile(condition(.duration, op, .number(1800)))
            XCTAssertEqual(compiled.sql, "(episode.duration \(symbol) ?)", "operator \(op)")
            XCTAssertEqual(compiled.arguments, [Double(1800).databaseValue], "operator \(op)")
        }
    }

    func testNumberBetweenBindsBothBounds() throws {
        let compiled = try compile(condition(.fileSize, .between, .number(1_000_000), .number(50_000_000)))
        XCTAssertEqual(compiled.sql, "(episode.sizeInBytes >= ? AND episode.sizeInBytes <= ?)")
        XCTAssertEqual(compiled.arguments, [Double(1_000_000).databaseValue, Double(50_000_000).databaseValue])
    }

    func testSeasonNumberIsSetUsesSentinel() throws {
        let isSet = try compile(condition(.seasonNumber, .isSet))
        XCTAssertEqual(isSet.sql, "(episode.seasonNumber >= 0)")
        XCTAssertTrue(isSet.arguments.isEmpty)

        let isNotSet = try compile(condition(.episodeNumber, .isNotSet))
        XCTAssertEqual(isNotSet.sql, "(NOT (episode.episodeNumber >= 0))")
    }

    func testDurationIsSetUsesZeroThreshold() throws {
        let compiled = try compile(condition(.duration, .isSet))
        XCTAssertEqual(compiled.sql, "(episode.duration > 0)")
    }

    func testProgressPercentCompilesCaseExpression() throws {
        let compiled = try compile(condition(.progressPercent, .greaterThan, .number(50)))
        XCTAssertEqual(
            compiled.sql,
            "((CASE WHEN episode.duration > 0 THEN (episode.playedUpTo * 100.0 / episode.duration) ELSE 0 END) > ?)"
        )
        XCTAssertEqual(compiled.arguments, [Double(50).databaseValue])
    }

    // MARK: - Boolean operators

    func testStarredBindsBooleanAsInteger() throws {
        let starred = try compile(condition(.starred, .equals, .bool(true)))
        XCTAssertEqual(starred.sql, "(episode.keepEpisode = ?)")
        XCTAssertEqual(starred.arguments, [1.databaseValue])

        let unstarred = try compile(condition(.starred, .equals, .bool(false)))
        XCTAssertEqual(unstarred.arguments, [0.databaseValue])
    }

    func testPodcastSubscribedHandlesMissingJoinRow() throws {
        let subscribed = try compile(condition(.podcastSubscribed, .equals, .bool(true)))
        XCTAssertEqual(subscribed.sql, "(podcast.subscribed IS NOT NULL AND podcast.subscribed <> 0)")
        XCTAssertTrue(subscribed.arguments.isEmpty)

        let unsubscribed = try compile(condition(.podcastSubscribed, .equals, .bool(false)))
        XCTAssertEqual(unsubscribed.sql, "(podcast.subscribed IS NULL OR podcast.subscribed = 0)")
    }

    // MARK: - Date operators

    func testInLastDaysResolvesAgainstInjectedNow() throws {
        let compiled = try compile(condition(.publishedDate, .inLastDays, .number(7)))
        XCTAssertEqual(compiled.sql, "(episode.publishedDate > ?)")
        let expected = now.timeIntervalSince1970 - 7 * 24 * 3600
        XCTAssertEqual(compiled.arguments, [expected.databaseValue])
    }

    func testBeforeAndAfterWithAbsoluteEpoch() throws {
        let before = try compile(condition(.addedDate, .before, .date(.epoch(1_700_000_000))))
        XCTAssertEqual(before.sql, "(episode.addedDate < ?)")
        XCTAssertEqual(before.arguments, [Double(1_700_000_000).databaseValue])

        let after = try compile(condition(.lastPlayedDate, .after, .date(.epoch(1_700_000_000))))
        XCTAssertEqual(after.sql, "(episode.lastPlaybackInteractionDate > ?)")
    }

    func testDateBetweenMixesRelativeAndAbsolute() throws {
        let compiled = try compile(condition(.publishedDate, .between, .date(.relativeDays(30)), .date(.epoch(1_767_225_600))))
        XCTAssertEqual(compiled.sql, "(episode.publishedDate >= ? AND episode.publishedDate <= ?)")
        let expectedLower = now.timeIntervalSince1970 - 30 * 24 * 3600
        XCTAssertEqual(compiled.arguments, [expectedLower.databaseValue, Double(1_767_225_600).databaseValue])
    }

    func testDateIsSetChecksNullAndEpochZero() throws {
        let compiled = try compile(condition(.lastPlayedDate, .isSet))
        XCTAssertEqual(compiled.sql, "(episode.lastPlaybackInteractionDate IS NOT NULL AND episode.lastPlaybackInteractionDate > 0)")
    }

    // MARK: - Podcast and enumeration lists

    func testPodcastInListBindsEveryUuid() throws {
        let compiled = try compile(condition(.podcast, .isIn, .stringList(["uuid-a", "uuid-b"])))
        XCTAssertEqual(compiled.sql, "(episode.podcastUuid IN (?,?))")
        XCTAssertEqual(compiled.arguments, ["uuid-a".databaseValue, "uuid-b".databaseValue])
    }

    func testPodcastNotInList() throws {
        let compiled = try compile(condition(.podcast, .notIn, .stringList(["uuid-a"])))
        XCTAssertEqual(compiled.sql, "(episode.podcastUuid NOT IN (?))")
    }

    func testPlayingStatusMapsIdentifiersToRawValues() throws {
        let compiled = try compile(condition(.playingStatus, .isIn, .stringList(["notPlayed", "inProgress"])))
        XCTAssertEqual(compiled.sql, "(episode.playingStatus IN (?,?))")
        XCTAssertEqual(compiled.arguments, [PlayingStatus.notPlayed.rawValue.databaseValue, PlayingStatus.inProgress.rawValue.databaseValue])
    }

    func testDownloadStatusMapsIdentifiersToRawValues() throws {
        let compiled = try compile(condition(.downloadStatus, .notIn, .stringList(["downloaded", "waitingForWifi"])))
        XCTAssertEqual(compiled.sql, "(episode.episodeStatus NOT IN (?,?))")
        XCTAssertEqual(compiled.arguments, [DownloadStatus.downloaded.rawValue.databaseValue, DownloadStatus.waitingForWifi.rawValue.databaseValue])
    }

    func testEpisodeTypeBindsStoredStrings() throws {
        let compiled = try compile(condition(.episodeType, .isIn, .stringList(["full", "bonus"])))
        XCTAssertEqual(compiled.sql, "(episode.episodeType IN (?,?))")
        XCTAssertEqual(compiled.arguments, ["full".databaseValue, "bonus".databaseValue])
    }

    func testMediaTypeCompilesToFixedLikePrefixes() throws {
        let audio = try compile(condition(.mediaType, .isIn, .stringList(["audio"])))
        XCTAssertEqual(audio.sql, "(episode.fileType LIKE 'audio%')")
        XCTAssertTrue(audio.arguments.isEmpty)

        let both = try compile(condition(.mediaType, .isIn, .stringList(["audio", "video"])))
        XCTAssertEqual(both.sql, "(episode.fileType LIKE 'audio%' OR episode.fileType LIKE 'video%')")

        let notVideo = try compile(condition(.mediaType, .notIn, .stringList(["video"])))
        XCTAssertEqual(notVideo.sql, "(NOT (episode.fileType LIKE 'video%'))")
    }

    // MARK: - Groups and nesting

    func testNestedAnyInsideAllJoinsWithParentheses() throws {
        let node = CustomQueryNode.group(CustomQueryGroup(op: .all, children: [
            condition(.playingStatus, .isIn, .stringList(["notPlayed"])),
            .group(CustomQueryGroup(op: .any, children: [
                condition(.episodeTitle, .contains, .string("interview")),
                condition(.duration, .greaterThan, .number(3600))
            ]))
        ]))
        let compiled = try compile(node)
        XCTAssertEqual(
            compiled.sql,
            "((episode.playingStatus IN (?)) AND ((UPPER(episode.title) LIKE ? ESCAPE '\\') OR (episode.duration > ?)))"
        )
        XCTAssertEqual(compiled.arguments, [
            PlayingStatus.notPlayed.rawValue.databaseValue,
            "%INTERVIEW%".databaseValue,
            Double(3600).databaseValue
        ])
    }

    func testEmptyGroupsCompileToBooleanIdentities() throws {
        let all = try compile(.group(CustomQueryGroup(op: .all, children: [])))
        XCTAssertEqual(all.sql, "(1)")

        let any = try compile(.group(CustomQueryGroup(op: .any, children: [])))
        XCTAssertEqual(any.sql, "(0)")
    }

    // MARK: - Caps

    func testGroupsDeeperThanMaxDepthThrow() {
        // Depth 3 (groups nested three deep) is allowed...
        let depth3 = CustomQueryNode.group(CustomQueryGroup(op: .all, children: [
            .group(CustomQueryGroup(op: .any, children: [
                .group(CustomQueryGroup(op: .all, children: [
                    condition(.starred, .equals, .bool(true))
                ]))
            ]))
        ]))
        XCTAssertNoThrow(try compile(depth3))

        // ...a fourth level is not.
        let depth4 = CustomQueryNode.group(CustomQueryGroup(op: .all, children: [
            .group(CustomQueryGroup(op: .any, children: [
                .group(CustomQueryGroup(op: .all, children: [
                    .group(CustomQueryGroup(op: .any, children: [
                        condition(.starred, .equals, .bool(true))
                    ]))
                ]))
            ]))
        ]))
        XCTAssertThrowsError(try compile(depth4)) { error in
            XCTAssertEqual(error as? CustomQueryCompileError, .depthLimitExceeded(limit: CustomQueryCompiler.maxDepth))
        }
    }

    func testGroupsWiderThanMaxChildrenThrow() {
        let children = Array(repeating: condition(.starred, .equals, .bool(true)), count: CustomQueryCompiler.maxChildrenPerGroup + 1)
        XCTAssertThrowsError(try compile(.group(CustomQueryGroup(op: .all, children: children)))) { error in
            XCTAssertEqual(error as? CustomQueryCompileError, .groupTooLarge(limit: CustomQueryCompiler.maxChildrenPerGroup))
        }
    }

    func testMoreThanMaxConditionsThrows() {
        // 3 groups x 17 leaves = 51 conditions, but each group stays within the
        // 20-child cap and the tree within the depth cap.
        let leaves = Array(repeating: condition(.starred, .equals, .bool(true)), count: 17)
        let node = CustomQueryNode.group(CustomQueryGroup(op: .all, children: [
            .group(CustomQueryGroup(op: .any, children: leaves)),
            .group(CustomQueryGroup(op: .any, children: leaves)),
            .group(CustomQueryGroup(op: .any, children: leaves))
        ]))
        XCTAssertThrowsError(try compile(node)) { error in
            XCTAssertEqual(error as? CustomQueryCompileError, .tooManyConditions(limit: CustomQueryCompiler.maxConditions))
        }
    }

    // MARK: - Invalid conditions

    func testOperatorOutsideFieldCatalogThrows() {
        XCTAssertThrowsError(try compile(condition(.duration, .contains, .string("x")))) { error in
            XCTAssertEqual(error as? CustomQueryCompileError, .invalidCondition(field: .duration, op: .contains))
        }
    }

    func testValueShapeMismatchThrows() {
        XCTAssertThrowsError(try compile(condition(.episodeTitle, .contains, .number(5)))) { error in
            XCTAssertEqual(error as? CustomQueryCompileError, .invalidCondition(field: .episodeTitle, op: .contains))
        }
        XCTAssertThrowsError(try compile(condition(.duration, .between, .number(1), nil))) { error in
            XCTAssertEqual(error as? CustomQueryCompileError, .invalidCondition(field: .duration, op: .between))
        }
    }

    func testUnknownEnumerationValueThrows() {
        XCTAssertThrowsError(try compile(condition(.playingStatus, .isIn, .stringList(["nope"])))) { error in
            XCTAssertEqual(error as? CustomQueryCompileError, .unknownEnumerationValue(field: .playingStatus, value: "nope"))
        }
    }

    func testEmptyListThrows() {
        XCTAssertThrowsError(try compile(condition(.podcast, .isIn, .stringList([])))) { error in
            XCTAssertEqual(error as? CustomQueryCompileError, .emptyList(field: .podcast))
        }
    }

    // MARK: - Envelope round-trip

    func testEnvelopeJSONRoundTripsBuilderMode() throws {
        let node = CustomQueryNode.group(CustomQueryGroup(op: .all, children: [
            condition(.publishedDate, .inLastDays, .number(14)),
            condition(.podcast, .isIn, .stringList(["uuid-a"]))
        ]))
        let envelope = CustomPlaylistQuery(root: node)
        let json = try envelope.envelopeJSON()
        let decoded = try XCTUnwrap(CustomPlaylistQuery(envelopeJSON: json))
        XCTAssertEqual(decoded, envelope)
        XCTAssertTrue(decoded.isSupported)
    }

    func testEnvelopeJSONRoundTripsSQLMode() throws {
        let envelope = CustomPlaylistQuery(sql: "episode.duration > 1800")
        let decoded = try XCTUnwrap(CustomPlaylistQuery(envelopeJSON: try envelope.envelopeJSON()))
        XCTAssertEqual(decoded.mode, .sql)
        XCTAssertEqual(decoded.sql, "episode.duration > 1800")
    }

    func testUndecodableAndUnknownEnvelopesAreRejectedGracefully() throws {
        XCTAssertNil(CustomPlaylistQuery(envelopeJSON: nil))
        XCTAssertNil(CustomPlaylistQuery(envelopeJSON: "not json"))
        XCTAssertNil(CustomPlaylistQuery(envelopeJSON: #"{"version":1,"mode":"quantum"}"#))

        // A future version decodes but reports itself unsupported.
        let future = try XCTUnwrap(CustomPlaylistQuery(envelopeJSON: #"{"version":99,"mode":"sql","sql":"1"}"#))
        XCTAssertFalse(future.isSupported)
    }
}
