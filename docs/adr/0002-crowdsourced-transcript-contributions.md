# Contribute generated transcripts silently, paired with an audio fingerprint

Generated transcripts exist only on the device that transcribed the episode, so every
other listener of the same episode re-pays the transcription cost (or has nothing).
We decided the app uploads every Generated transcript of an Eligible episode to this
fork's backend — **silently, always-on, with no user-facing setting** (product
decision; a default-on toggle and a passive-disclosure variant were considered and
rejected) — and pairs the VTT with a `fingerprint-compact-v2` fingerprint of the
exact audio it was cut from, so a future consumer can align the contributor's
timestamps to their own ad-stitched copy using the existing `syncedTranscripts`
machinery unchanged. Publisher-provided transcripts are never re-uploaded; the
client sends a **Sighting** (URL + format) and the server fetches the content
itself. The backend is **write-only in v1**: nothing is served back yet.

## Consequences

- Privacy rests entirely on the eligibility rules: private local feeds are never
  contributed or sighted, transcript URLs carrying credentials/tokens are never
  sighted, and no listening behavior is ever included. Episodes *outside* the
  Pocket Casts catalog are deliberately eligible — deterministic feed-derived
  UUIDs mean all subscribers of the same feed compute the same keys, so the feed
  URL itself never leaves the device for a Contribution.
- A locally deleted transcription cancels a pending upload but cannot retract an
  already-uploaded copy (no user identity, no control surface).
- Contributions are attributed server-side: to the account ID when the request is
  authenticated, otherwise to the App Attest key ID as a per-install identity
  (see ADR-0003).
- There is no client feature flag. Operator control is server-side only
  (429/503 backoff contract) — a bad server day is handled by the server telling
  clients to pause, not by a client kill switch.
- Fingerprinting is a follow-on background stage after `complete()` so the
  transcript UX is never blocked; the whole pipeline (fingerprint + upload) obeys
  the same battery/Low Power policy as transcription itself.
- Details: `docs/TranscriptContributions.md` (contract), `docs/AppAttest.md`
  (endpoint authentication).
