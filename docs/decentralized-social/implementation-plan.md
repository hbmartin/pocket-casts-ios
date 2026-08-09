# Decentralized Social for Pocket Casts — Implementation Plan (AT Protocol)

Status: Draft for review · Target protocol: **AT Protocol (atproto)** · Identity: **Bluesky accounts (BYO)**

## 1. Goals, principles, and scope

We are adding a **listener-centric** social layer to Pocket Casts built on the AT Protocol, using
the listener's own atproto (Bluesky) identity and repository. Social data lives in each user's PDS;
Pocket Casts runs an **indexer/AppView** and (in Phase 2) a **moderation labeler**. Nothing about a
podcast's own feed is required — features work across every podcast a user subscribes to.

### Non-negotiable principles

1. **No automatic posting, ever.** Every network write (star, listen-share, comment) is the direct
   result of an explicit user action. There is no passive scrobbler and no background broadcaster.
   Sharing is always a deliberate choice, disclosed at the moment it happens.
2. **No Pocket Casts account required.** The atproto **DID is the identity**. Users sign in with an
   existing Bluesky account. Social features must work for a user who has never created (or has signed
   out of) a Pocket Casts account.
3. **Fewest possible clicks to sign in.** Handle entry → system auth sheet → done.
4. **Least-privilege access.** Request granular OAuth scopes limited to our own record collections.
5. **Data portability.** All user content is standard atproto records in the user's own repo; the
   Pocket Casts index is a replaceable convenience, not a silo.

### Phasing

| Phase | Scope | New infra |
|-------|-------|-----------|
| **1 — Identity + follow graph + shared listens** | OAuth sign-in; reuse the user's existing `app.bsky.graph.follow` graph; a "Following" activity feed of episodes friends explicitly shared/starred | 1 indexer/AppView |
| **2 — Comments + timestamped comments + moderation** | Episode comments, optional millisecond `temporalSpan`, threaded replies; report/block; Ozone labeler | + 1 Ozone labeler |
| **3 (optional) — Interop + discovery** | Propose schemas to `lexicon-community`; custom discovery feeds; cross-app read | — |

This document specifies Phases 1–2 in full and sketches Phase 3.

---

## 2. Architecture overview

```
        ┌─────────────────────┐        OAuth (PAR+PKCE+DPoP)        ┌──────────────────┐
        │  Pocket Casts iOS    │ ─────────────────────────────────▶ │  User's PDS       │
        │  (Petrel client)     │   write: star / listen / comment   │  (bsky.social or  │
        │                      │ ◀───────────────────────────────── │   self-hosted)    │
        └──────────┬───────────┘        read own records            └────────┬─────────┘
                   │                                                          │
       read feeds/activity (XRPC)                                            │ firehose
                   │                                                          ▼
        ┌──────────▼───────────┐        Jetstream (filtered)        ┌──────────────────┐
        │  Pocket Casts AppView │ ◀──────────────────────────────── │  Relay / Jetstream│
        │  - firehose consumer  │   com.pocketcasts.social.* +      │  (public infra)   │
        │  - Postgres index     │   app.bsky.graph.follow            └──────────────────┘
        │  - XRPC query API     │
        │  - episode resolver   │        (Phase 2) label queries     ┌──────────────────┐
        └──────────┬───────────┘ ─────────────────────────────────▶ │ Ozone labeler +   │
                   │                                                 │ Bluesky mod labels│
      hydrate podcast/episode metadata                               └──────────────────┘
                   ▼
        ┌──────────────────────┐
        │ Podcast Index / PC API│  (resolve podcast:guid ↔ feed ↔ episode)
        └──────────────────────┘
```

**What we run:** the AppView (Phase 1) and an Ozone labeler (Phase 2).
**What we do not run:** relay, firehose, or PDS. BYO-Bluesky users keep their data on their existing PDS.

---

## 3. Identity, authentication, and "sign in with Bluesky"

### 3.1 Library choice

**Use [Petrel](https://github.com/joshlacal/Petrel) as the primary dependency.** Rationale:

- Provides **public-client OAuth (PAR + PKCE + DPoP)** — the exact native/mobile flow atproto requires.
  DPoP token binding and refresh are handled for us; this is the single hardest piece to hand-roll.
- Generates strongly-typed Swift from lexicons, and supports **overlay packages** so we can generate our
  own `com.pocketcasts.social.*` namespace *without forking* Petrel's core `app.bsky.*` / `com.atproto.*`.
- Swift 6, iOS 18+. Pocket Casts already targets **iOS 26.0** (`config/PocketCasts.base.xcconfig`), so the
  floor is a non-issue, and `AuthenticationServices` is already linked.

[ATProtoKit](https://github.com/MasterJ93/ATProtoKit) (MIT) is a useful **secondary reference** for
RichText/facet parsing and identifier validation, but its OAuth lives in a separate, explicitly
un-audited `ATOAuthKit` and is not production-ready — do not depend on it for auth.

Both libraries are pre-1.0. **Isolate the dependency** behind our own protocol-based `ATProtoClient`
abstraction (see §5.1) so the concrete library can be swapped or vendored if needed. Pin exact versions.

### 3.2 OAuth flow (few-clicks)

1. Host a static **client metadata** JSON at a stable URL, e.g.
   `https://pocketcasts.com/.well-known/atproto/client-metadata.json`. This URL **is** the `client_id`.
   - `application_type: "native"`, `token_endpoint_auth_method: "none"`, `dpop_bound_access_tokens: true`,
     `grant_types: ["authorization_code","refresh_token"]`, `response_types: ["code"]`.
   - `redirect_uris`: an **iOS Universal Link** (preferred, smoothest return), e.g.
     `https://pocketcasts.com/oauth/callback`; register the associated-domains entitlement. A custom
     scheme is the fallback.
   - `scope`: see §3.3.
2. In-app: user taps **"Connect Bluesky"**, types their handle once (pre-fill/paste supported).
3. Petrel resolves the handle → DID → PDS, performs PAR, and opens the PDS auth page in
   **`ASWebAuthenticationSession`** (ephemeral, respects the system browser session — often one tap to
   approve if already logged into Bluesky in Safari).
4. On approval the Universal Link returns to the app; Petrel completes the code exchange (PKCE) and
   stores DPoP-bound tokens. **Persist the refresh token in the Keychain**; silent refresh thereafter.

Net UX: **handle entry + one approval tap.** No Pocket Casts account touched.

### 3.3 Scopes (least privilege)

Request only:

```
atproto
repo:com.pocketcasts.social.star
repo:com.pocketcasts.social.listen
repo:com.pocketcasts.social.comment
rpc:com.pocketcasts.social.*?aud=<appview-did>
blob:image/*
```

- `repo:<collection>` grants create/update/delete on *only* our collections — nothing else in the repo.
- `app.bsky.graph.follow` is **read-only** for us; we read the follow graph via the AppView/firehose and
  never write follows on the user's behalf. (If in-app "follow" is added later, add `repo:app.bsky.graph.follow`
  and gate it behind an explicit action.)
- Consent screen will read, in effect, "Pocket Casts can post podcast stars, listens, and comments — and
  nothing else." This is a materially better trust posture than legacy app passwords.

### 3.4 Session & identity model in the app

- Store: `did`, `handle` (cache, may change), `pdsUrl`, DPoP keypair + tokens (Keychain).
- The DID is the durable key; resolve handle → DID at sign-in and treat DID as canonical everywhere.
- The atproto session is **independent** of any Pocket Casts sync session. A user can be in exactly one
  of four states: (a) no accounts, (b) PC account only, (c) Bluesky only, (d) both. Social features
  depend solely on (c)/(d).

---

## 4. Schema specification (Lexicons)

Namespace: **`com.pocketcasts.social.*`** (reverse-DNS of a domain we control, required for NSID
resolution via DNS/well-known). Design the records to be **app-neutral** so they can later be proposed to
`lexicon-community` under a shared podcast namespace; note that changing the NSID later is a migration.

We **reuse** existing lexicons where they fit:
- **Follows:** `app.bsky.graph.follow` (no new lexicon).
- **Profiles/handles:** `app.bsky.actor.profile`.
- **Rich text in comments:** `app.bsky.richtext.facet`.

### 4.1 The episode-identity problem → `episodeRef`

There is no universal podcast episode ID. We define a **composite reference** and resolve/canonicalize it
in the AppView. Precedence for matching: `podcastGuid` + `episodeGuid` → `feedUrl` + `episodeGuid` →
`enclosureUrlHash`.

`com.pocketcasts.social.defs` (shared defs):

```json
{
  "lexicon": 1,
  "id": "com.pocketcasts.social.defs",
  "defs": {
    "episodeRef": {
      "type": "object",
      "description": "Portable, app-neutral reference to a podcast episode.",
      "required": ["episodeGuid"],
      "properties": {
        "podcastGuid":  { "type": "string", "description": "RSS <podcast:guid> (channel-level), preferred." },
        "episodeGuid":  { "type": "string", "description": "RSS <guid> of the item." },
        "feedUrl":      { "type": "string", "format": "uri", "description": "Canonical feed URL (disambiguation/fallback)." },
        "enclosureUrl": { "type": "string", "format": "uri", "description": "Media URL (fallback identity)." },
        "title":        { "type": "string", "maxGraphemes": 300, "description": "Denormalized for display and when GUIDs are missing." },
        "podcastTitle": { "type": "string", "maxGraphemes": 300 }
      }
    },
    "temporalSpan": {
      "type": "object",
      "description": "A time range within the episode audio, in milliseconds from start.",
      "required": ["startMs"],
      "properties": {
        "startMs": { "type": "integer", "minimum": 0 },
        "endMs":   { "type": "integer", "minimum": 0 }
      }
    }
  }
}
```

### 4.2 `com.pocketcasts.social.star` — shared star/endorsement (Phase 1)

Created **only** when a user explicitly shares a star (not on every local star). Analogous to a like.

```json
{
  "lexicon": 1,
  "id": "com.pocketcasts.social.star",
  "defs": {
    "main": {
      "type": "record",
      "key": "tid",
      "record": {
        "type": "object",
        "required": ["subject", "createdAt"],
        "properties": {
          "subject":   { "type": "ref", "ref": "com.pocketcasts.social.defs#episodeRef" },
          "note":      { "type": "string", "maxGraphemes": 300, "description": "Optional user blurb." },
          "createdAt": { "type": "string", "format": "datetime" }
        }
      }
    }
  }
}
```

### 4.3 `com.pocketcasts.social.listen` — shared listen (Phase 1)

The "podcast to a followers feed" primitive. **Explicitly opt-in per share** (or via a clearly-disclosed,
default-OFF "share my listens" setting). Not a passive scrobble.

```json
{
  "lexicon": 1,
  "id": "com.pocketcasts.social.listen",
  "defs": {
    "main": {
      "type": "record",
      "key": "tid",
      "record": {
        "type": "object",
        "required": ["subject", "createdAt"],
        "properties": {
          "subject":         { "type": "ref", "ref": "com.pocketcasts.social.defs#episodeRef" },
          "completed":       { "type": "boolean", "description": "Whether the user finished the episode." },
          "positionSeconds": { "type": "integer", "minimum": 0, "description": "Optional progress at time of sharing." },
          "durationSeconds": { "type": "integer", "minimum": 0 },
          "createdAt":       { "type": "string", "format": "datetime" }
        }
      }
    }
  }
}
```

### 4.4 `com.pocketcasts.social.comment` — comment, optionally timestamped (Phase 2)

```json
{
  "lexicon": 1,
  "id": "com.pocketcasts.social.comment",
  "defs": {
    "main": {
      "type": "record",
      "key": "tid",
      "record": {
        "type": "object",
        "required": ["subject", "text", "createdAt"],
        "properties": {
          "subject":      { "type": "ref", "ref": "com.pocketcasts.social.defs#episodeRef" },
          "text":         { "type": "string", "maxGraphemes": 3000, "maxLength": 30000 },
          "facets":       { "type": "array", "items": { "type": "ref", "ref": "app.bsky.richtext.facet" } },
          "temporalSpan": { "type": "ref", "ref": "com.pocketcasts.social.defs#temporalSpan",
                            "description": "Present ⇒ a timestamped comment anchored to a moment in the audio." },
          "reply":        { "type": "ref", "ref": "com.pocketcasts.social.comment#replyRef",
                            "description": "Present ⇒ a threaded reply." },
          "createdAt":    { "type": "string", "format": "datetime" }
        }
      }
    },
    "replyRef": {
      "type": "object",
      "required": ["root", "parent"],
      "properties": {
        "root":   { "type": "ref", "ref": "com.atproto.repo.strongRef" },
        "parent": { "type": "ref", "ref": "com.atproto.repo.strongRef" }
      }
    }
  }
}
```

Design notes: we reuse `com.atproto.repo.strongRef` (uri+cid) for threading and `app.bsky.richtext.facet`
for links/mentions, so existing tooling understands the rich text. `temporalSpan` mirrors the
`pub.layers`/Media-Fragments `t=start,end` convention but stays self-contained.

### 4.5 XRPC query methods served by the AppView

These are lexicons too (`type: "query"`); the app calls them via `rpc:` scope.

- `com.pocketcasts.social.getFollowingFeed` — `(actor DID, cursor, limit)` → reverse-chron activity
  (stars/listens/comments) authored by accounts the actor follows. Powers the Phase-1 "Following" tab.
- `com.pocketcasts.social.getEpisodeActivity` — `(episodeRef fields, cursor)` → counts + recent
  stars/listens/comments for one episode. Powers per-episode social affordances.
- `com.pocketcasts.social.getComments` — `(episodeRef fields, sort, cursor)` → threaded comment tree,
  with timestamped comments flagged for timeline rendering. Phase 2.

Responses are **hydrated** by the AppView (author profile, podcast/episode display metadata, viewer
mute/label state) so the client makes one call per view.

---

## 5. Client (iOS app) work

### 5.1 New module: `PocketCastsSocial`

A new SwiftPM module under `Modules/`, depending on Petrel (+ generated overlay). Expose a narrow,
testable surface and keep Petrel types out of the rest of the app:

```
protocol ATProtoClient {
  // auth
  func startLogin(handle: String) async throws -> AuthSession   // ASWebAuthenticationSession under the hood
  func restoreSession() async throws -> AuthSession?
  func signOut() async
  // writes (all user-initiated)
  func putStar(_ ref: EpisodeRef, note: String?) async throws -> RecordRef
  func putListen(_ ref: EpisodeRef, progress: Progress?) async throws -> RecordRef
  func putComment(_ c: NewComment) async throws -> RecordRef
  func delete(_ ref: RecordRef) async throws
  // reads (via AppView)
  func followingFeed(cursor: String?) async throws -> Page<ActivityItem>
  func episodeActivity(_ ref: EpisodeRef) async throws -> EpisodeActivity
  func comments(_ ref: EpisodeRef, sort: CommentSort, cursor: String?) async throws -> Page<CommentNode>
}
```

### 5.2 Episode reference construction

- **Add identity fields to the data model.** Today `Episode`/`Podcast` carry only Pocket-Casts `uuid`,
  and `Episode.downloadUrl` (`Modules/.../Model/Episode.swift`, `Podcast.swift`). Extend the feed
  parser + models to persist **`episodeGuid`** (RSS `<guid>`) and **`podcastGuid`** (`<podcast:guid>`),
  falling back to a normalized `enclosureUrl` hash. This is the load-bearing change for all social
  features and should land first, behind the flag, even before UI.
- Build `EpisodeRef` from these fields at share/read time.

### 5.3 Sign-in UI

- A single "Connect Bluesky" entry point in Profile/Settings and inline where social features appear.
- Handle field + system auth sheet (§3.2). Clear disclosure of scopes. Sign-out clears Keychain.

### 5.4 Sharing integration (reuse existing pipeline — user-initiated only)

Pocket Casts already has a rich share system (`podcasts/Sharing/`, `SharingModal.Option` incl.
`.currentPosition(Episode, TimeInterval)`, `.bookmark`, `.clip`). Add **new destinations**, never
automatic:

- `ShareDestination` for **"Share to Bluesky followers"** →
  - from an episode / star action → `putStar` or `putListen`
  - from a timestamp / bookmark context (`.currentPosition`, `.bookmark`) → `putComment` with
    `temporalSpan` prefilled from the current playback position.
- **Starring stays local by default.** Publishing a star record is either a distinct "share this star"
  tap or governed by an explicit, default-OFF setting "Share my stars with followers," disclosed on
  toggle. No star, listen, or comment is ever written without a user action.

### 5.5 Reading UIs

- **Phase 1:** a "Following" feed (new tab or Profile section) rendering `getFollowingFeed`; per-episode
  "N friends listened / starred" affordance on the episode screen.
- **Phase 2:** a comments view on the episode screen; **timestamped comments** rendered against the
  player timeline (reuse chapter/transcript timeline patterns — `PlayerChapterCell`, transcript VCs).
  Tapping a timestamped comment seeks the player (we already have precise seek APIs).
- **Moderation UI (Phase 2, required):** report, block/mute, hide — see §7.

### 5.6 Cross-cutting

- Feature-flag the whole surface (Firebase/remote config as used elsewhere) for staged rollout.
- Offline: queue writes, reconcile on reconnect; reads are cache-first.
- Localization via SwiftGen `L10n`; theming via `AppTheme.color(for:theme:)` per repo conventions.
- Analytics: privacy-preserving; never log listening content off-device without consent.

---

## 6. Server (AppView / indexer) work

A standalone service (not in this repo). Reference: the
[feed-generator starter kit](https://github.com/bluesky-social/feed-generator) and lexicon-driven
AppView patterns (e.g. [HappyView](https://github.com/gamesgamesgamesgamesgames/happyview)).

### 6.1 Ingestion

- Subscribe to **Jetstream** filtered to `wantedCollections`:
  `com.pocketcasts.social.*` and `app.bsky.graph.follow`.
- Track cursor for resumable consumption; backfill on gaps.
- **Phase 1 scale target (~1k users):** this is Regime A — filter to relevant records; a single small
  VM handles it. (See cost note in §9.)

### 6.2 Storage (Postgres)

Core tables: `accounts(did, handle, pds, profile_cache)`, `follows(subject_did, object_did)` (mirror of
bsky follows for feed fan-out), `episode(canonical_id, podcast_guid, episode_guid, feed_url,
enclosure_hash, title, …)`, `star`, `listen`, `comment(uri, cid, author_did, canonical_episode_id,
text, temporal_start_ms, temporal_end_ms, reply_root, reply_parent, created_at)`, plus `labels`
(Phase 2). Index by `canonical_episode_id` and `author_did`. GC raw activity past a retention window
(e.g. 90 days) while keeping comments durable.

### 6.3 Episode canonicalization service

Resolve incoming `episodeRef`s to a `canonical_episode_id` using the precedence in §4.1, enriched via the
**Podcast Index API** and/or the Pocket Casts content API (podcast:guid ↔ feed ↔ episode). This is where
the "same episode across clients" guarantee is enforced; invest in it early and test it hard.

### 6.4 XRPC query API + hydration

Implement the three `com.pocketcasts.social.get*` methods (§4.5). Verify DPoP-bound tokens and `rpc:`
scope/audience. Hydrate author profiles and episode metadata; apply viewer mutes/labels before returning.

### 6.5 Ops

- Deployment: container on a small VM/managed platform; managed Postgres.
- Health/metrics, cursor lag alerting, rate limiting on write-adjacent and query endpoints.
- Publish the lexicons for resolution (DNS `_lexicon` TXT + `.well-known`) so third parties can interop.

---

## 7. Moderation, safety, and App Store compliance (Phase 2 — gating for comments)

Surfacing user-generated comments makes Apple hold **us** responsible for the content
(App Store Guideline 1.2). Comments **cannot ship** without all of:

- **Report** action on every comment/user (in-app reporting flow → our Ozone queue).
- **Block/mute** users; **hide** individual comments locally.
- A **filter mechanism**: subscribe to **Bluesky's moderation labels** (inherit network takedowns for
  free) *and* run our own **[Ozone](https://github.com/bluesky-social/ozone) labeler** for
  podcast-specific policy — the stackable model. The AppView applies labels before serving.
- Respect account lifecycle: do not redistribute content from `deleted`/`takendown`/`suspended` accounts.
- A published content policy + a moderation runbook (human review time is the real cost here).

Phase 1 (stars/listens among people you follow) carries far less risk and does not require the labeler,
but still needs block/mute and a report path for shared content.

---

## 8. Privacy & consent

- All sharing is opt-in and user-initiated (§1). Listening data is sensitive; defaults are OFF.
- Clear disclosure at sign-in (what scopes mean) and at each share (what becomes public and where).
- Granular controls: per-share choice, plus global toggles; easy sign-out and "delete my social records"
  (delete records from the user's repo — they own them).
- GDPR/CCPA: because records live in the user's PDS, deletion is largely user-controlled; the AppView must
  honor deletions from the firehose and purge its index.
- Update the App Privacy nutrition labels and privacy policy.

---

## 9. Effort, cost, milestones

**Hosting cost (≈1k users, Phase 1):** ~$30–100/month (one small VM + small Postgres + filtered
Jetstream). Negligible vs. engineering/ops time. Cost scales with *network coverage chosen*, not user
count. Phase 2 adds a comparable-sized Ozone box; its dominant cost is human moderation.

**Engineering milestones:**

1. **M0 — Foundations:** `episodeGuid`/`podcastGuid` in the data model + parser; `PocketCastsSocial`
   module skeleton; Petrel integration + overlay lexicon codegen; client-metadata JSON hosted.
2. **M1 — Auth:** OAuth sign-in end-to-end (Universal Link, Keychain, silent refresh); sign-out.
3. **M2 — AppView v1:** Jetstream consumer, episode canonicalization, Postgres, `getFollowingFeed`.
4. **M3 — Phase 1 UX:** star/listen share destinations (user-initiated), Following feed, per-episode
   "friends" affordance. Ship behind flag to internal/beta.
5. **M4 — Comments backend:** `comment` lexicon, `getComments`/`getEpisodeActivity`, threading.
6. **M5 — Comments UX + timestamps:** comment UI, timeline-anchored timestamped comments, seek-on-tap.
7. **M6 — Moderation:** Ozone labeler, Bluesky label subscription, report/block/hide, policy + runbook.
   **Gate GA of comments on this.**
8. **M7 — Interop (optional):** propose schemas to `lexicon-community`; discovery feeds.

---

## 10. Open questions / risks

1. **Namespace:** ship under app-owned `com.pocketcasts.social.*` (fast, we control it) vs. push for a
   neutral community namespace first (better interop, slower, coordination). Recommendation: ship
   app-owned, design neutral, propose to community in Phase 3 — accept a possible NSID migration.
2. **Petrel/ATProtoKit are pre-1.0.** Mitigate via the `ATProtoClient` abstraction, pinned versions, and
   willingness to vendor the OAuth/DPoP path.
3. **iOS-native atproto OAuth** has historically had sharp edges (DPoP refresh, PAR). Prototype M1 early
   and in isolation; it is the riskiest single piece.
4. **Episode identity accuracy** determines whether comments/activity land on the right episode across
   apps. Needs real-world testing against messy feeds (missing/duplicate GUIDs, mutating enclosure URLs).
5. **Non-Bluesky users are excluded** in the BYO model. Decide consciously whether Phase 3 provisions
   identities (running a PDS = more infra) or social stays Bluesky-gated.
6. **Coordination:** align the `listen` schema with teal.fm and the `episodeRef`/`comment` schemas with
   Podcast Index folks to avoid fragmenting the nascent podcast-on-atproto space.
```
