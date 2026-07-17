# Domain Glossary

Canonical vocabulary for this fork's transcript, playback and intelligence features.
Terms here are the ubiquitous language — code, docs and PRs should use them exactly.

## Transcript search

- **Transcript Corpus** — the single unified full-text index of transcript segments
  across the library. One corpus, two *sources* (below). Device-local, never syncs.
- **Provided transcript** — a transcript the podcast's feed offers (VTT/SRT/JSON),
  fetched from the publisher. Re-fetchable at any time, so its index rows are
  evictable under the corpus byte cap.
- **Generated transcript** — a transcript produced by this app's transcription
  pipeline (on-device engine or a user-configured remote provider). Backed by a VTT
  artifact on the device; its index rows are never evicted. Generated transcripts
  of Eligible episodes are contributed to the backend.
- **Segment** — the unit of the corpus: a sentence-ish run of transcript text with
  a start time (and, when known, end time and speaker), belonging to one episode
  and one source.
- **Transcription record** — the per-episode pipeline-state row (status, engine,
  provider, artifact path). Pipeline state, not index data: it survives index
  rebuilds and lives in its own table.

- **Highlight** — a Bookmark enriched with a transcript excerpt and end time;
  the user-curated "hot segment" of an episode. Enrichment is write-once and
  best-effort: no transcript means a plain bookmark.
- **Quote Link** — a timestamped share link whose payload carries the transcript
  sentence(s) at the timestamp: in the share text and in the URL's `q`
  parameter. The quote is display/deep-link data only — the canonical
  transcript is unchanged, and a link without a resolvable quote is exactly a
  plain timestamped link.

## Transcript crowdsourcing

- **Contribution** — an upload of a Generated transcript's content, together with
  a fingerprint of the exact audio it was cut from, so other listeners of the
  same episode can use it with correct timing despite dynamic ad insertion.
  Only Generated transcripts are contributed; the server already has everything
  else.
- **Sighting** — a report that an episode has a Provided transcript at a publisher
  URL (with format and language). No content leaves the device; a Sighting asks
  the server to fetch the transcript itself from the publisher.
- **Eligible episode** — an episode whose transcripts may be contributed or
  sighted: every episode except those of private local feeds. Episodes outside
  the Pocket Casts catalog are eligible — their deterministic feed-derived
  identity is shared by all subscribers of the same feed. A transcript URL
  carrying credentials or access tokens is never sighted.

## Playback intelligence

- **Catch Me Up** — an on-device summary of an in-progress episode covering only
  the portion already played (start → playhead), for resuming after time away.
  Distinct from an *episode summary*, which covers the whole episode.
- **Effects Profile** — a named disposition of the audio-effects chain (trim
  silence, voice boost) that can be swapped at runtime without rewriting the
  user's persisted tuning. "Music profile" suspends trim and boost during
  music-dominant segments.

## Feedback

- **Feedback Report** — a user-initiated report from a TestFlight/debug build
  (shake gesture): message plus attached diagnostics (device/app info, log tail,
  bitdrift session ID), sent to this fork's own feedback endpoint.

## Social

- **Join** — the one-time opt-in that turns a private account into a public social
  identity: claim a handle and accept the public-identity terms. Before Join an account
  has no handle, no public footprint and no ability to act socially; everything behaves
  exactly as it does today. Join requires a logged-in synced account.
- **Handle** — the immutable, permanent `@name` that addresses a joined account
  (`pca.st/u/<handle>`). Unique, lowercase alphanumeric + `_`, 3–30 chars. Users can
  never rename it; the canonical stored identity is still the server `uuid`, so follows,
  mentions and attribution reference the `uuid` and render the handle at read time.
- **Tombstone** — the permanent retirement of a handle after account deletion: the
  profile PII is erased but the handle string is kept as a non-PII reservation, so the
  handle is never reissued and old mentions/links can't be hijacked.
- **Social Profile** — the server-hosted public identity keyed to the account `uuid`:
  handle, display name, avatar, bio, and the per-field visibility settings. Distinct from
  the deprecated device-local *Share Profile*, which only seeds it on Join.
- **Visibility** — the per-field privacy tier of a profile element (avatar, bio, followed
  shows, top podcasts, stats/heatmap, history, presence): `public`, `followers-only` or
  `private`. Stored three-tier from day one; only public/private are selectable until the
  follow graph unlocks `followers-only`. Every field defaults to private.
- **Profile Link** — the shareable address of a Social Profile: the fork backend's
  public base URL + `/u/<handle>` on the web, and `thcast://profile/<handle>` for
  app-to-app opening. The `pca.st/u/<handle>` form in early documents is upstream's
  domain and is aspirational only — this fork cannot serve or deep-link it.
- **Block / Mute / Report** — the day-one safety primitives. *Block* is mutual
  invisibility (no view, follow, mention or interaction either way). *Mute* is a one-way
  hide; the muted party is not notified. *Report* files a flag into the triage queue.
- **Triage Queue** — the single `moderation_reports` queue that receives both community
  flags and automated pre-filter hits (text classifier, image scan), distinguished by
  `source`. Worked manually at launch. See `docs/SocialModeration.md`.
- **Listen-gate** — the pre-existing anti-spam rule (you may only rate a podcast after
  listening to ≥1–2 episodes) reused to gate reviews, comments and reactions.
- **Review** — a podcast's star rating plus optional written text. The stars remain the
  anonymous account-level primitive; the *text* requires a joined account and is publicly
  attributed (@handle, display name, date). One per person per podcast; editable,
  deletable, pre-filtered, reportable, and erased with the profile.
- **Reaction** — an account-recorded emoji (❤️ 😂 🤯 👏 🔥) on an episode, one per person,
  listen-gated. Publicly displayed as aggregate counts only; attribution surfaces only for
  joined accounts once feeds exist.
- **Shared Item** — an episode sent person-to-person, with an optional note and a
  listen-from timestamp. Sender and recipient must both be joined; a blocked or unknown
  recipient is indistinguishable at send time. Sent items die with the sender's profile.
- **Inbox** — the recipient-side list of Shared Items: unread count, marked read on open,
  deletable. Reacting to a received item waits until senders can see reactions.
