import Foundation
import PocketCastsUtils

class DatabaseHelper {
    private static let currentSchemaVersion: Int32 = 73
    private static let minimumMigratableSchemaVersion: Int32 = 73

    class func setup(queue: PCDBQueue) {
        queue.write { db in
            do {
                try db.executeQuery("PRAGMA busy_timeout = 10000", values: nil).close()

                let startingSchemaVersion = db.pragmaUserVersion() ?? 0

                var newSchemaVersion = startingSchemaVersion
                upgradeIfRequired(schemaVersion: &newSchemaVersion, db: db)

                if newSchemaVersion != startingSchemaVersion {
                    FileLog.shared.addMessage("Schema update from \(startingSchemaVersion) to \(newSchemaVersion)")
                    try db.executeUpdate("PRAGMA user_version = \(newSchemaVersion)", values: nil)
                }
            } catch {
                assertionFailure("Failed to setup database \(db.lastErrorCode()): \(db.lastErrorMessage()) actual error: \(error)")
                FileLog.shared.addMessage("Failed to setup database \(db.lastErrorCode()): \(db.lastErrorMessage()) actual error: \(error)")
            }
        }
    }

    private class func upgradeIfRequired(schemaVersion: inout Int32, db: PCDatabase) {
        guard schemaVersion < currentSchemaVersion else { return }
        guard schemaVersion == 0 || schemaVersion >= minimumMigratableSchemaVersion else { return }

        db.beginTransaction()

        do {
            if schemaVersion == 0 {
                try createCurrentSchema(db: db)
                schemaVersion = currentSchemaVersion
            } else {
                try migrateSchema(schemaVersion: &schemaVersion, db: db)
            }
            db.commit()
        } catch {
            let lastErrorCode = db.lastErrorCode()
            let lastErrorMessage = db.lastErrorMessage()
            db.rollback()
            FileLog.shared.addMessage("Schema setup failed, code \(lastErrorCode): \(lastErrorMessage), actual error: \(error)")
        }
    }

    private class func migrateSchema(schemaVersion: inout Int32, db: PCDatabase) throws {
        _ = db
        _ = schemaVersion
        // Append future migrations here as currentSchemaVersion increases, updating schemaVersion after each step.
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
