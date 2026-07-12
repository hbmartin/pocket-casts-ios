# Audio Fingerprinting — Transcript Time Alignment

**Status:** shipped, gated by `FeatureFlag.syncedTranscripts` · **Last verified against code:** 2026-07-12

## Why this exists

Server-generated transcripts are produced from a *reference* copy of an episode's audio. The audio a
listener actually plays often differs from that reference because of **dynamic ad insertion**: ads of
arbitrary length are spliced in (or swapped out) per download, shifting every subsequent word by an
unpredictable offset. A transcript cue that says a word occurs at 12:05 may really play at 13:31.

The fingerprinting subsystem maps **live playback time ↔ reference-transcript time** by acoustically
matching the audio the user is hearing against a compact fingerprint of the reference audio. With
that mapping:

- transcript **follow-along highlighting** stays on the word actually being spoken,
- **tap-to-seek** on a transcript cue lands on the right audio,
- both degrade gracefully (highlighting simply stops) inside inserted ads, which by definition have
  no counterpart in the reference timeline.

Everything runs on-device; the only network access is a one-shot download of the reference
fingerprint file.

## Component map

All app-side code lives in `podcasts/Fingerprint/`:

| File | Role |
|---|---|
| `FingerprintConstants.swift` | Every tuning constant, each documented in-source (window/interval sizes, drift-filter thresholds, cache schema version, highlight gap). |
| `FingerprintTimingManager.swift` | The state machine and public API. Streams local audio, drives matching, maintains the time mapping. |
| `ReferenceFingerprint.swift` | Decoder for the server's `fingerprint-compact-v2` JSON format. |
| `FingerprintReferenceRetriever.swift` | Actor that downloads + gunzips the reference file (3 retries, exponential backoff, in-flight dedup). |
| `FingerprintMappingCache.swift` | Persists a completed mapping beside the audio file so replays skip the streaming pass. |
| `FingerprintDebugOverlay.swift` | DEBUG-only timeline visualization of matches/rejections. |

The fingerprint math itself (hashing windows of PCM, matching against checkpoints) is a **UniFFI
Rust binding**: `Automattic/pocket-casts-ios-fingerprint`, pinned by revision in
`Modules/Package.swift:80` and linked as product `Fingerprint`. It provides `CheckpointMatcher`,
`StreamingWindowedFingerprinter`, and `WindowedFingerprint`.

## Server contract

`FingerprintReferenceRetriever` fetches

```
{ServerConstants.Urls.generatedTranscripts}{podcastUuid}/{episodeUuid}-fingerprints.json.gz
```

(see `ServerConstants.swift` — same host that serves generated transcripts). A 404 means "no
reference exists for this episode" and resolves to `.unavailable`; transport errors retry up to 3
times with 2ⁿ-second backoff. The payload is gzip; decompression uses the system `Compression`
framework.

### Reference format: `fingerprint-compact-v2`

`ReferenceFingerprint` decodes and validates (unknown `format` strings are rejected):

```jsonc
{
  "format": "fingerprint-compact-v2",
  "total_duration": 3921.4,        // seconds of reference audio
  "checkpoint_interval": 2000,     // ms between checkpoints (the 2 s grid)
  "checkpoint_duration": 8000,     // ms of audio each checkpoint summarizes
  "timestamp_quantum": 10,         // ms units used by delta encoding
  "checkpoints": [ [delta, "base64…"], … ]
}
```

Each checkpoint is a `[delta, data]` pair: `delta` advances a running quantized timestamp and
`data` is base64-packed little-endian `UInt32` hashes. Decoding expands these into
`LibraryCheckpoint { timestampSeconds, hashes }` for the Rust matcher.

## How the live side works (`FingerprintTimingManager`)

State machine (`FingerprintTimingManager.State`):

```
idle → preparing → active(coverage: Int) → (idle on stop)
              ↘ failed(Error) / unavailable
```

- Entry is gated: `FeatureFlag.syncedTranscripts.enabled` must be true
  (`FingerprintTimingManager.swift:408`), and the transcript UI is what starts it.
- **Streaming fingerprint generation:** local audio is read via `AVAudioFile` in
  `streamChunkSeconds` (5 s) chunks and fed to `StreamingWindowedFingerprinter`, which emits an
  8000 ms fingerprint window every 1000 ms (`windowDurationMs` / `windowIntervalMs`). The 1 s
  stride deliberately **oversamples** the reference's 2 s checkpoint grid: a dynamic ad of
  non-multiple-of-2s length phase-shifts live windows off the grid, and at a 2 s stride every
  post-ad window would straddle two checkpoints and match neither. At 1 s, some window always lands
  within ~0.5 s of a checkpoint.
- **Not-yet-downloaded episodes** (streaming playback) are handled by fingerprinting the growing
  buffer file: the grow-loop polls every `bufferGrowPollCadenceSeconds` (1 s), refuses to read the
  trailing `bufferGrowTrailingMarginSeconds` (1 s — a partial MP3 frame decodes to noise), and
  gives up after `bufferGrowMaxStallSeconds` (60 s) without new bytes (a later playback-progress
  restart re-arms it).
- **CPU bounding:** while the fingerprint position is more than `lookaheadSeconds` (60 s) ahead of
  the listener, the loop sleeps `outsideLookaheadSleepSeconds` (0.5 s) between chunks. Chunks are
  never skipped — dense coverage to EOF is an invariant tap-to-seek relies on.
- **Seek handling:** playback-progress jumps larger than `restartDeltaSeconds` (10 s), or playback
  escaping the mapped range by more than `playbackRangeMarginSeconds` (30 s), restart generation at
  the new position.

### Match filtering (the drift filter)

Raw matcher output is noisy. A candidate `TimeMappingEntry` (playback time, reference time, score)
must survive:

1. **Score floor:** matcher matches below `matchScoreThreshold` (0.5) never surface; candidates
   below `driftAnchorScoreThreshold` (0.65) can't become anchors.
2. **Dominance gate:** the top-1 match must beat top-2 by `driftScoreDominanceGap` (0.05) —
   correlated false positives score near-ties across neighboring reference windows.
3. **Rate-≈1 projection:** audio plays at rate 1 against the reference between splice points, so a
   trusted anchor projects the next candidate's expected reference time; residuals beyond
   `driftToleranceSeconds` (5 s) are rejected as jump-around noise. A jump of any size is accepted
   if subsequent candidates re-form a consistent rate-1 line (`driftBootstrapCount` = 3 consecutive
   candidates bootstrap the first anchor).

Accepted entries are committed into two sorted arrays (`playbackToReference`,
`referenceToPlayback`); the manager becomes `.active` once `minimumCoverageForActive` (2) entries
exist. Rejections are kept (DEBUG) for the overlay.

### Public API

```swift
func referenceTime(forPlaybackTime: Double) -> Double?   // highlight: where in the transcript are we
func playbackTime(forReferenceTime: Double) -> Double?   // tap-to-seek: where in the audio is this cue
func isWithinMatchedContent(forPlaybackTime: Double) -> Bool
```

Both conversions interpolate between committed anchors. Consumers:
`TranscriptViewController` — the `CADisplayLink`-driven highlight loop only highlights when the
state is `.active` **and** playback sits between two anchors no further apart than
`highlightMaxGapSeconds` (8 s). That gap rule is the entire "ad detection": inserted ads commit no
anchors, so the gap over an ad break (≥15 s typically) exceeds the bound and highlighting stops
instantly, resuming at the first post-ad anchor.

## Mapping cache (`FingerprintMappingCache`)

A completed mapping is persisted as `<audio path minus extension>.map.fp.json` next to the audio
file, and loaded on replay only when **all** of these hold:

- `schemaVersion == FingerprintConstants.mappingCacheSchemaVersion` (2 — bump to invalidate),
- `referenceHash` equals the SHA-256 of the reference fingerprint data (reference changed → stale),
- the audio file's size/mtime and a 64 KiB content sample still match (file re-downloaded → the ad
  splice layout may differ → stale),
- coverage ≥ `fullCoverageThreshold` (0.95) of the reference timeline. Partial caches are ignored
  entirely — seeding a short-circuit from a partial cache is how an earlier attempt got stuck in
  `.preparing`.

A valid cache replaces the whole streaming pass; anything less reruns it from scratch.

## Relationship to the transcript flags

- `generatedTranscripts` — whether Pocket Casts server-generated transcripts are offered at all
  (`ShowInfoCoordinator.loadTranscriptsMetadata`).
- `syncedTranscripts` — whether the fingerprint alignment layer runs. Without it, transcripts
  render but follow-along/tap-to-seek use raw cue times (correct only when the played audio happens
  to match the reference).
- Local-feed podcasts (`refreshSource == .localFeed`) have no server-generated transcripts or
  fingerprints; the subsystem resolves `.unavailable` for them by construction.

## Tests

`PocketCastsTests/Tests/Fingerprint/`:

- `FingerprintTimingManagerTests.swift` — drift filter (jump acceptance, noise rejection,
  bootstrap), state transitions, mapping interpolation (uses `insert(mapping:)` /
  `stubMatches(_:)` seams).
- `FingerprintMappingCacheTests.swift` — schema/hash/coverage invalidation matrix.
- `ReferenceFingerprintTests.swift` — format validation, delta decoding, base64 hash unpacking.

## Debugging

`FingerprintDebugOverlay` (DEBUG builds) renders the mapped timeline: committed anchors (green),
score-band coloring for rejected candidates, current playback/reference cursors. Enable from the
transcript screen's debug affordance. `FileLog` lines are prefixed `Fingerprint…` per component.
