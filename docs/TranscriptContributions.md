# Transcript Contributions — Crowdsourced Transcript Upload

**Status:** contract specified, client implementation in progress · **Decisions:** ADR-0002 (feature), ADR-0003 (auth)
**Vocabulary:** `CONTEXT.md` — *Contribution*, *Sighting*, *Eligible episode*, *Generated transcript*, *Provided transcript*.

The goal is crowdsourcing: one listener's Generated transcript, uploaded with the
timing fingerprint of the exact audio it was cut from, can later serve every other
listener of that episode. **v1 is write-only** — the backend ingests and stores;
nothing is served back to clients yet. Serving is a future design with its own
doc; the schema below is shaped so serving needs no re-collection.

---

## 1. What is uploaded

| Kind | Trigger | Payload |
|---|---|---|
| **Contribution** | A transcription job reaches `complete()` for an Eligible episode | gzipped VTT + gzipped `fingerprint-compact-v2` fingerprint of the contributor's audio + source metadata |
| **Sighting** | First load of an episode's Provided-transcript metadata (deduplicated per episode, locally) | transcript URL + format + language; the **server fetches the content itself** |

Never uploaded: anything from private local feeds (a locally-refreshed podcast
**with stored Basic-auth credentials** — `feedRefreshSource` alone doesn't make a
feed private; credential-less URL-subscribed feeds are public and eligible),
transcript URLs carrying userinfo or query-string tokens (Sighting dropped — a URL
is rejected when it has userinfo, or any query item whose name matches
`(?i)(token|sig|signature|key|auth|session|expires|policy)` or whose value is 16+
characters; `TranscriptContributionEligibility.isTokenFreeURL`), any
listening behavior, any device identifier beyond the App Attest key ID in headers.
Episodes **outside** the Pocket Casts catalog are eligible: their deterministic
feed-derived UUIDs (`LocalFeedIdentity`) are computed identically by every
subscriber of the same feed, so contributions key correctly server-side without
the feed URL ever leaving the device.

## 2. Client pipeline

`transcribe → complete() → fingerprint (background stage) → upload (background stage)`

- `complete()` publishes the transcript to the user immediately; fingerprinting
  never blocks the transcript UX.
- The fingerprint stage streams the on-device audio file once through
  `StreamingWindowedFingerprinter` (UniFFI Rust binding) and serializes the
  windows to `fingerprint-compact-v2` JSON — the exact format
  `ReferenceFingerprint` already decodes; the encoder is round-trip-tested
  against the decoder.
- Pending work lives in a GRDB-backed table drained serially (the
  `TranscriptionQueueManager` pattern), survives relaunch, retries with
  exponential backoff, and has **no terminal give-up** — a row persists until
  success or its transcription is deleted (tombstone check before every send;
  deleting locally cancels pending uploads but cannot retract delivered ones).
- The whole pipeline obeys the transcription battery/Low Power policy: deferred
  power state pauses fingerprinting and uploads exactly like transcription jobs.
- **No client feature flag and no user setting** (product decision, ADR-0002).
  Operator control is entirely server-side (§5).

## 3. Wire contract

Both endpoints require App Attest assertion headers (`docs/AppAttest.md`);
`Authorization: Bearer` is attached when the user is signed in. Bodies are
protobuf (fork-owned messages; fields in the ≥1001 fork allocation range where
they extend shared messages), gzip-encoded.

### `POST transcripts/contribute`

| Field | Notes |
|---|---|
| `episode_uuid`, `podcast_uuid` | catalog UUIDs or deterministic local-feed identities — indistinguishable by design |
| `vtt` | gzipped VTT bytes, speaker labels included, exactly the on-device artifact |
| `fingerprint` | gzipped `fingerprint-compact-v2` JSON of the contributor's audio stitch |
| `engine` | `whisperkit` \| `applespeech` \| remote provider identifier |
| `model_id` | the *specific* producer: e.g. `whisper-large-v3-turbo`, `apple-speech-ios26`, or the remote provider's model/API identifier from the provider config |
| `language` | BCP-47 as reported by the engine |
| `diarized` | bool |
| `app_version` | build marketing version |
| `episode_duration_seconds` | sanity anchor for validation |
| `created_at` | contribution creation time (no listening timestamps) |

### `POST transcripts/sighting`

`episode_uuid`, `podcast_uuid`, `transcript_url` (token-free, enforced client-side
and re-validated server-side), `format` (mime), `language?`. Server response 202;
the fetch itself is a server-side job (fetch from the publisher URL, byte-cap,
content-type check, store keyed like a contribution with `engine = "publisher"`).

## 4. Server storage model (backend team)

- **Store every contribution** — multiple contributions per episode are expected
  and all are kept (no arbitration, no replacement rule; serving-time selection
  is a future design).
- Attribution per row: `account_user_id` when the request carried a valid Bearer,
  else `attest_key_id`. Exactly one; never both, never neither.
- Suggested row: `id, episode_uuid, podcast_uuid, vtt_blob, fingerprint_blob,
  engine, model_id, language, diarized, app_version, episode_duration_seconds,
  created_at, received_at, attribution (user|install), attribution_id`.
- Validation before storage: VTT parses and is non-empty; cue span ≈
  `episode_duration_seconds` (reject > ±20 %); fingerprint JSON decodes as
  `fingerprint-compact-v2` with sane window cadence and non-degenerate hashes;
  size caps: VTT ≤ 2 MB gzipped, fingerprint ≤ 512 KB gzipped, request ≤ 3 MB.
- Sightings dedup on `(episode_uuid, transcript_url)`; re-sighting refreshes
  nothing in v1.

## 5. Operator controls (replace the client kill switch)

The client is always-on, so the server owns every lever:

- **429 + `Retry-After`** — client backs off the single pending item and resumes.
- **`503 + Retry-After`** (or a dedicated pause envelope) — client parks the
  *entire* upload queue for the indicated window (default 24 h when the header is
  absent). This is the kill switch.
- Per-endpoint App Attest enforcement mode (`off/log-only/required`) — see
  `docs/AppAttest.md` §2.3.
- Per-key and per-account rate limits (suggested: 50 contributions/day,
  200 sightings/day — far above organic use).
- Size caps and validation (§4) reject junk before storage.

## 6. Backend task list (detailed followups)

1. Everything in `docs/AppAttest.md` §4 (challenge, enroll, assertion middleware,
   metrics) — **prerequisite**; the flagless client must find these live.
2. The two endpoints (§3) with validation (§4) and storage schema.
3. Sighting fetch worker: fetch publisher URL (timeouts, redirects capped,
   content-type/size checks), store alongside contributions.
4. Operator controls (§5): pause envelope, rate limiters, enforcement flags.
5. Metrics: contributions/day by engine+model, sightings/day, validation
   rejections by cause, queue-pause activations, per-key volume outliers.
6. Retention/ops decisions to make before launch: blob storage target and
   budget (VTTs are small; fleet is TestFlight-scale), backup policy, and the
   deletion runbook for takedown requests (attribution makes per-install or
   per-account deletion tractable).
7. Proto: add the two request messages to the canonical `api.proto`
   (fork field allocations ≥1001 where shared messages are extended), then
   regenerate the client (`mise run generate:proto`) — the wire-compat gate
   must stay green.
8. Future (explicitly out of v1): serving/selection design (source-priority,
   quality ranking across multiple contributions), client download path — a
   contributed transcript should eventually be indistinguishable from a server
   reference transcript (same `{episodeUuid}.vtt` + `{episodeUuid}-fingerprints.json.gz`
   shape the `syncedTranscripts` machinery consumes today).
