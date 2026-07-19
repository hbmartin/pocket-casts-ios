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
  `private`. Stored three-tier from day one; all three tiers became selectable when the
  follow graph shipped. Every field defaults to private.
- **Profile Link** — the shareable address of a Social Profile: the fork backend's
  public base URL + `/u/<handle>` on the web, and `thcast://profile/<handle>` for
  app-to-app opening. The `pca.st/u/<handle>` form in early documents is upstream's
  domain and is aspirational only — this fork cannot serve or deep-link it.
- **Block / Mute / Report** — the day-one safety primitives. *Block* is mutual
  invisibility (no view, follow, mention or interaction either way). *Mute* is a one-way
  hide — the muted person's items are filtered from the muter's Activity Feed; the muted
  party is not notified. *Report* files a flag into the triage queue.
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
  listen-gated. Publicly displayed as aggregate counts only; for joined accounts the
  reaction also appears attributed as a Feed Item to their followers.
- **Shared Item** — an episode sent person-to-person, with an optional note and a
  listen-from timestamp. Sender and recipient must both be joined; a blocked or unknown
  recipient is indistinguishable at send time. Sent items die with the sender's profile.
- **Inbox** — the screen for things addressed to *you*: Shared Items (unread count, marked
  read on open, deletable), pending Follow Requests (accept/decline), and Replies to your
  Comments (watermark-based unread). List-collaboration invites live in the Shared Lists
  hub. Reacting to a received item waits until senders can see reactions.
- **Follow** — the one-way graph edge between joined accounts. Open by default: following
  someone succeeds instantly and may reveal their `followers-only` fields. If the followee
  has enabled follower approval, a new follow becomes a Follow Request instead. Blocking
  severs follows in both directions; erasure deletes them.
- **Follow Request** — a follow awaiting the followee's approval (their "Approve My
  Followers" setting is on). Pending requesters see nothing extra — no followers-only
  fields, no feed items — until accepted. Surfaces in the Inbox for accept/decline.
- **Activity Feed / Feed Item** — the reverse-chronological list of followees' activity:
  joined, followed a person, followed a show, finished an episode, reviewed, reacted,
  commented. Items are derived at read time from existing records (nothing is stored
  per-item); the listening-derived kinds obey the actor's per-field Visibility for each
  viewer, and muted or blocked actors are filtered out.
- **Comment** — attributed text by a joined account on an episode, forming the episode's
  discussion tree. A *top-level* comment (posting requires having played ≥25% of the
  episode) optionally anchors to a playback timestamp; a *Reply* attaches to any comment
  (full nesting, no listen-gate). Editable only within a short grace window and only
  until replied to; text is pre-filtered and reportable. Top-level comments emit Feed
  Items; replies are conversation, not broadcast.
- **Moment** — the player-surface rendering of a timestamp-anchored top-level Comment: a
  pin on the scrubber that seeks and opens the comment's subtree. Not a separate entity —
  the episode page and the player are two lenses over one comment tree.
- **Transcript Quote** — a short excerpt of the episode's transcript attached to a
  Moment: the quote text is self-contained rendering truth (it can never break), while an
  accompanying advisory reference to the generating transcript segment enables future
  deep-linking and is allowed to rot when transcripts regenerate. Wiped with the text on
  tombstoning.
- **Group** — a member-owned room with a feed of deliberate Group Posts. One entity, two
  configurations: a *private* Group (invite-only, invisible to non-members) or a *public*
  Group (one-tap joinable, discoverable). Membership never grants follower-level
  visibility into members' listening.
- **Fandom Hub** — a public Group anchored to a podcast. Anchors are non-exclusive: any
  number of Groups may anchor to the same show, listed on its page by size.
- **Group Post** — a deliberate act of sharing into a Group: an episode, a Shared List, or
  plain text, with a note; carries threaded replies with the same semantics as Comments
  (tombstones, grace-window edit, pre-filtering, reportable, block invisibility).
- **Succession** — the public-hub lifecycle rule: when a hub owner's profile is erased,
  ownership passes to the longest-tenured remaining member (a memberless hub dies). A
  private Group instead dies with its owner, like a Shared List.
- **Tombstoned Comment** — a deleted, moderation-removed, or erasure-affected Comment:
  its text and author are wiped but its position in the tree is kept, so other people's
  replies survive. The comment-tree analogue of a tombstoned Handle.
- **Shared List** — an episode list published as a first-class server object: an owner,
  invited Collaborators who co-edit (add/remove/reorder, attributed per entry), and
  Subscribers who follow it read-only. Carries the standard three-tier Visibility;
  followers/public lists appear on the owner's profile. Dies with its owner; an erased
  collaborator's entries survive with their attribution wiped.
- **List Mirror** — the local playlist that renders a Shared List in the Playlists tab.
  Mirrors are server-derived caches, rebuilt on refresh; the owner's original playlist is
  never rebuilt — it keeps syncing as an ordinary manual playlist.
- **Materialize** — publishing a smart or custom playlist snapshots its *current results*
  into a new Shared List; the playlist itself stays personal. Live queries never share
  (a rule evaluates differently in every account).
- **Social Push** — an APNs notification for one of six directed-at-you events: follow
  request, follow approved, new follower, shared item, comment reply, list invite. All
  on by default (they are personally addressed, never broadcast); each individually
  toggleable, with the preference stored on the profile so it gates sending at the
  server across every device. Taps deep-link to the event's home surface.
- **Discoverable** — whether a joined profile appears in people search and suggestions.
  On by default (existence is already public: any profile is reachable by exact handle);
  the privacy screen's "Include me in search & suggestions" toggle turns it off. Stored
  inverted (hide flag) so an absent value means discoverable.
- **Social Proof** — the podcast-page line naming which of your followees follow this
  show. Names appear only when that person's followed-shows visibility already grants you
  their list; everyone else folds into the count. The Explore "Trending with friends" row
  is the listening-side sibling: ranked by followees' recently finished episodes under
  each actor's history visibility. Each surface reveals only what its source field
  already permits.
- **Contact Match** — finding accounts from the user's address book: an explicit action
  that salted-hashes every email and phone number per contact on device and uploads only
  the hashes. The server matches emails (accounts have no phone numbers yet; phone hashes
  are wire-ready and ignored), returns joined + Discoverable matches, stores nothing, and
  never notifies the matched person. Suggestions themselves are friends-of-followed,
  explained only as a mutual-connection count — never names — honoring the caller-own
  follow-lists rule.
