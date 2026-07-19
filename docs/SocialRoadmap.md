# Social Features Roadmap (living tracker)

Phased plan for the social program. Update the **Status** column as work lands. See
`docs/Social.md` for decisions and `docs/SocialModeration.md` for the moderation contract.

**Status legend:** `planned` · `in-progress` · `shipped` · `deferred`

## Phase 1 — Identity & lightweight sharing

| Slice | Item | Status | Notes |
|---|---|---|---|
| 1 | Identity + moderation foundation — **iOS dark scaffolding** (proto, `FeatureFlag.socialProfiles`, migration 85, models, API tasks) | shipped | PR #313. |
| 1 | Identity + moderation foundation — **backend endpoints** (`social/*`: handles + tombstone, profiles, per-field visibility, block/mute/report, triage queue, GDPR erase incl. account deletion) | shipped | `podcast-backend` branch `social/foundation-endpoints`: migration 012, handlers, routes; Go handler + e2e suites green; iOS `SocialLocalBackendE2ETests` proves the Swift↔Go wire contract against the local Docker backend. |
| 1 | **Avatar upload + CSAM/nudity scan pipeline** | deferred | Deliberately cut from the first backend slice (2026-07-16): profiles are handle+name+bio only; `SocialAvatarUploadSender` sits unused; the scan-pipeline decision returns when avatars do. HARD gate: real scan vendor integration before avatars go live publicly. |
| 1+2 | **Slice-1 UI + Slice-2 sections (merged by decision 2026-07-16)**: Join flow (CTA row + one-time announcement + terms + handle claim + privacy nudge), own profile + edit, public profile with 4 visibility-gated sections (followed shows, top podcasts, stats totals, recently played), block/report affordances, social privacy screen, `thcast://profile` deep link + backend `/u/{handle}` HTML page | shipped | Heatmap renders own-profile-only (no per-day series server-side; public heatmap deferred until a per-day sync exists). Mute UI deferred to first feed surface (ADR-0007 amendment — **fulfilled in Slice 5**, mute ships on the public profile and filters the feed). Profile Link = backend URL + thcast scheme (ADR-0008; pktc hard-replaced). |
| 3 | Stat/heatmap **share cards** (static images, @handle + Profile Link stamped when joined) | shipped | Snapshot-template pipeline; entries on Stats screen. **Year-in-Review cut from this slice (2026-07-17 decision)** — see deferred row below. |
| 3 | Written **reviews** — stars stay anonymous; TEXT requires Join, attributed; 1/user/podcast; edit/delete; pre-filtered; reportable (content-level reports); erased with profile | shipped | Server-only storage v1 (own review rides the fetch); server-side listen-gate from synced `user_episodes`. |
| 3 | Episode **reactions** (❤️😂🤯👏🔥) — account-recorded, counts-only display; one per episode (switch/clear); ≥25%-played gate | shipped | Per-account rows make Phase-2 attributed feeds migration-free. |
| — | **Year-in-Review stories** | deferred | Cut 2026-07-17: all aggregates net-new and local data approximate (cumulative time attributed to last-interaction day; this-device only). Revisit with per-day listening tracking and/or the §11 vertical story export. |
| 4 | **Send-to-friend** + shared-item inbox — both ends joined; item = episode + note (≤500, filtered) + timestamp; inbox = read/unread + delete + open-at-timestamp with a Profile-tab unread badge | shipped | *Amended 2026-07-17:* the roadmap's inbox **react** is deferred until senders can see reactions (sent-view or notifications) — same do-nothing-control reasoning as the mute deferral. Erase deletes sent items. |

## Phase 2 — Graph & discovery

| § | Item | Status | Gating decisions still open | Reuse anchor |
|---|---|---|---|---|
| 2 | Follow (asymmetric), find friends, import graph, people-you-may-know | in-progress | **Slice 5 shipped the core (2026-07-17)**; **Slice 9 shipped find-people (2026-07-18):** prefix search over joined+discoverable profiles (opt-out toggle, stored inverted), friends-of-followed suggestions with count-only copy (no names — the caller-own-lists rule holds), and contacts matching via typed salted hashes (emails matched, phone hashes wire-ready; transient, no reverse notification). Nothing left open in §2. | `SharingHelper.shareLinkToApp` |
| 3 | Activity feed, now-playing presence, milestones, "recently played by" shelf, weekly digest | in-progress | **Slice 5 shipped the feed (2026-07-17):** fan-out-on-read derivation over existing tables (ADR-0009), six event kinds, per-field-visibility gated, mute/block filtered, on the Explore tab. Still open: presence TTL + ops cost; milestones; shelf; digest. | sync events; push token infra; `NotificationsCoordinator` |
| 6 | Recommend-to, trending-in-network, follow curators, "because friends listen", guest/host graph, social proof | in-progress | **Slice 10 shipped the core (2026-07-18):** "Trending with friends" Explore row ranked by followees' last-30-days finished episodes (history-visibility gated per actor — the livelier signal, chosen knowing it thins at small scale) + podcast-page social proof from follows (followed-shows gated, **named only when the actor's list is already visible to you**, others fold into the count). Two signals, matching per-field gates. Still open: recommend-to, curators, guest/host graph. | `DiscoverServerHandler` (dormant) |
| 7 | Episode discussion threads, timestamped comments, reactions | in-progress | **Slice 6 decisions locked (2026-07-17, ADR-0010):** one comment entity, two lenses (episode thread + Moment scrubber pins for timestamped seeds); full nesting; tombstoned deletion; Join + ≥25%-played gate on top-level only; grace-window edit; `commented` feed kind (top-level only); Inbox "Replies" section w/ seen-watermark. Transcript pinning resolved by Slice 12 (2026-07-19, ADR-0010 amendment): Moments may carry a Transcript Quote — self-contained quote text (300-rune cap, UGC-filtered, tombstone-wiped) plus an advisory (source, segment) ref that may rot on regeneration; compose via transcript-line selection or composer auto-quote of the current line. | `?t=`/`?q=` model, `ShareQuoteBuilder` |
| 8 | Collaborative + subscribable lists, reactions/forks, auto-lists | in-progress | **Slice 7 shipped the core (2026-07-18, ADR-0011):** shared lists as social objects + mirrors (Inbox-style invites, attributed entries, 3-tier visibility, profile Lists section, published-list feed kind) AND the custom-playlist sync overturn (`custom_query = 1001` fork field; the exclusion in `PlaylistDataManager`/`SyncTask` is gone). Still open: list reactions/forks, auto-lists; note — the invite surface landed in the Shared Lists hub rather than the Inbox (dated amendment). | `sharePodcastList` |
| 8 | Explore tab → **Social** tab | in-progress | **Amended + started in Slice 5 (2026-07-17):** the tab restructured feed-first (feed → find-people → charts + search; join card for non-joined) but **keeps the name "Explore"** in all user strings/copy — amends decision 8's naming. | `ExploreViewModel`, `MainTabBarController` |

## Phase 3 — Community

| § | Item | Status | Gating decisions still open | Reuse anchor |
|---|---|---|---|---|
| 9 | Private group feeds, fandom hubs, shared-item inbox | in-progress | **Slice 13 decisions locked (2026-07-19, ADR-0012):** ONE Group entity, two configurations (private invite-only circle / public joinable hub, optional non-exclusive podcast anchor). Posts-only content (episode/list/text + note, threaded replies with comment-tree semantics) — NO ambient member activity (membership ≠ followership). Any-member invites via Inbox; owner moderates; private dies with owner, public hub succession to longest-tenured member; erased owner's posts tombstone. Quiet by default: invite push type 7 on-by-default; per-group opt-in new-post alerts (type 8, default off); public joins emit feed kind 9, private groups emit nothing. Deferred: moderator tier, request-to-join, group avatars (CSAM gate), group muting. | Slice-4 inbox, ADR-0010/0011 machinery |
| 3 | Listening parties / live chat | planned | real-time infra + moderation | presence infra |
| 10 | Streaks, badges, achievements, friend leaderboards | planned | achievement definitions; leaderboard privacy gating | `ListeningHeatmapViewModel` |
| 11 | Social push notifications (recommend, live, presence, reactions) + configurable defaults | in-progress | **Slice 8 shipped the core (2026-07-18):** six directed-at-you types (follow request/approved, new follower, shared item, comment reply, list invite), ALL ON by default (settled: personally-addressed events are the non-intrusive case), per-type toggles in Settings → Notifications backed by a server-side disabled-bitmask that gates sends at the source; category "so" + typed payload deep links; per-(type, actor) collapse ids. Still open: recommendation/presence/reaction pushes as those features land. Human prerequisite: APNs .p8 in backend config for real devices. | remote push token infra |
| 11 | Native social-story vertical export | planned | net-new Stories format | `VideoExporter` |
| 12 | AI: shareable summaries, taste-embedding friend-match, "why you'd like it", NL→shared playlist | planned | on-device vs server embeddings; taste-embedding privacy | `podcasts/Playback/Intelligence/`, bookmark `ai_*` fields |

## Cross-cutting notes

- **Monetization (§11–12):** no premium gate; use **Supporter Podcasts** where a paid
  concept is needed. Never trip `no-legacy-plus-payment-entry-points`.
- **Custom/AI playlist sync:** RESOLVED 2026-07-18 (Slice 7): the exclusion is overturned —
  `custom_query = 1001` on the shared playlist messages (guarded by
  `ApiForkPlaylistFieldsTests`), backend column + passthrough, both client guards removed.
- **Deferred foundation decisions:** wiring SSO/QR into Join; verified/reserved handles for
  creators & brands; presence TTL. (Feed fan-out settled 2026-07-17: fan-out-on-read,
  ADR-0009.)
