# Semantic Library Search — Design Document

**Status: design only — NOT scheduled.** Recorded as program item 20 (user decision 2026-07-12:
"design doc only; implementation deferred"). Nothing in this document exists in code.

## Goal

Natural-language retrieval over the user's own library: "the episode where they argued about
nuclear power costs", "interviews with the woman who wrote about octopus cognition". Lexical search
(what `podcasts/New Search/` does today, plus the planned transcription FTS index) requires the
user to guess exact words; semantic search ranks by meaning.

Scope is the **local library** (subscribed podcasts' episodes, downloaded or not): show notes +
titles always; transcript text when a transcript exists locally (server-generated cache or the
planned on-device transcription artifacts). This is not a Discover/catalog search — nothing leaves
the device.

## Candidate embedding backends (iOS 26, on-device only)

| Backend | Pros | Cons |
|---|---|---|
| `NLEmbedding` / `NLContextualEmbedding` (NaturalLanguage) | Ships with OS (no model download); stable API; contextual variant gives sentence-level vectors; multilingual coverage via language-specific models | Quality below current open embedding models; dimensionality/model fixed by OS version; contextual embedding requires asset download per language |
| FoundationModels embedding surface | Highest quality Apple offers on-device; shares assets with other FoundationModels features the app may adopt (item 19) | API surface still evolving; asset availability varies by device class; larger memory footprint during indexing |
| Bundled third-party model (e.g. quantized MiniLM/GTE via CoreML) | Full control of quality/dims/versioning; identical vectors across OS versions | +30–90 MB app size or a download manager; conversion/maintenance burden; multilingual needs bigger models |

**Recommendation:** start with `NLContextualEmbedding` (sentence mode) behind a
`TextEmbedding` protocol so the backend is swappable; re-evaluate FoundationModels once its
embedding API stabilizes. The protocol seam is the design's only hard commitment:

```swift
protocol TextEmbedding: Sendable {
    var modelID: String { get }      // persisted with vectors; mismatch ⇒ re-index
    var dimensions: Int { get }
    func prepare() async throws      // asset download if needed
    func embed(_ texts: [String]) async throws -> [[Float]]
}
```

## Storage

New GRDB table (append-only migration in `DatabaseHelper.swift`, next free version at
implementation time):

```sql
CREATE TABLE episode_embedding (
    episodeUuid TEXT NOT NULL,
    chunkIndex  INTEGER NOT NULL,
    model       TEXT NOT NULL,      -- TextEmbedding.modelID
    dims        INTEGER NOT NULL,
    startTime   REAL,               -- transcript chunks only; NULL for show-notes chunks
    endTime     REAL,
    sourceKind  INTEGER NOT NULL,   -- 0 = title+shownotes, 1 = transcript window
    vector      BLOB NOT NULL,      -- packed little-endian Float32 [dims]
    PRIMARY KEY (episodeUuid, chunkIndex, model)
);
CREATE INDEX episode_embedding_model ON episode_embedding (model);
```

- **Brute-force cosine is sufficient.** A large library is ~10⁴ episodes; at ~8 transcript chunks +
  1 notes chunk per episode that is ~10⁵ vectors × 512–768 dims ≈ 200–300 MB *worst case*, so
  chunk counts must be bounded (below) to keep the table ≤ ~50 MB typical. Scanning 10⁵ vectors
  with vDSP dot products is a few ms — no ANN index, no extension dependency (sqlite-vec would be
  the escalation path, not the starting point).
- Vectors are L2-normalized at write time so cosine = dot product.
- `DataManager` exposure follows the `BookmarkDataManager` pattern: `EmbeddingDataManager` struct
  over `GRDBQueue`, surfaced as `DataManager.sharedManager.embeddings`.

## Chunking strategy

- **Show notes + title (sourceKind 0):** one chunk per episode — title + first ~1,500 chars of
  HTML-stripped show notes. Always available; this alone makes the feature useful pre-transcription.
- **Transcripts (sourceKind 1):** windows over cue text, ~120 words with 20-word overlap, aligned
  to cue boundaries (each window records `startTime`/`endTime` of its cue span for deep-link
  seeking). Cap: 32 windows per episode, sampled evenly across the duration when a transcript
  exceeds the cap (a 3-hour episode yields ~250 raw windows; even sampling preserves topical
  spread while bounding storage).

## Indexing pipeline

- Triggers: episode added/refreshed (notes chunk), transcript became available locally
  (transcript chunks), embedding model changed (full re-index).
- Runs as a low-priority background pass modeled on `EpisodeLoudnessScanner`: serial utility queue,
  one episode at a time, skipped when `ProcessInfo.thermalState >= .serious` or Low Power Mode is
  active; drains fully during the (planned) charging-time BGProcessingTask alongside transcription.
- Idempotency key: `(episodeUuid, model)` — re-running deletes and rewrites that episode's rows in
  one write transaction.
- Deletion: rows cascade when an episode is deleted from the DB (application-level delete hook —
  same place bookmark/transcription artifacts are removed).

## Query flow

1. `embed(query)` (one vector; ~10 ms warm).
2. vDSP dot-product scan over all vectors for the active `model`, top-K (K ≈ 40) with a min-score
   floor (~0.25 cosine; tuned empirically).
3. Group hits by episode: episode score = max(chunk scores) with a small bonus for multi-chunk
   hits; transcript hits carry their `startTime` for "play from here".
4. Present in the existing search UI (`podcasts/New Search/`) as a **"By meaning"** results section
   below exact-match results, each row showing episode + matched snippet (the chunk's first cue
   text) + jump-to-time affordance. No new screen; zero results section is simply hidden.
5. Latency budget: < 150 ms end-to-end on a 10⁴-episode library (dominated by the scan, which is
   parallelizable with `vDSP_dotpr` across chunks if needed).

## Privacy

Nothing leaves the device: embedding runs locally, vectors and query text are never transmitted,
and the table lives in the existing local GRDB database (excluded from any server sync by
construction — no sync_status column, no journal hooks). Analytics may record only counts/latency,
never query text.

## Open questions (to resolve at implementation time)

1. **Model versioning:** `NLContextualEmbedding` revisions with OS updates — does `modelID`
   capture enough (embed a revision probe vector and compare?) or do we pin re-index to OS major?
2. **Multilingual libraries:** per-language embedding assets vs one multilingual model; how to
   handle a query language different from episode language (likely: embed query with the model
   matched to each row's language and merge — needs a `language` column).
3. **Re-index policy:** on model change, full re-index could take hours for big libraries — do we
   dual-write old+new model rows and cut over, or serve stale vectors during re-index (preferred)?
4. **Transcript cap tuning:** is 32 windows/episode enough recall for 3-hour episodes, or should
   the cap scale with duration?
5. **Interaction with the transcription FTS screen** (transcription plan): should "By meaning" and
   FTS results merge into one ranked list, or stay separate sections (start separate)?

## Re-entry pointer

When scheduled: implement `TextEmbedding` + `EmbeddingDataManager` + indexer first (testable
without UI: cosine ranking golden tests with a stub embedding), then the search-section UI. The
transcription plan's FTS segment table already carries `(episodeUuid, segmentIndex, startTime)` —
transcript chunking should read from those segments rather than re-parsing VTT.
