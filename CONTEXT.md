# Domain Glossary

Canonical vocabulary for this fork's transcript, playback and intelligence features.
Terms here are the ubiquitous language — code, docs and PRs should use them exactly.

## Transcript search

- **Transcript Corpus** — the single unified full-text index of transcript segments
  across the library. One corpus, two *sources* (below). Device-local, never syncs.
- **Provided transcript** — a transcript the podcast's feed offers (VTT/SRT/JSON),
  fetched from the publisher. Re-fetchable at any time, so its index rows are
  evictable under the corpus byte cap.
- **Generated transcript** — a transcript produced by this app's transcription
  pipeline (on-device engine or a user-configured remote provider). Backed by a VTT
  artifact on the device; its index rows are never evicted. Generated transcripts
  of Eligible episodes are contributed to the backend.
- **Segment** — the unit of the corpus: a sentence-ish run of transcript text with
  a start time (and, when known, end time and speaker), belonging to one episode
  and one source.
- **Transcription record** — the per-episode pipeline-state row (status, engine,
  provider, artifact path). Pipeline state, not index data: it survives index
  rebuilds and lives in its own table.

## Transcript crowdsourcing

- **Contribution** — an upload of a Generated transcript's content, together with
  a fingerprint of the exact audio it was cut from, so other listeners of the
  same episode can use it with correct timing despite dynamic ad insertion.
  Only Generated transcripts are contributed; the server already has everything
  else.
- **Sighting** — a report that an episode has a Provided transcript at a publisher
  URL (with format and language). No content leaves the device; a Sighting asks
  the server to fetch the transcript itself from the publisher.
- **Eligible episode** — an episode whose transcripts may be contributed or
  sighted: every episode except those of private local feeds. Episodes outside
  the Pocket Casts catalog are eligible — their deterministic feed-derived
  identity is shared by all subscribers of the same feed. A transcript URL
  carrying credentials or access tokens is never sighted.

## Playback intelligence

- **Catch Me Up** — an on-device summary of an in-progress episode covering only
  the portion already played (start → playhead), for resuming after time away.
  Distinct from an *episode summary*, which covers the whole episode.
- **Effects Profile** — a named disposition of the audio-effects chain (trim
  silence, voice boost) that can be swapped at runtime without rewriting the
  user's persisted tuning. "Music profile" suspends trim and boost during
  music-dominant segments.

## Feedback

- **Feedback Report** — a user-initiated report from a TestFlight/debug build
  (shake gesture): message plus attached diagnostics (device/app info, log tail,
  bitdrift session ID), sent to this fork's own feedback endpoint.
