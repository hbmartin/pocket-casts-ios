import Foundation

public enum FeatureFlag: String, CaseIterable, Sendable {

    /// Whether logging of analytics events in console are enabled
    case analyticsLogging

    /// Whether logging the theme properties in analytics events
    case appThemePropertiesLogging

    /// Store settings as JSON in User Defaults (global) or SQLite (podcast)
    case newSettingsStorage

    /// Syncing all app and podcast settings
    case settingsSync

    /// When a user sign in, we always mark ALL podcasts as unsynced
    /// This recently caused issues, syncing changes that shouldn't have been synced
    /// When `true`, we only mark podcasts as unsynced if the user never signed in before
    case onlyMarkPodcastsUnsyncedForNewUsers

    /// Run a vacuum process on the database in order to optimize data fetch
    case runVacuumOnVersionUpdate

    /// Push two auto downloads on subscribe of a podcast
    case autoDownloadOnSubscribe

    /// Replace Subscribe/Unsubscribe with Follow/Unfollow
    case useFollowNaming

    /// Enable/Disable the podcast feed reload feature
    case podcastFeedUpdate

    /// Enable the generated transcript
    case generatedTranscripts

    /// Enable synced transcripts with playback timing
    case syncedTranscripts

    /// Enable on-device diarized transcription (speech-to-text with speaker labels)
    case diarizedTranscription

    /// Enable the new podcast sorting options
    case podcastsSortChanges

    /// Use the new upgrade screens for account creation
    case newOnboardingAccountCreation

    /// Use the new search endpoint and new UI
    case searchImprovements

    /// Optimizes manual playlist queries with improved deduplication
    case optimizeManualPlaylistQueries

    /// Show explicit content badges on podcasts
    case showExplicitBadges

    /// Custom playlists: user-defined query playlists built either with the visual
    /// condition builder or a raw SQL WHERE fragment. Device-local (excluded from
    /// account sync and file sync).
    case customPlaylists

    /// Auth hardening workstream A: password accounts authenticate via rotating
    /// refresh tokens (refresh grant tried first, one-shot password-to-refresh-token
    /// migration) and stop persisting the account password in the Keychain.
    /// Default OFF until the M1 server contract (user/login and user/register
    /// issuing refresh tokens) is live; see plans/API Auth Hardening Plan.md.
    case refreshTokenForPasswordAuth

    /// Auth hardening workstream B: share-list creation authenticates with the
    /// user's bearer token instead of the legacy static SHA-1 signature.
    /// Default OFF until the sharing service dual-accept window is live;
    /// see plans/API Auth Hardening Plan.md.
    case sharingListBearerAuth

    /// AI summary card on the episode detail screen with tap-to-seek key
    /// takeaways (on-device FoundationModels with deterministic fallbacks);
    /// see plans/AI UX Improvements.md Phase 2.
    case episodeSummaries

    /// Smart highlights: bookmarks enriched with transcript excerpts and
    /// on-device auto-titles, shareable as quote cards;
    /// see plans/AI UX Improvements.md Phase 3.
    case smartHighlights

    /// Library-wide transcript search: viewed podcast-provided transcripts are
    /// FTS-indexed on device and surfaced as a Transcripts section in search;
    /// see plans/AI UX Improvements.md Phase 4.
    case transcriptSearch

    /// Prompted playlists: natural language description -> smart playlist draft
    /// (on-device FoundationModels with a deterministic rule-parser fallback);
    /// see plans/AI UX Improvements.md Phase 5.
    case promptedPlaylists

    /// People credits on episode detail (parsed from `<podcast:person>` for
    /// local feeds; server payloads documented in docs/ServerAPISurface.md);
    /// see plans/AI UX Improvements.md Phase 6.
    case episodeCredits

    /// Catch Me Up: on-device recap of an in-progress episode's already-played
    /// portion, from the player shelf and the episode summary card (Deferred
    /// Work Item 19).
    case catchMeUp

    /// On-device chapter generation from the local transcript when an episode
    /// has no chapters from any other source (Deferred Work Item 19; completes
    /// Item 2's on-device path).
    case onDeviceChapters

    /// The People directory: user-renamed transcript speakers aggregated by
    /// display name into a Profile-tab screen;
    /// see plans/transcript-based-ideas.md item 3.
    case speakerDirectory

    /// Custom playlist "Transcript mentions" condition: an FTS MATCH predicate
    /// over the on-device transcript corpus. Positive-only — the index covers
    /// only episodes with fetched/generated transcripts, so unindexed episodes
    /// never match (and negation is deliberately not offered);
    /// see plans/transcript-based-ideas.md item 7.
    case transcriptPlaylistPredicates

    /// Mirrors downloaded episodes (and, later, transcript text and highlights)
    /// into iOS Spotlight as searchable items with deep links back into the app;
    /// see plans/transcript-based-ideas.md item 2.
    case spotlightIndexing

    /// Semantic transcript search: indexed transcripts are embedded on-device
    /// (NLContextualEmbedding) into a windowed vector sidecar, and New Search
    /// fuses vector matches into the Transcripts section so paraphrases match
    /// when keywords don't; see plans/transcript-based-ideas.md item 1.
    case semanticTranscriptSearch

    /// "Mentioned in this episode": entities (people/books/products/websites/
    /// places/organizations) extracted from the indexed transcript with
    /// tap-to-seek anchors — auto-generated show notes;
    /// see plans/transcript-based-ideas.md item 5.
    case episodeMentions

    /// Social identity foundation: opt-in public profiles keyed to the account
    /// uuid, immutable handles (pca.st/u/<handle>), per-field privacy, and
    /// block/mute/report. Ships DARK — the backend must be live in production
    /// before this is enabled (remote key `social_profiles` is the kill switch);
    /// see docs/Social.md and ADR-0005/0006/0007.
    case socialProfiles

    /// Account sync for the highlight fields on bookmarks: excerpt/endTime,
    /// user trims (trim_modified) and tags (tags/tags_modified) ride
    /// SyncUserBookmark as fork fields >= 1001 and are restored by full sync.
    /// Ships DARK — backend milestone B1 must be live in production first
    /// (remote key `highlight_account_sync` is the kill switch); see ADR-0016.
    case highlightAccountSync

    /// Eyes-free highlight capture (Highlights program S3): haptic + tiered
    /// confirmation (sound / spoken "Saved") on every capture, the
    /// Save Highlight App Intent (Siri phrase, Action Button, Shortcuts) and
    /// Control Center control.
    case highlightCapture

    /// The highlight editor (Highlights program S4): trim the excerpt window
    /// against the transcript with looping preview, free-form tags with
    /// autocomplete + list filtering, and the synced "review after capture"
    /// flow. Replaces the title-only edit sheet.
    case highlightEditor

    /// PKM export (Highlights program S5): Markdown auto-export of highlights
    /// into a user-picked folder (Obsidian vault, iCloud Drive), plus the
    /// Get Highlights App Intent for Shortcuts pipelines.
    case pkmExport

    /// Readwise sync (Highlights program S6): pushes new/edited highlights to
    /// the user's Readwise account (their gateway to Notion/Roam/etc.). Token
    /// lives in the Keychain and survives sign-out.
    case readwiseSync

    /// Custom prompt styles (Highlights program S7): presets + a capped
    /// free-text preference shaping highlight-family generation only
    /// (auto-titles, suggested-highlight titles). Output validation is never
    /// weakened; other generators keep fixed prompts.
    case highlightPromptStyles

    public var enabled: Bool {
        if let overriddenValue = FeatureFlagOverrideStore().overriddenValue(for: self) {
            return overriddenValue
        }

        if let remoteValue = FeatureFlagRemoteConfigStore().overriddenValue(for: self) {
            return remoteValue
        }

        return `default`
    }

    public var `default`: Bool {
        switch self {
        case .analyticsLogging:
            false
        case .appThemePropertiesLogging:
            if BuildEnvironment.current == .debug {
                false
            } else {
                true
            }
        case .newSettingsStorage:
            shouldEnableSyncedSettings
        case .settingsSync:
            shouldEnableSyncedSettings
        case .onlyMarkPodcastsUnsyncedForNewUsers:
            true
        case .runVacuumOnVersionUpdate:
            false
        case .autoDownloadOnSubscribe:
            true
        case .useFollowNaming:
            true
        case .podcastFeedUpdate:
            true
        case .generatedTranscripts:
            true
        case .syncedTranscripts:
            true
        case .diarizedTranscription:
            BuildEnvironment.current != .appStore
        case .podcastsSortChanges:
            true
        case .newOnboardingAccountCreation:
            true
        case .searchImprovements:
            true
        case .optimizeManualPlaylistQueries:
            true
        case .showExplicitBadges:
            false
        case .customPlaylists:
            BuildEnvironment.current == .debug
        case .refreshTokenForPasswordAuth:
            false
        case .sharingListBearerAuth:
            false
        case .episodeSummaries:
            BuildEnvironment.current != .appStore
        case .smartHighlights:
            BuildEnvironment.current != .appStore
        case .transcriptSearch:
            BuildEnvironment.current != .appStore
        case .promptedPlaylists:
            BuildEnvironment.current != .appStore
        case .episodeCredits:
            BuildEnvironment.current != .appStore
        case .catchMeUp:
            BuildEnvironment.current != .appStore
        case .onDeviceChapters:
            BuildEnvironment.current != .appStore
        case .speakerDirectory:
            BuildEnvironment.current != .appStore
        case .transcriptPlaylistPredicates:
            BuildEnvironment.current != .appStore
        case .spotlightIndexing:
            BuildEnvironment.current != .appStore
        case .semanticTranscriptSearch:
            BuildEnvironment.current != .appStore
        case .episodeMentions:
            BuildEnvironment.current != .appStore
        case .socialProfiles:
            BuildEnvironment.current != .appStore
        case .highlightAccountSync:
            BuildEnvironment.current != .appStore
        case .highlightCapture:
            BuildEnvironment.current != .appStore
        case .highlightEditor:
            BuildEnvironment.current != .appStore
        case .pkmExport:
            BuildEnvironment.current != .appStore
        case .readwiseSync:
            BuildEnvironment.current != .appStore
        case .highlightPromptStyles:
            BuildEnvironment.current != .appStore
        }
    }

    /// A6a: flipped on 2026-07-12 after the storage/sync plumbing soak-tested behind
    /// the gate. The remote keys `new_settings_storage`/`settings_sync` are now live
    /// kill switches; A6b (deleting both flags and collapsing the ~158 call sites)
    /// follows after one release of soak — see docs/DeferredWork.md.
    private var shouldEnableSyncedSettings: Bool {
        true
    }

    /// User-facing description shown below each toggle in the Beta Features menu.
    /// Plain (non-localized) strings: this screen is only visible in non-App Store builds.
    public var betaDescription: String {
        switch self {
        case .analyticsLogging:
            "Logs analytics events to the console for debugging. No user-facing changes. Low risk."
        case .appThemePropertiesLogging:
            "Attaches the current theme's properties to analytics events. No user-facing changes. Low risk."
        case .newSettingsStorage:
            "Stores app settings as JSON in User Defaults and podcast settings in SQLite (the modern storage path). Turning this off reverts to legacy storage. High risk."
        case .settingsSync:
            "Syncs all app and podcast settings with your account across devices. Turning this off stops settings from syncing. High risk."
        case .onlyMarkPodcastsUnsyncedForNewUsers:
            "On sign-in, only marks podcasts as unsynced for accounts that never signed in before, avoiding syncing changes that shouldn't be synced. Low risk."
        case .runVacuumOnVersionUpdate:
            "Runs a database vacuum after an app update to optimize data fetches. May slow the first launch after updating. Low risk."
        case .autoDownloadOnSubscribe:
            "Automatically queues the two latest episodes for download when you subscribe to a podcast. Low risk."
        case .useFollowNaming:
            "Uses Follow/Unfollow wording instead of Subscribe/Unsubscribe throughout the app. Cosmetic only. Low risk."
        case .podcastFeedUpdate:
            "Enables refreshing a podcast's episode feed on demand from its page. Low risk."
        case .generatedTranscripts:
            "Shows server-generated transcripts for episodes that don't provide their own. Low risk."
        case .syncedTranscripts:
            "Enables transcripts synced to playback timing, so the text follows along with the audio. Medium risk (staged rollout)."
        case .diarizedTranscription:
            "On-device speech-to-text transcription with speaker labels, including background processing and transcript search. Uses significant CPU and battery while transcribing. Medium risk."
        case .podcastsSortChanges:
            "Enables the newer podcast sorting options in the library and folders. Low risk."
        case .newOnboardingAccountCreation:
            "Uses the redesigned upgrade and account-creation onboarding screens. Low risk."
        case .searchImprovements:
            "Uses the new search endpoint and redesigned search UI, including predictive results. Medium risk."
        case .optimizeManualPlaylistQueries:
            "Optimizes manual playlist database queries with improved deduplication. Low risk."
        case .showExplicitBadges:
            "Shows explicit-content badges on podcasts in lists and search results. Low risk."
        case .customPlaylists:
            "Custom smart playlists built with a visual condition builder or a raw SQL WHERE clause. Stored on this device only, excluded from sync. Experimental. Medium risk."
        case .refreshTokenForPasswordAuth:
            "Password accounts sign in via rotating refresh tokens and stop storing your password in the Keychain. Requires server support that may not be live yet; enabling early can break sign-in. High risk."
        case .sharingListBearerAuth:
            "Authenticates share-list creation with your account token instead of the legacy static signature. Requires server support that may not be live yet; enabling early can break list sharing. High risk."
        case .episodeSummaries:
            "AI summary card on the episode detail screen with tap-to-seek key takeaways, generated on device. Medium risk."
        case .smartHighlights:
            "Enriches bookmarks with transcript excerpts and on-device auto-titles, shareable as quote cards. Medium risk."
        case .transcriptSearch:
            "Indexes podcast-provided transcripts you've viewed and adds a Transcripts section to search. Medium risk."
        case .promptedPlaylists:
            "Creates a smart playlist draft from a natural-language description, interpreted on device with a rule-based fallback. Medium risk."
        case .episodeCredits:
            "Shows people credits (hosts and guests) on the episode detail screen, parsed from podcast feed data. Low risk."
        case .catchMeUp:
            "On-device recap of the already-played portion of an in-progress episode, available from the player shelf and the episode summary card. Medium risk."
        case .onDeviceChapters:
            "Generates chapters on device from the local transcript when an episode has no chapters from any other source. Medium risk."
        case .speakerDirectory:
            "People directory on the Profile tab aggregating speakers you've named in transcripts, with per-person episode lists, scoped search, and AI name suggestions in the rename sheet. Medium risk."
        case .transcriptPlaylistPredicates:
            "Adds a 'Transcript mentions' condition to custom playlists that matches episodes whose searchable transcript contains a phrase. Only sees episodes with an indexed transcript. Medium risk."
        case .spotlightIndexing:
            "Indexes downloaded episodes (including transcript text) and highlights into iOS Spotlight search, plus a 'Search Transcripts' Siri shortcut. Medium risk."
        case .semanticTranscriptSearch:
            "Embeds indexed transcripts on device so transcript search also matches paraphrases, with a Played-only filter and recency boost. Uses storage for vectors and CPU while embedding. Medium risk."
        case .episodeMentions:
            "'Mentioned in this episode' card extracting people, books, products, websites and places from the transcript with tap-to-seek links, generated on device. Medium risk."
        case .socialProfiles:
            "Social identity foundation: opt-in public profiles with an immutable @handle (pca.st/u/<handle>), per-field privacy, and block/mute/report. Ships dark — requires the social backend to be live in production; enabling early will fail. High risk."
        case .highlightAccountSync:
            "Syncs highlight excerpts, trims and tags on bookmarks with your account. Requires backend milestone B1 to be live; until then these fields stay device-local while titles keep syncing. Medium risk."
        case .highlightCapture:
            "Eyes-free highlight capture: haptic plus a configurable sound or spoken confirmation on every capture, a Save Highlight Siri shortcut (replaces Open Filter) and a Control Center control. Low risk."
        case .highlightEditor:
            "Highlight editor: trim the transcript excerpt window with audio preview, add free-form tags with filtering, and optionally review each capture as it happens. Replaces the title-only bookmark edit sheet. Medium risk."
        case .pkmExport:
            "Auto-exports highlights as Markdown into a folder you pick (Obsidian vault, iCloud Drive), one file per episode, and adds a Get Highlights action to Shortcuts. Low risk."
        case .readwiseSync:
            "Pushes new and edited highlights to your Readwise account (token entered in Settings > Highlights, stored in the Keychain). Low risk."
        case .highlightPromptStyles:
            "Choose how AI writes highlight titles: presets (atomic note, question-first, quote-only, punchy) plus an optional free-text style preference. Only affects highlight titling. Low risk."
        }
    }

    /// Remote feature flag key used by runtime configuration providers.
    public var remoteKey: String? {
        switch self {
        case .newSettingsStorage:
            shouldEnableSyncedSettings ? "new_settings_storage" : nil
        case .settingsSync:
            shouldEnableSyncedSettings ? "settings_sync" : nil
        default:
            rawValue.lowerSnakeCased()
        }
    }
}

public struct FeatureFlagRemoteConfigStore {
    private let values: RemoteConfigValueStore

    public init(store: UserDefaults = .standard) {
        values = RemoteConfigValueStore(store: store)
    }

    public func overriddenValue(for flag: FeatureFlag) -> Bool? {
        guard let remoteKey = flag.remoteKey else {
            return nil
        }

        return values.bool(forKey: remoteKey)
    }
}

extension FeatureFlag: OverrideableFlag {
    public var description: String {
        rawValue
    }

    public var canOverride: Bool {
        true
    }
}
