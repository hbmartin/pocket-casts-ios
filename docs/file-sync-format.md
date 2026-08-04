# Uploads Folder Format

The Files tab is backed by a folder of audio files in iOS Files-accessible
storage — iCloud Drive natively, or any user-picked folder (Dropbox, Google
Drive, local) via a security-scoped bookmark. Audio files dropped into the
`Uploads/` area of that folder become playable episodes on every device
pointing at the same folder.

The implementation lives in the `PocketCastsFileSync` SwiftPM module
(`Modules/Sources/PocketCastsFileSync`), which deliberately does **not**
depend on `PocketCastsServer`.

> **History:** this folder used to carry a full library sync engine (per-device
> protobuf op logs under `Sync/`, plus an opt-in `Podcast Mirrors/` download
> cache). The engine was removed in August 2026 — library and playback state
> now sync through backend account sync. Folders written before the removal may
> still contain `Sync/` and `Podcast Mirrors/` directories; both are obsolete
> debris and safe to delete manually (mirrors can be large).

## Folder layout

```text
Pocket Casts/                           # root (iCloud container Documents/, or picked folder)
└── Uploads/                            # user audio; subfolders = groupings
    ├── loose-file.mp3
    └── Audiobooks/chapter01.m4b
```

The first path component below `Uploads/` is the episode's group (`groupName`,
shown as a section in the Files tab); loose files have an empty group.

## Identity model ("list now, hash on download")

`UploadsScanner` reconciles the folder listing against `SJUserEpisode` rows on
every scan pass (app activation, pull-to-refresh, folder change hints on
iCloud). The pure decision core is `UploadScanPlanner`; identity state persists
in the migration-75 columns on `SJUserEpisode` (`folderRelativePath`,
`contentHash`, `groupName`, `identityState`):

- A newly discovered file gets a **provisional** episode keyed by
  path+size(+mtime), so it is listable and playable immediately — even while
  the bytes are still a cloud placeholder.
- When the file is first fully materialized (played or downloaded) it is
  SHA-256 hashed; the hash either **promotes** the provisional episode to
  **canonical** or **re-keys** it onto an existing canonical episode that
  already owns that content (rename/copy detection, merging playback state).
- A file replaced in place (same path, different size) resets its episode to
  provisional; a file that vanishes (and no rename target matches) removes its
  episode row — cloud trash is the undo.
- `identityState = 0` (`legacyLocal`) marks pre-folder app-local files; they
  have no `folderRelativePath` and never touch the folder.

Because the removal of the sync engine took the cross-device identity manifest
with it, each device now mints its own episode UUIDs for the same folder file:
the files themselves appear everywhere, but per-file playback position does
not follow across devices.

## Scanning and I/O

- All folder I/O goes through `NSFileCoordinator` (`CoordinatedFileIO`) so File
  Provider extensions observe coherent reads and writes.
- `UbiquitySyncFolder` (iCloud) delivers change hints via `NSMetadataQuery`;
  `BookmarkSyncFolder` (picked folders) is scan-based because third-party File
  Providers push no notifications.
- Placeholder entries (`.icloud` stubs) are listed with their real size, so
  provisional episodes exist before the bytes are local; `ensureMaterialized`
  triggers the download when playback needs them.

## Settings

`FileSync.enabled`, `FileSync.folderKind`, and `FileSync.rootBookmark` in
UserDefaults. iCloud is silently enabled on first launch when available and
nothing was configured; Settings → File Sync swaps to a picked folder.
