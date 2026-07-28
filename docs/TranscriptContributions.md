# Transcript corpus contribution and read contract

The transcript system is a read/write immutable corpus. Automatic client
contribution remains enabled with no consent or premium gate.

## Contribution pipeline

After on-device transcription completes, the app uploads the transcript
immediately. A successful response supplies a candidate ID, SHA-256, and a
cryptographically random candidate-scoped attachment token. Only the token hash
is stored by the server and it is consumed once when the client later attaches
summary and chapters through `POST /transcripts/contribute/metadata`.

The client runs one bounded, transcript-segment-aligned Foundation Models
map/reduce. Maps produce factual segment summaries and chapter candidates; the
reducer produces a 150–250-word factual summary and three to eight ordered
chapters within the episode duration. If the model is unavailable, a compact
durable job retains the candidate reference and attachment token and retries on
lifecycle opportunities and weekly until success or candidate removal. There is
no server-side Gemini summary generation.

All writes require App Attest. Bearer authentication is optional and controls
attribution. Bodies are capped before decoding: 3 MiB compressed request, 2 MiB
transcript, 512 KiB fingerprint, and 128 KiB metadata. Contribution writes are
idempotent by content hash. Fingerprints are optional.

## Immutable releases and reads

The private object store contains immutable artifacts; PostgreSQL records
candidates, hashes, provenance, decisions, releases, and audit history. Existing
contribution rows import idempotently as legacy candidates when storage becomes
available. Account deletion anonymizes contributor provenance without deleting
canonical artifacts.

One active release exists per BCP-47 language. Transcript, fingerprint, summary,
and chapters may be selected independently, including explicit cross-source or
cross-language composition. Publisher artifacts auto-promote only when their
exact URL is currently declared for the episode in the cataloged feed. Admin
edits derive new candidates; rollback activates an older snapshot.

The typed manifest is the only source of artifact URLs, media types, formats,
hashes, source, and provenance. The client never constructs `.vtt` or fingerprint
paths and never probes R2. Reads require App Attest, use `private, no-cache`,
strong ETags and 304, resolve language from `Accept-Language` then podcast
language then `und`, and return 404 when no active release exists.

Timed publisher VTT, SRT, and Podcast JSON normalize to VTT. Sanitized HTML and
plain text remain accurately typed instead of being represented as fake VTT.
