# File-Sync On-Disk Format (Local-First Sync)

This fork syncs library state between devices through a folder of files in
iOS Files-accessible storage — iCloud Drive natively, or any user-picked
folder (Dropbox, Google Drive, local) via a security-scoped bookmark — with
no Pocket Casts server involved. Audio files dropped into the `Uploads/`
area of that folder become playable episodes on every device.

The implementation lives in the `PocketCastsFileSync` SwiftPM module
(`Modules/Sources/PocketCastsFileSync`), which deliberately does **not**
depend on `PocketCastsServer`.

## Folder layout

```text
Pocket Casts/                           # sync root (iCloud container Documents/, or picked folder)
├── Sync/
│   ├── version.pb                      # FormatVersion — readers refuse newer formats
│   └── devices/
│       └── <deviceId>/                 # ONLY this device ever writes here
│           ├── device.pb               # DeviceInfo: name, model, last-seen, head seq
│           ├── log-00000001.pcsync     # op log: length-delimited OpEnvelope records
│           ├── log-00000002.pcsync
│           └── snapshot-<seq>.pcsnap   # Snapshot: full state as of own op <seq>
├── Uploads/                            # user audio; subfolders = groupings
│   ├── loose-file.mp3
│   └── Audiobooks/chapter01.m4b
└── Podcast Mirrors/                    # opt-in per-podcast download mirror (one-way)
```

**The core invariant: each device writes only inside its own
`Sync/devices/<deviceId>/` directory.** No file is ever written by two
devices, so providers with no merge support (Dropbox, Drive) can never
produce conflicted copies of sync state. Merging happens at read time.

## Wire format

Schemas are vendored in `Modules/Sources/PocketCastsFileSync/Proto/`:

- `sync_records.proto` (package `api`) — a reconstruction of the Pocket
  Casts sync record schema from the generated code in `PocketCastsServer`,
  wire-compatible with `Api_Record` and friends. Fork extension: field
  `feed_url = 1000` on `SyncUserPodcast` stores the RSS feed URL so a
  future direct-RSS refresher needs no data migration.
- `filesync.proto` (package `filesync`) — the envelope and container
  formats: `OpEnvelope`, `RecordTombstone`, `UpNextOp`, `SettingOp`,
  `StatsCumulative`, `UploadIdentity`/`UploadTombstone`, `DeviceInfo`,
  `FormatVersion`, `Snapshot`.

Regenerate the Swift with `mise run generate:filesync-proto` (requires
protoc + protoc-gen-swift; see `scripts/generate-filesync-proto.sh`).
Field numbers and types of shipped fields must never change.

Log files are standard protobuf length-delimited framing:
`[varint length][OpEnvelope bytes]…`. Readers (`OpLogFile`) tolerate a
truncated final record — partially propagated cloud files are expected —
and resume from byte-offset cursors.

## Merge model

Ops from all devices are ordered by `(wall_clock_ms, device_id, seq)` and
folded last-writer-wins per field (`MergeEngine`, pure and unit-tested):

- **Episodes** merge per field using the `*_modified` timestamps embedded
  in the record — the same LWW scheme the app's database already uses.
- **Podcasts** merge per field on the envelope timestamp; nested
  `PodcastSettings` sub-merge per setting on their own `modified_at`.
- **Playlists and folders** merge whole-record (the app saves them whole).
- **Bookmarks** merge title/deleted per field, creation fields ride along.
- **Deletion** is just another LWW field (`subscribed=false` for podcasts,
  `is_deleted=true` elsewhere). `RecordTombstone` ops exist so snapshots
  can drop long-deleted records while keeping resurrection protection for
  `tombstoneRetention` (90 days).
- **Up Next** merges op-based (`UpNextMerger`): the newest `replace`
  anchors the queue, later add/remove ops replay on top — concurrent
  additions survive a reorder on another device.
- **Settings** are per-name LWW; **stats** are per-device monotonic
  counters (displayed totals sum across devices).

Change capture: `DataManager` journals user-intent saves into the
`FileSyncJournal` table (migration 75) transactionally with the change,
coalescing repeated position heartbeats. The journal is independent of
server-sync's `syncStatus`/`*Modified` bookkeeping so both engines can run
simultaneously; `DataManager.withFileSyncApplySuppression` keeps applied
remote ops from echoing back into the journal.

## Uploads ("the folder is the library")

Files in `Uploads/` are the source of truth. Discovery is "list now, hash
on download" (`UploadScanPlanner`, pure):

1. A new file immediately gets a **provisional** `UserEpisode` keyed by
   path+size (`identityState = 1`) — playable without downloading.
2. If the merged manifest (all devices' `UploadIdentity` ops) already maps
   that path+size, the shared uuid is **adopted** — devices agree on
   identity without re-downloading.
3. On first full materialization the file is SHA-256 hashed
   (`UploadIdentityResolver`): the episode is **promoted** to canonical
   (`identityState = 2`) and its identity published, or **re-keyed** onto
   the existing canonical episode (rename/duplicate detection), merging
   playback state by the freshest `*Modified` stamp.

Renames keep identity (hash, or size+mtime heuristic before hashing);
in-place content changes reset identity. Deleting the file removes the
episode everywhere; in-app delete coordinated-deletes the real file (the
provider's trash is the undo). Playback goes through `UploadMaterializer`:
a coordinated copy into the app's normal download cache
(`podcasts_non_backed_up/<uuid>.<ext>`), so `PlaybackManager` needs no new
code paths; evicting the cache never removes the episode.

## Compaction and hygiene

- Logs rotate at 512 KB / 2,000 ops.
- A device snapshots its merged state when >2 MB of its logs accumulate or
  weekly, then deletes own logs covered by the snapshot after a 7-day
  grace period. Readers whose cursor points at a deleted log fall back to
  snapshot bootstrap; snapshots persist per-field timestamps
  (`SnapshotRecord.field_modified_ms`) so LWW re-merge stays deterministic.
- Tombstones are retained in snapshots for 90 days. A device offline
  longer than that can resurrect deletions when it rejoins (documented
  limitation; the inspector flags devices unseen for 60+ days).
- "Forget device" writes a `DeviceForget` op and deletes that device's
  directory.

## iCloud specifics

The app declares an iCloud Documents container (`iCloud.$(bundle id)`)
with `NSUbiquitousContainerIsDocumentScopePublic = YES` so the folder is
visible in the Files app — that visibility is the feature: users drop
audio into `Uploads/` there. Change hints come from `NSMetadataQuery`
(`UbiquityChangeMonitor`); `FolderScanner` diffs full listings as a
backstop and as the only change source for picked folders. `Sync/` files
are downloaded eagerly; `Uploads/` audio stays as placeholders until
played or downloaded.

## Status / roadmap

Implemented: vendored schemas + generated code + protoc golden vectors,
pure merge engine + Up Next merger + log framing (unit-tested), folder
access layer (both kinds), change journal + DataManager hooks + cursors
(migration 75, tested), uploads planner/resolver/materializer
(planner unit-tested), `FileSyncManager` facade with device presence and
uploads reconciliation.

Next: op flusher (journal → log files), remote ingest + `RemoteOpApplier`
(merged state → DataManager via `saveIfNotModified`/suppression), union-
join bootstrap and seeding, cadence trigger wiring in the app, iCloud
entitlements + Info.plist, rebacked Files UI, settings/stats observers,
snapshot writer, inspector UI. See the implementation plan for phasing.
