# 10. One comment tree, fully nested, with tombstoned deletion

Date: 2026-07-17

## Status

Accepted

## Context

Slice 6 adds episode discussion (roadmap §7). The product asks for two surfaces —
an episode discussion thread AND timestamp-anchored "Moments" on the player — which
naïvely suggests two entities with separate schemas, endpoints, and moderation
surfaces. Separately, replies could be flat (YouTube-style single level) or fully
nested (Reddit-style trees), and deletion in a tree must decide the fate of a
removed comment's descendants. All three choices are hard to reverse once public
conversation exists on top of them.

## Decision

1. **One entity, two lenses.** A single `episode_comments` table holds the whole
   tree. A *Moment* is nothing but a top-level comment whose optional
   `timestamp_seconds` is set — the player renders it as a scrubber pin, the
   episode page renders it in the same list with a seek chip. There is no second
   schema, endpoint family, or moderation surface.
2. **Full nesting.** `parent_id` may reference any comment. The phone UI copes by
   paginating top-level comments and fetching children on expand, collapsing past
   a display depth.
3. **Tombstoned deletion.** Author deletion, moderation removal, and GDPR erasure
   all wipe a comment's text and authorship (`user_id` nulled) but keep the row, so
   descendants — other people's contributions — survive under a "[removed]"
   placeholder. This is the comment-tree analogue of ADR-0005's handle tombstones:
   erase the PII, keep the non-PII skeleton.

Supporting policy locked in the same grill round: writes require a joined account;
top-level comments carry the ≥25%-played listen-gate while replies carry none;
edits are allowed only inside a short grace window and only until first reply
(`edited` flagged, re-filtered); top-level comments emit `commented` feed items
(fan-out-on-read per ADR-0009) while replies do not; replies to your comments
surface in the Inbox with a per-profile seen-watermark instead of per-item read
rows.

## Consequences

- Moments inherit every thread behavior for free (replies, reports, tombstones,
  feed presence) — and any future thread feature automatically works on Moments.
  The cost: Moments can never diverge structurally (e.g. become react-only pins)
  without a migration.
- Full nesting commits the iOS UI to tree rendering (expand/collapse, per-branch
  pagination). Reverting to a flat model later would orphan existing deep replies.
- Tombstones mean comment counts include removed placeholders and the table only
  grows; erasure compliance rests on the wipe being total (text, author link,
  edited state) rather than on row deletion. A blocked-either-way author's
  comments are excluded outright from lists (mutual invisibility), which hides
  their entire subtree from that viewer — accepted as the block contract rather
  than leaking a placeholder.

## Amendment (2026-07-19, Slice 12)

The deferred transcript-line anchor question is resolved: a Moment may carry a
**Transcript Quote** — the quoted line text stored verbatim on the comment
(self-contained rendering truth), plus an advisory `(quote_source,
quote_segment)` reference into the transcript that produced it. The quote can
never break; the reference is best-effort and expected to rot when transcripts
regenerate, so nothing may ever *depend* on it resolving. Quotes require a
timestamp (a quoted comment is a Moment by construction), pass the same UGC
text filter as comment bodies, cap at 300 runes, and are wiped alongside the
text on tombstoning/erasure.
