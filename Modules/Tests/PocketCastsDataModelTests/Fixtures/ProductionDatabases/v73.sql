-- Sanitized production-shape data captured at schema version 73. DatabaseHelper
-- creates the exact baked v73 schema before this fixture is loaded; this file
-- supplies representative user data whose preservation is the migration contract.
INSERT INTO Folder (
    uuid, name, color, addedDate, sortOrder, sortType, wasDeleted, syncModified
) VALUES (
    'fixture-folder', 'Saved Shows', 2, 1700000000, 0, 2, 0, 1700000000000
);

INSERT INTO SJPodcast (
    id, addedDate, podcastUrl, title, uuid, subscribed, syncStatus, folderUuid
) VALUES (
    101, 1700000000, 'https://example.test/fixture.xml', 'Fixture & Friends',
    'fixture-podcast', 1, 1, 'fixture-folder'
);

INSERT INTO SJEpisode (
    id, addedDate, downloadUrl, episodeStatus, playedUpTo, duration, playingStatus,
    publishedDate, title, uuid, podcastUuid, podcast_id
) VALUES (
    201, 1700000100, 'https://example.test/fixture.mp3', 1, 321.5, 3600, 2,
    1700000100, 'An Episode Worth Keeping', 'fixture-episode', 'fixture-podcast', 101
);

INSERT INTO SJFilteredPlaylist (
    id, playlistName, sortPosition, sortType, uuid, syncStatus, manual
) VALUES (
    301, 'Fixture Queue', 0, 4, 'fixture-playlist', 1, 1
);

INSERT INTO SJPlaylistEpisode (
    id, episodePosition, episodeUuid, playlist_id, title, podcastUuid
) VALUES (
    401, 0, 'fixture-episode', 1, 'An Episode Worth Keeping', 'fixture-podcast'
);

INSERT INTO SJUserEpisode (
    id, addedDate, downloadUrl, episodeStatus, playedUpTo, duration, playingStatus,
    publishedDate, title, uuid, uploadStatus, imageColor
) VALUES (
    501, 1700000200, 'fixture-user-episode.m4a', 5, 12, 90, 2,
    1700000200, 'A Local File', 'fixture-user-episode', 5, 0
);
