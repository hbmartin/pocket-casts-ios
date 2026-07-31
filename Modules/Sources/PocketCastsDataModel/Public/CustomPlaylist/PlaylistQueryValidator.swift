import Foundation
import GRDB
import PocketCastsUtils

/// Why a SQL-mode fragment was rejected. Surfaced to the editor UI via
/// `DataManager.validateCustomQueryFragment(_:)`.
public enum CustomQueryValidationError: Error, Equatable, Sendable {
    case empty
    case tooLong(limit: Int)
    case containsPlaceholders
    case syntax(message: String)
    case multipleStatements
    case notReadOnly
    case executionFailed(message: String)
}

/// Save-time gate for SQL-mode custom playlist fragments. The only path by which
/// user-entered SQL may reach the database:
///
/// 1. Trim; reject empty; cap at `maxFragmentLength` characters.
/// 2. Reject `?`/`:name`/`$name`/`@name` placeholders — SQL mode is zero-argument,
///    so a placeholder could otherwise reach statement execution with no bound value.
/// 3. Wrap the fragment in the exact `.episodeCount` query shape the runtime uses and
///    prepare it: syntax errors and multi-statement smuggling
///    (`1=1); DROP TABLE ...`) both fail here.
/// 4. Assert the prepared statement is read-only (defense in depth; the wrap already
///    confines the fragment to expression position inside a SELECT).
/// 5. Trial-execute the count on a read connection, catching runtime-only errors.
///    Slow fragments (> `slowQueryWarningThreshold`) log a warning but still pass.
///
/// Call off the main thread: step 5 runs a real query over the episode table.
enum PlaylistQueryValidator {
    static let maxFragmentLength = 4000
    static let slowQueryWarningThreshold: TimeInterval = 0.5

    static func validate(fragment: String, dbQueue: GRDBQueue) -> Result<Int, CustomQueryValidationError> {
        let trimmed = fragment.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .failure(.empty)
        }
        guard trimmed.count <= maxFragmentLength else {
            return .failure(.tooLong(limit: maxFragmentLength))
        }
        guard !containsPlaceholders(trimmed) else {
            return .failure(.containsPlaceholders)
        }

        // The exact `.episodeCount` shape custom playlists execute at runtime,
        // including both the SQL-mode rule wrapper and combined WHERE wrapper.
        let countLiteral = countFragment(for: trimmed)

        do {
            return try dbQueue.dbPool.read { db -> Result<Int, CustomQueryValidationError> in
                let built: (sql: String, arguments: StatementArguments)
                do {
                    built = try countLiteral.build(db)
                } catch {
                    return .failure(.syntax(message: databaseErrorMessage(error)))
                }

                let statement: Statement
                switch prepareReadOnlyStatement(sql: built.sql, db: db) {
                case .success(let prepared):
                    statement = prepared
                case .failure(let error):
                    return .failure(error)
                }

                do {
                    try statement.setArguments(built.arguments)
                    let start = DispatchTime.now()
                    let count = try Int.fetchOne(statement) ?? 0
                    let elapsed = TimeInterval(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000_000
                    if elapsed > slowQueryWarningThreshold {
                        FileLog.shared.addMessage("PlaylistQueryValidator: custom query fragment took \(String(format: "%.2f", elapsed))s to count — accepted, but expect slow playlists")
                    }
                    return .success(count)
                } catch {
                    return .failure(.executionFailed(message: databaseErrorMessage(error)))
                }
            }
        } catch {
            return .failure(.executionFailed(message: databaseErrorMessage(error)))
        }
    }

    /// The exact runtime count shape used during validation. Kept as one entry
    /// point so parity tests fail if validation ever drifts from playlist reads.
    static func countFragment(for fragment: String) -> SQL {
        PlaylistQueryBuilder.smartCountFragment(
            shouldShowArchived: false,
            allEpisodesCount: false,
            whereFragment: PlaylistQueryBuilder.sqlModeWhereFragment(fragment)
        )
    }

    /// Prepares a single statement and asserts it cannot write. Split out so tests
    /// can exercise the read-only guard with statement shapes (e.g. `DELETE ...
    /// RETURNING`) that the expression-position wrap makes unreachable in practice.
    static func prepareReadOnlyStatement(sql: String, db: Database) -> Result<Statement, CustomQueryValidationError> {
        let statement: Statement
        do {
            statement = try db.makeStatement(sql: sql)
        } catch {
            let message = databaseErrorMessage(error)
            if let databaseError = error as? DatabaseError,
               databaseError.resultCode == .SQLITE_MISUSE || message.localizedCaseInsensitiveContains("multiple statements") {
                return .failure(.multipleStatements)
            }
            return .failure(.syntax(message: message))
        }
        guard statement.isReadonly else {
            return .failure(.notReadOnly)
        }
        return .success(statement)
    }

    /// `?` positional and `:name`/`@name`/`$name` named placeholders are rejected
    /// outright, even inside string literals — a conservative overmatch that keeps
    /// the zero-argument invariant trivially checkable.
    static func containsPlaceholders(_ fragment: String) -> Bool {
        if fragment.contains("?") {
            return true
        }
        return fragment.range(of: "[:@$][A-Za-z_][A-Za-z0-9_]*", options: .regularExpression) != nil
    }

    /// True when the fragment contains a statement separator outside of a
    /// single-quoted SQL string literal, a quoted identifier (`"…"`, `` `…` ``,
    /// `[…]`), or a SQL comment. Malformed quoted strings, quoted identifiers,
    /// and block comments also return true so the runtime re-check fails closed
    /// when a stored fragment bypassed save-time statement preparation.
    static func containsStatementSeparator(_ fragment: String) -> Bool {
        enum State {
            case sql
            case singleQuotedString
            case doubleQuotedIdentifier
            case backtickIdentifier
            case bracketIdentifier
            case lineComment
            case blockComment
        }

        let characters = Array(fragment)
        var state = State.sql
        var index = 0

        while index < characters.count {
            let character = characters[index]
            let nextCharacter = index + 1 < characters.count ? characters[index + 1] : nil

            switch state {
            case .sql:
                switch (character, nextCharacter) {
                case ("'", _):
                    state = .singleQuotedString
                case ("\"", _):
                    state = .doubleQuotedIdentifier
                case ("`", _):
                    state = .backtickIdentifier
                case ("[", _):
                    state = .bracketIdentifier
                case ("-", "-"):
                    state = .lineComment
                    index += 1
                case ("/", "*"):
                    state = .blockComment
                    index += 1
                case (";", _):
                    return true
                default:
                    break
                }
            case .singleQuotedString:
                if character == "'" {
                    if nextCharacter == "'" {
                        index += 1
                    } else {
                        state = .sql
                    }
                }
            case .doubleQuotedIdentifier:
                if character == "\"" {
                    if nextCharacter == "\"" {
                        index += 1
                    } else {
                        state = .sql
                    }
                }
            case .backtickIdentifier:
                if character == "`" {
                    if nextCharacter == "`" {
                        index += 1
                    } else {
                        state = .sql
                    }
                }
            case .bracketIdentifier:
                if character == "]" {
                    state = .sql
                }
            case .lineComment:
                // SQLite ends `--` comments only at '\n' (or end of input); a lone
                // '\r' is comment text, so treating it as a terminator would desync
                // the scanner from what SQLite actually parses.
                if character == "\n" {
                    state = .sql
                }
            case .blockComment:
                if character == "*", nextCharacter == "/" {
                    state = .sql
                    index += 1
                }
            }

            index += 1
        }

        switch state {
        case .singleQuotedString, .doubleQuotedIdentifier, .backtickIdentifier, .bracketIdentifier, .blockComment:
            return true
        case .sql, .lineComment:
            return false
        }
    }

    private static func databaseErrorMessage(_ error: Error) -> String {
        if let databaseError = error as? DatabaseError {
            return databaseError.message ?? databaseError.description
        }
        return "\(error)"
    }
}
