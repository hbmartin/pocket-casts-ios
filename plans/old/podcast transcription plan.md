# Diarized Podcast Transcription (3 engine modes)

## Context

Pocket Casts today only *displays* transcripts fetched from podcast RSS feeds or Pocket Casts' servers — there is no on-device speech-to-text, no speaker labels beyond what a feed happens to embed, no local persistence of transcript text, and no cross-episode search. This feature adds **user-triggered (and per-podcast automatic) diarized transcription** — speech-to-text with "who spoke when" — stored locally so episodes become referenceable and full-text searchable. Three user-selectable engine modes:

1. **iOS built-in** — iOS 26 `SpeechAnalyzer`/`SpeechTranscriber` (min deployment target IS 26.0, no availability gating). Apple ships no diarization, so speaker labels come from a shared local diarizer stage.
2. **Local downloaded models** — WhisperKit CoreML ASR + SpeakerKit diarizer (argmax-oss-swift SPM, one package for both), with FluidAudio (Parakeet TDT v3 + pyannote) as a user-selectable alternate stack later.
3. **Remote APIs, user-entered keys** — AssemblyAI, Deepgram (URL-based: provider fetches `episode.downloadUrl`, no upload), then OpenAI `gpt-4o-transcribe-diarize`, ElevenLabs Scribe, Google Gemini (file-upload based).

User decisions: both local stacks (WhisperKit primary), all five remote providers, dedicated cross-episode search screen (Profile tab), auto-transcribe-on-download per-podcast opt-in included.

**Pipeline**: `ASR (text+timestamps) → diarization (speaker turns) → merge/align → WebVTT with <v Speaker N> tags`. Remote providers return diarized output natively and skip stages 2–3. Everything lands behind a new `FeatureFlag.diarizedTranscription` (default `BuildEnvironment.current != .appStore`). No paid gating (none exists in this fork). No sync (device-local: no sync_status, no FileSyncJournal writes).

## Why WebVTT as the canonical artifact

`TranscriptModel.makeModel(from:format:)` (`podcasts/TranscriptModel.swift:41`) already parses VTT `<v Speaker>` voice tags into speaker-header runs with the `.transcriptSpeaker` attribute, and `TranscriptFilter` strips the tags from cue text at render. **Serializing our output as VTT means the entire existing render/search/highlight/tap-to-seek stack works unchanged.** Bonus over server transcripts: we transcribe the exact audio file the user plays, so timestamps align natively — skip `FingerprintTimingManager` entirely for local transcripts.

## Architecture / module split

Hard rule: **`Modules/Sources/PocketCastsTranscription` (new SPM target) holds everything that compiles with system frameworks only** — domain types, protocols, merge algorithm, VTT serializer, remote provider adapters (pure URLSession), `AppleSpeechEngine` (wrapped `#if os(iOS)` so host-side `swift test` still builds). Depends only on `PocketCastsUtils`.

**WhisperKit/SpeakerKit/FluidAudio products must NOT be dependencies of this module** (they'd break the macOS-host test target). They attach only to `XcodeTarget_podcasts` in `Modules/Package.swift` (~line 262), and their engine wrappers live in the app layer `podcasts/Transcription/` — along with the queue manager (needs DataManager/DownloadManager/UIKit BG tasks) and all UI.

**DB records + DAO live inside `PocketCastsDataModel`** (`GRDBQueue` is internal there), exposed as `DataManager.sharedManager.transcriptions` (BookmarkDataManager pattern).

### Core types & protocols (module)

```swift
struct TranscriptWord   { text, start, end }
struct ASRSegment       { text, start, end, words: [TranscriptWord]? }
struct SpeakerTurn      { speakerId, start, end }
struct DiarizedCue      { speaker: String?, text, start, end }
struct DiarizedTranscript { cues, language: String?, speakerCount, engineDescription }
enum TranscriptionEngineMode: Int32 { appleBuiltIn = 0, localModel = 1, remoteProvider = 2 }

protocol SpeechToTextEngine: Sendable {
    var id: String { get }
    func prepare(locale: Locale?, progress: @escaping @Sendable (Double) -> Void) async throws
    func transcribe(audioFile: URL, language: String?, progress: ...) async throws -> [ASRSegment]
}
protocol SpeakerDiarizing: Sendable {
    func prepare(progress: ...) async throws
    func diarize(audioFile: URL, maxSpeakers: Int?, progress: ...) async throws -> [SpeakerTurn]
}

enum RemoteAudioSource { case publicURL(URL); case fileUpload(URL, mimeType: String) }
enum SubmitOutcome { case job(RemoteJobHandle); case completed(DiarizedTranscript) }  // sync providers (Deepgram/ElevenLabs) return .completed directly — no adapter-side state
protocol RemoteTranscriptionProvider: Sendable {
    var id: String { get }; var displayName: String { get }; var supportsPublicURL: Bool { get }
    func submit(source: RemoteAudioSource, language: String?, apiKey: String) async throws -> SubmitOutcome
    func poll(handle: RemoteJobHandle, apiKey: String) async throws -> RemoteJobStatus
}
```

`TranscriptionError` enum: `invalidAPIKey` (401/403), `quotaExceeded` (402/429), `audioTooLarge(limitMB:)`, `unsupportedAudio`, `remoteJobFailed(String)`, `networkUnavailable`, `notDownloaded`, `audioUnreadable`, `modelDownloadFailed`, `engineFailure`, `thermalThrottled`, `cancelled`.

### Merge algorithm — `SpeakerAligner.align(segments:turns:options:) -> [DiarizedCue]` (pure, heavily unit-tested)

1. Units = words when word timings exist, else segments.
2. Speaker per unit = turn with maximal temporal overlap; ties → earlier turn start; zero overlap → nearest turn midpoint within `gapTolerance` (1.0s), else inherit previous speaker, else nil.
3. Group consecutive same-speaker units into cues; break at sentence-final punctuation + pause > 0.75s, at 200 chars, or 15s.
4. Normalize speaker IDs to `"Speaker 1"…N` by first appearance.
5. ≤1 distinct speaker → emit `speaker = nil` (serializer omits `<v>`; clean monologue display).

`VTTSerializer`: `WEBVTT` header, `HH:MM:SS.mmm`, escape `&<>`, clamp zero-length cues (+10ms). Must round-trip through `TranscriptModel.makeModel(from:format:.vtt)` (dedicated test).

### Storage

- Artifact: `Documents/generated_transcripts/{episodeUuid}.vtt` — own dir (NOT inside podcasts_non_backed_up, transcripts outlive deleted audio), `isExcludedFromBackup = true`.
- Migration **toVersion: 78** in `DatabaseHelper.swift` (append to `migrations`; do NOT touch `createCurrentSchema` — fresh installs run baseline 73 + all migrations):

```sql
CREATE TABLE EpisodeTranscription (
    episodeUuid TEXT PRIMARY KEY, podcastUuid TEXT,
    status INTEGER NOT NULL DEFAULT 0, engineMode INTEGER NOT NULL DEFAULT 0,
    provider TEXT, modelId TEXT, language TEXT,
    createdAt REAL NOT NULL DEFAULT 0, updatedAt REAL NOT NULL DEFAULT 0,
    durationSecs REAL NOT NULL DEFAULT 0, speakerCount INTEGER NOT NULL DEFAULT 0,
    speakerNames TEXT, errorMessage TEXT, remoteJobId TEXT, filePath TEXT );
CREATE INDEX episode_transcription_status ON EpisodeTranscription (status);
CREATE VIRTUAL TABLE TranscriptionSegmentFTS USING fts5(
    text, episodeUuid UNINDEXED, podcastUuid UNINDEXED, segmentIndex UNINDEXED,
    startTime UNINDEXED, speaker UNINDEXED, tokenize = 'unicode61 remove_diacritics 2');
```

- FTS-only segments (plain FTS5 stores values; `DELETE WHERE episodeUuid=?` works; `snippet()`/`bm25()` power search). Model `EpisodeTranscriptionRecord` via `@GRDBRecord(table:)` (copy `NetworkDataUsageRecord.swift`); `TranscriptionStatus: Int32 { queued, processing, completed, failed, cancelled }`.
- `TranscriptionDataManager` (struct + GRDBQueue): `find`, `upsert`, `setStatus`, `setRemoteJobId`, `setSpeakerNames`, `pendingRecords`, `completedCount`, `delete` (row+FTS+artifact hook), `replaceSegments` (DELETE+batch INSERT in one write), `searchSegments(query:limit:)` with `sanitizeFTSQuery` (quote tokens, `*` on last token — test hostile input).
- Speaker renames: `speakerNames` JSON on the row (`{"Speaker 1":"Alice"}`), applied by string substitution on raw VTT before parse. VTT file stays canonical; no FTS rebuild; renamed names not FTS-searchable (accepted v1 tradeoff).

### Queue manager (app layer, actor)

`TranscriptionQueueManager` — serial drain, one job at a time. States: `queued → preparingModel(Double) → transcribing(Double) → diarizing(Double) → saving → completed | failed(TranscriptionError) | cancelled`. DB `status` column is the durable record: `restorePendingJobs()` on launch re-enqueues `queued`, resets crashed `processing` → `queued` (or resumes polling when `remoteJobId` set). Progress fan-out: `NotificationCenter.postOnMainThread`, 1/sec throttle (DownloadProgressManager pattern), new `Constants.Notifications.transcriptionProgress` / `episodeTranscriptionCompleted`. Cancellation: cancel running Task; engines call `Task.checkCancellation()` between chunks/polls. `beginBackgroundTask` around in-flight job (FileSyncCoordinator.swift:114 pattern — end in BOTH expiration handler and completion; semgrep rule enforces). BGProcessingTask `au.com.shiftyjelly.podcasts.Transcription` (`requiresExternalPower = true`) drains queue overnight — plist `BGTaskSchedulerPermittedIdentifiers` addition (`UIBackgroundModes` already has `processing`). Thermal check between stages: `.serious`/`.critical` → leave queued for the charging pass. Engine/provider selection via `TranscriptionEngineFactory` (single extension point across phases).

## Phase 1 — Foundation + Apple engine end-to-end (shippable)

Downloaded episode → Generate → SpeechTranscriber → aligner (empty turns → untagged cues) → VTT → renders in existing UI with native seek → FTS rows written.

**New (module)**: `TranscriptionTypes.swift`, `SpeechToTextEngine.swift`, `SpeakerAligner.swift`, `VTTSerializer.swift`, `AppleSpeechEngine.swift` (`#if os(iOS)`; `AssetInventory.assetInstallationRequest` → `downloadAndInstall()` sampling `progress.fractionCompleted` @250ms; locale: supported-locales check → settings override → device locale; file analysis via `SpeechAnalyzer.analyzeSequence(from: AVAudioFile)`, collect `results` with `audioTimeRange`).

**New (DataModel)**: `Public/Transcription/EpisodeTranscriptionRecord.swift`, `TranscriptionDataManager.swift`; migration 78 in `Private/Managers/Util/DatabaseHelper.swift`; `public let transcriptions` on `DataManager` (~line 29 + init ~101).

**New (app)**: `podcasts/Transcription/TranscriptionArtifactStore.swift` (write/read VTT, `applyingSpeakerNames`, delete), `TranscriptionQueueManager.swift`, `TranscriptionEngineFactory.swift`, `TranscriptionSettingsView.swift` + ViewModel (FileSyncSettingsView template: `@MainActor ObservableObject`, `List` sections, `AppTheme.color(for:theme:)`; Phase 1 = mode picker + language override only).

**Modified**:
- `Modules/Package.swift` — new library/target/testTarget (`strictConcurrencyTestableSettings`), add product to `XcodeTarget_podcasts`.
- `FeatureFlag.swift` — `case diarizedTranscription` (auto-appears in BetaMenu).
- `podcasts/Constants.swift` — 2 notification names + `Values.transcriptionTaskId`.
- `podcasts/podcasts-Info.plist` — BG task id (line ~5).
- `podcasts/AppDelegate.swift` — register BGProcessingTask in `setupBackgroundRefresh()` (line 251); `scheduleTranscriptionProcessingIfNeeded()`; `restorePendingJobs()` post-launch.
- `podcasts/TranscriptManager.swift` — new `TranscriptSource { automatic, podcastProvided, localGenerated }` + `sourcePreference`; top of `loadTranscript()` (line 49): flag on → check `transcriptions.find(episodeUuid:)` → completed → read+rename-substitute VTT → `TranscriptModel.makeModel` → return (parse failure falls through to existing flow). Track `hasLocalTranscription`/`hasPodcastProvidedTranscripts`/`isDisplayingLocalTranscription`.
- `podcasts/TranscriptViewController.swift` — **additive only, enumerated functions** (file is refactor-sensitive): Generate button in error state (downloaded episodes; enqueue + progress state); observe the two notifications; on local display skip `FingerprintTimingManager.prepareForCurrentEpisode()`, use raw playback time in `updateTranscriptPosition()` (line 865, factor highlight-paint into shared helper) and direct `seekTo` in `transcriptTapped` (line 993); source-switcher `UIMenu` button (podcast vs generated, delete, rename [P2]).
- `podcasts/TranscriptErrorView.swift` — `showGenerateButton(title:action:)`.
- `podcasts/Episode/EpisodeDetailViewController+Actions.swift` — OptionsPicker action "Generate Transcript" (flag + downloaded + no record).
- `podcasts/Settings.swift` — UserDefaults accessors (localFeedIngestEnabled pattern): `transcriptionEngineMode`, `transcriptionLanguageOverride`, `transcriptionWhisperModel`, `transcriptionLocalStack`, `transcriptionAllowCellularModelDownloads`, `transcriptionMaxSpeakers` (0=auto), `transcriptionRemoteProvider`.
- `podcasts/Analytics/AnalyticsEvent.swift` (~line 815): `transcriptionGenerateTapped/Started/Completed/Failed/Cancelled/SourceSwitched/SpeakerRenamed/SearchShown/SearchResultTapped/SettingsShown`.
- `podcasts/en.lproj/Localizable.strings` + SwiftGen regen; `podcasts/SettingsViewController.swift` 4-touch row (case/visible/display/selectRow → `PCHostingController`).

**Tests**: `Modules/Tests/PocketCastsTranscriptionTests/` SpeakerAlignerTests (fixtures: overlap, ties, gap tolerance, merge caps, single-speaker→nil, empty turns), VTTSerializerTests (golden, escaping, clamp); `Modules/Tests/PocketCastsDataModelTests/TranscriptionDataManagerTests` (in-memory GRDB: migration, upsert, FTS search+snippet, replaceSegments idempotence, sanitizer vs hostile input); `PocketCastsTests/Tests/Transcription/` VTTRoundTripTests (needs app-target TranscriptModel), TranscriptionQueueManagerTests (mock engine: transitions, cancel, crash-restore, thermal).

## Phase 2 — Local models + diarization for modes 1 & 2

- `Modules/Package.swift`: `.package(url: "https://github.com/argmaxinc/argmax-oss-swift", …)` — **confirm exact repo URL/product names at integration time**; products only on `XcodeTarget_podcasts`.
- App layer: `WhisperKitEngine.swift` (**actor** — WhisperKit instance non-Sendable; `WhisperKit.download(variant:progressCallback:)` then `WhisperKit(WhisperKitConfig(modelFolder:))`; `@preconcurrency import` fallback), `SpeakerKitDiarizer.swift` (~10MB model; also attached to mode 1 → Apple ASR + SpeakerKit = diarized built-in mode), `WhisperKitModelStore.swift` (list/size/delete; cellular gate via `NetworkUtils.shared.isConnectedToUnexpensiveConnection()`).
- Alternate stack: `ParakeetEngine.swift` + `FluidAudioDiarizer.swift` behind `Settings.transcriptionLocalStack` (`whisperKit` default | `fluidAudio`) — same protocols, pure adapter work. Can trail as 2b.
- Settings UI: model picker (tiny/base/small/large-v3-turbo + sizes + downloaded badge + delete), disk usage row, cellular toggle, stack picker, max-speakers stepper.
- Speaker rename: `SpeakerRenameView.swift` sheet from source menu → `setSpeakerNames` → refresh notification → re-render.
- Tests: word-level aligner fixtures, rename round-trip, model store with temp dirs.

## Phase 3 — Remote providers

**3a URL-based**: `AssemblyAIProvider` (POST `/v2/transcript` `{audio_url, speaker_labels:true}`, header `authorization`; poll 3s ×1.5 backoff cap 30s, overall 30min; map `utterances[]`), `DeepgramProvider` (POST `/v1/listen?diarize=true&punctuate=true&utterances=true&smart_format=true` `{url}`, `Authorization: Token`; synchronous → `SubmitOutcome.completed`). Works for **non-downloaded** episodes (`supportsPublicURL` + parseable `episode.downloadUrl`).

**3b Upload-based**: shared `AudioTranscodeHelper` (AVAssetWriter → mono AAC m4a ~32–48kbps). `OpenAIProvider` (`gpt-4o-transcribe-diarize`, multipart, 25MB cap — episodes whose transcode exceeds it fail `.audioTooLarge` with "try AssemblyAI" guidance; no chunking in v1 since cross-chunk speaker IDs don't stabilize). `ElevenLabsProvider` (Scribe, multipart, diarize=true, sync → `.completed`). `GeminiProvider` (Files API resumable upload → poll file state ACTIVE → `generateContent` on `gemini-2.5-flash` with `responseSchema` JSON `{segments:[{speaker,start,end,text}]}`, header `x-goog-api-key`; enforce monotonic timestamps post-parse — model-generated stamps drift on long audio; document as approximate).

**App-side**: `TranscriptionKeyStore.swift` — `KeychainHelper.save(string:key:"transcription.apikey.<providerId>", accessibility: kSecAttrAccessibleAfterFirstUnlock)`; **deliberately NOT cleared on logout** (user's own provider keys — comment this). Per-provider consent sheet on first enqueue (UserDefaults bool; copy covers URL-vs-upload variants). Persist `remoteJobId` post-submit; `restorePendingJobs` resumes polling. Settings: provider picker, `SecureField` per provider, validate-key button.

**Tests**: URLProtocol fixtures per provider (happy path, 401 → `.invalidAPIKey`, job-failed), Deepgram/ElevenLabs sync mapping, Gemini schema parse + monotonic fix, backoff schedule.

## Phase 4 — Auto-transcribe + cross-episode search + polish

- **Auto-transcribe on download** (user-selected): `@ModifiedDate public var autoTranscribe: Bool = false` in `Modules/Sources/PocketCastsDataModel/Public/Model/PodcastSettings.swift` (verify JSON decode default for old payloads); toggle row in `podcasts/Podcasts/Podcast Page/Podcast Settings/PodcastSettingsViewController(+Table).swift`; new `TranscriptionAutoRunCoordinator.swift` — singleton observing `Constants.Notifications.episodeDownloaded` (clone `EpisodeLoudnessScanner.swift:23` shape): flag on + podcast opted in + no existing record + **local modes only** → enqueue.
- **Search screen**: `TranscriptSearchView/ViewModel` — debounced field → `transcriptions.searchSegments` off-main → grouped by episode (titles via DataManager), snippet + timestamp rows → tap plays from time (clone `playBookmark`, `PlaybackManager.swift:2531-2561`). Entry: `ProfileViewController.swift` `TableRow` (line 75) + `navigateToRow` (line 358), gated flag + `completedCount() > 0`.
- Polish: video episodes — extract audio track to temp CAF (AVAssetReader) before engines; storage accounting row; share with speaker names; snapshot tests (`Modules/Tests/SnapshotTests`); delete-artifact action.

## Key patterns to follow / avoid

- Reuse: `EpisodeLoudnessScanner` (offline decode/trigger shape), `DownloadProgressManager` (throttled progress), `BookmarkDataManager`/`NetworkDataUsageRecord` (DAO/macro), `FileSyncSettingsView` (settings page), `playBookmark` (seek deep-link), `KeychainHelper` + `InMemoryKeychainStore` (keys/tests), `OptionsPicker` (actions/consent).
- Swift 6 strict concurrency everywhere; progress crosses to UI only via main-thread NotificationCenter; view models `@MainActor` re-querying the actor.
- Don't: touch `createCurrentSchema`; write FileSyncJournal entries; clear provider keys on logout; deep-rewrite `TranscriptViewController` (enumerated additive edits only); add SPM ML deps to the transcription module target.
- L10n snake_case keys + positional placeholders; themed colors via `AppTheme.color(for:theme:)`; new Semgrep rule candidates: none required up front (revisit if key-handling bugs emerge).

## Verification

1. `mise run format` && `mise run check:static` (SwiftLint/semgrep — bg-task rule, natural alignment).
2. Module tests: `ONLY_TESTING=PocketCastsTranscriptionTests mise run test:staging` (also runs host-side via `swift test` in Modules/); DAO: `ONLY_TESTING=PocketCastsDataModelTests mise run test:staging`; app: `ONLY_TESTING=PocketCastsTests/Tests/Transcription mise run test:staging`. (Requires macOS/Xcode — in a Linux session, push and rely on CI.)
3. Manual sim script: enable flag in Beta menu → download short episode → player shelf → Transcript → Generate → progress → diarized render (speaker headers smaller font) → tap cue seeks exactly → kill app mid-job → relaunch resumes → rename speaker → source menu switch on an episode with podcast-provided transcript → Profile → Search Transcripts → result tap plays at timestamp → settings: mode switches, Wi-Fi-only model download refusal on cellular, API key entry + consent sheet on first remote job.
4. Each phase lands independently behind the flag; Phase 1 must land migration 78 + FTS writes so later phases need no schema change.
