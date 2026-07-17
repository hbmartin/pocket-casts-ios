# Social Features Roadmap (living tracker)

Phased plan for the social program. Update the **Status** column as work lands. See
`docs/Social.md` for decisions and `docs/SocialModeration.md` for the moderation contract.

**Status legend:** `planned` · `in-progress` · `shipped` · `deferred`

## Phase 1 — Identity & lightweight sharing

| Slice | Item | Status | Notes |
|---|---|---|---|
| 1 | Identity + moderation foundation — **iOS dark scaffolding** (proto, `FeatureFlag.socialProfiles`, migration 85, models, API tasks) | shipped | PR #313. |
| 1 | Identity + moderation foundation — **backend endpoints** (`social/*`: handles + tombstone, profiles, per-field visibility, block/mute/report, triage queue, GDPR erase incl. account deletion) | in-progress | `podcast-backend` branch `social/foundation-endpoints`: migration 012, handlers, routes; Go handler + e2e suites green; iOS `SocialLocalBackendE2ETests` proves the Swift↔Go wire contract against the local Docker backend. |
| 1 | **Avatar upload + CSAM/nudity scan pipeline** | deferred | Deliberately cut from the first backend slice (2026-07-16): profiles are handle+name+bio only; `SocialAvatarUploadSender` sits unused; the scan-pipeline decision returns when avatars do. HARD gate: real scan vendor integration before avatars go live publicly. |
| 2 | Public profiles (followed shows, top podcasts, stats/heatmap, history, public lists — privacy-gated) | planned | Reuses `ListeningHeatmapView`. |
| 3 | Stat/heatmap share cards + **Year-in-Review** stories | planned | Client-only; rides `VideoExporter`/`ShareImageView`. YIR is net-new. |
| 3 | Written **reviews** (extend synced ratings + listen-gate) | planned | Needs new local rating DB storage (ratings are in-memory today). |
| 3 | Episode **reactions** (❤️😂🤯) | planned | Listen-gated; per-user + aggregate counts. |
| 4 | **Send-to-friend** + shared-item inbox | planned | Adds `ShareDestination.sendToUser`; minimal inbox. |

## Phase 2 — Graph & discovery

| § | Item | Status | Gating decisions still open | Reuse anchor |
|---|---|---|---|---|
| 2 | Follow (asymmetric), find friends, import graph, people-you-may-know | planned | follow-request model for private accts; contacts-matching privacy; `followers-only` UI unlock | `SharingHelper.shareLinkToApp` |
| 3 | Activity feed, now-playing presence, milestones, "recently played by" shelf, weekly digest | planned | feed fan-out (push vs pull); presence TTL + ops cost | sync events; push token infra; `NotificationsCoordinator` |
| 6 | Recommend-to, trending-in-network, follow curators, "because friends listen", guest/host graph, social proof | planned | revive dormant `DiscoverServerHandler`; People-directory scope | `DiscoverServerHandler` (dormant) |
| 7 | Episode discussion threads, timestamped comments, reactions | planned | comment DB storage; timestamp pinned to transcript line | `?t=`/`?q=` model, `ShareQuoteBuilder` |
| 8 | Collaborative + subscribable lists, reactions/forks, auto-lists | planned | **overturn custom-playlist device-local exclusion** (sync custom/AI playlists) — reverses a deliberate choice in `PlaylistDataManager`/`SyncTask` | `sharePodcastList` |
| 8 | Explore tab → **Social** tab | planned | fold directory discovery into the social cut | `ExploreViewModel`, `MainTabBarController` |

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
  creators & brands; presence TTL + feed fan-out architecture.
