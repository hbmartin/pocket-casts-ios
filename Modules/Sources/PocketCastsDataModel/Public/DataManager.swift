import GRDB
import Foundation
import PocketCastsUtils
import SQLite3

public class DataManager {
    public static let podcastTableName = "SJPodcast"
    public static let episodeTableName = "SJEpisode"
    public static let userEpisodeTableName = "SJUserEpisode"
    public static let playlistsTableName = "SJFilteredPlaylist"
    public static let playlistEpisodeTableName = "SJPlaylistEpisode"
    public static let upNextChangesTableName = "UpNextChanges"
    public static let folderTableName = "Folder"

    private let podcastManager = PodcastDataManager()
    private let upNextManager = UpNextDataManager()
    private let upNextChangesManager = UpNextChangesDataManager()
    private let playlistManager = PlaylistDataManager()
    private let episodeManager = EpisodeDataManager()
    private let userEpisodeManager = UserEpisodeDataManager()
    private let folderManager = FolderDataManager()
    private let upNextHistoryManager = UpNextHistoryManager()
    private let folderHistoryManager = FolderHistoryManager()

    public let autoAddCandidates: AutoAddCandidatesDataManager
    public let bookmarks: BookmarkDataManager
    public let ratings: RatingsDataManager
    public let networkDataUsageManager: NetworkDataUsageManager
    public let transcriptions: TranscriptionDataManager
    public let transcriptSearch: TranscriptSearchDataManager
    public let salientSegments: SalientSegmentDataManager
    public let mentionedEntities: MentionedEntityDataManager
    public let pendingTranscriptUploads: PendingTranscriptUploadDataManager
    public let transcriptEmbeddings: TranscriptEmbeddingDataManager
    public let socialGraph: SocialGraphStore
    public let narrations: NarrationDataManager

    let dbQueue: GRDBQueue

    // nonisolated(unsafe): assigned once during startup; tests swap in a fresh instance
    // from setUp before any concurrent access.
    nonisolated(unsafe) public internal(set) static var sharedManager = DataManager()

    // nonisolated(unsafe): assigned once during app startup, before the database is used.
    nonisolated(unsafe) public static var logger: ErrorLogger?

    // nonisolated(unsafe): legacy database-corruption recovery flag, read once at launch.
    nonisolated(unsafe) public static var loginAgain = false

    /// Creates a DataManager using a queue that is persisted to a local SQLIte file
    public convenience init() {
        DataManager.ensureDbFolderExists()

        var config = Configuration()
        config.busyMode = .timeout(10)
        let dbPool = try! DatabasePool(path: DataManager.pathToDb(), configuration: config)
        let dbQueue = GRDBQueue(dbPool: dbPool, logger: Self.logger)
        DataManager.setDatabaseFileProtectionToNone()

        self.init(dbQueue: dbQueue)
    }

    static func checkDatabaseCorruption(dbPool: DatabasePool) -> Bool {
        var isDatabaseCorrupted = false
        try? dbPool.write { db in
            do {
                let rows = try Row.fetchAll(db, sql: "PRAGMA integrity_check")
                    for row in rows {
                        let result: String = row[0]
                        if result != "ok" {
                            isDatabaseCorrupted = true
                        }
                    }
            } catch {
                if error.localizedDescription.contains("image is malformed") {
                    isDatabaseCorrupted = true
                }
            }
        }

        if isDatabaseCorrupted {
            try? dbPool.close()

            try? FileManager.default.moveItem(at: URL(fileURLWithPath: DataManager.pathToDb()), to: URL(fileURLWithPath: DataManager.pathToDbBackup()))
            try? FileManager.default.moveItem(at: URL(fileURLWithPath: "\(DataManager.pathToDb())-shm"), to: URL(fileURLWithPath: "\(DataManager.pathToDbBackup())-shm"))
            try? FileManager.default.moveItem(at: URL(fileURLWithPath: "\(DataManager.pathToDb())-wal"), to: URL(fileURLWithPath: "\(DataManager.pathToDbBackup())-wal"))
        }

        return isDatabaseCorrupted
    }

    /// Creates a DataManager using the given `GRDBQueue`.
    init(dbQueue: GRDBQueue) {
        self.dbQueue = dbQueue

        guard DatabaseHelper.setup(queue: dbQueue) else {
            preconditionFailure("Failed to setup database")
        }

        // closing it above won't affect these calls, since they will re-open it
        podcastManager.setup(dbQueue: dbQueue)
        folderManager.setup(dbQueue: dbQueue)
        upNextManager.setup(dbQueue: dbQueue)

        autoAddCandidates = AutoAddCandidatesDataManager(dbQueue: dbQueue)
        bookmarks = BookmarkDataManager(dbQueue: dbQueue)
        ratings = RatingsDataManager()
        networkDataUsageManager = NetworkDataUsageManager(dbQueue: dbQueue)
        transcriptions = TranscriptionDataManager(dbQueue: dbQueue)
        transcriptSearch = TranscriptSearchDataManager(dbQueue: dbQueue)
        salientSegments = SalientSegmentDataManager(dbQueue: dbQueue)
        mentionedEntities = MentionedEntityDataManager(dbQueue: dbQueue)
        pendingTranscriptUploads = PendingTranscriptUploadDataManager(dbQueue: dbQueue)
        transcriptEmbeddings = TranscriptEmbeddingDataManager(dbQueue: dbQueue, isAvailable: transcriptSearch.isAvailable)
        socialGraph = SocialGraphStore(dbQueue: dbQueue)
        narrations = NarrationDataManager(dbQueue: dbQueue)
    }

    private var databaseSize: String? {
        let pathToDB = DataManager.pathToDb()
        guard let fileAttributes = try? FileManager.default.attributesOfItem(atPath: pathToDB),
              let size = fileAttributes[.size] as? NSNumber else {
            return nil
        }
        let sizeString = ByteCountFormatter.string(fromByteCount: size.int64Value, countStyle: .file)
        return sizeString
    }

    public func cleanUp() {
        // Retained for source compatibility. Schema cleanup now happens in the baseline bootstrap.
    }

    public func vacuumDatabase() {
        if let sizeString = databaseSize {
            FileLog.shared.addMessage("VACUUM -> Database start size: \(sizeString)")
        }

        FileLog.shared.addMessage("VACUUM -> Start")
        let duration =  DBUtils.measureTime {
            dbQueue.write { db in
                do {
                    try db.executeUpdate("VACUUM;", values: nil)
                } catch {
                    FileLog.shared.addMessage("VACUUM -> error: \(error)")
                }
            }
        }
        FileLog.shared.addMessage("VACUUM -> End")

        FileLog.shared.addMessage("VACUUM -> Duration: \(duration)")
        if let sizeString = databaseSize {
            FileLog.shared.addMessage("VACUUM -> Database end size: \(sizeString)")
        }
    }

    // MARK: - Up Next

    public func allUpNextPlaylistEpisodes() -> [PlaylistEpisode] {
        upNextManager.allUpNextPlaylistEpisodes(dbQueue: dbQueue)
    }

    public func upNextPlayListContains(episodeUuid: String) -> Bool {
        upNextManager.isEpisodePresent(uuid: episodeUuid, dbQueue: dbQueue)
    }

    public func allUpNextEpisodes(from uuids: [String]) -> [Episode] {
        episodeManager.allUpNextEpisodes(from: uuids, dbQueue: dbQueue)
    }

    public func allUpNextEpisodes() -> [BaseEpisode] {
        let allUpNextEpisodes = upNextManager.allUpNextPlaylistEpisodes(dbQueue: dbQueue)
        if allUpNextEpisodes.isEmpty { return [BaseEpisode]() }

        let episodes = episodeManager.allUpNextEpisodes(dbQueue: dbQueue)
        let userEpisodes = userEpisodeManager.allUpNextEpisodes(dbQueue: dbQueue)

        // this extra step is to make sure we return the episodes in the order they are in the up next list, which they won't be if there's both Episodes and UserEpisodes in Up Next
        if userEpisodes.isEmpty {
            return episodes
        }

        var convertedEpisodes = [BaseEpisode]()
        var episodeIndex = 0
        var userEpisodeIndex = 0
        for upNextEpisode in allUpNextEpisodes {
            if let episode = episodes[safe: episodeIndex],
               episode.uuid == upNextEpisode.episodeUuid {
                convertedEpisodes.append(episode)
                episodeIndex += 1
                continue
            }
            if let userEpisode = userEpisodes[safe: userEpisodeIndex], userEpisode.uuid == upNextEpisode.episodeUuid {
                convertedEpisodes.append(userEpisode)
                userEpisodeIndex += 1
            }
        }

        return convertedEpisodes
    }

    public func allUpNextEpisodeUuids() -> [BaseEpisode] {
        upNextManager.allUpNextPlaylistEpisodes(dbQueue: dbQueue).map {
            var episode = Episode()
            episode.uuid = $0.episodeUuid
            episode.hasOnlyUuid = true
            return episode
        }
    }

    public func findPlaylistEpisode(uuid: String) -> PlaylistEpisode? {
        upNextManager.findPlaylistEpisode(uuid: uuid, dbQueue: dbQueue)
    }

    public func positionForPlaylistEpisode(bottomOfList: Bool) -> Int32 {
        upNextManager.positionForPlaylistEpisode(bottomOfList: bottomOfList, dbQueue: dbQueue)
    }

    public func deleteAllUpNextEpisodes() {
        upNextManager.deleteAllUpNextEpisodes(dbQueue: dbQueue)
    }

    public func deleteAllUpNextEpisodesExcept(episodeUuid: String) {
        upNextManager.deleteAllUpNextEpisodesExcept(episodeUuid: episodeUuid, dbQueue: dbQueue)
    }

    public func deleteAllUpNextEpisodesNotIn(uuids: [String]) {
        upNextManager.deleteAllUpNextEpisodesNotIn(uuids: uuids, dbQueue: dbQueue)
    }

    public func deleteAllUpNextEpisodesIn(uuids: [String]) {
        upNextManager.deleteAllUpNextEpisodesIn(uuids: uuids, dbQueue: dbQueue)
    }

    public func save(playlistEpisode: PlaylistEpisode) {
        upNextManager.save(playlistEpisode: playlistEpisode, dbQueue: dbQueue)
    }

    public func save(playlistEpisodes: [PlaylistEpisode]) {
        upNextManager.save(playlistEpisodes: playlistEpisodes, dbQueue: dbQueue)
    }

    public func delete(playlistEpisode: PlaylistEpisode) {
        upNextManager.delete(playlistEpisode: playlistEpisode, dbQueue: dbQueue)
    }

    public func movePlaylistEpisode(from: Int, to: Int) {
        upNextManager.movePlaylistEpisode(from: from, to: to, dbQueue: dbQueue)
    }

    public func playlistEpisodeCount() -> Int {
        upNextManager.playlistEpisodeCount(dbQueue: dbQueue)
    }

    public func playlistEpisodeAt(index: Int) -> PlaylistEpisode? {
        upNextManager.playlistEpisodeAt(index: index, dbQueue: dbQueue)
    }

    public func episodeInUpNextAt(index: Int) -> BaseEpisode? {
        guard let playlistEpisode = playlistEpisodeAt(index: index) else { return nil }

        if let episode = userEpisodeManager.findBy(uuid: playlistEpisode.episodeUuid, dbQueue: dbQueue) {
            return episode
        }

        return episodeManager.findBy(uuid: playlistEpisode.episodeUuid, dbQueue: dbQueue)
    }

    // MARK: - Up Next Changes

    public func findReplaceAction() -> UpNextChanges? {
        upNextChangesManager.findReplaceAction(dbQueue: dbQueue)
    }

    public func findUpdateActions() -> [UpNextChanges] {
        upNextChangesManager.findUpdateActions(dbQueue: dbQueue)
    }

    public func saveUpNextRemove(episodeUuid: String) {
        dbQueue.inTransaction { db in
            try upNextChangesManager.saveUpNextRemove(episodeUuid: episodeUuid, db: db)
        }
    }

    public func saveUpNextAddToTop(episodeUuid: String) {
        dbQueue.inTransaction { db in
            try upNextChangesManager.saveUpNextAddToTop(episodeUuid: episodeUuid, db: db)
        }
    }

    public func saveUpNextAddToBottom(episodeUuid: String) {
        dbQueue.inTransaction { db in
            try upNextChangesManager.saveUpNextAddToBottom(episodeUuid: episodeUuid, db: db)
        }
    }

    public func saveUpNextAddNowPlaying(episodeUuid: String) {
        dbQueue.inTransaction { db in
            try upNextChangesManager.saveUpNextAddNowPlaying(episodeUuid: episodeUuid, db: db)
        }
    }

    public func saveReplace(episodeList: [String]) {
        dbQueue.inTransaction { db in
            try upNextChangesManager.saveReplace(episodeList: episodeList, db: db)
        }
    }

    public func deleteChangesOlderThan(utcTime: Int64) {
        upNextChangesManager.deleteChangesOlderThan(utcTime: utcTime, dbQueue: dbQueue)
    }

    // MARK: - Podcasts

    public func allPodcasts(includeUnsubscribed: Bool, reloadFromDatabase: Bool = false) -> [Podcast] {
        podcastManager.allPodcasts(includeUnsubscribed: includeUnsubscribed, reloadFromDatabase: reloadFromDatabase, dbQueue: dbQueue)
    }

    public func searchPodcasts(term: String) -> [Podcast] {
        podcastManager.searchPodcasts(term: term, dbQueue: dbQueue)
    }

    public func allPodcastsOrderedByTitle(reloadFromDatabase: Bool = false) -> [Podcast] {
        podcastManager.allPodcastsOrderedByTitle(reloadFromDatabase: reloadFromDatabase, dbQueue: dbQueue)
    }

    public func allPodcastsOrderedByNewestEpisodes(reloadFromDatabase: Bool = false) -> [Podcast] {
        podcastManager.allPodcastsOrderedByNewestEpisodes(reloadFromDatabase: reloadFromDatabase, dbQueue: dbQueue)
    }

    public func allPodcastsOrderedByLastPlayedEpisodes(reloadFromDatabase: Bool = false) -> [Podcast] {
        podcastManager.allPodcastsOrderedByLastPlayedEpisodes(reloadFromDatabase: reloadFromDatabase, dbQueue: dbQueue)
    }

    public func allPodcastsOrderedByAddedDate(reloadFromDatabase: Bool = false) -> [Podcast] {
        podcastManager.allPodcastsOrderedByAddedDate(reloadFromDatabase: reloadFromDatabase, dbQueue: dbQueue)
    }

    public func findPodcast(uuid: String, includeUnsubscribed: Bool = false) -> Podcast? {
        podcastManager.find(uuid: uuid, includeUnsubscribed: includeUnsubscribed, dbQueue: dbQueue)
    }

    public func allUnsubscribedPodcastUuids() -> [String] {
        podcastManager.allUnsubscribedPodcastUuids(dbQueue: dbQueue)
    }

    public func allUnsubscribedPodcasts() -> [Podcast] {
        podcastManager.allUnsubscribedPodcasts(dbQueue: dbQueue)
    }

    public func allPaidPodcasts() -> [Podcast] {
        podcastManager.allPaidPodcasts(dbQueue: dbQueue)
    }

    public func allOverrideGlobalArchivePodcasts() -> [Podcast] {
        podcastManager.allOverrideGlobalArchivePodcasts(dbQueue: dbQueue)
    }

    public func podcastCount() -> Int {
        podcastManager.count(dbQueue: dbQueue)
    }

    public func podcastUnfinishedCounts() -> [String: Int32] {
        podcastManager.unfinishedCounts(dbQueue: dbQueue)
    }

    public func markAllPodcastsSynced() {
        podcastManager.markAllSynced(dbQueue: dbQueue)
    }

    public func markAllPodcastsUnsynced() {
        podcastManager.markAllUnsynced(dbQueue: dbQueue)
    }

    public func markAllPodcastsUnsyncedWhereLastSyncAtNot(_ lastSyncAt: String) {
        podcastManager.markAllUnsyncedWhereLastSyncAtNot(lastSyncAt, dbQueue: dbQueue)
    }

    public func setPushForAllPodcasts(pushEnabled: Bool) {
        podcastManager.setPushForAllPodcasts(pushEnabled: pushEnabled, dbQueue: dbQueue)
    }

    public func saveAutoAddToUpNextForAllPodcasts(autoAddToUpNext: Int32) {
        podcastManager.saveAutoAddToUpNextForAllPodcasts(autoAddToUpNext: autoAddToUpNext, dbQueue: dbQueue)
    }

    public func updateAutoAddToUpNext(to value: AutoAddToUpNextSetting, for podcasts: [Podcast]) {
        podcastManager.updateAutoAddToUpNext(to: value, for: podcasts, in: dbQueue)
    }

    public func setDownloadSettingForAllPodcasts(setting: AutoDownloadSetting) {
        podcastManager.setDownloadSettingForAllPodcasts(setting: setting, dbQueue: dbQueue)
    }

    public func allUnsyncedPodcasts() -> [Podcast] {
        podcastManager.allUnsynced(dbQueue: dbQueue)
    }

    public func delete(podcast: Podcast) {
        let success = dbQueue.inTransaction { db in
            try podcastManager.delete(podcast: podcast, db: db)
        }
        if success {
            podcastManager.cachePodcasts(dbQueue: dbQueue)
        }
    }

    @discardableResult
    public func save(podcast: Podcast) -> Podcast {
        var saved = podcast
        let success = dbQueue.inTransaction { db in
            saved = try podcastManager.save(podcast: podcast, db: db)
        }
        if success {
            podcastManager.cachePodcasts(dbQueue: dbQueue)
        }
        return saved
    }

    public func savePushSetting(podcast: Podcast, pushEnabled: Bool) {
        podcastManager.savePushSetting(podcast: podcast, pushEnabled: pushEnabled, dbQueue: dbQueue)
    }

    public func savePushSetting(podcastUuid: String, pushEnabled: Bool) {
        podcastManager.savePushSetting(podcastUuid: podcastUuid, pushEnabled: pushEnabled, dbQueue: dbQueue)
    }

    /// Atomically updates only the podcast's auto-add fields and sync status, so callers holding
    /// an older `Podcast` value cannot overwrite unrelated changes made after it was loaded.
    public func saveAutoAddToUpNext(podcastUuid: String, autoAddToUpNext: Int32) {
        podcastManager.saveAutoAddToUpNext(podcastUuid: podcastUuid, autoAddToUpNext: autoAddToUpNext, dbQueue: dbQueue)
    }

    /// Persists the chapter smart-skip title patterns for a podcast into the settings JSON payload.
    /// Writes through the json_set settings writer so it works regardless of `newSettingsStorage`.
    public func saveSkipChapterTitles(_ titles: [String], podcastUuid: String) {
        podcastManager.saveSkipChapterTitles(titles, podcastUuid: podcastUuid, dbQueue: dbQueue)
    }

    /// Persists the per-podcast auto-transcribe-on-download opt-in into the settings JSON payload.
    /// Device-local behavior — the field never syncs to the server.
    public func saveDisableRemoteTranscription(_ disabled: Bool, podcastUuid: String) {
        podcastManager.saveDisableRemoteTranscription(disabled, podcastUuid: podcastUuid, dbQueue: dbQueue)
    }

    public func savePodcastDownloadSetting(_ setting: AutoDownloadSetting, podcastUuid: String) {
        podcastManager.savePodcastDownloadSetting(setting, podcastUuid: podcastUuid, dbQueue: dbQueue)
    }

    public func saveAutoArchiveLimit(podcast: Podcast, limit: Int32) {
        podcastManager.saveAutoArchiveLimit(podcast: podcast, limit: limit, dbQueue: dbQueue)
    }

    public func saveSortOrders(podcasts: [Podcast]) {
        podcastManager.saveSortOrders(podcasts: podcasts, dbQueue: dbQueue)
    }

    public func markAllUnarchivedForPodcast(id: Int64) {
        episodeManager.markAllUnarchivedForPodcast(id: id, dbQueue: dbQueue)
    }

    public func updateAllPodcastGrouping(to grouping: PodcastGrouping) {
        podcastManager.updateAllPodcastGrouping(to: grouping, dbQueue: dbQueue)
    }

    public func updateAllShowArchived(to showArchived: Bool) {
        podcastManager.updateAllShowArchived(to: showArchived, dbQueue: dbQueue)
    }

    public func setPodcastImageVersion(podcastUuid: String, version: Int) {
        podcastManager.setPodcastImageVersion(podcastUuid: podcastUuid, version: version, dbQueue: dbQueue)
    }

    public func setAllPodcastImageVersions(to version: Int) {
        podcastManager.setAllPodcastImageVersions(to: version, dbQueue: dbQueue)
    }

    public func bulkSetFolderUuid(folderUuid: String, podcastUuids: [String]) {
        podcastManager.bulkSetFolderUuid(folderUuid: folderUuid, podcastUuids: podcastUuids, dbQueue: dbQueue)
    }

    public func updatePodcastFolder(podcastUuid: String, to folderUuid: String?, sortOrder: Int32) {
        podcastManager.updatePodcastFolder(podcastUuid: podcastUuid, sortOrder: sortOrder, folderUuid: folderUuid, dbQueue: dbQueue)
    }

    // MARK: - Episodes

    public func findEpisode(uuid: String) -> Episode? {
        episodeManager.findBy(uuid: uuid, dbQueue: dbQueue)
    }

    /// Native-async variant of `findEpisode(uuid:)`; the read runs on the
    /// database engine's reader pool instead of blocking the calling thread.
    public func findEpisodeAsync(uuid: String) async -> Episode? {
        await episodeManager.findByAsync(uuid: uuid, dbQueue: dbQueue)
    }

    public func findBaseEpisode(uuid: String) -> BaseEpisode? {
        if let episode = userEpisodeManager.findBy(uuid: uuid, dbQueue: dbQueue) {
            return episode
        }

        return episodeManager.findBy(uuid: uuid, dbQueue: dbQueue)
    }

    /// Native-async variant of `findBaseEpisode(uuid:)`; the reads run on the
    /// database engine's reader pool instead of blocking the calling thread.
    public func findBaseEpisodeAsync(uuid: String) async -> BaseEpisode? {
        if let episode = await userEpisodeManager.findByAsync(uuid: uuid, dbQueue: dbQueue) {
            return episode
        }

        return await episodeManager.findByAsync(uuid: uuid, dbQueue: dbQueue)
    }

    public func findEpisodeCount(podcastId: Int64) -> Int {
        count(query: "SELECT COUNT(*) FROM \(DataManager.episodeTableName) WHERE podcast_id == ?", values: [podcastId])
    }

    public func findPlayedEpisodes(uuids: [String]) -> [String] {
        episodeManager.findPlayedEpisodes(uuids: uuids, dbQueue: dbQueue)
    }

    public func findMatchingEpisodes(uuids: [String]) -> [String] {
        episodeManager.findMatchingEpisodes(uuids: uuids, dbQueue: dbQueue)
    }

    public func findPlayedEpisodesCount(podcastId: Int64) async -> Int {
        await episodeManager.findPlayedEpisodesCount(podcastId: podcastId, dbQueue: dbQueue)
    }

    public func markAllEpisodePlaybackHistorySynced() {
        episodeManager.markAllEpisodePlaybackHistorySynced(dbQueue: dbQueue)
    }

    public func downloadedEpisodeExists(uuid: String) -> Bool {
        episodeManager.downloadedEpisodeExists(uuid: uuid, dbQueue: dbQueue)
    }

    public func findBaseEpisode(downloadTaskId: String) -> BaseEpisode? {
        if let episode = userEpisodeManager.findBy(downloadTaskId: downloadTaskId, dbQueue: dbQueue) {
            return episode
        }

        return episodeManager.findBy(downloadTaskId: downloadTaskId, dbQueue: dbQueue)
    }

    public func findEpisodeWhere(customWhere: String, arguments: [Any]?) -> Episode? {
        episodeManager.findWhere(customWhere: customWhere, arguments: arguments, dbQueue: dbQueue)
    }

    public func findEpisodesWhereNotNull(propertyName: String) -> [BaseEpisode] {
        var episodes = episodeManager.findWhereNotNull(columnName: propertyName, dbQueue: dbQueue) as [BaseEpisode]
        let userEpisodes = userEpisodeManager.findWhereNotNull(columnName: propertyName, dbQueue: dbQueue) as [BaseEpisode]
        episodes.append(contentsOf: userEpisodes)
        return episodes
    }

    /// RETAINED raw-SQL API: playlist queries moved to the typed `episodes(matching:)`,
    /// but many non-playlist call sites (download cleanup, podcast episode lists,
    /// sync history, mirrors) still build WHERE strings. Do not add new callers;
    /// migrate to typed requests instead.
    public func findEpisodesWhere(customWhere: String, arguments: [Any]?) -> [Episode] {
        episodeManager.findEpisodesWhere(customWhere: customWhere, arguments: arguments, dbQueue: dbQueue)
    }

    public func findEpisodes(with term: String, podcastUUID: String) -> [Episode] {
        episodeManager.findEpisodes(with: term, podcastUUID: podcastUUID, dbQueue: dbQueue)
    }

    /// LEGACY, test-only: executes a full raw playlist SQL string. Kept internal as
    /// the golden-reference execution path for PlaylistQueryBuilderParityTests; all
    /// production playlist fetches use `episodes(matching:)`.
    func findPlaylistEpisodesWhere(query: String, arguments: [Any]?) -> [Episode] {
        episodeManager.findPlaylistEpisodesWhere(query: query, arguments: arguments, dbQueue: dbQueue)
    }

    /// Fetches episodes matching a typed request (see `PlaylistQueryBuilder`'s
    /// `episodesRequest`/`filterEpisodesRequest`). Prefer this over the raw-string
    /// `findEpisodesWhere`/`findPlaylistEpisodesWhere` APIs for playlist queries.
    public func episodes(matching request: SQLRequest<Episode>) -> [Episode] {
        dbQueue.fetchAll(request)
    }

    /// Fetches a single count value from a typed request (see `PlaylistQueryBuilder.countRequest`).
    public func count(matching request: SQLRequest<Int>) -> Int {
        dbQueue.fetchValue(request) ?? 0
    }

    /// Whether a typed existence probe (a `SELECT 1 ... LIMIT 1` request such as
    /// `PlaylistQueryBuilder.podcastExistsInPlaylistEpisodesRequest`) returns a row.
    public func exists(matching request: SQLRequest<Int>) -> Bool {
        dbQueue.fetchValue(request) != nil
    }

    public func findEpisodesAndPodcastsWhere(customWhere: String, listenedTo: Bool) -> [Episode] {
        episodeManager.findEpisodesAndPodcastsWhere(customWhere: customWhere, listenedTo: listenedTo, dbQueue: dbQueue)
    }

    public func findLatestEpisode(podcast: Podcast) -> Episode? {
        episodeManager.findLatestEpisode(podcast: podcast, dbQueue: dbQueue)
    }

    public func findLatestEpisodes(podcast: Podcast, limit: Int) -> [Episode] {
        episodeManager.findLatestEpisodes(podcast: podcast, limit: limit, dbQueue: dbQueue)
    }

    public func unsyncedEpisodes(limit: Int) -> [Episode] {
        episodeManager.unsyncedEpisodes(limit: limit, dbQueue: dbQueue)
    }

    public func episodesWithListenHistory(limit: Int) -> [Episode] {
        episodeManager.episodesWithListenHistory(limit: limit, dbQueue: dbQueue)
    }

    public func dailyListeningTime(forLast days: Int = 365) -> [String: Double] {
        episodeManager.dailyListeningTime(forLast: days, dbQueue: dbQueue)
    }

    public func failedDownloadedEpisodesCount() -> Int {
        episodeManager.failedDownloadEpisodeCount(dbQueue: dbQueue)
    }

    public func oldestFailedEpisodeDownload() -> Date? {
        episodeManager.failedDownloadFirstDate(dbQueue: dbQueue, sortOrder: .reverse)
    }

    public func newestFailedEpisodeDownload() -> Date? {
        episodeManager.failedDownloadFirstDate(dbQueue: dbQueue, sortOrder: .forward)
    }

    public func findDownloadedEpisodes() -> [BaseEpisode] {
        let query = "episodeStatus = \(DownloadStatus.downloaded.rawValue)"
        let downloadedEpisodes = findEpisodesWhere(customWhere: query, arguments: nil)

        let downloadedUserEpisodes = userEpisodeManager.findAllDownloaded(sortedBy: .newestToOldest, dbQueue: dbQueue)
        var allEpisodes: [BaseEpisode] = downloadedEpisodes + downloadedUserEpisodes

        allEpisodes.sort(by: { $0.lastDownloadAttemptDate?.compare($1.lastDownloadAttemptDate ?? Date.distantPast) == .orderedDescending })
        return allEpisodes
    }

    public func downloadedEpisodeCount() -> Int {
        let episodeCount = episodeManager.downloadedEpisodeCount(dbQueue: dbQueue)
        let userEpisodeCount = userEpisodeManager.downloadedEpisodeCount(dbQueue: dbQueue)
        return episodeCount + userEpisodeCount
    }

    /// Count of unplayed, unarchived episodes belonging to subscribed podcasts,
    /// optionally restricted to episodes added after a date. Backs the app icon badge.
    public func subscribedUnplayedEpisodeCount(addedAfter: Date? = nil) -> Int {
        count(matching: Self.subscribedUnplayedCountRequest(addedAfter: addedAfter))
    }

    /// Single source of truth for the badge's unplayed-count SQL: the synchronous
    /// `subscribedUnplayedEpisodeCount` and `observeBadgeCount(.subscribedUnplayed)`
    /// both run exactly this request.
    static func subscribedUnplayedCountRequest(addedAfter: Date?) -> SQLRequest<Int> {
        var query: SQL = "SELECT COUNT(e.id) FROM \(sql: DataManager.episodeTableName) e LEFT JOIN \(sql: DataManager.podcastTableName) p ON p.id = e.podcast_id WHERE p.subscribed = 1 AND e.playingStatus = \(PlayingStatus.notPlayed.rawValue) AND e.archived = 0"
        if let addedAfter {
            // addedDate is stored as epoch seconds (REAL), matching the legacy Date binding
            query = query + " AND e.addedDate > \(addedAfter.timeIntervalSince1970)"
        }
        return SQLRequest(literal: query)
    }

    public func save(episode: BaseEpisode) {
        if let episode = episode as? Episode {
            episodeManager.save(episode: episode, dbQueue: dbQueue)
        } else if let episode = episode as? UserEpisode {
            userEpisodeManager.save(episode: episode, dbQueue: dbQueue)
        }
    }

    /// Value-type UserEpisode: returns the saved copy carrying the generated row id.
    @discardableResult
    public func save(episode: UserEpisode) -> UserEpisode {
        userEpisodeManager.save(episode: episode, dbQueue: dbQueue)
    }

    /// Value-type Episode: returns the saved copy carrying the generated row id.
    @discardableResult
    public func save(episode: Episode) -> Episode {
        episodeManager.save(episode: episode, dbQueue: dbQueue)
    }

    public func bulkSave(episodes: [Episode]) {
        episodeManager.bulkSave(episodes: episodes, dbQueue: dbQueue)
    }

    public func bulkSetStarred(starred: Bool, episodes: [Episode], updateSyncStatus: Bool) {
        episodeManager.bulkSetStarred(starred: starred, episodes: episodes, updateSyncFlag: updateSyncStatus, dbQueue: dbQueue)
    }

    public func bulkUserFileDelete(baseEpisodes: [BaseEpisode]) {
        let episodes = baseEpisodes.compactMap { $0 as? Episode }
        if !episodes.isEmpty {
            episodeManager.bulkUserFileDelete(episodes: episodes, dbQueue: dbQueue)
        }
        let userEpisodes = baseEpisodes.compactMap { $0 as? UserEpisode }
        if !userEpisodes.isEmpty {
            userEpisodeManager.bulkUserFileDelete(episodes: userEpisodes, dbQueue: dbQueue)
        }
    }

    // returns true if the save succeeded, false otherwise
    public func saveIfNotModified(starred: Bool, episodeUuid: String) -> Bool {
        episodeManager.saveIfNotModified(starred: starred, episodeUuid: episodeUuid, dbQueue: dbQueue)
    }

    // returns true if the save succeeded, false otherwise
    public func saveIfNotModified(archived: Bool, episodeUuid: String) -> Bool {
        episodeManager.saveIfNotModified(archived: archived, episodeUuid: episodeUuid, dbQueue: dbQueue)
    }

    // returns true if the save succeeded, false otherwise
    public func saveIfNotModified(playingStatus: PlayingStatus, episodeUuid: String) -> Bool {
        episodeManager.saveIfNotModified(playingStatus: playingStatus, episodeUuid: episodeUuid, dbQueue: dbQueue)
    }

    // returns true if the save succeeded, false otherwise
    @discardableResult
    public func saveIfNotModified(chapters: String, remoteModified: Int64, episodeUuid: String) -> Bool {
        episodeManager.saveIfNotModified(chapters: chapters, remoteModified: remoteModified, episodeUuid: episodeUuid, dbQueue: dbQueue)
    }

    public func saveEpisode(playedUpTo: Double, episode: BaseEpisode, updateSyncFlag: Bool) {
        let trace = TraceManager.shared.beginTracing(eventName: "DATABASE_EPISODE_POSITION_SAVE")
        defer { TraceManager.shared.endTracing(trace: trace) }

        dbQueue.inTransaction { db in
            if let episode = episode as? Episode {
                try episodeManager.saveEpisode(playedUpTo: playedUpTo, episode: episode, updateSyncFlag: updateSyncFlag, db: db)
            } else if let episode = episode as? UserEpisode {
                try userEpisodeManager.saveEpisode(playedUpTo: playedUpTo, episode: episode, updateSyncFlag: updateSyncFlag, db: db)
            }
        }
    }

    public func saveEpisode(playingStatus: PlayingStatus, episode: BaseEpisode, updateSyncFlag: Bool) {
        dbQueue.inTransaction { db in
            if let episode = episode as? Episode {
                try episodeManager.saveEpisode(playingStatus: playingStatus, episode: episode, updateSyncFlag: updateSyncFlag, db: db)
            } else if let episode = episode as? UserEpisode {
                try userEpisodeManager.saveEpisode(playingStatus: playingStatus, episode: episode, updateSyncFlag: updateSyncFlag, db: db)
            }
        }
    }

    public func saveEpisode(archived: Bool, episode: Episode, updateSyncFlag: Bool) {
        dbQueue.inTransaction { db in
            try episodeManager.saveEpisode(archived: archived, episode: episode, updateSyncFlag: updateSyncFlag, db: db)
        }
    }

    public func saveEpisode(excludeFromEpisodeLimit: Bool, episode: Episode) {
        episodeManager.saveEpisode(excludeFromEpisodeLimit: excludeFromEpisodeLimit, episode: episode, dbQueue: dbQueue)
    }

    public func saveEpisode(fileType: String, episode: Episode) {
        episodeManager.saveFileType(episode: episode, fileType: fileType, dbQueue: dbQueue)
    }

    public func saveEpisode(contentType: String, episode: BaseEpisode) {
        if let episode = episode as? Episode {
            episodeManager.saveContentType(episode: episode, contentType: contentType, dbQueue: dbQueue)
        } else if let episode = episode as? UserEpisode {
            userEpisodeManager.saveContentType(contentType: contentType, episode: episode, dbQueue: dbQueue)
        }
    }

    public func saveEpisode(fileSize: Int64, episode: Episode) {
        episodeManager.saveFileSize(episode: episode, fileSize: fileSize, dbQueue: dbQueue)
    }

    public func saveBulkEpisodeSyncInfo(episodes: [EpisodeBasicData]) {
        episodeManager.saveBulkEpisodeSyncInfo(episodes: episodes, dbQueue: dbQueue)
    }

    public func saveFrameCount(episode: BaseEpisode, frameCount: Int64) {
        if let episode = episode as? Episode {
            episodeManager.saveFrameCount(episodeId: episode.id, frameCount: frameCount, dbQueue: dbQueue)
        } else if let episode = episode as? UserEpisode {
            userEpisodeManager.saveFrameCount(episodeId: episode.id, frameCount: frameCount, dbQueue: dbQueue)
        }
    }

    public func findFrameCount(episode: BaseEpisode) -> Int64 {
        if let episode = episode as? Episode {
            return episodeManager.findFrameCount(episodeId: episode.id, dbQueue: dbQueue)
        }

        let userEpisode = episode as! UserEpisode
        return userEpisodeManager.findFrameCount(episodeId: userEpisode.id, dbQueue: dbQueue)
    }

    /// Stores the integrated BS.1770 loudness (LUFS) measured for the episode's
    /// downloaded file; 0 means "not measured".
    public func saveLoudness(episode: BaseEpisode, loudness: Double) {
        if let episode = episode as? Episode {
            episodeManager.saveLoudness(episodeId: episode.id, loudness: loudness, dbQueue: dbQueue)
        } else if let episode = episode as? UserEpisode {
            userEpisodeManager.saveLoudness(episodeId: episode.id, loudness: loudness, dbQueue: dbQueue)
        }
    }

    public func findLoudness(episode: BaseEpisode) -> Double {
        if let episode = episode as? Episode {
            return episodeManager.findLoudness(episodeId: episode.id, dbQueue: dbQueue)
        }
        if let userEpisode = episode as? UserEpisode {
            return userEpisodeManager.findLoudness(episodeId: userEpisode.id, dbQueue: dbQueue)
        }

        return 0
    }

    /// Zeroes the cached frame count and loudness; call whenever the episode's
    /// local file is replaced so stale measurements never seed the player.
    public func clearCachedAudioMetadata(episode: BaseEpisode) {
        if let episode = episode as? Episode {
            episodeManager.clearCachedAudioMetadata(episodeId: episode.id, dbQueue: dbQueue)
        } else if let episode = episode as? UserEpisode {
            userEpisodeManager.clearCachedAudioMetadata(episodeId: episode.id, dbQueue: dbQueue)
        }
    }

    public func saveEpisode(starred: Bool, starredModified: Int64? = nil, episode: Episode, updateSyncFlag: Bool) {
        dbQueue.inTransaction { db in
            try episodeManager.saveEpisode(starred: starred, starredModified: starredModified, episode: episode, updateSyncFlag: updateSyncFlag, db: db)
        }
    }

    public func saveEpisode(duration: Double, episode: BaseEpisode, updateSyncFlag: Bool) {
        dbQueue.inTransaction { db in
            if let episode = episode as? Episode {
                try episodeManager.saveEpisode(duration: duration, episode: episode, updateSyncFlag: updateSyncFlag, db: db)
            } else if let episode = episode as? UserEpisode {
                try userEpisodeManager.saveEpisode(duration: duration, episode: episode, db: db)
            }
        }
    }

    public func saveEpisode(playbackError: String?, episode: BaseEpisode) {
        if let episode = episode as? Episode {
            episodeManager.saveEpisode(playbackError: playbackError, episode: episode, dbQueue: dbQueue)
        } else if let episode = episode as? UserEpisode {
            userEpisodeManager.saveEpisode(playbackError: playbackError, episode: episode, dbQueue: dbQueue)
        }
    }

    public func saveEpisode(downloadStatus: DownloadStatus, episode: Episode) {
        episodeManager.saveEpisode(downloadStatus: downloadStatus, episode: episode, dbQueue: dbQueue)
    }

    public func saveEpisode(downloadStatus: DownloadStatus, lastDownloadAttemptDate: Date, autoDownloadStatus: AutoDownloadStatus, episode: BaseEpisode) {
        if let episode = episode as? Episode {
            episodeManager.saveEpisode(downloadStatus: downloadStatus, lastDownloadAttemptDate: lastDownloadAttemptDate, autoDownloadStatus: autoDownloadStatus, episode: episode, dbQueue: dbQueue)
        } else if let episode = episode as? UserEpisode {
            userEpisodeManager.saveEpisode(downloadStatus: downloadStatus, lastDownloadAttemptDate: lastDownloadAttemptDate, autoDownloadStatus: autoDownloadStatus, episode: episode, dbQueue: dbQueue)
        }
    }

    public func saveEpisode(downloadStatus: DownloadStatus, downloadError: String?, downloadTaskId: String?, episode: BaseEpisode) {
        if let episode = episode as? Episode {
            episodeManager.saveEpisode(downloadStatus: downloadStatus, downloadError: downloadError, downloadTaskId: downloadTaskId, episode: episode, dbQueue: dbQueue)
        } else if let episode = episode as? UserEpisode {
            userEpisodeManager.saveEpisode(downloadStatus: downloadStatus, downloadError: downloadError, downloadTaskId: downloadTaskId, episode: episode, dbQueue: dbQueue)
        }
    }

    public func saveEpisode(autoDownloadStatus: AutoDownloadStatus, episode: BaseEpisode) {
        if let episode = episode as? Episode {
            episodeManager.saveEpisode(autoDownloadStatus: autoDownloadStatus, episode: episode, dbQueue: dbQueue)
        } else if let episode = episode as? UserEpisode {
            userEpisodeManager.saveEpisode(autoDownloadStatus: autoDownloadStatus, episode: episode, dbQueue: dbQueue)
        }
    }

    public func saveEpisode(downloadStatus: DownloadStatus, downloadTaskId: String?, episode: BaseEpisode) {
        if let episode = episode as? Episode {
            episodeManager.saveEpisode(downloadStatus: downloadStatus, downloadTaskId: downloadTaskId, episode: episode, dbQueue: dbQueue)
        } else if let episode = episode as? UserEpisode {
            userEpisodeManager.saveEpisode(downloadStatus: downloadStatus, downloadTaskId: downloadTaskId, episode: episode, dbQueue: dbQueue)
        }
    }

    public func saveEpisode(downloadStatus: DownloadStatus, sizeInBytes: Int64, downloadTaskId: String?, episode: BaseEpisode) {
        if let episode = episode as? Episode {
            episodeManager.saveEpisode(downloadStatus: downloadStatus, sizeInBytes: sizeInBytes, downloadTaskId: downloadTaskId, episode: episode, dbQueue: dbQueue)
        } else if let episode = episode as? UserEpisode {
            userEpisodeManager.saveEpisode(downloadStatus: downloadStatus, sizeInBytes: sizeInBytes, downloadTaskId: downloadTaskId, episode: episode, dbQueue: dbQueue)
        }
    }

    public func saveEpisode(downloadStatus: DownloadStatus, sizeInBytes: Int64, episode: BaseEpisode) {
        if let episode = episode as? Episode {
            episodeManager.saveEpisode(downloadStatus: downloadStatus, sizeInBytes: sizeInBytes, downloadTaskId: episode.uuid, episode: episode, dbQueue: dbQueue)
        } else if let episode = episode as? UserEpisode {
            userEpisodeManager.saveEpisode(downloadStatus: downloadStatus, sizeInBytes: sizeInBytes, episode: episode, dbQueue: dbQueue)
        }
    }

    public func saveEpisode(downloadUrl: String, episodeUuid: String) {
        episodeManager.saveEpisode(downloadUrl: downloadUrl, episodeUuid: episodeUuid, dbQueue: dbQueue)
    }

    public func updateEpisodePlaybackInteractionDate(episode: BaseEpisode) {
        // only Episodes have playback interaction dates, we don't have those for UserEpisodes
        if let episode = episode as? Episode {
            episodeManager.updateEpisodePlaybackInteractionDate(episode: episode, dbQueue: dbQueue)
        }
    }

    public func setEpisodePlaybackInteractionDate(interactionDate: Date, episodeUuid: String) {
        episodeManager.setEpisodePlaybackInteractionDate(interactionDate: interactionDate, episodeUuid: episodeUuid, dbQueue: dbQueue)
    }

    public func clearKeepEpisodeModified(episode: Episode) {
        episodeManager.clearKeepEpisodeModified(episode: episode, dbQueue: dbQueue)
    }

    public func clearEpisodePlaybackInteractionDate(episodeUuid: String) {
        episodeManager.clearEpisodePlaybackInteractionDate(episodeUuid: episodeUuid, dbQueue: dbQueue)
    }

    public func clearEpisodePlaybackInteractionDatesBefore(date: Date) {
        episodeManager.clearEpisodePlaybackInteractionDatesBefore(date: date, dbQueue: dbQueue)
    }

    public func clearAllEpisodePlayInteractions() {
        episodeManager.clearAllEpisodePlaybackInteractions(dbQueue: dbQueue)
    }

    public func clearDownloadTaskId(episode: BaseEpisode) {
        if let episode = episode as? Episode {
            episodeManager.clearDownloadTaskId(episode: episode, dbQueue: dbQueue)
        } else if let episode = episode as? UserEpisode {
            userEpisodeManager.clearDownloadTaskId(episode: episode, dbQueue: dbQueue)
        }
    }

    public func bulkMarkAsPlayed(episodes: [Episode], updateSyncFlag: Bool) {
        episodeManager.bulkMarkAsPlayed(episodes: episodes, updateSyncFlag: updateSyncFlag, dbQueue: dbQueue)
    }

    public func bulkMarkAsPlayed(episodes: [UserEpisode], updateSyncFlag: Bool) {
        userEpisodeManager.bulkMarkAsPlayed(episodes: episodes, updateSyncFlag: updateSyncFlag, dbQueue: dbQueue)
    }

    public func bulkMarkAsUnPlayed(baseEpisodes: [BaseEpisode], updateSyncFlag: Bool) {
        let episodes = baseEpisodes.compactMap { $0 as? Episode }
        if !episodes.isEmpty {
            episodeManager.bulkMarkAsUnPlayed(episodes: episodes, updateSyncFlag: updateSyncFlag, dbQueue: dbQueue)
        }

        let userEpisodes = baseEpisodes.compactMap { $0 as? UserEpisode }
        if !userEpisodes.isEmpty {
            userEpisodeManager.bulkMarkAsUnPlayed(episodes: userEpisodes, updateSyncFlag: updateSyncFlag, dbQueue: dbQueue)
        }
    }

    public func bulkArchive(episodes: [Episode], markAsNotDownloaded: Bool, markAsPlayed: Bool, updateSyncFlag: Bool) {
        episodeManager.bulkArchive(episodes: episodes, markAsNotDownloaded: markAsNotDownloaded, markAsPlayed: markAsPlayed, updateSyncFlag: updateSyncFlag, dbQueue: dbQueue)
    }

    public func bulkUnarchive(episodes: [Episode], updateSyncFlag: Bool) {
        episodeManager.bulkUnarchive(episodes: episodes, updateSyncFlag: updateSyncFlag, dbQueue: dbQueue)
    }

    public func markAllSynced(episodes: [Episode]) {
        episodeManager.markAllSynced(episodes: episodes, dbQueue: dbQueue)
    }

    public func markAllSynced(episodeIDs: [String]) {
        episodeManager.markAllSynced(episodeIDs: episodeIDs, dbQueue: dbQueue)
    }

    public func allEpisodesForPodcast(id: Int64) -> [Episode] {
        episodeManager.allEpisodesForPodcast(id: id, dbQueue: dbQueue)
    }

    public func delete(episodeUuid: String) {
        episodeManager.delete(episodeUuid: episodeUuid, dbQueue: dbQueue)
    }

    public func deleteAllEpisodesInPodcast(podcastId: Int64) {
        episodeManager.deleteAllEpisodesInPodcast(podcastId: podcastId, dbQueue: dbQueue)
    }

    public func randomPodcasts() -> [Podcast] {
        podcastManager.randomPodcasts(dbQueue: dbQueue)
    }

    // MARK: - User Episodes

    public func findUserEpisode(uuid: String) -> UserEpisode? {
        userEpisodeManager.findBy(uuid: uuid, dbQueue: dbQueue)
    }

    /// Native-async variant of `findUserEpisode(uuid:)`; the read runs on the
    /// database engine's reader pool instead of blocking the calling thread.
    public func findUserEpisodeAsync(uuid: String) async -> UserEpisode? {
        await userEpisodeManager.findByAsync(uuid: uuid, dbQueue: dbQueue)
    }

    public func allUserEpisodes(sortedBy: UploadedSort, limit: Int? = nil) -> [UserEpisode] {
        userEpisodeManager.findAll(sortedBy: sortedBy, limit: limit, dbQueue: dbQueue)
    }

    public func allUserEpisodesDownloaded(sortedBy: UploadedSort, limit: Int? = nil) -> [UserEpisode] {
        userEpisodeManager.findAllDownloaded(sortedBy: sortedBy, limit: limit, dbQueue: dbQueue)
    }

    public func bulkSave(episodes: [UserEpisode]) {
        userEpisodeManager.bulkSave(episodes: episodes, dbQueue: dbQueue)
    }

    public func delete(userEpisodeUuid: String) {
        userEpisodeManager.delete(userEpisodeUuid: userEpisodeUuid, dbQueue: dbQueue)
    }

    public func deleteUserEpisodes(userEpisodeUuids: [String]) {
        userEpisodeManager.delete(userEpisodeUuids: userEpisodeUuids, dbQueue: dbQueue)
    }

    public func findUserEpisode(folderRelativePath: String) -> UserEpisode? {
        userEpisodeManager.findBy(folderRelativePath: folderRelativePath, dbQueue: dbQueue)
    }

    public func findUserEpisode(contentHash: String) -> UserEpisode? {
        userEpisodeManager.findBy(contentHash: contentHash, dbQueue: dbQueue)
    }

    /// Every upload episode backed by a file in the sync folder.
    public func allFolderBackedUserEpisodes() -> [UserEpisode] {
        userEpisodeManager.findAllFolderBacked(dbQueue: dbQueue)
    }

    public func findUserEpisodesWhereNotNull(propertyName: String) -> [UserEpisode] {
        userEpisodeManager.findWhereNotNull(columnName: propertyName, dbQueue: dbQueue)
    }

    public func removeOrphanedUserEpisodes() {
        userEpisodeManager.removeOrphaned(dbQueue: dbQueue)
    }

    // MARK: - Playlists

    public func allPlaylists(includeDeleted: Bool) -> [EpisodeFilter] {
        playlistManager.allPlaylists(includeDeleted: includeDeleted, dbQueue: dbQueue)
    }

    public func allSmartPlaylists(includeDeleted: Bool) -> [EpisodeFilter] {
        playlistManager.allSmartPlaylists(includeDeleted: includeDeleted, dbQueue: dbQueue)
    }

    public func allManualPlaylists(includeDeleted: Bool) -> [EpisodeFilter] {
        playlistManager.allManualPlaylists(includeDeleted: includeDeleted, dbQueue: dbQueue)
    }

    public func playlistsCount(includeDeleted: Bool) -> Int {
        playlistManager.count(includeDeleted: includeDeleted, dbQueue: dbQueue)
    }

    public func playlistContainsEpisode(episodeUuid: String, includeDeleted: Bool = false) -> Bool {
        playlistManager.playlistContainsEpisode(episodeUuid: episodeUuid, includeDeleted: includeDeleted, dbQueue: dbQueue)
    }

    public func manualPlaylistUUIDs(for episodeUUID: String) -> [String] {
        playlistManager.manualPlaylistUUIDs(for: episodeUUID, dbQueue: dbQueue)
    }

    public func playlistContainsPodcast(podcastUuid: String, includeDeleted: Bool = false) -> Bool {
        playlistManager.playlistContainsPodcast(podcastUuid: podcastUuid, includeDeleted: includeDeleted, dbQueue: dbQueue)
    }

    public func findPlaylist(uuid: String) -> EpisodeFilter? {
        playlistManager.findBy(uuid: uuid, dbQueue: dbQueue)
    }

    public func episodeCount(for playlist: EpisodeFilter, episodeUuidToAdd: String?) -> Int {
        playlistEpisodeCount(for: playlist, episodeUuidToAdd: episodeUuidToAdd)
    }

    public func playlistEpisodeCount(for playlist: EpisodeFilter, episodeUuidToAdd: String?) -> Int {
        playlistManager.playlistEpisodeCount(clause: .episodeCount, playlist: playlist, episodeUuidToAdd: episodeUuidToAdd, shouldShowArchived: false, dbQueue: dbQueue)
    }

    public func playlistArchivedEpisodeCount(for playlist: EpisodeFilter, episodeUuidToAdd: String?) -> Int {
        playlistManager.playlistEpisodeCount(clause: .episodeCount, playlist: playlist, episodeUuidToAdd: episodeUuidToAdd, shouldShowArchived: true, dbQueue: dbQueue)
    }

    public func allPlaylistEpisodeCount(for playlist: EpisodeFilter, episodeUuidToAdd: String?, includingArchivedEpisodes: Bool = false) -> Int {
        playlistManager.playlistEpisodeCount(clause: .allEpisodeCount, playlist: playlist, episodeUuidToAdd: episodeUuidToAdd, shouldShowArchived: includingArchivedEpisodes, dbQueue: dbQueue)
    }

    public func playlistEpisodes(for playlist: EpisodeFilter, limit: Int? = nil, sortType: PlaylistSort? = nil) -> [Episode] {
        let limit = limit ?? EpisodeDataManager.Constants.Limits.maxPlaylistItems
        let request = PlaylistQueryBuilder.episodesRequest(
            for: playlist,
            episodeUuidToAdd: nil,
            limit: limit,
            sortType: sortType
        )
        return episodes(matching: request)
    }

    public func playlistFirstDistinctEpisodes(
        for playlist: EpisodeFilter,
        limit: Int = 4,
        shouldShowArchived: Bool = false,
        search: String? = nil,
        episodeUuidToAdd: String? = nil
    ) -> [Episode] {
        let request = PlaylistQueryBuilder.episodesRequest(
            .firstDistinctEpisodes,
            for: playlist,
            episodeUuidToAdd: episodeUuidToAdd,
            searchTerm: search,
            limit: limit,
            shouldShowArchived: shouldShowArchived
        )
        return episodes(matching: request)
    }

    public func deleteDeletedPlaylists() {
        playlistManager.deleteDeletedPlaylists(dbQueue: dbQueue)
    }

    /// Validates a SQL-mode custom playlist fragment (a WHERE-clause body over the
    /// `episode`/`podcast` aliases) and returns its current match count on success.
    /// This is the only approved path for user-entered SQL to reach the database —
    /// see `PlaylistQueryValidator` for the pipeline. Call off the main thread: the
    /// final step trial-executes a count query.
    public func validateCustomQueryFragment(_ fragment: String) -> Result<Int, CustomQueryValidationError> {
        PlaylistQueryValidator.validate(fragment: fragment, dbQueue: dbQueue)
    }

    public func allUnsyncedPlaylists() -> [EpisodeFilter] {
        playlistManager.allUnsyncedPlaylists(dbQueue: dbQueue)
    }

    @discardableResult
    public func save(playlist: EpisodeFilter) -> EpisodeFilter {
        var saved = playlist
        dbQueue.inTransaction { db in
            saved = try playlistManager.save(playlist: playlist, db: db)
        }
        return saved
    }

    public func updatePlaylistUpdateDate(for playlist: EpisodeFilter, to date: Date = .now) {
        playlistManager.updatePlaylistUpdateDate(for: playlist, to: date, dbQueue: dbQueue)
    }

    @discardableResult
    public func add(episodes: [Episode], to playlist: EpisodeFilter) -> Bool {
        playlistManager.add(episodes: episodes, to: playlist, dbQueue: dbQueue)
    }

    public func delete(playlist: EpisodeFilter) {
        dbQueue.inTransaction { db in
            try playlistManager.delete(playlist: playlist, db: db)
        }
    }

    public func markAllPlaylistsSynced() {
        playlistManager.markAllSynced(dbQueue: dbQueue)
    }

    public func markAllPlaylistsUnsynced() {
        playlistManager.markAllUnsynced(dbQueue: dbQueue)
    }

    public func nextSortPositionForPlaylist() -> Int {
        playlistManager.nextSortPositionForPlaylist(dbQueue: dbQueue)
    }

    public func firstSortPositionForPlaylist() -> Int {
        playlistManager.firstSortPositionForPlaylist(dbQueue: dbQueue)
    }

    public func bumpSortPositionForAllPlaylists(adding value: Int = 1) {
        playlistManager.bumpSortPositionForAllPlaylists(adding: value, dbQueue: dbQueue)
    }

    public func updatePosition(playlist: EpisodeFilter, newPosition: Int32) {
        playlistManager.updatePosition(playlist: playlist, newPosition: newPosition, dbQueue: dbQueue)
    }

    // Manual Playlist episode management
    public func moveEpisode(_ episodeUuid: String, in playlist: EpisodeFilter, to index: Int) {
        playlistManager.moveEpisode(episodeUuid, in: playlist, to: index, dbQueue: dbQueue)
    }

    public func updateEpisodePosition(_ episodeUuid: String, in playlist: EpisodeFilter, to position: Int32) {
        playlistManager.updateEpisodePosition(episodeUuid, in: playlist, to: position, dbQueue: dbQueue)
    }

    public func deleteEpisodes(_ episodeUuids: [String], from playlist: EpisodeFilter) {
        playlistManager.deleteEpisodes(episodeUuids, from: playlist, dbQueue: dbQueue)
    }

    public func rawDeleteEpisodes(_ episodeUuids: [String], from playlist: EpisodeFilter) {
        playlistManager.rawDeleteEpisodes(episodeUuids, from: playlist, dbQueue: dbQueue)
    }

    public func deleteAllEpisodes(in playlist: EpisodeFilter) {
        playlistManager.deleteAllEpisodes(in: playlist, dbQueue: dbQueue)
    }

    // MARK: - Folders

    @discardableResult
    public func save(folder: Folder) -> Folder {
        var saved = folder
        let success = dbQueue.inTransaction { db in
            saved = try folderManager.save(folder: folder, db: db)
        }
        if success {
            folderManager.cacheFolders(dbQueue: dbQueue)
        }
        return saved
    }

    public func allFolders(includeDeleted: Bool = false) -> [Folder] {
        folderManager.allFolders(includeDeleted: includeDeleted, dbQueue: dbQueue)
    }

    public func findFolder(uuid: String) -> Folder? {
        folderManager.findFolder(uuid: uuid, dbQueue: dbQueue)
    }

    public func topPodcastsUuidInFolder(folder: Folder) -> [String] {
        let topPodcasts = podcastManager.allPodcastsInFolder(folder: folder, dbQueue: dbQueue).map({$0.uuid})
        return topPodcasts
    }

    public func allPodcastsInFolder(folder: Folder) -> [Podcast] {
        podcastManager.allPodcastsInFolder(folder: folder, dbQueue: dbQueue)
    }

    public func countOfPodcastsInFolder(folder: Folder) -> Int {
        podcastManager.countOfPodcastsInFolder(folder: folder, dbQueue: dbQueue)
    }

    public func countOfPodcastsInRootFolder() -> Int {
        podcastManager.countOfPodcastsInFolder(folder: nil, dbQueue: dbQueue)
    }

    public func saveSortOrders(folders: [Folder], syncModified: Int64) {
        folderManager.saveSortOrders(folders: folders, syncModified: syncModified, dbQueue: dbQueue)
    }

    public func updateFolderColor(folderUuid: String, color: Int32, syncModified: Int64) {
        folderManager.updateFolderColor(folderUuid: folderUuid, color: color, syncModified: syncModified, dbQueue: dbQueue)
    }

    public func updateFolderSyncModified(folderUuid: String, syncModified: Int64) {
        folderManager.updateFolderSyncModified(folderUuid: folderUuid, syncModified: syncModified, dbQueue: dbQueue)
    }

    public func delete(folderUuid: String, markAsDeleted: Bool) {
        let success = dbQueue.inTransaction { db in
            try podcastManager.removeAllPodcastsFromFolder(folderUuid: folderUuid, db: db)

            if markAsDeleted {
                try folderManager.markFolderAsDeleted(folderUuid: folderUuid, syncModified: TimeFormatter.currentUTCTimeInMillis(), db: db)
            } else {
                try folderManager.delete(folderUuid: folderUuid, db: db)
            }
        }
        if success {
            podcastManager.cachePodcasts(dbQueue: dbQueue)
            folderManager.cacheFolders(dbQueue: dbQueue)
        }
    }

    public func bulkSetSyncModified(_ syncModified: Int64, onFolders folderUuids: [String]) {
        folderManager.bulkSetSyncModified(syncModified, onFolders: folderUuids, dbQueue: dbQueue)
    }

    public func allUnsyncedFolders() -> [Folder] {
        folderManager.allUnsyncedFolders(dbQueue: dbQueue)
    }

    public func markAllFoldersSynced() {
        folderManager.markAllFoldersSynced(dbQueue: dbQueue)
    }

    public func clearAllFolderInformation() {
        podcastManager.removeAllPodcastsFromAllFolders(dbQueue: dbQueue)
        folderManager.deleteAllFolders(dbQueue: dbQueue)
    }

    public func deleteAllFoldersAndMarkSync() {
        folderManager.markAllFolderAsDeleted(syncModified: TimeFormatter.currentUTCTimeInMillis(), dbQueue: dbQueue)
    }

    // MARK: - Advanced

    /// RETAINED raw-SQL API: playlist counts moved to the typed `count(matching:)`,
    /// but podcast/episode count sites across the app, Server module and tests
    /// (push defaults, episode-limit prompts, podcast page counts) still pass raw
    /// COUNT queries here. Delete once those callers migrate to typed requests.
    public func count(query: String, values: [Any]?) -> Int {
        var count = 0
        dbQueue.read { db in
            do {
                let resultSet = try db.executeQuery(query, values: values)
                if resultSet.next() {
                    count = resultSet.long(forColumnIndex: 0)
                }
                resultSet.close()
            } catch {
                FileLog.shared.addMessage("DataManager.count error: \(error)")
            }
        }

        return count
    }

    // MARK: - Path Related

    public static func pathToDb() -> String {
        let folderPath = pathToDbFolder() as NSString

        return folderPath.appendingPathComponent("podcast_newDB.sqlite3")
    }

    public static func pathToDbBackup() -> String {
        let folderPath = pathToDbFolder() as NSString

        return folderPath.appendingPathComponent("podcast_newDB_backup.sqlite3")
    }

    private static func pathToDbFolder() -> String {
        let typeOfDirectory: FileManager.SearchPathDirectory = .applicationSupportDirectory
        let documentsPath = NSSearchPathForDirectoriesInDomains(typeOfDirectory, .userDomainMask, true).last as NSString?
        let mainFolder = documentsPath?.appendingPathComponent("Pocket Casts")

        return mainFolder!
    }

    private static func ensureDbFolderExists() {
        do {
            try FileManager.default.createDirectory(atPath: pathToDbFolder(), withIntermediateDirectories: true, attributes: nil)
        } catch {
            FileLog.shared.addMessage("Unable to create database folder: \(error)")
        }
    }

    // MARK: - Push Notification

    public func setPushDefaultForNewPodcast(_ podcast: Podcast) {
        var podcast = podcast
        // if all the podcasts the user currently has are auto download, set this one to be as well
        let pushOnQuery = "SELECT COUNT(*) FROM \(DataManager.podcastTableName) WHERE subscribed = 1 AND pushEnabled = 1"
        let totalQuery = "SELECT COUNT(*) FROM \(DataManager.podcastTableName) WHERE subscribed = 1"

        let pushOnCount = DataManager.sharedManager.count(query: pushOnQuery, values: nil)
        let totalCount = (DataManager.sharedManager.count(query: totalQuery, values: nil) - 1) // -1 because the podcast we're currently adding could be returned by this query
        if totalCount > 0, pushOnCount >= totalCount {
            podcast.isPushEnabled = true
        } else {
            podcast.isPushEnabled = false
        }

        DataManager.sharedManager.save(podcast: podcast)
    }

    public func pushEnabledPodcastsCount() -> Int {
        if FeatureFlag.newSettingsStorage.enabled {
            DataManager.sharedManager.count(query: "SELECT COUNT(*) FROM \(DataManager.podcastTableName) WHERE json_extract(settings, '$.notification.value') = ? AND subscribed = 1", values: [true])
        } else {
            DataManager.sharedManager.count(query: "SELECT COUNT(*) FROM \(DataManager.podcastTableName) WHERE pushEnabled = 1 AND subscribed = 1", values: nil)
        }
    }

    // MARK: - Up Next History Manager

    public func snapshotUpNext() {
        upNextHistoryManager.snapshot(dbQueue: dbQueue)
    }

    public func upNextHistoryEntries() -> [UpNextHistoryManager.UpNextHistoryEntry] {
        upNextHistoryManager.entries(dbQueue: dbQueue)
    }

    public func upNextHistoryEpisodes(entry: Date) -> [String] {
        upNextHistoryManager.episodes(entry: entry, dbQueue: dbQueue)
    }

    // MARK: - Folders History

    public func snapshot(podcastsAndFolders: [String: String]) {
        folderHistoryManager.snapshot(podcastsAndFolders: podcastsAndFolders, dbQueue: dbQueue)
    }

    public func foldersHistoryEntries() -> [FolderHistoryManager.PodcastFoldersHistoryEntry] {
        folderHistoryManager.entries(dbQueue: dbQueue)
    }

    public func folderHistory(entry: Date) -> [String: String] {
        folderHistoryManager.podcastsAndFolders(entry: entry, dbQueue: dbQueue)
    }
}

// MARK: - Ghost Episode Cleanup

public extension DataManager {
    func findGhostEpisodes() -> [Episode] {
        episodeManager.findGhostEpisodes(dbQueue)
    }

    func deleteGhostsEpisodes(uuids: [String]) {
        // The ghost-episode list is unbounded, so delete in chunks to stay below
        // SQLite's bound-variable limit.
        for chunk in stride(from: 0, to: uuids.count, by: 500).map({ Array(uuids[$0 ..< min($0 + 500, uuids.count)]) }) {
            _ = dbQueue.deleteAll(Episode.self, filter: chunk.contains(Episode.Columns.uuid))
        }
    }
}

// MARK: - GRDB: Database protection

extension DataManager {
    // This is the implementation of SQLITE_OPEN_FILEPROTECTION_NONE
    // for GRDB, which we need to handle manually.
    static func setDatabaseFileProtectionToNone() {
        let dbPath = DataManager.pathToDb()
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: dbPath) {
            if let attributes = try? fileManager.attributesOfItem(atPath: dbPath),
               let currentProtection = attributes[.protectionKey] as? FileProtectionType,
               currentProtection != .none {
                // Only set the attribute if it's not already .none
                try? fileManager.setAttributes([.protectionKey: FileProtectionType.none], ofItemAtPath: dbPath)
            }
        }
    }
}

// MARK: - GRDB: Backup / Restore

extension DataManager {
    /// Writes a consistent snapshot of the live database (WAL included) to `path`,
    /// using SQLite's online-backup API. The foundation of user-facing library backup.
    public func backupDatabase(to path: String) throws {
        let destination = try DatabaseQueue(path: path)
        defer { try? destination.close() }
        try dbQueue.dbPool.backup(to: destination)
    }

    /// User-facing restore: replaces the current library with the database staged at
    /// `path` (by default `pathToDbBackup()`), **including `SJEpisode`** — unlike
    /// `copyAllData()`, which is corruption-recovery-specific and deliberately skips
    /// episodes. Each table present in the backup is cleared and repopulated, and
    /// in-memory caches are rebuilt. Returns false when the backup can't be opened.
    @discardableResult
    public func restoreAllData(fromPath path: String = DataManager.pathToDbBackup()) -> Bool {
        guard FileManager.default.fileExists(atPath: path),
              let sourceDbQueue = try? DatabaseQueue(path: path) else {
            return false
        }
        defer { try? sourceDbQueue.close() }

        // Virtual-table shadow tables (FTS5 *_data/_idx/_content/_docsize/_config) are
        // maintained by SQLite and cannot be written directly; the virtual table itself
        // is copied through its declared columns instead, which rebuilds its index.
        guard let tableNames: [String] = try? sourceDbQueue.read({ db in
            let all = try String.fetchAll(db,
                sql: """
                SELECT name FROM sqlite_master
                WHERE type = 'table' AND name NOT LIKE 'sqlite_%'
                """)
            let virtualTables = try String.fetchAll(db,
                sql: """
                SELECT name FROM sqlite_master
                WHERE type = 'table' AND sql LIKE 'CREATE VIRTUAL TABLE%'
                """)
            let shadowPrefixes = virtualTables.map { $0 + "_" }
            return all.filter { name in !shadowPrefixes.contains { name.hasPrefix($0) } }
        }) else {
            return false
        }

        do {
            try dbQueue.dbPool.write { destDb in
                for tableName in tableNames {
                    try destDb.execute(sql: "DELETE FROM \(tableName.quotedDatabaseIdentifier)")
                    try sourceDbQueue.read { sourceDb in
                        let columnNames = try sourceDb.columns(in: tableName).map(\.name)
                        guard !columnNames.isEmpty else { return }
                        let columnsList = columnNames.map { $0.quotedDatabaseIdentifier }.joined(separator: ", ")
                        let placeholders = Array(repeating: "?", count: columnNames.count).joined(separator: ", ")
                        let insertSQL = "INSERT OR REPLACE INTO \(tableName.quotedDatabaseIdentifier) (\(columnsList)) VALUES (\(placeholders))"
                        let rowCursor = try Row.fetchCursor(sourceDb, sql: "SELECT * FROM \(tableName.quotedDatabaseIdentifier)")
                        while let row = try rowCursor.next() {
                            let values: [DatabaseValueConvertible?] = columnNames.map { row[$0] }
                            try destDb.execute(sql: insertSQL, arguments: StatementArguments(values))
                        }
                    }
                }
            }
        } catch {
            FileLog.shared.addMessage("DataManager: restore failed: \(error)")
            return false
        }

        podcastManager.cachePodcasts(dbQueue: dbQueue)
        folderManager.setup(dbQueue: dbQueue)
        upNextManager.setup(dbQueue: dbQueue)
        return true
    }
}

// MARK: - GRDB: Database corruption

extension DataManager {
    public func copyAllData() {
        guard let sourceDbQueue = try? DatabaseQueue(path: DataManager.pathToDbBackup()) else {
            return
        }

        let destinationDbQueue = dbQueue.dbPool

        // Fetch all table names (excluding SQLite internal tables, SJEpisode, and
        // virtual-table shadow tables, which SQLite maintains and forbids writing).
        let tableNames: [String]? = try? sourceDbQueue.read { db in
            let all = try String.fetchAll(db,
                sql: """
                SELECT name FROM sqlite_master
                WHERE type = 'table' AND name NOT LIKE 'sqlite_%' AND name NOT LIKE 'SJEpisode'
                """)
            let virtualTables = try String.fetchAll(db,
                sql: """
                SELECT name FROM sqlite_master
                WHERE type = 'table' AND sql LIKE 'CREATE VIRTUAL TABLE%'
                """)
            let shadowPrefixes = virtualTables.map { $0 + "_" }
            return all.filter { name in !shadowPrefixes.contains { name.hasPrefix($0) } }
        }

        for tableName in tableNames ?? [] {
            try? sourceDbQueue.read { sourceDb in
                // Fetch first row to get column names
                let previewCursor = try Row.fetchCursor(sourceDb, sql: "SELECT * FROM \(tableName.quotedDatabaseIdentifier)")
                guard let firstRow = try previewCursor.next() else { return }
                let columnNames = firstRow.columnNames

                // Re-create the cursor to read all rows again
                let rowCursor = try Row.fetchCursor(sourceDb, sql: "SELECT * FROM \(tableName.quotedDatabaseIdentifier)")

                // Prepare insert SQL
                let columnsList = columnNames.map { $0.quotedDatabaseIdentifier }.joined(separator: ", ")
                let placeholders = Array(repeating: "?", count: columnNames.count).joined(separator: ", ")
                let insertSQL = "INSERT OR REPLACE INTO \(tableName.quotedDatabaseIdentifier) (\(columnsList)) VALUES (\(placeholders))"

                try? destinationDbQueue.write { destDb in
                    while let row = try rowCursor.next() {
                        // Any podcast we copy we set lastUpdateddAt to nil so all episodes are fetch
                        let values: [DatabaseValueConvertible?] = columnNames.map { columnName in
                            if tableName == "SJPodcast" && columnName == "lastUpdatedAt" {
                                return nil
                            } else {
                                return row[columnName]
                            }
                        }

                        try? destDb.execute(sql: insertSQL, arguments: StatementArguments(values))
                    }
                }
            }
        }

        try? sourceDbQueue.close()
    }
}
