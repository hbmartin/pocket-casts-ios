# Feature Flag Audit

Phase 0 deliverable of [MODERNIZATION.md](../MODERNIZATION.md): a retirement-planning audit of every
case in `Modules/Sources/PocketCastsUtils/Feature Flags/FeatureFlag.swift`, generated 2026-06-11 from
the actual definitions and call sites (`grep` across `podcasts/`, `Modules/`, `WidgetExtension/`,
excluding the definition file).

**No flag is retired by this document.** Every flag has a live remote kill-switch key (the
`remoteKey` fallthrough derives one from the case name), so each retirement needs sign-off from
whoever owns remote config: confirm the key is not actively targeted, then fill in the Sign-off
column and remove the flag in a small PR (inline the `true` branch, delete the `false` branch and
the enum case).

Assessment meanings:

- **dead — remove enum case**: zero call sites; the flag gates nothing. Removing the case is pure
  dead-code deletion (still confirm remote config does not target the key).
- **candidate**: defaults unconditionally to `true`, few call sites, not playback-adjacent. Retire in
  batches of 3–5 related flags.
- **candidate (wide adoption)**: same signals but many call sites; retire one per PR.
- **keep**: default is `false` or conditional (build-environment or staged-rollout logic) — still an
  active decision point.
- **defer-playback**: any call site is in the playback engine (PlaybackManager, DefaultPlayer,
  EffectsPlayer, AudioReadTask, PlaybackQueue, …). Deferred to Phase 5 regardless of other signals.

| Flag | Default | Usages | Used in | Assessment | Sign-off |
|---|---|---|---|---|---|
| ~~`guestListsNetworkHighlightsRedesign`~~ | true | 0 | — | dead — removed | ✅ removed 2026-06-27 |
| ~~`refreshPlaylistOnSubscriptions`~~ | true | 0 | — | dead — removed | ✅ removed 2026-06-27 |
| ~~`smartCategories`~~ | true | 0 | — | dead — removed | ✅ removed 2026-06-27 |
| ~~`syncStats`~~ | true | 0 | — | dead — removed | ✅ removed 2026-06-27 |
| `activateAudioSessionForRoutePicker` | true | 1 | NowPlayingPlayerItemViewController+Shelf.swift | candidate | |
| `checkProtectedDataBeforeMigration` | true | 1 | AppDelegate+Defaults.swift | candidate | |
| `detectTruncatedBackgroundSyncDownloads` | true | 1 | BackgroundSyncManager+URLSession.swift | candidate | |
| `encourageAccountCreation` | true | 1 | InformationalBannerViewCoordinator.swift | candidate | |
| `episodeDetailTranscript` | true | 1 | EpisodeDetailViewController+ShowNotes.swift | candidate | |
| `listeningHistorySearch` | true | 1 | ListeningHistoryViewController.swift | candidate | |
| `logMainThreadDatabaseAccess` | true | 1 | MainThreadDBReporter.swift | candidate | |
| `manageDownloadedEpisodes` | true | 1 | ManageDownloadsCoordinator.swift | candidate | |
| `newOnboardingRecommendationChanges` | true | 1 | LoginCoordinator.swift | candidate | |
| `podcastBookmarksInline` | true | 1 | PodcastViewController.swift | candidate | |
| `retryWithoutUserAgent` | true | 1 | DownloadManager+URLSessionDelegate.swift | candidate | |
| `shareTranscripts` | true | 1 | TranscriptViewController.swift | candidate | |
| `skipSyncWhenProtectedDataUnavailable` | true | 1 | UpNextSyncTask.swift | candidate | |
| `streamingCustomSessionConfiguration` | true | 1 | MediaExporterResourceLoaderDelegate.swift | candidate | |
| `useBackgroundQueueForStreamingCallback` | true | 1 | MediaExporterResourceLoaderDelegate.swift | candidate | |
| `useDescriptiveActionAttributedTextView` | true | 1 | DescriptiveActionView.swift | candidate | |
| `useMimetypePackage` | true | 1 | DownloadManager+URLSessionDelegate.swift | candidate | |
| `cleanUpTmpFiles` | true | 2 | DownloadedFilesViewController.swift | candidate | |
| ~~`concurrentDatabaseReads`~~ | true | 0 | — | removed (data-layer track B0 — DatabasePool concurrent reads are the only path; ValueObservation depends on this) | ✅ code removed 2026-07-12; retire remote `concurrent_database_reads` key server-side |
| `customPlaybackSettings` | true | 2 | EffectsViewController.swift, PodcastEffectsViewController+Ta | candidate | |
| `downloadsThreadSafeCache` | true | 2 | DownloadManager.swift | candidate | |
| `enableLocalizationHeaders` | true | 2 | AppDelegate.swift, Settings.swift | candidate | |
| `markAllSyncedInSingleStatement` | true | 2 | EpisodeDataManager.swift | candidate | |
| `searchPredictive` | true | 2 | SearchResultsViewController.swift, Settings.swift | candidate | |
| `statsHeatmap` | true | 2 | StatsViewController.swift | candidate | |
| `suggestedFolders` | true | 2 | FoldersCoordinator.swift | candidate | |
| `displayErrorsOnPlayer` | true | 3 | MainTabBarController.swift, NowPlayingPlayerItemViewControll | candidate | |
| `releaseMediaExporterWhenNoLongerActive` | true | 3 | DownloadManager.swift | candidate | |
| `useCellularNetworkApis` | true | 3 | DownloadManager.swift, NetworkUtils.swift | candidate | |
| `playlistCacheInvalidation` | true | 4 | NewPlaylistCell.swift, PlaylistsViewController.swift | candidate | |
| `playlistDataCacheBeforeQuery` | true | 4 | NewPlaylistCell.swift, PlaylistMetadataLoader.swift | candidate | |
| `recommendations` | true | 4 | DiscoverServerHandler.swift, PodcastDetailsTabView.swift, Po | candidate | |
| `onlyMarkPodcastsUnsyncedForNewUsers` | true | 6 | AuthenticationHelper.swift, SyncSigninView.swift, SyncSignin | candidate (wide adoption — retire in its own PR) | |
| `autoDownloadOnSubscribe` | true | 8 | AppDelegate+Defaults.swift, DownloadSettingsViewController.s | candidate (wide adoption — retire in its own PR) | |
| `generatedTranscripts` | true | 8 | ShowInfoCoordinator.swift, TranscriptViewController.swift | candidate (wide adoption — retire in its own PR) | |
| `podcastFeedUpdate` | true | 8 | PodcastViewController+NetworkLoad.swift, PodcastViewControll | candidate (wide adoption — retire in its own PR) | |
| `searchImprovements` | true | 8 | PCSearchBarController+Search.swift, PredictiveList.swift, Se | candidate (wide adoption — retire in its own PR) | |
| `podcastsSortChanges` | true | 10 | FolderViewController.swift, HomeGridDataHelper.swift, Podcas | candidate (wide adoption — retire in its own PR) | |
| ~~`liquidGlass`~~ | true | 0 | — | removed (iOS 26 min-target migration) | ✅ code removed 2026-07-06; retire remote `liquid_glass` key server-side |
| ~~`fileSync`~~ | conditional | 0 | — | removed (local-first program A1 — feature shipped un-gated; user off switch `FileSync.enabled` remains) | ✅ code removed 2026-07-12; retire remote `file_sync` key server-side |
| `syncedTranscripts` | conditional | — | FingerprintTimingManager.swift, TranscriptViewController.swift | keep (post-audit flag; staged rollout) | |
| `showExplicitBadges` | false | — | PodcastCells, search results | keep (default false) | |
| ~~`grdbQueryInterface`~~ | true | 0 | — | removed (GRDB query-interface conversion) | ✅ code removed before 2026-07-12; retire remote `grdb_query_interface` key server-side |
| `newOnboardingAccountCreation` | true | 18 | InformationalModalView.swift, InformationalModalViewModel.sw | candidate (wide adoption — retire in its own PR) | |
| `useFollowNaming` | true | 18 | DiscoverPodcastTableCell.swift, ImportExportViewController.s | candidate (wide adoption — retire in its own PR) | |
| `optimizeManualPlaylistQueries` | true | 42 | PlaylistQueryBuilder.swift, PlaylistQueryBuilderTests.swift | candidate (wide adoption — retire in its own PR) | |
| `analyticsLogging` | false | 1 | AnalyticsLoggingAdapter.swift | keep (default not unconditionally true) | |
| `appThemePropertiesLogging` | conditional | 1 | Analytics.swift | keep (default not unconditionally true) | |
| `runVacuumOnVersionUpdate` | false | 1 | MainTabBarController.swift | keep (default not unconditionally true) | |
| ~~`voiceBoostN`~~ | false | 0 | — | removed (local-first program A5 — DSP available in all builds; user toggle `useVoiceBoostN` stays opt-in) | ✅ code removed 2026-07-12; retire remote `voice_boost_n` key server-side |
| `settingsSync` | conditional | 5 | SyncSettingsTask.swift, SyncTask+LocalChanges.swift, SyncTas | keep (default not unconditionally true) | |
| ~~`shareProfile`~~ | conditional | 0 | — | removed (local-first program A4 — available in all builds; renders signed-out with local data) | ✅ code removed 2026-07-12; retire remote `share_profile` key server-side |
| ~~`upNextSort`~~ | conditional | 0 | — | removed (local-first program A4) | ✅ code removed 2026-07-12; retire remote `up_next_sort` key server-side |
| ~~`generatedChapters`~~ | conditional | 0 | — | removed (local-first program A4 — AI chapters for server-sourced podcasts in all builds; unavailable for `.localFeed` podcasts by design) | ✅ code removed 2026-07-12; retire remote `generated_chapters` key server-side |
| `activateAudioSessionInBackground` | true | 1 | PlaybackManager.swift | defer-playback | |
| `avoidReplaceOnEpisodeSwap` | true | 1 | PlaybackQueue.swift | defer-playback | |
| `doNotSwitchToDownloadedFile` | true | 1 | PlaybackManager.swift | defer-playback | |
| `dontAutoplayOnRouteChange` | true | 1 | PlaybackManager.swift | defer-playback | |
| `effectsPlayerQOSUpgrade` | true | 1 | AudioReadTask.swift | defer-playback | |
| `ignorePlayWithOtherAudio` | true | 1 | PlaybackManager.swift | defer-playback | |
| `ignoreRouteDisconnectedInterruption` | true | 1 | PlaybackManager.swift | defer-playback | |
| `playerIsReadyToPlay` | true | 1 | PlaybackManager.swift | defer-playback | |
| `replaceSpecificEpisode` | true | 1 | PlaybackQueue.swift | defer-playback | |
| `limitPlaybackPositionChanges` | true | 2 | PlaybackManager.swift | defer-playback | |
| `whenPlayingOnlyUpdateEpisodeIfPlaybackFails` | true | 2 | DefaultPlayer.swift, PlaybackActionHelper.swift | defer-playback | |
| `checkFinishedTimeBeforeShouldKeepPlaying` | true | 3 | DefaultPlayer.swift | defer-playback | |
| `defaultPlayerFilterCallbackFix` | true | 5 | DefaultPlayer.swift, FeatureFlagTests.swift | defer-playback | |
| `useDefaultPlayerTapCookie` | true | 5 | DefaultPlayer.swift | defer-playback | |
| `streamAndCachePlayingEpisode` | true | 6 | DownloadManager.swift, PlaybackManager.swift, PlaybackQueue. | defer-playback | |
| `trackNetworkDataUsage` | true | 7 | BackgroundSyncManager+URLSession.swift, DefaultPlayer.swift, | defer-playback | |
| `upNextShuffle` | true | 14 | PlaybackManager.swift, Settings.swift, UpNextViewController+ | defer-playback | |
| `newSettingsStorage` | conditional | 153 | AppDelegate+Defaults.swift, AutoAddQueueDataManager.swift, A | defer-playback | |