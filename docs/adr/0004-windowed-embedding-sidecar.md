# Store transcript embeddings as windowed, quantized vectors in a corpus-mirrored sidecar

Semantic transcript search needs a vector per unit of text, and the obvious unit —
the corpus Segment — doesn't survive the arithmetic: sentence-sized segments at the
corpus's 200 MB text cap would mean millions of 512-dim float32 vectors (gigabytes).
We store one vector per **Embedding Window** — a run of ~6–10 consecutive segments
(~1,000 characters, slight overlap), mean-pooled, L2-normalized, encoded **float16**
little-endian — in a plain-table sidecar (`TranscriptEmbedding` +
`TranscriptEmbeddingMeta`, migration 84) keyed to the same `(episodeUuid, source)`
identity as the FTS corpus plus a window ordinal and segment range. Worst case this
is roughly 1:1 with the FTS text bytes it shadows; float16 is native on arm64 and,
with pre-normalized vectors, query scoring is a plain dot product. Int8 was
rejected (per-vector scale bookkeeping for marginal savings), as was per-segment
storage with a restricted corpus (coverage rules users would have to learn), and
query-time re-ranking of FTS results (keyword-bound recall, which defeats the
"works when no keyword matches" goal).

The sidecar's lifecycle is deliberately subordinate to the corpus: every corpus
deletion (re-index, explicit delete, byte-cap eviction) cascades to the sidecar
inside the same write transaction, and `replaceWindows` refuses to write for a
pair the corpus no longer contains — closing the race where an embed task
finishes after its FTS rows were evicted. Meta rows are stamped with model
identifier/revision/dimension/quantization; mismatched rows are invisible to
scans and re-listed as pending, so an OS model bump re-embeds lazily instead of
via a migration sweep.

## Consequences

- Semantic hits land on a window's first segment, not the exact sentence — a
  coarser jump target than FTS hits, accepted for the ~10× storage saving.
- A stored-format change (window shape, encoding) is a `schemaVersion`-style
  model-info bump plus lazy re-embed, not a destructive migration.
- Migration 84 deliberately skips 83, which is reserved for the transcript-
  contribution branch's `PendingTranscriptUpload` table; both migrations use
  IF NOT EXISTS so either adoption order is safe, but a device that runs 84
  before 83 exists will never run 83 — merge the contribution branch's
  migration to trunk first (or renumber it) before shipping installs from
  this branch.
- The `(podcastUuid, episodeUuid)` index plus `publishedBefore`/`excludeEpisodeUuid`
  candidate filters pre-build the "earlier episodes of this show" query that
  callback detection (deferred) needs — no schema change awaits it.
