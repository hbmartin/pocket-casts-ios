import Foundation

/// The v1 custom-playlist field catalog.
///
/// The UI reads this catalog to drive its field/operator/value pickers; the compiler
/// (`CustomQueryCompiler`) is the only source of SQL identifiers, so user-supplied text
/// never reaches identifier position — only bound `?` arguments.
public enum CustomQueryField: String, Codable, CaseIterable, Sendable {
    // Text
    case episodeTitle
    case episodeDescription
    case podcastTitle

    // Podcast membership (uuids picked from the user's podcasts)
    case podcast

    // Numbers
    case duration
    case playedUpTo
    case fileSize
    case seasonNumber
    case episodeNumber
    case progressPercent

    // Enumerations
    case playingStatus
    case downloadStatus
    case episodeType
    case mediaType

    // Booleans
    case starred
    case podcastSubscribed

    // Dates
    case publishedDate
    case addedDate
    case lastPlayedDate

    // Transcript. Note on forward compatibility: builds that predate a field fail
    // to decode envelopes containing it (unknown raw value), so
    // `CustomPlaylistQuery(envelopeJSON:)` returns nil there and the playlist
    // renders empty — adding a field needs no envelope version bump.
    case transcriptMentions

    /// The value shape a field expects; drives both the UI's value editors and the
    /// compiler's operator validation.
    public enum Kind: Sendable, Equatable {
        case text
        case number
        case boolean
        case date
        case podcastList
        case enumeration
        case transcript
    }

    public var kind: Kind {
        switch self {
        case .episodeTitle, .episodeDescription, .podcastTitle:
            return .text
        case .podcast:
            return .podcastList
        case .duration, .playedUpTo, .fileSize, .seasonNumber, .episodeNumber, .progressPercent:
            return .number
        case .playingStatus, .downloadStatus, .episodeType, .mediaType:
            return .enumeration
        case .starred, .podcastSubscribed:
            return .boolean
        case .publishedDate, .addedDate, .lastPlayedDate:
            return .date
        case .transcriptMentions:
            return .transcript
        }
    }

    /// The operators the UI may offer for this field. The compiler rejects any other
    /// (field, operator) pairing with `CustomQueryCompileError.invalidCondition`.
    public var allowedOperators: [CustomQueryOperator] {
        switch kind {
        case .text:
            return [.contains, .notContains, .equals, .notEquals, .startsWith, .endsWith]
        case .number:
            return [.equals, .notEquals, .greaterThan, .greaterThanOrEqual, .lessThan, .lessThanOrEqual, .between, .isSet, .isNotSet]
        case .boolean:
            return [.equals]
        case .date:
            return [.inLastDays, .before, .after, .between, .isSet, .isNotSet]
        case .podcastList:
            return [.isIn, .notIn]
        case .enumeration:
            return [.isIn, .notIn]
        case .transcript:
            // Positive-only by design: the transcript index only covers episodes
            // whose transcripts were fetched or generated, so "does not mention"
            // would match every unindexed episode.
            return [.mentions]
        }
    }

    /// Identifiers of the selectable values for enumeration fields (empty for the
    /// rest). Presentation labels live in the app layer; these identifiers are what
    /// the envelope stores and the compiler maps to column values.
    public var enumerationValues: [String] {
        switch self {
        case .playingStatus:
            return ["notPlayed", "inProgress", "completed"]
        case .downloadStatus:
            return ["notDownloaded", "queued", "downloading", "downloadFailed", "downloaded", "waitingForWifi"]
        case .episodeType:
            return ["full", "trailer", "bonus"]
        case .mediaType:
            return ["audio", "video"]
        default:
            return []
        }
    }
}

/// The v1 operator vocabulary. `between` reads `value` (lower bound) and
/// `secondValue` (upper bound); `isSet`/`isNotSet` take no operand.
public enum CustomQueryOperator: String, Codable, CaseIterable, Sendable {
    // Text
    case contains
    case notContains
    case equals
    case notEquals
    case startsWith
    case endsWith

    // Numbers / dates
    case greaterThan
    case greaterThanOrEqual
    case lessThan
    case lessThanOrEqual
    case between
    case isSet
    case isNotSet

    // Lists / enumerations
    case isIn = "in"
    case notIn

    // Dates
    case inLastDays
    case before
    case after

    // Transcript
    case mentions
}
