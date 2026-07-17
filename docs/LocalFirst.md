# Local-First Operation — Refresh Sources & Signed-Out Behavior

**Last updated:** 2026-07-12 (program Track A, items 1/2/6)

The fork's strategic direction: fully functional with no account — on-device RSS refresh, local
storage, file-based device sync (FileSync, un-gated) — with Pocket Casts server sync as an
optional layer when signed in.

## The `refreshSource` partition

Every podcast row carries a persisted `refreshSource` (`Podcast.feedRefreshSource`, migration 76):

| Value | Refresh pipeline | Sync to account | Episode identity |
|---|---|---|---|
| `.server` | Pocket Casts refresh servers (`ServerFeedRefreshProvider`) | yes, when signed in | server-canonical UUIDs |
| `.localFeed` | on-device fetch + parse (`LocalFeedRefreshProvider`) | never (`syncStatus` pinned `.synced`) | deterministic hash UUIDs (`LocalFeedIdentity`) — or server-canonical when the row flipped after a server-seeded add |

`CompositeFeedRefreshProvider` partitions each refresh per podcast and merges the responses; the
entire downstream pipeline (`RefreshOperation`, notifications, autoplay, widgets) is shared.

## The subscribe-time decision (sticky)

`ServerPodcastManager.effectiveRefreshSource(requested:subscribe:isLoggedIn:feedUrlPresent:)` —
pure, unit-tested (`SubscribeRefreshSourcePolicyTests`):

- **Signed-out subscribe of a server-sourced podcast (with a feed URL) → `.localFeed`.** The row
  keeps its canonical UUID and server-seeded episode catalog; one immediate on-device refresh
  populates the offline show-notes cache.
- Signed-in subscribes, non-subscribe adds (Up Next lookups, previews), and rows without a feed
  URL stay `.server` (`.localFeed` without a URL never refreshes).
- Explicit `.localFeed` requests (add-by-URL/OPML through the local-ingest pipeline) are never
  overridden.

**Sticky:** `refreshSource` is decided once, at subscribe time, and never changes on sign-in or
sign-out. There is deliberately no transition code — existing server rows keep refreshing via the
server even when signed out (the refresh endpoints are public; login only gates the post-refresh
sync backfill), and local rows never join account sync (their identity is meaningless to the
server or was never announced to it).

## Duplication safety (`LocalFeedEpisodeMatcher`)

A `.localFeed` refresh of a podcast whose catalog carries server-canonical UUIDs would re-mint
every episode under hash UUIDs without reconciliation. The matcher (pure; no I/O) resolves each
parsed item against the existing catalog with precedence:

1. deterministic hash UUID already in the database,
2. exact enclosure URL == `downloadUrl`,
3. normalized title + published date (UTC day granularity) — logged when it fires.

Matched items are skipped (and their show-info cache entries re-keyed to the stored UUID);
unmatched items ingest under their hash UUID. **Documented limitation:** an item with no guid AND
a changed enclosure URL AND a changed title cannot be correlated and will duplicate.

## Signed-out route coverage

Every subscribe route works with no account:

- **Search/Discover/Explore** → `subscribe(to:)` → `addFromJson` → the policy above.
- **OPML import** → server resolution first; feeds the catalog cannot resolve fall back to
  on-device ingest (regardless of the local-ingest toggle, which keeps its signed-in semantics).
- **`thcast://subscribe/<url>`** → catalog resolution first; on failure while signed out, the feed
  is ingested on device.
- **Local-ingest toggle on** (`Settings.localFeedIngestEnabled`): add-by-URL and OPML skip the
  server entirely.

## Signed-out degradations (by design)

- No AI (generated) chapters or transcripts for `.localFeed` podcasts — those are produced by the
  Pocket Casts pipeline for server-known episodes only. Feed-authored chapters
  (`<podcast:chapters>`), transcripts (`<podcast:transcript>`), and embedded chapters all work.
- Ratings submission prompts login; recommendations no-op.
- Cross-device continuity for signed-out libraries comes from FileSync (folder-based), not
  account sync.
