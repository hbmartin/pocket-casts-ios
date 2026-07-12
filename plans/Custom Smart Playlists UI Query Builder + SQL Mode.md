# Custom Smart Playlists: UI Query Builder + SQL Mode

## Context

Pocket Casts "smart playlists" (aka episode filters, model `EpisodeFilter`, table `SJFilteredPlaylist`) support only a fixed set of toggle criteria — play status, download status, media type, starred, duration bounds, release-date window, podcast list — compiled to SQL in `PlaylistQueryBuilder`. This feature adds a third playlist kind, **custom**, letting users build arbitrarily complex queries two ways:

1. **Builder mode** — a visual editor with nested All/Any condition groups over a typed field catalog (title contains, progress %, dates, sizes, season numbers, …).
2. **SQL mode** — direct entry of a SQL `WHERE`-clause body over the `episode`/`podcast` table aliases, validated before save.

Every playlist surface (detail list, tab cells/counts, badges, auto-download, metadata cache, previews, local search) already flows through `PlaylistQueryBuilder.query(clause:for:...)`, so a custom branch at that single point covers nearly the whole app.

## Decisions taken (recommended defaults — veto at review if wrong)

The interactive question dialog failed to deliver in this session, so these ship as the plan's assumptions:

| Decision                 | Choice                                                       | Why                                                          |
| ------------------------ | ------------------------------------------------------------ | ------------------------------------------------------------ |
| Sync                     | **Device-local v1** (excluded from account sync + FileSync; "Only on this device" copy in editor) | Sync protocol has no field for custom queries; a synced custom playlist would upload garbled and full sync would wipe its query. Server support needs pocketcasts-api changes. |
| SQL input shape          | **WHERE-clause body**, not full SELECT                       | Slots into all four existing `SelectClause` wrappers (episodes/counts/first-distinct), search, sort, LIMIT. Subqueries inside WHERE keep power. |
| Builder expressiveness   | **Nested All/Any groups, depth ≤ 3**                         | Matches "complex queries" goal; caps keep UI + compiler sane. |
| Existing-playlist bridge | **Seed-copy only** ("start from current rules" pre-fills a NEW playlist); no in-place smart→custom conversion | In-place conversion of a synced playlist makes sync guards murky. |
| Unsubscribed podcasts    | **Not force-excluded** for custom playlists (smart playlists force-exclude them) | Force-appending the exclusion silently rewrites user intent; expose `podcastSubscribed` as a queryable field instead. |
| Sort                     | Existing `sortType` picker only; no custom ORDER BY in v1    | Fragment is expression-position only, so ORDER BY injection fails validation naturally. |
| Rollout                  | `FeatureFlag.customPlaylists`, default `.debug` builds only  | House pattern (`FeatureFlag.swift`); remote key auto-derives to `custom_playlists`. |

## Verified architecture facts the plan relies on

- **GRDB 7.10** (`Modules/Package.resolved`): `db.makeStatement(sql:)` throws on syntax errors and on multi-statement strings; `Statement.isReadonly` wraps `sqlite3_stmt_readonly`. `GRDBQueue` wraps a `DatabasePool`; `read {}` uses true read-only connections when `FeatureFlag.concurrentDatabaseReads` is on (default true).
- **Full sync** (`SyncTask+FullSync.swift:6-36`) only delete-rewrites local playlists whose uuid matches a server record; the dangerous path for custom playlists is upload: `markAllPlaylistsUnsynced()` + `changedPlaylists()` → `allUnsyncedPlaylists()`.
- **Legacy raw-read path**: `PlaylistDataManager.columnNames` (line 25) + `createPlaylistFrom(resultSet:)` must include any new column or re-saving a playlist loaded that way silently drops it (`EpisodeFilterColumnConsistencyTests` guards this).
- **Two callers bypass** the modern builder via legacy `queryFor(filter:)`: `SiriShortcutsManager.swift:455` and `EpisodesDataManager.episodes(for:)` (~141, used by `AutoplayHelper`). They need explicit routing for custom playlists.
- **Fetch failures don't crash**: `EpisodeDataManager.loadMultiple` catches, logs to `FileLog`, returns `[]`.

## Implementation

### A. Data model + migration

1. `Modules/Sources/PocketCastsDataModel/Private/Managers/Util/DatabaseHelper.swift` — append `SchemaMigration(toVersion: 78)`: `ALTER TABLE SJFilteredPlaylist ADD COLUMN customQuery TEXT;`
2. `Modules/Sources/PocketCastsDataModel/Public/Model/EpisodeFilter.swift` — add:
   ```swift
   public var customQuery: String?                                  // JSON envelope; nil = normal playlist
   public var isCustom: Bool { customQuery != nil && !manual }      // computed, not persisted
   ```
   (`playlistUpdateDate: Date?` is the precedent for optional columns under `@GRDBRecord`.)
3. `Modules/Sources/PocketCastsDataModel/Private/Managers/PlaylistDataManager.swift` — add `customQuery` to `columnNames` and `createPlaylistFrom(resultSet:)`.

### B. Query engine — new dir `Modules/Sources/PocketCastsDataModel/Public/CustomPlaylist/`

1. **`CustomPlaylistQuery.swift`** — versioned Codable envelope stored in `customQuery`:
   ```json
   { "version": 1, "mode": "builder", "root": { …AST… } }
   { "version": 1, "mode": "sql", "sql": "episode.duration > 1800 AND podcast.title LIKE '%history%'" }
   ```
   Unknown version / undecodable ⇒ compiles to `AND (0)`: playlist renders empty ("unsupported query" UI state), never crashes. Builder mode is **recompiled at query time** (never store compiled SQL) so relative dates evaluate freshly, matching `filterTimeFor(hours:)` semantics.

2. **AST** (`CustomQueryNode`, Codable): `group` nodes (`op: all|any`, `children`) and `condition` nodes (`field`, `op`, typed `value`: string / number / bool / date `{epoch}` or `{relativeDays}` / stringList). Compiler-enforced caps: depth ≤ 3, ≤ 20 children per group, ≤ 50 conditions total.

3. **`CustomQueryField.swift`** — public field catalog (UI reads it for pickers; compiler is the only source of identifiers — user text never reaches identifier position). v1 fields:
   `episodeTitle`, `episodeDescription`, `podcastTitle` (text: contains/notContains/equals/startsWith/endsWith), `podcast` (uuid in/notIn via picker), `duration`, `playedUpTo`, `fileSize`, `seasonNumber`, `episodeNumber` (number ops incl. between, isSet), `progressPercent` (computed CASE expression), `playingStatus`, `downloadStatus`, `episodeType`, `mediaType` (enum in/notIn), `starred`, `podcastSubscribed` (bool), `publishedDate`, `addedDate`, `lastPlayedDate` (date: inLastDays/before/after/between/isSet). Dates are REAL `timeIntervalSince1970` columns; `GRDBDatabase.executeQuery` already maps bound `Date` args.

4. **`CustomQueryCompiler.swift`**:
   ```swift
   public enum CustomQueryCompiler {
       public static func compile(_ root: CustomQueryNode, now: Date = Date()) throws -> (sql: String, arguments: [Any])
   }
   ```
   All values bound as `?`. Text `contains` reuses LIKE-escaping — extract `likePattern(for:)` from `PlaylistQueryBuilder.swift:290` into a shared internal helper.

5. **`PlaylistQueryValidator.swift`** + `DataManager.validateCustomQueryFragment(_:) -> Result<Int, CustomQueryValidationError>` (Int = match count; `dbQueue` is internal so DB access goes through DataManager). Pipeline (off-main):
   1. Trim; reject empty; cap 4,000 chars.
   2. Reject `?` / `:name` / `$name` / `@name` placeholders (SQL mode is zero-argument; avoids the `StatementArguments` force-unwrap path in `GRDBDatabase.swift`).
   3. Wrap in the exact `.episodeCount` SQL shape and `try db.makeStatement(sql:)` on a read connection — syntax errors and multi-statement input (`1=1); DROP TABLE …`) both throw.
   4. Assert `statement.isReadonly` (blocks e.g. `DELETE … RETURNING` and any non-SELECT).
   5. Trial-execute the count inside `dbQueue.read {}`; catch runtime-only errors ("no such column"); return match count. Warn (not block) if wall time > ~500 ms.
   Errors: `empty, tooLong, containsPlaceholders, syntax(message), multipleStatements, notReadOnly, executionFailed(message)`.

6. **`PlaylistQueryBuilder.swift` integration** — in the non-manual branch of `query(clause:for:...)` (~line 239), swap the fragment producer:
   ```swift
   if FeatureFlag.customPlaylists.enabled, playlist.isCustom, let custom = CustomPlaylistQuery(envelopeJSON: playlist.customQuery) {
       queryValues.append(add(customRulesFor: custom, arguments: &arguments))
   } else {
       queryValues.append(add(smartRulesFor: playlist, arguments: &arguments))
   }
   ```
   Everything downstream (episodeUuidToAdd wrapper, first-distinct CTE, count CTEs, search LIKE, `add(sortFor:)`, LIMIT, archived handling) is reused untouched, so all four `SelectClause` shapes work. Also add public `smartRulesFragment(for:)` (refactor of `add(smartRulesFor:)`, uuids inlined as quoted literals, unsubscribed-exclusion stripped) to power "start from current rules" seeding.

### C. Sync / replication guards (device-local)

1. `PlaylistDataManager.allUnsyncedPlaylists` (line ~130) and `markAllUnsynced` (~372): add `customQuery == nil` filter — stops all uploads (`changedPlaylists()` in `SyncTask+LocalChanges.swift:110` is the sole consumer).
2. `SyncTask+ServerChanges.importPlaylist` (line 272): if the local playlist with that uuid `isCustom`, log + skip (uuid-collision belt-and-braces).
3. `SyncTask+FullSync.processServerPlaylists` (line 6): skip the delete+rewrite when the matching local playlist `isCustom`.
4. `podcasts/PlaylistManager.swift` `delete(...)` (~line 67): custom playlists hard-delete locally even when signed in (no tombstone upload for a uuid the server never saw).
5. `Modules/Sources/PocketCastsFileSync/Engine/OpJournalFlusher.swift:173` (`case (.playlist, .upsert)`): return nil for custom playlists (peers can't represent them).

### D. Legacy-path routing

- `podcasts/SiriShortcutsManager.swift:455` (`playFilter`) and `podcasts/EpisodesDataManager.swift` `episodes(for:)` (~141): when `filter.isCustom`, delegate to `DataManager.playlistEpisodes(for:)` instead of legacy `queryFor(filter:)` (do not extend the legacy builder — it lacks table aliases).

### E. UI — new dir `podcasts/New Creation/Custom Query/`

- **Entry**: `NewPlaylistViewController.setupContent()` adds a second SwiftUI card below `SmartPlaylistCreationView` (generalize it with title/subtitle/icon params or add sibling `CustomPlaylistCreationView`), shown only when `FeatureFlag.customPlaylists.enabled`; presents the editor the same way `createSmartPlaylist()` presents `PlaylistPreviewViewController`.
- **`CustomPlaylistEditorViewController`** — UIKit shell mirroring `PlaylistPreviewViewController` (modes `.creation`/`.edit`, `FilterCreatedDelegate`, bottom save button in creation; save = `bumpSortPositionForAllPlaylists` + `DataManager.save(playlist:)` + `filterCreated` + `Constants.Notifications.playlistChanged`).
- **`CustomPlaylistEditorViewModel`** (`@MainActor ObservableObject`) — draft `EpisodeFilter`, Builder|SQL mode picker, AST document, validation state, debounced live preview reusing `PlaylistRefreshOperation` (takes an `EpisodeFilter`; the draft flows through the new builder branch) + `playlistEpisodeCount(for:)` for match count. Footer copy: "Only on this device".
- **`CustomQueryBuilderView`** (SwiftUI) — recursive group editor: All/Any segmented header, add condition/group, delete; depth cap enforced by hiding "add group" at depth 3. **`CustomQueryConditionRow`** — field `Menu` from the catalog, operator picker filtered by field type, typed value editor (TextField/.decimalPad, DatePicker, Toggle, enum picker, podcast multi-select sheet). Theming per house rules: `@EnvironmentObject var theme: Theme`, `AppTheme.color(for:theme:)`, hosted via `ThemedHostingController`/`insertThemedUIView`.
- **`CustomQuerySQLView`** — editable monospace `UITextView` wrapper (start from `podcasts/Common SwiftUI/NonEditableTextView.swift` pattern; `autocorrectionType/.autocapitalizationType/.smartQuotesType/.smartDashesType` all off — smart quotes silently break SQL), Validate button + inline themed error, live count/preview once valid, "Schema reference" sheet (**`CustomQuerySchemaReferenceView`**: field catalog as column/type/example rows), "Start from current rules" seeding via `smartRulesFragment(for:)`. Save disabled until validation passes.
- **Edit routing**: `podcasts/New Detail/PlaylistDetailViewController.swift` `editPlaylist()` (~400) branches on `playlist.isCustom` → custom editor. `FilterEditOptionsViewController` (auto-download, Siri) works unchanged. Detail list, tab cells, badges, auto-download, metadata cache all work via the single builder branch.

### F. Flag, strings, analytics

- `Modules/Sources/PocketCastsUtils/Feature Flags/FeatureFlag.swift`: `case customPlaylists`, default `BuildEnvironment.current == .debug`.
- `podcasts/en.lproj/Localizable.strings`: `playlist_custom_*` keys (snake_case, translator comments, positional specifiers) → SwiftGen `L10n`.
- Analytics (`podcasts/Analytics/AnalyticsEvent.swift` + existing playlist track sites): `filterCreateAsCustomPlaylistTapped`, `filterCustomQueryValidated {result, mode}`, and `custom: true, custom_mode: builder|sql` properties on existing `.filterCreated`/`.filterUpdated`.

### G. Tests + guardrails

- `Modules/Tests/PocketCastsDataModelTests/`:
  - `CustomQueryCompilerTests` — golden (sql, arguments) per operator, nesting, caps, LIKE escaping, relative dates with injected `now`.
  - `PlaylistQueryValidatorTests` — accepts subqueries; rejects syntax errors, `1=1); DROP TABLE SJEpisode;--`, placeholders, over-length, non-readonly.
  - `PlaylistQueryBuilderCustomTests` — all four clauses execute against the in-memory test DB (à la `DataManagerTestCase`) incl. episodeUuidToAdd, search, sort; flag-off renders as empty smart playlist.
  - Migration v78 + extend `EpisodeFilterColumnConsistencyTests` (round-trip `customQuery`).
- Server tests: `allUnsyncedPlaylists` exclusion, `importPlaylist` skip, `processServerPlaylists` preservation.
- `Modules/Tests/SnapshotTests/`: builder view (empty/nested/error) and SQL view (valid/invalid) per `docs/snapshot-testing.md`.
- Semgrep (`semgrep/swift-security.yml`, per CLAUDE.md): rule flagging `findPlaylistEpisodesWhere(query:`-style raw-SQL calls in `podcasts/` whose query isn't a `PlaylistQueryBuilder` product — generalizes the "user SQL only enters the DB through the validator" invariant. Annotate the validator's `executeQuery` sites with justification comments.

## Suggested implementation order

A (schema/model) → B (engine + tests, pure logic first) → C (sync guards + tests) → D (legacy routing) → E (UI) → F (flag/strings/analytics) → G (snapshots, semgrep, polish). A–D are testable without any UI.

## Verification

1. `mise run format` and `mise run check:static` (SwiftLint + semgrep incl. the new rule).
2. Module tests: `ONLY_TESTING=PocketCastsDataModelTests mise run test:staging` and `ONLY_TESTING=PocketCastsServerTests mise run test:staging`; snapshot tests `make test_staging ONLY_TESTING=SnapshotTests` (record baselines first per docs/snapshot-testing.md).
3. Manual on Simulator (`mise run build:staging`, launch per CLAUDE.md):
   - Create a builder playlist (nested Any-inside-All, e.g. *unplayed AND (title contains "interview" OR duration > 1h)*); confirm detail list, tab cell count/artwork, and search-within-playlist.
   - Create a SQL playlist incl. a subquery; confirm invalid SQL (syntax error, `DROP`, multi-statement, unknown column) shows inline errors and Save stays disabled.
   - Kill/relaunch → playlists persist. Toggle flag off → custom playlists render empty, no crash.
   - Signed-in account: run a full sync → custom playlist survives, never appears on another device; delete it → no tombstone upload errors in logs.
   - Auto-download on a custom playlist downloads matches; badge count setting reflects it; Siri "play filter" plays its top episode; autoplay continues within it.