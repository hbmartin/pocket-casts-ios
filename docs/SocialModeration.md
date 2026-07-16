# Social Moderation & Safety — Operating Contract

The moderation model for social user-generated content (UGC). Decision rationale is in
ADR-0007; this document is the operating contract the client and backend implement.

## Posture

**Post-moderation.** UGC becomes visible immediately *after* passing automated
pre-filters. Users flag what slips through; flags feed an asynchronous triage queue.
There is no pre-approval step and no premium tier funding moderation, so the model is
built to run with a small operations team: automation first, community flagging second,
manual triage last.

## What counts as UGC

Display name, bio, avatar image (Slice 1); written reviews, episode reactions (Slice 3);
comments, clips, list metadata (Phase 2+). Every one passes the pre-filters below before
it is publicly visible.

## Automated pre-filters (before publish)

- **Text** (name, bio, review/comment): a classifier for slurs, hate, harassment and
  spam. Reject synchronously on the write path; the caller sees the rejection and can edit.
- **Image** (avatar, thumbnail): **mandatory** CSAM hash-match **and** nudity/adult
  classifier. The pipeline is: size-cap the raw bytes → decode → strip EXIF / re-encode →
  scan → publish to the media CDN **only if clean**. A flagged image is **never
  published**; it is enqueued to triage. A CSAM hit additionally enters the
  mandatory-reporting path. This scan is non-negotiable and independent of the posture
  choice.
- **Rate limits + listen-gate.** Write endpoints are rate-limited. Reviews/comments/
  reactions reuse the existing listen-gate (`RatePodcastViewModel.swift`,
  `numberOfEpisodesListenedRequiredToRate`): you must have listened to the podcast/episode
  before you can post.
- **First-party proof.** Write endpoints (join, avatar, report) carry an App Attest
  assertion over the request-body hash (ADR-0003 / `docs/AppAttest.md`).

## Triage queue

Community flags **and** automated pre-filter hits land in a single `moderation_reports`
queue, distinguished by `source`:

| Field | Meaning |
|---|---|
| `id` | queue row id |
| `target_user_id` / `target_handle` | who/what is reported |
| `reporter_user_id` | reporter (null for automated hits) |
| `source` | `community_flag` \| `auto_text` \| `auto_image` |
| `reason` | report reason / classifier label |
| `context_ref` | pointer to the offending content |
| `created_at`, `state` | timestamps + workflow state |

At launch, triage is **manual** — operators read the queue via an admin view or direct
DB queries and take action. **Deferred** until volume justifies: moderation dashboards,
reporter/target trust-weighting, automatic shadow-limiting, and an appeals workflow.
Repeat offenders are auto-throttled.

## Safety primitives (ship with the first UGC surface)

- **Block** — mutual invisibility. A blocked pair cannot see each other's profile or
  content, cannot follow, cannot mention-resolve, cannot interact. Enforced server-side at
  the public read: a blocked viewer receives the same shape as not-found. Mirrored to a
  local `SocialRelationship` store for instant filtering; the server is authoritative.
- **Mute** — one-way hide. The muter stops seeing the muted party's content; the muted
  party is **not** notified and is otherwise unaffected. Persisted server-side so it
  follows the user across devices.
- **Report** — a flag into the triage queue (reason + context). Returns immediately; no
  synchronous action.

## GDPR erasure

Account deletion (and an explicit `social/erase`) clears all profile PII — display name,
bio, stats, and the CDN avatar object — and sets the handle to `tombstoned`, nulling the
account association while **keeping the handle string** as a non-PII reservation so old
mentions/links can't be reassigned. A later availability check on that handle returns
`tombstoned`. The iOS account-deletion path (`DeleteAccountTask`) triggers social erase
and clears local caches (own-profile cache + `SocialGraphStore`).

## Operator carve-outs (handle integrity)

Operators can forcibly reclaim/reassign a handle for impersonation, trademark, slur or
legal order, and grant a one-off safety rename via support (ADR-0005). The `handles`
table (PK = handle, nullable `account_user_id`, `status ∈ {active, tombstoned,
reserved}`) already supports these operations; the operator UI is deferred, the data model
is not.
