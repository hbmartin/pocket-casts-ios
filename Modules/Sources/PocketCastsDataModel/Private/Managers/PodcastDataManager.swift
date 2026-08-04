import PocketCastsUtils
import Foundation
import GRDB

extension Podcast: Sortable {
    public var itemUUID: String {
        uuid
    }

    public var itemTitle: String? {
        title
    }
}

class PodcastDataManager {
    private static let defaultSettingsJsonString: String = {
        guard let json = PodcastSettings.defaults.jsonData,
              let jsonString = String(data: json, encoding: .utf8) else {
            preconditionFailure("PodcastSettings.defaults must encode to JSON")
        }
        return jsonString
    }()

    private var cachedPodcasts = [String: Podcast]()
    private lazy var cachedPodcastsQueue: DispatchQueue = {
        let queue = DispatchQueue(label: "au.com.pocketcasts.PodcastDataQueue")

        return queue
    }()

    /// Legacy column names for non-GRDB code path.
    let columnNames = [
        "id",
        "addedDate",
        "autoDownloadSetting",
        "autoAddToUpNext",
        "episodeKeepSetting",
        "backgroundColor",
        "detailColor",
        "primaryColor",
        "secondaryColor",
        "lastColorDownloadDate",
        "imageURL",
        "latestEpisodeUuid",
        "latestEpisodeDate",
        "mediaType",
        "lastThumbnailDownloadDate",
        "thumbnailStatus",
        "podcastUrl",
        "author",
        "playbackSpeed",
        "boostVolume",
        "trimSilenceAmount",
        "podcastCategory",
        "podcastDescription",
        "podcastHTMLDescription",
        "sortOrder",
        "startFrom",
        "skipLast",
        "subscribed",
        "title",
        "uuid",
        "syncStatus",
        "colorVersion",
        "pushEnabled",
        "episodeSortOrder",
        "showType",
        "estimatedNextEpisode",
        "episodeFrequency",
        "lastUpdatedAt",
        "excludeFromAutoArchive",
        "overrideGlobalEffects",
        "overrideGlobalArchive",
        "autoArchivePlayedAfter",
        "autoArchiveInactiveAfter",
        "episodeGrouping",
        "isPaid",
        "licensing",
        "fullSyncLastSyncAt",
        "showArchived",
        "refreshAvailable",
        "folderUuid",
        "usedCustomEffectsBefore",
        "isPrivate",
        "fundingURL"
    ]

    func setup(dbQueue: GRDBQueue) {
        cachePodcasts(dbQueue: dbQueue)
    }

    // MARK: - GRDB Fetching

    /// Materializes a fetched row, backfilling the `@GRDBIgnore`d `settings` payload the same way
    /// the legacy read path does: defaults when empty, log-and-defaults when undecodable.
    private static func podcastWithSettings(from row: Row) throws -> Podcast {
        var podcast = try Podcast(row: row)
        if let settingsString: String = row["settings"],
           !settingsString.isEmpty,
           let settingsData = settingsString.data(using: .utf8) {
            do {
                podcast.settings = try JSONDecoder().decode(PodcastSettings.self, from: settingsData)
            } catch {
                FileLog.shared.addMessage("Podcast.from failed to decode settings for \(podcast.uuid): \(error)")
            }
        }
        return podcast
    }

    /// Converts legacy `[Any]` binding values for the GRDB path, matching the legacy shim's
    /// conversions: `Date` binds as `timeIntervalSince1970` and `NSNull` as NULL.
    private static func databaseValue(from value: Any) -> DatabaseValue {
        if let date = value as? Date {
            return date.timeIntervalSince1970.databaseValue
        }
        if value is NSNull {
            return .null
        }
        return DatabaseValue(value: value) ?? .null
    }

    /// Decodes the aggregate `(podcast_id, COUNT(id))` rows fetched by `unfinishedCounts`.
    private struct PodcastUnfinishedCount: Decodable, FetchableRecord {
        let podcastId: Int64
        let count: Int32
    }

    /// Decodes the aggregate `(podcast_id, MAX(<date column>))` rows for the ordered fetches.
    private struct PodcastLatestDate: Decodable, FetchableRecord {
        let podcastId: Int64
        let latest: Double?
    }

    /// Two-step query-interface equivalent of the legacy correlated-subquery orderings: fetch the
    /// subscribed podcasts, aggregate each podcast's newest matching episode date, then sort with
    /// the legacy ORDER BY semantics — dated podcasts first (newest date descending), NULL-date
    /// podcasts last, optionally tiebroken by `latestEpisodeDate` descending.
    private func podcastsOrdered(byMaxOf dateColumn: String, episodeFilters: [any SQLSpecificExpressible], tiebreakOnLatestEpisodeDate: Bool, inFolderUuid: String?, in dbQueue: GRDBQueue) -> [Podcast] {
        dbQueue.read { (db: Database) -> [Podcast] in
            var podcastRequest = Podcast.filter(Podcast.Columns.subscribed == 1)
            if let inFolderUuid {
                podcastRequest = podcastRequest.filter(Podcast.Columns.folderUuid == inFolderUuid)
            }
            let podcasts = try Row.fetchAll(db, podcastRequest.asRequest(of: Row.self)).map(Self.podcastWithSettings(from:))

            var episodeRequest = Table(DataManager.episodeTableName).all()
            for episodeFilter in episodeFilters {
                episodeRequest = episodeRequest.filter(episodeFilter)
            }
            let latestRows = try episodeRequest
                .select([Column("podcast_id").forKey("podcastId"), max(Column(dateColumn)).forKey("latest")], as: PodcastLatestDate.self)
                .group(Column("podcast_id"))
                .fetchAll(db)
            let latestById = Dictionary(latestRows.map { ($0.podcastId, $0.latest) }, uniquingKeysWith: { first, _ in first })

            return podcasts.sorted { (lhs: Podcast, rhs: Podcast) -> Bool in
                let lhsLatest = latestById[lhs.id].flatMap { $0 }
                let rhsLatest = latestById[rhs.id].flatMap { $0 }
                switch (lhsLatest, rhsLatest) {
                case let (lhsDate?, rhsDate?):
                    if lhsDate != rhsDate { return lhsDate > rhsDate }
                case (.some, nil):
                    return true
                case (nil, .some):
                    return false
                case (nil, nil):
                    break
                }
                guard tiebreakOnLatestEpisodeDate else { return false }
                return (lhs.latestEpisodeDate ?? .distantPast) > (rhs.latestEpisodeDate ?? .distantPast)
            }
        } ?? []
    }

    // MARK: - Queries

    func allPodcasts(includeUnsubscribed: Bool, reloadFromDatabase: Bool, dbQueue: GRDBQueue) -> [Podcast] {
        if reloadFromDatabase { cachePodcasts(dbQueue: dbQueue) }

        var allPodcasts = [Podcast]()
        cachedPodcastsQueue.sync {
            for podcast in cachedPodcasts.values {
                if !podcast.isSubscribed(), !includeUnsubscribed { continue }
                allPodcasts.append(podcast)
            }
        }

        return allPodcasts
    }

    func allPodcastsOrderedByAddedDate(reloadFromDatabase: Bool, dbQueue: GRDBQueue) -> [Podcast] {
        if reloadFromDatabase { cachePodcasts(dbQueue: dbQueue) }

        var allPodcasts = [Podcast]()
        cachedPodcastsQueue.sync {
            for podcast in cachedPodcasts.values {
                if !podcast.isSubscribed() { continue }

                allPodcasts.append(podcast)
            }
        }

        return allPodcasts.sorted(by: { podcast1, podcast2 -> Bool in
            addedDateSort(p1: podcast1, p2: podcast2)
        })
    }

    func allPodcastsOrderedByTitle(reloadFromDatabase: Bool, dbQueue: GRDBQueue) -> [Podcast] {
        if reloadFromDatabase { cachePodcasts(dbQueue: dbQueue) }

        var allPodcasts = [Podcast]()
        cachedPodcastsQueue.sync {
            for podcast in cachedPodcasts.values {
                if !podcast.isSubscribed() { continue }

                allPodcasts.append(podcast)
            }
        }

        return allPodcasts.sorted(by: { podcast1, podcast2 -> Bool in
            titleSort(p1: podcast1, p2: podcast2)
        })
    }

    func allPodcastsOrderedByNewestEpisodes(reloadFromDatabase: Bool, inFolderUuid: String? = nil, dbQueue: GRDBQueue) -> [Podcast] {
        if reloadFromDatabase { cachePodcasts(dbQueue: dbQueue) }

        // MAX(publishedDate) over unfinished, unarchived episodes is equivalent to the legacy
        // correlated subquery that picks the newest such episode per podcast
        return podcastsOrdered(
            byMaxOf: "publishedDate",
            episodeFilters: [
                Column("playingStatus") != PlayingStatus.completed.rawValue,
                Column("archived") == false
            ],
            tiebreakOnLatestEpisodeDate: true,
            inFolderUuid: inFolderUuid,
            in: dbQueue
        )
    }

    func allPodcastsOrderedByLastPlayedEpisodes(reloadFromDatabase: Bool, inFolderUuid: String? = nil, dbQueue: GRDBQueue) -> [Podcast] {
        if reloadFromDatabase { cachePodcasts(dbQueue: dbQueue) }

        return podcastsOrdered(
            byMaxOf: "lastPlaybackInteractionDate",
            episodeFilters: [],
            tiebreakOnLatestEpisodeDate: false,
            inFolderUuid: inFolderUuid,
            in: dbQueue
        )
    }

    /// Returns 5 random podcasts from the DB
    /// This is here for development purposes.
    func randomPodcasts(dbQueue: GRDBQueue) -> [Podcast] {
        let podcasts = dbQueue.read { db in
            try Row.fetchAll(db, Podcast.all().asRequest(of: Row.self)).map(Self.podcastWithSettings(from:))
        } ?? []
        return Array(podcasts.shuffled().prefix(5))
    }

    func allUnsubscribedPodcastUuids(dbQueue: GRDBQueue) -> [String] {
        var allUnsubscribed = [String]()
        cachedPodcastsQueue.sync {
            for podcast in cachedPodcasts.values {
                if podcast.isSubscribed() { continue }

                allUnsubscribed.append(podcast.uuid)
            }
        }

        return allUnsubscribed
    }

    func allUnsubscribedPodcasts(dbQueue: GRDBQueue) -> [Podcast] {
        var allUnsubscribed = [Podcast]()
        cachedPodcastsQueue.sync {
            for podcast in cachedPodcasts.values {
                if podcast.isSubscribed() { continue }

                allUnsubscribed.append(podcast)
            }
        }

        return allUnsubscribed
    }

    func allPodcastsInFolder(folder: Folder, dbQueue: GRDBQueue) -> [Podcast] {
        let sortOrder = folder.folderSort()

        // newest episode release date is a special case we handle at the database level
        if sortOrder == .episodeDateNewestToOldest {
            return allPodcastsOrderedByNewestEpisodes(reloadFromDatabase: false, inFolderUuid: folder.uuid, dbQueue: dbQueue)
        }

        // newest episode release date is a special case we handle at the database level
        if sortOrder == .recentlyPlayed {
            return allPodcastsOrderedByLastPlayedEpisodes(reloadFromDatabase: false, inFolderUuid: folder.uuid, dbQueue: dbQueue)
        }

        // the other 3 cases we do in memory
        var allPodcastsInFolder: [Podcast] = []
        cachedPodcastsQueue.sync {
            allPodcastsInFolder = cachedPodcasts.values.filter { $0.isSubscribed() && $0.folderUuid == folder.uuid }
        }

        allPodcastsInFolder.sort { podcast1, podcast2 in
            if sortOrder == .dateAddedNewestToOldest {
                return addedDateSort(p1: podcast1, p2: podcast2)
            } else if sortOrder == .titleAtoZ {
                return titleSort(p1: podcast1, p2: podcast2)
            }

            return podcast1.sortOrder < podcast2.sortOrder
        }

        return allPodcastsInFolder
    }

    func countOfPodcastsInFolder(folder: Folder?, dbQueue: GRDBQueue) -> Int {
        cachedPodcastsQueue.sync {
            cachedPodcasts.values.filter { $0.isSubscribed() && $0.folderUuid == folder?.uuid }.count
        }
    }

    func allPaidPodcasts(dbQueue: GRDBQueue) -> [Podcast] {
        var allPaid = [Podcast]()
        cachedPodcastsQueue.sync {
            for podcast in cachedPodcasts.values {
                if !podcast.isPaid { continue }

                allPaid.append(podcast)
            }
        }

        return allPaid
    }

    func allUnsynced(dbQueue: GRDBQueue) -> [Podcast] {
        var unsyncedPodcasts = [Podcast]()
        cachedPodcastsQueue.sync {
            for podcast in cachedPodcasts.values {
                if podcast.syncStatus == SyncStatus.notSynced.rawValue {
                    unsyncedPodcasts.append(podcast)
                }
            }
        }

        return unsyncedPodcasts
    }

    func allOverrideGlobalArchivePodcasts(dbQueue: GRDBQueue) -> [Podcast] {
        var podcastsOverrideArchive = [Podcast]()
        cachedPodcastsQueue.sync {
            for podcast in cachedPodcasts.values {
                if podcast.isSubscribed(), podcast.isAutoArchiveOverridden {
                    podcastsOverrideArchive.append(podcast)
                }
            }
        }

        return podcastsOverrideArchive
    }

    func find(uuid: String, includeUnsubscribed: Bool, dbQueue: GRDBQueue) -> Podcast? {
        cachedPodcastsQueue.sync {
            guard let podcast = cachedPodcasts[uuid] else { return nil }

            if !includeUnsubscribed, !podcast.isSubscribed() { return nil }

            return podcast
        }
    }

    func searchPodcasts(term: String, dbQueue: GRDBQueue) -> [Podcast] {
        let trimmedTerm = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTerm.isEmpty else { return [] }

        let locale = Locale.current
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]

        var matchingPodcasts = [Podcast]()
        cachedPodcastsQueue.sync {
            for podcast in cachedPodcasts.values {
                guard podcast.isSubscribed() else { continue }

                if podcast.title?.range(of: trimmedTerm, options: options, range: nil, locale: locale) != nil {
                    matchingPodcasts.append(podcast)
                    continue
                }

                if podcast.author?.range(of: trimmedTerm, options: options, range: nil, locale: locale) != nil {
                    matchingPodcasts.append(podcast)
                }
            }
        }

        return matchingPodcasts.sorted(by: { lhs, rhs in
            PodcastSorter.sortByNameAndUUID(item1: lhs, item2: rhs)
        })
    }

    func count(dbQueue: GRDBQueue) -> Int {
        var count = 0
        cachedPodcastsQueue.sync {
            for podcast in cachedPodcasts.values {
                if !podcast.isSubscribed() { continue }

                count += 1
            }
        }

        return count
    }

    func unfinishedCounts(dbQueue: GRDBQueue) -> [String: Int32] {
        return dbQueue.read { db in
            // Two-step equivalent of the legacy episodes-podcasts JOIN: aggregate per
            // podcast_id, then key by uuid (episodes without a podcast row drop out)
            let episodeCounts = try Table(DataManager.episodeTableName)
                .filter(Column("playingStatus") != PlayingStatus.completed.rawValue)
                .filter(Column("archived") == false)
                .select([Column("podcast_id").forKey("podcastId"), GRDB.count(Column("id")).forKey("count")], as: PodcastUnfinishedCount.self)
                .group(Column("podcast_id"))
                .fetchAll(db)

            let podcastRows = try Row.fetchAll(db, Podcast.select([Podcast.Columns.id, Podcast.Columns.uuid]).asRequest(of: Row.self))
            let uuidById = Dictionary(podcastRows.map { ($0["id"] as Int64, $0["uuid"] as String) }, uniquingKeysWith: { first, _ in first })

            var counts = [String: Int32]()
            for episodeCount in episodeCounts {
                if let uuid = uuidById[episodeCount.podcastId] {
                    counts[uuid] = episodeCount.count
                }
            }
            return counts
        } ?? [:]
    }

    // MARK: - Updates

    @discardableResult
    func save(podcast: Podcast, dbQueue: GRDBQueue) -> Podcast {
        var saved = podcast
        let success = dbQueue.write { db in
            saved = try save(podcast: podcast, db: db)
        }
        if success {
            cachePodcasts(dbQueue: dbQueue)
        }
        return saved
    }

    @discardableResult
    func save(podcast: Podcast, db: Database) throws -> Podcast {
        var podcast = podcast
        var isInsert = podcast.id == 0
        if isInsert, let existingId = existingPodcastId(uuid: podcast.uuid) {
            // A value-type save no longer back-mutates the caller's id, so a caller that re-saves a copy
            // whose id is still 0 must update the existing row (resolved by uuid) rather than insert a
            // duplicate. Mirrors the EpisodeFilter save-then-add fix (PR #113).
            podcast.id = existingId
            isInsert = false
        } else if isInsert {
            podcast.id = DBUtils.generateUniqueId()
        }

        try podcast.save(db)
        if FeatureFlag.newSettingsStorage.enabled {
            try saveSettings(podcast: podcast, db: db)
        }
        return podcast
    }

    /// Resolves the persisted row id for a uuid from the in-memory cache (a complete mirror of the
    /// table). Used by `save` to update-by-uuid instead of inserting a duplicate when the caller's
    /// value-type copy has lost its id.
    private func existingPodcastId(uuid: String) -> Int64? {
        guard !uuid.isEmpty else { return nil }
        return cachedPodcastsQueue.sync { cachedPodcasts[uuid]?.id }
    }

    func bulkSetFolderUuid(folderUuid: String, podcastUuids: [String], dbQueue: GRDBQueue) {
        dbQueue.write { db in
            // clear out any that shouldn't be in this folder
            try Podcast
                .filter(Podcast.Columns.folderUuid == folderUuid)
                .updateAll(db, Podcast.Columns.folderUuid.set(to: nil as String?), Podcast.Columns.syncStatus.set(to: SyncStatus.notSynced.rawValue))

            // then set all the ones that should
            if !podcastUuids.isEmpty {
                try Podcast
                    .filter(podcastUuids.contains(Podcast.Columns.uuid))
                    .updateAll(db, Podcast.Columns.folderUuid.set(to: folderUuid), Podcast.Columns.syncStatus.set(to: SyncStatus.notSynced.rawValue))
            }
        }
        cachePodcasts(dbQueue: dbQueue)
    }

    func updatePodcastFolder(podcastUuid: String, sortOrder: Int32, folderUuid: String?, dbQueue: GRDBQueue) {
        dbQueue.updateAll(
            Podcast.self,
            filter: Podcast.Columns.uuid == podcastUuid,
            Podcast.Columns.folderUuid.set(to: folderUuid),
            Podcast.Columns.sortOrder.set(to: sortOrder),
            Podcast.Columns.syncStatus.set(to: SyncStatus.notSynced.rawValue)
        )
        cachePodcasts(dbQueue: dbQueue)
    }

    func savePushSetting(podcast: Podcast, pushEnabled: Bool, dbQueue: GRDBQueue) {
        var podcast = podcast
        podcast.isPushEnabled = pushEnabled
        savePushSetting(podcastUuid: podcast.uuid, pushEnabled: pushEnabled, dbQueue: dbQueue)
    }

    func savePushSetting(podcastUuid: String, pushEnabled: Bool, dbQueue: GRDBQueue) {
        if FeatureFlag.newSettingsStorage.enabled {
            savePushSettingWithNewSettingsStorage(podcastUuid: podcastUuid, pushEnabled: pushEnabled, dbQueue: dbQueue)
        } else {
            saveSingleValue(name: "pushEnabled", value: pushEnabled, podcastUuid: podcastUuid, dbQueue: dbQueue)
        }
    }

    func saveAutoAddToUpNext(podcastUuid: String, autoAddToUpNext: Int32, dbQueue: GRDBQueue) {
        guard let setting = AutoAddToUpNextSetting(rawValue: autoAddToUpNext) else {
            FileLog.shared.addMessage("Podcast Data: Failed to create AutoAddToUpNextSetting type for saving")
            return
        }

        dbQueue.write { db in
            do {
                if FeatureFlag.newSettingsStorage.enabled {
                    try Self.executeAutoAddUpdate(
                        setting: setting,
                        whereClause: "uuid = ?",
                        trailingArguments: [podcastUuid],
                        db: db
                    )
                } else {
                    try Podcast
                        .filter(Podcast.Columns.uuid == podcastUuid)
                        .updateAll(
                            db,
                            Podcast.Columns.autoAddToUpNext.set(to: autoAddToUpNext),
                            Podcast.Columns.syncStatus.set(to: SyncStatus.notSynced.rawValue)
                        )
                }
            } catch {
                FileLog.shared.addMessage("PodcastDataManager.saveAutoAddToUpNext error: \(error)")
            }
        }

        cachePodcasts(dbQueue: dbQueue)
    }

    func setPodcastImageVersion(podcastUuid: String, version: Int, dbQueue: GRDBQueue) {
        saveSingleValue(name: "lastColorDownloadDate", value: NSNull(), podcastUuid: podcastUuid, dbQueue: dbQueue)
        saveSingleValue(name: "colorVersion", value: version, podcastUuid: podcastUuid, dbQueue: dbQueue)
    }

    func savePodcastDownloadSetting(_ setting: AutoDownloadSetting, podcastUuid: String, dbQueue: GRDBQueue) {
        saveSingleValue(name: "autoDownloadSetting", value: setting.rawValue, podcastUuid: podcastUuid, dbQueue: dbQueue)
    }

    func saveAutoArchiveLimit(podcast: Podcast, limit: Int32, dbQueue: GRDBQueue) {
        var podcast = podcast
        podcast.autoArchiveEpisodeLimitCount = limit
        if FeatureFlag.newSettingsStorage.enabled {
            saveSingleSetting("autoArchiveEpisodeLimit", value: limit, podcastUuid: podcast.uuid, dbQueue: dbQueue)
        }
        saveSingleValue(name: "episodeKeepSetting", value: limit, podcastUuid: podcast.uuid, dbQueue: dbQueue)
    }

    /// Chapter smart-skip title patterns live only in the settings JSON payload (no legacy column),
    /// so the json_set writer runs unconditionally rather than behind `newSettingsStorage`.
    func saveSkipChapterTitles(_ titles: [String], podcastUuid: String, dbQueue: GRDBQueue) {
        saveSingleSetting("skipChapterTitles", value: titles, podcastUuid: podcastUuid, dbQueue: dbQueue)
    }

    /// The per-podcast remote-transcription opt-out lives only in the settings JSON payload (no
    /// legacy column) and is device-local, so the json_set writer runs unconditionally rather than
    /// behind `newSettingsStorage`.
    func saveDisableRemoteTranscription(_ disabled: Bool, podcastUuid: String, dbQueue: GRDBQueue) {
        saveSingleSetting("disableRemoteTranscription", value: disabled, podcastUuid: podcastUuid, dbQueue: dbQueue)
    }

    func delete(podcast: Podcast, dbQueue: GRDBQueue) {
        let success = dbQueue.write { db in
            try delete(podcast: podcast, db: db)
        }
        if success {
            cachePodcasts(dbQueue: dbQueue)
        }
    }

    func delete(podcast: Podcast, db: Database) throws {
        try Podcast.filter(Podcast.Columns.uuid == podcast.uuid).deleteAll(db)
    }

    func markAllSynced(dbQueue: GRDBQueue) {
        setOnAllPodcasts(value: SyncStatus.synced.rawValue, propertyName: "syncStatus", subscribedOnly: false, dbQueue: dbQueue)
    }

    func markAllUnsynced(dbQueue: GRDBQueue) {
        setOnAllPodcasts(value: SyncStatus.notSynced.rawValue, propertyName: "syncStatus", subscribedOnly: true, dbQueue: dbQueue)
    }

    func markAllUnsyncedWhereLastSyncAtNot(_ lastSyncAt: String, dbQueue: GRDBQueue) {
        dbQueue.updateAll(
            Podcast.self,
            filter: Podcast.Columns.subscribed == 1 && Podcast.Columns.fullSyncLastSyncAt != lastSyncAt,
            Podcast.Columns.syncStatus.set(to: SyncStatus.notSynced.rawValue)
        )

        cachePodcasts(dbQueue: dbQueue)
    }

    func setPushForAllPodcasts(pushEnabled: Bool, dbQueue: GRDBQueue) {
        if FeatureFlag.newSettingsStorage.enabled {
            setOnAllPodcasts(value: pushEnabled, settingName: "notification", subscribedOnly: true, dbQueue: dbQueue)
        }
        setOnAllPodcasts(value: pushEnabled, propertyName: "pushEnabled", subscribedOnly: true, dbQueue: dbQueue)
    }

    func saveAutoAddToUpNextForAllPodcasts(autoAddToUpNext: Int32, dbQueue: GRDBQueue) {
        guard let setting = AutoAddToUpNextSetting(rawValue: autoAddToUpNext) else {
            FileLog.shared.addMessage("Podcast Data: Failed to create AutoAddToUpNextSetting type for bulk saving")
            return
        }

        dbQueue.write { db in
            do {
                if FeatureFlag.newSettingsStorage.enabled {
                    try Self.executeAutoAddUpdate(
                        setting: setting,
                        whereClause: "subscribed = 1",
                        trailingArguments: [],
                        db: db
                    )
                } else {
                    try Podcast
                        .filter(Podcast.Columns.subscribed == 1)
                        .updateAll(
                            db,
                            Podcast.Columns.autoAddToUpNext.set(to: autoAddToUpNext),
                            Podcast.Columns.syncStatus.set(to: SyncStatus.notSynced.rawValue)
                        )
                }
            } catch {
                FileLog.shared.addMessage("PodcastDataManager.saveAutoAddToUpNextForAllPodcasts error: \(error)")
            }
        }

        cachePodcasts(dbQueue: dbQueue)
    }

    func updateAutoAddToUpNext(to value: AutoAddToUpNextSetting, for podcasts: [Podcast], in dbQueue: GRDBQueue) {
        let uuids = podcasts.map(\.uuid)
        guard !uuids.isEmpty else { return }

        dbQueue.write { db in
            do {
                if FeatureFlag.newSettingsStorage.enabled {
                    try Self.executeAutoAddUpdate(
                        setting: value,
                        whereClause: "uuid IN (\(DBUtils.placeholders(amount: uuids.count)))",
                        trailingArguments: uuids.map { $0 as (any DatabaseValueConvertible)? },
                        db: db
                    )
                } else {
                    try Podcast
                        .filter(uuids.contains(Podcast.Columns.uuid))
                        .updateAll(
                            db,
                            Podcast.Columns.autoAddToUpNext.set(to: value.rawValue),
                            Podcast.Columns.syncStatus.set(to: SyncStatus.notSynced.rawValue)
                        )
                }
            } catch {
                FileLog.shared.addMessage("PodcastDataManager.updateAutoAddToUpNext error: \(error)")
            }
        }

        cachePodcasts(dbQueue: dbQueue)
    }

    func setDownloadSettingForAllPodcasts(setting: AutoDownloadSetting, dbQueue: GRDBQueue) {
        setOnAllPodcasts(value: setting.rawValue, propertyName: "autoDownloadSetting", subscribedOnly: true, dbQueue: dbQueue)
    }

    enum JSONError: Error {
        case failedStringConvert(String, Data)

        var description: String {
            switch self {
            case .failedStringConvert(let name, let data):
                "Failed to convert JSON to String for \(name) with \(data)"
            }
        }
    }

    private static func autoAddJson(
        setting: AutoAddToUpNextSetting,
        modifiedAt: Date
    ) throws -> (enabled: String, position: String) {
        let enabledData = try JSONEncoder().encode(
            ModifiedDate(wrappedValue: setting != .off, modifiedAt: modifiedAt)
        )
        let positionData = try JSONEncoder().encode(
            ModifiedDate(
                wrappedValue: setting == .addFirst ? UpNextPosition.top : UpNextPosition.bottom,
                modifiedAt: modifiedAt
            )
        )
        guard let enabled = String(data: enabledData, encoding: .utf8) else {
            throw JSONError.failedStringConvert("addToUpNext", enabledData)
        }
        guard let position = String(data: positionData, encoding: .utf8) else {
            throw JSONError.failedStringConvert("addToUpNextPosition", positionData)
        }
        return (enabled, position)
    }

    private static func executeAutoAddUpdate(
        setting: AutoAddToUpNextSetting,
        whereClause: String,
        trailingArguments: [(any DatabaseValueConvertible)?],
        db: Database
    ) throws {
        let (enabledJson, positionJson) = try autoAddJson(setting: setting, modifiedAt: Date())
        let query = """
        UPDATE \(DataManager.podcastTableName)
        SET autoAddToUpNext = ?,
            settings = json_set(
                coalesce(nullif(settings, ''), json(?)),
                '$.addToUpNext',
                json(?),
                '$.addToUpNextPosition',
                json(?)
            ),
            syncStatus = \(SyncStatus.notSynced.rawValue)
        WHERE \(whereClause)
        """
        var arguments: [(any DatabaseValueConvertible)?] = [
            setting.rawValue,
            defaultSettingsJsonString,
            enabledJson,
            positionJson,
        ]
        arguments.append(contentsOf: trailingArguments)
        // nosemgrep: pocketcasts.no-new-raw-sql-in-data-managers - one atomic json_set writer preserves unmodeled payload fields for all auto-add update scopes
        try db.execute(sql: query, arguments: StatementArguments(arguments))
    }

    // NOTE: the json_set settings writers below (setOnAllPodcasts(settingName:),
    // savePushSettingWithNewSettingsStorage, saveSingleSetting, and the auto-add writers) stay raw
    // SQL deliberately: SQLite's JSON functions surgically patch
    // one key while preserving any fields the client doesn't model, which a Swift decode/re-encode
    // round trip would drop, and GRDB's query interface has no nullif/json_set equivalents for
    // the empty-payload seeding. They are the residue deliberately kept on the allowlist when the
    // grdbQueryInterface flag was deleted.
    func setOnAllPodcasts<Value: Codable & Equatable>(value: Value, settingName: String, subscribedOnly: Bool, dbQueue: GRDBQueue) {
        dbQueue.write { db in
            do {

                let modified = ModifiedDate(wrappedValue: value, modifiedAt: Date())
                let json = try JSONEncoder().encode(modified)
                guard let jsonString = String(data: json, encoding: .utf8) else {
                    throw JSONError.failedStringConvert(settingName, json)
                }

                let query = """
                UPDATE \(DataManager.podcastTableName)
                SET settings = json_set(
                    coalesce(nullif(settings, ''), json(?)),
                    '$.\(settingName)',
                    json(?)
                ), syncStatus = \(SyncStatus.notSynced.rawValue)
                """
                let queryWithWhere = subscribedOnly ? "\(query) WHERE subscribed = 1" : query
                try db.executeUpdate(queryWithWhere, values: [Self.defaultSettingsJsonString, jsonString]) // nosemgrep: pocketcasts.no-new-raw-sql-in-data-managers - json_set settings writer; Swift re-encode would drop unmodeled payload fields
            } catch {
                FileLog.shared.addMessage("PodcastDataManager.setOnAllPodcasts error: \(error)")
            }
        }

        cachePodcasts(dbQueue: dbQueue)
    }

    func setOnAllPodcasts(value: Any, propertyName: String, subscribedOnly: Bool, dbQueue: GRDBQueue) {
        dbQueue.write { db in
            var request = Podcast.all()
            if subscribedOnly {
                request = request.filter(Podcast.Columns.subscribed == 1)
            }
            try request.updateAll(db, Column(propertyName).set(to: Self.databaseValue(from: value)))
        }
        cachePodcasts(dbQueue: dbQueue)
    }

    func saveSortOrders(podcasts: [Podcast], dbQueue: GRDBQueue) {
        dbQueue.write { db in
            for podcast in podcasts {
                try Podcast
                    .filter(Podcast.Columns.id == podcast.id)
                    .updateAll(db, Podcast.Columns.sortOrder.set(to: podcast.sortOrder), Podcast.Columns.syncStatus.set(to: SyncStatus.notSynced.rawValue))
            }
        }
        cachePodcasts(dbQueue: dbQueue)
    }

    func removeAllPodcastsFromFolder(folderUuid: String, dbQueue: GRDBQueue) {
        let success = dbQueue.write { db in
            try removeAllPodcastsFromFolder(folderUuid: folderUuid, db: db)
        }

        if success {
            cachePodcasts(dbQueue: dbQueue)
        }
    }

    func removeAllPodcastsFromFolder(folderUuid: String, db: Database) throws {
        try Podcast
            .filter(Podcast.Columns.folderUuid == folderUuid)
            .updateAll(
                db,
                Podcast.Columns.folderUuid.set(to: nil as String?),
                Podcast.Columns.syncStatus.set(to: SyncStatus.notSynced.rawValue))
    }

    func removeAllPodcastsFromAllFolders(dbQueue: GRDBQueue) {
        _ = dbQueue.write { db in
            try Podcast.updateAll(db, Podcast.Columns.folderUuid.set(to: nil as String?))
        }

        cachePodcasts(dbQueue: dbQueue)
    }

    func updateAllPodcastGrouping(to grouping: PodcastGrouping, dbQueue: GRDBQueue) {
        setOnAllPodcasts(value: grouping.rawValue, propertyName: "episodeGrouping", subscribedOnly: true, dbQueue: dbQueue)
    }

    func updateAllShowArchived(to showArchived: Bool, dbQueue: GRDBQueue) {
        setOnAllPodcasts(value: showArchived, propertyName: "showArchived", subscribedOnly: true, dbQueue: dbQueue)
    }

    func setAllPodcastImageVersions(to version: Int, dbQueue: GRDBQueue) {
        setOnAllPodcasts(value: NSNull(), propertyName: "lastColorDownloadDate", subscribedOnly: true, dbQueue: dbQueue)
        setOnAllPodcasts(value: version, propertyName: "colorVersion", subscribedOnly: true, dbQueue: dbQueue)
    }

    private func saveSingleValue(name: String, value: Any?, podcastUuid: String, dbQueue: GRDBQueue) {
        dbQueue.updateAll(
            Podcast.self,
            filter: Podcast.Columns.uuid == podcastUuid,
            Column(name).set(to: Self.databaseValue(from: value ?? NSNull()))
        )

        cachePodcasts(dbQueue: dbQueue)
    }

    private func saveSettings(podcast: Podcast, dbQueue: GRDBQueue) {
        dbQueue.write { db in
            try saveSettings(podcast: podcast, db: db)
        }
    }

    private func saveSettings(podcast: Podcast, db: Database) throws {
        guard let json = podcast.settings.jsonData,
              let jsonString = String(data: json, encoding: .utf8) else {
            FileLog.shared.addMessage("PodcastDataManager.saveSettings failed to encode settings for \(podcast.uuid)")
            return
        }

        // Deliberately leaves syncStatus untouched: save(podcast:) must persist the object
        // as the caller built it (the sync import path saves server state and must stay
        // synced). Setting-specific writers mark notSynced themselves.
        // nosemgrep: pocketcasts.no-new-raw-sql-in-data-managers - settings JSON writer; Swift re-encode would drop unmodeled payload fields
        try db.execute(
            sql: "UPDATE \(DataManager.podcastTableName) SET settings = ? WHERE uuid = ?",
            arguments: StatementArguments([jsonString, podcast.uuid])!)
    }

    private func savePushSettingWithNewSettingsStorage(podcastUuid: String, pushEnabled: Bool, dbQueue: GRDBQueue) {
        dbQueue.write { db in
            do {
                let modified = ModifiedDate(wrappedValue: pushEnabled, modifiedAt: Date())
                let json = try JSONEncoder().encode(modified)
                guard let jsonString = String(data: json, encoding: .utf8) else {
                    throw JSONError.failedStringConvert("notification", json)
                }

                let query = """
                UPDATE \(DataManager.podcastTableName)
                SET pushEnabled = ?,
                    settings = json_set(
                        coalesce(nullif(settings, ''), json(?)),
                        '$.notification',
                        json(?)
                    ),
                    syncStatus = \(SyncStatus.notSynced.rawValue)
                WHERE uuid = ?
                """
                try db.executeUpdate(query, values: [pushEnabled, Self.defaultSettingsJsonString, jsonString, podcastUuid]) // nosemgrep: pocketcasts.no-new-raw-sql-in-data-managers - json_set settings writer; Swift re-encode would drop unmodeled payload fields
            } catch {
                FileLog.shared.addMessage("PodcastDataManager.savePushSetting for notification error: \(error)")
            }
        }
        cachePodcasts(dbQueue: dbQueue)
    }

    private func saveSingleSetting<Value: Codable & Equatable>(_ name: String, value: Value, podcastUuid: String, dbQueue: GRDBQueue) {
        dbQueue.write { db in
            do {
                let modified = ModifiedDate(wrappedValue: value, modifiedAt: Date())
                let json = try JSONEncoder().encode(modified)
                guard let jsonString = String(data: json, encoding: .utf8) else {
                    throw JSONError.failedStringConvert(name, json)
                }

                let query = """
                UPDATE \(DataManager.podcastTableName)
                SET settings = json_set(
                    coalesce(nullif(settings, ''), json(?)),
                    '$.\(name)',
                    json(?)
                ), syncStatus = \(SyncStatus.notSynced.rawValue)
                WHERE uuid = ?
                """
                try db.executeUpdate(query, values: [Self.defaultSettingsJsonString, jsonString, podcastUuid]) // nosemgrep: pocketcasts.no-new-raw-sql-in-data-managers - json_set settings writer; Swift re-encode would drop unmodeled payload fields
            } catch {
                FileLog.shared.addMessage("PodcastDataManager.saveSingleSetting for \(name) error: \(error)")
            }
        }
        cachePodcasts(dbQueue: dbQueue)
    }

    // MARK: - Caching

    func cachePodcasts(dbQueue: GRDBQueue) {
        let trace = TraceManager.shared.beginTracing(eventName: "DATABASE_PODCAST_CACHE")
        defer { TraceManager.shared.endTracing(trace: trace) }

        guard let podcasts = dbQueue.read({ db in
            try Row.fetchAll(db, Podcast.all().asRequest(of: Row.self)).map(Self.podcastWithSettings(from:))
        }) else { return }

        cachedPodcastsQueue.sync {
            cachedPodcasts = Dictionary(podcasts.map { ($0.uuid, $0) }, uniquingKeysWith: { _, last in last })
        }
    }

    // MARK: - Conversion



    private func addedDateSort(p1: Podcast, p2: Podcast) -> Bool {
        guard let date1 = p1.addedDate, let date2 = p2.addedDate else { return false }

        return PodcastSorter.dateAddedSort(date1: date1, date2: date2)
    }

    private func titleSort(p1: Podcast, p2: Podcast) -> Bool {
        guard let title1 = p1.title, let title2 = p2.title else { return false }

        return PodcastSorter.titleSort(title1: title1, title2: title2)
    }
}
