# ADR-0012: One Group entity — posts-only content, asymmetric lifecycle

Date: 2026-07-19 (Slice 13 grill)

## Decision

Groups (§9: private group feeds + fandom hubs) are ONE server entity with two
configurations — visibility ∈ {private, public} plus an optional, non-exclusive
podcast anchor — not two parallel features. A group's feed contains only
deliberate member posts (episode / Shared List / text, with threaded replies
reusing the comment-tree semantics of ADR-0010). Group membership never grants
follower-level visibility: no ambient member-activity lens. Lifecycle is
asymmetric: a private group dies with its owner's erasure (the ADR-0011
precedent), while a public hub survives via succession to the
longest-tenured remaining member.

## Why

- One entity keeps moderation, invites, feeds, and erasure single-pathed; the
  circle/hub distinction is configuration, not schema. (ADR-0010 philosophy.)
- Posts-only protects the existing privacy contract: listening-derived events
  are gated by *follower* relationships (ADR-0009); piping them into group
  rooms would bypass per-field visibility. Deliberate acts only.
- Non-exclusive anchors avoid hub squatting, implied officialness, and an
  operator arbitration queue; fragmentation self-resolves toward big rooms.
- Succession (user decision, over the symmetric dies-with-owner default): a
  community of N members should not vanish because one account erased. The
  cost — an erasure transaction that mutates ownership, and two lifecycle
  paths — is accepted. The erased owner's own posts still tombstone.

## Consequences

- The erase path must pick a successor (earliest active member row) inside the
  same transaction that wipes the owner, and delete the hub when none exists.
- Quiet-by-default noise model: invites push (directed, type 7, on by
  default); ordinary posts push only to members who opted in per-group
  (type 8, per-member flag, off by default); public joins emit a feed kind;
  private groups emit nothing anywhere.
- Deferred without schema risk: moderator tier, request-to-join approval mode,
  group avatars (CSAM-scan gate), per-group mute.
