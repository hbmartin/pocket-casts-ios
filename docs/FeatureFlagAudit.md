# Feature Flag Audit

Phase 0 deliverable of [MODERNIZATION.md](../MODERNIZATION.md): a retirement-planning audit of every
case in `Modules/Sources/PocketCastsUtils/Feature Flags/FeatureFlag.swift`, generated 2026-06-11 from
the actual definitions and call sites (`grep` across `podcasts/`, `Modules/`, `WidgetExtension/`,
excluding the definition file).

**No flag is retired by this document.** Every flag has a live remote kill-switch key (the
`remoteKey` fallthrough derives one from the case name), so each retirement needs sign-off from
the code owner and a separate remote-retirement request from whoever owns remote config. Confirm
the key is not actively targeted, then fill in the **Code sign-off / remote-retirement request**
column with both the code approval and the remote-config owner/status. Remove the flag in a small
PR (inline the `true` branch, delete the `false` branch and the enum case); do not mark remote
retirement complete until the remote owner records the completed change and date.

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

Remote-key retirement is tracked separately from code removal. For every row below that says
`retire remote … key server-side`, the per-key remote-config fields currently remain:
**targeting verification: unverified; responsible owner/approver: unassigned; retirement
completion: pending (no completion date)**. A row may replace those defaults only after the
remote targeting is checked and the named owner records completion.

| Flag | Default | Usages | Used in | Assessment | Code sign-off / remote-retirement request |
|---|---|---|---|---|---|
| ~~`guestListsNetworkHighlightsRedesign`~~ | true | 0 | — | dead — removed | ✅ removed 2026-06-27 |
| ~~`refreshPlaylistOnSubscriptions`~~ | true | 0 | — | dead — removed | ✅ removed 2026-06-27 |
| ~~`smartCategories`~~ | true | 0 | — | dead — removed | ✅ removed 2026-06-27 |
| ~~`syncStats`~~ | true | 0 | — | dead — removed | ✅ removed 2026-06-27 |
| ~~`activateAudioSessionForRoutePicker`~~ | true | 0 | — | removed (program D1 simple-candidate batch) | ✅ code removed 2026-07-12; retire remote `activate_audio_session_for_route_picker` key server-side |
| ~~`checkProtectedDataBeforeMigration`~~ | true | 0 | — | removed (program D1 simple-candidate batch) | ✅ code removed 2026-07-12; retire remote `check_protected_data_before_migration` key server-side |
| ~~`detectTruncatedBackgroundSyncDownloads`~~ | true | 0 | — | removed (program D1 simple-candidate batch) | ✅ code removed 2026-07-12; retire remote `detect_truncated_background_sync_downloads` key server-side |
| ~~`encourageAccountCreation`~~ | true | 0 | — | removed (program D1 simple-candidate batch) | ✅ code removed 2026-07-12; retire remote `encourage_account_creation` key server-side |
| ~~`episodeDetailTranscript`~~ | true | 0 | — | removed (program D1 simple-candidate batch) | ✅ code removed 2026-07-12; retire remote `episode_detail_transcript` key server-side |
| ~~`listeningHistorySearch`~~ | true | 0 | — | removed (program D1 simple-candidate batch) | ✅ code removed 2026-07-12; retire remote `listening_history_search` key server-side |
| ~~`logMainThreadDatabaseAccess`~~ | true | 0 | — | removed (program D1 simple-candidate batch) | ✅ code removed 2026-07-12; retire remote `log_main_thread_database_access` key server-side |
| ~~`manageDownloadedEpisodes`~~ | true | 0 | — | removed (program D1 simple-candidate batch) | ✅ code removed 2026-07-12; retire remote `manage_downloaded_episodes` key server-side |
| ~~`newOnboardingRecommendationChanges`~~ | true | 0 | — | removed (program D1 simple-candidate batch) | ✅ code removed 2026-07-12; retire remote `new_onboarding_recommendation_changes` key server-side |
| ~~`podcastBookmarksInline`~~ | true | 0 | — | removed (program D1 simple-candidate batch) | ✅ code removed 2026-07-12; retire remote `podcast_bookmarks_inline` key server-side |
| ~~`retryWithoutUserAgent`~~ | true | 0 | — | removed (program D1 simple-candidate batch) | ✅ code removed 2026-07-12; retire remote `retry_without_user_agent` key server-side |
| ~~`shareTranscripts`~~ | true | 0 | — | removed (program D1 simple-candidate batch) | ✅ code removed 2026-07-12; retire remote `share_transcripts` key server-side |
| ~~`skipSyncWhenProtectedDataUnavailable`~~ | true | 0 | — | removed (program D1 simple-candidate batch) | ✅ code removed 2026-07-12; retire remote `skip_sync_when_protected_data_unavailable` key server-side |
| ~~`streamingCustomSessionConfiguration`~~ | true | 0 | — | removed (program D1 simple-candidate batch) | ✅ code removed 2026-07-12; retire remote `streaming_custom_session_configuration` key server-side |
| ~~`useBackgroundQueueForStreamingCallback`~~ | true | 0 | — | removed (program D1 simple-candidate batch) | ✅ code removed 2026-07-12; retire remote `use_background_queue_for_streaming_callback` key server-side |
| ~~`useDescriptiveActionAttributedTextView`~~ | true | 0 | — | removed (program D1 simple-candidate batch) | ✅ code removed 2026-07-12; retire remote `use_descriptive_action_attributed_text_view` key server-side |
| ~~`useMimetypePackage`~~ | true | 0 | — | removed (program D1 simple-candidate batch) | ✅ code removed 2026-07-12; retire remote `use_mimetype_package` key server-side |
| ~~`cleanUpTmpFiles`~~ | true | 0 | — | removed (program D1 simple-candidate batch) | ✅ code removed 2026-07-12; retire remote `clean_up_tmp_files` key server-side |
| ~~`concurrentDatabaseReads`~~ | true | 0 | — | removed (data-layer track B0 — DatabasePool concurrent reads are the only path; ValueObservation depends on this) | ✅ code removed 2026-07-12; retire remote `concurrent_database_reads` key server-side |
| ~~`customPlaybackSettings`~~ | true | 0 | — | removed (program D1 simple-candidate batch) | ✅ code removed 2026-07-12; retire remote `custom_playback_settings` key server-side |
| ~~`downloadsThreadSafeCache`~~ | true | 0 | — | removed (program D1 simple-candidate batch) | ✅ code removed 2026-07-12; retire remote `downloads_thread_safe_cache` key server-side |
| ~~`enableLocalizationHeaders`~~ | true | 0 | — | removed (program D1 simple-candidate batch) | ✅ code removed 2026-07-12; retire remote `enable_localization_headers` key server-side |
| ~~`markAllSyncedInSingleStatement`~~ | true | 0 | — | removed (program D1 simple-candidate batch) | ✅ code removed 2026-07-12; retire remote `mark_all_synced_in_single_statement` key server-side |
| ~~`searchPredictive`~~ | true | 0 | — | removed (program D1 simple-candidate batch) | ✅ code removed 2026-07-12; retire remote `search_predictive` key server-side |
| ~~`statsHeatmap`~~ | true | 0 | — | removed (program D1 simple-candidate batch) | ✅ code removed 2026-07-12; retire remote `stats_heatmap` key server-side |
| ~~`suggestedFolders`~~ | true | 0 | — | removed (program D1 simple-candidate batch) | ✅ code removed 2026-07-12; retire remote `suggested_folders` key server-side |
| ~~`displayErrorsOnPlayer`~~ | true | 0 | — | removed (program D1 simple-candidate batch) | ✅ code removed 2026-07-12; retire remote `display_errors_on_player` key server-side |
| ~~`releaseMediaExporterWhenNoLongerActive`~~ | true | 0 | — | removed (program D1 simple-candidate batch) | ✅ code removed 2026-07-12; retire remote `release_media_exporter_when_no_longer_active` key server-side |
| ~~`useCellularNetworkApis`~~ | true | 0 | — | removed (program D1 simple-candidate batch) | ✅ code removed 2026-07-12; retire remote `use_cellular_network_apis` key server-side |
| ~~`playlistCacheInvalidation`~~ | true | 0 | — | removed (program D1 simple-candidate batch) | ✅ code removed 2026-07-12; retire remote `playlist_cache_invalidation` key server-side |
| ~~`playlistDataCacheBeforeQuery`~~ | true | 0 | — | removed (program D1 simple-candidate batch) | ✅ code removed 2026-07-12; retire remote `playlist_data_cache_before_query` key server-side |
| ~~`recommendations`~~ | true | 0 | — | removed (program D1 simple-candidate batch) | ✅ code removed 2026-07-12; retire remote `recommendations` key server-side |
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
| `settingsSync` | **true** (A6a, 2026-07-12) | 5 | SyncSettingsTask.swift, SyncTask+LocalChanges.swift, SyncTas | enabled — remote `settings_sync` key is a live kill switch; delete via A6b after one release of soak (docs/DeferredWork.md) | |
| ~~`shareProfile`~~ | conditional | 0 | — | removed (local-first program A4 — available in all builds; renders signed-out with local data) | ✅ code removed 2026-07-12; retire remote `share_profile` key server-side |
| ~~`upNextSort`~~ | conditional | 0 | — | removed (local-first program A4) | ✅ code removed 2026-07-12; retire remote `up_next_sort` key server-side |
| ~~`generatedChapters`~~ | conditional | 0 | — | removed (local-first program A4 — AI chapters for server-sourced podcasts in all builds; unavailable for `.localFeed` podcasts by design) | ✅ code removed 2026-07-12; retire remote `generated_chapters` key server-side |
| ~~`activateAudioSessionInBackground`~~ | true | 0 | — | removed (program D2 playback batch) | ✅ code removed 2026-07-12; retire remote `activate_audio_session_in_background` key server-side |
| ~~`avoidReplaceOnEpisodeSwap`~~ | true | 0 | — | removed (program D2 playback batch) | ✅ code removed 2026-07-12; retire remote `avoid_replace_on_episode_swap` key server-side |
| ~~`doNotSwitchToDownloadedFile`~~ | true | 0 | — | removed (program D2 playback batch) | ✅ code removed 2026-07-12; retire remote `do_not_switch_to_downloaded_file` key server-side |
| ~~`dontAutoplayOnRouteChange`~~ | true | 0 | — | removed (local-first program E3 — absorbed by route-aware playback rules: don't-autoplay is now the default, per-route auto-resume is opt-in via `RouteRulesStore`) | ✅ code removed 2026-07-12; retire remote `dont_autoplay_on_route_change` key server-side |
| ~~`effectsPlayerQOSUpgrade`~~ | true | 0 | — | removed (program D2 playback batch) | ✅ code removed 2026-07-12; retire remote `effects_player_q_o_s_upgrade` key server-side |
| ~~`ignorePlayWithOtherAudio`~~ | true | 0 | — | removed (program D2 playback batch) | ✅ code removed 2026-07-12; retire remote `ignore_play_with_other_audio` key server-side |
| ~~`ignoreRouteDisconnectedInterruption`~~ | true | 0 | — | removed (program D2 playback batch) | ✅ code removed 2026-07-12; retire remote `ignore_route_disconnected_interruption` key server-side |
| ~~`playerIsReadyToPlay`~~ | true | 0 | — | removed (program D2 playback batch) | ✅ code removed 2026-07-12; retire remote `player_is_ready_to_play` key server-side |
| ~~`replaceSpecificEpisode`~~ | true | 0 | — | removed (program D2 playback batch) | ✅ code removed 2026-07-12; retire remote `replace_specific_episode` key server-side |
| ~~`limitPlaybackPositionChanges`~~ | true | 0 | — | removed (program D2 playback batch) | ✅ code removed 2026-07-12; retire remote `limit_playback_position_changes` key server-side |
| ~~`whenPlayingOnlyUpdateEpisodeIfPlaybackFails`~~ | true | 0 | — | removed (program D2 playback batch) | ✅ code removed 2026-07-12; retire remote `when_playing_only_update_episode_if_playback_fails` key server-side |
| ~~`checkFinishedTimeBeforeShouldKeepPlaying`~~ | true | 0 | — | removed (program D2 playback batch) | ✅ code removed 2026-07-12; retire remote `check_finished_time_before_should_keep_playing` key server-side |
| ~~`defaultPlayerFilterCallbackFix`~~ | true | 0 | — | removed (program D2 playback batch) | ✅ code removed 2026-07-12; retire remote `default_player_filter_callback_fix` key server-side |
| ~~`useDefaultPlayerTapCookie`~~ | true | 0 | — | removed (program D2 playback batch) | ✅ code removed 2026-07-12; retire remote `use_default_player_tap_cookie` key server-side |
| ~~`streamAndCachePlayingEpisode`~~ | true | 0 | — | removed (program D2 playback batch) | ✅ code removed 2026-07-12; retire remote `stream_and_cache_playing_episode` key server-side |
| ~~`trackNetworkDataUsage`~~ | true | 0 | — | removed (program D2 playback batch) | ✅ code removed 2026-07-12; retire remote `track_network_data_usage` key server-side |
| ~~`upNextShuffle`~~ | true | 0 | — | removed (program D2 playback batch) | ✅ code removed 2026-07-12; retire remote `up_next_shuffle` key server-side |
| `newSettingsStorage` | **true** (A6a, 2026-07-12) | 153 | AppDelegate+Defaults.swift, AutoAddQueueDataManager.swift, A | enabled — remote `new_settings_storage` key is a live kill switch; collapse the 153 call sites via A6b after one release of soak (docs/DeferredWork.md) | |
| `episodeSummaries` | conditional (`!= .appStore`) | 1 | EpisodeDetailViewController+ShowNotes.swift | keep (staged rollout — AI UX plan Phase 2: episode summary card + takeaways) | |
| `smartHighlights` | conditional (`!= .appStore`) | 3 | HighlightEnricher.swift, SharingModal.swift, BookmarkRow.swift | keep (staged rollout — AI UX plan Phase 3: bookmark enrichment + quote cards) | |
| `transcriptSearch` | conditional (`!= .appStore`) | 4 | TranscriptSearchIndexer.swift, SearchResultsModel.swift, SearchResultsListView.swift | keep (staged rollout — AI UX plan Phase 4: library-wide transcript search over viewed podcast-provided transcripts; note: locally generated transcripts have a separate search surface behind `diarizedTranscription`) | |
| `promptedPlaylists` | conditional (`!= .appStore`) | 1 | NewPlaylistViewController.swift | keep (staged rollout — AI UX plan Phase 5: natural language → smart playlist draft, on-device interpretation with deterministic fallback) | |
| `episodeCredits` | conditional (`!= .appStore`) | 1 | EpisodeDetailViewController+ShowNotes.swift | keep (staged rollout — AI UX plan Phase 6: people-credits card; chapter url/img passthrough ships un-flagged) | |
| `diarizedTranscription` | conditional (`!= .appStore`) | 8+ | TranscriptionQueueManager.swift, TranscriptManager.swift, AppDelegate.swift, SettingsViewController.swift, ProfileViewController.swift | keep (staged rollout — diarized transcription plan: three engine modes, BG processing, FTS search) | |
| `customPlaylists` | conditional (`== .debug`) | 4 | PlaylistQueryRequests.swift, NewPlaylistViewController.swift, PlaylistDetailViewController.swift | keep (staged rollout — custom smart playlists plan: builder + SQL mode, device-local) | |
