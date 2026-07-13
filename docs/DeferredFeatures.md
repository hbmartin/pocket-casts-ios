# Deferred AI/UX Features

Companion to `plans/AI UX Improvements.md` (shipped July 2026 as phases 2–6 behind flags
`episodeSummaries`, `smartHighlights`, `transcriptSearch`, `promptedPlaylists`,
`episodeCredits`; AI chapters shipped un-gated earlier). This file records what was
deliberately not built, why, and what it would build on.

## Deferred: Daily briefing / highlights feed

**Concept:** a morning surface summarizing what's new across the user's subscriptions —
new-episode summaries, key takeaways, and the user's recent highlights, assembled
on-device into a scannable feed (optionally narrated).

**Why deferred:** every ingredient shipped this round, but the product shape (feed vs
notification vs widget), refresh economics (N summaries × subscriptions on a schedule),
and notification fatigue need design time that the implementation round deliberately
excluded.

**Primitives it would build on (all landed):**
- `OnDeviceIntelligence` / `IntelligenceProviding` (podcasts/Playback/Intelligence/)
- `ShowInfoCoordinator.loadEpisodeSummary(podcastUuid:episodeUuid:)`
- `TranscriptIndexDataManager` + `TranscriptionDataManager` FTS corpora
- `HighlightEnricher` output (bookmark excerpts + titles)
- `PlaybackManager.play(episodeUuid:podcastUuid:at:)` deep-link seek

**Revisit criteria:** episodeSummaries flag proves retention in beta; a design answers
where the feed lives; a budget for background FM invocations exists (thermal + battery
telemetry from the transcription BG task is a useful proxy).

**Standing constraints:** on-device only; everything free; per-feature flags.

## Smaller cut lines (from the plan, unchanged rationale)

- **Transcript Q&A chat** — user-cut.
- **Transcript-view citation changes** — user-cut (summary-card citations only).
- **On-device transcription** — NOT deferred after all: shipped separately as the
  diarized transcription plan (three engine modes, behind `diarizedTranscription`).
- **Download-triggered background transcript indexing** — v1 indexes transcripts when
  viewed; auto-transcribe-on-download exists for the *generated* corpus only.
- **Chapter `img` artwork fetch** — `image` is decoded and stored; no UI yet.
- **Generated-chapter `url`s** — backend-optional; documented in ServerAPISurface.
- **Two transcript-search surfaces** — generated transcripts search from Profile
  (`TranscriptionSegmentFTS`), viewed podcast transcripts from New Search
  (`TranscriptCueIndex`). Unifying them into one surface (and one corpus policy) is a
  deliberate follow-up once both prove out.
