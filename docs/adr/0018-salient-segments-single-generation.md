# One cached salient-segment generation per episode serves both the Highlights Tour and Suggested Highlights

The Highlights Tour needs "the segments worth touring"; Suggested Highlights
needs "the segments worth keeping." These are the same question asked with
different budgets, and on-device FoundationModels generation is the scarcest
resource involved (single-slot admission, 30 s ceiling, battery). So there is
exactly one generator — `SalientSegmentGenerator`, one FM call over the existing
12k-char/12-window transcript digest — and one durable store: `SalientSegment`
rows (rank, start/end, title, score, excerpt, `suggestionStatus`) plus a
`SalientSegmentMeta` row (outcome, transcript source, generator version) in the
GRDB database.

The store is the **database, not a Caches file**, unlike the superficially
similar `OnDeviceChapterStore`: `suggestionStatus` carries user state
(pending/accepted/dismissed), and a dismissed suggestion that resurrects after
an OS cache purge is a bug, not a regeneration. The durable `noSegments`
sentinel also prevents regeneration loops, and pending suggestions need
cross-episode queries for the review queue. Tour length presets (Quick ≈ 5 min,
Standard ≈ 25%, Deep ≈ 50%) are served from the one ranked candidate list by a
pure planner (greedy prefix-by-rank, reordered chronologically) — never by
re-generating. Rejected: separate generations per feature (double battery,
drifting results between tour and suggestions) and map/reduce chunking (N
serialized calls through the single-slot gate for granularity the cue-snapping
validator discards anyway).

## Consequences

- Transient FM failures leave an episode unattempted (retryable); only
  definitive outcomes (segments, or a durable `noSegments`) are persisted —
  the same semantics `TranscriptChapterGenerator` established.
- A prompt/validator change is a `generatorVersion` bump that orphans rows for
  lazy regeneration, not a migration.
- Segment times live in the transcript's own time domain with the source
  recorded in meta; consumers apply `TranscriptHitPlayback.resolvedSeekTime`
  semantics at seek/accept time. The tour never starts audio fingerprinting
  (tour jumps would perpetually restart it; it re-anchors off a notification
  that is suppressed in the background).
- Suggestion acceptance writes a Bookmark plus enrichment immediately; the
  segment row records the created `bookmarkUuid`, so accept is idempotent and
  auditable.
