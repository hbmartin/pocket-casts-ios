import Foundation
import PocketCastsDataModel
import PocketCastsUtils

/// The one place the UI touches the engine's AST shape: draft-document to
/// `CustomQueryNode` conversion (and back, for edit mode), plus the app-layer
/// display metadata for the engine's field/operator catalog (the module owns
/// identifiers and typing; presentation labels live here, per the catalog docs).

// MARK: - Draft -> AST

nonisolated extension CustomQueryDraftGroup.Match {
    var engineOperator: CustomQueryGroup.Operator {
        switch self {
        case .all: .all
        case .any: .any
        }
    }

    init(engineOperator: CustomQueryGroup.Operator) {
        switch engineOperator {
        case .all: self = .all
        case .any: self = .any
        }
    }
}

nonisolated extension CustomQueryDraftGroup {
    /// Compiles the draft group into an AST node. Empty groups and incomplete
    /// conditions are dropped; a group with nothing left returns nil.
    func queryNode() -> CustomQueryNode? {
        let childNodes = children.compactMap { child -> CustomQueryNode? in
            switch child {
            case .condition(let condition):
                condition.queryNode()
            case .group(let group):
                group.queryNode()
            }
        }
        guard !childNodes.isEmpty else { return nil }
        return .group(CustomQueryGroup(op: match.engineOperator, children: childNodes))
    }
}

nonisolated extension CustomQueryDraftCondition {
    func queryNode() -> CustomQueryNode? {
        guard isComplete else { return nil }

        var primary: CustomQueryValue?
        var secondary: CustomQueryValue?

        switch field.kind {
        case .text:
            primary = .string(value.text.trimmingCharacters(in: .whitespacesAndNewlines))
        case .number:
            switch op {
            case .isSet, .isNotSet:
                break // no operand
            case .between:
                guard let lower = Double(value.numberText), let upper = Double(value.secondNumberText) else { return nil }
                primary = .number(min(lower, upper))
                secondary = .number(max(lower, upper))
            default:
                guard let number = Double(value.numberText) else { return nil }
                primary = .number(number)
            }
        case .boolean:
            primary = .bool(value.boolValue)
        case .date:
            switch op {
            case .isSet, .isNotSet:
                break // no operand
            case .inLastDays:
                guard let days = Int(value.daysText) else { return nil }
                primary = .date(.relativeDays(days))
            case .between:
                primary = .date(.epoch(value.date.timeIntervalSince1970))
                secondary = .date(.epoch(value.secondDate.timeIntervalSince1970))
            default:
                primary = .date(.epoch(value.date.timeIntervalSince1970))
            }
        case .enumeration, .podcastList:
            primary = .stringList(value.selectedValues)
        }

        return .condition(CustomQueryCondition(field: field, op: op, value: primary, secondValue: secondary))
    }
}

// MARK: - AST -> Draft (edit mode)

nonisolated extension CustomQueryDraftGroup {
    /// Rebuilds an editable draft from a stored AST.
    init(node: CustomQueryNode) {
        switch node {
        case .group(let group):
            self.init(
                match: Match(engineOperator: group.op),
                children: group.children.map { CustomQueryDraftNode(node: $0) }
            )
        case .condition:
            // A bare condition at the root gets wrapped in an implicit All group.
            self.init(match: .all, children: [CustomQueryDraftNode(node: node)])
        }
    }
}

nonisolated extension CustomQueryDraftNode {
    init(node: CustomQueryNode) {
        switch node {
        case .group:
            self = .group(CustomQueryDraftGroup(node: node))
        case .condition(let condition):
            self = .condition(CustomQueryDraftCondition(engineCondition: condition))
        }
    }
}

nonisolated extension CustomQueryDraftCondition {
    init(engineCondition: CustomQueryCondition) {
        var draftValue = CustomQueryDraftValue()

        func apply(_ engineValue: CustomQueryValue, isSecondary: Bool) {
            switch engineValue {
            case .string(let string):
                draftValue.text = string
            case .number(let number):
                if isSecondary {
                    draftValue.secondNumberText = Self.editableText(for: number)
                } else {
                    draftValue.numberText = Self.editableText(for: number)
                }
            case .bool(let bool):
                draftValue.boolValue = bool
            case .date(.epoch(let epoch)):
                if isSecondary {
                    draftValue.secondDate = Date(timeIntervalSince1970: epoch)
                } else {
                    draftValue.date = Date(timeIntervalSince1970: epoch)
                }
            case .date(.relativeDays(let days)):
                draftValue.daysText = String(days)
            case .stringList(let values):
                draftValue.selectedValues = values
            }
        }

        if let value = engineCondition.value {
            apply(value, isSecondary: false)
        }
        if let secondValue = engineCondition.secondValue {
            apply(secondValue, isSecondary: true)
        }

        self.init(id: UUID(), field: engineCondition.field, op: engineCondition.op, value: draftValue)
    }

    private static func editableText(for number: Double) -> String {
        if number == number.rounded(), abs(number) < Double(Int64.max) {
            return String(Int64(number))
        }
        return String(number)
    }
}

// MARK: - Field display metadata (app layer)

nonisolated extension CustomQueryField {
    var displayName: String {
        switch self {
        case .episodeTitle: L10n.playlistCustomFieldEpisodeTitle
        case .episodeDescription: L10n.playlistCustomFieldEpisodeDescription
        case .podcastTitle: L10n.playlistCustomFieldPodcastTitle
        case .podcast: L10n.playlistCustomFieldPodcast
        case .duration: L10n.playlistCustomFieldDuration
        case .playedUpTo: L10n.playlistCustomFieldPlayedUpTo
        case .fileSize: L10n.playlistCustomFieldFileSize
        case .seasonNumber: L10n.playlistCustomFieldSeasonNumber
        case .episodeNumber: L10n.playlistCustomFieldEpisodeNumber
        case .progressPercent: L10n.playlistCustomFieldProgressPercent
        case .playingStatus: L10n.playlistCustomFieldPlayingStatus
        case .downloadStatus: L10n.playlistCustomFieldDownloadStatus
        case .episodeType: L10n.playlistCustomFieldEpisodeType
        case .mediaType: L10n.playlistCustomFieldMediaType
        case .starred: L10n.statusStarred
        case .podcastSubscribed: L10n.playlistCustomFieldPodcastSubscribed
        case .publishedDate: L10n.playlistCustomFieldPublishedDate
        case .addedDate: L10n.playlistCustomFieldAddedDate
        case .lastPlayedDate: L10n.playlistCustomFieldLastPlayedDate
        }
    }

    /// Presentation label for one of the catalog's `enumerationValues` identifiers.
    func displayName(forEnumerationValue enumerationValue: String) -> String {
        switch (self, enumerationValue) {
        case (.playingStatus, "notPlayed"): L10n.statusUnplayed
        case (.playingStatus, "inProgress"): L10n.inProgress
        case (.playingStatus, "completed"): L10n.statusPlayed
        case (.downloadStatus, "notDownloaded"): L10n.statusNotDownloaded
        case (.downloadStatus, "queued"): L10n.podcastQueued
        case (.downloadStatus, "downloading"): L10n.statusDownloading
        case (.downloadStatus, "downloadFailed"): L10n.downloadFailed
        case (.downloadStatus, "downloaded"): L10n.statusDownloaded
        case (.downloadStatus, "waitingForWifi"): L10n.waitForWifi
        case (.episodeType, "full"): L10n.playlistCustomEpisodeTypeFull
        case (.episodeType, "trailer"): L10n.playlistCustomEpisodeTypeTrailer
        case (.episodeType, "bonus"): L10n.playlistCustomEpisodeTypeBonus
        case (.mediaType, "audio"): L10n.filterMediaTypeAudio
        case (.mediaType, "video"): L10n.filterMediaTypeVideo
        default: enumerationValue
        }
    }

    /// SQL column (or computed expression) shown in the schema-reference sheet.
    var columnExpression: String {
        switch self {
        case .episodeTitle: "episode.title"
        case .episodeDescription: "episode.episodeDescription"
        case .podcastTitle: "podcast.title"
        case .podcast: "podcast.uuid"
        case .duration: "episode.duration"
        case .playedUpTo: "episode.playedUpTo"
        case .fileSize: "episode.sizeInBytes"
        case .seasonNumber: "episode.seasonNumber"
        case .episodeNumber: "episode.episodeNumber"
        case .progressPercent: "episode.playedUpTo / episode.duration"
        case .playingStatus: "episode.playingStatus"
        case .downloadStatus: "episode.episodeStatus"
        case .episodeType: "episode.episodeType"
        case .mediaType: "episode.fileType"
        case .starred: "episode.keepEpisode"
        case .podcastSubscribed: "podcast.subscribed"
        case .publishedDate: "episode.publishedDate"
        case .addedDate: "episode.addedDate"
        case .lastPlayedDate: "episode.lastPlaybackInteractionDate"
        }
    }

    /// Example fragment shown in the schema-reference sheet.
    var exampleFragment: String {
        switch self {
        case .episodeTitle: "episode.title LIKE '%interview%'"
        case .episodeDescription: "episode.episodeDescription LIKE '%live show%'"
        case .podcastTitle: "podcast.title LIKE '%history%'"
        case .podcast: "podcast.uuid IN ('uuid-1', 'uuid-2')"
        case .duration: "episode.duration > 1800"
        case .playedUpTo: "episode.playedUpTo > 600"
        case .fileSize: "episode.sizeInBytes > 100000000"
        case .seasonNumber: "episode.seasonNumber = 2"
        case .episodeNumber: "episode.episodeNumber BETWEEN 1 AND 10"
        case .progressPercent: "episode.playedUpTo > episode.duration * 0.5"
        case .playingStatus: "episode.playingStatus = 2"
        case .downloadStatus: "episode.episodeStatus = 3"
        case .episodeType: "episode.episodeType = 'trailer'"
        case .mediaType: "episode.fileType LIKE 'video%'"
        case .starred: "episode.keepEpisode = 1"
        case .podcastSubscribed: "podcast.subscribed = 1"
        case .publishedDate: "episode.publishedDate > strftime('%s', 'now', '-30 days')"
        case .addedDate: "episode.addedDate > strftime('%s', 'now', '-7 days')"
        case .lastPlayedDate: "episode.lastPlaybackInteractionDate IS NOT NULL"
        }
    }

    /// Schema-reference type label for the field's kind.
    var kindDisplayName: String {
        switch kind {
        case .text: L10n.playlistCustomSchemaTypeText
        case .number: L10n.playlistCustomSchemaTypeNumber
        case .boolean: L10n.playlistCustomSchemaTypeBoolean
        case .date: L10n.playlistCustomSchemaTypeDate
        case .enumeration: L10n.playlistCustomSchemaTypeEnum
        case .podcastList: L10n.playlistCustomSchemaTypePodcast
        }
    }
}

// MARK: - Operator display metadata (app layer)

nonisolated extension CustomQueryOperator {
    var displayName: String {
        switch self {
        case .contains: L10n.playlistCustomOpContains
        case .notContains: L10n.playlistCustomOpNotContains
        case .equals: L10n.playlistCustomOpEquals
        case .notEquals: L10n.playlistCustomOpNotEquals
        case .startsWith: L10n.playlistCustomOpStartsWith
        case .endsWith: L10n.playlistCustomOpEndsWith
        case .greaterThan: L10n.playlistCustomOpGreaterThan
        case .lessThan: L10n.playlistCustomOpLessThan
        case .greaterThanOrEqual: L10n.playlistCustomOpAtLeast
        case .lessThanOrEqual: L10n.playlistCustomOpAtMost
        case .between: L10n.playlistCustomOpBetween
        case .isSet: L10n.playlistCustomOpIsSet
        case .isNotSet: L10n.playlistCustomOpIsNotSet
        case .isIn: L10n.playlistCustomOpIn
        case .notIn: L10n.playlistCustomOpNotIn
        case .inLastDays: L10n.playlistCustomOpInLastDays
        case .before: L10n.playlistCustomOpBefore
        case .after: L10n.playlistCustomOpAfter
        }
    }
}

// MARK: - Validation error display (app layer)

nonisolated extension CustomQueryValidationError {
    var displayMessage: String {
        switch self {
        case .empty:
            L10n.playlistCustomErrorEmpty
        case .tooLong(let limit):
            L10n.playlistCustomErrorTooLong(limit.localized(.decimal))
        case .containsPlaceholders:
            L10n.playlistCustomErrorPlaceholders
        case .syntax(let message):
            L10n.playlistCustomErrorSyntax(message)
        case .multipleStatements:
            L10n.playlistCustomErrorMultipleStatements
        case .notReadOnly:
            L10n.playlistCustomErrorNotReadOnly
        case .executionFailed(let message):
            L10n.playlistCustomErrorExecution(message)
        }
    }

    /// Analytics property value for `filterCustomQueryValidated`.
    var analyticsName: String {
        switch self {
        case .empty: "empty"
        case .tooLong: "too_long"
        case .containsPlaceholders: "contains_placeholders"
        case .syntax: "syntax"
        case .multipleStatements: "multiple_statements"
        case .notReadOnly: "not_read_only"
        case .executionFailed: "execution_failed"
        }
    }
}
