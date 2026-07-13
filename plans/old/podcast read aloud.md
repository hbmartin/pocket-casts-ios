# Read Aloud — text file → TTS episode (design + implementation plan)

## Context

The user wants Pocket Casts (fork `hbmartin/pocket-casts-ios`) to import a **text** file and synthesize it to audio ("Read Aloud"), treating the result like a podcast episode — with a user-selectable TTS backend: (1) iOS built-in synthesis, (2) downloadable on-device AI models, (3) cloud APIs with user-entered keys. v1 ingests .txt/.md only, but the extraction layer must accommodate future PDF/HTML extractors. All product decisions below were resolved with the user across a 6-round design interview (terminology note: the user wrote "STT" but confirmed intent is **TTS**). Deliverable branch: `claude/text-to-speech-backend-design-5il83x`.

## Part 1 — Verification of the uploads claim (user asked; answered)

Claim: "a file added to iCloud Drive / Google Drive / Dropbox appears as an upload."
**Verdict: true with nuance — and truer in this fork than upstream.**

- **Manual paths (upstream behavior)**: Files tab "+" → `UIDocumentPickerViewController(forOpeningContentTypes: FileTypeUtil.supportedUserFileTypes, asCopy: true)` (`podcasts/UploadedViewController.swift:259`; audio/video UTTypes only, `podcasts/FileTypeUtil.swift:81`) browses iCloud Drive/Google Drive/Dropbox via Files-app providers; plus open-in via `CFBundleDocumentTypes` (`public.audio`, Video — `podcasts/podcasts-Info.plist`). Nothing appears automatically; each file is picked/shared, then becomes a `UserEpisode` via `AddCustomViewController` → `UserEpisodeManager.addUserEpisode` (`podcasts/UserEpisodeManager.swift:9`). Cloud storage/sync of those files is the Plus-gated part.
- **Auto path (this fork)**: `PocketCastsFileSync` module + `FileSyncCoordinator` (behind `FeatureFlag.fileSync`) watches a sync folder (iCloud ubiquity folder by default, custom folder via security-scoped bookmark); `UploadsScanner` auto-discovers supported files → they appear as uploads with provisional→canonical (content-hash) identity. So drop-file-in-folder → appears-as-upload IS this fork's behavior for the watched folder.

## Part 2 — Shared understanding (all interview decisions, final)

| #    | Decision         | Resolution                                                   |
| ---- | ---------------- | ------------------------------------------------------------ |
| 1    | Synthesis timing | **Eager**: full audio generated at import; output is a normal local audio file (existing playback/effects/sync untouched). Progressive playback = possible v2 |
| 2    | Data model       | **UserEpisode + local-only sidecar tables** (source docs + generations). **New episode per (re)generation**; N generations per source doc |
| 3    | Backends         | Built-in `AVSpeechSynthesizer` (no Personal Voice in v1) · Local model **catalog**, download-on-demand, **two runtimes: sherpa-onnx + MLX** · API presets **OpenAI, ElevenLabs, Google Cloud TTS, Deepgram Aura** + **custom OpenAI-compatible endpoint** (AssemblyAI rejected — STT-only) |
| 4    | Selection        | Global default backend+voice in settings + per-import override |
| 5    | GPL risk         | espeak-ng (GPL-3.0) phonemization → local backend behind its **own flag**, disabled in release until GPL-free phonemization spike + legal review clears |
| 6    | Entry points     | Files "+" picker · open-in/share for text types · paste/type compose screen · App Intent/Siri Shortcut — all canonicalize into one pipeline |
| 7    | File types v1    | **.txt + .md** (Markdown stripped for narration, headings → paragraph breaks/future chapters); UTF-8 + BOM/legacy sniffing; extractor registry keyed by UTType for future PDF/HTML |
| 8    | Language         | NLLanguageRecognizer detect → non-blocking mismatch hint + preselect matching voice where available |
| 9    | Backgrounding    | Best-effort: chunked checkpoint/resume (never lose completed chunks) + backgroundTask grace + BGProcessingTask + background URLSession (models now; API calls Phase B.2) |
| 10   | API cost guard   | Confirmation with **char count + estimated audio duration only** (no dollar estimates) |
| 11   | Source text      | Retained permanently; themed reading screen ("View Original Text"); player-transcript time-sync = stretch |
| 12   | Previews         | Only where free: built-in/local on-device sample; ElevenLabs `preview_url`; none for OpenAI/Deepgram/Google v1 |
| 13   | Model downloads  | Wi-Fi by default + per-download cellular override; SHA-256 verified |
| 14   | Naming / IA      | **"Read Aloud"**; own settings screen under Profile → Settings (sibling of Files) |
| 15   | Gating           | **Free** (mirrors Files precedent; cloud sync of generated audio remains Plus automatically). Keys in Keychain |

Constraints: no PocketCastsServer protobuf changes; provenance never syncs; Swift 6.3 strict concurrency (min iOS 26).

## Part 3 — Implementation plan

### 3.1 New SPM target `PocketCastsReadAloud` (in `Modules/Package.swift`)

Library target + test target (deps: PocketCastsDataModel, PocketCastsUtils; strict-concurrency settings; added to the `podcasts` Xcode-target deps ~line 262). No UIKit/SwiftUI in the module (mirrors `PocketCastsFileSync`). sherpa-onnx/MLX deps enter the graph **only in Phase C** (pinned versions — semgrep forbids `branch:`).

Structure: `Public/` (`ReadAloudManager` facade, `ReadAloudDependencies`, `ReadAloudError`, `GenerationEvents`) · `Extraction/` · `Chunking/` · `Synthesis/` (`BuiltIn/`, `API/`, `Local/`) · `Queue/` · `Assembly/`.

Core types (Sendable throughout):
- `ExtractedDocument { suggestedTitle, blocks: [Block(kind: paragraph|heading, text, level)], characterCount, detectedLanguage }`
- `protocol TextExtractor { supportedTypes: [UTType]; extract(data:filename:) throws -> ExtractedDocument }` + `TextExtractorRegistry` (v1 conformers: `PlainTextExtractor` with `TextEncodingSniffer` (BOM→UTF-8→NSString legacy sniff), `MarkdownExtractor` (strip syntax, code fences dropped, links→text, headings→blocks)). Future PDF/HTML = one more conformer.
- `protocol SpeechSynthesisBackend { id; capabilities: BackendCapabilities (supportsFreePreview, requiresAPIKey, requiresConfirmationBeforeGeneration, maxCharactersPerRequest, maxConcurrentRequests); availableVoices(); synthesize(chunk:voice:settings:into:) async throws -> AudioSegment; previewSample(voice:); estimate(characterCount:settings:) }`
- `SynthesisVoice { id, name, language, qualityLabel?, previewURL? }`
- `TextChunker` — per block `NLTokenizer(unit: .sentence)`, greedy pack to ~0.8 × backend max chars; never split sentences (word-boundary fallback for pathological ones); paragraph/heading boundaries always end a chunk; chunks carry `sourceRange` (UTF-16 offsets) for future transcript sync.
- `GenerationQueue` actor — serial generations, per-backend chunk concurrency; after each chunk: write segment + atomically rewrite `CheckpointManifest` (settingsFingerprint = SHA-256 of source hash+backend+voice+settings; mismatch ⇒ restart) + bump DB `completedChunkCount`. API: `enqueue/cancel/retry/resumePending/suspendAfterCurrentChunk/progressEvents() -> AsyncStream`.
- `GenerationWorkspace`: `Documents/read_aloud/work/<generationUuid>/` with don't-backup flag (NOT Caches — purge would kill resume). Sources: `Documents/read_aloud/sources/<uuid>.txt` (backed up). Models: `Documents/read_aloud/models/<runtime>/<modelID>/` (don't-backup).
- `AudioAssembler`: segments (PCM .caf from built-in/local, mp3/aac from APIs — AVAudioFile decodes on read) → mono AAC .m4a 44.1kHz ~64kbps via `AVAudioFile(forWriting:)` + `AVAudioConverter`; ~350ms silence at paragraph starts; returns (url, duration, sizeInBytes). Behind a small protocol (AVAssetWriter fallback if needed).
- `ReadAloudError` taxonomy with stable `code` strings for analytics/DB (unsupportedFileType, documentTooLarge(limit ~500k chars), apiKeyMissing, apiRateLimited(retryAfter), modelChecksumMismatch, checkpointCorrupt, …). Transient errors: 3× exponential backoff per chunk.

**Built-in backend**: private actor owning `AVSpeechSynthesizer`; `write(utterance)` accumulating PCM buffers per chunk into .caf; voices from `AVSpeechSynthesisVoice.speechVoices()` incl. enhanced/premium, **excluding** `.isPersonalVoice`.

**API backends**: `protocol TTSProviderClient { validate; fetchVoices; synthesize }` with injected URLSession (URLProtocol-testable). Five clients: OpenAI (`POST /v1/audio/speech`), ElevenLabs (`/v1/text-to-speech/{voice_id}`, voices list supplies preview_url), Google Cloud TTS (`text:synthesize`, base64 audio), Deepgram Aura (`/v1/speak`), OpenAI-compatible custom (user base URL). `APIProviderConfig` holds provider/baseURL/model/voice — **key lives only in Keychain** (`KeychainHelper`, keys `readAloudApiKey.<provider>`, `kSecAttrAccessibleAfterFirstUnlock`).

**Local backend (Phase C, flag `readAloudLocalModels`)**: `protocol LocalModelRuntime { runtimeID; isSupportedOnThisDevice; load(entry:from:) -> LoadedTTSModel }` with `SherpaOnnxRuntime` + `MLXRuntime` conformers; **runtime-keyed** `ModelCatalog` JSON (bundled `model-catalog.json`, remote-overridable, versioned schema; entries carry license + `phonemizer` metadata driving the GPL gate; per-runtime artifact lists with SHA-256 + byte sizes). `ModelDownloadManager` on background URLSession, Wi-Fi-only default + per-download override.

### 3.2 Data model (PocketCastsDataModel)

Append `SchemaMigration(toVersion: 78)` in `Modules/Sources/PocketCastsDataModel/Private/Managers/Util/DatabaseHelper.swift` (verified current tail: 77):

- `ReadAloudSourceDocument(id, uuid UNIQUE, title, originalFilename, sourceKind 0-3, utType, textPath, characterCount, language, contentHash, addedDate)`
- `ReadAloudGeneration(id, uuid UNIQUE, sourceDocumentUuid, episodeUuid NULL, backendKind 0-2, runtimeID, modelID, provider, voiceID, voiceName, languageCode, rate, state 0-7, chunkCount, completedChunkCount, errorCode, errorDetails, createdDate, completedDate, outputDuration, outputSizeInBytes)` + indexes on sourceDocumentUuid/episodeUuid/state.

No syncStatus, no journal hooks — deliberately local-only. Records as `@GRDBRecord` Sendable structs in `Public/ReadAloud/`; `ReadAloudDataManager` modeled on `BookmarkDataManager` (add/find/update/generationsPendingResume/detachEpisode/cascade delete); exposed as `DataManager.readAloud`; `ReadAloudRepository` protocol + mock in `PocketCastsDataModelTesting` (mirrors `UserEpisodeRepository`).

### 3.3 Materialization (completed generation → episode)

In app-side coordinator: new `episodeUuid` → `DownloadManager.shared.addLocalFile(url:uuid:)` (`podcasts/DownloadManager.swift:232`) → `UserEpisodeManager.addUserEpisode(uuid:title:localFileUrl:artwork:nil,color:fileSize:duration:)` (`podcasts/UserEpisodeManager.swift:9` — sets fileType/downloaded, saves, FileSync import when enabled, honors auto-Up-Next) → update generation row (episodeUuid, .completed, duration/size) → delete workspace → post the refresh notification `UploadedViewController` observes. Observe episode-deletion notification → `detachEpisode` (source doc + provenance survive). Plus-gated cloud upload continues to apply automatically since the result is a plain UserEpisode.

### 3.4 UI (in `podcasts/ReadAloud/`, SwiftUI + PCHostingController, themed like `FileSyncSettingsView`)

1. **Files "+"** (`UploadedViewController.swift`): flag-gated — picker types = existing audio/video **+ text types via app-side `ReadAloudFileTypes`** (do NOT touch `FileTypeUtil.supportedUserFileTypes`; FileSync's `isSupportedUserFileType` depends on it, `FileSyncCoordinator.swift:32`); `didPickDocumentsAt` branches text → import sheet, else existing `AddCustomViewController`. Options menu gains "Read Aloud…" compose entry. Active-generation banner (pattern: `FileSyncBanner`) → generations screen.
2. **Import sheet** `ReadAloudImportView(+ViewModel/+ViewController)`: editable title (from suggestedTitle), char count, backend picker (default + per-import override), voice picker grouped by language with preview-where-free, language-mismatch footnote, rate control, color swatches; API mode swaps Generate for a confirm stage (char count + "About N minutes of audio"). Enqueue → dismiss → banner.
3. **Compose screen** `ReadAloudComposeView`: title + TextEditor + live char count → same confirm flow (`sourceKind = .pasted`).
4. **Generations screen** `ReadAloudGenerationsView`: progress rows (ProgressView from completed/chunkCount), failed+Retry, completed→episode link, swipe-cancel. **No placeholder episode cells** (fake UserEpisodes would leak into Up Next/FileSync).
5. **Settings screen** `ReadAloudSettingsView` pushed from `SettingsViewController` (new flag-gated row beside `case fileSync`, line 12): default backend/voice; built-in voice list (+ footnote re downloading enhanced voices in iOS Settings); per-provider config (`ReadAloudProviderConfigView`: base URL editable for custom only, model, SecureField key, Validate button); local-model catalog with download/delete/progress/Wi-Fi toggle (sub-flag only); storage section (source docs list, usage); generations link. Defaults in plain UserDefaults via `podcasts/Settings.swift` statics (NOT synced appSettings).
6. **Reading screen** `ReadAloudReadingView`: themed rendering of `ExtractedDocument.blocks`, font-size control; entry: "View Original Text" row in `UserEpisodeDetailViewController` when a generation row exists + from source list. TranscriptModel time-sync = Phase D stretch (transcripts today are server/podcast-wired via `ShowInfoCoordinator` — don't force it in v1).
7. **Previews** `ReadAloudVoicePreviewPlayer` (@MainActor): built-in `speak()` sample; local `previewSample`; ElevenLabs AVPlayer on preview_url; audio-session ducking; capability-driven visibility.

### 3.5 Entry-point wiring

- `podcasts-Info.plist`: CFBundleDocumentTypes += `public.plain-text`, `net.daringfireball.markdown` (`LSHandlerRank: Alternate`).
- `AppDelegate+UrlHandling.swift`: `InboundAction.readAloudText(URL)`; route `type.conforms(to: .plainText)` **after** OPML/XML checks; navigate via `NavigationManager` key (mirroring `navigateToAddCustom`). Existing `pktc://import-file/*` JLRoutes funnel makes share-extension files arrive here for free.
- `Share Extension/`: `Info.plist` activation rule += plain-text; `ShareViewController.swift:16` insert `.plainText` into `acceptedTypes` **before** `.data` (the `.data` branch renames files to `opml.opml`); preserve original filename/extension.
- App Intent `CreateReadAloudEpisodeIntent` (text or txt/md file params; `requestConfirmation` with char count when default backend is API; AppShortcut phrase) registered beside `PocketCastsAppIntents.swift`.

### 3.6 Background execution

`ReadAloudCoordinator` (@MainActor, owned by AppDelegate beside `fileSyncCoordinator`): configures queue deps, `resumePending()` on launch; on background with active work — `beginBackgroundTask` grace, expiration → `suspendAfterCurrentChunk()` hopping to MainActor (exact `FileSyncCoordinator.swift:112-129` shape; semgrep rule exists) — and schedules a **BGProcessingTask** (`au.com.shiftyjelly.podcasts.ReadAloud` added to `BGTaskSchedulerPermittedIdentifiers`; registered in `AppDelegate.setupBackgroundRefresh()` ~line 251; `requiresNetworkConnectivity` per backend; handler resumes queue, expiration checkpoints). Model downloads: background URLSession (`DownloadManager.swift:183` pattern). API chunk calls: foreground URLSession within grace in Phase B; background-session file-based uploads as Phase B.2.

### 3.7 Flags, analytics, L10n, semgrep

- Flags: `readAloud` (default non-appStore, like `fileSync`), `readAloudLocalModels` (default false — GPL gate) in `FeatureFlag.swift`.
- Analytics (`AnalyticsEvent.swift`): readAloudGenerationQueued/Completed/Failed/Cancelled/Resumed (backend/provider/source/char_count/error_code — never key material), import/settings/compose/sourceText shown, providerValidated, modelDownloadStarted/Completed/Failed, voicePreviewPlayed, intentInvoked.
- L10n: `read_aloud*` keys in `podcasts/en.lproj/Localizable.strings` (snake_case, positional placeholders) → generated L10n; no LocalizedStringKey (SwiftLint).
- Semgrep: KeychainHelper-only keys; MainActor BG-task expiration; AsyncStream not public mutable subjects; pinned SPM deps; SHA-256 only; append-only migration.

### 3.8 Phasing (each shippable behind flags)

- **A — Foundation + built-in end-to-end**: module, extractors/chunker, migration 78 + managers, queue/manifest/assembler, AVSpeechBackend, coordinator + BG wiring, import/compose/generations/settings-skeleton/reading UI, open-in/share, flags/L10n/analytics.
- **B — API providers**: 5 clients + validation UI + Keychain + confirm stage + ElevenLabs voices/preview + retry/backoff. (B.2: background-session API uploads.)
- **C — Local models**: GPL-free phonemization spike + legal review **first**; then pinned sherpa-onnx + MLX runtimes, catalog + ModelDownloadManager + management UI + local previews.
- **D — Extras**: App Intent polish/AppShortcut, reading-screen polish, remote catalog override, TranscriptModel time-sync spec, headings→chapters exploration.

## Part 4 — Testing & verification

- `Modules/Tests/PocketCastsReadAloudTests`: chunker (sentence integrity, CJK, hard-split), extractors + encoding fixtures (BOM/Latin-1/Windows-1252, markdown edge cases), manifest round-trip/fingerprint-mismatch/corruption, queue with `FakeSynthesisBackend` (cancel, retry/backoff, suspend→resume without re-synthesis), assembler duration ±50ms, catalog decoding, provider clients via URLProtocol stubs (request shape, voice decoding incl. preview_url, 401/429 mapping).
- `Modules/Tests/PocketCastsDataModelTests/ReadAloudDataManagerTests`: migration 78 on fresh + upgraded DBs, CRUD, cascade, pending-resume filter, detachEpisode.
- `PocketCastsTests`: coordinator materialization (episode exists, file placed, row linked — DBTestCase + InMemoryKeychainStore), InboundActionRouter additions (.txt/.md route; XML still OPML; flag-off), intent perform, settings round-trip. Snapshot tests for import sheet + settings screen (themed light/dark; via SnapshotTesting product added to PocketCastsTests, or extract pure views into the module as fallback).
- Manual E2E: build staging → import 20k-char sample.md → verify char count/language hint → generate with built-in voice → kill app at ~50% → relaunch resumes from checkpoint → episode in Files with correct duration; plays/scrubs; View Original Text renders; share/open-in a .txt lands in import sheet; BGTask simulated-launch resumes; API mode confirm shows chars+duration and airplane-mode mid-run pauses then retries without redoing chunks. Finish: `mise run test`, `mise run test:staging`, `mise run check:static`, semgrep, format.

**Critical files**: `Modules/Package.swift` · `Modules/Sources/PocketCastsDataModel/Private/Managers/Util/DatabaseHelper.swift` · new `Modules/Sources/PocketCastsReadAloud/**` · `podcasts/UserEpisodeManager.swift` · `podcasts/UploadedViewController.swift` · `podcasts/AppDelegate+UrlHandling.swift` + `AppDelegate.swift` · `podcasts/SettingsViewController.swift` · `podcasts/podcasts-Info.plist` · `Share Extension/ShareViewController.swift` + plist · new `podcasts/ReadAloud/**` · `FeatureFlag.swift` · `Localizable.strings` · `AnalyticsEvent.swift`.