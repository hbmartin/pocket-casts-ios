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
| 2 | Follow (asymmetric), find friends, import graph, people-you-may-know | in-progress | **Slice 5 shipped the core (2026-07-17):** hybrid consent (open default + per-account "Approve My Followers" → requests), follower/following lists + profile counts, `followers-only` tier unlocked in the privacy UI. Still open: find-friends/import-graph/PYMK (contacts-matching privacy). | `SharingHelper.shareLinkToApp` |
| 3 | Activity feed, now-playing presence, milestones, "recently played by" shelf, weekly digest | in-progress | **Slice 5 shipped the feed (2026-07-17):** fan-out-on-read derivation over existing tables (ADR-0009), six event kinds, per-field-visibility gated, mute/block filtered, on the Explore tab. Still open: presence TTL + ops cost; milestones; shelf; digest. | sync events; push token infra; `NotificationsCoordinator` |
| 6 | Recommend-to, trending-in-network, follow curators, "because friends listen", guest/host graph, social proof | planned | revive dormant `DiscoverServerHandler`; People-directory scope | `DiscoverServerHandler` (dormant) |
| 7 | Episode discussion threads, timestamped comments, reactions | planned | comment DB storage; timestamp pinned to transcript line | `?t=`/`?q=` model, `ShareQuoteBuilder` |
| 8 | Collaborative + subscribable lists, reactions/forks, auto-lists | planned | **overturn custom-playlist device-local exclusion** (sync custom/AI playlists) — reverses a deliberate choice in `PlaylistDataManager`/`SyncTask` | `sharePodcastList` |
| 8 | Explore tab → **Social** tab | in-progress | **Amended + started in Slice 5 (2026-07-17):** the tab restructured feed-first (feed → find-people → charts + search; join card for non-joined) but **keeps the name "Explore"** in all user strings/copy — amends decision 8's naming. | `ExploreViewModel`, `MainTabBarController` |

## Phase 3 — Community

| § | Item | Status | Gating decisions still open | Reuse anchor |
|---|---|---|---|---|
| 9 | Private group feeds, fandom hubs, shared-item inbox | planned | group moderation scaling; presence in groups | Slice-4 inbox |
| 3 | Listening parties / live chat | planned | real-time infra + moderation | presence infra |
| 10 | Streaks, badges, achievements, friend leaderboards | planned | achievement definitions; leaderboard privacy gating | `ListeningHeatmapViewModel` |
| 11 | Social push notifications (recommend, live, presence, reactions) + configurable defaults | planned | per-type opt-in matrix; non-intrusive defaults | remote push token infra |
| 11 | Native social-story vertical export | planned | net-new Stories format | `VideoExporter` |
| 12 | AI: shareable summaries, taste-embedding friend-match, "why you'd like it", NL→shared playlist | planned | on-device vs server embeddings; taste-embedding privacy | `podcasts/Playback/Intelligence/`, bookmark `ai_*` fields |

## Cross-cutting notes

- **Monetization (§11–12):** no premium gate; use **Supporter Podcasts** where a paid
  concept is needed. Never trip `no-legacy-plus-payment-entry-points`.
- **Custom/AI playlist sync:** collaborative lists (§8) require overturning the current
  device-local-only exclusion of `customQuery` playlists — a deliberate choice enforced in
  `PlaylistDataManager.allUnsyncedPlaylists` and the `SyncTask` import guard. Carries
  migration + sync-protocol risk; grill before committing.
- **Deferred foundation decisions:** wiring SSO/QR into Join; verified/reserved handles for
  creators & brands; presence TTL. (Feed fan-out settled 2026-07-17: fan-out-on-read,
  ADR-0009.)
