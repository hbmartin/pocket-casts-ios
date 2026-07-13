# Merge the two transcript FTS corpora into one table

The app had two near-identical FTS5 indexes: `TranscriptionSegmentFTS` (generated
transcripts, migration 78, searched from a Profile screen) and `TranscriptCueIndex`
(viewed provided transcripts, migration 81, searched from New Search). We merged
them at the schema level — migration 82 creates one `TranscriptSegmentIndex` table
with a `source` column plus one `TranscriptSearchIndexMeta` bookkeeping table,
backfills both corpora, and drops the old tables — rather than federating two
tables at query time, because a single table gives one BM25 ranking across both
corpora (federated bm25 scores are not comparable across tables), one eviction
policy, and one data manager instead of two drifting copies.

## Consequences

- Eviction is byte-cap only (200 MB, no episode-count cap); only `provided` rows
  are victims (departed-episode rows first, then LRU) — `generated` rows are never
  evicted because they are expensive to recreate.
- `EpisodeTranscription` deliberately stays: it is pipeline state, not index data.
- The migration re-tokenizes both corpora inside the single setup transaction on
  the launch path — a one-time cost, worst case a few seconds on a large index.
