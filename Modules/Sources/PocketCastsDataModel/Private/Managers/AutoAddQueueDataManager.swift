import PocketCastsUtils
import Foundation
import GRDB
import GRDBMacros

/// Row record for the `AutoAddCandidates` table.
/// `id` is optional so inserts encode NULL and SQLite assigns the
/// `INTEGER PRIMARY KEY` rowid, matching the legacy INSERT that omits the column.
@GRDBRecord(table: "AutoAddCandidates")
struct AutoAddCandidateRow: Equatable, Sendable {
    var id: Int64?
    @GRDBColumn("episode_uuid")
    var episodeUuid = ""
    @GRDBColumn("podcast_uuid")
    var podcastUuid = ""
}

public struct AutoAddCandidatesDataManager {
    private let dbQueue: GRDBQueue

    init(dbQueue: GRDBQueue) {
        self.dbQueue = dbQueue
    }

    /// Adds a new auto add candidate to the database
    public func add(podcastUUID: String, episodeUUID: String) {
        dbQueue.write { db in
            try AutoAddCandidateRow(id: nil, episodeUuid: episodeUUID, podcastUuid: podcastUUID).insert(db)
        }
    }

    /// Removes a single candidate from the DB
    public func remove(_ candidate: AutoAddCandidate) {
        dbQueue.deleteAll(AutoAddCandidateRow.self, filter: AutoAddCandidateRow.Columns.id == candidate.id)
    }

    /// Reset the the entire candidates table
    public func clearAll() {
        _ = dbQueue.write { db in
            try AutoAddCandidateRow.deleteAll(db)
        }
    }

    /// Returns the auto add up next candidates
    /// Each candidate contains the
    public func candidates() -> [AutoAddCandidate] {
        return dbQueue.read { db in
            // Process the oldest items first, like the legacy ORDER BY queue.id ASC
            let rows = try AutoAddCandidateRow.order(AutoAddCandidateRow.Columns.id.asc).fetchAll(db)
            guard !rows.isEmpty else { return [] }

            // The podcast's auto-add setting, read the same way the legacy JOIN does:
            // json_extract of the settings payload when newSettingsStorage is enabled,
            // the autoAddToUpNext column otherwise.
            let settingSelection: any SQLSelectable = FeatureFlag.newSettingsStorage.enabled
                ? JSONColumn(Constants.settingsColumnName).jsonExtract(atPath: "$.addToUpNextPosition.value").forKey(Constants.settingKey)
                : Podcast.Columns.autoAddToUpNext.forKey(Constants.settingKey)

            let settings = try Podcast
                .filter(rows.map(\.podcastUuid).contains(Podcast.Columns.uuid))
                .select([Podcast.Columns.uuid, settingSelection], as: PodcastAutoAddSetting.self)
                .fetchAll(db)
            let settingByUuid = Dictionary(settings.map { ($0.uuid, $0.setting) }, uniquingKeysWith: { first, _ in first })

            return rows.compactMap { row -> AutoAddCandidate? in
                // A candidate without a matching podcast is dropped, like the legacy INNER JOIN
                guard let id = row.id, let setting = settingByUuid[row.podcastUuid] else { return nil }
                return AutoAddCandidate(id: Int(id), episodeUuid: row.episodeUuid, podcastSettingValue: setting)
            }
        } ?? []
    }

    // MARK: - Model

    /// The `AutoAddCandidate` represents an episode that could be auto added to the up next queue.
    /// To reduce the number of queries needed this also includes the related Podcast's auto add up next setting
    public struct AutoAddCandidate {
        let id: Int

        /// The Podcast.autoAddToUpNext setting value
        public let autoAddToUpNextSetting: AutoAddToUpNextSetting

        /// The UUID of the candidate episode to add
        public let episodeUuid: String

        init?(from resultSet: PCDBResultSet) {

            let setting: Int32
            if FeatureFlag.newSettingsStorage.enabled {
                let value = resultSet.int(forColumn: Constants.autoAddSettingColumnName)
                let position = UpNextPosition(rawValue: value)
                switch position {
                case .top:
                    setting = AutoAddToUpNextSetting.addFirst.rawValue
                case .bottom:
                    setting = AutoAddToUpNextSetting.addLast.rawValue
                default:
                    setting = AutoAddToUpNextSetting.off.rawValue
                }
            } else {
                setting = resultSet.int(forColumn: Constants.autoAddSettingColumnName)
            }

            guard
                let idObj = resultSet.object(forColumn: Constants.idColumnName) as? NSNumber,
                let episodeUuid = resultSet.string(forColumn: Constants.episodeColumnName),
                let autoAddSetting = AutoAddToUpNextSetting(rawValue: setting)
            else {
                return nil
            }

            self.id = idObj.intValue
            self.autoAddToUpNextSetting = autoAddSetting
            self.episodeUuid = episodeUuid
        }

        /// GRDB-path equivalent of `init?(from:)`: maps the podcast's raw setting value the same
        /// way, including NULL → 0 (the missing-JSON-key case reads as `.bottom`, not `.off`,
        /// matching `json_extract` + `resultSet.int` behavior).
        init?(id: Int, episodeUuid: String, podcastSettingValue: Int32?) {
            let setting: Int32
            if FeatureFlag.newSettingsStorage.enabled {
                switch UpNextPosition(rawValue: podcastSettingValue ?? 0) {
                case .top:
                    setting = AutoAddToUpNextSetting.addFirst.rawValue
                case .bottom:
                    setting = AutoAddToUpNextSetting.addLast.rawValue
                default:
                    setting = AutoAddToUpNextSetting.off.rawValue
                }
            } else {
                setting = podcastSettingValue ?? 0
            }

            guard let autoAddSetting = AutoAddToUpNextSetting(rawValue: setting) else {
                return nil
            }

            self.id = id
            self.autoAddToUpNextSetting = autoAddSetting
            self.episodeUuid = episodeUuid
        }
    }

    /// Decodes the per-podcast `(uuid, setting)` pairs fetched by the GRDB path of `candidates()`.
    private struct PodcastAutoAddSetting: Decodable, FetchableRecord {
        let uuid: String
        let setting: Int32?
    }

    // MARK: - Config

    private enum Constants {
        static let tableName = "AutoAddCandidates"
        static let autoAddSettingColumnName = "auto_add_setting"
        static let settingsColumnName = "settings"
        static let episodeColumnName = "episode_uuid"
        static let idColumnName = "id"
        /// Result key for the GRDB-path setting selection (matches `PodcastAutoAddSetting.setting`)
        static let settingKey = "setting"
    }
}
