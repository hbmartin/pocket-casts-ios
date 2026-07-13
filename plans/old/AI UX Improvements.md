# Pocket Casts iOS — AI based UX Improvements

> Queued 2026-07-12 (user-provided mid-session). Execution notes from the program session:
> Phase 1 is ALREADY SHIPPED — the local-first program's A4 commit deleted
> `FeatureFlag.generatedChapters` outright (available in all builds), which supersedes the
> planned default flip. The "Linux" constraints in this plan (hand-editing Strings+Generated,
> protoc availability) do not apply on this Mac environment — SwiftGen/protoc run normally.
> Phase 4 (transcript FTS) overlaps the transcription plan's FTS design; reconcile table
> naming/ownership when whichever lands second. docs/ServerBackendSpec.md was deleted by
> program decision #59 — the Phase 2/6 payload documentation goes in docs/ServerAPISurface.md.

## Context

A July 2026 comparison of 18 iOS podcast apps shows Pocket Casts trailing Snipd, Spotify, Apple Podcasts, Metacast, and Castamatic on AI-assisted features — while this codebase already owns most of the required infrastructure: a generated-metadata endpoint returning AI chapters *and* summaries (summary fetched but never displayed), cue-timed transcripts with a fingerprint seek-mapping subsystem, bookmarks, clip sharing, smart playlists, and PodcastIndex chapter ingestion. This plan closes those gaps with six features plus a documented deferral, all free (no paid gates), all client-side (no new server dependencies).

**User-locked decisions:**
- #3 is **summary citations only** — tappable timestamped key-takeaways on the AI summary card; the transcript view is untouched (it already has cue-level tap-to-seek).
- Language intelligence = **on-device Apple FoundationModels** (iOS 26 floor is already 26.0; runtime `SystemLanguageModel.default.availability` check) with **deterministic fallback** on every device.
- **Everything free**; bookmarks are already un-gated in this fork. Rollout control via feature flags only.
- Daily briefing / highlights feed is **deferred** and must be documented.

## Key verified facts (anchors)

- `ShowInfoCoordinator.loadChapters` (podcasts/Episode Info Coordinator/ShowInfoCoordinator.swift:63-85): external-chapter priority PodcastIndex → Podlove → generated; `FeatureFlag.generatedChapters` checked only at :78; envelope `summary` (GeneratedEpisodeMetadataRetriever.swift:6) has zero readers.
- Generated chapters are fully wired into player/chapters-list UI incl. "AI-generated" warning header (ChaptersHeader.swift:96-97, `PlaybackManager.chaptersAreGenerated`). Shipping = flag default change only.
- `ChapterInfo.url` exists with working link UI (player + `PlayerChapterCell`); only the embedded-chapter parser populates it (PodcastChapterParser.swift:133-135) — Podlove/PodcastIndex parsers drop `url`.
- Episode-detail cards = code-embedded `ThemedHostingController` child VCs (pattern: EpisodeDetailViewController+ShowNotes.swift:47-81).
- Transcripts: cue-level timing (`TranscriptCue{startTime,endTime,characterRange}`); raw text in URLCache only, never in DB; no FTS anywhere. Playback↔reference mapping via `FingerprintTimingManager` (generated transcripts only); generated-chapter seeks are raw today.
- Bookmarks: `Bookmark` model + `BookmarkDataManager` (GRDB macros); created instantly with default title from shelf/headphone actions via `PlaybackManager.bookmark(source:)`; no excerpt field.
- `PlaybackManager.playBookmark(_:source:firstTry:)` (PlaybackManager.swift:2541) already implements load-episode-then-seek — generalize it for all deep-link seeks.
- DB: schema version 77; **new tables/columns go ONLY in a new `SchemaMigration`** (baseline frozen at 73; fresh installs run baseline + all migrations — DatabaseHelper.swift:13-15). Raw DDL in migrations is the established pattern (no nosemgrep needed).
- GRDB 7.10.0 (FTS5 available); `fuse-swift` 1.4.0 already a dependency (fuzzy matching).
- Smart playlists: `EpisodeFilter` (@GRDBRecord, table SJFilteredPlaylist); creation flow `NewPlaylistViewController.createSmartPlaylist()` → `PlaylistPreviewViewController(playlistName:)` builds an **unsaved draft** in `viewDidLoad`/`createNewPlaylist()` (:72-88), persisted only via `PlaylistPreviewViewModel.saveFilter()` — prefill = new initializer, review-before-save holds by construction.
- New Search: `SearchResultsModel` + `NewSearchResultsView` pill filter over `SearchResultsListView.DisplayMode` — adding a section = new published array + new pill case + row view.
- `Episode.Metadata` (Episode.swift:204-234) has showNotes/image/chapters/chaptersUrl/transcripts — **no persons field**; local-feed podcasts synthesize metadata via `FeedParser` (parses `<podcast:chapters>`, not `<podcast:person>`). No PodcastIndex API credentials exist (chapter retriever just GETs a JSON URL).
- Conventions: L10n via Localizable.strings + SwiftGen (`Strings+Generated.swift`); analytics = enum case (snake_case auto-derived); flags in FeatureFlag.swift with auto remote keys + `docs/FeatureFlagAudit.md` table; fork documents expected backend payloads in `docs/ServerBackendSpec.md` / `ServerAPISurface.md`.

## Cross-cutting design

### FoundationModels wrapper — `podcasts/Intelligence/`
- `OnDeviceIntelligence` actor + `IntelligenceProviding` protocol (`availability()`, `respond<T: Generable & Sendable>(instructions:prompt:generating:)`); checks `SystemLanguageModel.default.availability` per call; short-lived `LanguageModelSession` per request; per-call timeout; errors mapped to `IntelligenceError`. Lives in the app target (OS framework, no SPM change; all consumers are app-target).
- Feature services take `any IntelligenceProviding` (mockable in PocketCastsTests) and own their deterministic fallbacks so every device gets the feature.
- Prompt-injection posture: transcript/summary text passed as data with ignore-embedded-directives instructions; outputs length-capped; timestamps validated (clamp to `[0, duration]`, snap to nearest cue startTime, drop non-snappable).

### Feature flags (FeatureFlag.swift; remote keys auto-derive; each gets a FeatureFlagAudit.md row)
| Flag | Default |
| --- | --- |
| `generatedChapters` (existing) | ~~change to `true`~~ ALREADY DELETED (shipped un-gated) in program commit A4 |
| `episodeSummaries`, `smartHighlights`, `transcriptSearch`, `promptedPlaylists`, `episodeCredits` (new) | `BuildEnvironment.current != .appStore` |

Chapter url/img passthrough ships un-flagged (parity with embedded chapters).

### DB migrations (append after toVersion 77)
- **78** (Phase 3): `ALTER TABLE Bookmark ADD COLUMN excerpt TEXT;` + `ALTER TABLE Bookmark ADD COLUMN endTime REAL;`
- **79** (Phase 4): `CREATE VIRTUAL TABLE TranscriptCueIndex USING fts5(text, episodeUuid UNINDEXED, podcastUuid UNINDEXED, cueIndex UNINDEXED, startTime UNINDEXED, endTime UNINDEXED, tokenize='unicode61 remove_diacritics 2');` + plain `TranscriptIndexMeta(episodeUuid PK, podcastUuid, indexedDate, cueCount, textBytes)` for LRU bookkeeping.
- NOTE (session): migration numbers must be re-checked against the live tail at execution time — the transcription plan also claims 78.

### Commit strategy
Seven commits, one per phase, each self-contained (its flags, L10n, analytics, tests, doc rows). (Branching per this session's layout: work continues on the program branch lineage unless the user redirects.)

## Phase 1 — Ship AI chapters
DONE (superseded): `FeatureFlag.generatedChapters` deleted in program commit A4; audit row recorded.

## Phase 2 — AI summary card with tap-to-seek key takeaways (+ intelligence foundation)
- **Create** `podcasts/Intelligence/OnDeviceIntelligence.swift` (wrapper above); `SummaryTakeawayGenerator.swift` (`Takeaway{text,startTime}`; layered: FM `@Generable` takeaways over a ~3k-token time-stamped cue digest when available → else generated chapters as "Key moments" → summary always renders); `TimestampLinkifier.swift` (regex `\b(?:\d{1,2}:)?\d{1,2}:\d{2}\b` → tappable ranges); `podcasts/Episode/Summary/EpisodeSummaryCardView.swift` + `EpisodeSummaryViewModel.swift` (themed SwiftUI: header + sparkle + "AI-generated" caption, linkified summary, takeaway rows with mm:ss chips, expand/collapse).
- **Modify** `ShowInfoCoordinator` — add `loadEpisodeSummary(podcastUuid:episodeUuid:) async throws -> String?` returning `loadMetadata(...).summary` (reuses retriever coalescing/cache) + protocol entry. `PlaybackManager` — extract `playBookmark`'s core into `play(episodeUuid:podcastUuid:at:)`; `playBookmark` delegates. `EpisodeDetailViewController(+ShowNotes)` — flag-gated card between transcript excerpt and show notes via code-created container view + constraints hosting `ThemedHostingController`.
- **Seek path**: current episode + `FingerprintTimingManager.state == .active` → map `playbackTime(forReferenceTime:)` (matches transcript tap-to-seek); nil mapping → raw `seekTo` (matches today's generated-chapter seeks); episode not loaded → `play(episodeUuid:podcastUuid:at:)`. Skip card for `UserEpisode`.
- Flag `episodeSummaries`. L10n: `episode_summary_card_title/_generated_disclaimer/_key_moments/_show_more/_show_less`. Analytics: `episodeDetailSummaryCardShown/TakeawayTapped/GenerationFailed(fallback_layer)`.
- Tests (PocketCastsTests): `TimestampLinkifierTests`; `SummaryTakeawayGeneratorTests` with mock provider (FM path, unavailable→chapters fallback, clamp/snap/drop). Snapshot of card if module-visible, else Mac-side QA.

## Phase 3 — Smart highlights (bookmark + excerpt + auto-title + quote card)
- **Migration 78** (above). **Modify** `Bookmark` + `BookmarkRow`/`BookmarkDataManager`: `excerpt: String?`, `endTime: TimeInterval?`, `updateEnrichment(uuid:excerpt:endTime:...)` + fileSync journal record.
- **Create** `podcasts/Bookmarks/Highlights/HighlightEnricher.swift`: subscribes `BookmarkManager.onBookmarkCreated` (flag-gated, dedupe-safe); background task: `TranscriptManager.loadTranscript()` → map bookmark time to reference time when generated+`.active` (else raw) → select cues intersecting `[t−10s, t+5s]` (text via `characterRange`) → write excerpt/endTime → FM ≤6-word title (`HighlightTitleGenerator`, fallback = first-sentence truncation ~50 chars) applied **only if title is still `L10n.bookmarkDefaultTitle`** (rename race guard) → emit `onBookmarkChanged`. No transcript → plain bookmark, no regression.
- **Sharing**: new `SharingModal.Option.highlight(Episode, Bookmark)`; new `ShareImageStyle.quote` branch in `ShareImageView` (gradient bg, quote glyph, excerpt, attribution, logo pill); `ShareImageInfo.excerpt: String?`; `SharingView.styles(for:)` returns `[.quote, .large, .medium, .small]` for `.highlight` only; `shareData` renders static image for `.quote`; `copyLink` keeps `?t=` URL. Bookmark rows (player/podcast/episode/profile lists) use `.highlight` when `excerpt != nil`; `BookmarkRowView` shows 2-line excerpt preview.
- **fileSync proto**: add optional `excerpt`/`end_time` to bookmark record in `sync_records.proto` + `RecordConverters`/`SnapshotWriter`/`RemoteOpApplier`; regenerate via `mise run generate:filesync-proto`.
- Flag `smartHighlights`. L10n: `highlight_quote_share_style`, `highlight_excerpt_unavailable` + a11y labels. Analytics: `highlightEnrichmentCompleted/Failed(reason)`, `highlightQuoteShared`.
- Tests: PocketCastsDataModelTests (column round-trip, updateEnrichment, migration-78 upgrade path); PocketCastsTests (`HighlightExcerptBuilder` cue-window + title fallback, pure logic); PocketCastsFileSyncTests (record round-trip); snapshot `.quote` card.

## Phase 4 — Library-wide transcript search
- **Migration 79** (above). **Create** `Modules/.../PocketCastsDataModel/Public/Transcripts/TranscriptIndexDataManager.swift` (+ `TranscriptSearchHit`): `index(episodeUuid:podcastUuid:cues:)` transactional delete+insert+meta upsert+cap enforcement; `search(term:limit:)` FTS5 prefix MATCH, `bm25()` rank, `snippet()`; `isIndexed(episodeUuid:)`; `removeAll()`. Single isolated `SQLRequest` function with justification comment. Expose `DataManager.sharedManager.transcriptIndex`.
- **Create** `podcasts/Transcripts/TranscriptSearchIndexer.swift` (cue text extraction via characterRange, merge adjacent cues <~40 chars, dedupe via `TranscriptIndexMeta`); hook = `TranscriptManager.loadTranscript()` success path, fire-and-forget, flag-gated. **Eviction**: LRU by indexedDate, caps 500 episodes AND 50 MB. No download-triggered indexing in v1 (documented).
- **Search UI**: `SearchResultsListView.DisplayMode.transcripts` pill (flag-gated) + `SearchResultsModel.transcriptHits` (queried off-main) + `TranscriptSearchResultRow` (artwork, episode title, bolded snippet, mm:ss). Tap → `PlaybackManager.play(episodeUuid:podcastUuid:at: hit.startTime)`; long-press → episode detail.
- Flag `transcriptSearch`. L10n: `search_transcripts_pill`, `search_transcripts_empty_title/_message`, `search_transcripts_result_at_time`. Analytics: `librarySearchTranscriptsShown`, `librarySearchTranscriptResultTapped(position, seconds)`.
- Tests: PocketCastsDataModelTests `TranscriptIndexDataManagerTests` (FTS5 create-on-migrate, index/search/snippet, eviction, diacritics); PocketCastsTests cue extraction/merging; snapshot result row. FTS5 creation failure → caught, feature self-disables via meta-table probe.

## Phase 5 — Prompted playlists (natural language → smart playlist draft)
- **Create** `podcasts/Intelligence/PlaylistPromptInterpreter.swift`: `@Generable PlaylistPromptDraft` — playedState(any/unplayed/inProgress/finished), downloadState, mediaType, starredOnly, longerThan/shorterThanMinutes, releaseWindowHours (snapped to `ReleaseDateFilterOption` buckets {24,72,168,336,744}), podcastNames (fuse-swift fuzzy → `podcastUuids` CSV + `filterAllPodcasts=false`; unmatched surfaced inline), suggestedName. Deterministic `PlaylistPromptRuleParser` fallback (pure struct: played/downloaded/media/starred keywords, "under/over N min", "today/this week/past month" → nearest bucket, quoted or fuzzy podcast names); ambiguity → all-inclusive defaults. Post-validate FM output (swap inverted duration bounds, reset contradictory groups).
- **Create** `podcasts/New Creation/Prompted/PromptedPlaylistSheetView.swift` + `PromptedPlaylistViewModel.swift` (prompt field, example chips, "uses on-device intelligence" footnote, fallback notice when FM unavailable).
- **Modify** `NewPlaylistViewController` (near `createSmartPlaylist()` :313): flag-gated "Describe your playlist" entry → sheet → apply draft over `PlaylistManager.createNewPlaylist()` → push **new** `PlaylistPreviewViewController(prefilled:)` (`.creation` mode consumes prefilled draft; set transient `*SmartRuleApplied` flags so rule chips render enabled). Saving stays exclusively `viewModel.saveFilter()` — never auto-save; resulting EpisodeFilter syncs via existing protobuf; prompt text never persisted.
- Flag `promptedPlaylists`. L10n: `prompted_playlist_entry_button/_sheet_title/_placeholder/_generate/_fallback_notice/_unmatched_podcasts`. Analytics: `promptedPlaylistShown`, `promptedPlaylistGenerated(used_fm, rules_count)`, `promptedPlaylistGenerationFailed`.
- Tests (PocketCastsTests): table-driven `PlaylistPromptRuleParserTests` (phrase → expected EpisodeFilter fields); draft application incl. fuzzy matching fixtures; FM path via mock provider.
- NOTE (session): coordinate with the Custom Smart Playlists plan (#22) — both touch the creation flow; land B5 first, then #22, then this phase reuses whatever the query-builder UI becomes.

## Phase 6 — People credits + timed episode extras
- **Timed extras**: decode `url`/`img` on `PodcastIndexChapter`; add `url` (accept `href` alias via CodingKeys) + `image` to `Episode.Metadata.EpisodeChapter`; pass validated urls through Podlove + PodcastIndex parsers in `PodcastChapterParser` (hoist shared `isValidUrl`). Existing player/chapter-cell link UI lights up — zero UI changes. (`GeneratedChapter` url = backend-optional, documented; chapter `img` artwork fetch = follow-up.)
- **Credits**: add `persons: [Person]?` (`Person{name, role?, group?, img?, href?}`) to `Episode.Metadata` (optional → no decode regression); parse `<podcast:person>` in `FeedParser` (channel + item level) and emit via `LocalFeedShowInfo`. **Create** `podcasts/Episode/Credits/EpisodeCreditsView.swift` + ViewModel — horizontal chips (avatar-or-initials via Kingfisher, name, role), embedded on episode detail via Phase-2 container pattern; self-hides when empty. Tap → `SearchResultsViewController.startExternalSearch(term: person.name)` (new method).
- **Data honesty**: local-feed podcasts with `<podcast:person>` show credits immediately; server-refreshed podcasts show nothing until the cache server adds `persons` — document expected shape in `docs/ServerAPISurface.md` (ServerBackendSpec was deleted by program decision #59).
- Flag `episodeCredits` (credits UI only). L10n: `episode_credits_title`, `episode_credits_find_more`. Analytics: `episodeDetailCreditsShown`, `episodeDetailCreditTapped`.
- Tests: PocketCastsServerTests `FeedParserTests` (person variants, channel vs item, missing attrs) + LocalFeedShowInfo output; PocketCastsDataModelTests Metadata decode fixtures (with/without persons; chapter url/href/img); PocketCastsTests parser url passthrough/validation; snapshot credits card.

## Phase 7 — Deferral doc + docs sweep
- **Create `docs/DeferredFeatures.md`** (house style): (1) this round's scope + flags; (2) **Deferred: Daily briefing / highlights feed** — concept, why deferred, primitives it would build on (`OnDeviceIntelligence`, `loadEpisodeSummary`, `TranscriptIndexDataManager`, `HighlightEnricher`), revisit criteria, standing constraints; (3) smaller cut lines: transcript Q&A chat (user-cut), transcript-view citation changes (user-cut), on-device transcription (user-skipped — NOTE: actually queued as its own plan in plans/), download-triggered background indexing, chapter img artwork, generated-chapter urls.
- **Update** `docs/FeatureFlagAudit.md` (final sweep) + verify ServerAPISurface additions from Phases 2/6.

## Verification

- `mise run build:staging`; `mise run test:staging` with ONLY_TESTING per target; SnapshotTests with `SNAPSHOT_TESTING_RECORD=all` first run.
- `mise run generate:code` → zero diff on Strings+Generated.swift; `mise run generate:filesync-proto` if Phase 3 proto landed.
- Manual QA script: (1) chapter-less episode → generated chapters + warning header; (2) summary card renders, takeaway tap seeks live episode and cold-loads others, airplane mode falls back to key moments; (3) shelf bookmark on generated-transcript episode → excerpt/title within seconds, quote-card share, rename-before-enrichment race; (4) view two transcripts → search → transcripts pill → tap seeks correct episode/time; upgrade-install to prove migrations; (5) "unplayed episodes under 30 minutes from <podcast> this week" → preview chips + episodes correct → save; Apple-Intelligence-off device uses fallback parser; (6) local-feed podcast with `<podcast:person>` + PodcastIndex chapters with `url` → credits card + chapter link button.
