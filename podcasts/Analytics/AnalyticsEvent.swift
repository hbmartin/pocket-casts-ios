import Foundation

enum AnalyticsEvent: String {
    // MARK: - App Lifecycle

    case applicationInstalled
    case applicationOpened
    case applicationUpdated
    case applicationClosed

    case appClipOpened

    // MARK: - User Lifecycle

    case userSignedIn
    case userSignedOut
    case userSignInFailed
    case userAccountCreated
    case userAccountCreationFailed
    case userAccountDeleted
    case userEmailUpdated
    case userPasswordUpdated
    case userPasswordReset

    // MARK: - Setup Account

    case setupAccountShown
    case setupAccountDismissed
    case setupAccountButtonTapped

    // MARK: - Onboarding

    case onboardingCarouselShown
    case onboardingGetStarted

    // MARK: - Sign in View

    case signInShown
    case signInDismissed

    // MARK: - Select Account Type

    case selectAccountTypeShown
    case selectAccountTypeDismissed
    case selectAccountTypeNextButtonTapped

    // MARK: - Create Account

    case createAccountShown
    case createAccountDismissed
    case createAccountNextButtonTapped

    // MARK: - Terms of Use

    case termsOfUseShown
    case termsOfUseDismissed
    case termsOfUseAccepted
    case termsOfUseRejected

    // MARK: - Podcasts List
    case podcastsListShown
    case podcastsListFolderButtonTapped
    case podcastsListPodcastTapped
    case podcastsListFolderTapped
    case podcastsListOptionsButtonTapped
    case podcastsListReordered
    case podcastsListModalOptionTapped
    case podcastsListSortOrderChanged
    case podcastsListLayoutChanged
    case podcastsListBadgesChanged
    case podcastsListDiscoverButtonTapped
    case podcastsListNotificationsTapped

    // MARK: - Forgot Password

    case forgotPasswordShown
    case forgotPasswordDismissed

    // MARK: - Account Updated View

    case accountUpdatedShown
    case accountUpdatedDismissed

    // MARK: - Table Swipe Actions for Podcast episodes

    case episodeSwipeActionPerformed

    // MARK: - Profile View

    case profileShown
    case profileSettingsButtonTapped
    case profileAccountButtonTapped
    case profileRefreshButtonTapped
    case profileBookmarksShow

    case accountDetailsShowTOS
    case accountDetailsShowPrivacyPolicy
    case accountDetailsChangeAvatar

    // MARK: - Stats View

    case statsShown
    case statsDismissed

    // MARK: - Folders

    case folderShown
    case folderCreateShown
    case folderPodcastPickerSearchPerformed
    case folderPodcastPickerSearchCleared
    case folderPodcastPickerFilterChanged
    case folderCreateNameShown
    case folderCreateColorShown
    case folderSaved
    case folderChoosePodcastsShown
    case folderChoosePodcastsDismissed
    case folderAddPodcastsButtonTapped
    case folderOptionsButtonTapped
    case folderSortByChanged
    case folderOptionsModalOptionTapped
    case folderEditShown
    case folderEditDismissed
    case folderEditDeleteButtonTapped
    case folderDeleted
    case folderChooseShown
    case folderChooseFolderTapped
    case folderChooseRemovedFromFolder
    case folderPodcastModalOptionTapped

    case suggestedFoldersPageShown
    case suggestedFoldersPageDismissed
    case suggestedFoldersUseSuggestedFoldersTapped
    case suggestedFoldersCreateCustomFolderTapped
    case suggestedFoldersPreviewFolderTapped
    case suggestedFoldersReplaceFoldersTapped
    case suggestedFoldersReplaceFoldersConfirmTapped

    // MARK: - Tab Bar Items

    case podcastsTabOpened
    case filtersTabOpened
    case discoverTabOpened
    case profileTabOpened
    case upNextTabOpened

    // MARK: - Downloads View

    case downloadsShown
    case downloadsOptionsButtonTapped
    case downloadsOptionsModalOptionTapped
    case freeUpSpaceBannerShown
    case freeUpSpaceManageDownloadsTapped
    case freeUpSpaceModalShown
    case freeUpSpaceMaybeLaterTapped

    case downloadsMultiSelectEntered
    case downloadsSelectAllButtonTapped
    case downloadsMultiSelectExited

    // MARK: - Downloads Clean Up View

    case downloadsCleanUpShown
    case downloadsCleanUpButtonTapped
    case downloadsCleanUpCompleted

    // MARK: - Listening History

    case listeningHistoryShown
    case listeningHistoryOptionsButtonTapped
    case listeningHistoryOptionsModalOptionTapped

    case listeningHistoryMultiSelectEntered
    case listeningHistorySelectAllButtonTapped
    case listeningHistoryMultiSelectExited

    case listeningHistoryCleared
    case listeningHistoryClearConfirmationShown
    case listeningHistoryClearConfirmationDismissed

    case listeningHistoryDiscoverButtonTapped

    // MARK: - Uploaded Files

    case uploadedFilesShown
    case uploadedFilesOptionsButtonTapped
    case uploadedFilesOptionsModalOptionTapped
    case uploadedFilesAddButtonTapped

    case uploadedFilesMultiSelectEntered
    case uploadedFilesSelectAllButtonTapped
    case uploadedFilesMultiSelectExited

    case uploadedFilesSortByChanged
    case uploadedFilesHelpButtonTapped

    // MARK: - User File Details View

    case userFileDeleted
    case userFileDetailShown
    case userFileDetailDismissed
    case userFileDetailOptionTapped
    case userFileEditShown
    case userFileEditDismissed
    case userFileEditSave
    case userFileDeleteShown
    case userFileDeleteDismissed

    case userFilePlayPauseButtonTapped

    // MARK: - Starred

    case starredShown
    case starredMultiSelectEntered
    case starredSelectAllButtonTapped
    case starredMultiSelectExited

    // MARK: - Playback

    case playbackPlay
    case playbackPause
    case playbackSkipBack
    case playbackSkipForward
    case playbackNextEpisode
    case playbackPreviousEpisode
    case playbackSeek

    case playbackEffectSettingsViewAppeared
    case playbackEffectSettingsChanged
    case playbackEffectSpeedChanged
    case playbackEffectTrimSilenceToggled
    case playbackEffectTrimSilenceAmountChanged
    case playbackEffectVolumeBoostToggled

    case playbackChapterSkipped

    case playbackFailed
    case playbackErrorShown
    case playbackErrorTapped

    // MARK: - Autoplay
    case playbackEpisodeAutoplayed
    case autoplayStarted
    case autoplayFinishedLastEpisode

    // MARK: - Filters

    case filterListShown
    case filterListEditButtonToggled
    case filterListReordered

    case filterCreateButtonTapped

    case filterDeleted
    case filterUpdated
    case filterCreated
    case filterCreateShown
    case filterCreateAsManualPlaylistTapped
    case filterCreateAsSmartPlaylistTapped
    case filterCreateAsCustomPlaylistTapped
    case filterCustomQueryValidated

    // Prompted playlists (natural language -> smart playlist draft)
    case promptedPlaylistShown
    case promptedPlaylistGenerated
    case promptedPlaylistGenerationFailed
    case filterCreateCancelled
    case filterDeleteTriggered
    case filterDeleteDismissed

    case filterShown
    case filterTooltipShown
    case filterTooltipClosed

    case filterMultiSelectEntered
    case filterSelectAllButtonTapped
    case filterSelectAll
    case filterDeselectAll
    case filterSelectAllAbove
    case filterSelectAllBelow
    case filterDeselectAllAbove
    case filterDeselectAllBelow
    case filterMultiSelectExited

    case filterOptionsButtonTapped
    case filterOptionsModalOptionTapped
    case filterSortByChanged
    case filterEditDismissed

    case filterSiriShortcutsShown
    case filterSiriShortcutAdded
    case filterSiriShortcutRemoved

    case filterAutoDownloadUpdated
    case filterAutoDownloadLimitUpdated

    case filterAddEpisodesShown
    case filterAddEpisodesFolderTapped
    case filterAddEpisodesPodcastTapped
    case filterAddEpisodesEpisodeTapped

    case filterEditRulesTapped
    case filterAddEpisodesTapped

    case filterPlayAllTapped
    case filterPlayAllReplaceAndPlayTapped
    case filterPlayAllDismissed

    case filterOptionsTapped
    case filterSelectEpisodesTapped
    case filterSortByTapped
    case filterDownloadAllTapped
    case filterChromeCastTapped
    case filterArchiveAllTapped
    case filterUnarchiveAllTapped
    case filterRearrangeEpisodesTapped

    case filterShowArchivedTapped
    case filterHideArchivedTapped

    case filterRemoveFromPlaylistTapped

    case filterNameUpdated

    case filterEditRulesCtaEmptyTapped
    case filterAddEpisodesCtaEmptyTapped
    case filterBrowseShowsCtaEmptyTapped
    case filterShowArchivedCtaEmptyTapped

    case filterManualEpisodesRearranged
    case filterManualEpisodeDeleted

    case episodeRecentlyPlayedSortOptionTooltipShown
    case episodeRecentlyPlayedSortOptionTooltipDismissed

    case episodeAddedToList
    case episodeRemovedFromList

    case addToPlaylistsShown
    case addToPlaylistsEpisodeAddTapped
    case addToPlaylistsRemoveTapped
    case addToPlaylistsNewPlaylistTapped
    case addToPlaylistsCreateNewPlaylistTapped

    // MARK: - Podcast screen

    case podcastScreenShown
    case podcastScreenFolderTapped
    case podcastScreenSettingsTapped
    case podcastScreenFundingTapped
    case podcastScreenSubscribeTapped
    case podcastScreenUnsubscribeTapped
    case podcastScreenSearchPerformed
    case podcastScreenSearchCleared
    case podcastScreenOptionsTapped
    case podcastScreenToggleArchived
    case podcastScreenShareTapped
    case podcastScreenToggleSummary
    case podcastScreenPodcastDescriptionTapped
    case podcastsScreenSortOrderChanged
    case podcastsScreenEpisodeGroupingChanged
    case podcastsScreenTabTapped
    case podcastScreenPodcastDescriptionLinkTapped
    case podcastScreenNotificationsTapped
    case podcastScreenPodcastDetailsLinkTapped
    case podcastScreenCategoryTapped
    case podcastScreenYouMightLikeTapped
    case podcastScreenYouMightLikeSubscribed
    case podcastScreenSeasonOptionsTapped
    case podcastScreenSeasonOptionsSelectAllTapped
    case podcastScreenSeasonOptionsDownloadAllTapped
    case podcastScreenSeasonOptionsRemoveAllTapped
    case podcastScreenSeasonOptionsArchiveAllTapped
    case podcastScreenSeasonOptionsUnarchiveAllTapped

    // MARK: - Signed out alert

    case signedOutAlertShown

    // MARK: - Discover

    case discoverShown
    case discoverCategoryShown
    case discoverCategoriesPillTapped
    case discoverFeaturedPodcastTapped
    case discoverFeaturedPodcastSubscribed
    case discoverShowAllTapped
    case discoverCategoryCloseButtonTapped
    case discoverCategoriesPickerPick
    case discoverCategoriesPickerClosed
    case discoverCategoriesPickerShown

    case discoverListImpression
    case discoverListShowAllTapped
    case discoverListEpisodeTapped
    case discoverListEpisodePlay
    case discoverListPodcastTapped
    case discoverListPodcastSubscribed
    case discoverListShareTapped

    case discoverFeaturedPageChanged
    case discoverSmallListPageChanged
    case discoverLargeListPageChanged
    case discoverNetworkListPageChanged

    case discoverRegionChanged
    case discoverCollectionLinkTapped

    case discoverAdCategoryTapped
    case discoverAdCategorySubscribed

    // MARK: - Mini Player

    case miniPlayerLongPressMenuShown
    case miniPlayerLongPressMenuOptionTapped
    case miniPlayerLongPressMenuDismissed

    // MARK: - Up Next

    case upNextShown
    case upNextQueueCleared
    case upNextNowPlayingTapped
    case upNextQueueEpisodeTapped
    case upNextQueueEpisodeLongPressed
    case upNextMultiSelectEntered
    case upNextSelectAllButtonTapped
    case upNextMultiSelectExited
    case upNextQueueReordered
    case upNextDismissed
    case upNextShuffleEnabled
    case upNextSort
    case upNextDiscoverButtonTapped
    case upNextGoToPodcastsTapped

    // MARK: - Privacy

    case privacySettingsShown
    case analyticsOptIn
    case analyticsOptOut
    case analyticsThirdPartyOptIn
    case analyticsThirdPartyOptOut

    // MARK: - Player

    case playerShown
    case playerDismissed

    case deselectChaptersChapterSelected
    case deselectChaptersChapterDeselected
    case deselectChaptersToggledOn
    case deselectChaptersToggledOff
    case chapterLinkClicked

    case playerTabSelected
    case playerShowNotesLinkTapped
    case playerChapterSelected
    case playerPodcastNameTapped

    case playerPreviousChapterTapped
    case playerNextChapterTapped
    case playerEpisodeCompleted


    // MARK: - Player: Sleep Timer

    case playerSleepTimerEnabled
    case playerSleepTimerExtended
    case playerSleepTimerCancelled
    case playerSleepTimerRestarted
    case playerSleepTimerSettingsTapped

    // MARK: - Player: Shelf

    case playerShelfActionTapped
    case playerShelfOverflowMenuShown
    case playerShelfOverflowMenuRearrangeStarted
    case playerShelfOverflowMenuRearrangeActionMoved
    case playerShelfOverflowMenuRearrangeFinished

    // MARK: - Episode Events

    case episodeTapped

    case episodeStarred
    case episodeBulkStarred

    case episodeUnstarred
    case episodeBulkUnstarred

    case episodeDownloadQueued
    case episodeDownloadFinished
    case episodeBulkDownloadQueued
    case episodeDownloadCancelled
    case episodeDownloadFailed
    case episodeDownloadsStale
    case episodeDownloadTasks

    case episodeDownloadDeleted
    case episodeBulkDownloadDeleted

    case episodeArchived
    case episodeBulkArchived

    case episodeUnarchived
    case episodeBulkUnarchived

    case episodeMarkedAsPlayed
    case episodeBulkMarkedAsPlayed

    case episodeMarkedAsUnplayed
    case episodeBulkMarkedAsUnplayed

    case episodeAddedToUpNext
    case episodeBulkAddToUpNext

    case episodeRemovedFromUpNext

    case episodeRemovedListeningHistory

    case podcastShared

    // MARK: - Episode Detail

    case episodeDetailShown
    case episodeDetailShowNotesLinkTapped
    case episodeDetailPodcastNameTapped
    case episodeDetailDismissed
    case episodeDetailTabChanged

    // MARK: - Multi Select View

    case multiSelectViewOverflowMenuShown
    case multiSelectViewOverflowMenuRearrangeStarted
    case multiSelectViewOverflowMenuRearrangeActionMoved
    case multiSelectViewOverflowMenuRearrangeFinished

    // MARK: - Pull to Refresh

    case pulledToRefresh

    // MARK: - Push notifications

    case notificationsOptInShown
    case notificationsOptInAllowed
    case notificationsOptInDenied

    case notificationsPermissionsShown
    case notificationsPermissionsAllowTapped
    case notificationsPermissionsNotNowTapped
    case notificationsPermissionsOpenSystemSettings

    case notificationOpened

    // MARK: - Podcast Settings

    case podcastSettingsFeedErrorTapped
    case podcastSettingsFeedErrorUpdateTapped
    case podcastSettingsFeedErrorFixSucceeded
    case podcastSettingsFeedErrorFixFailed

    case podcastSettingsAutoDownloadToggled
    case podcastSettingsNotificationsToggled
    case podcastSettingsAutoTranscribeToggled
    case podcastSettingsAutoAddUpNextToggled
    case podcastSettingsAutoAddUpNextPositionOptionChanged

    case podcastSettingsCustomPlaybackEffectsToggled

    case podcastSettingsSkipFirstChanged
    case podcastSettingsSkipLastChanged
    case podcastSettingsSkipChaptersRulesChanged

    case podcastSettingsAutoArchiveToggled
    case podcastSettingsAutoArchivePlayedChanged
    case podcastSettingsAutoArchiveInactiveChanged
    case podcastSettingsAutoArchiveEpisodeLimitChanged

    case podcastSettingsSiriShortcutAdded
    case podcastSettingsSiriShortcutRemoved

    // MARK: - Settings: General

    case settingsGeneralShown
    case settingsGeneralRowActionChanged
    case settingsGeneralEpisodeGroupingChanged
    case settingsGeneralEpisodeGroupingApplyToExisting
    case settingsGeneralEpisodeGroupingDoNotApplyToExisting
    case settingsGeneralArchivedEpisodesChanged
    case settingsGeneralArchivedEpisodesApplyToExisting
    case settingsGeneralArchivedEpisodesDoNotApplyToExisting
    case settingsGeneralUpNextSwipeChanged
    case settingsGeneralOpenLinksInBrowserToggled
    case settingsGeneralSkipForwardChanged
    case settingsGeneralSkipBackChanged
    case settingsGeneralKeepScreenAwakeToggled
    case settingsGeneralOpenPlayerAutomaticallyToggled
    case settingsGeneralDisableLockScreenScrubberToggled
    case settingsGeneralIntelligentPlaybackToggled
    case settingsGeneralPlayUpNextOnTapToggled
    case settingsGeneralRemoteSkipsChaptersToggled
    case settingsGeneralExtraPlaybackActionsToggled
    case settingsGeneralLegacyBluetoothToggled
    case settingsGeneralMultiSelectGestureToggled
    case settingsGeneralPublishChapterTitlesToggled
    case settingsGeneralAutoplayToggled
    case settingsGeneralAutoSleepTimerRestartToggled
    case settingsGeneralShakeToResetSleepTimerToggled
    case settingsGeneralTapToPlayToggled
    case settingsGeneralSeekAccelerationToggled

    // MARK: - Settings: Devices (route-aware playback rules)

    case settingsDeviceRuleChanged

    // MARK: - Settings: Notifications

    case settingsNotificationsShown
    case settingsNotificationsNewEpisodesToggled
    case settingsNotificationsPodcastsChanged
    case settingsNotificationsAppBadgeChanged
    case settingsNotificationsTrendingToggle
    case settingsNotificationsDailyRemindersToggle
    case settingsNotificationsNewFeaturesToggle
    case settingsNotificationsOffersToggle

    // MARK: - Settings: Appearance

    case settingsAppearanceShown
    case settingsAppearanceFollowSystemThemeToggled
    case settingsAppearanceThemeChanged
    case settingsAppearanceLightThemeChanged
    case settingsAppearanceDarkThemeChanged
    case settingsAppearanceAppIconChanged
    case settingsAppearanceRefreshAllArtworkTapped
    case settingsAppearanceUseEmbeddedArtworkToggled
    case settingsAppearanceUseDarkUpNextToggled
    case settingsAppearanceTabBarMinimizingToggled

    // MARK: - Settings: Auto Archive

    case settingsAutoArchiveShown
    case settingsAutoArchivePlayedChanged
    case settingsAutoArchiveInactiveChanged
    case settingsAutoArchiveIncludeStarredToggled

    // MARK: - Settings: Auto Download

    case settingsAutoDownloadShown
    case settingsAutoDownloadUpNextToggled
    case settingsAutoDownloadNewEpisodesToggled
    case settingsAutoDownloadOnFollowPodcastToggled
    case settingsAutoDownloadLimitDownloadsChanged
    case settingsAutoDownloadPodcastsChanged
    case settingsAutoDownloadFiltersChanged
    case settingsAutoDownloadOnlyOnWifiToggled

    // MARK: - Settings: Auto Add to Up Next

    case settingsAutoAddUpNextShown
    case settingsAutoAddUpNextAutoAddLimitChanged
    case settingsAutoAddUpNextLimitReachedChanged
    case settingsAutoAddUpNextPodcastsChanged
    case settingsAutoAddUpNextPodcastPositionOptionChanged

    // MARK: - Settings: Storage & Data Use

    case settingsStorageShown
    case settingsStorageWarnBeforeUsingDataToggled

    // MARK: - Settings: Siri Shortcuts

    case settingsSiriShown
    case settingsSiriShortcutAdded
    case settingsSiriShortcutRemoved

    // MARK: - Settings: Files

    case settingsFilesShown
    case settingsFilesAutoAddUpNextToggled
    case settingsFilesDeleteLocalFileAfterPlayingToggled
    case settingsFilesOnlyOnWifiToggled

    // MARK: - Settings: Help and Feedback

    case settingsHelpShown
    case settingsGetSupport
    case settingsLeaveFeedback
    case exportDatabaseTapped

    // MARK: - Settings: Import / Export OPML

    case settingsImportShown
    case settingsImportExportTapped
    case settingsImportExportStarted
    case settingsImportExportFinished
    case settingsImportExportFailed

    // MARK: - Settings: About

    case settingsAboutShown
    case settingsAboutShareWithFriendsTapped
    case settingsAboutWebsiteTapped
    case settingsAboutTwitterTapped
    case settingsAboutAutomatticFamilyTapped
    case settingsAboutLegalAndMoreTapped
    case settingsAboutWorkWithUsTapped

    // MARK: - OPML Import

    case opmlImportStarted
    case opmlImportFailed
    case opmlImportFinished

    // MARK: - Subscribe / Unsubscribe

    case podcastSubscribed
    case podcastUnsubscribed

    // MARK: - Podcast Search

    case searchShown
    case searchDismissed
    case searchPerformed
    case searchFailed
    case searchEmptyResults
    case searchPredictiveFailed
    case searchResultTapped
    case searchListShown
    case searchCleared
    case searchFilterTapped
    case searchPredictiveShown
    case searchPredictiveTermTapped
    case searchPredictiveViewAllTapped

    // MARK: - Podcast List Share

    case sharePodcastsShown
    case sharePodcastsPodcastsSelected
    case sharePodcastsListPublishStarted
    case sharePodcastsListPublishSucceeded
    case sharePodcastsListPublishFailed

    // MARK: - Incoming Share List

    case incomingShareListShown
    case incomingShareListSubscribedAll

    case playbackShared

    // MARK: - Welcome View

    case welcomeShown
    case welcomeImportTapped
    case welcomeDiscoverTapped
    case welcomeDismissed

    // MARK: - Import

    case onboardingImportShown
    case onboardingImportAppSelected
    case onboardingImportOpenAppTapped
    case onboardingImportDismissed

    // MARK: - Recommendations

    case recommendationsShown
    case recommendationsDismissed
    case recommendationsSearchTapped
    case recommendationsMoreTapped
    case recommendationsContinueTapped
    case recommendationsImportTapped

    // MARK: - Interests
    case onboardingInterestsShown
    case onboardingInterestsNotNowTapped
    case onboardingInterestsCategorySelected
    case onboardingInterestsShownMoreTapped
    case onboardingInterestsContinueTapped

    // MARK: - Search History
    case searchHistoryCleared
    case searchHistoryItemTapped
    case searchHistoryItemDeleteButtonTapped

    // MARK: - Ratings
    case ratingStarsTapped
    case ratingScreenShown
    case ratingScreenDismissed
    case ratingScreenSubmitTapped
    case notAllowedToRateScreenShown
    case notAllowedToRateScreenDismissed

    // MARK: - What's New
    case whatsnewShown
    case whatsnewDismissed
    case whatsnewConfirmButtonTapped

    // MARK: - Bookmarks
    case bookmarkCreated
    case bookmarkUpdateTitle
    case bookmarksEmptyGoToHeadphoneSettings
    case bookmarkPlayTapped
    case bookmarksSortByChanged
    case bookmarksExportedAsMarkdown
    case bookmarkDeleted
    case bookmarkShareTapped
    case bookmarkEditFormShown
    case bookmarkEditFormDismissed
    case bookmarkEditFormSubmitted
    case bookmarkDeleteFormShown
    case bookmarkDeleteFormDismissed
    case bookmarkDeleteFormSubmitted

    // MARK: - Smart Highlights

    case highlightEnrichmentCompleted
    case highlightEnrichmentFailed
    case highlightQuoteShared

    // MARK: - People Directory

    case peopleDirectoryShown

    // MARK: - Headphone Controls
    case settingsHeadphoneControlsShown
    case settingsHeadphoneControlsNextChanged
    case settingsHeadphoneControlsPreviousChanged
    case settingsHeadphoneControlsBookmarkSoundToggled

    // MARK: - Transcript

    case transcriptShown
    case transcriptError
    case transcriptDismissed
    case transcriptSearchShown
    case transcriptSearchNextResult
    case transcriptSearchPreviousResult
    case episodeDetailTranscriptCardShown
    case episodeDetailTranscriptCardTapped
    case episodeTranscriptShown
    case transcriptShared
    case transcriptTextHighlighted
    case syncedTranscriptSeekUsed
    case syncedTranscriptPreparationStarted
    case syncedTranscriptPreparationCompleted
    case syncedTranscriptPreparationFailed
    case syncedTranscriptUnavailable
    case syncedTranscriptSeekFailed
    case syncedTranscriptAutoScrollResumed

    // MARK: - Episode Summary (AI summary card on episode detail)

    case episodeDetailSummaryCardShown
    case episodeDetailSummaryTakeawayTapped
    case episodeDetailSummaryGenerationFailed
    case episodeDetailSummaryCatchMeUpTapped
    case catchMeUpShown
    case catchMeUpFailed
    case shakeFeedbackSent

    // MARK: - Episode Credits (people credits card on episode detail)

    case episodeDetailCreditsShown
    case episodeDetailCreditTapped

    // MARK: - Library Transcript Search (viewed podcast-provided transcripts)

    case librarySearchTranscriptsShown
    case librarySearchTranscriptResultTapped

    // MARK: - Diarized Transcription (locally generated transcripts)

    case transcriptionGenerateTapped
    case transcriptionStarted
    case transcriptionCompleted
    case transcriptionFailed
    case transcriptionCancelled
    case transcriptionSourceSwitched
    case transcriptionSettingsShown
    case transcriptionKeyValidated
    case transcriptionSpeakerRenamed
    case transcriptionModelDownloaded
    case transcriptionModelDeleted

    // MARK: - Widgets

    case widgetInstalled
    case widgetUninstalled
    case widgetInteraction

    // MARK: - Share Screen
    case shareScreenShown
    case shareScreenPlayTapped
    case shareScreenPauseTapped
    case shareScreenClipShared
    case shareScreenNavigationButtonTapped
    case shareScreenEditButtonTapped
    case shareScreenCloseButtonTapped

    // MARK: - Select/Choose Podcasts
    case settingsSelectPodcastsShown
    case settingsSelectPodcastsDismissed
    case settingsSelectPodcastsSelectAllTapped
    case settingsSelectPodcastsSelectNoneTapped
    case settingsSelectPodcastsPodcastToggled
    case settingsSelectPodcastsSelectAllPodcastsToggled

    // MARK: - Podcast Feed Reload
    case podcastScreenRefreshEpisodeList
    case podcastScreenRefreshNoEpisodesFound
    case podcastScreenRefreshNewEpisodeFound
    case podcastRefreshEpisodeTooltipShown
    case podcastRefreshEpisodeTooltipDismissed

    // MARK: - Encourage Account Creation
    case informationalModalViewShowed
    case informationalModalViewDismissed
    case informationalModalViewGetStartedTap
    case informationalModalViewLoginTap
    case informationalModalViewCardShowed
    case informationalBannerViewDismissed
    case informationalBannerViewCreateAccountTap

    // MARK: - Podroll Information Modal
    case podcastScreenPodrollInformationModelShown
    case podcastScreenPodrollPodcastSubscribed
    case podcastScreenPodrollPodcastTapped
}
