import Foundation
import PocketCastsUtils

struct SchemaMigration: Sendable {
    let toVersion: Int32
    let migrate: @Sendable (PCDatabase) throws -> Void
}

class DatabaseHelper {
    static let baselineSchemaVersion: Int32 = 73
    private static let minimumMigratableSchemaVersion: Int32 = 73

    /// Append future migrations here in strictly ascending version order, starting at
    /// baselineSchemaVersion + 1. Fresh installs create the baked baseline schema and then
    /// run every migration, so a fresh database and an upgraded one always converge.
    static let migrations: [SchemaMigration] = [
        // Adds the explicit-content flag parsed from the server feed (#4427).
        SchemaMigration(toVersion: 74) { db in
            try db.executeUpdate("ALTER TABLE SJPodcast ADD COLUMN isExplicit INTEGER DEFAULT 0;", values: nil)
        },
        // File-based sync (local-first): the change journal + per-device
        // cursors that back PocketCastsFileSync, and the folder-identity
        // columns that let SJUserEpisode rows reference files living in the
        // user's sync folder (identityState: 0 = legacy app-local file,
        // 1 = provisional path-keyed identity, 2 = canonical content-hash).
        SchemaMigration(toVersion: 75) { db in
            try db.executeUpdate("""
            CREATE TABLE FileSyncJournal (
                id INTEGER PRIMARY KEY,
                entityType INTEGER NOT NULL,
                entityUuid TEXT,
                opType INTEGER NOT NULL,
                fields TEXT,
                wallClockMs INTEGER NOT NULL,
                flushedSeq INTEGER
            );
            """, values: nil)
            try db.executeUpdate(
                "CREATE INDEX file_sync_journal_unflushed ON FileSyncJournal (flushedSeq, wallClockMs);", values: nil)
            try db.executeUpdate("""
            CREATE TABLE FileSyncCursor (
                peerDeviceId TEXT PRIMARY KEY,
                fileName TEXT,
                recordOffset INTEGER NOT NULL DEFAULT 0,
                lastAppliedSeq INTEGER NOT NULL DEFAULT 0,
                lastAppliedSnapshotSeq INTEGER NOT NULL DEFAULT 0,
                currentLogIndex INTEGER NOT NULL DEFAULT 0,
                headSeq INTEGER NOT NULL DEFAULT 0,
                lastSnapshotSeq INTEGER NOT NULL DEFAULT 0
            );
            """, values: nil)
            try db.executeUpdate("ALTER TABLE SJUserEpisode ADD COLUMN folderRelativePath TEXT;", values: nil)
            try db.executeUpdate("ALTER TABLE SJUserEpisode ADD COLUMN contentHash TEXT;", values: nil)
            try db.executeUpdate("ALTER TABLE SJUserEpisode ADD COLUMN groupName TEXT;", values: nil)
            try db.executeUpdate("ALTER TABLE SJUserEpisode ADD COLUMN identityState INTEGER DEFAULT 0;", values: nil)
            try db.executeUpdate(
                "CREATE INDEX user_episode_folder_relative_path ON SJUserEpisode (folderRelativePath) WHERE folderRelativePath IS NOT NULL;",
                values: nil)
            try db.executeUpdate(
                "CREATE INDEX user_episode_content_hash ON SJUserEpisode (contentHash) WHERE contentHash IS NOT NULL;",
                values: nil)
        },
        // Local-first ingest: which regime owns refreshing each podcast (0 = Pocket Casts
        // refresh servers, 1 = on-device feed fetch/parse). Local-feed podcasts use
        // deterministic hash UUIDs and are excluded from account sync.
        SchemaMigration(toVersion: 76) { db in
            try db.executeUpdate("ALTER TABLE SJPodcast ADD COLUMN refreshSource INTEGER DEFAULT 0;", values: nil)
        },
        // Precomputed integrated loudness (BS.1770 LUFS) for downloaded episodes so
        // VoiceBoostN can seed its gain instantly. 0 = not yet measured (real
        // measurements are always negative). Follows the cachedFrameCount pattern.
        SchemaMigration(toVersion: 77) { db in
            try db.executeUpdate("ALTER TABLE SJEpisode ADD COLUMN cachedLoudness REAL NOT NULL DEFAULT 0;", values: nil)
            try db.executeUpdate("ALTER TABLE SJUserEpisode ADD COLUMN cachedLoudness REAL NOT NULL DEFAULT 0;", values: nil)
        },
        // Diarized transcription (device-local, no sync): per-episode transcription
        // state rows, plus an FTS5 index over transcript segments powering
        // cross-episode search. The VTT artifact itself lives on disk (filePath);
        // the app layer owns writing/deleting it.
        SchemaMigration(toVersion: 78) { db in
            try db.executeUpdate("""
            CREATE TABLE EpisodeTranscription (
                episodeUuid TEXT PRIMARY KEY,
                podcastUuid TEXT,
                status INTEGER NOT NULL DEFAULT 0,
                engineMode INTEGER NOT NULL DEFAULT 0,
                provider TEXT,
                modelId TEXT,
                language TEXT,
                createdAt REAL NOT NULL DEFAULT 0,
                updatedAt REAL NOT NULL DEFAULT 0,
                durationSecs REAL NOT NULL DEFAULT 0,
                speakerCount INTEGER NOT NULL DEFAULT 0,
                speakerNames TEXT,
                errorMessage TEXT,
                remoteJobId TEXT,
                filePath TEXT
            );
            """, values: nil)
            try db.executeUpdate(
                "CREATE INDEX episode_transcription_status ON EpisodeTranscription (status);", values: nil)
            try db.executeUpdate("""
            CREATE VIRTUAL TABLE TranscriptionSegmentFTS USING fts5(
                text,
                episodeUuid UNINDEXED,
                podcastUuid UNINDEXED,
                segmentIndex UNINDEXED,
                startTime UNINDEXED,
                speaker UNINDEXED,
                tokenize = 'unicode61 remove_diacritics 2'
            );
            """, values: nil)
        },
        // Custom playlists (device-local, excluded from account sync and file sync):
        // the versioned JSON envelope describing either a builder AST or a validated
        // SQL WHERE fragment (see CustomPlaylistQuery). NULL = regular smart/manual
        // playlist.
        SchemaMigration(toVersion: 79) { db in
            try db.executeUpdate("ALTER TABLE SJFilteredPlaylist ADD COLUMN customQuery TEXT;", values: nil)
        },
        // Smart highlights (AI UX plan phase 3): the transcript excerpt around a
        // bookmark's position and the end of that excerpt window, written once by
        // HighlightEnricher after creation. NULL = plain (un-enriched) bookmark.
        SchemaMigration(toVersion: 80) { db in
            try db.executeUpdate("ALTER TABLE Bookmark ADD COLUMN excerpt TEXT;", values: nil)
            try db.executeUpdate("ALTER TABLE Bookmark ADD COLUMN endTime REAL;", values: nil)
        },
        // Library-wide transcript search (AI UX plan phase 4, device-local, no sync):
        // an FTS5 index over the cue text of viewed podcast-provided transcripts, plus
        // a bookkeeping table (one row per indexed episode) driving dedupe and LRU
        // eviction. Locally generated transcripts have their own index
        // (TranscriptionSegmentFTS, migration 78) — this is a separate corpus.
        //
        // The FTS5 CREATE is caught rather than propagated so an SQLite build without
        // the FTS5 module can't fail the whole migration chain: on failure neither
        // table is created, TranscriptIndexDataManager's meta-table probe reports the
        // index unavailable, and the feature self-disables.
        SchemaMigration(toVersion: 81) { db in
            do {
                try db.executeUpdate("""
                CREATE VIRTUAL TABLE TranscriptCueIndex USING fts5(
                    text,
                    episodeUuid UNINDEXED,
                    podcastUuid UNINDEXED,
                    cueIndex UNINDEXED,
                    startTime UNINDEXED,
                    endTime UNINDEXED,
                    tokenize = 'unicode61 remove_diacritics 2'
                );
                """, values: nil)
            } catch {
                FileLog.shared.addMessage("Migration 81: FTS5 unavailable, transcript search index not created: \(error)")
                return
            }
            try db.executeUpdate("""
            CREATE TABLE TranscriptIndexMeta (
                episodeUuid TEXT PRIMARY KEY,
                podcastUuid TEXT,
                indexedDate REAL NOT NULL DEFAULT 0,
                cueCount INTEGER NOT NULL DEFAULT 0,
                textBytes INTEGER NOT NULL DEFAULT 0
            );
            """, values: nil)
        },
        // Unified transcript search index (device-local, no sync): merges the two
        // former corpora — locally generated transcription segments
        // (TranscriptionSegmentFTS, migration 78) and viewed podcast-provided
        // transcript cues (TranscriptCueIndex, migration 81) — into one FTS5 table
        // with a `source` column, plus one bookkeeping table keyed
        // (episodeUuid, source). Existing rows are backfilled from both corpora
        // (each guarded by an existence check: migration 81 self-disables on
        // FTS5-less builds, so its tables may be absent while 78's are present),
        // then the old tables are dropped. EpisodeTranscription stays — it is
        // pipeline state, not index data. See docs/adr/0001-unified-transcript-index.md.
        //
        // The FTS5 CREATE is caught rather than propagated for the same reason as
        // migration 81: on failure neither new table is created, nothing is
        // backfilled or dropped, and TranscriptSearchDataManager's meta-table probe
        // reports the index unavailable, so the feature self-disables.
        SchemaMigration(toVersion: 82) { db in
            do {
                try db.executeUpdate("""
                CREATE VIRTUAL TABLE TranscriptSegmentIndex USING fts5(
                    text,
                    episodeUuid UNINDEXED,
                    podcastUuid UNINDEXED,
                    segmentIndex UNINDEXED,
                    startTime UNINDEXED,
                    endTime UNINDEXED,
                    speaker UNINDEXED,
                    source UNINDEXED,
                    tokenize = 'unicode61 remove_diacritics 2'
                );
                """, values: nil)
            } catch {
                FileLog.shared.addMessage("Migration 82: FTS5 unavailable, unified transcript search index not created: \(error)")
                return
            }
            try db.executeUpdate("""
            CREATE TABLE TranscriptSearchIndexMeta (
                episodeUuid TEXT NOT NULL,
                source TEXT NOT NULL,
                podcastUuid TEXT,
                indexedDate REAL NOT NULL DEFAULT 0,
                segmentCount INTEGER NOT NULL DEFAULT 0,
                textBytes INTEGER NOT NULL DEFAULT 0,
                PRIMARY KEY (episodeUuid, source)
            );
            """, values: nil)

            func tableExists(_ name: String) throws -> Bool {
                let resultSet = try db.executeQuery(
                    "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?", values: [name])
                defer { resultSet.close() }
                return resultSet.next()
            }

            if try tableExists("TranscriptionSegmentFTS") {
                try db.executeUpdate("""
                INSERT INTO TranscriptSegmentIndex (text, episodeUuid, podcastUuid, segmentIndex, startTime, endTime, speaker, source)
                SELECT text, episodeUuid, podcastUuid, segmentIndex, startTime, NULL, speaker, 'generated'
                FROM TranscriptionSegmentFTS;
                """, values: nil)
                // indexedDate comes from the transcription record's updatedAt when one
                // still exists; orphaned segments get the migration time.
                try db.executeUpdate("""
                INSERT INTO TranscriptSearchIndexMeta (episodeUuid, source, podcastUuid, indexedDate, segmentCount, textBytes)
                SELECT f.episodeUuid, 'generated', MAX(f.podcastUuid),
                       COALESCE(MAX(t.updatedAt), CAST(strftime('%s', 'now') AS REAL)),
                       COUNT(*), SUM(LENGTH(CAST(f.text AS BLOB)))
                FROM TranscriptionSegmentFTS f
                LEFT JOIN EpisodeTranscription t ON t.episodeUuid = f.episodeUuid
                GROUP BY f.episodeUuid;
                """, values: nil)
                try db.executeUpdate("DROP TABLE TranscriptionSegmentFTS;", values: nil)
            }

            if try tableExists("TranscriptCueIndex") {
                try db.executeUpdate("""
                INSERT INTO TranscriptSegmentIndex (text, episodeUuid, podcastUuid, segmentIndex, startTime, endTime, speaker, source)
                SELECT text, episodeUuid, podcastUuid, cueIndex, startTime, endTime, NULL, 'provided'
                FROM TranscriptCueIndex;
                """, values: nil)
                try db.executeUpdate("DROP TABLE TranscriptCueIndex;", values: nil)
            }
            if try tableExists("TranscriptIndexMeta") {
                try db.executeUpdate("""
                INSERT INTO TranscriptSearchIndexMeta (episodeUuid, source, podcastUuid, indexedDate, segmentCount, textBytes)
                SELECT episodeUuid, 'provided', podcastUuid, indexedDate, cueCount, textBytes
                FROM TranscriptIndexMeta;
                """, values: nil)
                try db.executeUpdate("DROP TABLE TranscriptIndexMeta;", values: nil)
            }
        }
    ]

    static func currentSchemaVersion(for migrations: [SchemaMigration]) -> Int32 {
        migrations.last?.toVersion ?? baselineSchemaVersion
    }

    @discardableResult
    class func setup(queue: PCDBQueue) -> Bool {
        setup(queue: queue, migrations: migrations)
    }

    @discardableResult
    class func setup(queue: PCDBQueue, migrations: [SchemaMigration]) -> Bool {
        assertMigrationsAreValid(migrations)

        var setupSucceeded = true
        var transactionStarted = false

        queue.inTransaction { db, rollback in
            transactionStarted = true

            do {
                try db.executeQuery("PRAGMA busy_timeout = 10000", values: nil).close()

                let startingSchemaVersion = db.pragmaUserVersion() ?? 0

                var newSchemaVersion = startingSchemaVersion
                try upgradeIfRequired(schemaVersion: &newSchemaVersion, db: db, migrations: migrations)

                if newSchemaVersion != startingSchemaVersion {
                    FileLog.shared.addMessage("Schema update from \(startingSchemaVersion) to \(newSchemaVersion)")
                    try db.executeUpdate("PRAGMA user_version = \(newSchemaVersion)", values: nil)
                }
            } catch {
                rollback.pointee = true
                setupSucceeded = false
                FileLog.shared.addMessage("Failed to setup database \(db.lastErrorCode()): \(db.lastErrorMessage()) actual error: \(error)")
            }
        }

        if !transactionStarted {
            FileLog.shared.addMessage("Failed to setup database: transaction did not start")
        }

        return setupSucceeded && transactionStarted
    }

    private class func upgradeIfRequired(schemaVersion: inout Int32, db: PCDatabase, migrations: [SchemaMigration]) throws {
        guard schemaVersion < currentSchemaVersion(for: migrations) else { return }
        guard schemaVersion == 0 || schemaVersion >= minimumMigratableSchemaVersion else {
            let error = DatabaseSetupError.schemaTooOld(
                schemaVersion: schemaVersion,
                minimumMigratableSchemaVersion: minimumMigratableSchemaVersion
            )
            FileLog.shared.addMessage(error.description)
            throw error
        }

        do {
            if schemaVersion == 0 {
                try createCurrentSchema(db: db)
                schemaVersion = baselineSchemaVersion
            }
            try migrateSchema(schemaVersion: &schemaVersion, db: db, migrations: migrations)
        } catch {
            let lastErrorCode = db.lastErrorCode()
            let lastErrorMessage = db.lastErrorMessage()
            FileLog.shared.addMessage("Schema setup failed, code \(lastErrorCode): \(lastErrorMessage), actual error: \(error)")
            throw error
        }
    }

    private enum DatabaseSetupError: LocalizedError, CustomStringConvertible {
        case schemaTooOld(schemaVersion: Int32, minimumMigratableSchemaVersion: Int32)

        var errorDescription: String? {
            description
        }

        var description: String {
            switch self {
            case let .schemaTooOld(schemaVersion, minimumMigratableSchemaVersion):
                return "Database schema version \(schemaVersion) is older than the minimum migratable version \(minimumMigratableSchemaVersion). Database setup cannot continue."
            }
        }
    }

    private class func migrateSchema(schemaVersion: inout Int32, db: PCDatabase, migrations: [SchemaMigration]) throws {
        for migration in migrations where migration.toVersion > schemaVersion {
            try migration.migrate(db)
            schemaVersion = migration.toVersion
        }
    }

    private class func assertMigrationsAreValid(_ migrations: [SchemaMigration]) {
        var previousVersion = baselineSchemaVersion
        for migration in migrations {
            assert(
                migration.toVersion > previousVersion,
                "Schema migrations must be strictly ascending starting at \(baselineSchemaVersion + 1); found \(migration.toVersion) after \(previousVersion)"
            )
            previousVersion = migration.toVersion
        }
    }

    private class func createCurrentSchema(db: PCDatabase) throws {
        try execute(schemaStatements, db: db)
        try BookmarkDataManager.createTable(in: db)
        try NetworkDataUsageManager.createTable(in: db)
    }

    private class func execute(_ statements: [String], db: PCDatabase) throws {
        for statement in statements {
            try db.executeUpdate(statement, values: nil)
        }
    }

    private static let schemaStatements = [
        """
        CREATE TABLE SJPodcast (
            id INTEGER PRIMARY KEY,
            addedDate REAL NOT NULL,
            autoDownloadSetting INTEGER NOT NULL DEFAULT 0,
            autoAddToUpNext INTEGER NOT NULL DEFAULT 0,
            episodeKeepSetting INTEGER NOT NULL DEFAULT 0,
            backgroundColor TEXT,
            detailColor TEXT,
            primaryColor TEXT,
            secondaryColor TEXT,
            lastColorDownloadDate REAL,
            imageURL TEXT,
            latestEpisodeUuid TEXT,
            latestEpisodeDate REAL,
            mediaType TEXT,
            lastThumbnailDownloadDate REAL,
            thumbnailStatus INTEGER NOT NULL DEFAULT 1,
            podcastUrl TEXT,
            author TEXT,
            playbackSpeed REAL NOT NULL DEFAULT 1,
            boostVolume INTEGER NOT NULL DEFAULT 0,
            trimSilenceAmount INTEGER NOT NULL DEFAULT 0,
            podcastCategory TEXT,
            podcastDescription TEXT,
            podcastHTMLDescription TEXT,
            sortOrder INTEGER NOT NULL DEFAULT 0,
            startFrom INTEGER NOT NULL DEFAULT 0,
            skipLast INTEGER NOT NULL DEFAULT 0,
            subscribed INTEGER NOT NULL DEFAULT 1,
            thumbnailURL TEXT,
            title TEXT,
            uuid TEXT NOT NULL,
            syncStatus INTEGER NOT NULL DEFAULT 0,
            colorVersion INTEGER NOT NULL DEFAULT 1,
            pushEnabled INTEGER NOT NULL DEFAULT 1,
            episodeSortOrder INTEGER NOT NULL DEFAULT 1,
            showType TEXT,
            estimatedNextEpisode REAL,
            episodeFrequency TEXT,
            lastUpdatedAt TEXT,
            excludeFromAutoArchive INTEGER NOT NULL DEFAULT 0,
            overrideGlobalEffects INTEGER NOT NULL DEFAULT 0,
            overrideGlobalArchive INTEGER NOT NULL DEFAULT 0,
            autoArchivePlayedAfter REAL NOT NULL DEFAULT -1,
            autoArchiveInactiveAfter REAL NOT NULL DEFAULT -1,
            episodeGrouping INTEGER NOT NULL DEFAULT 0,
            isPaid INTEGER NOT NULL DEFAULT 0,
            licensing INTEGER NOT NULL DEFAULT 0,
            fullSyncLastSyncAt TEXT,
            showArchived INTEGER NOT NULL DEFAULT 0,
            refreshAvailable INTEGER NOT NULL DEFAULT 0,
            wasDeleted INTEGER NOT NULL DEFAULT 0,
            folderUuid TEXT,
            settings TEXT NOT NULL DEFAULT '',
            usedCustomEffectsBefore INTEGER NOT NULL DEFAULT 0,
            isPrivate INTEGER NOT NULL DEFAULT 0,
            fundingURL TEXT
        );
        """,
        "CREATE INDEX IF NOT EXISTS podcast_uuid ON SJPodcast (uuid);",
        "CREATE INDEX IF NOT EXISTS podcast_sync_status ON SJPodcast (syncStatus);",
        """
        CREATE TABLE SJEpisode (
            id INTEGER PRIMARY KEY,
            addedDate REAL NOT NULL,
            lastDownloadAttemptDate REAL NOT NULL DEFAULT 0,
            detailedDescription TEXT,
            downloadErrorDetails TEXT,
            downloadTaskId TEXT,
            downloadUrl TEXT,
            episodeDescription TEXT,
            episodeStatus INTEGER NOT NULL,
            fileType TEXT,
            contentType TEXT,
            keepEpisode INTEGER NOT NULL DEFAULT 0,
            playedUpTo REAL NOT NULL DEFAULT 0,
            duration REAL NOT NULL DEFAULT 0,
            playingStatus INTEGER NOT NULL,
            autoDownloadStatus INTEGER NOT NULL DEFAULT 0,
            publishedDate REAL,
            showNotes TEXT,
            sizeInBytes INTEGER NOT NULL DEFAULT 0,
            playingStatusModified INTEGER NOT NULL DEFAULT 0,
            playedUpToModified INTEGER NOT NULL DEFAULT 0,
            durationModified INTEGER NOT NULL DEFAULT 0,
            keepEpisodeModified INTEGER NOT NULL DEFAULT 0,
            title TEXT,
            uuid TEXT NOT NULL,
            podcastUuid TEXT NOT NULL,
            wasDeleted INTEGER NOT NULL DEFAULT 0,
            podcast_id INTEGER NOT NULL,
            playbackErrorDetails TEXT,
            cachedFrameCount INTEGER NOT NULL DEFAULT 0,
            lastPlaybackInteractionDate REAL,
            lastPlaybackInteractionSyncStatus INTEGER NOT NULL DEFAULT 1,
            episodeNumber INTEGER NOT NULL DEFAULT -1,
            seasonNumber INTEGER NOT NULL DEFAULT -1,
            episodeType TEXT,
            archived INTEGER NOT NULL DEFAULT 0,
            archivedModified INTEGER NOT NULL DEFAULT 0,
            lastArchiveInteractionDate REAL NOT NULL DEFAULT 0,
            excludeFromEpisodeLimit INTEGER NOT NULL DEFAULT 0,
            starredModified INTEGER NOT NULL DEFAULT 0,
            deselectedChapters TEXT,
            deselectedChaptersModified INTEGER NOT NULL DEFAULT 0,
            hasGeneratedTranscript INTEGER
        );
        """,
        "CREATE INDEX IF NOT EXISTS episode_uuid ON SJEpisode (uuid);",
        "CREATE INDEX IF NOT EXISTS episode_podcast_uuid ON SJEpisode (podcastUuid);",
        "CREATE INDEX IF NOT EXISTS episode_was_deleted ON SJEpisode (wasDeleted);",
        "CREATE INDEX IF NOT EXISTS episode_pub_date ON SJEpisode (publishedDate);",
        "CREATE INDEX IF NOT EXISTS episode_podcast_id ON SJEpisode (podcast_id);",
        "CREATE INDEX IF NOT EXISTS episode_episodeStatus ON SJEpisode (episodeStatus);",
        "CREATE INDEX IF NOT EXISTS episode_playingStatus ON SJEpisode (playingStatus);",
        "CREATE INDEX IF NOT EXISTS episode_keepEpisode ON SJEpisode (keepEpisode);",
        "CREATE INDEX IF NOT EXISTS episode_playing_status_modified ON SJEpisode (playingStatusModified);",
        "CREATE INDEX IF NOT EXISTS episode_played_opto_modified ON SJEpisode (playedUpToModified);",
        "CREATE INDEX IF NOT EXISTS episode_duration_modified ON SJEpisode (durationModified);",
        "CREATE INDEX IF NOT EXISTS episode_keep_episode_modified ON SJEpisode (keepEpisodeModified);",
        "CREATE INDEX IF NOT EXISTS ep_down_date ON SJEpisode (lastDownloadAttemptDate);",
        "CREATE INDEX IF NOT EXISTS episode_archived_modified ON SJEpisode (archivedModified);",
        "CREATE INDEX IF NOT EXISTS episode_download_task_id ON SJEpisode (downloadTaskId);",
        "CREATE INDEX IF NOT EXISTS episode_non_null_download_task_id ON SJEpisode(downloadTaskId) WHERE downloadTaskId IS NOT NULL;",
        "CREATE INDEX IF NOT EXISTS episode_added_date ON SJEpisode (addedDate);",
        """
        CREATE TABLE SJFilteredPlaylist (
            id INTEGER PRIMARY KEY,
            autoDownloadEpisodes INTEGER NOT NULL DEFAULT 0,
            customIcon INTEGER NOT NULL DEFAULT 0,
            filterAllPodcasts INTEGER NOT NULL DEFAULT 0,
            filterAudioVideoType INTEGER NOT NULL DEFAULT 0,
            filterDownloaded INTEGER NOT NULL DEFAULT 0,
            filterDownloading INTEGER NOT NULL DEFAULT 0,
            filterFinished INTEGER NOT NULL DEFAULT 0,
            filterNotDownloaded INTEGER NOT NULL DEFAULT 0,
            filterPartiallyPlayed INTEGER NOT NULL DEFAULT 0,
            filterStarred INTEGER NOT NULL DEFAULT 0,
            filterUnplayed INTEGER NOT NULL DEFAULT 0,
            filterHours INTEGER NOT NULL DEFAULT 0,
            playlistName TEXT NOT NULL,
            sortPosition INTEGER NOT NULL DEFAULT 0,
            sortType INTEGER NOT NULL DEFAULT 0,
            uuid TEXT NOT NULL,
            podcastUuids TEXT,
            autoDownloadLimit INTEGER NOT NULL DEFAULT 0,
            syncStatus INTEGER NOT NULL DEFAULT 0,
            wasDeleted INTEGER NOT NULL DEFAULT 0,
            filterDuration INTEGER NOT NULL DEFAULT 0,
            longerThan INTEGER NOT NULL DEFAULT 0,
            shorterThan INTEGER NOT NULL DEFAULT 0,
            manual INTEGER NOT NULL DEFAULT 0,
            showArchivedEpisodes BOOLEAN DEFAULT FALSE,
            playlistUpdateDate REAL
        );
        """,
        "CREATE INDEX IF NOT EXISTS filteredplaylist_uuid ON SJFilteredPlaylist (uuid);",
        "CREATE INDEX IF NOT EXISTS filteredplaylist_sync_status ON SJFilteredPlaylist (syncStatus);",
        "CREATE INDEX IF NOT EXISTS filteredplaylist_was_deleted ON SJFilteredPlaylist (wasDeleted);",
        """
        CREATE TABLE SJPlaylistEpisode (
            id INTEGER PRIMARY KEY,
            episodePosition INTEGER NOT NULL DEFAULT 0,
            episodeUuid TEXT NOT NULL,
            playlist_id INTEGER NOT NULL,
            upcoming INTEGER NOT NULL DEFAULT 0,
            timeModified INTEGER NOT NULL DEFAULT 0,
            wasDeleted INTEGER NOT NULL DEFAULT 0,
            title TEXT,
            podcastUuid TEXT,
            playlist_uuid TEXT
        );
        """,
        "CREATE INDEX IF NOT EXISTS playlist_episode_uuid ON SJPlaylistEpisode (episodeUuid);",
        "CREATE INDEX IF NOT EXISTS playlist_episode_playlist_id ON SJPlaylistEpisode (playlist_id);",
        "CREATE INDEX IF NOT EXISTS playlist_episode_playlist_uuid ON SJPlaylistEpisode (playlist_uuid);",
        "CREATE INDEX IF NOT EXISTS playlist_episode_playlist_uuid_pos ON SJPlaylistEpisode (playlist_uuid, episodePosition);",
        "CREATE INDEX IF NOT EXISTS playlist_episode_playlist_uuid_episode ON SJPlaylistEpisode (playlist_uuid, episodeUuid);",
        """
        CREATE TABLE UpNextChanges (
            id INTEGER PRIMARY KEY,
            type INTEGER NOT NULL,
            uuid TEXT,
            uuids TEXT,
            utcTime INTEGER NOT NULL
        );
        """,
        "CREATE INDEX IF NOT EXISTS up_next_changes_episode ON UpNextChanges (uuid);",
        "CREATE INDEX IF NOT EXISTS up_next_changes_time ON UpNextChanges (utcTime);",
        """
        CREATE TABLE SJUserEpisode (
            id INTEGER PRIMARY KEY,
            addedDate REAL NOT NULL,
            lastDownloadAttemptDate REAL NOT NULL DEFAULT 0,
            downloadErrorDetails TEXT,
            downloadTaskId TEXT,
            downloadUrl TEXT,
            episodeStatus INTEGER NOT NULL,
            fileType TEXT,
            contentType TEXT,
            playedUpTo REAL NOT NULL DEFAULT 0,
            duration REAL NOT NULL DEFAULT 0,
            playingStatus INTEGER NOT NULL,
            autoDownloadStatus INTEGER NOT NULL DEFAULT 0,
            publishedDate REAL,
            sizeInBytes INTEGER NOT NULL DEFAULT 0,
            playingStatusModified INTEGER NOT NULL DEFAULT 0,
            playedUpToModified INTEGER NOT NULL DEFAULT 0,
            title TEXT,
            uuid TEXT NOT NULL,
            playbackErrorDetails TEXT,
            cachedFrameCount INTEGER NOT NULL DEFAULT 0,
            uploadStatus INTEGER NOT NULL,
            uploadTaskId TEXT,
            imageUrl TEXT,
            imageColor INTEGER NOT NULL,
            hasCustomImage BOOLEAN DEFAULT FALSE,
            imageColorModified INTEGER NOT NULL DEFAULT 0,
            titleModified INTEGER NOT NULL DEFAULT 0,
            durationModified INTEGER NOT NULL DEFAULT 0,
            imageModified INTEGER NOT NULL DEFAULT 0
        );
        """,
        "CREATE INDEX IF NOT EXISTS user_episode_uuid ON SJUserEpisode (uuid);",
        "CREATE INDEX IF NOT EXISTS user_episode_episodeStatus ON SJUserEpisode (episodeStatus);",
        """
        CREATE TABLE Folder (
            uuid TEXT NOT NULL,
            name TEXT NOT NULL,
            color INTEGER NOT NULL,
            addedDate INTEGER NOT NULL,
            sortOrder INTEGER NOT NULL,
            sortType INTEGER NOT NULL,
            wasDeleted INTEGER NOT NULL,
            syncModified INTEGER NOT NULL,
            PRIMARY KEY(uuid)
        );
        """,
        """
        CREATE TABLE AutoAddCandidates (
            id INTEGER PRIMARY KEY,
            episode_uuid varchar(40) NOT NULL,
            podcast_uuid varchar(40) NOT NULL
        );
        """,
        "CREATE INDEX IF NOT EXISTS candidate_episode ON AutoAddCandidates (episode_uuid);",
        "CREATE INDEX IF NOT EXISTS candidate_podcast ON AutoAddCandidates (podcast_uuid);",
        """
        CREATE TABLE PlaylistEpisodeHistory (
            id INTEGER,
            episodePosition INTEGER NOT NULL DEFAULT 0,
            episodeUuid TEXT NOT NULL,
            playlist_id INTEGER NOT NULL,
            upcoming INTEGER NOT NULL DEFAULT 0,
            timeModified INTEGER NOT NULL DEFAULT 0,
            wasDeleted INTEGER NOT NULL DEFAULT 0,
            title TEXT,
            podcastUuid TEXT,
            date REAL NOT NULL
        );
        """,
        "CREATE INDEX IF NOT EXISTS episode_history_date ON PlaylistEpisodeHistory (date);",
        """
        CREATE TABLE PodcastFoldersHistory (
            podcastUuid TEXT NOT NULL,
            folderUuid TEXT NOT NULL,
            date REAL NOT NULL
        );
        """,
        "CREATE INDEX IF NOT EXISTS podcast_folders_history_date ON PodcastFoldersHistory (date);"
    ]
}
