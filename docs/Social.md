# Social Features Program

This fork is building a complete, phased set of social features that ultimately replace
the Explore/Discover surface with a people-driven experience. This document is the
program's decision record and entry point. Companion docs:

- `docs/SocialModeration.md` — the moderation & safety operating contract.
- `docs/SocialRoadmap.md` — the living, phased roadmap and status tracker.
- ADRs `0005` (identity & handles), `0006` (per-field privacy), `0007` (content moderation).
- `CONTEXT.md` → "Social" — the domain glossary (Join, Handle, Tombstone, Visibility, …).

## Framing constraints

- **No premium tier.** Plus/IAP is removed and `semgrep/swift-security.yml`
  (`no-legacy-plus-payment-entry-points`) blocks reintroducing payment entry points.
  Social ships to **everyone**; where a paid concept is genuinely needed, it leans on the
  one sanctioned mechanism, **Supporter Podcasts** (creator support) — never a Plus gate.
- **Backend live before ship.** Any build containing a social surface must not ship until
  the backend it depends on is live in production (same hard rule as transcript
  contributions). The client feature flag ships the code dark until then.
- **Fork-owned backend.** The program builds and operates the full stack in
  `podcast-backend`: identity, graph, feed fan-out, presence, comments + moderation queue,
  media CDN, and abuse tooling — including the ongoing ops, moderation and GDPR surface.

## Locked decisions

1. **Full social backend**, owned and operated in `podcast-backend`.
2. **Opt-in identity.** No handle / no public footprint / no participation until an
   explicit one-time **Join**. Pre-Join, existing sync is unchanged. Join requires a
   logged-in synced account. (ADR-0005)
3. **Immutable, permanent handle** in the user UI; profile URL `pca.st/u/<handle>`; the
   canonical stored identity remains the server `uuid`. (ADR-0005)
4. **Tombstone + operator reclaim.** Deleted handles are tombstoned forever (PII erased,
   handle string reserved). Operators can reclaim/reassign for impersonation, trademark,
   slur or legal order, and grant a one-off safety rename via support. (ADR-0005)
5. **Per-field 3-tier privacy schema, 2-tier UI now, default private.** Store
   `{public | followers-only | private}` per field from day one; expose only
   public/private until the Phase-2 graph unlocks `followers-only`. (ADR-0006)
6. **Post-moderation** + automated pre-filters (text classifier; mandatory CSAM/nudity
   image scan on every avatar/thumbnail) + community flags into one async triage queue;
   block/mute/report ship with the first UGC surface; anti-spam reuses the listen-gate.
   (ADR-0007)
7. **Explore → Social (end-state).** The Explore tab becomes a unified Social tab merging
   people-driven and directory discovery. Phase-1 interim: social attaches to existing
   profile/podcast/episode screens; the tab flips when the Phase-2 feed exists.
8. **Seed from local, server wins.** Join seeds display name + avatar from the device-local
   Share Profile as candidate content only (not its share-on toggles); then the server is
   source of truth and the local card retargets to `pca.st/u/<handle>`.
9. **Identity-first ship order.** Foundation → public profiles → share cards + reviews +
   reactions → send-to-friend + inbox.
10. **Lean-but-safe foundation** is the first ship: handle claim/reserve/tombstone, profile
    store, avatar upload + scan, per-field privacy schema, block/mute/report capture, GDPR
    erasure, automated pre-filters, manual triage, and the public profile read. Deferred:
    dashboards, trust-weighting, shadow-limiting, appeals.

## Phase 1 slices

1. **Identity + moderation foundation** (the backend-live gate). Backend: `handles` table
   (PK = handle → reissue impossible), profile store with per-field visibility, avatar
   upload + CSAM/nudity scan → CDN, block/mute/report → `moderation_reports` queue, GDPR
   erasure, public read powering `pca.st/u/<handle>`. Client: new fork-owned proto messages,
   `ApiServerHandler+SocialIdentity`/`+SocialModeration` tasks, GRDB migration 85
   (`SocialRelationship`) + `SocialGraphStore`, own-profile cache, `FeatureFlag.socialProfiles`,
   the Join flow, own/other profile pages, the social privacy screen, and retargeting the
   Share Profile card.
2. **Public profiles** — populate followed shows, top podcasts, stats/heatmap, history and
   public lists behind the privacy gates.
3. **Share cards + reviews + reactions** — stat/heatmap + Year-in-Review share cards (client
   only, ride `VideoExporter`/`ShareImageView`); written reviews extending the synced rating
   primitive (needs new local rating storage — ratings are in-memory today); episode
   reactions (❤️😂🤯), listen-gated.
4. **Send-to-friend + shared-item inbox** — `ShareDestination.sendToUser(handle)` plus a
   minimal inbox (read/unread, react).

## Where things live (code anchors)

- Identity anchor `ServerSettings.userId`; Join gate `SyncManager.isUserLoggedIn()`.
- Seed source: `podcasts/Share Profile/ShareProfileViewModel.swift`; entry
  `ProfileHeaderViewModel.shareTapped()`.
- API pattern to clone: `UserPodcastRatingTask.swift` (+ `ApiServerHandler+UserPodcastRating.swift`);
  App-Attest sender to clone for avatar upload: `TranscriptUploadSender.swift`.
- Proto: repo-root `api.proto` (byte-identical mirror of `podcast-backend/protos/api.proto`),
  regenerate with `mise run generate:proto`; keep the settings hand-edits and
  `ApiForkSettingsFieldsTests` green.
- Feature-flag gate: `FeatureFlag.socialProfiles` (Beta-menu described, remote kill switch).
