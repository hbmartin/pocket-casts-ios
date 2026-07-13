import Foundation
import GRDB

public enum CustomQueryCompileError: Error, Equatable {
    case depthLimitExceeded(limit: Int)
    case groupTooLarge(limit: Int)
    case tooManyConditions(limit: Int)
    /// The (field, operator) pairing is outside `field.allowedOperators`, or the
    /// operand value shape doesn't match what the operator needs.
    case invalidCondition(field: CustomQueryField, op: CustomQueryOperator)
    case unknownEnumerationValue(field: CustomQueryField, value: String)
    case emptyList(field: CustomQueryField)
}

/// Compiles a builder-mode AST into a SQL boolean expression over the `episode`/
/// `podcast` table aliases (the shape every playlist query joins), with every
/// user-supplied value emitted as a bound `?` argument.
///
/// Identifiers (columns, enum raw values, LIKE prefixes) come exclusively from this
/// file's tables; user input can only ever bind as an argument. Compilation happens
/// at query time (see `PlaylistQueryBuilder.customRuleFragment(for:)`) so relative
/// dates resolve against a fresh `now`.
public enum CustomQueryCompiler {
    public static let maxDepth = 3
    public static let maxChildrenPerGroup = 20
    public static let maxConditions = 50

    public static func compile(root: CustomQueryNode, now: Date = Date()) throws -> (sql: String, arguments: [DatabaseValue]) {
        var conditionCount = 0
        var arguments = [DatabaseValue]()
        let sql = try compile(node: root, groupDepth: 0, conditionCount: &conditionCount, arguments: &arguments, now: now)
        return (sql, arguments)
    }

    // MARK: - Tree walk

    private static func compile(
        node: CustomQueryNode,
        groupDepth: Int,
        conditionCount: inout Int,
        arguments: inout [DatabaseValue],
        now: Date
    ) throws -> String {
        switch node {
        case .group(let group):
            let depth = groupDepth + 1
            guard depth <= maxDepth else {
                throw CustomQueryCompileError.depthLimitExceeded(limit: maxDepth)
            }
            guard group.children.count <= maxChildrenPerGroup else {
                throw CustomQueryCompileError.groupTooLarge(limit: maxChildrenPerGroup)
            }
            guard !group.children.isEmpty else {
                // The boolean identity of each combinator: an empty ALL group is
                // vacuously true, an empty ANY group matches nothing.
                return group.op == .all ? "(1)" : "(0)"
            }
            let joiner = group.op == .all ? " AND " : " OR "
            let children = try group.children.map {
                try compile(node: $0, groupDepth: depth, conditionCount: &conditionCount, arguments: &arguments, now: now)
            }
            return "(" + children.joined(separator: joiner) + ")"

        case .condition(let condition):
            conditionCount += 1
            guard conditionCount <= maxConditions else {
                throw CustomQueryCompileError.tooManyConditions(limit: maxConditions)
            }
            return try compile(condition: condition, arguments: &arguments, now: now)
        }
    }

    // MARK: - Conditions

    private static func compile(
        condition: CustomQueryCondition,
        arguments: inout [DatabaseValue],
        now: Date
    ) throws -> String {
        let field = condition.field
        let op = condition.op
        guard field.allowedOperators.contains(op) else {
            throw CustomQueryCompileError.invalidCondition(field: field, op: op)
        }

        switch field.kind {
        case .text:
            return try textCondition(field: field, op: op, value: condition.value, arguments: &arguments)
        case .number:
            return try numberCondition(field: field, op: op, value: condition.value, secondValue: condition.secondValue, arguments: &arguments)
        case .boolean:
            return try booleanCondition(field: field, op: op, value: condition.value, arguments: &arguments)
        case .date:
            return try dateCondition(field: field, op: op, value: condition.value, secondValue: condition.secondValue, arguments: &arguments, now: now)
        case .podcastList:
            return try podcastCondition(field: field, op: op, value: condition.value, arguments: &arguments)
        case .enumeration:
            return try enumerationCondition(field: field, op: op, value: condition.value, arguments: &arguments)
        }
    }

    private static func textCondition(
        field: CustomQueryField,
        op: CustomQueryOperator,
        value: CustomQueryValue?,
        arguments: inout [DatabaseValue]
    ) throws -> String {
        guard case .string(let term)? = value else {
            throw CustomQueryCompileError.invalidCondition(field: field, op: op)
        }
        let column = columnExpression(for: field)
        // All text matching is case-insensitive, matching the playlist search
        // semantics; LIKE operands reuse the shared wildcard escaping and every
        // query declares ESCAPE '\'.
        let escaped = PlaylistQueryBuilder.likeEscaped(term).uppercased()
        switch op {
        case .contains:
            arguments.append("%\(escaped)%".databaseValue)
            return "(UPPER(\(column)) LIKE ? ESCAPE '\\')"
        case .notContains:
            arguments.append("%\(escaped)%".databaseValue)
            // NULL columns count as "does not contain".
            return "(\(column) IS NULL OR UPPER(\(column)) NOT LIKE ? ESCAPE '\\')"
        case .equals:
            arguments.append(term.uppercased().databaseValue)
            return "(UPPER(\(column)) = ?)"
        case .notEquals:
            arguments.append(term.uppercased().databaseValue)
            return "(\(column) IS NULL OR UPPER(\(column)) <> ?)"
        case .startsWith:
            arguments.append("\(escaped)%".databaseValue)
            return "(UPPER(\(column)) LIKE ? ESCAPE '\\')"
        case .endsWith:
            arguments.append("%\(escaped)".databaseValue)
            return "(UPPER(\(column)) LIKE ? ESCAPE '\\')"
        default:
            throw CustomQueryCompileError.invalidCondition(field: field, op: op)
        }
    }

    private static func numberCondition(
        field: CustomQueryField,
        op: CustomQueryOperator,
        value: CustomQueryValue?,
        secondValue: CustomQueryValue?,
        arguments: inout [DatabaseValue]
    ) throws -> String {
        let column = columnExpression(for: field)

        switch op {
        case .isSet:
            return isSetExpression(for: field)
        case .isNotSet:
            return "(NOT \(isSetExpression(for: field)))"
        case .between:
            guard case .number(let lower)? = value, case .number(let upper)? = secondValue else {
                throw CustomQueryCompileError.invalidCondition(field: field, op: op)
            }
            arguments.append(lower.databaseValue)
            arguments.append(upper.databaseValue)
            return "(\(column) >= ? AND \(column) <= ?)"
        default:
            guard case .number(let number)? = value, let comparison = comparisonOperator(for: op) else {
                throw CustomQueryCompileError.invalidCondition(field: field, op: op)
            }
            arguments.append(number.databaseValue)
            return "(\(column) \(comparison) ?)"
        }
    }

    private static func booleanCondition(
        field: CustomQueryField,
        op: CustomQueryOperator,
        value: CustomQueryValue?,
        arguments: inout [DatabaseValue]
    ) throws -> String {
        guard op == .equals, case .bool(let expected)? = value else {
            throw CustomQueryCompileError.invalidCondition(field: field, op: op)
        }
        switch field {
        case .starred:
            arguments.append((expected ? 1 : 0).databaseValue)
            return "(episode.keepEpisode = ?)"
        case .podcastSubscribed:
            // LEFT JOIN: a missing podcast row counts as not subscribed.
            if expected {
                return "(podcast.subscribed IS NOT NULL AND podcast.subscribed <> 0)"
            }
            return "(podcast.subscribed IS NULL OR podcast.subscribed = 0)"
        default:
            throw CustomQueryCompileError.invalidCondition(field: field, op: op)
        }
    }

    private static func dateCondition(
        field: CustomQueryField,
        op: CustomQueryOperator,
        value: CustomQueryValue?,
        secondValue: CustomQueryValue?,
        arguments: inout [DatabaseValue],
        now: Date
    ) throws -> String {
        let column = columnExpression(for: field)

        switch op {
        case .isSet:
            return isSetExpression(for: field)
        case .isNotSet:
            return "(NOT \(isSetExpression(for: field)))"
        case .inLastDays:
            // The builder UI's bridge emits .date(.relativeDays(n)); .number(n)
            // is the compiler-native shape. Both must compile — rejecting one
            // nulls the entire playlist to "(0)".
            let days: Int
            switch value {
            case .number(let number)?:
                days = Int(number)
            case .date(.relativeDays(let relativeDays))?:
                days = relativeDays
            default:
                throw CustomQueryCompileError.invalidCondition(field: field, op: op)
            }
            let cutoff = CustomQueryDateValue.relativeDays(days).resolved(now: now)
            arguments.append(cutoff.databaseValue)
            return "(\(column) > ?)"
        case .before:
            guard case .date(let date)? = value else {
                throw CustomQueryCompileError.invalidCondition(field: field, op: op)
            }
            arguments.append(date.resolved(now: now).databaseValue)
            return "(\(column) < ?)"
        case .after:
            guard case .date(let date)? = value else {
                throw CustomQueryCompileError.invalidCondition(field: field, op: op)
            }
            arguments.append(date.resolved(now: now).databaseValue)
            return "(\(column) > ?)"
        case .between:
            guard case .date(let lower)? = value, case .date(let upper)? = secondValue else {
                throw CustomQueryCompileError.invalidCondition(field: field, op: op)
            }
            arguments.append(lower.resolved(now: now).databaseValue)
            arguments.append(upper.resolved(now: now).databaseValue)
            return "(\(column) >= ? AND \(column) <= ?)"
        default:
            throw CustomQueryCompileError.invalidCondition(field: field, op: op)
        }
    }

    private static func podcastCondition(
        field: CustomQueryField,
        op: CustomQueryOperator,
        value: CustomQueryValue?,
        arguments: inout [DatabaseValue]
    ) throws -> String {
        guard case .stringList(let uuids)? = value else {
            throw CustomQueryCompileError.invalidCondition(field: field, op: op)
        }
        guard !uuids.isEmpty else {
            throw CustomQueryCompileError.emptyList(field: field)
        }
        arguments.append(contentsOf: uuids.map { $0.databaseValue })
        let placeholders = DBUtils.placeholders(amount: uuids.count)
        let keyword = op == .isIn ? "IN" : "NOT IN"
        return "(episode.podcastUuid \(keyword) (\(placeholders)))"
    }

    private static func enumerationCondition(
        field: CustomQueryField,
        op: CustomQueryOperator,
        value: CustomQueryValue?,
        arguments: inout [DatabaseValue]
    ) throws -> String {
        guard case .stringList(let identifiers)? = value else {
            throw CustomQueryCompileError.invalidCondition(field: field, op: op)
        }
        guard !identifiers.isEmpty else {
            throw CustomQueryCompileError.emptyList(field: field)
        }
        for identifier in identifiers where !field.enumerationValues.contains(identifier) {
            throw CustomQueryCompileError.unknownEnumerationValue(field: field, value: identifier)
        }

        if field == .mediaType {
            // fileType is a MIME string; media kinds compile to fixed compiler-owned
            // LIKE prefixes (no interpolation, no bound values).
            let prefixMatches: [String: String] = [
                "audio": "episode.fileType LIKE 'audio%'",
                "video": "episode.fileType LIKE 'video%'"
            ]
            let matches = identifiers.compactMap { prefixMatches[$0] }.joined(separator: " OR ")
            return op == .isIn ? "(\(matches))" : "(NOT (\(matches)))"
        }

        let column = columnExpression(for: field)
        switch field {
        case .playingStatus:
            let statuses: [String: PlayingStatus] = ["notPlayed": .notPlayed, "inProgress": .inProgress, "completed": .completed]
            arguments.append(contentsOf: identifiers.compactMap { statuses[$0]?.rawValue.databaseValue })
        case .downloadStatus:
            let statuses: [String: DownloadStatus] = [
                "notDownloaded": .notDownloaded,
                "queued": .queued,
                "downloading": .downloading,
                "downloadFailed": .downloadFailed,
                "downloaded": .downloaded,
                "waitingForWifi": .waitingForWifi
            ]
            arguments.append(contentsOf: identifiers.compactMap { statuses[$0]?.rawValue.databaseValue })
        case .episodeType:
            // Identifiers double as the stored feed values ("full"/"trailer"/"bonus").
            arguments.append(contentsOf: identifiers.map { $0.databaseValue })
        default:
            throw CustomQueryCompileError.invalidCondition(field: field, op: op)
        }

        let placeholders = DBUtils.placeholders(amount: identifiers.count)
        let keyword = op == .isIn ? "IN" : "NOT IN"
        return "(\(column) \(keyword) (\(placeholders)))"
    }

    // MARK: - Field tables

    /// The SQL expression each field reads. `episode`/`podcast` are the aliases every
    /// playlist query shape provides (see `PlaylistQueryBuilder.fragment`).
    private static func columnExpression(for field: CustomQueryField) -> String {
        switch field {
        case .episodeTitle: return "episode.title"
        case .episodeDescription: return "episode.episodeDescription"
        case .podcastTitle: return "podcast.title"
        case .podcast: return "episode.podcastUuid"
        case .duration: return "episode.duration"
        case .playedUpTo: return "episode.playedUpTo"
        case .fileSize: return "episode.sizeInBytes"
        case .seasonNumber: return "episode.seasonNumber"
        case .episodeNumber: return "episode.episodeNumber"
        case .progressPercent:
            return "(CASE WHEN episode.duration > 0 THEN (episode.playedUpTo * 100.0 / episode.duration) ELSE 0 END)"
        case .playingStatus: return "episode.playingStatus"
        case .downloadStatus: return "episode.episodeStatus"
        case .episodeType: return "episode.episodeType"
        case .mediaType: return "episode.fileType"
        case .starred: return "episode.keepEpisode"
        case .podcastSubscribed: return "podcast.subscribed"
        case .publishedDate: return "episode.publishedDate"
        case .addedDate: return "episode.addedDate"
        case .lastPlayedDate: return "episode.lastPlaybackInteractionDate"
        }
    }

    /// What "has a value" means per field: season/episode numbers use the -1
    /// sentinel, size/duration/progress use 0, and dates are nullable REAL columns.
    private static func isSetExpression(for field: CustomQueryField) -> String {
        let column = columnExpression(for: field)
        switch field {
        case .seasonNumber, .episodeNumber:
            return "(\(column) >= 0)"
        case .publishedDate, .addedDate, .lastPlayedDate:
            return "(\(column) IS NOT NULL AND \(column) > 0)"
        default:
            return "(\(column) > 0)"
        }
    }

    private static func comparisonOperator(for op: CustomQueryOperator) -> String? {
        switch op {
        case .equals: return "="
        case .notEquals: return "<>"
        case .greaterThan: return ">"
        case .greaterThanOrEqual: return ">="
        case .lessThan: return "<"
        case .lessThanOrEqual: return "<="
        default: return nil
        }
    }
}
