# ADR-0013: Milestone crossings are materialized (narrow ADR-0009 amendment)

Date: 2026-07-19 (Slice 14 grill)

## Decision

Listening milestones (two global ladders: total hours and episodes finished,
tiers {10, 50, 100, 250, 500, 1000}) are stored as materialized crossing rows
— `social_milestones(user, kind, tier, crossed_at)` — written when the sync
engine applies playback records, not derived at feed-read time (ADR-0009's
default) and not client-reported.

## Why

- The *aggregate* ("over 100 hours") is re-derivable; the *crossing moment*
  is not. A feed item needs a stable timestamp for ordering and cursoring,
  and recovering "when the sum crossed the tier" would mean replaying
  playback history inside the feed query, with a different answer whenever
  history rows re-sync.
- Client detection was rejected as a trust and dedup surface: any client
  could claim any tier, and multi-device would double-fire.
- This is deliberately the *narrowest possible* amendment to ADR-0009: one
  small insert-only table whose rows are facts about the past, written
  behind `ON CONFLICT DO NOTHING` so re-detection is idempotent. The feed
  still derives everything else at read time.

## Consequences

- Detection runs as two aggregate queries per sync batch that contains
  episode records — accepted at fork scale.
- Shared surfaces (feed kind, profile stats line) obey `stats_visibility`
  per viewer, like the heatmap; there is no new privacy field. The owner's
  own crossing always fires a local celebration.
- Erasure deletes milestone rows outright (they are the user's stats, not
  tree-structural like comments).
- The weekly digest (push type 9, on by default, guarded: joined AND
  (≥1 followee OR a milestone this week), `digest_sent_at` watermark)
  reads the same table for "crossed this week".
