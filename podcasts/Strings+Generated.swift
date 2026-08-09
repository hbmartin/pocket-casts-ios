// swiftlint:disable all
// Generated using SwiftGen — https://github.com/SwiftGen/SwiftGen

import Foundation

// swiftlint:disable superfluous_disable_command file_length implicit_return prefer_self_in_static_references

// MARK: - Strings

// swiftlint:disable explicit_type_interface function_parameter_count identifier_name line_length
// swiftlint:disable nesting type_body_length type_name vertical_whitespace_opening_braces
// nonisolated: pure string constants read from every isolation domain; required
// because the app target builds with SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor
nonisolated internal enum L10n {
  /// Button that takes you to other Automattic apps, eg: our Automattic family of apps
  internal static var aboutA8cFamily: String { return L10n.tr("Localizable", "about_a8c_family", fallback: "Automattic Family") }
  /// Button that takes the user to the Acknowledgements screen
  internal static var aboutAcknowledgements: String { return L10n.tr("Localizable", "about_acknowledgements", fallback: "Acknowledgements") }
  /// Secondary text on our come with with us call out
  internal static var aboutJoinFromAnywhere: String { return L10n.tr("Localizable", "about_join_from_anywhere", fallback: "Join From Anywhere") }
  /// Button that takes the user to legal and more screen
  internal static var aboutLegalAndMore: String { return L10n.tr("Localizable", "about_legal_and_more", fallback: "Legal and More") }
  /// Button that takes the user to privacy policy screen
  internal static var aboutPrivacyPolicy: String { return L10n.tr("Localizable", "about_privacy_policy", fallback: "Privacy Policy") }
  /// About page text to ask the user to share a link to our app with friends
  internal static var aboutShareFriends: String { return L10n.tr("Localizable", "about_share_friends", fallback: "Share With Friends") }
  /// Button that takes the user to terms of service screen
  internal static var aboutTermsOfService: String { return L10n.tr("Localizable", "about_terms_of_service", fallback: "Terms of service") }
  /// Button that takes people to our website
  internal static var aboutWebsite: String { return L10n.tr("Localizable", "about_website", fallback: "Website") }
  /// Main callout to come get a job with Automattic
  internal static var aboutWorkWithUs: String { return L10n.tr("Localizable", "about_work_with_us", fallback: "Work With Us") }
  /// A common string used throughout the app. An accessibility label to direct the user to turn off the multi-select mode.
  internal static var accessibilityCancelMultiselect: String { return L10n.tr("Localizable", "accessibility_cancel_multiselect", fallback: "Cancel multiselect") }
  /// A common string used throughout the app. Accessibility hint to inform that the control closes the current dialog window.
  internal static var accessibilityCloseDialog: String { return L10n.tr("Localizable", "accessibility_close_dialog", fallback: "Close dialog") }
  /// A common string used throughout the app. Accessibility hint to inform the user that this control will deselect the episode.
  internal static var accessibilityDeselectEpisode: String { return L10n.tr("Localizable", "accessibility_deselect_episode", fallback: "Deselect Episode") }
  /// A common string used throughout the app. Accessibility hint to inform that the control is disabled.
  internal static var accessibilityDisabled: String { return L10n.tr("Localizable", "accessibility_disabled", fallback: "Disabled") }
  /// A common string used throughout the app. Accessibility hint to inform that the control dismisses the current window.
  internal static var accessibilityDismiss: String { return L10n.tr("Localizable", "accessibility_dismiss", fallback: "Dismiss") }
  /// Accessibility label for episode playback scrubber
  internal static var accessibilityEpisodePlayback: String { return L10n.tr("Localizable", "accessibility_episode_playback", fallback: "Episode Playback") }
  /// An accessibility label to direct the user tap to get access to filter details.
  internal static var accessibilityHideFilterDetails: String { return L10n.tr("Localizable", "accessibility_hide_filter_details", fallback: "Tap to hide filter details") }
  /// Accessibility hint to indicate to users that tapping on the podcast will navigate to podcast information page
  internal static var accessibilityHintPlayerNavigateToPodcastLabel: String { return L10n.tr("Localizable", "accessibility_hint_player_navigate_to_podcast_label", fallback: "Tap to navigate to main podcast information page") }
  /// Accessibility hint to inform the user how to star (favorite) for an episode.
  internal static var accessibilityHintStar: String { return L10n.tr("Localizable", "accessibility_hint_star", fallback: "Double tap to star episode") }
  /// Accessibility hint to inform the user how to un-star (remove favorite) for an episode.
  internal static var accessibilityHintUnstar: String { return L10n.tr("Localizable", "accessibility_hint_unstar", fallback: "Double tap to remove star from episode") }
  /// A common string used throughout the app. An accessibility label to inform the user that the selected item is locked.
  internal static var accessibilityLockedFeature: String { return L10n.tr("Localizable", "accessibility_locked_feature", fallback: "Locked feature") }
  /// A common string used throughout the app. Accessibility hint to inform that the control opens a menu for more options.
  internal static var accessibilityMoreActions: String { return L10n.tr("Localizable", "accessibility_more_actions", fallback: "More actions") }
  /// A common string used throughout the app. An accessibility label to inform the user that the selected item is locked.
  internal static var accessibilityPatronOnly: String { return L10n.tr("Localizable", "accessibility_patron_only", fallback: "Locked feature") }
  /// A common string used throughout the app. An accessibility label to inform the user the completed percentage of a given task. '%1$@' is a placeholder for the localized spelled out number for Voice Over
  internal static func accessibilityPercentCompleteFormat(_ p1: Any) -> String {
    return L10n.tr("Localizable", "accessibility_percent_complete_format", String(describing: p1), fallback: "%1$@ percent completed")
  }
  /// Accessibility label for episode playback progress scrubber
  internal static func accessibilityPlaybackProgress(_ p1: Any, _ p2: Any) -> String {
    return L10n.tr("Localizable", "accessibility_playback_progress", String(describing: p1), String(describing: p2), fallback: "%1$@ of %2$@")
  }
  /// Accessibility text listing the current value for the playback speed. '%1$@' is a placeholder for the playback speed.
  internal static func accessibilityPlayerEffectsPlaybackSpeed(_ p1: Any) -> String {
    return L10n.tr("Localizable", "accessibility_player_effects_playback_speed", String(describing: p1), fallback: "Playback speed %1$@ times")
  }
  /// VoiceOver action for opening a timestamped comment from the player scrubber. %1$d = Moment position in the action list; %2$@ = episode timestamp.
  internal static func accessibilityPlayerOpenMoment(_ p1: Int, _ p2: Any) -> String {
    return L10n.tr("Localizable", "accessibility_player_open_moment", p1, String(describing: p2), fallback: "Open Moment %1$d at %2$@")
  }
  /// An accessibility label used for the add episode action for the Add Episodes search view
  internal static var accessibilityPlaylistAddEpisode: String { return L10n.tr("Localizable", "accessibility_playlist_add_episode", fallback: "Add Episode") }
  /// Accessibility hint to inform the user which filter color flag is being used. '%1$@' is a placeholder for the filter color number.
  internal static func accessibilityPlaylistColor(_ p1: Any) -> String {
    return L10n.tr("Localizable", "accessibility_playlist_color", String(describing: p1), fallback: "Playlist color %1$@")
  }
  /// An accessibility label used for the playlist image
  internal static var accessibilityPlaylistImage: String { return L10n.tr("Localizable", "accessibility_playlist_image", fallback: "Playlist image") }
  /// A common string used throughout the app. An accessibility label to inform the user that the selected item is locked.
  internal static var accessibilityPlusOnly: String { return L10n.tr("Localizable", "accessibility_plus_only", fallback: "Locked feature") }
  /// Accessibility label fir the profile settings icon in the app. 'Pocket Casts' is treated as a proper noun and hasn't been localized in other places of the app.
  internal static var accessibilityProfileSettings: String { return L10n.tr("Localizable", "accessibility_profile_settings", fallback: "Pocket Casts Settings") }
  /// A common string used throughout the app. Accessibility hint to inform the user that this control will select the episode.
  internal static var accessibilitySelectEpisode: String { return L10n.tr("Localizable", "accessibility_select_episode", fallback: "Select Episode") }
  /// An accessibility label to direct the user tap to get access to filter details.
  internal static var accessibilityShowFilterDetails: String { return L10n.tr("Localizable", "accessibility_show_filter_details", fallback: "Tap to show filter details") }
  /// An accessibility hint to prompt the user to tap to open their account details or sign in.
  internal static var accessibilitySignIn: String { return L10n.tr("Localizable", "accessibility_sign_in", fallback: "Tap to view or setup account") }
  /// A common string used throughout the app. An accessibility label to direct the user to sort and option menus.
  internal static var accessibilitySortAndOptions: String { return L10n.tr("Localizable", "accessibility_sort_and_options", fallback: "Sort and Options") }
  /// Title for the options for the user to configure their account.
  internal static var account: String { return L10n.tr("Localizable", "account", fallback: "Account") }
  /// Prompt to allow the user to update the email associated to their account.
  internal static var accountChangeEmail: String { return L10n.tr("Localizable", "account_change_email", fallback: "Change Email") }
  /// Nudge to inform the user that they are nearly done with the account set up steps.
  internal static var accountCompletionNudge: String { return L10n.tr("Localizable", "account_completion_nudge", fallback: "Almost There!") }
  /// Message portion of the nudge to inform the user that they are nearly done with the account set up steps.
  internal static var accountCompletionNudgeMsg: String { return L10n.tr("Localizable", "account_completion_nudge_msg", fallback: "Finalize your payment to finish upgrading your account.") }
  /// Title informing the user that their account has been successfully created
  internal static var accountCreated: String { return L10n.tr("Localizable", "account_created", fallback: "Account Created") }
  /// Error shown after account registration succeeds but the required sign-in request fails.
  internal static var accountCreatedSignInFailed: String { return L10n.tr("Localizable", "account_created_sign_in_failed", fallback: "Account created, but sign-in couldn't be completed. Try again.") }
  /// Title for the final screen in the account creation flow.
  internal static var accountCreationComplete: String { return L10n.tr("Localizable", "account_creation_complete", fallback: "Complete Account") }
  /// Prompt to allow the user to delete their account.
  internal static var accountDeleteAccount: String { return L10n.tr("Localizable", "account_delete_account", fallback: "Delete Account") }
  /// Confirmation option for deleting the user account.
  internal static var accountDeleteAccountConf: String { return L10n.tr("Localizable", "account_delete_account_conf", fallback: "Yes, Delete It") }
  /// Error title for when the delete account process has failed.
  internal static var accountDeleteAccountError: String { return L10n.tr("Localizable", "account_delete_account_error", fallback: "Delete Account Failed") }
  /// Error message for when the delete account process has failed.
  internal static var accountDeleteAccountErrorMsg: String { return L10n.tr("Localizable", "account_delete_account_error_msg", fallback: "Unable to delete account.") }
  /// The final alert message for the confirmation dialog asking the user to confirm they want to delete their account.
  internal static var accountDeleteAccountFinalAlertMsg: String { return L10n.tr("Localizable", "account_delete_account_final_alert_msg", fallback: "Last chance, you definitely want to delete your account? You will lose all your subscriptions and play history permanently!") }
  /// The first message for the confirmation dialog asking the user to confirm they want to delete their account.
  internal static var accountDeleteAccountFirstAlertMsg: String { return L10n.tr("Localizable", "account_delete_account_first_alert_msg", fallback: "Are you sure you want to delete your account, there's no way to undo this!") }
  /// Title for the confirmation dialog asking the user to confirm they want to delete their account.
  internal static var accountDeleteAccountTitle: String { return L10n.tr("Localizable", "account_delete_account_title", fallback: "Delete Account?") }
  /// Label that informs the user they have a free account
  internal static var accountDetailsFreeAccount: String { return L10n.tr("Localizable", "account_details_free_account", fallback: "Free Account") }
  /// Label that shows the user how much time they have listened to podcasts for, %1$@ is the localized formatted time, ie: 2 hours
  internal static func accountDetailsListenedFor(_ p1: Any) -> String {
    return L10n.tr("Localizable", "account_details_listened_for", String(describing: p1), fallback: "Listened for %1$@")
  }
  /// Marketing text that promotes the plus feature to the user
  internal static var accountDetailsPlusTitle: String { return L10n.tr("Localizable", "account_details_plus_title", fallback: "Take your podcasting experience to the next level with exclusive access to features and customisation options.") }
  /// Button title to prompt a user to login.
  internal static var accountLogin: String { return L10n.tr("Localizable", "account_login", fallback: "Log in") }
  /// Informs the user that their purchase will be automatically renewed monthly
  internal static var accountPaymentRenewsMonthly: String { return L10n.tr("Localizable", "account_payment_renews_monthly", fallback: "Renews automatically monthly") }
  /// Informs the user that their purchase will be automatically renewed yearly
  internal static var accountPaymentRenewsYearly: String { return L10n.tr("Localizable", "account_payment_renews_yearly", fallback: "Renews automatically yearly") }
  /// Allows the user to ope a screen to review the Privacy Policy
  internal static var accountPrivacyPolicy: String { return L10n.tr("Localizable", "account_privacy_policy", fallback: "Privacy Policy") }
  /// Error message for when the account registration request has failed.
  internal static var accountRegistrationFailed: String { return L10n.tr("Localizable", "account_registration_failed", fallback: "Registration failed, please try again later") }
  /// Prompt to allow the user to choose their account time when setting up their account.
  internal static var accountSelectType: String { return L10n.tr("Localizable", "account_select_type", fallback: "Select Account Type") }
  /// Prompt to allow the user to sign out of their account.
  internal static var accountSignOut: String { return L10n.tr("Localizable", "account_sign_out", fallback: "Sign Out") }
  /// Message of the confirmation alert shown before signing the user out of their account, reassuring them their data will still be available when they sign back in.
  internal static var accountSignOutAlertMessage: String { return L10n.tr("Localizable", "account_sign_out_alert_message", fallback: "Your podcasts, progress, and data will be here when you are back.") }
  /// Title of the confirmation alert shown before signing the user out of their account.
  internal static var accountSignOutAlertTitle: String { return L10n.tr("Localizable", "account_sign_out_alert_title", fallback: "Sign Out?") }
  /// Confirmation dialog informing the user that signing out will remove the given number of supported podcasts. '%1$@' is a placeholder for the number of supported podcasts.
  internal static func accountSignOutSupporterPrompt(_ p1: Any) -> String {
    return L10n.tr("Localizable", "account_sign_out_supporter_prompt", String(describing: p1), fallback: "Signing out will remove %1$@ supported podcasts from this device. Are you sure?")
  }
  /// Subtitle to the Confirmation dialog informing the user that signing out will remove the given number of supported podcasts.
  internal static var accountSignOutSupporterSubtitle: String { return L10n.tr("Localizable", "account_sign_out_supporter_subtitle", fallback: "You can sign in again to regain access.") }
  /// Message/Body of an alert that explains that the user should tap a button and sign in again
  internal static var accountSignedOutAlertMessage: String { return L10n.tr("Localizable", "account_signed_out_alert_message", fallback: "Turns out, if you type Google into Google, you can break the internet. 🫢 \n\nTap the button below to sign into your Pocket Casts account again.") }
  /// Title of an alert that informs the user that they have been signed out of their account
  internal static var accountSignedOutAlertTitle: String { return L10n.tr("Localizable", "account_signed_out_alert_title", fallback: "You've been signed out.") }
  /// Title for the account screen for the user's Pocket Casts Account. 'Pocket Casts' refers to the app name and is treated as a proper noun so it shouldn't be localized.
  internal static var accountTitle: String { return L10n.tr("Localizable", "account_title", fallback: "Pocket Casts Account") }
  /// Title informing the user that their account has been successfully upgraded to Pocket Casts Plus
  internal static var accountUpgraded: String { return L10n.tr("Localizable", "account_upgraded", fallback: "Account Upgraded") }
  /// Welcome message presented after a user has signed up for Pocket Casts
  internal static var accountWelcome: String { return L10n.tr("Localizable", "account_welcome", fallback: "Welcome to Pocket Casts!") }
  /// Welcome message presented after a user has signed up for Pocket Casts Plus
  internal static var accountWelcomePlus: String { return L10n.tr("Localizable", "account_welcome_plus", fallback: "Welcome to Pocket Casts Plus!") }
  /// Footer under the adaptive effects toggle explaining the behavior
  internal static var adaptiveEffectsFooter: String { return L10n.tr("Localizable", "adaptive_effects_footer", fallback: "Pauses Trim Silence and Voice Boost while music is playing, so songs keep their dynamics and quiet passages aren't skipped. Uses the on-device sound classifier.") }
  /// Section header in Advanced Audio settings for adaptive effects switching
  internal static var adaptiveEffectsHeader: String { return L10n.tr("Localizable", "adaptive_effects_header", fallback: "Adaptive Effects") }
  /// Toggle in Advanced Audio settings enabling automatic effects suspension during music
  internal static var adaptiveEffectsToggle: String { return L10n.tr("Localizable", "adaptive_effects_toggle", fallback: "Auto-Adjust for Music") }
  /// Title for an action that allows a user to create a new bookmark
  internal static var addBookmark: String { return L10n.tr("Localizable", "add_bookmark", fallback: "Add Bookmark") }
  /// The subtitle of a view where the user can edit their bookmark title
  internal static var addBookmarkSubtitle: String { return L10n.tr("Localizable", "add_bookmark_subtitle", fallback: "Add an optional title to identify this bookmark") }
  /// A common string used throughout the app. Title for the prompt to add an episode to the up next queue.
  internal static var addToUpNext: String { return L10n.tr("Localizable", "add_to_up_next", fallback: "Add to Up Next") }
  /// Advanced Audio - toggle for converging faster while far from the target loudness
  internal static var advancedAudioBoostAdaptiveSmoothing: String { return L10n.tr("Localizable", "advanced_audio_boost_adaptive_smoothing", fallback: "Adaptive smoothing") }
  /// Advanced Audio - slider for the compressor attack time
  internal static var advancedAudioBoostCompAttack: String { return L10n.tr("Localizable", "advanced_audio_boost_comp_attack", fallback: "Attack") }
  /// Advanced Audio - slider for the compressor soft knee width
  internal static var advancedAudioBoostCompKnee: String { return L10n.tr("Localizable", "advanced_audio_boost_comp_knee", fallback: "Knee width") }
  /// Advanced Audio - slider for the compression ratio
  internal static var advancedAudioBoostCompRatio: String { return L10n.tr("Localizable", "advanced_audio_boost_comp_ratio", fallback: "Ratio") }
  /// Advanced Audio - slider for the compressor release time
  internal static var advancedAudioBoostCompRelease: String { return L10n.tr("Localizable", "advanced_audio_boost_comp_release", fallback: "Release") }
  /// Advanced Audio - slider for the compressor threshold
  internal static var advancedAudioBoostCompThreshold: String { return L10n.tr("Localizable", "advanced_audio_boost_comp_threshold", fallback: "Threshold") }
  /// Advanced Audio - toggle for the compressor stage
  internal static var advancedAudioBoostCompressor: String { return L10n.tr("Localizable", "advanced_audio_boost_compressor", fallback: "Compressor") }
  /// Advanced Audio - header of the compressor and limiter section
  internal static var advancedAudioBoostDynamicsHeader: String { return L10n.tr("Localizable", "advanced_audio_boost_dynamics_header", fallback: "Voice Boost — Compressor & Limiter") }
  /// Advanced Audio - picker choosing the volume boost processing engine
  internal static var advancedAudioBoostEngine: String { return L10n.tr("Localizable", "advanced_audio_boost_engine", fallback: "Boost engine") }
  /// Advanced Audio - footer shown when the VoiceBoostN feature flag is off
  internal static var advancedAudioBoostEngineFooter: String { return L10n.tr("Localizable", "advanced_audio_boost_engine_footer", fallback: "The VoiceBoostN feature flag is currently off, so the legacy engine is used regardless of this setting.") }
  /// Advanced Audio - the original AudioUnit-based boost engine
  internal static var advancedAudioBoostEngineLegacy: String { return L10n.tr("Localizable", "advanced_audio_boost_engine_legacy", fallback: "Legacy") }
  /// Advanced Audio - the modern loudness-normalization boost engine
  internal static var advancedAudioBoostEngineModern: String { return L10n.tr("Localizable", "advanced_audio_boost_engine_modern", fallback: "VoiceBoostN") }
  /// Advanced Audio - slider for how quickly the gain converges on its target
  internal static var advancedAudioBoostGainSmoothing: String { return L10n.tr("Localizable", "advanced_audio_boost_gain_smoothing", fallback: "Gain smoothing") }
  /// Advanced Audio - header of the Voice Boost normalization section
  internal static var advancedAudioBoostHeader: String { return L10n.tr("Localizable", "advanced_audio_boost_header", fallback: "Voice Boost — Normalization") }
  /// Advanced Audio - toggle for the rumble high-pass filter
  internal static var advancedAudioBoostHighPass: String { return L10n.tr("Localizable", "advanced_audio_boost_high_pass", fallback: "High-pass filter") }
  /// Advanced Audio - slider for the high-pass cutoff frequency
  internal static var advancedAudioBoostHighPassFreq: String { return L10n.tr("Localizable", "advanced_audio_boost_high_pass_freq", fallback: "Cutoff frequency") }
  /// Advanced Audio - slider for the high-pass resonance (Q)
  internal static var advancedAudioBoostHighPassQ: String { return L10n.tr("Localizable", "advanced_audio_boost_high_pass_q", fallback: "Resonance (Q)") }
  /// Advanced Audio - slider for the limiter output ceiling
  internal static var advancedAudioBoostLimiterCeiling: String { return L10n.tr("Localizable", "advanced_audio_boost_limiter_ceiling", fallback: "Limiter ceiling") }
  /// Advanced Audio - slider for the limiter lookahead time
  internal static var advancedAudioBoostLimiterLookahead: String { return L10n.tr("Localizable", "advanced_audio_boost_limiter_lookahead", fallback: "Limiter lookahead") }
  /// Advanced Audio - slider for the limiter release time
  internal static var advancedAudioBoostLimiterRelease: String { return L10n.tr("Localizable", "advanced_audio_boost_limiter_release", fallback: "Limiter release") }
  /// Advanced Audio - slider for the maximum boost the normalizer may apply
  internal static var advancedAudioBoostMaxGain: String { return L10n.tr("Localizable", "advanced_audio_boost_max_gain", fallback: "Maximum gain") }
  /// Advanced Audio - slider for the maximum attenuation the normalizer may apply
  internal static var advancedAudioBoostMinGain: String { return L10n.tr("Localizable", "advanced_audio_boost_min_gain", fallback: "Minimum gain") }
  /// Advanced Audio - slider for the loudness normalization target
  internal static var advancedAudioBoostTargetLufs: String { return L10n.tr("Localizable", "advanced_audio_boost_target_lufs", fallback: "Target loudness") }
  /// Advanced Audio - footer explaining the loudness target measurement point
  internal static var advancedAudioBoostTargetLufsFooter: String { return L10n.tr("Localizable", "advanced_audio_boost_target_lufs_footer", fallback: "Target applies before compression; the compressor adds roughly 3 dB, so the default lands near -14 LUFS.") }
  /// Advanced Audio - toggle for oversampled inter-sample peak detection
  internal static var advancedAudioBoostTruePeak: String { return L10n.tr("Localizable", "advanced_audio_boost_true_peak", fallback: "True-peak detection") }
  /// Advanced Audio - footer explaining true-peak detection
  internal static var advancedAudioBoostTruePeakFooter: String { return L10n.tr("Localizable", "advanced_audio_boost_true_peak_footer", fallback: "True-peak detection catches inter-sample peaks with 4x oversampling at a small CPU cost.") }
  /// Advanced Audio - warning footer explaining these are expert DSP settings
  internal static var advancedAudioFooterWarning: String { return L10n.tr("Localizable", "advanced_audio_footer_warning", fallback: "These settings tune the audio engine directly. Defaults match standard playback; reset if something sounds wrong.") }
  /// Unit shown beside advanced-audio loudness targets; LUFS means Loudness Units relative to Full Scale.
  internal static var advancedAudioLoudnessUnitLufs: String { return L10n.tr("Localizable", "advanced_audio_loudness_unit_lufs", fallback: "LUFS") }
  /// Advanced Audio - label for the current normalization gain meter
  internal static var advancedAudioMetersGain: String { return L10n.tr("Localizable", "advanced_audio_meters_gain", fallback: "Applied gain") }
  /// Advanced Audio - header of the live meters section
  internal static var advancedAudioMetersHeader: String { return L10n.tr("Localizable", "advanced_audio_meters_header", fallback: "Live Status") }
  /// Advanced Audio - shown in the meters section while nothing is playing with Voice Boost
  internal static var advancedAudioMetersIdle: String { return L10n.tr("Localizable", "advanced_audio_meters_idle", fallback: "Play something with Volume Boost on to see live meters.") }
  /// Advanced Audio - label for the limiter gain-reduction meter
  internal static var advancedAudioMetersLimiter: String { return L10n.tr("Localizable", "advanced_audio_meters_limiter", fallback: "Limiter reduction") }
  /// Advanced Audio - label for the measured loudness meter
  internal static var advancedAudioMetersLufs: String { return L10n.tr("Localizable", "advanced_audio_meters_lufs", fallback: "Measured loudness") }
  /// Advanced Audio - button resetting every tuning parameter
  internal static var advancedAudioResetAll: String { return L10n.tr("Localizable", "advanced_audio_reset_all", fallback: "Reset All Tuning") }
  /// Advanced Audio - message of the reset-all confirmation alert
  internal static var advancedAudioResetConfirmMessage: String { return L10n.tr("Localizable", "advanced_audio_reset_confirm_message", fallback: "All parameters return to their defaults. Playback behaves exactly like standard Pocket Casts.") }
  /// Advanced Audio - title of the reset-all confirmation alert
  internal static var advancedAudioResetConfirmTitle: String { return L10n.tr("Localizable", "advanced_audio_reset_confirm_title", fallback: "Reset all audio tuning?") }
  /// Advanced Audio - button resetting one section's parameters
  internal static var advancedAudioResetSection: String { return L10n.tr("Localizable", "advanced_audio_reset_section", fallback: "Reset Section") }
  /// Advanced Audio - the classic speech-tuned time stretch algorithm
  internal static var advancedAudioStretchAlgoIpod: String { return L10n.tr("Localizable", "advanced_audio_stretch_algo_ipod", fallback: "Classic (speech-tuned)") }
  /// Advanced Audio - the spectral time stretch algorithm
  internal static var advancedAudioStretchAlgoSpectral: String { return L10n.tr("Localizable", "advanced_audio_stretch_algo_spectral", fallback: "Spectral") }
  /// Advanced Audio - the time-domain time stretch algorithm
  internal static var advancedAudioStretchAlgoTimeDomain: String { return L10n.tr("Localizable", "advanced_audio_stretch_algo_time_domain", fallback: "Time domain") }
  /// Advanced Audio - the varispeed algorithm that shifts pitch with speed
  internal static var advancedAudioStretchAlgoVarispeed: String { return L10n.tr("Localizable", "advanced_audio_stretch_algo_varispeed", fallback: "Varispeed (pitch shifts)") }
  /// Advanced Audio - picker for the streamed-audio time stretch algorithm
  internal static var advancedAudioStretchDefaultPlayer: String { return L10n.tr("Localizable", "advanced_audio_stretch_default_player", fallback: "Streamed audio") }
  /// Advanced Audio - picker for the downloaded-audio time stretch algorithm
  internal static var advancedAudioStretchEffectsPlayer: String { return L10n.tr("Localizable", "advanced_audio_stretch_effects_player", fallback: "Downloaded audio") }
  /// Advanced Audio - footer warning that changing the downloaded-audio algorithm restarts playback
  internal static var advancedAudioStretchFooter: String { return L10n.tr("Localizable", "advanced_audio_stretch_footer", fallback: "Changing the downloaded-audio algorithm briefly restarts playback.") }
  /// Advanced Audio - header of the time stretch section
  internal static var advancedAudioStretchHeader: String { return L10n.tr("Localizable", "advanced_audio_stretch_header", fallback: "Time Stretch") }
  /// Advanced Audio - toggle for tracking the recording's noise floor automatically
  internal static var advancedAudioTrimAdaptiveFloor: String { return L10n.tr("Localizable", "advanced_audio_trim_adaptive_floor", fallback: "Adaptive noise floor") }
  /// Advanced Audio - slider for how far above the noise floor the gate sits
  internal static var advancedAudioTrimAdaptiveOffset: String { return L10n.tr("Localizable", "advanced_audio_trim_adaptive_offset", fallback: "Floor offset") }
  /// Advanced Audio - slider for how much recent audio the noise floor tracks
  internal static var advancedAudioTrimAdaptiveWindow: String { return L10n.tr("Localizable", "advanced_audio_trim_adaptive_window", fallback: "Floor window") }
  /// Advanced Audio - slider for the crossfade length at each trim splice
  internal static var advancedAudioTrimCrossfade: String { return L10n.tr("Localizable", "advanced_audio_trim_crossfade", fallback: "Crossfade") }
  /// Advanced Audio - footer explaining the custom trim gate toggle
  internal static var advancedAudioTrimCustomFooter: String { return L10n.tr("Localizable", "advanced_audio_trim_custom_footer", fallback: "When Custom gate is on, these values replace the Low/Medium/High preset amounts chosen in playback effects.") }
  /// Advanced Audio - toggle replacing the Low/Medium/High presets with the custom values below
  internal static var advancedAudioTrimCustomToggle: String { return L10n.tr("Localizable", "advanced_audio_trim_custom_toggle", fallback: "Custom gate") }
  /// Advanced Audio - picker choosing how silence is detected
  internal static var advancedAudioTrimDiscriminator: String { return L10n.tr("Localizable", "advanced_audio_trim_discriminator", fallback: "Detection") }
  /// Advanced Audio - silence detection using loudness plus spectral heuristics
  internal static var advancedAudioTrimDiscriminatorHeuristic: String { return L10n.tr("Localizable", "advanced_audio_trim_discriminator_heuristic", fallback: "Heuristic") }
  /// Advanced Audio - silence detection using loudness only
  internal static var advancedAudioTrimDiscriminatorRms: String { return L10n.tr("Localizable", "advanced_audio_trim_discriminator_rms", fallback: "Loudness only") }
  /// Advanced Audio - silence detection assisted by the system speech classifier
  internal static var advancedAudioTrimDiscriminatorVad: String { return L10n.tr("Localizable", "advanced_audio_trim_discriminator_vad", fallback: "Speech detection") }
  /// Advanced Audio - slider for how many final seconds of an episode are never trimmed
  internal static var advancedAudioTrimEndGuard: String { return L10n.tr("Localizable", "advanced_audio_trim_end_guard", fallback: "End guard") }
  /// Advanced Audio - slider for the spectral flatness above which quiet audio counts as silence
  internal static var advancedAudioTrimFlatnessThreshold: String { return L10n.tr("Localizable", "advanced_audio_trim_flatness_threshold", fallback: "Flatness threshold") }
  /// Advanced Audio - header of the trim silence tuning section
  internal static var advancedAudioTrimHeader: String { return L10n.tr("Localizable", "advanced_audio_trim_header", fallback: "Trim Silence") }
  /// Advanced Audio - slider for how long the gate stays open after speech resumes
  internal static var advancedAudioTrimHold: String { return L10n.tr("Localizable", "advanced_audio_trim_hold", fallback: "Hold time") }
  /// Advanced Audio - slider for the gap between the gate's close and reopen thresholds
  internal static var advancedAudioTrimHysteresis: String { return L10n.tr("Localizable", "advanced_audio_trim_hysteresis", fallback: "Hysteresis") }
  /// Advanced Audio - slider for how much of each trimmed pause is kept
  internal static var advancedAudioTrimKeepGap: String { return L10n.tr("Localizable", "advanced_audio_trim_keep_gap", fallback: "Kept pause") }
  /// Advanced Audio - menu seeding the custom trim values from a preset
  internal static var advancedAudioTrimLoadPreset: String { return L10n.tr("Localizable", "advanced_audio_trim_load_preset", fallback: "Load Values From Preset") }
  /// Advanced Audio - slider for the shortest pause that can be trimmed
  internal static var advancedAudioTrimMinGap: String { return L10n.tr("Localizable", "advanced_audio_trim_min_gap", fallback: "Minimum gap") }
  /// Advanced Audio - slider for the silence gate threshold in decibels
  internal static var advancedAudioTrimThreshold: String { return L10n.tr("Localizable", "advanced_audio_trim_threshold", fallback: "Threshold") }
  /// Advanced Audio - slider for the speech confidence that blocks a trim
  internal static var advancedAudioTrimVadConfidence: String { return L10n.tr("Localizable", "advanced_audio_trim_vad_confidence", fallback: "Speech confidence") }
  /// Advanced Audio - slider for how far below the gate fricative protection applies
  internal static var advancedAudioTrimZcrMargin: String { return L10n.tr("Localizable", "advanced_audio_trim_zcr_margin", fallback: "Protection margin") }
  /// Advanced Audio - slider for the zero-crossing rate protecting quiet consonants
  internal static var advancedAudioTrimZcrThreshold: String { return L10n.tr("Localizable", "advanced_audio_trim_zcr_threshold", fallback: "Fricative protection") }
  /// A common string used throughout the app. Option that determines the behavior of the app after playing an item.
  internal static var afterPlaying: String { return L10n.tr("Localizable", "after_playing", fallback: "After Playing") }
  /// Search Results filter option
  internal static var allResults: String { return L10n.tr("Localizable", "all_results", fallback: "Top Results") }
  /// Autoplay feature announcement description
  internal static var announcementAutoplayDescription: String { return L10n.tr("Localizable", "announcement_autoplay_description", fallback: "If your Up Next queue is empty and you start listening to an episode, Autoplay will keep playing episodes from that show or list.") }
  /// Autoplay feature announcement title
  internal static var announcementAutoplayTitle: String { return L10n.tr("Localizable", "announcement_autoplay_title", fallback: "Autoplay is here!") }
  /// Bookmarks feature announcement description
  internal static var announcementBookmarksDescription: String { return L10n.tr("Localizable", "announcement_bookmarks_description", fallback: "You can now save timestamps of episodes from the actions menu in the player or with a headphones action.") }
  /// Bookmarks feature announcement title
  internal static var announcementBookmarksTitle: String { return L10n.tr("Localizable", "announcement_bookmarks_title", fallback: "Bookmarks are here!") }
  /// Bookmarks feature announcement title
  internal static var announcementBookmarksTitleBeta: String { return L10n.tr("Localizable", "announcement_bookmarks_title_beta", fallback: "Join us in the beta testing for bookmarks!") }
  /// Announcement of Preselect Chapters for free users
  internal static var announcementDeselectChaptersFree: String { return L10n.tr("Localizable", "announcement_deselect_chapters_free", fallback: "Subscribe to Plus now so you can preselect and skip chapters automatically in any episode that supports them.") }
  /// Announcement of Preselect Chapters for Patron users
  internal static var announcementDeselectChaptersPatron: String { return L10n.tr("Localizable", "announcement_deselect_chapters_patron", fallback: "As part of your Patron subscription, you can now preselect and skip chapters automatically in any episode that supports them.") }
  /// Announcement of Preselect Chapters for Plus users
  internal static var announcementDeselectChaptersPlus: String { return L10n.tr("Localizable", "announcement_deselect_chapters_plus", fallback: "As part of your Plus subscription, you can now preselect and skip chapters automatically in any episode that supports them.") }
  /// Message shown when the code is copied to clipboard
  internal static var announcementSlumberCodeCopied: String { return L10n.tr("Localizable", "announcement_slumber_code_copied", fallback: "Code copied to clipboard") }
  /// Slumber Studios partnership announcement description. %1$@ is a promo code.
  internal static func announcementSlumberDescription(_ p1: Any) -> String {
    return L10n.tr("Localizable", "announcement_slumber_description", String(describing: p1), fallback: "Enjoy a 1-year subscription to Slumber Studios content using code %1$@. Learn more.")
  }
  /// Should match the "Learn more" translation on announcement_slumber_description
  internal static var announcementSlumberDescriptionLearnMore: String { return L10n.tr("Localizable", "announcement_slumber_description_learn_more", fallback: "Learn more") }
  /// Slumber Studios partnership announcement description for non-subscribed users
  internal static var announcementSlumberNonPlusDescription: String { return L10n.tr("Localizable", "announcement_slumber_non_plus_description", fallback: "Subscribe to Plus Yearly and enjoy a 1-year subscription to Slumber Studios content, podcasts designed for the sweetest dreams. Learn more.") }
  /// Slumber Studios partnership announcement description for subscribed users
  internal static func announcementSlumberPlusDescription(_ p1: Any) -> String {
    return L10n.tr("Localizable", "announcement_slumber_plus_description", String(describing: p1), fallback: "As part of your Yearly Plus subscription, enjoy a 1-year subscription to Slumber Studios content using code %1$@. Learn more.")
  }
  /// Should match the "Learn more" translation on announcement_slumber_plus_description and announcement_slumber_non_plus_description
  internal static var announcementSlumberPlusDescriptionLearnMore: String { return L10n.tr("Localizable", "announcement_slumber_plus_description_learn_more", fallback: "Learn more") }
  /// Button label for a feature the user can redeem using a code
  internal static var announcementSlumberRedeem: String { return L10n.tr("Localizable", "announcement_slumber_redeem", fallback: "Redeem your code") }
  /// Slumber Studios partnership feature announcement title
  internal static var announcementSlumberTitle: String { return L10n.tr("Localizable", "announcement_slumber_title", fallback: "Dream big") }
  /// A common string used throughout the app. References to Badge settings for the app.
  internal static var appBadge: String { return L10n.tr("Localizable", "app_badge", fallback: "App Badge") }
  /// The name for the Classic App Icon
  internal static var appIconClassic: String { return L10n.tr("Localizable", "app_icon_classic", fallback: "Classic") }
  /// The name for the Dark App Icon
  internal static var appIconDark: String { return L10n.tr("Localizable", "app_icon_dark", fallback: "Dark") }
  /// The name for the Default App Icon
  internal static var appIconDefault: String { return L10n.tr("Localizable", "app_icon_default", fallback: "Default") }
  /// The name for the Electric Blue App Icon
  internal static var appIconElectricBlue: String { return L10n.tr("Localizable", "app_icon_electric_blue", fallback: "Electric Blue") }
  /// The name for the Electric Pink App Icon
  internal static var appIconElectricPink: String { return L10n.tr("Localizable", "app_icon_electric_pink", fallback: "Electric Pink") }
  /// Halloween app icon name
  internal static var appIconHalloween: String { return L10n.tr("Localizable", "app_icon_halloween", fallback: "Halloween") }
  /// The name for the Indigo App Icon
  internal static var appIconIndigo: String { return L10n.tr("Localizable", "app_icon_indigo", fallback: "Indigo") }
  /// The name for the chrome App Icon
  internal static var appIconPatronChrome: String { return L10n.tr("Localizable", "app_icon_patron_chrome", fallback: "Chrome") }
  /// The name for the violet dark App Icon
  internal static var appIconPatronDark: String { return L10n.tr("Localizable", "app_icon_patron_dark", fallback: "Violet Dark") }
  /// The name for the violet glow App Icon
  internal static var appIconPatronGlow: String { return L10n.tr("Localizable", "app_icon_patron_glow", fallback: "Violet Glow") }
  /// The name for the violet round App Icon
  internal static var appIconPatronRound: String { return L10n.tr("Localizable", "app_icon_patron_round", fallback: "Violet Round") }
  /// The name for the gold App Icon
  internal static var appIconPlus: String { return L10n.tr("Localizable", "app_icon_plus", fallback: "Gold") }
  /// The name for the Pocket Cats App Icon. The name for this one is meant to be a play on the App name Pocket Casts and the icon includes a cat image.
  internal static var appIconPocketCats: String { return L10n.tr("Localizable", "app_icon_pocket_cats", fallback: "Pocket Cats") }
  /// The name for the Radioactivity App Icon
  internal static var appIconRadioactivity: String { return L10n.tr("Localizable", "app_icon_radioactivity", fallback: "Radioactivity") }
  /// The name for the Red Velvet App Icon
  internal static var appIconRedVelvet: String { return L10n.tr("Localizable", "app_icon_red_velvet", fallback: "Red Velvet") }
  /// The name for the Rosé App Icon
  internal static var appIconRose: String { return L10n.tr("Localizable", "app_icon_rose", fallback: "Rosé") }
  /// The name for the Round Dark App Icon
  internal static var appIconRoundDark: String { return L10n.tr("Localizable", "app_icon_round_dark", fallback: "Round Dark") }
  /// The name for the Round Light App Icon
  internal static var appIconRoundLight: String { return L10n.tr("Localizable", "app_icon_round_light", fallback: "Round Light") }
  /// The app name shown when subscription UI needs a generic Pocket Casts label.
  internal static var appPocketCastsName: String { return L10n.tr("Localizable", "app_pocket_casts_name", fallback: "Pocket Casts") }
  /// Text sent when sharing a link to our app with other people
  internal static var appShareText: String { return L10n.tr("Localizable", "app_share_text", fallback: "Hey! Here is a link to download the Pocket Casts app. I'm really enjoying it and thought you might too.") }
  /// App version label in the about controller. `%1$@` is a placeholder for the version number and %2$@ is a placeholder for the build number
  internal static func appVersion(_ p1: Any, _ p2: Any) -> String {
    return L10n.tr("Localizable", "app_version", String(describing: p1), String(describing: p2), fallback: "Version %1$@ (%2$@)")
  }
  /// Section header for the appearance settings related to app icons.
  internal static var appearanceAppIconHeader: String { return L10n.tr("Localizable", "appearance_app_icon_header", fallback: "App Icon") }
  /// Section header for the appearance settings related to artwork.
  internal static var appearanceArtworkHeader: String { return L10n.tr("Localizable", "appearance_artwork_header", fallback: "Podcast Artwork") }
  /// Label for letting the user choose a theme for iOS dark mode.
  internal static var appearanceDarkTheme: String { return L10n.tr("Localizable", "appearance_dark_theme", fallback: "Dark Theme") }
  /// Prompt to toggle on the use of artwork per episode, as opposed to per podcast.
  internal static var appearanceEmbeddedArtwork: String { return L10n.tr("Localizable", "appearance_embedded_artwork", fallback: "Use Episode Artwork") }
  /// Subtitle explaining episode artwork.
  internal static var appearanceEmbeddedArtworkSubtitle: String { return L10n.tr("Localizable", "appearance_embedded_artwork_subtitle", fallback: "Some shows have custom artwork for certain episodes. Enable this option and Pocket Casts will display them instead of the show’s artwork.") }
  /// Label for letting the user choose a theme for iOS light mode.
  internal static var appearanceLightTheme: String { return L10n.tr("Localizable", "appearance_light_theme", fallback: "Light Theme") }
  /// Prompt to toggle whether the theme will match the device theme or not.
  internal static var appearanceMatchDeviceTheme: String { return L10n.tr("Localizable", "appearance_match_device_theme", fallback: "Use iOS Light/Dark Mode") }
  /// Prompt to refresh the artwork for all podcasts.
  internal static var appearanceRefreshAllArtwork: String { return L10n.tr("Localizable", "appearance_refresh_all_artwork", fallback: "Refresh All Podcast Artwork") }
  /// Confirmation message used to inform the user that the refresh has been successfully triggered.
  internal static var appearanceRefreshAllArtworkConfMsg: String { return L10n.tr("Localizable", "appearance_refresh_all_artwork_conf_msg", fallback: "Refreshing your artwork now") }
  /// Confirmation title used to inform the user that the refresh has been successfully triggered.
  internal static var appearanceRefreshAllArtworkConfTitle: String { return L10n.tr("Localizable", "appearance_refresh_all_artwork_conf_title", fallback: "Aye Aye Captain") }
  /// Section header for the appearance settings related to the tab bar.
  internal static var appearanceTabBarHeader: String { return L10n.tr("Localizable", "appearance_tab_bar_header", fallback: "Tab Bar") }
  /// Toggle that controls whether the tab bar shrinks into a compact pill as the user scrolls (iOS 26 Liquid Glass).
  internal static var appearanceTabBarMinimizing: String { return L10n.tr("Localizable", "appearance_tab_bar_minimizing", fallback: "Minimize on Scroll") }
  /// Subtitle explaining the tab bar minimize-on-scroll toggle.
  internal static var appearanceTabBarMinimizingFooter: String { return L10n.tr("Localizable", "appearance_tab_bar_minimizing_footer", fallback: "When enabled, the tab bar shrinks into a compact pill as you scroll down so more content stays in view.") }
  /// Section header for the appearance settings related to themes.
  internal static var appearanceThemeHeader: String { return L10n.tr("Localizable", "appearance_theme_header", fallback: "Theme") }
  /// Header for asking the user to select a theme.
  internal static var appearanceThemeSelect: String { return L10n.tr("Localizable", "appearance_theme_select", fallback: "Select Theme") }
  /// A common string used throughout the app. Prompt to archive the selected item(s).
  internal static var archive: String { return L10n.tr("Localizable", "archive", fallback: "Archive") }
  /// A common string used throughout the app. Confirmation prompt before moving forward.
  internal static var areYouSure: String { return L10n.tr("Localizable", "are_you_sure", fallback: "Are You Sure?") }
  /// A common string used throughout the app. Prompt to configure the auto add options for a podcast.
  internal static var autoAdd: String { return L10n.tr("Localizable", "auto_add", fallback: "Auto Add To") }
  /// Option in the auto add dialog to add the items to the bottom of the queue.
  internal static var autoAddToBottom: String { return L10n.tr("Localizable", "auto_add_to_bottom", fallback: "To Bottom") }
  /// Option in the auto add dialog to add the items to the top of the queue.
  internal static var autoAddToTop: String { return L10n.tr("Localizable", "auto_add_to_top", fallback: "To Top") }
  /// Option in the auto add settings to stop adding options once the limit is reached. This option won't add new episodes.
  internal static var autoAddToUpNextStop: String { return L10n.tr("Localizable", "auto_add_to_up_next_stop", fallback: "Stop Adding New Episodes") }
  /// Option in the auto add settings to stop adding options once the limit is reached. This option won't add new episodes. To conserve space this should be a more concise version of 'Stop Adding New Episodes'
  internal static var autoAddToUpNextStopShort: String { return L10n.tr("Localizable", "auto_add_to_up_next_stop_short", fallback: "Stop Adding") }
  /// Option in the auto add settings to stop adding options once the limit is reached. This option will add the podcast to the top top the queue and drop the bottom.
  internal static var autoAddToUpNextTopOnly: String { return L10n.tr("Localizable", "auto_add_to_up_next_top_only", fallback: "Only Add To Top") }
  /// Option in the auto add settings to stop adding options once the limit is reached. This option will add the podcast to the top top the queue and drop the bottom. To conserve space this shouldn't be longer than the English string. If needed "Add To Top" or "To Top" can be translated instead
  internal static var autoAddToUpNextTopOnlyShort: String { return L10n.tr("Localizable", "auto_add_to_up_next_top_only_short", fallback: "Only Add To Top") }
  /// Title for the dialog box that presents the available options for how many episodes for auto download from a filter.
  internal static var autoDownloadFirst: String { return L10n.tr("Localizable", "auto_download_first", fallback: "Auto Download First") }
  /// Auto Downloads Setting - Limits downloads picker title
  internal static var autoDownloadLimitAutoDownloads: String { return L10n.tr("Localizable", "auto_download_limit_auto_downloads", fallback: "Limit auto downloads") }
  /// Auto Downloads Setting - Limits downloads row title
  internal static var autoDownloadLimitDownloads: String { return L10n.tr("Localizable", "auto_download_limit_downloads", fallback: "Limit Downloads") }
  /// Auto Downloads Setting - Limits downloads to a number of episodes. `%1$@' is a placeholder for the number of episodes
  internal static func autoDownloadLimitNumberOfEpisodes(_ p1: Any) -> String {
    return L10n.tr("Localizable", "auto_download_limit_number_of_episodes", String(describing: p1), fallback: "%1$@ Episodes")
  }
  /// Auto Downloads Setting - Limits downloads to a number of show episodes. `%1$@' is a placeholder for the number of episodes
  internal static func autoDownloadLimitNumberOfEpisodesShow(_ p1: Any) -> String {
    return L10n.tr("Localizable", "auto_download_limit_number_of_episodes_show", String(describing: p1), fallback: "%1$@ Latest Episodes per Show")
  }
  /// Auto Downloads Setting - Limits downloads to one episodes.
  internal static var autoDownloadLimitOneEpisode: String { return L10n.tr("Localizable", "auto_download_limit_one_episode", fallback: "Latest Episode") }
  /// Auto Downloads Setting - Limits downloads to the latest episode
  internal static var autoDownloadLimitOneEpisodeShow: String { return L10n.tr("Localizable", "auto_download_limit_one_episode_show", fallback: "Latest Episode per Show") }
  /// Subtitle for the auto download setting. This is displayed when the option is turned off.
  internal static var autoDownloadOffSubtitle: String { return L10n.tr("Localizable", "auto_download_off_subtitle", fallback: "Enable to auto download episodes in this filter") }
  /// Subtitle for the auto download setting. This is displayed when the option is turned on. '%1$@' is a placeholder for the number of episodes, this will be more than one.
  internal static func autoDownloadOnPluralFormat(_ p1: Any) -> String {
    return L10n.tr("Localizable", "auto_download_on_plural_format", String(describing: p1), fallback: "The first %1$@ episodes in this filter will be automatically downloaded")
  }
  /// Provides hint text to auto download the a the first of a configurable amount of episodes. Accompanied by a label indicating how many episodes will be auto downloaded.
  internal static var autoDownloadPromptFirst: String { return L10n.tr("Localizable", "auto_download_prompt_first", fallback: "First") }
  /// Name of the option to restart sleep timer
  internal static var autoRestartSleepTimer: String { return L10n.tr("Localizable", "auto_restart_sleep_timer", fallback: "Auto Restart Sleep Timer") }
  /// Description of the option to restart sleep timer
  internal static var autoRestartSleepTimerDescription: String { return L10n.tr("Localizable", "auto_restart_sleep_timer_description", fallback: "If on, the sleep timer will restart automatically if you play an episode within 5 minutes after the last pause.") }
  /// A common string used throughout the app. Title for the back button. Used with the accessibility settings.
  internal static var back: String { return L10n.tr("Localizable", "back", fallback: "Back") }
  /// Section title for diagnostic tools in the beta menu.
  internal static var betaMenuDiagnosticsTitle: String { return L10n.tr("Localizable", "beta_menu_diagnostics_title", fallback: "Diagnostics") }
  /// Button and screen title for viewing collected MetricKit payload files.
  internal static var betaMenuMetricKitPayloadsTitle: String { return L10n.tr("Localizable", "beta_menu_metric_kit_payloads_title", fallback: "MetricKit Payloads") }
  /// Message of an alert that informs the user purchasing is disabled in the beta. 'Pocket Casts' is treated as a proper noun and hasn't been localized in other places of the app. %1$@ is the name of the tier (Plus or Patron)
  internal static func betaPurchaseDisabled(_ p1: Any) -> String {
    return L10n.tr("Localizable", "beta_purchase_disabled", String(describing: p1), fallback: "Please download Pocket Casts from the App Store to purchase %1$@.")
  }
  /// Title of a message thanking the user for being a beta tester
  internal static var betaThankYou: String { return L10n.tr("Localizable", "beta_thank_you", fallback: "Thank you for beta testing!") }
  /// Empty state message for the books directory.
  internal static var bookDirectoryEmptyMessage: String { return L10n.tr("Localizable", "book_directory_empty_message", fallback: "Books mentioned in episodes you view will collect here.") }
  /// Empty state title for the books directory.
  internal static var bookDirectoryEmptyTitle: String { return L10n.tr("Localizable", "book_directory_empty_title", fallback: "No books yet") }
  /// Book row subtitle; placeholder is the number of episodes mentioning it.
  internal static func bookDirectoryEpisodeCountPlural(_ p1: Any) -> String {
    return L10n.tr("Localizable", "book_directory_episode_count_plural", String(describing: p1), fallback: "Mentioned in %1$@ episodes")
  }
  /// Book row subtitle when the book was mentioned in exactly one episode.
  internal static var bookDirectoryEpisodeCountSingular: String { return L10n.tr("Localizable", "book_directory_episode_count_singular", fallback: "Mentioned in 1 episode") }
  /// Title of the Mentioned Books directory (Profile tab).
  internal static var bookDirectoryTitle: String { return L10n.tr("Localizable", "book_directory_title", fallback: "Mentioned Books") }
  /// A message that appears to inform the user their bookmark is added
  internal static var bookmarkAdded: String { return L10n.tr("Localizable", "bookmark_added", fallback: "Bookmark added") }
  /// Title of a button that allows the user to view their bookmarks
  internal static var bookmarkAddedButtonTitle: String { return L10n.tr("Localizable", "bookmark_added_button_title", fallback: "View") }
  /// A message that appears after the user created a bookmark and %1$@ displays the title they choose for it.
  internal static func bookmarkAddedNotification(_ p1: Any) -> String {
    return L10n.tr("Localizable", "bookmark_added_notification", String(describing: p1), fallback: "Bookmark \"%1$@\" added")
  }
  /// The default title to use for a bookmark
  internal static var bookmarkDefaultTitle: String { return L10n.tr("Localizable", "bookmark_default_title", fallback: "Bookmark") }
  /// The body of an alert message asking the user if they want to continue with deleting the selected bookmarks
  internal static var bookmarkDeleteWarningBody: String { return L10n.tr("Localizable", "bookmark_delete_warning_body", fallback: "Are you sure you want to delete these bookmarks, there’s no way to undo it!") }
  /// The title of an alert message asking the user if they want to continue with deleting the selected bookmarks
  internal static var bookmarkDeleteWarningTitle: String { return L10n.tr("Localizable", "bookmark_delete_warning_title", fallback: "Delete Bookmarks?") }
  /// Body of a message when no search results appear
  internal static var bookmarkSearchNoResultsMessage: String { return L10n.tr("Localizable", "bookmark_search_no_results_message", fallback: "We couldn't find any bookmarks for that search.") }
  /// Title of a message when no search results appear
  internal static var bookmarkSearchNoResultsTitle: String { return L10n.tr("Localizable", "bookmark_search_no_results_title", fallback: "No bookmarks found") }
  /// A message that appears after the user updates a bookmark and %1$@ displays the title they choose for it.
  internal static func bookmarkUpdatedNotification(_ p1: Any) -> String {
    return L10n.tr("Localizable", "bookmark_updated_notification", String(describing: p1), fallback: "Bookmark \"%1$@\" updated")
  }
  /// The plural name of a feature called Bookmarks, used in various places in the app
  internal static var bookmarks: String { return L10n.tr("Localizable", "bookmarks", fallback: "Bookmarks") }
  /// Label for displaying the number of bookmarks the user has when the bookmark count is more than one
  internal static func bookmarksCountPlural(_ p1: Any) -> String {
    return L10n.tr("Localizable", "bookmarks_count_plural", String(describing: p1), fallback: "%1$@ bookmarks")
  }
  /// Label for displaying the number of bookmarks the user has when the bookmark count is equal to one
  internal static var bookmarksCountSingular: String { return L10n.tr("Localizable", "bookmarks_count_singular", fallback: "1 bookmark") }
  /// A message informing the user a feature is locked while in early access. %1$@ and %2$@ are the names of the tier (Plus or Patron)
  internal static func bookmarksEarlyAccessLockedMessage(_ p1: Any, _ p2: Any) -> String {
    return L10n.tr("Localizable", "bookmarks_early_access_locked_message", String(describing: p1), String(describing: p2), fallback: "Unlock this feature and many more with Pocket Casts %1$@ and save timestamps of your favorite episodes. Available for %2$@ subscribers soon.")
  }
  /// Option menu action that exports the bookmark list as a Markdown document
  internal static var bookmarksExportOption: String { return L10n.tr("Localizable", "bookmarks_export_option", fallback: "Export as Markdown") }
  /// Heading used in the bookmark Markdown export when an episode no longer exists
  internal static var bookmarksExportUnknownEpisode: String { return L10n.tr("Localizable", "bookmarks_export_unknown_episode", fallback: "Unknown Episode") }
  /// Heading used in the bookmark Markdown export when a podcast no longer exists
  internal static var bookmarksExportUnknownPodcast: String { return L10n.tr("Localizable", "bookmarks_export_unknown_podcast", fallback: "Unknown Podcast") }
  /// Tag-filter option that clears the filter and shows every bookmark.
  internal static var bookmarksFilterAllTags: String { return L10n.tr("Localizable", "bookmarks_filter_all_tags", fallback: "All Tags") }
  /// Bookmark list menu option that filters the list to a single tag.
  internal static var bookmarksFilterByTag: String { return L10n.tr("Localizable", "bookmarks_filter_by_tag", fallback: "Filter by Tag") }
  /// A message informing the user a feature is locked. %1$@ is the name of the tier (Plus or Patron)
  internal static func bookmarksLockedMessage(_ p1: Any) -> String {
    return L10n.tr("Localizable", "bookmarks_locked_message", String(describing: p1), fallback: "Unlock this feature and many more with Pocket Casts %1$@ and save timestamps of your favorite episodes.")
  }
  /// A common string used throughout the app. Title option to place the item at the bottom of the queue.
  internal static var bottom: String { return L10n.tr("Localizable", "bottom", fallback: "Bottom") }
  /// A common string used throughout the app. Informs the user of the maximum amount of bulk downloads. '%1$@' is a placeholder for maximum amount of bulk downloads.
  internal static func bulkDownloadMaxFormat(_ p1: Any) -> String {
    return L10n.tr("Localizable", "bulk_download_max_format", String(describing: p1), fallback: "Bulk downloads are limited to %1$@.")
  }
  /// A common string used throughout the app. Prompt to cancel the current flow.
  internal static var cancel: String { return L10n.tr("Localizable", "cancel", fallback: "Cancel") }
  /// Button title that lets the user continue the cancellation process
  internal static var cancelConfirmCancelButtonTitle: String { return L10n.tr("Localizable", "cancel_confirm_cancel_button_title", fallback: "Cancel my subscription") }
  /// Title of a list item that informs the user their folders will be removed if they cancel
  internal static var cancelConfirmItemFolders: String { return L10n.tr("Localizable", "cancel_confirm_item_folders", fallback: "Your folders will be removed and their contents will move back to the Podcasts screen.") }
  /// Title of a list item that informs the user will continue access listening history and podcasts
  internal static var cancelConfirmItemHistory: String { return L10n.tr("Localizable", "cancel_confirm_item_history", fallback: "Your podcasts and listening history will continue to be accessible. ") }
  /// Title of a list item that informs the user their plus features will be locked if they cancel
  internal static var cancelConfirmItemPlus: String { return L10n.tr("Localizable", "cancel_confirm_item_plus", fallback: "After this date, access to Plus features like bookmarks, shuffle, wearables and more will be removed.") }
  /// Title of a list item that informs the user they will no longer be able to access plus on the web if they cancel
  internal static var cancelConfirmItemWebPlayer: String { return L10n.tr("Localizable", "cancel_confirm_item_web_player", fallback: "You will no longer be able to access Pocket Casts using your web browser, or desktop computer.") }
  /// Button title that lets the user stop the cancellation process
  internal static var cancelConfirmStayButtonTitle: String { return L10n.tr("Localizable", "cancel_confirm_stay_button_title", fallback: "Keep my subscription") }
  /// Title of a list item that informs the user the date their subscription will expire. %1$@ is the date of expiration
  internal static func cancelConfirmSubExpiry(_ p1: Any) -> String {
    return L10n.tr("Localizable", "cancel_confirm_sub_expiry", String(describing: p1), fallback: "Your current subscription will remain active until %1$@.")
  }
  /// Item that appears in place of the user's missing expiration date if it's not available.
  internal static var cancelConfirmSubExpiryDateFallback: String { return L10n.tr("Localizable", "cancel_confirm_sub_expiry_date_fallback", fallback: "your expiration date") }
  /// Sub title of a view that informs the user what will happen if they cancel their subscription
  internal static var cancelConfirmSubtitle: String { return L10n.tr("Localizable", "cancel_confirm_subtitle", fallback: "Canceling will change your plan to a free account.") }
  /// Title of a view that informs the user what will happen if they cancel their subscription
  internal static var cancelConfirmTitle: String { return L10n.tr("Localizable", "cancel_confirm_title", fallback: "Things you should know before you cancel") }
  /// A common string used throughout the app. Prompt to cancel the download for the selected item(s).
  internal static var cancelDownload: String { return L10n.tr("Localizable", "cancel_download", fallback: "Cancel Download") }
  /// Message title indicating that the cancel process has failed.
  internal static var cancelFailed: String { return L10n.tr("Localizable", "cancel_failed", fallback: "Unable To Cancel") }
  /// Prompt to allow the user to cancel their Pocket Casts Plus subscription.
  internal static var cancelSubscription: String { return L10n.tr("Localizable", "cancel_subscription", fallback: "Cancel Subscription") }
  /// Badge that appears over the best value plan in the available plans list
  internal static var cancelSubscriptionAvailablePlansBestValueBadge: String { return L10n.tr("Localizable", "cancel_subscription_available_plans_best_value_badge", fallback: "Best Value") }
  /// Footer of the Available Plans screen accessible from the Cancel Subscription view
  internal static var cancelSubscriptionAvailablePlansFooter: String { return L10n.tr("Localizable", "cancel_subscription_available_plans_footer", fallback: "Your new plan will activate at the end of your current billing period.") }
  /// Text displayed when the retry screen is visible
  internal static var cancelSubscriptionAvailablePlansRetryScreenText: String { return L10n.tr("Localizable", "cancel_subscription_available_plans_retry_screen_text", fallback: "Sorry, but something went wrong fetching your plans.") }
  /// Title of the Available Plans screen accessible from the Cancel Subscription view
  internal static var cancelSubscriptionAvailablePlansTitle: String { return L10n.tr("Localizable", "cancel_subscription_available_plans_title", fallback: "Available Plans") }
  /// Title for the claim offer button
  internal static var cancelSubscriptionClaimOfferButton: String { return L10n.tr("Localizable", "cancel_subscription_claim_offer_button", fallback: "Claim offer") }
  /// Title for the continue button
  internal static var cancelSubscriptionContinueButton: String { return L10n.tr("Localizable", "cancel_subscription_continue_button", fallback: "Continue with cancellation") }
  /// Generic error if the product loading fails
  internal static var cancelSubscriptionGenericError: String { return L10n.tr("Localizable", "cancel_subscription_generic_error", fallback: "An error occurred. Please try again later.") }
  /// Cancel subscription: description for the help row
  internal static var cancelSubscriptionHelpDescription: String { return L10n.tr("Localizable", "cancel_subscription_help_description", fallback: "Struggling with any features or having issues.") }
  /// Cancel subscription: title for the help row
  internal static var cancelSubscriptionHelpTitle: String { return L10n.tr("Localizable", "cancel_subscription_help_title", fallback: "Need help with Pocket Casts?") }
  /// Cancel subscription: description for the new plan row
  internal static var cancelSubscriptionNewPlanDescription: String { return L10n.tr("Localizable", "cancel_subscription_new_plan_description", fallback: "Find the plan that’s right for you.") }
  /// Cancel subscription: title for the new plan row
  internal static var cancelSubscriptionNewPlanTitle: String { return L10n.tr("Localizable", "cancel_subscription_new_plan_title", fallback: "Looking for a different plan?") }
  /// Description of the success screen when the cancel subscription offer is applied
  internal static var cancelSubscriptionOfferSuccessViewDescription: String { return L10n.tr("Localizable", "cancel_subscription_offer_success_view_description", fallback: "Thanks for choosing Pocket Casts. Your free month will be added to your current subscription.") }
  /// Title of the success screen when the cancel subscription offer is applied
  internal static var cancelSubscriptionOfferSuccessViewTitle: String { return L10n.tr("Localizable", "cancel_subscription_offer_success_view_title", fallback: "Enjoy your free month!") }
  /// Description of the success screen when the cancel yearly subscription offer is applied
  internal static var cancelSubscriptionOfferYearlySuccessViewDescription: String { return L10n.tr("Localizable", "cancel_subscription_offer_yearly_success_view_description", fallback: "Thanks for choosing Pocket Casts. Your discounted year begins after your current plan ends.") }
  /// Title of the success screen when the cancel yearly subscription offer is applied
  internal static var cancelSubscriptionOfferYearlySuccessViewTitle: String { return L10n.tr("Localizable", "cancel_subscription_offer_yearly_success_view_title", fallback: "50%% off your next year!") }
  /// Cancel subscription: description for the monthly promotion row. The %@ represents the price.
  internal static func cancelSubscriptionPromotionDescriptionMonthly(_ p1: Any) -> String {
    return L10n.tr("Localizable", "cancel_subscription_promotion_description_monthly", String(describing: p1), fallback: "Save %@ at the start of your next billing cycle.")
  }
  /// Cancel subscription: description for the yearly promotion row. The %@ represents the price.
  internal static func cancelSubscriptionPromotionDescriptionYearly(_ p1: Any) -> String {
    return L10n.tr("Localizable", "cancel_subscription_promotion_description_yearly", String(describing: p1), fallback: "Pay %@ now for another year at 50%% off")
  }
  /// Cancel subscription: title for the promotion row
  internal static var cancelSubscriptionPromotionTitle: String { return L10n.tr("Localizable", "cancel_subscription_promotion_title", fallback: "Get your next month free") }
  /// Description of the survey screen that appears when a user cancels the subscription
  internal static var cancelSubscriptionSurveyDescription: String { return L10n.tr("Localizable", "cancel_subscription_survey_description", fallback: "We'd love to know why you canceled. Your feedback helps us improve.") }
  /// Option in the in the survey screen that appears when a user cancels the subscription
  internal static var cancelSubscriptionSurveyRowBetterApp: String { return L10n.tr("Localizable", "cancel_subscription_survey_row_better_app", fallback: "I found a better app") }
  /// Option in the in the survey screen that appears when a user cancels the subscription
  internal static var cancelSubscriptionSurveyRowCost: String { return L10n.tr("Localizable", "cancel_subscription_survey_row_cost", fallback: "Cost-related reasons") }
  /// Option in the in the survey screen that appears when a user cancels the subscription
  internal static var cancelSubscriptionSurveyRowNotEnough: String { return L10n.tr("Localizable", "cancel_subscription_survey_row_not_enough", fallback: "I don’t use it enough") }
  /// Option in the in the survey screen that appears when a user cancels the subscription
  internal static var cancelSubscriptionSurveyRowOther: String { return L10n.tr("Localizable", "cancel_subscription_survey_row_other", fallback: "Other") }
  /// Option in the in the survey screen that appears when a user cancels the subscription
  internal static var cancelSubscriptionSurveyRowTechnicalIssue: String { return L10n.tr("Localizable", "cancel_subscription_survey_row_technical_issue", fallback: "Technical issues") }
  /// Title of the Send Button in the survey screen that appears when a user cancels the subscription
  internal static var cancelSubscriptionSurveySubmitFeedback: String { return L10n.tr("Localizable", "cancel_subscription_survey_submit_feedback", fallback: "Submit feedback") }
  /// Title of the survey screen that appears when a user cancels the subscription. 
  ///  forces Pocket Casts to be on a new line
  internal static var cancelSubscriptionSurveyTitle: String { return L10n.tr("Localizable", "cancel_subscription_survey_title", fallback: "Thanks for trying\nPocket Casts Plus") }
  /// Toast message that appears if the survey submission goes wrong
  internal static var cancelSubscriptionSurveyToastFail: String { return L10n.tr("Localizable", "cancel_subscription_survey_toast_fail", fallback: "Sorry, something went wrong.") }
  /// Toast message that appears if the survey submission goes well
  internal static var cancelSubscriptionSurveyToastSuccess: String { return L10n.tr("Localizable", "cancel_subscription_survey_toast_success", fallback: "Thanks for your feedback!") }
  /// Title of the cancel subscription view, '
  /// ' is a line break format to allow a clean wrapping of text
  internal static var cancelSubscriptionTitle: String { return L10n.tr("Localizable", "cancel_subscription_title", fallback: "Thinking of leaving?\nLet us help first") }
  /// Offer view: button used to accept the offer
  internal static var cancelSubscriptionWinbackViewAcceptOfferButton: String { return L10n.tr("Localizable", "cancel_subscription_winback_view_accept_offer_button", fallback: "Accept offer") }
  /// Offer view: button used to prompt the system cancellation view
  internal static var cancelSubscriptionWinbackViewContinueCancellationButton: String { return L10n.tr("Localizable", "cancel_subscription_winback_view_continue_cancellation_button", fallback: "Continue with cancellation") }
  /// Offer view: description for the monthly promotion.
  internal static var cancelSubscriptionWinbackViewDescriptionMontly: String { return L10n.tr("Localizable", "cancel_subscription_winback_view_description_montly", fallback: "Enjoy one month of Pocket Casts Plus on us! The offer will be added to your current subscription.") }
  /// Offer view: description for the yearly promotion. The %@ represents the price.
  internal static func cancelSubscriptionWinbackViewDescriptionYearly(_ p1: Any) -> String {
    return L10n.tr("Localizable", "cancel_subscription_winback_view_description_yearly", String(describing: p1), fallback: "Pay %@ now to lock in a year of Pocket Casts Plus at half price. Your discounted year begins after your current plan ends.")
  }
  /// Offer view: title for the monthly promotion. The %@ represents the price.
  internal static func cancelSubscriptionWinbackViewTitleMontly(_ p1: Any) -> String {
    return L10n.tr("Localizable", "cancel_subscription_winback_view_title_montly", String(describing: p1), fallback: "Get your next month free and save %@")
  }
  /// Offer view: title for the yearly promotion. The %@ represents the price.
  internal static func cancelSubscriptionWinbackViewTitleYearly(_ p1: Any) -> String {
    return L10n.tr("Localizable", "cancel_subscription_winback_view_title_yearly", String(describing: p1), fallback: "Get 50%% off your next year and save %@")
  }
  /// Cancel subscription: title for the yearly promotion row
  internal static var cancelSubscriptionYearlyPromotionTitle: String { return L10n.tr("Localizable", "cancel_subscription_yearly_promotion_title", fallback: "Get 50%% off your next year") }
  /// An activity message indicating that the process to cancel is running.
  internal static var canceling: String { return L10n.tr("Localizable", "canceling", fallback: "Canceling...") }
  /// Shown in the Catch Me Up sheet when a recap could not be generated
  internal static var catchMeUpFailed: String { return L10n.tr("Localizable", "catch_me_up_failed", fallback: "A recap isn't available for this episode yet. Try again after the transcript finishes processing.") }
  /// Shown with a spinner while the catch-up recap is being generated on-device
  internal static var catchMeUpGenerating: String { return L10n.tr("Localizable", "catch_me_up_generating", fallback: "Catching you up…") }
  /// Title of the Catch Me Up feature: shelf action, summary-card button and sheet header. Recaps the already-played part of an in-progress episode
  internal static var catchMeUpTitle: String { return L10n.tr("Localizable", "catch_me_up_title", fallback: "Catch Me Up") }
  /// Button label that changes the users chosen app icon
  internal static var changeAppIcon: String { return L10n.tr("Localizable", "change_app_icon", fallback: "Change App Icon") }
  /// The subtitle of a view where the user can edit their bookmark title
  internal static var changeBookmarkSubtitle: String { return L10n.tr("Localizable", "change_bookmark_subtitle", fallback: "Change the title that identifies this bookmark") }
  /// The title of a view where the user can edit their bookmark title
  internal static var changeBookmarkTitle: String { return L10n.tr("Localizable", "change_bookmark_title", fallback: "Change title") }
  /// Prompt to allow the user to update their email address.
  internal static var changeEmail: String { return L10n.tr("Localizable", "change_email", fallback: "Change Email Address") }
  /// Confirmation message title informing the user that their email has been successfully updated.
  internal static var changeEmailConf: String { return L10n.tr("Localizable", "change_email_conf", fallback: "Email Address Changed") }
  /// Prompt to allow the user to Update their password.
  internal static var changePassword: String { return L10n.tr("Localizable", "change_password", fallback: "Change Password") }
  /// Confirmation message title informing the user that their password has been successfully updated.
  internal static var changePasswordConf: String { return L10n.tr("Localizable", "change_password_conf", fallback: "Password Changed") }
  /// Error message informing the user that the change password process failed.
  internal static var changePasswordError: String { return L10n.tr("Localizable", "change_password_error", fallback: "Unable to change password. Invalid password.") }
  /// Error message informing the user that the change password process failed because they failed to enter matching passwords.
  internal static var changePasswordErrorMismatch: String { return L10n.tr("Localizable", "change_password_error_mismatch", fallback: "Passwords do not match") }
  /// Error message informing the user that they need to choose a longer password.
  internal static var changePasswordLengthError: String { return L10n.tr("Localizable", "change_password_length_error", fallback: "Must be at least 6 characters") }
  /// A common string used throughout the app. Often refers to the Chapters list or Chapters tab in the player.
  internal static var chapters: String { return L10n.tr("Localizable", "chapters", fallback: "Chapters") }
  /// Warning message shown for automatically generated episode chapters
  internal static var chaptersGeneratedWarningMessage: String { return L10n.tr("Localizable", "chapters_generated_warning_message", fallback: "These chapters are automatically generated and may not be perfectly accurate.") }
  /// A description and call to action to check your internet connection state when content has failed to load.
  internal static var checkInternetConnection: String { return L10n.tr("Localizable", "check_internet_connection", fallback: "Please check your Internet connection") }
  /// A common string used throughout the app. Informs the user how many podcasts have been chosen. '%1$@' is a placeholder for the number of podcasts, this will be more than one.
  internal static func chosenPodcastsPluralFormat(_ p1: Any) -> String {
    return L10n.tr("Localizable", "chosen_podcasts_plural_format", String(describing: p1), fallback: "%1$@ Podcasts Chosen")
  }
  /// A common string used throughout the app. Informs the user how many podcasts have been chosen. This is the singular format for an accompanying plural option.
  internal static var chosenPodcastsSingular: String { return L10n.tr("Localizable", "chosen_podcasts_singular", fallback: "1 Podcast Chosen") }
  /// A common string used throughout the app. Prompt to perform a clean up operation on the selected items.
  internal static var cleanUp: String { return L10n.tr("Localizable", "clean_up", fallback: "Clean Up") }
  /// A common string used throughout the app. Prompt to clear the up next queue.
  internal static var clear: String { return L10n.tr("Localizable", "clear", fallback: "Clear") }
  /// Title of a button the clears the current search text
  internal static var clearSearch: String { return L10n.tr("Localizable", "clear_search", fallback: "Clear Search") }
  /// A common string used throughout the app. Prompt to clear the up next queue.
  internal static var clearUpNext: String { return L10n.tr("Localizable", "clear_up_next", fallback: "Clear Up Next") }
  /// A common string used throughout the app. Message to clear the up next queue.
  internal static var clearUpNextMessage: String { return L10n.tr("Localizable", "clear_up_next_message", fallback: "Are you sure you want to clear your Up Next queue?") }
  /// A generic message for an error fetching the token from the server. This will cause logout issues.
  internal static var clientErrorTokenDeauth: String { return L10n.tr("Localizable", "client_error_token_deauth", fallback: "Token authentication failed.") }
  /// Shown in a button when creating a shareable audio clip of an episode
  internal static var clip: String { return L10n.tr("Localizable", "clip", fallback: "Clip") }
  /// A label shown with the duration time of a clip
  internal static func clipDurationLabel(_ p1: Any) -> String {
    return L10n.tr("Localizable", "clip_duration_label", String(describing: p1), fallback: "%@ Duration")
  }
  /// A label shown while the clip is being created
  internal static var clipLoadingLabel: String { return L10n.tr("Localizable", "clip_loading_label", fallback: "Creating Clip...") }
  /// A label shown with the clip start time
  internal static func clipStartLabel(_ p1: Any) -> String {
    return L10n.tr("Localizable", "clip_start_label", String(describing: p1), fallback: "%@ Start")
  }
  /// Clips - A label used for Voice Over to indicate the end time of a clip. The time will be read as a localized version of "20 minutes 30 seconds" after this label
  internal static var clipsEndTimeAccessibilityLabel: String { return L10n.tr("Localizable", "clips_end_time_accessibility_label", fallback: "Clip end") }
  /// A Voice Over label used to identify a shareable media. This represents different image and video sizes such as "large, medium, small" as well as the "audio" format
  internal static var clipsShareableMediaA11yLabel: String { return L10n.tr("Localizable", "clips_shareable_media_a11y_label", fallback: "Shareable media options") }
  /// A Voice Over label used to identify the container for the shareable media options. This contains different image and video sizes such as "large, medium, small" as well as the "audio" format
  internal static func clipsShareableMediaItemA11yLabel(_ p1: Any, _ p2: Any, _ p3: Any) -> String {
    return L10n.tr("Localizable", "clips_shareable_media_item_a11y_label", String(describing: p1), String(describing: p2), String(describing: p3), fallback: "%1$@ format %2$@ of %3$@")
  }
  /// Clips - A label used for Voice Over to indicate the start time of a clip. The time will be read as a localized version of "20 minutes 30 seconds" after this label
  internal static var clipsStartTimeAccessibilityLabel: String { return L10n.tr("Localizable", "clips_start_time_accessibility_label", fallback: "Clip start") }
  /// Clips - Button title to show in What's New screen announcing the Clips feature
  internal static var clipsWhatsNewButtonTitle: String { return L10n.tr("Localizable", "clips_whats_new_button_title", fallback: "Got it") }
  /// Clips - Message to show in What's New screen announcing the Clips feature
  internal static var clipsWhatsNewMessage: String { return L10n.tr("Localizable", "clips_whats_new_message", fallback: "You can now share clips of your favorite bits from any episode. We’ve also made easier to share any content to all social media apps.") }
  /// Clips - Title to show in What's New screen announcing the Clips feature
  internal static var clipsWhatsNewTitle: String { return L10n.tr("Localizable", "clips_whats_new_title", fallback: "Clip sharing available now!") }
  /// A common string used throughout the app. Prompt to close the current screen.
  internal static var close: String { return L10n.tr("Localizable", "close", fallback: "Close") }
  /// Common word, the color of something
  internal static var color: String { return L10n.tr("Localizable", "color", fallback: "Color") }
  /// A common string used throughout the app. Generic confirmation
  internal static var confirm: String { return L10n.tr("Localizable", "confirm", fallback: "Confirm") }
  /// Password change form confirm new password field prompt
  internal static var confirmNewPasswordPrompt: String { return L10n.tr("Localizable", "confirm_new_password_prompt", fallback: "Confirm New Password") }
  /// A common string used throughout the app. A prompt to move to the next step of a flow.
  internal static var `continue`: String { return L10n.tr("Localizable", "continue", fallback: "Continue") }
  /// The string for the act of Copy (from Copy & Paste)
  internal static var copy: String { return L10n.tr("Localizable", "copy", fallback: "Copy") }
  /// Prompt to open the create account options.
  internal static var createAccount: String { return L10n.tr("Localizable", "create_account", fallback: "Create Account") }
  /// Error message shown when Pocket Casts can't connect to the App Store to retrieve in app purchase details
  internal static var createAccountAppStoreErrorMessage: String { return L10n.tr("Localizable", "create_account_app_store_error_message", fallback: "Pocket Casts is having trouble connecting to the App Store. Please check your connection and try again.") }
  /// Error title shown when Pocket Casts can't connect to the App Store to retrieve in app purchase details
  internal static var createAccountAppStoreErrorTitle: String { return L10n.tr("Localizable", "create_account_app_store_error_title", fallback: "Unable to contact App Store") }
  /// Button title to find out more about Pocket Casts Plus. Note that "Pocket Casts Plus" shouldn't be translated as it's a product name
  internal static var createAccountFindOutMorePlus: String { return L10n.tr("Localizable", "create_account_find_out_more_plus", fallback: "Find out more about Pocket Casts Plus") }
  /// Account type shown on the select account page. Regular as in the normal or default option
  internal static var createAccountFreeAccountType: String { return L10n.tr("Localizable", "create_account_free_account_type", fallback: "Regular") }
  /// Shown under the create account type to indicate what you get with a free Pocket Casts account
  internal static var createAccountFreeDetails: String { return L10n.tr("Localizable", "create_account_free_details", fallback: "Almost everything") }
  /// Price shown for the free tier. "Free" in this case meaning the cost is free
  internal static var createAccountFreePrice: String { return L10n.tr("Localizable", "create_account_free_price", fallback: "Free") }
  /// Shown under the create account type to indicate what you get in Pocket Casts Plus
  internal static var createAccountPlusDetails: String { return L10n.tr("Localizable", "create_account_plus_details", fallback: "Everything unlocked") }
  /// A description shown for a share option which creates an audio clip of an episode. This produces a ".m4a" file which is like an mp3
  internal static var createAudioClipDescription: String { return L10n.tr("Localizable", "create_audio_clip_description", fallback: "Create a .m4a audio file") }
  /// A title shown for a share option which creates an audio clip of an episode
  internal static var createAudioClipTitle: String { return L10n.tr("Localizable", "create_audio_clip_title", fallback: "Create audio file") }
  /// A title shown for a share option which creates an animated video clip with audio of an episode
  internal static var createClip: String { return L10n.tr("Localizable", "create_clip", fallback: "Create clip") }
  /// Title for the screen where a user starts creating a filter
  internal static var createFilter: String { return L10n.tr("Localizable", "create_filter", fallback: "Create Filter") }
  /// Create snapshot
  internal static var createUpNextSnapshot: String { return L10n.tr("Localizable", "create_up_next_snapshot", fallback: "Create snapshot") }
  /// Description for modal explaining Creator Picks
  internal static var creatorPickModalDescription: String { return L10n.tr("Localizable", "creator_pick_modal_description", fallback: "Creator Picks are podcasts recommended by the show's creator using Podroll.") }
  /// Text used for the "Learn more" link in the modal explaining Creator Picks
  internal static var creatorPickModalLearnMore: String { return L10n.tr("Localizable", "creator_pick_modal_learn_more", fallback: "Learn more") }
  /// Title for modal explaining Creator Picks
  internal static var creatorPickModalTitle: String { return L10n.tr("Localizable", "creator_pick_modal_title", fallback: "What's a Creator Pick?") }
  /// Email change form current email label
  internal static var currentEmailPrompt: String { return L10n.tr("Localizable", "current_email_prompt", fallback: "Current Email") }
  /// Password change form current password field prompt
  internal static var currentPasswordPrompt: String { return L10n.tr("Localizable", "current_password_prompt", fallback: "Current Password") }
  /// An indicator that the current episode is a user generated episode
  internal static var customEpisode: String { return L10n.tr("Localizable", "custom_episode", fallback: "Custom Episode") }
  /// Message displayed when doing heavy database operations
  internal static var databaseMigration: String { return L10n.tr("Localizable", "database_migration", fallback: "We're moving a few bits and bytes so the app runs faster...") }
  /// day
  internal static var day: String { return L10n.tr("Localizable", "day", fallback: "day") }
  /// Label shown for days listened when it's singular, eg: 1 day listened.
  internal static var dayListened: String { return L10n.tr("Localizable", "day_listened", fallback: "Day listened") }
  /// Label shown for days saved when it's singular, eg: 1 day saved.
  internal static var daySaved: String { return L10n.tr("Localizable", "day_saved", fallback: "Day saved") }
  /// Label shown for days listened when it's singular, eg: 2 days listened.
  internal static var daysListened: String { return L10n.tr("Localizable", "days_listened", fallback: "Days listened") }
  /// Label shown for days saved when it's singular, eg: 2 days saved.
  internal static var daysSaved: String { return L10n.tr("Localizable", "days_saved", fallback: "Days saved") }
  /// A common string used throughout the app. Prompt to delete the selected item(s).
  internal static var delete: String { return L10n.tr("Localizable", "delete", fallback: "Delete") }
  /// A prompt to delete the downloaded file
  internal static var deleteDownload: String { return L10n.tr("Localizable", "delete_download", fallback: "Delete Download") }
  /// Prompt to delete the selected item(s) from the device storage and the cloud.
  internal static var deleteEverywhere: String { return L10n.tr("Localizable", "delete_everywhere", fallback: "Delete From Everywhere") }
  /// Prompt to delete the selected item(s) from the device storage and the cloud.
  internal static var deleteEverywhereShort: String { return L10n.tr("Localizable", "delete_everywhere_short", fallback: "Delete Everywhere") }
  /// A common string used throughout the app. Title portion of the prompt to delete the selected file.
  internal static var deleteFile: String { return L10n.tr("Localizable", "delete_file", fallback: "Delete File") }
  /// A common string used throughout the app. Message portion of the prompt to delete the selected file.
  internal static var deleteFileMessage: String { return L10n.tr("Localizable", "delete_file_message", fallback: "Are you sure you want to delete this file?") }
  /// A common string used throughout the app. Prompt to delete the selected item(s) from the device storage.
  internal static var deleteFromDevice: String { return L10n.tr("Localizable", "delete_from_device", fallback: "Delete From Device") }
  /// A common string used throughout the app. Prompt to delete the selected item(s) from the device storage. 'Only' is used to emphasize that the item is also stored in the cloud and that file won't be deleted.
  internal static var deleteFromDeviceOnly: String { return L10n.tr("Localizable", "delete_from_device_only", fallback: "Delete From Device Only") }
  /// A common string used throughout the app. Prompt to deselect all items in the presented list.
  internal static var deselectAll: String { return L10n.tr("Localizable", "deselect_all", fallback: "Deselect All") }
  /// A common string used throughout the app. Prompt to deselect all items above the currently selected item.
  internal static var deselectAllAbove: String { return L10n.tr("Localizable", "deselect_all_above", fallback: "Deselect all above") }
  /// A common string used throughout the app. Prompt to deselect all items below the currently selected item.
  internal static var deselectAllBelow: String { return L10n.tr("Localizable", "deselect_all_below", fallback: "Deselect all below") }
  /// Message explaining why the sleep timer was restarted after the user shook the device
  internal static var deviceShakeSleepTimer: String { return L10n.tr("Localizable", "device_shake_sleep_timer", fallback: "Sleep timer restarted due to device shake") }
  /// A common string used throughout the app. Refers to the Discover tab.
  internal static var discover: String { return L10n.tr("Localizable", "discover", fallback: "Discover") }
  /// Title used when displaying all episodes from a search.
  internal static var discoverAllEpisodes: String { return L10n.tr("Localizable", "discover_all_episodes", fallback: "All Episodes") }
  /// Title used when displaying all podcasts from a search.
  internal static var discoverAllPodcasts: String { return L10n.tr("Localizable", "discover_all_podcasts", fallback: "All Podcasts") }
  /// Title for the section that allows the user to explore different podcast categories.
  internal static var discoverBrowseByCategory: String { return L10n.tr("Localizable", "discover_browse_by_category", fallback: "Browse By Category") }
  /// Title for the podcast category Arts
  internal static var discoverBrowseByCategoryArt: String { return L10n.tr("Localizable", "discover_browse_by_category_art", fallback: "Arts") }
  /// Title for the podcast category Business
  internal static var discoverBrowseByCategoryBusiness: String { return L10n.tr("Localizable", "discover_browse_by_category_business", fallback: "Business") }
  /// Title for the podcast category Comedy
  internal static var discoverBrowseByCategoryComedy: String { return L10n.tr("Localizable", "discover_browse_by_category_comedy", fallback: "Comedy") }
  /// Title for the podcast category Education
  internal static var discoverBrowseByCategoryEducation: String { return L10n.tr("Localizable", "discover_browse_by_category_education", fallback: "Education") }
  /// Abbreviation for the podcast category Kids & Family, using only "Family"
  internal static var discoverBrowseByCategoryFamily: String { return L10n.tr("Localizable", "discover_browse_by_category_family", fallback: "Family") }
  /// Title for the podcast category Fiction
  internal static var discoverBrowseByCategoryFiction: String { return L10n.tr("Localizable", "discover_browse_by_category_fiction", fallback: "Fiction") }
  /// Title for the podcast category Games & Hobbies
  internal static var discoverBrowseByCategoryGamesAndHobbies: String { return L10n.tr("Localizable", "discover_browse_by_category_games_and_hobbies", fallback: "Games & Hobbies") }
  /// Title for the podcast category Government
  internal static var discoverBrowseByCategoryGovernment: String { return L10n.tr("Localizable", "discover_browse_by_category_government", fallback: "Government") }
  /// Title for the podcast category Government & Organizations
  internal static var discoverBrowseByCategoryGovernmentAndOrganizations: String { return L10n.tr("Localizable", "discover_browse_by_category_government_and_organizations", fallback: "Government & Organizations") }
  /// Abbreviation for the podcast category Health & Fitness, using only "Health"
  internal static var discoverBrowseByCategoryHealth: String { return L10n.tr("Localizable", "discover_browse_by_category_health", fallback: "Health") }
  /// Title for the podcast category Health & Fitness
  internal static var discoverBrowseByCategoryHealthAndFitness: String { return L10n.tr("Localizable", "discover_browse_by_category_health_and_fitness", fallback: "Health & Fitness") }
  /// Title for the podcast category History
  internal static var discoverBrowseByCategoryHistory: String { return L10n.tr("Localizable", "discover_browse_by_category_history", fallback: "History") }
  /// Title for the podcast category Kids & Family
  internal static var discoverBrowseByCategoryKidsAndFamily: String { return L10n.tr("Localizable", "discover_browse_by_category_kids_and_family", fallback: "Kids & Family") }
  /// Title for the podcast category Leisure
  internal static var discoverBrowseByCategoryLeisure: String { return L10n.tr("Localizable", "discover_browse_by_category_leisure", fallback: "Leisure") }
  /// Title for the podcast category Music
  internal static var discoverBrowseByCategoryMusic: String { return L10n.tr("Localizable", "discover_browse_by_category_music", fallback: "Music") }
  /// Title for the podcast category News
  internal static var discoverBrowseByCategoryNews: String { return L10n.tr("Localizable", "discover_browse_by_category_news", fallback: "News") }
  /// Title for the podcast category News & Politics
  internal static var discoverBrowseByCategoryNewsAndPolitics: String { return L10n.tr("Localizable", "discover_browse_by_category_news_and_politics", fallback: "News & Politics") }
  /// Title for the podcast category Religion & Spirituality
  internal static var discoverBrowseByCategoryReligionAndSpirituality: String { return L10n.tr("Localizable", "discover_browse_by_category_religion_and_spirituality", fallback: "Religion & Spirituality") }
  /// Title for the podcast category Science
  internal static var discoverBrowseByCategoryScience: String { return L10n.tr("Localizable", "discover_browse_by_category_science", fallback: "Science") }
  /// Title for the podcast category Science & Medicine
  internal static var discoverBrowseByCategoryScienceAndMedicine: String { return L10n.tr("Localizable", "discover_browse_by_category_science_and_medicine", fallback: "Science & Medicine") }
  /// Title for the podcast category Society
  internal static var discoverBrowseByCategorySociety: String { return L10n.tr("Localizable", "discover_browse_by_category_society", fallback: "Society") }
  /// Title for the podcast category Society & Culture
  internal static var discoverBrowseByCategorySocietyAndCulture: String { return L10n.tr("Localizable", "discover_browse_by_category_society_and_culture", fallback: "Society & Culture") }
  /// Abbreviation for the podcast category Religion & Spirituality
  internal static var discoverBrowseByCategorySpirituality: String { return L10n.tr("Localizable", "discover_browse_by_category_spirituality", fallback: "Spirituality") }
  /// Title for the podcast category Sports
  internal static var discoverBrowseByCategorySports: String { return L10n.tr("Localizable", "discover_browse_by_category_sports", fallback: "Sports") }
  /// Title for the podcast category Sports & Recreation
  internal static var discoverBrowseByCategorySportsAndRecreation: String { return L10n.tr("Localizable", "discover_browse_by_category_sports_and_recreation", fallback: "Sports & Recreation") }
  /// Title for the podcast category Technology
  internal static var discoverBrowseByCategoryTechnology: String { return L10n.tr("Localizable", "discover_browse_by_category_technology", fallback: "Technology") }
  /// Title for the podcast category True Crime
  internal static var discoverBrowseByCategoryTrueCrime: String { return L10n.tr("Localizable", "discover_browse_by_category_true_crime", fallback: "True Crime") }
  /// Title for the podcast category TV & Film
  internal static var discoverBrowseByCategoryTvAndFilm: String { return L10n.tr("Localizable", "discover_browse_by_category_tv_and_film", fallback: "TV & Film") }
  /// Prompt to allow the user to manually change the regional information for the Discover tab. '%1$@' is a placeholder for the current region.
  internal static func discoverChangeRegion(_ p1: Any) -> String {
    return L10n.tr("Localizable", "discover_change_region", String(describing: p1), fallback: "Change Region, currently %1$@")
  }
  /// Informational title when the episode fails to load.
  internal static var discoverEpisodeFailToLoad: String { return L10n.tr("Localizable", "discover_episode_fail_to_load", fallback: "The episode couldn't be loaded") }
  /// Badge used to mark featured podcasts.
  internal static var discoverFeatured: String { return L10n.tr("Localizable", "discover_featured", fallback: "Featured") }
  /// Informative label letting the users know that the displayed episode is a featured episode.
  internal static var discoverFeaturedEpisode: String { return L10n.tr("Localizable", "discover_featured_episode", fallback: "FEATURED EPISODE") }
  /// Error message informing the user that the episode they tapped could not be found, with instructions on how to fix the issue.
  internal static var discoverFeaturedEpisodeErrorNotFound: String { return L10n.tr("Localizable", "discover_featured_episode_error_not_found", fallback: "Featured podcast or episode not found. Make sure you are connected to the internet and try again.") }
  /// Informative label letting the users know that the displayed podcast is a featured new podcast.
  internal static var discoverFreshPick: String { return L10n.tr("Localizable", "discover_fresh_pick", fallback: "FRESH PICK") }
  /// Informational title when the episode search succeeds but returns no results.
  internal static var discoverNoEpisodesFound: String { return L10n.tr("Localizable", "discover_no_episodes_found", fallback: "No episodes found") }
  /// Informational title when the search succeeds but returns no results.
  internal static var discoverNoPodcastsFound: String { return L10n.tr("Localizable", "discover_no_podcasts_found", fallback: "No podcasts found") }
  /// Informational title when the search succeeds but returns no results.
  internal static var discoverNoPodcastsFoundMsg: String { return L10n.tr("Localizable", "discover_no_podcasts_found_msg", fallback: "Try more general or different keywords.") }
  /// Button prompt on the discover page to play the featured episode.
  internal static var discoverPlayEpisode: String { return L10n.tr("Localizable", "discover_play_episode", fallback: "Play Episode") }
  /// Button prompt on the discover page to play the trailer of a featured episode.
  internal static var discoverPlayTrailer: String { return L10n.tr("Localizable", "discover_play_trailer", fallback: "Play Trailer") }
  /// Display title for calling out a podcast network on the discover tab. '%1$@' is a placeholder for the podcast's network title.
  internal static func discoverPodcastNetwork(_ p1: Any) -> String {
    return L10n.tr("Localizable", "discover_podcast_network", String(describing: p1), fallback: "%1$@ Network")
  }
  /// Title used for promotional purposes to highlight podcasts that are popular worldwide.
  internal static var discoverPopular: String { return L10n.tr("Localizable", "discover_popular", fallback: "Popular") }
  /// Title used for promotional purposes to highlight podcasts that are popular in a specific region. '%1$@' is a placeholder for the region's name.
  internal static func discoverPopularIn(_ p1: Any) -> String {
    return L10n.tr("Localizable", "discover_popular_in", String(describing: p1), fallback: "Popular in %1$@")
  }
  /// Region name for Australia used in the Discover Section
  internal static var discoverRegionAustralia: String { return L10n.tr("Localizable", "discover_region_australia", fallback: "Australia") }
  /// Region name for Austria used in the Discover Section
  internal static var discoverRegionAustria: String { return L10n.tr("Localizable", "discover_region_austria", fallback: "Austria") }
  /// Region name for Belgium used in the Discover Section
  internal static var discoverRegionBelgium: String { return L10n.tr("Localizable", "discover_region_belgium", fallback: "Belgium") }
  /// Region name for Brazil used in the Discover Section
  internal static var discoverRegionBrazil: String { return L10n.tr("Localizable", "discover_region_brazil", fallback: "Brazil") }
  /// Region name for Canada used in the Discover Section
  internal static var discoverRegionCanada: String { return L10n.tr("Localizable", "discover_region_canada", fallback: "Canada") }
  /// Region name for China used in the Discover Section
  internal static var discoverRegionChina: String { return L10n.tr("Localizable", "discover_region_china", fallback: "China") }
  /// Region name for Czechia used in the Discover Section
  internal static var discoverRegionCzechia: String { return L10n.tr("Localizable", "discover_region_czechia", fallback: "Czechia") }
  /// Region name for Denmark used in the Discover Section
  internal static var discoverRegionDenmark: String { return L10n.tr("Localizable", "discover_region_denmark", fallback: "Denmark") }
  /// Region name for Finland used in the Discover Section
  internal static var discoverRegionFinland: String { return L10n.tr("Localizable", "discover_region_finland", fallback: "Finland") }
  /// Region name for France used in the Discover Section
  internal static var discoverRegionFrance: String { return L10n.tr("Localizable", "discover_region_france", fallback: "France") }
  /// Region name for Germany used in the Discover Section
  internal static var discoverRegionGermany: String { return L10n.tr("Localizable", "discover_region_germany", fallback: "Germany") }
  /// Region name for Hong Kong used in the Discover Section
  internal static var discoverRegionHongKong: String { return L10n.tr("Localizable", "discover_region_hong_kong", fallback: "Hong Kong") }
  /// Region name for India used in the Discover Section
  internal static var discoverRegionIndia: String { return L10n.tr("Localizable", "discover_region_india", fallback: "India") }
  /// Region name for Ireland used in the Discover Section
  internal static var discoverRegionIreland: String { return L10n.tr("Localizable", "discover_region_ireland", fallback: "Ireland") }
  /// Region name for Israel used in the Discover Section
  internal static var discoverRegionIsrael: String { return L10n.tr("Localizable", "discover_region_israel", fallback: "Israel") }
  /// Region name for Italy used in the Discover Section
  internal static var discoverRegionItaly: String { return L10n.tr("Localizable", "discover_region_italy", fallback: "Italy") }
  /// Region name for Japan used in the Discover Section
  internal static var discoverRegionJapan: String { return L10n.tr("Localizable", "discover_region_japan", fallback: "Japan") }
  /// Region name for Mexico used in the Discover Section
  internal static var discoverRegionMexico: String { return L10n.tr("Localizable", "discover_region_mexico", fallback: "Mexico") }
  /// Region name for Netherlands used in the Discover Section
  internal static var discoverRegionNetherlands: String { return L10n.tr("Localizable", "discover_region_netherlands", fallback: "Netherlands") }
  /// Region name for New Zealand used in the Discover Section
  internal static var discoverRegionNewZealand: String { return L10n.tr("Localizable", "discover_region_new_zealand", fallback: "New Zealand") }
  /// Region name for Norway used in the Discover Section
  internal static var discoverRegionNorway: String { return L10n.tr("Localizable", "discover_region_norway", fallback: "Norway") }
  /// Region name for Philippines used in the Discover Section
  internal static var discoverRegionPhilippines: String { return L10n.tr("Localizable", "discover_region_philippines", fallback: "Philippines") }
  /// Region name for Poland used in the Discover Section
  internal static var discoverRegionPoland: String { return L10n.tr("Localizable", "discover_region_poland", fallback: "Poland") }
  /// Region name for Portugal used in the Discover Section
  internal static var discoverRegionPortugal: String { return L10n.tr("Localizable", "discover_region_portugal", fallback: "Portugal") }
  /// Region name for Russia used in the Discover Section
  internal static var discoverRegionRussia: String { return L10n.tr("Localizable", "discover_region_russia", fallback: "Russia") }
  /// Region name for Saudi Arabia used in the Discover Section
  internal static var discoverRegionSaudiArabia: String { return L10n.tr("Localizable", "discover_region_saudi_arabia", fallback: "Saudi Arabia") }
  /// Region name for Singapore used in the Discover Section
  internal static var discoverRegionSingapore: String { return L10n.tr("Localizable", "discover_region_singapore", fallback: "Singapore") }
  /// Region name for South Africa used in the Discover Section
  internal static var discoverRegionSouthAfrica: String { return L10n.tr("Localizable", "discover_region_south_africa", fallback: "South Africa") }
  /// Region name for South Korea used in the Discover Section
  internal static var discoverRegionSouthKorea: String { return L10n.tr("Localizable", "discover_region_south_korea", fallback: "South Korea") }
  /// Region name for Spain used in the Discover Section
  internal static var discoverRegionSpain: String { return L10n.tr("Localizable", "discover_region_spain", fallback: "Spain") }
  /// Region name for Sweden used in the Discover Section
  internal static var discoverRegionSweden: String { return L10n.tr("Localizable", "discover_region_sweden", fallback: "Sweden") }
  /// Region name for Switzerland used in the Discover Section
  internal static var discoverRegionSwitzerland: String { return L10n.tr("Localizable", "discover_region_switzerland", fallback: "Switzerland") }
  /// Region name for Taiwan used in the Discover Section
  internal static var discoverRegionTaiwan: String { return L10n.tr("Localizable", "discover_region_taiwan", fallback: "Taiwan") }
  /// Region name for Turkey used in the Discover Section
  internal static var discoverRegionTurkey: String { return L10n.tr("Localizable", "discover_region_turkey", fallback: "Turkey") }
  /// Region name for Ukraine used in the Discover Section
  internal static var discoverRegionUkraine: String { return L10n.tr("Localizable", "discover_region_ukraine", fallback: "Ukraine") }
  /// Region name for United Kingdom used in the Discover Section
  internal static var discoverRegionUnitedKingdom: String { return L10n.tr("Localizable", "discover_region_united_kingdom", fallback: "United Kingdom") }
  /// Region name for United States used in the Discover Section
  internal static var discoverRegionUnitedStates: String { return L10n.tr("Localizable", "discover_region_united_states", fallback: "United States") }
  /// Region name used in the Discover Section for a generic global setting instead of a specific region.
  internal static var discoverRegionWorldwide: String { return L10n.tr("Localizable", "discover_region_worldwide", fallback: "Worldwide") }
  /// Error message when a user performs a search using a search term that's too short.
  internal static var discoverSearchErrorMsg: String { return L10n.tr("Localizable", "discover_search_error_msg", fallback: "Please enter at least 2 characters.") }
  /// Error title when a user performs a search using a search term that's too short.
  internal static var discoverSearchErrorTitle: String { return L10n.tr("Localizable", "discover_search_error_title", fallback: "Length Challenged") }
  /// Informational title informing the users that the search has failed.
  internal static var discoverSearchFailed: String { return L10n.tr("Localizable", "discover_search_failed", fallback: "Search Failed") }
  /// Informational message suggesting that the user checks their internet connection when an error occurs.
  internal static var discoverSearchFailedMsg: String { return L10n.tr("Localizable", "discover_search_failed_msg", fallback: "Check your Internet connection.") }
  /// Screen title to allow the user to manually change the regional information for the Discover tab. This screen shows the available options.
  internal static var discoverSelectRegion: String { return L10n.tr("Localizable", "discover_select_region", fallback: "Select Content Region") }
  /// Button prompt used on the Discover Tab. Opens the linked list to show all podcasts in the section.
  internal static var discoverShowAll: String { return L10n.tr("Localizable", "discover_show_all", fallback: "SHOW ALL") }
  /// Informative label letting the users know that the displayed podcast is a paid placement ad.
  internal static var discoverSponsored: String { return L10n.tr("Localizable", "discover_sponsored", fallback: "SPONSORED") }
  /// Title used for promotional purposes to highlight trending podcasts.
  internal static var discoverTrending: String { return L10n.tr("Localizable", "discover_trending", fallback: "Trending") }
  /// Informative label letting users know when the Discover page has failed to load due to a network error.
  internal static var discoverUnableToLoad: String { return L10n.tr("Localizable", "discover_unable_to_load", fallback: "Unable to load Discover") }
  /// A common string used throughout the app. Confirmation text.
  internal static var done: String { return L10n.tr("Localizable", "done", fallback: "Done") }
  /// A common string used throughout the app. Prompt to download the selected item(s).
  internal static var download: String { return L10n.tr("Localizable", "download", fallback: "Download") }
  /// A common string used throughout the app. Prompt to download all of the selected item(s).
  internal static var downloadAll: String { return L10n.tr("Localizable", "download_all", fallback: "Download All") }
  /// A common string used throughout the app. Prompt to warn the user that continuing with the download will consume data. Used in tandem with a notice that the user is not on WiFi.
  internal static var downloadDataWarning: String { return L10n.tr("Localizable", "download_data_warning", fallback: "Downloading will use data.") }
  /// A common string used throughout the app. Prompt to warn the user that continuing with the download will consume data. Used in tandem with a notice that the user is not on WiFi. The word Settings will be linked to an internal URL which redirects the user to the correct Settings. The %@ is the placeholder for the URL
  internal static func downloadDataWarningWithSettingsLink(_ p1: Any) -> String {
    return L10n.tr("Localizable", "download_data_warning_with_settings_link", String(describing: p1), fallback: "This download will use mobile data. You can turn off this warning in [Settings](%@).")
  }
  /// A common string used throughout the app. Prompts the user that they have selected multiple episodes to download. '%1$@' is a placeholder for the count of the selected items, will be more than one.
  internal static func downloadEpisodePluralFormat(_ p1: Any) -> String {
    return L10n.tr("Localizable", "download_episode_plural_format", String(describing: p1), fallback: "Download %1$@ Episodes")
  }
  /// A common string used throughout the app. Prompts the user that they have selected one episode to download.
  internal static var downloadEpisodeSingular: String { return L10n.tr("Localizable", "download_episode_singular", fallback: "Download 1 Episode") }
  /// The episode failed to download due to an issue with the feed. Suggesting the user reaches out to the Podcast Author.
  internal static var downloadErrorContactAuthor: String { return L10n.tr("Localizable", "download_error_contact_author", fallback: "Episode not available due to an error in the podcast feed. Contact the podcast author.") }
  /// The episode failed to download due to an issue with the feed. Suggesting the user reaches out to the Podcast Author.
  internal static var downloadErrorContactAuthorVersion2: String { return L10n.tr("Localizable", "download_error_contact_author_version_2", fallback: "This episode may have been moved or deleted. Contact the podcast author.") }
  /// The episode failed to download because the device has no internet connection.
  internal static var downloadErrorNoInternet: String { return L10n.tr("Localizable", "download_error_no_internet", fallback: "Unable to download episode. Check your internet connection and try again.") }
  /// The episode failed to download due to the user running out of storage space.
  internal static var downloadErrorNotEnoughSpace: String { return L10n.tr("Localizable", "download_error_not_enough_space", fallback: "Unable to save episode, have you run out of space?") }
  /// The episode failed to download due to an issue with the feed. Suggesting the user reaches out to the Podcast Author. '%1$@' is a placeholder for the status code that the app received.
  internal static func downloadErrorStatusCode(_ p1: Any) -> String {
    return L10n.tr("Localizable", "download_error_status_code", String(describing: p1), fallback: "Download failed, error code %1$@. Contact the podcast author.")
  }
  /// The episode failed to download but the app wasn't able to determine why. Suggesting to try again after waiting for a bit.
  internal static var downloadErrorTryAgain: String { return L10n.tr("Localizable", "download_error_try_again", fallback: "Unable to download episode. Please try again later.") }
  /// A common string used throughout the app. Informs the user the download has failed.
  internal static var downloadFailed: String { return L10n.tr("Localizable", "download_failed", fallback: "Download Failed") }
  /// User-facing error shown when a streaming download is cancelled before completion.
  internal static var downloadStreamingCancelled: String { return L10n.tr("Localizable", "download_streaming_cancelled", fallback: "The streaming download was cancelled.") }
  /// User-facing error shown when a streaming download exceeds its completion timeout.
  internal static var downloadStreamingTimedOut: String { return L10n.tr("Localizable", "download_streaming_timed_out", fallback: "The streaming download timed out.") }
  /// A common string used throughout the app. Title for screens and prompts related to storage and downloaded files.
  internal static var downloadedFiles: String { return L10n.tr("Localizable", "downloaded_files", fallback: "Downloaded Files") }
  /// Confirmation message when you choose to delete a set of downloaded files
  internal static var downloadedFilesCleanupConfirmation: String { return L10n.tr("Localizable", "downloaded_files_cleanup_confirmation", fallback: "Are you sure you want to delete these downloaded files?") }
  /// Message for an unsubscribe message box that informs the user that unsubscribing will remove downloaded files.
  internal static var downloadedFilesConfMessage: String { return L10n.tr("Localizable", "downloaded_files_conf_message", fallback: "Unsubscribing will delete all downloaded files in this Podcast, are you sure?") }
  /// Message for an unfollow message box that informs the user that unfollowing will remove downloaded files.
  internal static var downloadedFilesConfMessageNew: String { return L10n.tr("Localizable", "downloaded_files_conf_message_new", fallback: "Unfollowing will delete all downloaded files in this Podcast, are you sure?") }
  /// Title for an unsubscribe message box that informs the user that unsubscribing will remove downloaded files. Informs the user how many files have been downloaded. '%1$@' is a placeholder for the number of downloaded files, will be more than one.
  internal static func downloadedFilesConfPluralFormat(_ p1: Any) -> String {
    return L10n.tr("Localizable", "downloaded_files_conf_plural_format", String(describing: p1), fallback: "%1$@ Downloaded Files")
  }
  /// Title for an unsubscribe message box that informs the user that unsubscribing will remove downloaded files. Informs the user one file has been downloaded. Singular version of an accompanying plural message.
  internal static var downloadedFilesConfSingular: String { return L10n.tr("Localizable", "downloaded_files_conf_singular", fallback: "1 Downloaded File") }
  /// A common string used throughout the app. Often refers to the Downloads screen.
  internal static var downloads: String { return L10n.tr("Localizable", "downloads", fallback: "Downloads") }
  /// Prompt to navigate the user to the Auto Downloads settings menu.
  internal static var downloadsAutoDownload: String { return L10n.tr("Localizable", "downloads_auto_download", fallback: "Auto Download Settings") }
  /// The description for the empty state when there are no downloads available
  internal static var downloadsNoDownloadsDesc: String { return L10n.tr("Localizable", "downloads_no_downloads_desc", fallback: "Save episodes for offline listening and never miss a moment.") }
  /// Title for the empty state when there are no downloads available
  internal static var downloadsNoDownloadsTitle: String { return L10n.tr("Localizable", "downloads_no_downloads_title", fallback: "Enjoy offline listening") }
  /// Prompt to allow the user to retry failed downloads.
  internal static var downloadsRetryFailedDownloads: String { return L10n.tr("Localizable", "downloads_retry_failed_downloads", fallback: "Retry Failed Downloads") }
  /// Prompt to allow the user to stop active downloads.
  internal static var downloadsStopAllDownloads: String { return L10n.tr("Localizable", "downloads_stop_all_downloads", fallback: "Stop All Downloads") }
  /// Encourage Account Creation: title of the button used to start the login flow
  internal static var eacInformationalBannerCreateAccount: String { return L10n.tr("Localizable", "eac_informational_banner_create_account", fallback: "Create a free account") }
  /// Encourage Account Creation: description for the banner in the filters view
  internal static var eacInformationalBannerFiltersDescription: String { return L10n.tr("Localizable", "eac_informational_banner_filters_description", fallback: "Create a free account to sync your filters on any device.") }
  /// Encourage Account Creation: accessibility label for the banner in the filters view
  internal static var eacInformationalBannerFiltersIconAccessibility: String { return L10n.tr("Localizable", "eac_informational_banner_filters_icon_accessibility", fallback: "Filters Icon") }
  /// Encourage Account Creation: title for the banner in the filters view
  internal static var eacInformationalBannerFiltersTitle: String { return L10n.tr("Localizable", "eac_informational_banner_filters_title", fallback: "Keep your filters in sync") }
  /// Encourage Account Creation: description for the banner in the listening history
  internal static var eacInformationalBannerListeningHistoryDescription: String { return L10n.tr("Localizable", "eac_informational_banner_listening_history_description", fallback: "Create a free account to sync your listening history everywhere.") }
  /// Encourage Account Creation: accessibility label for the banner in the listening history view
  internal static var eacInformationalBannerListeningHistoryIconAccessibility: String { return L10n.tr("Localizable", "eac_informational_banner_listening_history_icon_accessibility", fallback: "Listening History Icon") }
  /// Encourage Account Creation: title for the banner in the listening history
  internal static var eacInformationalBannerListeningHistoryTitle: String { return L10n.tr("Localizable", "eac_informational_banner_listening_history_title", fallback: "Keep track of what you’ve played") }
  /// Encourage Account Creation: description for the banner in the playlists view
  internal static var eacInformationalBannerPlaylistsDescription: String { return L10n.tr("Localizable", "eac_informational_banner_playlists_description", fallback: "Create a free account to sync your playlists on any device.") }
  /// Encourage Account Creation: accessibility label for the banner in the playlists view
  internal static var eacInformationalBannerPlaylistsIconAccessibility: String { return L10n.tr("Localizable", "eac_informational_banner_playlists_icon_accessibility", fallback: "Playlists Icon") }
  /// Encourage Account Creation: title for the banner in the playlists view
  internal static var eacInformationalBannerPlaylistsTitle: String { return L10n.tr("Localizable", "eac_informational_banner_playlists_title", fallback: "Keep your playlists in sync") }
  /// Encourage Account Creation: description for the banner in the profile view
  internal static var eacInformationalBannerProfileDescription: String { return L10n.tr("Localizable", "eac_informational_banner_profile_description", fallback: "Create a free account to sync your shows and listen anywhere.") }
  /// Encourage Account Creation: accessibility label for the banner in the profile view
  internal static var eacInformationalBannerProfileIconAccessibility: String { return L10n.tr("Localizable", "eac_informational_banner_profile_icon_accessibility", fallback: "Profile Icon") }
  /// Encourage Account Creation: title for the banner in the profile view
  internal static var eacInformationalBannerProfileTitle: String { return L10n.tr("Localizable", "eac_informational_banner_profile_title", fallback: "Your shows, on any device") }
  /// Encourage Account Creation: card description for backups feature
  internal static var eacInformationalCardBackupsDescription: String { return L10n.tr("Localizable", "eac_informational_card_backups_description", fallback: "Your library and preferences are securely saved.") }
  /// Encourage Account Creation: card title for backups feature
  internal static var eacInformationalCardBackupsTitle: String { return L10n.tr("Localizable", "eac_informational_card_backups_title", fallback: "Reliable backups") }
  /// Encourage Account Creation: card description for recommendations feature
  internal static var eacInformationalCardRecommendationDescription: String { return L10n.tr("Localizable", "eac_informational_card_recommendation_description", fallback: "Get tailored podcast suggestions based on your listening habits.") }
  /// Encourage Account Creation: card title for recommendations feature
  internal static var eacInformationalCardRecommendationTitle: String { return L10n.tr("Localizable", "eac_informational_card_recommendation_title", fallback: "Personalized recommendations") }
  /// Encourage Account Creation: card description for sync feature
  internal static var eacInformationalCardSyncDescription: String { return L10n.tr("Localizable", "eac_informational_card_sync_description", fallback: "Sync your progress, and shows across all your devices.") }
  /// Encourage Account Creation: card title for sync feature
  internal static var eacInformationalCardSyncTitle: String { return L10n.tr("Localizable", "eac_informational_card_sync_title", fallback: "Sync across devices") }
  /// Encourage Account Creation: modal description
  internal static var eacInformationalViewModalDescription: String { return L10n.tr("Localizable", "eac_informational_view_modal_description", fallback: "Create an account or log in to enjoy\nPocket Casts to the fullest.") }
  /// Encourage Account Creation: Get Started button
  internal static var eacInformationalViewModalGetStartedButton: String { return L10n.tr("Localizable", "eac_informational_view_modal_get_started_button", fallback: "Get Started") }
  /// Encourage Account Creation: modal title
  internal static var eacInformationalViewModalTitle: String { return L10n.tr("Localizable", "eac_informational_view_modal_title", fallback: "We noticed you’re not logged in") }
  /// Common word used to denote editting something
  internal static var edit: String { return L10n.tr("Localizable", "edit", fallback: "Edit") }
  /// A title shown for a button to return to editing a clip
  internal static var editClip: String { return L10n.tr("Localizable", "edit_clip", fallback: "Edit clip") }
  /// Button label for a feature that the user can enable
  internal static var enableItNow: String { return L10n.tr("Localizable", "enable_it_now", fallback: "Enable it now") }
  /// Section header listing where an entity appears.
  internal static var entityDetailAppearances: String { return L10n.tr("Localizable", "entity_detail_appearances", fallback: "Appearances") }
  /// Line with the number of followed shows mentioning this entity.
  internal static func entityDetailFollowedShowsPlural(_ p1: Any) -> String {
    return L10n.tr("Localizable", "entity_detail_followed_shows_plural", String(describing: p1), fallback: "%1$@ shows you follow mentioned this")
  }
  /// Line when exactly one show the user follows mentioned this entity.
  internal static var entityDetailFollowedShowsSingular: String { return L10n.tr("Localizable", "entity_detail_followed_shows_singular", fallback: "1 show you follow mentioned this") }
  /// Appearance subtitle with the mention's timestamp. Placeholder is a play time like 34:12.
  internal static func entityDetailMentionedAt(_ p1: Any) -> String {
    return L10n.tr("Localizable", "entity_detail_mentioned_at", String(describing: p1), fallback: "Mentioned at %1$@")
  }
  /// Description shown on the final End of Year story for 2024
  internal static var eoy2024EpilogueDescription: String { return L10n.tr("Localizable", "eoy_2024_epilogue_description", fallback: "Don’t forget to share with friends and give a shout out to your favourite podcasts and creators.") }
  /// Title shown on the final End of Year story for 2024
  internal static var eoy2024EpilogueTitle: String { return L10n.tr("Localizable", "eoy_2024_epilogue_title", fallback: "Thank you for listening with us this year.\nSee you in 2025!") }
  /// End of Year card description that appears under Profile
  internal static var eoyCardDescription: String { return L10n.tr("Localizable", "eoy_card_description", fallback: "See your listening stats, top podcasts, and more.") }
  /// Description to why the user needs to create an account to see their end of year stats.
  internal static var eoyCreateAccountToSee: String { return L10n.tr("Localizable", "eoy_create_account_to_see", fallback: "Save your podcasts in the cloud, get your end of year review and sync your progress with other devices.") }
  /// A description of the End of Year feature
  internal static var eoyDescription: String { return L10n.tr("Localizable", "eoy_description", fallback: "See your top podcasts, categories, listening stats, and more. Share with friends and shout out your favorite creators!") }
  /// Label of the End of Year dismiss button
  internal static var eoyNotNow: String { return L10n.tr("Localizable", "eoy_not_now", fallback: "Not Now") }
  /// Label of a button to share the current story as a shareable story card
  internal static var eoyShare: String { return L10n.tr("Localizable", "eoy_share", fallback: "Share this story") }
  /// Message of an alert displayed to the user asking if they want to share the current story
  internal static var eoyShareThisStoryMessage: String { return L10n.tr("Localizable", "eoy_share_this_story_message", fallback: "Paste this image to your socials and give a shout out to your favorite shows and creators") }
  /// Title of an alert displayed to the user asking if they want to share the current story
  internal static var eoyShareThisStoryTitle: String { return L10n.tr("Localizable", "eoy_share_this_story_title", fallback: "Share this story?") }
  /// A smaller title for the End of Year feature
  internal static var eoySmallTitle: String { return L10n.tr("Localizable", "eoy_small_title", fallback: "Year in Podcasts") }
  /// Subtitle explaining the user why they should subscribe to Plus in the context of the end of year stories.
  internal static var eoyStartYourFreeTrial: String { return L10n.tr("Localizable", "eoy_start_your_free_trial", fallback: "Start your Free Trial") }
  /// When loading the End of Year stats stories fails.
  internal static var eoyStoriesFailed: String { return L10n.tr("Localizable", "eoy_stories_failed", fallback: "Failed to load stories.") }
  /// Subtitle for the epilogue story
  internal static var eoyStoryEpilogueSubtitle: String { return L10n.tr("Localizable", "eoy_story_epilogue_subtitle", fallback: "Don't forget to share with your friends and give a shout out to your favorite podcast creators") }
  /// Title for the epilogue story
  internal static var eoyStoryEpilogueTitle: String { return L10n.tr("Localizable", "eoy_story_epilogue_title", fallback: "Thank you for listening with us this year.\nSee you in 2024!") }
  /// Description that appears on the first story of the 2022 Pocket Casts wrap up (End of Year)
  internal static var eoyStoryIntroTitle: String { return L10n.tr("Localizable", "eoy_story_intro_title", fallback: "Let's celebrate your year of listening...") }
  /// String telling the user how much time they listened to podcasts in 2022, %1$@ is a placeholder for the amount of time.
  internal static func eoyStoryListenedTo(_ p1: Any) -> String {
    return L10n.tr("Localizable", "eoy_story_listened_to", String(describing: p1), fallback: "In 2022, you spent %1$@ listening to podcasts")
  }
  /// String telling the user how much podcast categories they listened to podcasts in 2022, %1$@ is a placeholder a segment of text that contains the number of categories .
  internal static func eoyStoryListenedToCategories(_ p1: Any) -> String {
    return L10n.tr("Localizable", "eoy_story_listened_to_categories", String(describing: p1), fallback: "You listened to %1$@ different categories this year")
  }
  /// String telling the user how much podcast categories they listened to podcasts in 2022, %1$@ is a placeholder a segment of text that contains the number of categories .
  internal static func eoyStoryListenedToCategoriesHighlighted(_ p1: Any) -> String {
    return L10n.tr("Localizable", "eoy_story_listened_to_categories_highlighted", String(describing: p1), fallback: "You listened to %1$@ this year")
  }
  /// Text that appears when someone shares the listened categories to story to Twitter, for example. %1$@ is a placeholder for the number of categories.
  internal static func eoyStoryListenedToCategoriesShareText(_ p1: Any) -> String {
    return L10n.tr("Localizable", "eoy_story_listened_to_categories_share_text", String(describing: p1), fallback: "I listened to %1$@ different categories in 2023")
  }
  /// String prompting the user for the next story to check the most listened categories.
  internal static var eoyStoryListenedToCategoriesSubtitle: String { return L10n.tr("Localizable", "eoy_story_listened_to_categories_subtitle", fallback: "Let's take a look at some of your favorites...") }
  /// String telling the user how much podcast categories they listened to podcasts in 2022, %1$@ is a placeholder for the number of different categories.
  internal static func eoyStoryListenedToCategoriesText(_ p1: Any) -> String {
    return L10n.tr("Localizable", "eoy_story_listened_to_categories_text", String(describing: p1), fallback: "%1$@ different categories")
  }
  /// String telling the user how many episodes they listened to this year, %1$@ is a placeholder for the number number of episodes.
  internal static func eoyStoryListenedToEpisodesText(_ p1: Any) -> String {
    return L10n.tr("Localizable", "eoy_story_listened_to_episodes_text", String(describing: p1), fallback: "%1$@ episodes")
  }
  /// String telling the user how many podcasts and episodes they listened to this year, %1$@ is a placeholder for the number of podcasts and %2$@ is a placeholder for the number of episodes.
  internal static func eoyStoryListenedToNumbers(_ p1: Any, _ p2: Any) -> String {
    return L10n.tr("Localizable", "eoy_story_listened_to_numbers", String(describing: p1), String(describing: p2), fallback: "You listened to %1$@ different shows and %2$@ episodes in total")
  }
  /// Text that appear when someone share the listened numbers story to Twitter. %1$@ is a placeholder for the number of podcasts listened and %2$@ for the number of episodes.
  internal static func eoyStoryListenedToNumbersShareText(_ p1: Any, _ p2: Any) -> String {
    return L10n.tr("Localizable", "eoy_story_listened_to_numbers_share_text", String(describing: p1), String(describing: p2), fallback: "I listened to %1$@ different podcasts and %2$@ episodes this year")
  }
  /// Subtitle for the story containing number of podcasts and episodes played this year. Segway for the next story.
  internal static var eoyStoryListenedToNumbersSubtitle: String { return L10n.tr("Localizable", "eoy_story_listened_to_numbers_subtitle", fallback: "But there was one you kept coming to...") }
  /// String telling the user how many podcasts and episodes they listened to this year, %1$@ is a placeholder for the number of podcasts and %2$@ is a placeholder for the number of episodes.
  internal static func eoyStoryListenedToNumbersUpdated(_ p1: Any, _ p2: Any) -> String {
    return L10n.tr("Localizable", "eoy_story_listened_to_numbers_updated", String(describing: p1), String(describing: p2), fallback: "You listened to %1$@ and %2$@")
  }
  /// String telling the user how many podcasts they listened to this year, %1$@ is a placeholder for the number of podcasts
  internal static func eoyStoryListenedToPodcastText(_ p1: Any) -> String {
    return L10n.tr("Localizable", "eoy_story_listened_to_podcast_text", String(describing: p1), fallback: "%1$@ different podcasts")
  }
  /// Text that appears when someone shares the listened to story to Twitter, for example. %1$@ is a placeholder for the amount of time.
  internal static func eoyStoryListenedToShareText(_ p1: Any) -> String {
    return L10n.tr("Localizable", "eoy_story_listened_to_share_text", String(describing: p1), fallback: "I spent %1$@ listening to podcasts this year")
  }
  /// Title of the listening time Story.
  internal static var eoyStoryListenedToSubtitle: String { return L10n.tr("Localizable", "eoy_story_listened_to_subtitle", fallback: "We hope you loved every minute of it!") }
  /// Title of the listening time Story.
  internal static var eoyStoryListenedToTitle: String { return L10n.tr("Localizable", "eoy_story_listened_to_title", fallback: "This was your total time listening to podcasts") }
  /// String telling the user how much time they listened to podcasts in 2022, %1$@ is a placeholder for the amount of time.
  internal static func eoyStoryListenedToUpdated(_ p1: Any) -> String {
    return L10n.tr("Localizable", "eoy_story_listened_to_updated", String(describing: p1), fallback: "This year, you spent %1$@ listening to podcasts")
  }
  /// Title for the story showing the longest episode listened for the user in the current year. %1$@ is a placeholder for the episode title and %2$@ is a placeholder for the podcast title.
  internal static func eoyStoryLongestEpisode(_ p1: Any) -> String {
    return L10n.tr("Localizable", "eoy_story_longest_episode", String(describing: p1), fallback: "The longest episode you listened to was %1$@")
  }
  /// Subtitle for the story showing the longest episode listened for the user in the current year. %1$@ is a placeholder for the episode length.
  internal static func eoyStoryLongestEpisodeDuration(_ p1: Any) -> String {
    return L10n.tr("Localizable", "eoy_story_longest_episode_duration", String(describing: p1), fallback: "This episode was %1$@ long")
  }
  /// Text that appear when someone share the longest episode they listened to story to Twitter. %1$@ is the URL to the episode.
  internal static func eoyStoryLongestEpisodeShareText(_ p1: Any) -> String {
    return L10n.tr("Localizable", "eoy_story_longest_episode_share_text", String(describing: p1), fallback: "The longest episode I listened to this year %1$@")
  }
  /// Title for the story showing the longest episode listened for the user in the current year. %1$@ is a placeholder for the title of the podcast for the longest episode.
  internal static func eoyStoryLongestEpisodeSubtitle(_ p1: Any, _ p2: Any) -> String {
    return L10n.tr("Localizable", "eoy_story_longest_episode_subtitle", String(describing: p1), String(describing: p2), fallback: "It was none other than “%1$@” from “%2$@”")
  }
  /// Title for the story showing the longest episode listened for the user in the current year. %1$@ is a placeholder for the duration of the episode.
  internal static func eoyStoryLongestEpisodeTime(_ p1: Any) -> String {
    return L10n.tr("Localizable", "eoy_story_longest_episode_time", String(describing: p1), fallback: "The longest episode\nyou listened to was\n%1$@")
  }
  /// Label for the replay button, which when tapped started the end of year stories from the first one.
  internal static var eoyStoryReplay: String { return L10n.tr("Localizable", "eoy_story_replay", fallback: "Play again") }
  /// Title of the top categories story.
  internal static var eoyStoryTopCategories: String { return L10n.tr("Localizable", "eoy_story_top_categories", fallback: "Your Top Categories") }
  /// Text that appear when someone share the top categories story to Twitter.
  internal static var eoyStoryTopCategoriesShareText: String { return L10n.tr("Localizable", "eoy_story_top_categories_share_text", fallback: "My most listened to podcast categories") }
  /// Subtitle of the top categories story. %1$@ is the total number of episodes and %2$@ is the total listened time.
  internal static func eoyStoryTopCategoriesSubtitle(_ p1: Any, _ p2: Any) -> String {
    return L10n.tr("Localizable", "eoy_story_top_categories_subtitle", String(describing: p1), String(describing: p2), fallback: "You listened to %1$@ episodes for a total of %2$@")
  }
  /// Title of the top categories story. %1$@ being the name of the most listened category.
  internal static func eoyStoryTopCategoriesTitle(_ p1: Any) -> String {
    return L10n.tr("Localizable", "eoy_story_top_categories_title", String(describing: p1), fallback: "Did you know that %1$@ was your favorite category?")
  }
  /// Title for the story that display the most listened podcast by the user this year. %1$@ is a placeholder for the podcast title and %2$@ is a placeholder for the author.
  internal static func eoyStoryTopPodcast(_ p1: Any) -> String {
    return L10n.tr("Localizable", "eoy_story_top_podcast", String(describing: p1), fallback: "%1$@ was your most listened show in 2023")
  }
  /// Text that appear when someone share the top podcast of the year story to Twitter. %1$@ is the URL to the podcast.
  internal static func eoyStoryTopPodcastShareText(_ p1: Any) -> String {
    return L10n.tr("Localizable", "eoy_story_top_podcast_share_text", String(describing: p1), fallback: "My favorite podcast this year! %1$@")
  }
  /// Subtitle for the story that display the most listened podcast by the user this year. %1$@ is a placeholder for the number of episodes and %2$@ is a placeholder for the listened time.
  internal static func eoyStoryTopPodcastSubtitle(_ p1: Any, _ p2: Any) -> String {
    return L10n.tr("Localizable", "eoy_story_top_podcast_subtitle", String(describing: p1), String(describing: p2), fallback: "You listened to %1$@ episodes for a total of %2$@")
  }
  /// Title for the story showing the top podcasts for the user in the current year.
  internal static var eoyStoryTopPodcasts: String { return L10n.tr("Localizable", "eoy_story_top_podcasts", fallback: "Your Top Podcasts") }
  /// Title of a list of podcasts created containing the user's top 5 podcasts of 2022.
  internal static var eoyStoryTopPodcastsListTitle: String { return L10n.tr("Localizable", "eoy_story_top_podcasts_list_title", fallback: "My top podcasts of the year!") }
  /// Text that appear when someone share the top 5 podcasts of the year story to Twitter. %1$@ is a link to the list of the top podcasts.
  internal static func eoyStoryTopPodcastsShareText(_ p1: Any) -> String {
    return L10n.tr("Localizable", "eoy_story_top_podcasts_share_text", String(describing: p1), fallback: "My top podcasts of the year! %1$@")
  }
  /// Subtitle for the story showing the top podcasts for the user in the current year.
  internal static var eoyStoryTopPodcastsSubtitle: String { return L10n.tr("Localizable", "eoy_story_top_podcasts_subtitle", fallback: "This is your top 5 most listened to in 2023") }
  /// Title for the story showing the top podcasts for the user in the current year.
  internal static var eoyStoryTopPodcastsTitle: String { return L10n.tr("Localizable", "eoy_story_top_podcasts_title", fallback: "And you were big on these shows too!") }
  /// Subtitle explaining the user why they should subscribe to Plus in the context of the end of year stories.
  internal static var eoySubscribeToPlus: String { return L10n.tr("Localizable", "eoy_subscribe_to_plus", fallback: "Subscribe to Plus and find out how your listening compares to 2022, other fun stats, and Premium features like bookmarks and folders.") }
  /// Title of the story paywall. Telling the users that there are more stories to check.
  internal static var eoyTheresMore: String { return L10n.tr("Localizable", "eoy_theres_more", fallback: "There’s more!") }
  /// Title for the End of Year feature
  internal static var eoyTitle: String { return L10n.tr("Localizable", "eoy_title", fallback: "Your Year in Podcasts") }
  /// Label of the End of Year call to action button
  internal static var eoyViewYear: String { return L10n.tr("Localizable", "eoy_view_year", fallback: "View My 2023") }
  /// Subtitle when displaying the user episode completion rate, all in lowercase.
  internal static var eoyYearCompletionRate: String { return L10n.tr("Localizable", "eoy_year_completion_rate", fallback: "completion rate") }
  /// Title for when sharing the completion rate story to social media.
  internal static func eoyYearCompletionRateShareText(_ p1: Any) -> String {
    return L10n.tr("Localizable", "eoy_year_completion_rate_share_text", String(describing: p1), fallback: "My %1$@ completion rate")
  }
  /// Title for the completion rate. %1$@ is the total of episodes listened this year, %2$@ is the total of episodes fully listened to.
  internal static func eoyYearCompletionRateSubtitle(_ p1: Any, _ p2: Any) -> String {
    return L10n.tr("Localizable", "eoy_year_completion_rate_subtitle", String(describing: p1), String(describing: p2), fallback: "From the %1$@ episodes you started you listened fully to a total of %2$@")
  }
  /// Title for the completion rate. %1$@ is the percentage.
  internal static func eoyYearCompletionRateTitle(_ p1: Any) -> String {
    return L10n.tr("Localizable", "eoy_year_completion_rate_title", String(describing: p1), fallback: "Your completion rate this year was %1$@")
  }
  /// Text for when a user shares the story comparing the 2022 and 2023 listening time.
  internal static func eoyYearOverShareText(_ p1: Any, _ p2: Any) -> String {
    return L10n.tr("Localizable", "eoy_year_over_share_text", String(describing: p1), String(describing: p2), fallback: "My %1$@ listening time compared to %2$@")
  }
  /// Subtitle of the story that compares year listening time when this year's listening time is almost the same as last's year
  internal static var eoyYearOverYearSubtitleFlat: String { return L10n.tr("Localizable", "eoy_year_over_year_subtitle_flat", fallback: "And they say consistency is the key to success... or something like that!") }
  /// Subtitle of the story that compares year listening time when this year's listening time is less than last's year
  internal static var eoyYearOverYearSubtitleWentDown: String { return L10n.tr("Localizable", "eoy_year_over_year_subtitle_went_down", fallback: "Aaaah... there’s a life to be lived, right?") }
  /// Subtitle of the story that compares year listening time when this year's listening time is bigger than last's year
  internal static var eoyYearOverYearSubtitleWentUp: String { return L10n.tr("Localizable", "eoy_year_over_year_subtitle_went_up", fallback: "Ready to top it in 2024?") }
  /// Title of the story when this year's listening time is almost the same as the previous year. %1$@ is the percentage
  internal static var eoyYearOverYearTitleFlat: String { return L10n.tr("Localizable", "eoy_year_over_year_title_flat", fallback: "Compared to 2022, your listening time stayed pretty consistent") }
  /// Title of the story when this year's listening time is way bigger than previous year.
  internal static var eoyYearOverYearTitleSkyrocketed: String { return L10n.tr("Localizable", "eoy_year_over_year_title_skyrocketed", fallback: "Compared to 2022, your listening time skyrocketed!") }
  /// Title of the story when this year's listening time is less than the previous year. %1$@ is the percentage
  internal static var eoyYearOverYearTitleWentDown: String { return L10n.tr("Localizable", "eoy_year_over_year_title_went_down", fallback: "Compared to 2022, your listening time went down a little") }
  /// Title of the story when this year's listening time is bigger than previous year. %1$@ is the percentage
  internal static func eoyYearOverYearTitleWentUp(_ p1: Any) -> String {
    return L10n.tr("Localizable", "eoy_year_over_year_title_went_up", String(describing: p1), fallback: "Compared to 2022, your listening time went up a whopping %1$@%")
  }
  /// Text for when a user shares the Ratings story summarizing their podcast ratings from the last year
  internal static func eoyYearRatingsShareText(_ p1: Any, _ p2: Any, _ p3: Any) -> String {
    return L10n.tr("Localizable", "eoy_year_ratings_share_text", String(describing: p1), String(describing: p2), String(describing: p3), fallback: "I rated %1$@ different podcasts in %2$@, with %3$@ as my most used rating")
  }
  /// Refers to an Episode in the singular form.
  internal static var episode: String { return L10n.tr("Localizable", "episode", fallback: "Episode") }
  /// A common string used throughout the app. Display configurable options related to a number of episodes. '%1$@' is a placeholder for the number of episodes, the value will be more than one.
  internal static func episodeCountPluralFormat(_ p1: Any) -> String {
    return L10n.tr("Localizable", "episode_count_plural_format", String(describing: p1), fallback: "%1$@ episodes")
  }
  /// Accessibility hint on a person chip on the episode credits card; tapping searches the podcast catalog for that person's name
  internal static var episodeCreditsFindMore: String { return L10n.tr("Localizable", "episode_credits_find_more", fallback: "Find more episodes featuring this person") }
  /// Title of the credits card on the episode detail screen listing the people (hosts, guests) featured on the episode
  internal static var episodeCreditsTitle: String { return L10n.tr("Localizable", "episode_credits_title", fallback: "Credits") }
  /// Title of the Episode description
  internal static var episodeDescriptionTitle: String { return L10n.tr("Localizable", "episode_description_title", fallback: "Episode Description") }
  /// Label for the Add button on the episode detail page. Opens a bottom sheet with options to add to Up Next or playlist.
  internal static var episodeDetailAdd: String { return L10n.tr("Localizable", "episode_detail_add", fallback: "Add") }
  /// Title of a button the clears the current search text
  internal static var episodeDetailsTitle: String { return L10n.tr("Localizable", "episode_details_title", fallback: "Details") }
  /// Label for adding duration filtering to an episode filter, eg: filter by the duration of an episode
  internal static var episodeFilterByDurationLabel: String { return L10n.tr("Localizable", "episode_filter_by_duration_label", fallback: "Filter by duration") }
  /// Message shown when you have no episodes in an episode filter
  internal static var episodeFilterNoEpisodesMsg: String { return L10n.tr("Localizable", "episode_filter_no_episodes_msg", fallback: "Either it's time to celebrate completing this list, or edit your filter settings to get some more.") }
  /// Title shown when you have no episodes in an episode filter
  internal static var episodeFilterNoEpisodesTitle: String { return L10n.tr("Localizable", "episode_filter_no_episodes_title", fallback: "No Episodes") }
  /// Episode indicator that the current episode is a bonus episode.
  internal static var episodeIndicatorBonus: String { return L10n.tr("Localizable", "episode_indicator_bonus", fallback: "Bonus") }
  /// Episode indicator that the current episode is a trailer for an upcoming season of the podcast. '%1$@' is a placeholder for the season number.
  internal static func episodeIndicatorSeasonTrailer(_ p1: Any) -> String {
    return L10n.tr("Localizable", "episode_indicator_season_trailer", String(describing: p1), fallback: "Season %1$@ Trailer")
  }
  /// Episode indicator that the current episode is a trailer.
  internal static var episodeIndicatorTrailer: String { return L10n.tr("Localizable", "episode_indicator_trailer", fallback: "Trailer") }
  /// Tappable seek link under a mentioned entity; '%1$@' is a timestamp like 34:12
  internal static func episodeMentionsAtTime(_ p1: Any) -> String {
    return L10n.tr("Localizable", "episode_mentions_at_time", String(describing: p1), fallback: "Mentioned at %1$@")
  }
  /// Header of the episode-detail card listing entities extracted from the transcript
  internal static var episodeMentionsTitle: String { return L10n.tr("Localizable", "episode_mentions_title", fallback: "Mentioned in this episode") }
  /// Shorthand format used to show the Episode number of a podcast. '%1$@' is a placeholder for the episode number.
  internal static func episodeShorthandFormat(_ p1: Any) -> String {
    return L10n.tr("Localizable", "episode_shorthand_format", String(describing: p1), fallback: "EPISODE %1$@")
  }
  /// Shorthand format used to show the Episode number of a podcast. 'EP' is short for Episode. '%1$@' is a placeholder for the episode number.
  internal static func episodeShorthandFormatShort(_ p1: Any) -> String {
    return L10n.tr("Localizable", "episode_shorthand_format_short", String(describing: p1), fallback: "EP %1$@")
  }
  /// Caption on the episode summary card disclosing that the summary and takeaways are AI-generated and may not be perfectly accurate
  internal static var episodeSummaryCardGeneratedDisclaimer: String { return L10n.tr("Localizable", "episode_summary_card_generated_disclaimer", fallback: "AI-generated") }
  /// Header for the list of chapter-based key moments on the episode summary card, shown when on-device takeaway generation is unavailable
  internal static var episodeSummaryCardKeyMoments: String { return L10n.tr("Localizable", "episode_summary_card_key_moments", fallback: "Key moments") }
  /// Button that collapses the expanded episode summary text back to a preview
  internal static var episodeSummaryCardShowLess: String { return L10n.tr("Localizable", "episode_summary_card_show_less", fallback: "Show less") }
  /// Button that expands the truncated episode summary text to show it in full
  internal static var episodeSummaryCardShowMore: String { return L10n.tr("Localizable", "episode_summary_card_show_more", fallback: "Show more") }
  /// Title of the AI episode summary card on the episode detail screen
  internal static var episodeSummaryCardTitle: String { return L10n.tr("Localizable", "episode_summary_card_title", fallback: "Episode Summary") }
  /// Message indicating that the episode is unavailable server side but will remain in your manual playlist until removed.
  internal static var episodeUnavailableMessage: String { return L10n.tr("Localizable", "episode_unavailable_message", fallback: "The podcast creator deleted this episode. It will stay in your playlist until you remove it.") }
  /// Title indicating that the episode is unavailable server side
  internal static var episodeUnavailableTitle: String { return L10n.tr("Localizable", "episode_unavailable_title", fallback: "Episode Unavailable") }
  /// Refers to an Episode in the plural form.
  internal static var episodes: String { return L10n.tr("Localizable", "episodes", fallback: "Episodes") }
  /// A common string used throughout the app. Generic title informing the user of an Error. Accompanied with an error message.
  internal static var error: String { return L10n.tr("Localizable", "error", fallback: "Error") }
  /// A common string used throughout the app. Generic title informing the user of an Error. General error message used when the app is unable to locate the podcast that was selected. This usually comes from a sharing or import feature.
  internal static var errorGeneralPodcastNotFound: String { return L10n.tr("Localizable", "error_general_podcast_not_found", fallback: "Unable to find podcast. Please contact the podcast author.") }
  /// Explore tab: label for the category chip that shows the overall top charts across all categories.
  internal static var exploreAllCategories: String { return L10n.tr("Localizable", "explore_all_categories", fallback: "All") }
  /// Explore tab: error message shown when the podcast charts or search results fail to load.
  internal static var exploreLoadFailed: String { return L10n.tr("Localizable", "explore_load_failed", fallback: "Unable to load podcasts. Check your connection and try again.") }
  /// Explore tab: message shown when a podcast search returns no results.
  internal static var exploreNoResults: String { return L10n.tr("Localizable", "explore_no_results", fallback: "No podcasts found") }
  /// Title of the Explore tab in the main tab bar, where users can discover new podcasts.
  internal static var exploreTabTitle: String { return L10n.tr("Localizable", "explore_tab_title", fallback: "Explore") }
  /// Title of an option to export the users data
  internal static var exportDatabase: String { return L10n.tr("Localizable", "export_database", fallback: "Export Database") }
  /// Describes how the process to export podcasts from Pocket Casts works.
  internal static var exportPodcastsDescription: String { return L10n.tr("Localizable", "export_podcasts_description", fallback: "Exports all your podcasts as an OPML file, which you can import into other podcast apps.") }
  /// Title for the button that allows the user to export podcasts from Pocket Casts
  internal static var exportPodcastsOption: String { return L10n.tr("Localizable", "export_podcasts_option", fallback: "Export Podcasts") }
  /// Title for the section that provides information on how to export podcasts from Pocket Casts
  internal static var exportPodcastsTitle: String { return L10n.tr("Localizable", "export_podcasts_title", fallback: "EXPORT") }
  /// Title of a message shown when the users data is being exported
  internal static var exportingDatabase: String { return L10n.tr("Localizable", "exporting_database", fallback: "Exporting Database...") }
  /// Title shown when recommended podcasts can't be loaded
  internal static var failedRecommendations: String { return L10n.tr("Localizable", "failed_recommendations", fallback: "Couldn't load recommendations") }
  /// Patron has all features of plus marketing message
  internal static var featureMarketingAllPlusFeatures: String { return L10n.tr("Localizable", "feature_marketing_all_plus_features", fallback: "All the features in Plus") }
  /// Bookmarks feature marketing message
  internal static var featureMarketingBookmarks: String { return L10n.tr("Localizable", "feature_marketing_bookmarks", fallback: "Keep timestamps with Bookmarks") }
  /// Patron early access to new features marketing message
  internal static var featureMarketingEarlyAccess: String { return L10n.tr("Localizable", "feature_marketing_early_access", fallback: "Early access to new features") }
  /// Extra Themes And App Icons feature marketing message
  internal static var featureMarketingExtraThemesIcons: String { return L10n.tr("Localizable", "feature_marketing_extra_themes_icons", fallback: "Extra Themes and App Icons") }
  /// Folders feature marketing message
  internal static var featureMarketingFolders: String { return L10n.tr("Localizable", "feature_marketing_folders", fallback: "Tidy your collection with Folders") }
  /// SKip Chapters feature marketing message
  internal static var featureMarketingSkipChapters: String { return L10n.tr("Localizable", "feature_marketing_skip_chapters", fallback: "Save time with Preselect Chapters") }
  /// Slumber Studios feature marketing message
  internal static var featureMarketingSlumber: String { return L10n.tr("Localizable", "feature_marketing_slumber", fallback: "1 year of content from Slumber Studios") }
  /// Shuffle up next queue feature marketing message
  internal static var featureMarketingUpNextShuffle: String { return L10n.tr("Localizable", "feature_marketing_up_next_shuffle", fallback: "Shuffle your queue") }
  /// Indicator during the new feature tour serves as a prompt to end the tour.
  internal static var featureTourEndTour: String { return L10n.tr("Localizable", "feature_tour_end_tour", fallback: "End Tour") }
  /// Indicator during the new feature tour. Used as a navigation indicator when the tour is on the first step. This is replaced with 'position of total' as the user progresses.
  internal static var featureTourNew: String { return L10n.tr("Localizable", "feature_tour_new", fallback: "NEW") }
  /// Indicator during the new feature tour. Used as a navigation indicator as the user progresses through the tour. '%1$@' is a placeholder for the current position. '%2$@' is a placeholder for the total number of steps.
  internal static func featureTourStepFormat(_ p1: Any, _ p2: Any) -> String {
    return L10n.tr("Localizable", "feature_tour_step_format", String(describing: p1), String(describing: p2), fallback: "%1$@ of %2$@")
  }
  /// Option to continue with a Third-Party Mail app when the default Apple mail app isn't available.
  internal static var feedbackContinueWithMail: String { return L10n.tr("Localizable", "feedback_continue_with_mail", fallback: "Open Default Mail App") }
  /// Error message for when the user has a mail app configured that's not the default mail app.
  internal static var feedbackMailNotConfiguredMsg: String { return L10n.tr("Localizable", "feedback_mail_not_configured_msg", fallback: "To send a debug attachment, the Apple Mail app has to be configured on your phone. What would you like to do?") }
  /// Error title for when the user has a mail app configured that's not the default mail app.
  internal static var feedbackMailNotConfiguredTitle: String { return L10n.tr("Localizable", "feedback_mail_not_configured_title", fallback: "Mail Not Configured") }
  /// Button title that lets the user pick a different local file-sync folder.
  internal static var fileSyncActionChooseFolder: String { return L10n.tr("Localizable", "file_sync_action_choose_folder", fallback: "Choose Folder") }
  /// Button title that starts a manual file-sync pass.
  internal static var fileSyncActionSyncNow: String { return L10n.tr("Localizable", "file_sync_action_sync_now", fallback: "Sync Now") }
  /// Destructive action that deletes a folder-backed upload from the sync folder and all devices.
  internal static var fileSyncDeleteEverywhere: String { return L10n.tr("Localizable", "file_sync_delete_everywhere", fallback: "Delete Everywhere") }
  /// Empty-state message shown in Files when local file sync is enabled and no files exist.
  internal static var fileSyncFilesEmptyMessage: String { return L10n.tr("Localizable", "file_sync_files_empty_message", fallback: "Add files here or drop supported audio files into your Pocket Casts uploads folder.") }
  /// Footer text explaining where uploaded files are stored.
  internal static var fileSyncFolderExplanation: String { return L10n.tr("Localizable", "file_sync_folder_explanation", fallback: "Pocket Casts stores your uploaded files in this folder, and files added to it appear on every device using the same folder. You can use iCloud Drive or choose another Files location.") }
  /// Label for the default iCloud Drive file-sync folder.
  internal static var fileSyncFolderIcloud: String { return L10n.tr("Localizable", "file_sync_folder_icloud", fallback: "iCloud Drive") }
  /// Label for a user-picked file-sync folder.
  internal static var fileSyncFolderPicked: String { return L10n.tr("Localizable", "file_sync_folder_picked", fallback: "Picked Folder") }
  /// Action that removes only the local cached copy of a folder-backed upload.
  internal static var fileSyncRemoveDownload: String { return L10n.tr("Localizable", "file_sync_remove_download", fallback: "Remove Download") }
  /// Row label for the current file-sync folder type.
  internal static var fileSyncStatusFolder: String { return L10n.tr("Localizable", "file_sync_status_folder", fallback: "Folder") }
  /// Row label for the most recent successful file-sync pass.
  internal static var fileSyncStatusLastSync: String { return L10n.tr("Localizable", "file_sync_status_last_sync", fallback: "Last Sync") }
  /// Value shown when file sync is disabled.
  internal static var fileSyncStatusOff: String { return L10n.tr("Localizable", "file_sync_status_off", fallback: "Off") }
  /// Value shown when file sync is enabled.
  internal static var fileSyncStatusOn: String { return L10n.tr("Localizable", "file_sync_status_on", fallback: "On") }
  /// Row label for the current file-sync enabled state.
  internal static var fileSyncStatusState: String { return L10n.tr("Localizable", "file_sync_status_state", fallback: "State") }
  /// Title for the file upload settings screen. This is used when a user is uploading a new file.
  internal static var fileUploadAddFile: String { return L10n.tr("Localizable", "file_upload_add_file", fallback: "Add File") }
  /// Prompt to add a custom image to the uploaded file.
  internal static var fileUploadAddImage: String { return L10n.tr("Localizable", "file_upload_add_image", fallback: "Add Custom Image") }
  /// Title for the dialog that allows the user to pick the image source for selecting a custom image. either Camera or Photo Library.
  internal static var fileUploadChooseImage: String { return L10n.tr("Localizable", "file_upload_choose_image", fallback: "Choose Image") }
  /// Option for selecting the image source for an uploaded image.
  internal static var fileUploadChooseImageCamera: String { return L10n.tr("Localizable", "file_upload_choose_image_camera", fallback: "Camera") }
  /// Option for selecting the image source for an uploaded image.
  internal static var fileUploadChooseImagePhotoLibrary: String { return L10n.tr("Localizable", "file_upload_choose_image_photo_Library", fallback: "Photo Library") }
  /// Title for the file upload settings screen. This is used when a user is editing an uploaded file.
  internal static var fileUploadEditFile: String { return L10n.tr("Localizable", "file_upload_edit_file", fallback: "Edit File") }
  /// Prompt indicating that the user needs to name the file in order to upload it.
  internal static var fileUploadNameRequired: String { return L10n.tr("Localizable", "file_upload_name_required", fallback: "Name required") }
  /// The description for the screen when there are no files currently uploaded. '
  /// ' is a line break format to allow a clean wrapping of text
  internal static var fileUploadNoFilesDescription: String { return L10n.tr("Localizable", "file_upload_no_files_description", fallback: "Upload your own files to Pocket Casts, and listen or watch them anytime.") }
  /// The helper link describing how to add files to Pocket Casts.
  internal static var fileUploadNoFilesHelper: String { return L10n.tr("Localizable", "file_upload_no_files_helper", fallback: "How do I do that?") }
  /// Title for the screen when there are no files currently uploaded
  internal static var fileUploadNoFilesTitle: String { return L10n.tr("Localizable", "file_upload_no_files_title", fallback: "Listen or watch your own files") }
  /// Prompt to remove the image from the uploaded file.
  internal static var fileUploadRemoveImage: String { return L10n.tr("Localizable", "file_upload_remove_image", fallback: "Remove Image") }
  /// Prompt to save the changes to an edited file.
  internal static var fileUploadSave: String { return L10n.tr("Localizable", "file_upload_save", fallback: "Save") }
  /// Error message displayed when the user has attempted to upload an unsupported file type.
  internal static var fileUploadSupportError: String { return L10n.tr("Localizable", "file_upload_support_error", fallback: "This file type is not supported") }
  /// A common string used throughout the app. Refers to the Files settings menu
  internal static var files: String { return L10n.tr("Localizable", "files", fallback: "Files") }
  /// Title for the screen that details how to add a file to Pocket Casts.
  internal static var filesHowToTitle: String { return L10n.tr("Localizable", "files_how_to_title", fallback: "How to save a file") }
  /// Prompt to open a menu to allow sorting of manually added files.
  internal static var filesSort: String { return L10n.tr("Localizable", "files_sort", fallback: "Sort Files") }
  /// Subtitle informing the user that new podcasts will be automatically added to this filter.
  internal static var filterAutoAddSubtitle: String { return L10n.tr("Localizable", "filter_auto_add_subtitle", fallback: "New podcasts you subscribe to will be automatically added") }
  /// Subtitle informing the user that new podcasts will be automatically added to this filter.
  internal static var filterAutoAddSubtitleNew: String { return L10n.tr("Localizable", "filter_auto_add_subtitle_new", fallback: "New podcasts you follow to will be automatically added") }
  /// Title for the filter option that indicates all podcasts will be included.
  internal static var filterChipsAllPodcasts: String { return L10n.tr("Localizable", "filter_chips_all_podcasts", fallback: "All Your Podcasts") }
  /// Title for the filter option that that opens the episode duration options.
  internal static var filterChipsDuration: String { return L10n.tr("Localizable", "filter_chips_duration", fallback: "Duration") }
  /// Filter option to select podcasts that will be included in the filter.
  internal static var filterChoosePodcasts: String { return L10n.tr("Localizable", "filter_choose_podcasts", fallback: "Choose Podcasts") }
  /// Used on the screen to create a new filter. Provides a prompt to continue refining the filter selections.
  internal static var filterCreateAddMore: String { return L10n.tr("Localizable", "filter_create_add_more", fallback: "Add more criteria to finish refining your filter.") }
  /// Used on the screen to create a new filter. The section header for the list of options to use with the filter.
  internal static var filterCreateFilterBy: String { return L10n.tr("Localizable", "filter_create_filter_by", fallback: "FILTER BY") }
  /// Used on the screen to create a new filter. Provides instructions on how to set up a new filter.
  internal static var filterCreateInstructions: String { return L10n.tr("Localizable", "filter_create_instructions", fallback: "Select your filter criteria using these buttons to create an up to date smart playlist of episodes.") }
  /// Used on the screen to create a new filter. Title for the state where their selection doesn't include any content.
  internal static var filterCreateNoEpisodes: String { return L10n.tr("Localizable", "filter_create_no_episodes", fallback: "No Matching Episodes") }
  /// Used on the screen to create a new filter. The description about why the list of filtered episodes is empty.
  internal static var filterCreateNoEpisodesDescriptionExplanation: String { return L10n.tr("Localizable", "filter_create_no_episodes_description_explanation", fallback: "The criteria you selected doesn’t match any current episodes in your subscriptions") }
  /// Used on the screen to create a new filter. The description about why the list of filtered episodes is empty.
  internal static var filterCreateNoEpisodesDescriptionExplanationNew: String { return L10n.tr("Localizable", "filter_create_no_episodes_description_explanation_new", fallback: "The criteria you selected doesn’t match any current episodes in your podcasts") }
  /// Used on the screen to create a new filter. The prompt about what they can do in order to make sure their filter returns results.
  internal static var filterCreateNoEpisodesDescriptionPrompt: String { return L10n.tr("Localizable", "filter_create_no_episodes_description_prompt", fallback: "Choose different criteria, or save this filter if you think it will match episodes in the future.") }
  /// Used on the screen to create a new filter. Title for the toggle to include all podcasts in the filter.
  internal static var filterCreatePodcastsAllPodcasts: String { return L10n.tr("Localizable", "filter_create_podcasts_all_podcasts", fallback: "All Podcasts") }
  /// Used on the screen to create a new filter. The section that shows a preview of what podcast episodes will be included in the filter.
  internal static var filterCreatePreview: String { return L10n.tr("Localizable", "filter_create_preview", fallback: "PREVIEW") }
  /// Used on the screen to create a new filter. Title for the button to save the filter.
  internal static var filterCreateSave: String { return L10n.tr("Localizable", "filter_create_save", fallback: "Save Filter") }
  /// Title for the screen where a user can set the initial details for a new filter.
  internal static var filterDetails: String { return L10n.tr("Localizable", "filter_details", fallback: "Filter Details") }
  /// Hint text above the sections for the user to select the filter color and icon.
  internal static var filterDetailsColorIcon: String { return L10n.tr("Localizable", "filter_details_color_icon", fallback: "COLOUR & ICON") }
  /// Accessibility hint text for color selection on filters.
  internal static var filterDetailsColorSelection: String { return L10n.tr("Localizable", "filter_details_color_selection", fallback: "Colour Selector") }
  /// Accessibility hint text for icon selection on filters.
  internal static var filterDetailsIconSelection: String { return L10n.tr("Localizable", "filter_details_icon_selection", fallback: "Icon Selector") }
  /// Hint text above the dialog box to enter the filter's name.
  internal static var filterDetailsName: String { return L10n.tr("Localizable", "filter_details_name", fallback: "NAME") }
  /// Title for filter options related to Download Status.
  internal static var filterDownloadStatus: String { return L10n.tr("Localizable", "filter_download_status", fallback: "Download Status") }
  /// Title for filter sections that relate to episode status.
  internal static var filterEpisodeStatus: String { return L10n.tr("Localizable", "filter_episode_status", fallback: "Episode Status") }
  /// Label for the longer than duration filter time
  internal static var filterLongerThanLabel: String { return L10n.tr("Localizable", "filter_longer_than_label", fallback: "Longer than") }
  /// Subtitle informing the user that new podcasts will not be automatically added to this filter.
  internal static var filterManualAddSubtitle: String { return L10n.tr("Localizable", "filter_manual_add_subtitle", fallback: "New podcasts you subscribe to will not be automatically added") }
  /// Subtitle informing the user that new podcasts will not be automatically added to this filter.
  internal static var filterManualAddSubtitleNew: String { return L10n.tr("Localizable", "filter_manual_add_subtitle_new", fallback: "New podcasts you follow to will not be automatically added") }
  /// Title for filter options related to media type settings.
  internal static var filterMediaType: String { return L10n.tr("Localizable", "filter_media_type", fallback: "Media Type") }
  /// Media Type filter option for audio media types.
  internal static var filterMediaTypeAudio: String { return L10n.tr("Localizable", "filter_media_type_audio", fallback: "Audio") }
  /// Media Type filter option for video media types.
  internal static var filterMediaTypeVideo: String { return L10n.tr("Localizable", "filter_media_type_video", fallback: "Video") }
  /// Screen title for the filter options for configuring filter settings related to episode duration.
  internal static var filterOptionEpisodeDuration: String { return L10n.tr("Localizable", "filter_option_episode_duration", fallback: "Episode Duration") }
  /// Error message for when the user attempts to set a filter where the minimal duration is higher than the max duration. Meant to be a fun/funny message. '%1$@' and '%2$@' are placeholders for the configured minimum and maximum times, respectively.
  internal static func filterOptionEpisodeDurationErrorMsgFormat(_ p1: Any, _ p2: Any) -> String {
    return L10n.tr("Localizable", "filter_option_episode_duration_error_msg_format", String(describing: p1), String(describing: p2), fallback: "Filtering for episodes longer than %1$@ but shorter than %2$@ would cause a rift in our space time continuum. Sorry.")
  }
  /// Error title for when the user attempts to set a filter where the minimal duration is higher than the max duration. Meant to be a fun/funny message.
  internal static var filterOptionEpisodeDurationErrorTitle: String { return L10n.tr("Localizable", "filter_option_episode_duration_error_title", fallback: "Yes, But No") }
  /// Menu prompt to open the Filter options. Also used for the title of the filter options screen.
  internal static var filterOptions: String { return L10n.tr("Localizable", "filter_options", fallback: "Filter Options") }
  /// Title for filter options related to release date settings.
  internal static var filterReleaseDate: String { return L10n.tr("Localizable", "filter_release_date", fallback: "Release Date") }
  /// Release Date filter option for any release date.
  internal static var filterReleaseDateAnytime: String { return L10n.tr("Localizable", "filter_release_date_anytime", fallback: "Any time") }
  /// Release Date filter option for episodes with a release date with in the last day.
  internal static var filterReleaseDateLast24Hours: String { return L10n.tr("Localizable", "filter_release_date_last_24_hours", fallback: "Last 24 hours") }
  /// Release Date filter option for episodes with a release date with in the last 2 weeks.
  internal static var filterReleaseDateLast2Weeks: String { return L10n.tr("Localizable", "filter_release_date_last_2_weeks", fallback: "Last 2 weeks") }
  /// Release Date filter option for episodes with a release date with in the last three day.
  internal static var filterReleaseDateLast3Days: String { return L10n.tr("Localizable", "filter_release_date_last_3_days", fallback: "Last 3 days") }
  /// Release Date filter option for episodes with a release date with in the last month.
  internal static var filterReleaseDateLastMonth: String { return L10n.tr("Localizable", "filter_release_date_last_month", fallback: "Last month") }
  /// Release Date filter option for episodes with a release date with in the last week.
  internal static var filterReleaseDateLastWeek: String { return L10n.tr("Localizable", "filter_release_date_last_week", fallback: "Last week") }
  /// Label for the shorter than duration filter time
  internal static var filterShorterThanLabel: String { return L10n.tr("Localizable", "filter_shorter_than_label", fallback: "Shorter than") }
  /// Prompt to save the changes to an existing filter.
  internal static var filterUpdate: String { return L10n.tr("Localizable", "filter_update", fallback: "Update Filter") }
  /// A common string used throughout the app. Filter option for the default setting on multiple filters.
  internal static var filterValueAll: String { return L10n.tr("Localizable", "filter_value_all", fallback: "All") }
  /// A common string used throughout the app. Often refers to the Filters screen.
  internal static var filters: String { return L10n.tr("Localizable", "filters", fallback: "Filters") }
  /// A placeholder title for a newly created filter.
  internal static var filtersDefaultNewFilter: String { return L10n.tr("Localizable", "filters_default_new_filter", fallback: "New Filter") }
  /// The title for the auto generated 'New Release' filter.
  internal static var filtersDefaultNewReleases: String { return L10n.tr("Localizable", "filters_default_new_releases", fallback: "New Releases") }
  /// Button title for adding a new filter.
  internal static var filtersNewFilterButton: String { return L10n.tr("Localizable", "filters_new_filter_button", fallback: "+ New Filter") }
  /// The description shown in a Tip View when the user hasn't yet added a filter
  internal static var filtersTipViewDescription: String { return L10n.tr("Localizable", "filters_tip_view_description", fallback: "Create smart filters to organize your episodes. Filter by duration, release date, media type, and more.") }
  /// The title shown in a Tip View when the user hasn't yet added a filter
  internal static var filtersTipViewTitle: String { return L10n.tr("Localizable", "filters_tip_view_title", fallback: "Organize your episodes") }
  /// Common word used as in the app to denote a folder of items
  internal static var folder: String { return L10n.tr("Localizable", "folder", fallback: "Folder") }
  /// A common string used throughout the app. Informs the user how many podcasts are being added. '%1$@' is a placeholder for the number of podcasts, this will be more than one.
  internal static func folderAddPodcastsPluralFormat(_ p1: Any) -> String {
    return L10n.tr("Localizable", "folder_add_podcasts_plural_format", String(describing: p1), fallback: "Add %1$@ Podcasts")
  }
  /// A common string used throughout the app. Informs the user how many podcasts have been chosen. This is the singular format for an accompanying plural option.
  internal static var folderAddPodcastsSingular: String { return L10n.tr("Localizable", "folder_add_podcasts_singular", fallback: "Add 1 Podcast") }
  /// Label for the option to add and remove podcasts from a folder
  internal static var folderAddRemovePodcasts: String { return L10n.tr("Localizable", "folder_add_remove_podcasts", fallback: "Add or Remove Podcasts") }
  /// Context menu action title for adding a podcast to a folder
  internal static var folderAddTo: String { return L10n.tr("Localizable", "folder_add_to", fallback: "Add to Folder") }
  /// Text shown on button to change the folder a podcast is in
  internal static var folderChange: String { return L10n.tr("Localizable", "folder_change", fallback: "Change folder") }
  /// Prompt to choose a folder color
  internal static var folderChooseColor: String { return L10n.tr("Localizable", "folder_choose_color", fallback: "Choose a color") }
  /// Title for the page where you select which podcasts are in a folder
  internal static var folderChoosePodcasts: String { return L10n.tr("Localizable", "folder_choose_podcasts", fallback: "Choose Podcasts") }
  /// Reason shown below a color picker for folders
  internal static var folderColorDetail: String { return L10n.tr("Localizable", "folder_color_detail", fallback: "Makes it easier to find folders") }
  /// Title for the create folder page
  internal static var folderCreate: String { return L10n.tr("Localizable", "folder_create", fallback: "Create Folder") }
  /// Voiceover label for creating a new folder
  internal static var folderCreateNew: String { return L10n.tr("Localizable", "folder_create_new", fallback: "Create New Folder") }
  /// Label for the delete folder button
  internal static var folderDelete: String { return L10n.tr("Localizable", "folder_delete", fallback: "Delete Folder") }
  /// Confirmation prompt message after you try to delete a folder
  internal static var folderDeletePromptMsg: String { return L10n.tr("Localizable", "folder_delete_prompt_msg", fallback: "This folder will be deleted, and its contents will be moved back to the Podcasts screen.") }
  /// Confirmation prompt title after you try to delete a folder
  internal static var folderDeletePromptTitle: String { return L10n.tr("Localizable", "folder_delete_prompt_title", fallback: "Are You Sure?") }
  /// Label for the option that lets you edit a folder
  internal static var folderEdit: String { return L10n.tr("Localizable", "folder_edit", fallback: "Edit Folder") }
  /// A button title for the empty folder state which will open the Add Podcasts screen
  internal static var folderEmptyButtonTitle: String { return L10n.tr("Localizable", "folder_empty_button_title", fallback: "Add podcasts") }
  /// Description shown under the title of an empty folder
  internal static var folderEmptyDescription: String { return L10n.tr("Localizable", "folder_empty_description", fallback: "Add podcasts to your folder and they’ll appear here.") }
  /// Title shown in an empty folder
  internal static var folderEmptyTitle: String { return L10n.tr("Localizable", "folder_empty_title", fallback: "Your folder is empty") }
  /// Text shown on button to go to the folder a podcast is in
  internal static var folderGoTo: String { return L10n.tr("Localizable", "folder_go_to", fallback: "Go to folder") }
  /// Placeholder text in the field asking you to name a folder
  internal static var folderName: String { return L10n.tr("Localizable", "folder_name", fallback: "Folder name") }
  /// Title for the folder name page
  internal static var folderNameTitle: String { return L10n.tr("Localizable", "folder_name_title", fallback: "Name your folder") }
  /// Label for the button to create a new folder
  internal static var folderNew: String { return L10n.tr("Localizable", "folder_new", fallback: "New Folder") }
  /// Title shown for podcasts that aren't in a folder
  internal static var folderNoFolder: String { return L10n.tr("Localizable", "folder_no_folder", fallback: "No Folder") }
  /// Title for the page where you select which folder a podcast is in
  internal static var folderPodcastChooseFolder: String { return L10n.tr("Localizable", "folder_podcast_choose_folder", fallback: "Choose Folder") }
  /// Text shown on button to remove a podcast from a folder
  internal static var folderRemoveFrom: String { return L10n.tr("Localizable", "folder_remove_from", fallback: "Remove from folder") }
  /// Shown on a button to save the folder
  internal static var folderSaveFolder: String { return L10n.tr("Localizable", "folder_save_folder", fallback: "Save Folder") }
  /// Name shown for folders that don't have names
  internal static var folderUnnamed: String { return L10n.tr("Localizable", "folder_unnamed", fallback: "Unnamed Folder") }
  /// Common word used as in the app to denote the folders feature
  internal static var folders: String { return L10n.tr("Localizable", "folders", fallback: "Folders") }
  /// Title of a screen that display Folders history
  internal static var foldersHistory: String { return L10n.tr("Localizable", "folders_history", fallback: "Folders History") }
  /// A message explaining how to use the Folders history
  internal static var foldersHistoryExplanation: String { return L10n.tr("Localizable", "folders_history_explanation", fallback: "A list of podcasts that were removed from folders as a result of a sync.") }
  /// Prompt to follow to the selected podcast.
  internal static var follow: String { return L10n.tr("Localizable", "follow", fallback: "Follow") }
  /// Label indicating that the user is currently following the selected podcast, e.g. read by VoiceOver on the follow button once followed.
  internal static var following: String { return L10n.tr("Localizable", "following", fallback: "Following") }
  /// Upsell dialog free trial detail label that informs the user that they no payment is needed, and can cancel at anytime
  internal static var freeTrialDetailLabel: String { return L10n.tr("Localizable", "free_trial_detail_label", fallback: "No Payment Now – Cancel Anytime") }
  /// Free trial duration with the word free emphasized, %1$@ is the localize trial duration (1 month)
  internal static func freeTrialDurationFree(_ p1: Any) -> String {
    return L10n.tr("Localizable", "free_trial_duration_free", String(describing: p1), fallback: "%1$@ FREE")
  }
  /// Free trial duration with the word free trial emphasized, %1$@ is the localized trial duration (1 month)
  internal static func freeTrialDurationFreeTrial(_ p1: Any) -> String {
    return L10n.tr("Localizable", "free_trial_duration_free_trial", String(describing: p1), fallback: "%1$@ FREE TRIAL")
  }
  /// Free trial terms where %1$@ refers to the trial duration (30 days) and %2$@ is the price after the trial ($0.99 / month)
  internal static func freeTrialPricingTerms(_ p1: Any, _ p2: Any) -> String {
    return L10n.tr("Localizable", "free_trial_pricing_terms", String(describing: p1), String(describing: p2), fallback: "%1$@ free then %2$@")
  }
  /// Title for a button that allows the user to subscrbe with a free trial
  internal static var freeTrialStartAndSubscribeButton: String { return L10n.tr("Localizable", "free_trial_start_and_subscribe_button", fallback: "Start Free Trial & Subscribe") }
  /// Upsell dialog confirmation button title when a free trial is active
  internal static var freeTrialStartButton: String { return L10n.tr("Localizable", "free_trial_start_button", fallback: "Start Free Trial") }
  /// Upsell dialog title label when a free trial is active, %1$@ refers to the duration of the trial (1 month)
  internal static func freeTrialTitleLabel(_ p1: Any) -> String {
    return L10n.tr("Localizable", "free_trial_title_label", String(describing: p1), fallback: "Try Plus with %1$@ free")
  }
  /// Funding
  internal static var funding: String { return L10n.tr("Localizable", "funding", fallback: "Funding") }
  /// Funny confirmation message accompanying several descriptive dialogs
  internal static var funnyConfMsg: String { return L10n.tr("Localizable", "funny_conf_msg", fallback: "It really matches your eyes ✨") }
  /// The default value when the user has listened for under one minute.
  internal static var funnyTimeNotEnough: String { return L10n.tr("Localizable", "funny_time_not_enough", fallback: "You really don't listen much, do you?") }
  /// A funny time unit used in stats comparing the listening time to the number of times an airplane has taken off. '%1$@' is a placeholder for the amount of time listened compared to the stat.
  internal static func funnyTimeUnitAirplaneTakeoffs(_ p1: Any) -> String {
    return L10n.tr("Localizable", "funny_time_unit_airplane_takeoffs", String(describing: p1), fallback: "During which time %1$@ planes took off. Please fasten your seatbelt. 🛫")
  }
  /// A funny time unit used in stats comparing the listening time to the number of times an astronaut has sneezed. '%1$@' is a placeholder for the amount of time listened compared to the stat.
  internal static func funnyTimeUnitAstronautSneezes(_ p1: Any) -> String {
    return L10n.tr("Localizable", "funny_time_unit_astronaut_sneezes", String(describing: p1), fallback: "During which time an astronaut sneezed %1$@ times. Achoo! 😤")
  }
  /// A funny time unit used in stats comparing the listening time to the number of times you could have traveled around the world. '%1$@' is a placeholder for the amount of time listened compared to the stat.
  internal static func funnyTimeUnitBalloonTravel(_ p1: Any) -> String {
    return L10n.tr("Localizable", "funny_time_unit_balloon_travel", String(describing: p1), fallback: "During which time you could have gone around the world %1$@ times in an air balloon. 🌏")
  }
  /// A funny time unit used in stats comparing the listening time to the number of births that have happened. '%1$@' is a placeholder for the amount of time listened compared to the stat.
  internal static func funnyTimeUnitBirths(_ p1: Any) -> String {
    return L10n.tr("Localizable", "funny_time_unit_births", String(describing: p1), fallback: "During which time %1$@ babies were born. Wahhh! 🍼")
  }
  /// A funny time unit used in stats comparing the listening time to the number of times you've blinked. '%1$@' is a placeholder for the amount of time listened compared to the stat.
  internal static func funnyTimeUnitBlinks(_ p1: Any) -> String {
    return L10n.tr("Localizable", "funny_time_unit_blinks", String(describing: p1), fallback: "During which time you blinked %1$@ times. Heyooo! 👀")
  }
  /// A funny time unit used in stats comparing the listening time to the number of emails that have been sent. '%1$@' is a placeholder for the amount of time listened compared to the stat.
  internal static func funnyTimeUnitEmails(_ p1: Any) -> String {
    return L10n.tr("Localizable", "funny_time_unit_emails", String(describing: p1), fallback: "During which time %1$@ emails were sent. 💌")
  }
  /// A funny time unit used in stats comparing the listening time to the number of times you farted. '%1$@' is a placeholder for the amount of time listened compared to the stat.
  internal static func funnyTimeUnitFarts(_ p1: Any) -> String {
    return L10n.tr("Localizable", "funny_time_unit_farts", String(describing: p1), fallback: "During which time you released %1$@ oz of air biscuits. Gross! 💨")
  }
  /// A funny time unit used in stats comparing the listening time to the number of times a Google search was performed. '%1$@' is a placeholder for the amount of time listened compared to the stat.
  internal static func funnyTimeUnitGoogle(_ p1: Any) -> String {
    return L10n.tr("Localizable", "funny_time_unit_google", String(describing: p1), fallback: "During which time %1$@ Google searches were performed. Bazinga. 🔎")
  }
  /// A funny time unit used in stats comparing the listening time to the number of times lightning has struck. '%1$@' is a placeholder for the amount of time listened compared to the stat.
  internal static func funnyTimeUnitLightning(_ p1: Any) -> String {
    return L10n.tr("Localizable", "funny_time_unit_lightning", String(describing: p1), fallback: "During which time lightning struck %1$@ times. Boom. ⚡️")
  }
  /// A funny time unit used in stats comparing the listening time to the number of phones that have been produced. '%1$@' is a placeholder for the amount of time listened compared to the stat.
  internal static func funnyTimeUnitPhoneProduction(_ p1: Any) -> String {
    return L10n.tr("Localizable", "funny_time_unit_phone_production", String(describing: p1), fallback: "During which time a certain fruit vendor made $%1$@ 🍏")
  }
  /// A funny time unit used in stats comparing the listening time to the amount of skin cells you've shed. '%1$@' is a placeholder for the amount of time listened compared to the stat.
  internal static func funnyTimeUnitShedSkin(_ p1: Any) -> String {
    return L10n.tr("Localizable", "funny_time_unit_shed_skin", String(describing: p1), fallback: "During which time you shed %1$@ skin cells. Ew? 😅")
  }
  /// A funny time unit used in stats comparing the listening time to the number of times you tied your shoes. '%1$@' is a placeholder for the amount of time listened compared to the stat.
  internal static func funnyTimeUnitTiedShoes(_ p1: Any) -> String {
    return L10n.tr("Localizable", "funny_time_unit_tied_shoes", String(describing: p1), fallback: "During which time you could have tied %1$@ shoe laces. Maybe. 👟")
  }
  /// A funny time unit used in stats comparing the listening time to the number of tweets that have been sent. '%1$@' is a placeholder for the amount of time listened compared to the stat.
  internal static func funnyTimeUnitTweets(_ p1: Any) -> String {
    return L10n.tr("Localizable", "funny_time_unit_tweets", String(describing: p1), fallback: "During which time %1$@ tweets were tooted. Toot! Toot! 🐣")
  }
  /// Banner that indicates whether or not the transcripts are generated by us
  internal static var generatedTranscriptsBanner: String { return L10n.tr("Localizable", "generated_transcripts_banner", fallback: "This transcript is automatically generated and available to Plus subscribers only") }
  /// Description showed in the upsell overlay when a free user access the generated transcripts
  internal static var generatedTranscriptsOverlayDescription: String { return L10n.tr("Localizable", "generated_transcripts_overlay_description", fallback: "Subscribe to Plus to get access to it and other Premium features like bookmarks and folders.") }
  /// Title showed in the upsell overlay when a free user access the generated transcripts
  internal static var generatedTranscriptsOverlayTitle: String { return L10n.tr("Localizable", "generated_transcripts_overlay_title", fallback: "This transcript is automatically generated by Pocket Casts.") }
  /// A title for an action to navigate to the Discover section
  internal static var goToDiscover: String { return L10n.tr("Localizable", "go_to_discover", fallback: "Go to Discover") }
  /// A common string used throughout the app. Title for the prompt to navigate the user to the podcast associated to the selected item.
  internal static var goToPodcast: String { return L10n.tr("Localizable", "go_to_podcast", fallback: "Go to Podcast") }
  /// Used in a button meaning that the user undestood the message.
  internal static var gotIt: String { return L10n.tr("Localizable", "got_it", fallback: "Got it") }
  /// A common string used throughout the app. Title accompanying the group option setting.
  internal static var groupEpisodes: String { return L10n.tr("Localizable", "group_episodes", fallback: "Group Episodes") }
  /// Displayed when doing a heavy task the user has to wait
  internal static var hangOn: String { return L10n.tr("Localizable", "hang_on", fallback: "Hang on!") }
  /// Confirmation style option: no audible confirmation.
  internal static var highlightConfirmationNone: String { return L10n.tr("Localizable", "highlight_confirmation_none", fallback: "None") }
  /// Confirmation style option: play the confirmation tone only.
  internal static var highlightConfirmationSound: String { return L10n.tr("Localizable", "highlight_confirmation_sound", fallback: "Sound") }
  /// Confirmation style option: play the tone and speak a short confirmation.
  internal static var highlightConfirmationSoundSpoken: String { return L10n.tr("Localizable", "highlight_confirmation_sound_spoken", fallback: "Sound and Spoken") }
  /// Confirmation style option: speak a short confirmation only.
  internal static var highlightConfirmationSpoken: String { return L10n.tr("Localizable", "highlight_confirmation_spoken", fallback: "Spoken") }
  /// Shown in the highlight editor when the episode has no transcript, so only title and tags can be edited.
  internal static var highlightEditorNoTranscript: String { return L10n.tr("Localizable", "highlight_editor_no_transcript", fallback: "No transcript available for this episode — the excerpt can't be trimmed.") }
  /// Placeholder for the tag input field in the highlight editor.
  internal static var highlightEditorTagPlaceholder: String { return L10n.tr("Localizable", "highlight_editor_tag_placeholder", fallback: "Add a tag") }
  /// Section label above the tag editor in the highlight editor.
  internal static var highlightEditorTagsSection: String { return L10n.tr("Localizable", "highlight_editor_tags_section", fallback: "Tags") }
  /// Title of the highlight editor sheet (trim the excerpt window, edit title and tags).
  internal static var highlightEditorTitle: String { return L10n.tr("Localizable", "highlight_editor_title", fallback: "Edit Highlight") }
  /// Section label above the excerpt trim control in the highlight editor.
  internal static var highlightEditorTrimSection: String { return L10n.tr("Localizable", "highlight_editor_trim_section", fallback: "Excerpt") }
  /// Shown on the shareable quote card when a bookmark has no transcript excerpt
  internal static var highlightExcerptUnavailable: String { return L10n.tr("Localizable", "highlight_excerpt_unavailable", fallback: "No transcript excerpt available") }
  /// Accessibility label for the shareable quote card. %1$@ is the transcript excerpt shown on the card.
  internal static func highlightQuoteCardA11y(_ p1: Any) -> String {
    return L10n.tr("Localizable", "highlight_quote_card_a11y", String(describing: p1), fallback: "Quote card: %1$@")
  }
  /// Name of the quote-card style offered when sharing a highlight (a bookmark enriched with a transcript excerpt)
  internal static var highlightQuoteShareStyle: String { return L10n.tr("Localizable", "highlight_quote_share_style", fallback: "Quote") }
  /// Short spoken confirmation after a highlight is captured hands-free. Keep it to one word if possible.
  internal static var highlightSavedAnnouncement: String { return L10n.tr("Localizable", "highlight_saved_announcement", fallback: "Saved") }
  /// Highlight title style: a self-contained claim that stands alone (Zettelkasten).
  internal static var highlightStyleAtomicNote: String { return L10n.tr("Localizable", "highlight_style_atomic_note", fallback: "Atomic Note") }
  /// Highlight title style: as short and punchy as possible.
  internal static var highlightStylePunchy: String { return L10n.tr("Localizable", "highlight_style_punchy", fallback: "Punchy") }
  /// Highlight title style: phrased as the question the moment answers.
  internal static var highlightStyleQuestionFirst: String { return L10n.tr("Localizable", "highlight_style_question_first", fallback: "Question") }
  /// Highlight title style: no AI title; the quote itself is the note.
  internal static var highlightStyleQuoteOnly: String { return L10n.tr("Localizable", "highlight_style_quote_only", fallback: "Quote Only") }
  /// Highlight title style: the default balanced titling.
  internal static var highlightStyleStandard: String { return L10n.tr("Localizable", "highlight_style_standard", fallback: "Standard") }
  /// Toast action that opens the highlight editor right after a capture.
  internal static var highlightToastEdit: String { return L10n.tr("Localizable", "highlight_toast_edit", fallback: "Edit") }
  /// Prompt to clear the full listening history for the user.
  internal static var historyClearAll: String { return L10n.tr("Localizable", "history_clear_all", fallback: "Clear All") }
  /// Title for the details prompt to confirm the user wants to clear their listening history.
  internal static var historyClearAllDetails: String { return L10n.tr("Localizable", "history_clear_all_details", fallback: "Clear Listening History") }
  /// Message for the details prompt to confirm the user wants to clear their listening history.
  internal static var historyClearAllDetailsMsg: String { return L10n.tr("Localizable", "history_clear_all_details_msg", fallback: "This action cannot be undone.") }
  /// Label shown for hours listened when it's singular, eg: 1 hour listened.
  internal static var hourListened: String { return L10n.tr("Localizable", "hour_listened", fallback: "Hour listened") }
  /// Label shown for hours saved when it's singular, eg: 1 hour saved.
  internal static var hourSaved: String { return L10n.tr("Localizable", "hour_saved", fallback: "Hour saved") }
  /// Label shown for hours listened when it's plural, eg: 1 hours listened.
  internal static var hoursListened: String { return L10n.tr("Localizable", "hours_listened", fallback: "Hours listened") }
  /// Time format to display a set number of hours. '%1$@' is a placeholder for a number of hours, this value will be more than one.
  internal static func hoursPluralFormat(_ p1: Any) -> String {
    return L10n.tr("Localizable", "hours_plural_format", String(describing: p1), fallback: "%1$@ hours")
  }
  /// Label shown for hours saved when it's plural, eg: 1 hours saved.
  internal static var hoursSaved: String { return L10n.tr("Localizable", "hours_saved", fallback: "Hours saved") }
  /// Time format to display 1 hour.
  internal static var hoursSingularFormat: String { return L10n.tr("Localizable", "hours_singular_format", fallback: "1 hour") }
  /// The initial informational text explaining how to upload a file
  internal static var howToUploadExplanation: String { return L10n.tr("Localizable", "how_to_upload_explanation", fallback: "First, open an app that has the audio files you'd like to save") }
  /// The text for copying a file to Pocket Casts
  internal static var howToUploadShareActionImageCenterText: String { return L10n.tr("Localizable", "how_to_upload_share_action_image_center_text", fallback: "Copy to Pocket Casts") }
  /// The text for copying a file to Pocket Casts
  internal static var howToUploadShareActionImageSidesText: String { return L10n.tr("Localizable", "how_to_upload_share_action_image_sides_text", fallback: "Something Else") }
  /// The title for the second instructional image that explains how to upload a file by selecting the share action option for the app
  internal static var howToUploadShareActionInstruction: String { return L10n.tr("Localizable", "how_to_upload_share_action_instruction", fallback: "In the menu tap \"Copy to Pocket Casts\"") }
  /// The text for the button tapped first when uploading a file
  internal static var howToUploadShareMenuImageBackgroundButtonText: String { return L10n.tr("Localizable", "how_to_upload_share_menu_image_background_button_text", fallback: "Audio File") }
  /// The text for a generic menu option tapped first when uploading a file
  internal static var howToUploadShareMenuImageForegroundMenuOptionText: String { return L10n.tr("Localizable", "how_to_upload_share_menu_image_foreground_menu_option_text", fallback: "Menu Option") }
  /// The title for the first instructional image explaining how to upload a file by opening the share menu
  internal static var howToUploadShareMenuInstruction: String { return L10n.tr("Localizable", "how_to_upload_share_menu_instruction", fallback: "Choose to share that file") }
  /// The summary text at the end of the screen explaining how to upload a file
  internal static var howToUploadSummary: String { return L10n.tr("Localizable", "how_to_upload_summary", fallback: "That's it, you're done. Change any details you want, hit save and play!") }
  /// For yealry plans, we show the monthly price. %1$@ is the price. For example: $3.33/month
  internal static func iapProductMonthlyPricingFormat(_ p1: Any) -> String {
    return L10n.tr("Localizable", "iap_product_monthly_pricing_format", String(describing: p1), fallback: "%1$@/month")
  }
  /// For yealry plans, we show the weekly price. %1$@ is the price. For example: $0.70/week
  internal static func iapProductWeeklyPricingFormat(_ p1: Any) -> String {
    return L10n.tr("Localizable", "iap_product_weekly_pricing_format", String(describing: p1), fallback: "%1$@/week")
  }
  /// Import button text
  internal static var `import`: String { return L10n.tr("Localizable", "import", fallback: "Import") }
  /// Step by Step instructions on how to import from the app Apple Podcasts. 
  ///  are new lines and Apple Podcasts is a proper noun and should not be translated.
  internal static var importInstructionsApplePodcastsSteps: String { return L10n.tr("Localizable", "import_instructions_apple_podcasts_steps", fallback: "We can import your podcasts from Apple Podcasts by using the built-in Shortcuts app.\nNote: If you previously deleted the shortcuts app you will be prompted to reinstall it.\n\n1. Tap the Install Shortcut button below.\n2. When prompted tap the Add Shortcut button.\n3. Tap on the Shortcuts tab.\n4. Locate the \"Apple Podcasts to Pocket Casts\" shortcut in the list.\n5. Tap it to start the import process.\n6. Once the shortcut is done running Pocket Casts will reopen and finish the import process.") }
  /// Step by Step instructions on how to import from the app Breaker. 
  ///  are new lines and Breaker is a proper noun and should not be translated.
  internal static var importInstructionsBreaker: String { return L10n.tr("Localizable", "import_instructions_breaker", fallback: "1. Tap the Open Breaker button below\n2. Tap on Settings in the bottom tab bar\n3. Tap on Connection\n4. Tap on Export subscriptions\n5. When the dialog opens locate the Pocket Casts icon, and tap on it") }
  /// Step by Step instructions on how to import from the app Castbox. 
  ///  are new lines and Castbox is a proper noun and should not be translated.
  internal static var importInstructionsCastbox: String { return L10n.tr("Localizable", "import_instructions_castbox", fallback: "1. Tap the Open Castbox button below\n2. Tap the Personal tab\n3. Swipe down until you see the Settings option, then tap on it\n4. Swipe down until you see the OPML Export option, then tap on it\n5. If prompted, tap \"Open in Pocket Casts\"\n6. If the file opens in Safari, tap the Download button\n7. Once the download is complete, tap the download icon in the URL bar\n8. Tap the Downloads item\n9. Tap the castbox_opml file \n10. If needed, tap the Share icon, then open the file using Pocket Casts\n11. When the share dialog opens, locate the Pocket Casts icon, then tap on it") }
  /// Step by Step instructions on how to import from the app Castro. 
  ///  are new lines and Castro is a proper noun and should not be translated.
  internal static var importInstructionsCastro: String { return L10n.tr("Localizable", "import_instructions_castro", fallback: "1. Tap the Open Castro button below\n2. Tap the Cog icon in the top corner of the app\n3. Swipe down until you see the User Data option, then tap on it\n4. Tap the Export Subscriptions item\n5. When the share dialog opens, locate the Pocket Casts icon, then tap on it") }
  /// Button title to import from the given app name,  %1$@ is the name of the app
  internal static func importInstructionsImportFrom(_ p1: Any) -> String {
    return L10n.tr("Localizable", "import_instructions_import_from", String(describing: p1), fallback: "Import from %1$@")
  }
  /// Button title to install a shortcut
  internal static var importInstructionsInstallShortcut: String { return L10n.tr("Localizable", "import_instructions_install_shortcut", fallback: "Install Shortcut") }
  /// Button title to open the given app name,  %1$@ is the name of the app
  internal static func importInstructionsOpenIn(_ p1: Any) -> String {
    return L10n.tr("Localizable", "import_instructions_open_in", String(describing: p1), fallback: "Open %1$@")
  }
  /// Title of an option to import from other apps
  internal static var importInstructionsOtherAppsTitle: String { return L10n.tr("Localizable", "import_instructions_other_apps_title", fallback: "other apps") }
  /// Step by Step instructions on how to import from the app Overcast. 
  ///  are new lines and Overcast is a proper noun and should not be translated.
  internal static var importInstructionsOvercast: String { return L10n.tr("Localizable", "import_instructions_overcast", fallback: "1. Tap the button below to open Overcast\n2. Tap the Cog icon in the top corner of the app\n3. Swipe down until you see Export OPML, then tap on it\n4. When the dialog opens locate the Pocket Casts icon, and tap on it") }
  /// Description for importing opml from URL
  internal static var importOpmlFromUrl: String { return L10n.tr("Localizable", "import_opml_from_url", fallback: "Import your podcasts from an OPML file using a URL") }
  /// Describes the process about how to import podcasts to Pocket Casts. '\
  /// \
  /// ' Is a line break format to separate the description from the following note.
  internal static var importPodcastsDescription: String { return L10n.tr("Localizable", "import_podcasts_description", fallback: "You can import your podcasts subscriptions to Pocket Casts using the widely supported OPML format. Export the file from another app and choose open in Pocket Casts.\n\nNote: You may need to email the OPML file to yourself, long press on the attachment and select Pocket Casts.") }
  /// Describes the process about how to import podcasts to Pocket Casts. '\
  /// \
  /// ' Is a line break format to separate the description from the following note.
  internal static var importPodcastsDescriptionNew: String { return L10n.tr("Localizable", "import_podcasts_description_new", fallback: "You can import your podcasts to Pocket Casts using the widely supported OPML format. Export the file from another app and choose open in Pocket Casts.\n\nNote: You may need to email the OPML file to yourself, long press on the attachment and select Pocket Casts.") }
  /// Title for the section that provides information on how to import podcasts to Pocket Casts
  internal static var importPodcastsTitle: String { return L10n.tr("Localizable", "import_podcasts_title", fallback: "IMPORT TO POCKET CASTS") }
  /// Title of a view explaining the import feature
  internal static var importSubtitle: String { return L10n.tr("Localizable", "import_subtitle", fallback: "Coming from another app? Import your podcasts and get listening. You can always do this later in settings.") }
  /// Title of a view promoting the import feature
  internal static var importTitle: String { return L10n.tr("Localizable", "import_title", fallback: "Bring your\npodcasts with you") }
  /// A common string used throughout the app. Status message informing the user that the episode has been started but not finished.
  internal static var inProgress: String { return L10n.tr("Localizable", "in_progress", fallback: "In Progress") }
  /// Interests screen button title for interests confirmation. The %1$@ argument is the minimum number of interests you need to select. Ex: Select at least 3
  internal static func interestsSelectAtLeast(_ p1: Any) -> String {
    return L10n.tr("Localizable", "interests_select_at_least", String(describing: p1), fallback: "Select at least %1$@")
  }
  /// Interests screen show more categories button text
  internal static var interestsShowMoreCategories: String { return L10n.tr("Localizable", "interests_show_more_categories", fallback: "Show more categories") }
  /// Interests screen subtitle
  internal static var interestsSubtitle: String { return L10n.tr("Localizable", "interests_subtitle", fallback: "Great podcasts, handpicked by real people, are coming your way!") }
  /// Interests screen title
  internal static var interestsTitle: String { return L10n.tr("Localizable", "interests_title", fallback: "Tell us about your favorite topics") }
  /// Title for the hardware keyboard command that closes the player.
  internal static var keycommandClosePlayer: String { return L10n.tr("Localizable", "keycommand_close_player", fallback: "Close Player") }
  /// Title for the hardware keyboard command that decreases the playback speed.
  internal static var keycommandDecreaseSpeed: String { return L10n.tr("Localizable", "keycommand_decrease_speed", fallback: "Decrease Speed") }
  /// Title for the hardware keyboard command that increases the playback speed.
  internal static var keycommandIncreaseSpeed: String { return L10n.tr("Localizable", "keycommand_increase_speed", fallback: "Increase Speed") }
  /// Title for the hardware keyboard command that opens the player.
  internal static var keycommandOpenPlayer: String { return L10n.tr("Localizable", "keycommand_open_player", fallback: "Open Player") }
  /// Title for the hardware keyboard command that toggles play and pause of playback.
  internal static var keycommandPlayPause: String { return L10n.tr("Localizable", "keycommand_play_pause", fallback: "Play/Pause") }
  /// A title shown on a button to open information about the Podcast Ratings feature
  internal static var learnAboutRatings: String { return L10n.tr("Localizable", "learn_about_ratings", fallback: "Learn about ratings") }
  /// Text for a button where you learn more about a feature
  internal static var learnMore: String { return L10n.tr("Localizable", "learn_more", fallback: "Learn More") }
  /// A common string used throughout the app. Often refers to the Listening History screen.
  internal static var listeningHistory: String { return L10n.tr("Localizable", "listening_history", fallback: "Listening History") }
  /// Title for action to remove episode from listening history
  internal static var listeningHistoryRemove: String { return L10n.tr("Localizable", "listening_history_remove", fallback: "Remove from history") }
  /// The empty state view text when searching, and no episodes are found
  internal static var listeningHistorySearchNoEpisodesText: String { return L10n.tr("Localizable", "listening_history_search_no_episodes_text", fallback: "We couldn't find any episode for that search. Try another keyword.") }
  /// The empty state view title when searching, and no episodes are found
  internal static var listeningHistorySearchNoEpisodesTitle: String { return L10n.tr("Localizable", "listening_history_search_no_episodes_title", fallback: "No episodes found") }
  /// Progress indicator informing the user that the selected item is still loading.
  internal static var loading: String { return L10n.tr("Localizable", "loading", fallback: "Loading...") }
  /// Subtitle of the login view
  internal static var loginLandingSubtitle: String { return L10n.tr("Localizable", "login_landing_subtitle", fallback: "Your podcasts, always in sync. Keep your library safe, and enjoy Pocket Casts on web and desktop.") }
  /// Title of the login view
  internal static var loginLandingTitle: String { return L10n.tr("Localizable", "login_landing_title", fallback: "Create your Pocket Casts account") }
  /// Subtitle of the login marketing view
  internal static var loginSubtitle: String { return L10n.tr("Localizable", "login_subtitle", fallback: "Create an account to sync your listening experience across all your devices.") }
  /// Title of the login marketing view
  internal static var loginTitle: String { return L10n.tr("Localizable", "login_title", fallback: "Discover your next favorite podcast") }
  /// Title of an option to see the users logs
  internal static var logs: String { return L10n.tr("Localizable", "logs", fallback: "Logs") }
  /// Message when no email account is configured to be able to send the logs
  internal static var logsNoEmailAccountConfigured: String { return L10n.tr("Localizable", "logs_no_email_account_configured", fallback: "You need to configure an email account on the device in order to send the logs") }
  /// Button title for manage downloads file space usage banner and modal.
  internal static var manageDownloadsAction: String { return L10n.tr("Localizable", "manage_downloads_action", fallback: "Manage downloads") }
  /// Detail for manage downloads file space usage banner and modal. %1$@ is the disk space in Mb/GB that the episodes take
  internal static func manageDownloadsDetail(_ p1: Any) -> String {
    return L10n.tr("Localizable", "manage_downloads_detail", String(describing: p1), fallback: "Save %1$@ - by managing downloaded episodes.")
  }
  /// Title for manage downloads file space usage banner and modal
  internal static var manageDownloadsTitle: String { return L10n.tr("Localizable", "manage_downloads_title", fallback: "Need to free up space?") }
  /// A common string used throughout the app. Prompt to mark the selected item(s) as played.
  internal static var markPlayed: String { return L10n.tr("Localizable", "mark_played", fallback: "Mark as Played") }
  /// A common string used throughout the app. Prompt to mark the selected item(s) as played. Similar to 'Mark as Played' but more concise.
  internal static var markPlayedShort: String { return L10n.tr("Localizable", "mark_played_short", fallback: "Mark Played") }
  /// A common string used throughout the app. Prompt to mark the selected item(s) as not played.
  internal static var markUnplayedShort: String { return L10n.tr("Localizable", "mark_unplayed_short", fallback: "Mark Unplayed") }
  /// An action that the user want to postpone and maybe do later
  internal static var maybeLater: String { return L10n.tr("Localizable", "maybe_later", fallback: "Maybe later") }
  /// Prompt to close the mini player and clear the queue.
  internal static var miniPlayerClose: String { return L10n.tr("Localizable", "mini_player_close", fallback: "Close And Clear Up Next") }
  /// Label shown for minutes listened when it's singular, eg: 1 minute listened.
  internal static var minuteListened: String { return L10n.tr("Localizable", "minute_listened", fallback: "Minute listened") }
  /// Label shown for minutes saved when it's singular, eg: 1 minute saved.
  internal static var minuteSaved: String { return L10n.tr("Localizable", "minute_saved", fallback: "Minute saved") }
  /// Label shown for minutes listened when it's plural, eg: 2 minutes listened.
  internal static var minutesListened: String { return L10n.tr("Localizable", "minutes_listened", fallback: "Minutes listened") }
  /// Label shown for minutes saved when it's plural, eg: 2 minutes saved.
  internal static var minutesSaved: String { return L10n.tr("Localizable", "minutes_saved", fallback: "Minutes saved") }
  /// Basic string used in formats like 'price / month'
  internal static var month: String { return L10n.tr("Localizable", "month", fallback: "month") }
  /// Basic string used to callout payment intervals like yearly vs monthly
  internal static var monthly: String { return L10n.tr("Localizable", "monthly", fallback: "Monthly") }
  /// A title used to a show a list of the most popular podcasts in a category.
  internal static var mostPopular: String { return L10n.tr("Localizable", "most_popular", fallback: "Most Popular") }
  /// A title used to a show a list of the most popular podcasts in a category with the provided name of that category.
  internal static func mostPopularWithName(_ p1: Any) -> String {
    return L10n.tr("Localizable", "most_popular_with_name", String(describing: p1), fallback: "Most Popular in %1$@")
  }
  /// A common string used throughout the app. Prompt to move the selected item(s) to the end of the up next queue.
  internal static var moveToBottom: String { return L10n.tr("Localizable", "move_to_bottom", fallback: "Move to Bottom") }
  /// A common string used throughout the app. Prompt to move the selected item(s) to the top of the up next queue.
  internal static var moveToTop: String { return L10n.tr("Localizable", "move_to_top", fallback: "Move to Top") }
  /// Multi-select status message for adding multiple episodes. Notifies that the selected list exceeds the bulk limit so only the first set up to the limit will be added. '%1$@' is a placeholder for the max amount of episodes to add.
  internal static func multiSelectAddEpisodesMaxFormat(_ p1: Any) -> String {
    return L10n.tr("Localizable", "multi_select_add_episodes_max_format", String(describing: p1), fallback: "Adding max %1$@ episodes.")
  }
  /// Multi-select status message for adding multiple episodes. '%1$@' is a placeholder for the amount of episodes to add.
  internal static func multiSelectAddingEpisodesPluralFormat(_ p1: Any) -> String {
    return L10n.tr("Localizable", "multi_select_adding_episodes_plural_format", String(describing: p1), fallback: "Adding %1$@ episodes.")
  }
  /// Multi-select status message for adding an episode. '%1$@' is a placeholder for the amount of episodes to add.
  internal static var multiSelectAddingEpisodesSingular: String { return L10n.tr("Localizable", "multi_select_adding_episodes_singular", fallback: "Adding 1 episode.") }
  /// Multi-select status message for archiving multiple episodes. '%1$@' is a placeholder for the count of files to be archived (the number will be more than one).
  internal static func multiSelectArchivingEpisodesPluralFormat(_ p1: Any) -> String {
    return L10n.tr("Localizable", "multi_select_archiving_episodes_plural_format", String(describing: p1), fallback: "Archiving %1$@ episodes")
  }
  /// Multi-select status message for archiving one episode.
  internal static var multiSelectArchivingEpisodesSingular: String { return L10n.tr("Localizable", "multi_select_archiving_episodes_singular", fallback: "Archiving 1 episode") }
  /// Message portion of the prompt to delete the selected files on the multi select UI. '%1$@' is a placeholder for the count of files to be deleted (the number will be more than one).
  internal static func multiSelectDeleteFileMessagePlural(_ p1: Any) -> String {
    return L10n.tr("Localizable", "multi_select_delete_file_message_plural", String(describing: p1), fallback: "Are you sure you want to delete %1$@ files?")
  }
  /// Message portion of the prompt to delete a selected file on the multi select UI.
  internal static var multiSelectDeleteFileMessageSingular: String { return L10n.tr("Localizable", "multi_select_delete_file_message_singular", fallback: "Are you sure you want to delete 1 file?") }
  /// Multi-select status message informing the user that downloads have begun. '%1$@' is a placeholder for the count of the selected items being downloaded.
  internal static func multiSelectDownloadingEpisodesFormat(_ p1: Any) -> String {
    return L10n.tr("Localizable", "multi_select_downloading_episodes_format", String(describing: p1), fallback: "Downloading %1$@")
  }
  /// Multi-select status message for marking multiple episodes as played. '%1$@' is a placeholder for the count of episodes to be marked played (the number will be more than one).
  internal static func multiSelectMarkEpisodesPlayedPluralFormat(_ p1: Any) -> String {
    return L10n.tr("Localizable", "multi_select_mark_episodes_played_plural_format", String(describing: p1), fallback: "Marking %1$@ episodes as played.")
  }
  /// Multi-select status message for marking one episode as played.
  internal static var multiSelectMarkEpisodesPlayedSingular: String { return L10n.tr("Localizable", "multi_select_mark_episodes_played_singular", fallback: "Marking 1 episode as played.") }
  /// Multi-select status message for marking multiple episodes as not played. '%1$@' is a placeholder for the count of episodes to be marked not played (the number will be more than one).
  internal static func multiSelectMarkEpisodesUnplayedPluralFormat(_ p1: Any) -> String {
    return L10n.tr("Localizable", "multi_select_mark_episodes_unplayed_plural_format", String(describing: p1), fallback: "Marking %1$@ episodes as unplayed.")
  }
  /// Multi-select status message for marking one episode as not played.
  internal static var multiSelectMarkEpisodesUnplayedSingular: String { return L10n.tr("Localizable", "multi_select_mark_episodes_unplayed_singular", fallback: "Marking 1 episode as unplayed.") }
  /// Multi-select status message informing the user how many episodes have been queued for download. '%1$@' is a placeholder for the count of the selected items be queued for download.
  internal static func multiSelectQueuingEpisodesFormat(_ p1: Any) -> String {
    return L10n.tr("Localizable", "multi_select_queuing_episodes_format", String(describing: p1), fallback: "Queuing %1$@")
  }
  /// Multi-select status message informing the user one episode download is being removed.
  internal static var multiSelectRemoveDownloadSingular: String { return L10n.tr("Localizable", "multi_select_remove_download_singular", fallback: "Removing 1 download.") }
  /// Multi-select status message informing the user how many episodes downloads are being removed. '%1$@' is a placeholder for the count of the selected items be removed for download.
  internal static func multiSelectRemoveDownloadsPluralFormat(_ p1: Any) -> String {
    return L10n.tr("Localizable", "multi_select_remove_downloads_plural_format", String(describing: p1), fallback: "Removing %1$@ downloads.")
  }
  /// Title for the prompt to mark the selected items as not having been played.
  internal static var multiSelectRemoveMarkUnplayed: String { return L10n.tr("Localizable", "multi_select_remove_mark_unplayed", fallback: "Mark as Unplayed") }
  /// Multi-select label indicating the number of selected items. '%1$@' is a placeholder for the number of selected items, this will be more than one.
  internal static func multiSelectSelectedCountPlural(_ p1: Any) -> String {
    return L10n.tr("Localizable", "multi_select_selected_count_plural", String(describing: p1), fallback: "%1$@ SELECTED EPISODES")
  }
  /// Multi-select label indicating that there is one item selected.
  internal static var multiSelectSelectedCountSingular: String { return L10n.tr("Localizable", "multi_select_selected_count_singular", fallback: "1 SELECTED EPISODE") }
  /// Multi-select menu section header. Indicates that the options in this section will appear in the action bar.
  internal static var multiSelectShortcutInActionBar: String { return L10n.tr("Localizable", "multi_select_shortcut_in_action_bar", fallback: "SHORTCUT IN ACTION BAR") }
  /// Title for the prompt to mark the selected items as stared (favorited).
  internal static var multiSelectStar: String { return L10n.tr("Localizable", "multi_select_star", fallback: "Star Episodes") }
  /// Multi-select status message for marking multiple episodes as favorited (starred). '%1$@' is a placeholder for the count of episodes to be starred (the number will be more than one).
  internal static func multiSelectStarringEpisodesPluralFormat(_ p1: Any) -> String {
    return L10n.tr("Localizable", "multi_select_starring_episodes_plural_format", String(describing: p1), fallback: "Starring %1$@ episodes.")
  }
  /// Multi-select status message for marking one episode as favorited (starred).
  internal static var multiSelectStarringEpisodesSingular: String { return L10n.tr("Localizable", "multi_select_starring_episodes_singular", fallback: "Starring 1 episode.") }
  /// Multi-select status message for unarchiving multiple episodes. '%1$@' is a placeholder for the count of files to be unarchived (the number will be more than one).
  internal static func multiSelectUnarchivingEpisodesPluralFormat(_ p1: Any) -> String {
    return L10n.tr("Localizable", "multi_select_unarchiving_episodes_plural_format", String(describing: p1), fallback: "Unarchiving %1$@ episodes.")
  }
  /// Multi-select status message for unarchiving one episode.
  internal static var multiSelectUnarchivingEpisodesSingular: String { return L10n.tr("Localizable", "multi_select_unarchiving_episodes_singular", fallback: "Unarchiving 1 episode") }
  /// Title for the prompt to remove the selected items from being stared (favorited).
  internal static var multiSelectUnstar: String { return L10n.tr("Localizable", "multi_select_unstar", fallback: "Unstar Episodes") }
  /// Multi-select status message for marking multiple episodes as not favorited (un-starred). '%1$@' is a placeholder for the count of episodes to be un-starred (the number will be more than one).
  internal static func multiSelectUnstarringEpisodesPluralFormat(_ p1: Any) -> String {
    return L10n.tr("Localizable", "multi_select_unstarring_episodes_plural_format", String(describing: p1), fallback: "Unstarring %1$@ episodes.")
  }
  /// Multi-select status message for marking one episode as not favorited (un-starred).
  internal static var multiSelectUnstarringEpisodesSingular: String { return L10n.tr("Localizable", "multi_select_unstarring_episodes_singular", fallback: "Unstarring 1 episode") }
  /// Common word used as a title when asking the user to name something
  internal static var name: String { return L10n.tr("Localizable", "name", fallback: "Name") }
  /// Email change form new email address field prompt
  internal static var newEmailAddressPrompt: String { return L10n.tr("Localizable", "new_email_address_prompt", fallback: "New Email Address") }
  /// A common string used throughout the app. References to new episodes.
  internal static var newEpisodes: String { return L10n.tr("Localizable", "new_episodes", fallback: "New episodes") }
  /// Password change form new password field prompt
  internal static var newPasswordPrompt: String { return L10n.tr("Localizable", "new_password_prompt", fallback: "New Password") }
  /// A common string used throughout the app. Prompt to move forward in the flow.
  internal static var next: String { return L10n.tr("Localizable", "next", fallback: "Next") }
  /// A common string used throughout the app. Prompt to move to the next episode.
  internal static var nextEpisode: String { return L10n.tr("Localizable", "next_episode", fallback: "Next Episode") }
  /// A common string used throughout the app. Format used to call out when the associated subscription will be renewed. '%1$@' is a placeholder for a localized date indicating when the renewal will process.
  internal static func nextPaymentFormat(_ p1: Any) -> String {
    return L10n.tr("Localizable", "next_payment_format", String(describing: p1), fallback: "Next payment: %1$@")
  }
  /// Title of a button that takes the user to the headphone settings
  internal static var noBookmarksButtonTitle: String { return L10n.tr("Localizable", "no_bookmarks_button_title", fallback: "Headphone settings") }
  /// Button title shown when the bookmarks feature is locked due to account upgrade status. This will take the user to the upgrade screen.
  internal static var noBookmarksLockedButtonTitle: String { return L10n.tr("Localizable", "no_bookmarks_locked_button_title", fallback: "Get Bookmarks") }
  /// Title shown when the bookmarks feature is locked due to account upgrade status
  internal static var noBookmarksLockedMessage: String { return L10n.tr("Localizable", "no_bookmarks_locked_message", fallback: "You can save timestamps of important moments in an episode.") }
  /// Subtitle of a message explaining how to add new bookmarks
  internal static var noBookmarksMessage: String { return L10n.tr("Localizable", "no_bookmarks_message", fallback: "You can save timestamps of episodes from the actions menu in the player or by configuring an action with your headphones.") }
  /// Title of a message informing the user they don't have any bookmarks yet
  internal static var noBookmarksTitle: String { return L10n.tr("Localizable", "no_bookmarks_title", fallback: "Bookmark that moment") }
  /// A common string used throughout the app. Default 'not set' option mostly used with group settings.
  internal static var `none`: String { return L10n.tr("Localizable", "none", fallback: "None") }
  /// A common string used throughout the app. Informs the user that they are not on WiFi and the action they're about to take will use data. Used for downloads and uploads.
  internal static var notOnWifi: String { return L10n.tr("Localizable", "not_on_wifi", fallback: "You're not on WiFi") }
  /// Settings to control sending of daily reminders notifications
  internal static var notificationsDailyReminders: String { return L10n.tr("Localizable", "notifications_daily_reminders", fallback: "Daily Reminders") }
  /// Fallback body when the resurfaced highlight has no excerpt or title.
  internal static var notificationsHighlightResurfacingBodyFallback: String { return L10n.tr("Localizable", "notifications_highlight_resurfacing_body_fallback", fallback: "Revisit a moment you saved.") }
  /// Title of the notification that resurfaces an old highlight.
  internal static var notificationsHighlightResurfacingTitle: String { return L10n.tr("Localizable", "notifications_highlight_resurfacing_title", fallback: "From your highlights") }
  /// Notification body for new feature Suggested folders
  internal static var notificationsNewFeatureSuggestedFoldersBody: String { return L10n.tr("Localizable", "notifications_new_feature_suggested_folders_body", fallback: "Try Plus and automatically organize your shows with folders.") }
  /// Notification title for new feature Suggested folders
  internal static var notificationsNewFeatureSuggestedFoldersTitle: String { return L10n.tr("Localizable", "notifications_new_feature_suggested_folders_title", fallback: "Your podcasts organized") }
  /// Settings to control sending of new features and tips notifications
  internal static var notificationsNewFeaturesTips: String { return L10n.tr("Localizable", "notifications_new_features_tips", fallback: "New Features & Tips") }
  /// Notifications Off
  internal static var notificationsOff: String { return L10n.tr("Localizable", "notifications_off", fallback: "Notifications Off") }
  /// Notification body for offer upsell message
  internal static var notificationsOffersUpsellBody: String { return L10n.tr("Localizable", "notifications_offers_upsell_body", fallback: "Unlock exclusive features like folders, bookmarks, and more with Plus!") }
  /// Notification title for offer upsell message
  internal static var notificationsOffersUpsellTitle: String { return L10n.tr("Localizable", "notifications_offers_upsell_title", fallback: "Level up your podcast game") }
  /// Notifications On
  internal static var notificationsOn: String { return L10n.tr("Localizable", "notifications_on", fallback: "Notifications On") }
  /// Toast message when notifications are enable for podcast. %1$@ argument is the name of the podcast
  internal static func notificationsOnForPodcast(_ p1: Any) -> String {
    return L10n.tr("Localizable", "notifications_on_for_podcast", String(describing: p1), fallback: "We’ll notify you with new episodes of %1$@")
  }
  /// Notification body for onboarding to filters message
  internal static var notificationsOnboardingFiltersBody: String { return L10n.tr("Localizable", "notifications_onboarding_filters_body", fallback: "Create smart filters to organize your episodes.") }
  /// Notification title for filters onboarding message
  internal static var notificationsOnboardingFiltersTitle: String { return L10n.tr("Localizable", "notifications_onboarding_filters_title", fallback: "Organize your episodes") }
  /// Notification body for import onboarding message
  internal static var notificationsOnboardingImportBody: String { return L10n.tr("Localizable", "notifications_onboarding_import_body", fallback: "Switching from another app? Bring all your favorite shows to Pocket Casts.") }
  /// Notification title for import podcast onboarding message
  internal static var notificationsOnboardingImportTitle: String { return L10n.tr("Localizable", "notifications_onboarding_import_title", fallback: "Easily import your podcasts") }
  /// Subtitle for Notifications opt-in option in the Notifications screen during onboarding
  internal static var notificationsOnboardingNotificationsSubtitle: String { return L10n.tr("Localizable", "notifications_onboarding_notifications_subtitle", fallback: "Receive news, podcast suggestions and more") }
  /// Title for Notifications opt-in option in the Notifications screen during onboarding
  internal static var notificationsOnboardingNotificationsTitle: String { return L10n.tr("Localizable", "notifications_onboarding_notifications_title", fallback: "Receive Notifications") }
  /// Notification body for signup onboarding message
  internal static var notificationsOnboardingSignupBody: String { return L10n.tr("Localizable", "notifications_onboarding_signup_body", fallback: "Create a free account to sync your shows and listen anywhere.") }
  /// Notification title for signup onboarding message
  internal static var notificationsOnboardingSignupTitle: String { return L10n.tr("Localizable", "notifications_onboarding_signup_title", fallback: "Your shows, on any device!") }
  /// Notification body for onboarding to staff picks message
  internal static var notificationsOnboardingStaffPicksBody: String { return L10n.tr("Localizable", "notifications_onboarding_staff_picks_body", fallback: "Perfectly ripe podcasts, picked just for you by real, podcast-loving humans.") }
  /// Notification title for staff picks onboarding message
  internal static var notificationsOnboardingStaffPicksTitle: String { return L10n.tr("Localizable", "notifications_onboarding_staff_picks_title", fallback: "Explore our Staff Picks") }
  /// Notification body for themes onboarding message
  internal static var notificationsOnboardingThemesBody: String { return L10n.tr("Localizable", "notifications_onboarding_themes_body", fallback: "Browse our themes and find the one that suits your style.") }
  /// Notification title for themes onboarding message
  internal static var notificationsOnboardingThemesTitle: String { return L10n.tr("Localizable", "notifications_onboarding_themes_title", fallback: "Time for a new look") }
  /// Notification body for onboarding to upnext message
  internal static var notificationsOnboardingUpnextBody: String { return L10n.tr("Localizable", "notifications_onboarding_upnext_body", fallback: "Build a playback queue and say goodbye to jumping around between episodes.") }
  /// Notification title for upnext onboarding message
  internal static var notificationsOnboardingUpnextTitle: String { return L10n.tr("Localizable", "notifications_onboarding_upnext_title", fallback: "Simplify your queue") }
  /// Notification body for onboarding to upsell message
  internal static var notificationsOnboardingUpsellBody: String { return L10n.tr("Localizable", "notifications_onboarding_upsell_body", fallback: "Unlock exclusive features like folders, bookmarks, and more with Plus!") }
  /// Notification title for upsell onboarding message
  internal static var notificationsOnboardingUpsellTitle: String { return L10n.tr("Localizable", "notifications_onboarding_upsell_title", fallback: "Level up your podcast game") }
  /// Notifications permissions screen action button text
  internal static var notificationsPermissionsAction: String { return L10n.tr("Localizable", "notifications_permissions_action", fallback: "Allow Notifications") }
  /// Notifications permissions screen body text
  internal static var notificationsPermissionsBody: String { return L10n.tr("Localizable", "notifications_permissions_body", fallback: "Notifications are the best way to keep track of new episodes, get recommendations of new shows and tips about Pocket Casts.") }
  /// Notification message to indicate that notification permissions are needed
  internal static var notificationsPermissionsNeedsAction: String { return L10n.tr("Localizable", "notifications_permissions_needs_action", fallback: "Please allow notifications in your device settings") }
  /// Notification button title to open device notification settings
  internal static var notificationsPermissionsOpenSettings: String { return L10n.tr("Localizable", "notifications_permissions_open_settings", fallback: "Open Settings") }
  /// Notifications permissions screen action button text to save preferences for notifications and Newsletter
  internal static var notificationsPermissionsSavePreferences: String { return L10n.tr("Localizable", "notifications_permissions_save_preferences", fallback: "Save Preferences") }
  /// Notifications permissions screen title text
  internal static var notificationsPermissionsTitle: String { return L10n.tr("Localizable", "notifications_permissions_title", fallback: "Stay up to date!") }
  /// Prompt to play the selected item now.
  internal static var notificationsPlayNow: String { return L10n.tr("Localizable", "notifications_play_now", fallback: "Play Now") }
  /// Settings to control sending of pocket casts offers notifications
  internal static var notificationsPocketCastOffers: String { return L10n.tr("Localizable", "notifications_pocket_cast_offers", fallback: "Pocket Casts Offers") }
  /// Notification body for recommendations trending message
  internal static var notificationsRecommendationsTrendingBody: String { return L10n.tr("Localizable", "notifications_recommendations_trending_body", fallback: "Check out what everyone else is listening to this week.") }
  /// Notification title for recommendations trending message
  internal static var notificationsRecommendationsTrendingTitle: String { return L10n.tr("Localizable", "notifications_recommendations_trending_title", fallback: "Trending this week") }
  /// Notification body for recommendations you might like message
  internal static var notificationsRecommendationsYouMightLikeBody: String { return L10n.tr("Localizable", "notifications_recommendations_you_might_like_body", fallback: "Wondering what to listen to next? Check out these shows!") }
  /// Notification title for recommendations you might like message
  internal static var notificationsRecommendationsYouMightLikeTitle: String { return L10n.tr("Localizable", "notifications_recommendations_you_might_like_title", fallback: "New recommendations for you") }
  /// Notification body for reengagement downloads. %1$@ argument is the numbers of episodes downloaded
  internal static func notificationsReengagementDownloadsBody(_ p1: Any) -> String {
    return L10n.tr("Localizable", "notifications_reengagement_downloads_body", String(describing: p1), fallback: "You have %1$@ new episodes downloaded and ready to go!")
  }
  /// Notification title for reengagement downloads
  internal static var notificationsReengagementDownloadsTitle: String { return L10n.tr("Localizable", "notifications_reengagement_downloads_title", fallback: "Catch up offline") }
  /// Notification body for weekly reengagement message
  internal static var notificationsReengagementWeeklyBody: String { return L10n.tr("Localizable", "notifications_reengagement_weekly_body", fallback: "It’s been awhile since you’ve listened. Jump back in and enjoy!") }
  /// Notification title for weekly reengagement message
  internal static var notificationsReengagementWeeklyTitle: String { return L10n.tr("Localizable", "notifications_reengagement_weekly_title", fallback: "We miss you!") }
  /// Settings to control sending of trending and recommendations notifications
  internal static var notificationsTrendingAndRecommendations: String { return L10n.tr("Localizable", "notifications_trending_and_recommendations", fallback: "Trending & Recommendations") }
  /// Notification permission banner action
  internal static var notitificationsPermissionBannerAction: String { return L10n.tr("Localizable", "notitifications_permission_banner_action", fallback: "Go to device settings") }
  /// Notification permission banner message
  internal static var notitificationsPermissionBannerMessage: String { return L10n.tr("Localizable", "notitifications_permission_banner_message", fallback: "To get notifications from Pocket Casts, you’ll need to turn them on in your device settings.") }
  /// Notification permission banner title
  internal static var notitificationsPermissionBannerTitle: String { return L10n.tr("Localizable", "notitifications_permission_banner_title", fallback: "Allow Push Notifications") }
  /// A common string used throughout the app. Refers to the Now Playing tab in the player.
  internal static var nowPlaying: String { return L10n.tr("Localizable", "now_playing", fallback: "Now Playing") }
  /// A common string used throughout the app. Specifically calls out the item that is currently being played. '%1$@' is a placeholder for the item'r name that is being played.
  internal static func nowPlayingItem(_ p1: Any) -> String {
    return L10n.tr("Localizable", "now_playing_item", String(describing: p1), fallback: "Now Playing %1$@")
  }
  /// A common string used throughout the app. Refers to the Now Playing tab in the player. Removes 'Now' to conserve space.
  internal static var nowPlayingShortTitle: String { return L10n.tr("Localizable", "now_playing_short_title", fallback: "Playing") }
  /// Indicates the number of chapters in a podcast episode. %1$@ is the number of chapters.
  internal static func numberOfChapters(_ p1: Any) -> String {
    return L10n.tr("Localizable", "number_of_chapters", String(describing: p1), fallback: "%1$@ chapters")
  }
  /// Indicates the number of hidden chapters in a podcast episode. %1$@ is the number of hidden chapters.
  internal static func numberOfHiddenChapters(_ p1: Any) -> String {
    return L10n.tr("Localizable", "number_of_hidden_chapters", String(describing: p1), fallback: "%1$@ hidden")
  }
  /// A common string used throughout the app. Indicates that the feature is not enabled.
  internal static var off: String { return L10n.tr("Localizable", "off", fallback: "Off") }
  /// A common string used throughout the app. Used as a confirmation or acceptance.
  internal static var ok: String { return L10n.tr("Localizable", "ok", fallback: "OK") }
  /// A common string used throughout the app. Indicates that the feature is enabled.
  internal static var on: String { return L10n.tr("Localizable", "on", fallback: "On") }
  /// A generic label representing the authour of the onboarding quotes describing users of the app
  internal static var onboardingQuoteAuthor: String { return L10n.tr("Localizable", "onboarding_quote_author", fallback: "Pocket Casts user") }
  /// A user review quote shown during onboarding
  internal static var onboardingQuoteBest: String { return L10n.tr("Localizable", "onboarding_quote_best", fallback: "The best podcast app out there. By far") }
  /// A user review quote shown during onboarding alongside an image of the playback effects
  internal static var onboardingQuoteCustomization: String { return L10n.tr("Localizable", "onboarding_quote_customization", fallback: "The amount of customization is insane") }
  /// A user review quote shown during onboarding alongside an image of podcast folders
  internal static var onboardingQuoteFolders: String { return L10n.tr("Localizable", "onboarding_quote_folders", fallback: "Organizing my podcasts by folders is genius") }
  /// Subtitle shown for the recommendations sreen during onboarding
  internal static var onboardingRecommendationsSubtitle: String { return L10n.tr("Localizable", "onboarding_recommendations_subtitle", fallback: "Here are some great shows to start with. Tap to follow, search or import from other apps.") }
  /// Title shown for the recommendations sreen during onboarding
  internal static var onboardingRecommendationsTitle: String { return L10n.tr("Localizable", "onboarding_recommendations_title", fallback: "We hope you love these suggestions!") }
  /// Only on Unmetered Wifi
  internal static var onlyOnUnmeteredWifi: String { return L10n.tr("Localizable", "only_on_unmetered_wifi", fallback: "Only on Unmetered Wifi") }
  /// Only on Unmetered Wifi detail information
  internal static var onlyOnUnmeteredWifiDetails: String { return L10n.tr("Localizable", "only_on_unmetered_wifi_details", fallback: "Turning this off will allow downloads on cellular as well as other metered networks. Check your network settings for more info.") }
  /// A common string used throughout the app. Often used as a toggle to enable a feature only when the user is on Wifi.
  internal static var onlyOnWifi: String { return L10n.tr("Localizable", "only_on_wifi", fallback: "Only On WiFi") }
  /// Message for the dialog box informing the user that the podcast import from the provided OPML file has failed.
  internal static var opmlImportFailedMessage: String { return L10n.tr("Localizable", "opml_import_failed_message", fallback: "Unable to import podcasts from the OPML file you specified. Please check that it's valid") }
  /// Title for the dialog box informing the user that the podcast import from the provided OPML file has failed.
  internal static var opmlImportFailedTitle: String { return L10n.tr("Localizable", "opml_import_failed_title", fallback: "OPML Import Failed") }
  /// Progress message indicating the total number of podcasts imported from an OPML file. '%1$@' serves as a placeholder for the current number of imported podcasts. '%2$@' serves as a placeholder for the total number of podcasts to import.
  internal static func opmlImportProgressFormat(_ p1: Any, _ p2: Any) -> String {
    return L10n.tr("Localizable", "opml_import_progress_format", String(describing: p1), String(describing: p2), fallback: "Importing %1$@ of %2$@")
  }
  /// informing the user that the podcast import from the provided OPML URL succeeded.
  internal static var opmlImportSucceededTitle: String { return L10n.tr("Localizable", "opml_import_succeeded_title", fallback: "OPML Import Succeeded") }
  /// Progress message indicating that the import process of an OPML file is running.
  internal static var opmlImporting: String { return L10n.tr("Localizable", "opml_importing", fallback: "Importing Podcasts...") }
  /// Format used to indicate the current page and total in a custom page control. '%1$@' is a placeholder for the current page. '%2$@' is a placeholder for the total pages.
  internal static func pageControlPageProgressFormat(_ p1: Any, _ p2: Any) -> String {
    return L10n.tr("Localizable", "page_control_page_progress_format", String(describing: p1), String(describing: p2), fallback: "Page %1$@ of %2$@")
  }
  /// A label indicating the number of podcasts the user has subscribed to compared to the total number of podcasts in the bundle. '%1$@' is a placeholder for the number of subscribed podcasts. '%2$@' is a placeholder for the number of podcasts in the bundle.
  internal static func paidPodcastBundledSubscriptions(_ p1: Any, _ p2: Any) -> String {
    return L10n.tr("Localizable", "paid_podcast_bundled_subscriptions", String(describing: p1), String(describing: p2), fallback: "%1$@ / %2$@ SUBSCRIBED")
  }
  /// Option to allow the user to cancel their subscription to a paid podcast feed.
  internal static var paidPodcastCancel: String { return L10n.tr("Localizable", "paid_podcast_cancel", fallback: "Cancel Contribution") }
  /// Message displayed when the user selects to cancel their paid podcast subscription. This message is used when the user is canceling multiple subscriptions. '%1$@' is a placeholder for the last date that the current subscriptions will remain active.
  internal static func paidPodcastCancelMsgPlural(_ p1: Any) -> String {
    return L10n.tr("Localizable", "paid_podcast_cancel_msg_plural", String(describing: p1), fallback: "Supporter status will remain active until %1$@. After that you won't be able to play these podcast anymore.")
  }
  /// Message displayed when the user selects to cancel their paid podcast subscription. This message is used when the podcast allows the user to access episodes that were available to them during their subscription window. '%1$@' is a placeholder for the last date that the current subscription will remain active.
  internal static func paidPodcastCancelMsgRetainAccess(_ p1: Any) -> String {
    return L10n.tr("Localizable", "paid_podcast_cancel_msg_retain_access", String(describing: p1), fallback: "Supporter status will remain active until %1$@. You will only be able to listen to episodes released before this date.")
  }
  /// Message displayed when the user selects to cancel their paid podcast subscription. This message is used when the user is only canceling a singular subscription. '%1$@' is a placeholder for the last date that the current subscription will remain active.
  internal static func paidPodcastCancelMsgSingular(_ p1: Any) -> String {
    return L10n.tr("Localizable", "paid_podcast_cancel_msg_singular", String(describing: p1), fallback: "Supporter status will remain active until %1$@. After that you won't be able to play this podcast anymore.")
  }
  /// A generic error indicating that the app failed to load information about the paid feed.
  internal static var paidPodcastGenericError: String { return L10n.tr("Localizable", "paid_podcast_generic_error", fallback: "Unable to load info") }
  /// Prompt to open settings to adjust settings for a paid feed.
  internal static var paidPodcastManage: String { return L10n.tr("Localizable", "paid_podcast_manage", fallback: "Manage") }
  /// Informational label informing the user when to expect the next episode. '%1$@' is a placeholder for the next upcoming release date.
  internal static func paidPodcastNextEpisodeFormat(_ p1: Any) -> String {
    return L10n.tr("Localizable", "paid_podcast_next_episode_format", String(describing: p1), fallback: "Next episode %1$@")
  }
  /// Informational label informing the user when the latest episode was released. '%1$@' is a placeholder for the latest release date.
  internal static func paidPodcastReleaseFrequencyFormat(_ p1: Any) -> String {
    return L10n.tr("Localizable", "paid_podcast_release_frequency_format", String(describing: p1), fallback: "Released %1$@")
  }
  /// Prompt to get the user to sign in to see updates. This acts as the details message for a section. '
  /// ' is the new line character to cause a line wrap.
  internal static var paidPodcastSigninPromptMsg: String { return L10n.tr("Localizable", "paid_podcast_signin_prompt_msg", fallback: "SIGN IN FOR\nUPDATES") }
  /// Prompt to get the user to sign in to see updates. This acts as the title for a section.
  internal static var paidPodcastSigninPromptTitle: String { return L10n.tr("Localizable", "paid_podcast_signin_prompt_title", fallback: "Sign in for new episodes") }
  /// Format used to indicate the subscription for the paid podcast has ended. '%1$@' is a placeholder for the date that the subscription ended on.
  internal static func paidPodcastSubscriptionEnded(_ p1: Any) -> String {
    return L10n.tr("Localizable", "paid_podcast_subscription_ended", String(describing: p1), fallback: "ENDED: %1$@")
  }
  /// Format used to indicate the subscription for the paid podcast will end on the specified date. '%1$@' is a placeholder for the date that the subscription will end.
  internal static func paidPodcastSubscriptionEnds(_ p1: Any) -> String {
    return L10n.tr("Localizable", "paid_podcast_subscription_ends", String(describing: p1), fallback: "ENDS: %1$@")
  }
  /// A label used to inform the user that the selected podcast feed is for paid supporters only.
  internal static var paidPodcastSupporterOnlyMsg: String { return L10n.tr("Localizable", "paid_podcast_supporter_only_msg", fallback: "Supporter-only feed") }
  /// Prompt to get the user to sign in after selecting to support a podcast while signed out. '%1$@' is a placeholder for the name of the podcast the user has subscribed to.
  internal static func paidPodcastSupporterSigninPrompt(_ p1: Any) -> String {
    return L10n.tr("Localizable", "paid_podcast_supporter_signin_prompt", String(describing: p1), fallback: "Thanks for signing up as a %1$@ supporter. To access your special content, you’ll need to sign in.")
  }
  /// A confirmation message for when a user has selected too unsubscribe and has downloaded files.
  internal static var paidPodcastUnsubscribeMsg: String { return L10n.tr("Localizable", "paid_podcast_unsubscribe_msg", fallback: "Unsubscribing from all these podcasts will delete any downloaded files they have, are you sure?") }
  /// Name of the Patron plan. Do not translate "Patron".
  internal static var patron: String { return L10n.tr("Localizable", "patron", fallback: "Patron") }
  /// Label of a title explaining why to subscribe to Patron.
  internal static var patronCallout: String { return L10n.tr("Localizable", "patron_callout", fallback: "Believe in what we’re doing and want to show your support?") }
  /// Description of the Patron plan. Do not translate "Patron".
  internal static var patronDescription: String { return L10n.tr("Localizable", "patron_description", fallback: "Become a Pocket Casts Patron and help us continue to deliver the best podcasting experience available.") }
  /// Description of a Patron feature that gives user early access to new features.
  internal static var patronFeatureEarlyAccess: String { return L10n.tr("Localizable", "patron_feature_early_access", fallback: "Early access to features") }
  /// Description of a Patron feature that gives user everything in Plus.
  internal static var patronFeatureEverythingInPlus: String { return L10n.tr("Localizable", "patron_feature_everything_in_plus", fallback: "Everything in Plus") }
  /// Description of a Patron feature that gives user a badge on their profile image.
  internal static var patronFeatureProfileBadge: String { return L10n.tr("Localizable", "patron_feature_profile_badge", fallback: "Supporters profile badge") }
  /// Description of a Patron feature that gives users special app icons.
  internal static var patronFeatureProfileIcons: String { return L10n.tr("Localizable", "patron_feature_profile_icons", fallback: "Special Pocket Casts app icons") }
  /// The title of the purchase promo for Patron. Do not translate Patron.
  internal static var patronPurchasePromoTitle: String { return L10n.tr("Localizable", "patron_purchase_promo_title", fallback: "Become a Patron member and unlock all Pocket Casts features") }
  /// Label of a button to subscribe to Patron. Do not translate "Patron".
  internal static var patronSubscribeTo: String { return L10n.tr("Localizable", "patron_subscribe_to", fallback: "Subscribe to Patron") }
  /// Title of a label that thanks the user for their purchase
  internal static var patronThankYou: String { return L10n.tr("Localizable", "patron_thank_you", fallback: "Thank you for your support!") }
  /// Label that instructs the user to hold a button to unlock some gifts
  internal static var patronUnlockInstructions: String { return L10n.tr("Localizable", "patron_unlock_instructions", fallback: "Hold the unlock button below to receive some tokens of our appreciation.") }
  /// A button label that informs the user to release a button press to finish
  internal static var patronUnlockRelease: String { return L10n.tr("Localizable", "patron_unlock_release", fallback: "Release to Unlock") }
  /// The word unlock that is used to highlight the word unlock in the
  internal static var patronUnlockWord: String { return L10n.tr("Localizable", "patron_unlock_word", fallback: "unlock") }
  /// A button label that indicates a feature is being unlocked
  internal static var patronUnlocking: String { return L10n.tr("Localizable", "patron_unlocking", fallback: "Unlocking") }
  /// A common string used throughout the app. Prompt to pause the playback.
  internal static var pause: String { return L10n.tr("Localizable", "pause", fallback: "Pause") }
  /// Paywall header for when the view is presented from the banner ad source
  internal static var paywallDynamicHeadlineBannerAd: String { return L10n.tr("Localizable", "paywall_dynamic_headline_banner_ad", fallback: "Say goodbye to banner ads and more with Pocket Casts Plus") }
  /// Paywall header for when the view is presented from the folder source
  internal static var paywallDynamicHeadlineFolder: String { return L10n.tr("Localizable", "paywall_dynamic_headline_folder", fallback: "Organize your podcasts with Pocket Casts Plus, and more") }
  /// Paywall header for when the view is presented from the icons source
  internal static var paywallDynamicHeadlineIcons: String { return L10n.tr("Localizable", "paywall_dynamic_headline_icons", fallback: "Get exclusive app icons with Pocket Casts Plus, and more") }
  /// Paywall header for when the view is presented from the themes source
  internal static var paywallDynamicHeadlineThemes: String { return L10n.tr("Localizable", "paywall_dynamic_headline_themes", fallback: "Get exclusive themes with Pocket Casts Plus, and more") }
  /// Paywall header for when the view is presented from the Up Next Shuffle source
  internal static var paywallDynamicHeadlineUpNextShuffle: String { return L10n.tr("Localizable", "paywall_dynamic_headline_up_next_shuffle", fallback: "Shuffle your episodes with Pocket Casts Plus, and more") }
  /// Header above the list of episodes a person appears in
  internal static var peopleDetailEpisodesHeader: String { return L10n.tr("Localizable", "people_detail_episodes_header", fallback: "Episodes") }
  /// Placeholder for the search field scoped to one person's transcript segments
  internal static var peopleDetailSearchPlaceholder: String { return L10n.tr("Localizable", "people_detail_search_placeholder", fallback: "Search what they said") }
  /// Empty state message explaining how the People directory gets populated
  internal static var peopleDirectoryEmptyMessage: String { return L10n.tr("Localizable", "people_directory_empty_message", fallback: "Name the speakers in an episode's transcript and they'll show up here, across every show.") }
  /// Empty state title when no transcript speakers have been named yet
  internal static var peopleDirectoryEmptyTitle: String { return L10n.tr("Localizable", "people_directory_empty_title", fallback: "No People Yet") }
  /// Appearance count for a person; '%1$@' is the number of episodes
  internal static func peopleDirectoryEpisodeCountPlural(_ p1: Any) -> String {
    return L10n.tr("Localizable", "people_directory_episode_count_plural", String(describing: p1), fallback: "%1$@ episodes")
  }
  /// Appearance count for a person featured in exactly one episode
  internal static var peopleDirectoryEpisodeCountSingular: String { return L10n.tr("Localizable", "people_directory_episode_count_singular", fallback: "1 episode") }
  /// Title of the People directory screen listing renamed transcript speakers
  internal static var peopleDirectoryTitle: String { return L10n.tr("Localizable", "people_directory_title", fallback: "People") }
  /// Button that follows a person for new-appearance notifications.
  internal static var personFollowButton: String { return L10n.tr("Localizable", "person_follow_button", fallback: "Notify Me") }
  /// Button state when a person is already followed.
  internal static var personFollowingButton: String { return L10n.tr("Localizable", "person_following_button", fallback: "Notifying") }
  /// A common string used throughout the app. Used to reference a phone.
  internal static var phone: String { return L10n.tr("Localizable", "phone", fallback: "Phone") }
  /// A common string used throughout the app. Prompt to start playback.
  internal static var play: String { return L10n.tr("Localizable", "play", fallback: "Play") }
  /// A common string used throughout the app. Prompt to start playback and add the remaining selected items to the queue.
  internal static var playAll: String { return L10n.tr("Localizable", "play_all", fallback: "Play All") }
  /// A common string used throughout the app. Prompt to add the selected item(s) to the end of the queue.
  internal static var playLast: String { return L10n.tr("Localizable", "play_last", fallback: "Play Last") }
  /// Prompt to add an episode to the end of the Up Next queue. Shown in the episode detail bottom sheet.
  internal static var playLastInUpNext: String { return L10n.tr("Localizable", "play_last_in_up_next", fallback: "Play last in Up Next") }
  /// A common string used throughout the app. Prompt to add the selected item(s) to the top of the queue.
  internal static var playNext: String { return L10n.tr("Localizable", "play_next", fallback: "Play Next") }
  /// Prompt to add an episode to the top of the Up Next queue. Shown in the episode detail bottom sheet.
  internal static var playNextInUpNext: String { return L10n.tr("Localizable", "play_next_in_up_next", fallback: "Play next in Up Next") }
  /// A description shown in the Completion Rate screen for Playback 2024
  internal static func playback2024CompletionRateDescription(_ p1: Any, _ p2: Any) -> String {
    return L10n.tr("Localizable", "playback_2024_completion_rate_description", String(describing: p1), String(describing: p2), fallback: "From the %1$@ episodes you started you listened fully to a total of %2$@.")
  }
  /// A title shown in the Completion Rate screen for Playback 2024
  internal static func playback2024CompletionRateTitle(_ p1: Any) -> String {
    return L10n.tr("Localizable", "playback_2024_completion_rate_title", String(describing: p1), fallback: "You completion rate this year was %1$@")
  }
  /// A description of the Playback 2024 feature
  internal static var playback2024Description: String { return L10n.tr("Localizable", "playback_2024_description", fallback: "See your top podcasts, categories, listening stats and more. Share with friends and shout out your favourite creators!") }
  /// Description for the Playback 2024 feature
  internal static var playback2024FeatureDescription: String { return L10n.tr("Localizable", "playback_2024_feature_description", fallback: "See your listening stats, top podcasts, and more.") }
  /// Title for the Playback 2024 feature
  internal static var playback2024FeatureTitle: String { return L10n.tr("Localizable", "playback_2024_feature_title", fallback: "Playback 2024 is here!") }
  /// A description used to indicate the number of days and hours spent listening to podcasts in the last year
  internal static func playback2024ListeningTimeDescription(_ p1: Any) -> String {
    return L10n.tr("Localizable", "playback_2024_listening_time_description", String(describing: p1), fallback: "%1$@ total listening to podcasts")
  }
  /// A description shown on the Longest Episode screen of Playback 2024 with the episode title and podcast title
  internal static func playback2024LongestEpisodeDescription(_ p1: Any, _ p2: Any) -> String {
    return L10n.tr("Localizable", "playback_2024_longest_episode_description", String(describing: p1), String(describing: p2), fallback: "It was \"%1$@\" from \"%2$@\".")
  }
  /// A title shown with the amount of time listened on the Longest Episode screen of Playback 2024
  internal static func playback2024LongestEpisodeTitle(_ p1: Any) -> String {
    return L10n.tr("Localizable", "playback_2024_longest_episode_title", String(describing: p1), fallback: "The longest episode you listened to was %1$@")
  }
  /// A title shown in the button on the upsell screen to check out Pocket Casts Plus
  internal static var playback2024PlusUpsellButtonTitle: String { return L10n.tr("Localizable", "playback_2024_plus_upsell_button_title", fallback: "Check out Pocket Casts Plus") }
  /// A description shown in the upsell screen for Pocket Casts Plus subscription
  internal static var playback2024PlusUpsellDescription: String { return L10n.tr("Localizable", "playback_2024_plus_upsell_description", fallback: "Support Pocket Casts subscribing to Plus and get more stats, plus Premium features like bookmarks, folders or preselect chapters!") }
  /// A title shown in the upsell screen for Pocket Casts Plus subscription
  internal static var playback2024PlusUpsellTitle: String { return L10n.tr("Localizable", "playback_2024_plus_upsell_title", fallback: "There's more!") }
  /// A description shown in Playback 2024 when the user has only made ratings of 1-3/5 for Podcasts
  internal static var playback2024RatingsDescription1To3: String { return L10n.tr("Localizable", "playback_2024_ratings_description_1_to_3", fallback: "Thanks for sharing your feedback with the creator community") }
  /// A description shown in Playback 2024 when the user has made ratings of 4-5/5 for Podcasts
  internal static func playback2024RatingsDescription4To5(_ p1: Any) -> String {
    return L10n.tr("Localizable", "playback_2024_ratings_description_4_to_5", String(describing: p1), fallback: "Wow, so many %1$@ star ratings! Thanks for sharing the love with your favorite creators.")
  }
  /// A description shown in Playback 2024 to describe the new Podcast Ratings feature
  internal static var playback2024RatingsEmptyDescription: String { return L10n.tr("Localizable", "playback_2024_ratings_empty_description", fallback: "Did you know that you can rate shows now? Share the love for your favorite creators and help them get noticed!") }
  /// A title shown in Playback 2024 when the user has not made any ratings.
  internal static var playback2024RatingsEmptyTitle: String { return L10n.tr("Localizable", "playback_2024_ratings_empty_title", fallback: "Oh-oh! No podcast ratings to show you yet.") }
  /// A title shown on the Ratings Playback 2024 screen showing a bar chart of your ratings
  internal static var playback2024RatingsTitle: String { return L10n.tr("Localizable", "playback_2024_ratings_title", fallback: "Let’s see your ratings!") }
  /// You listened to %1$@ episodes for a total of %2$@ of "%3$@".
  internal static func playback2024TopSpotDescription(_ p1: Any, _ p2: Any, _ p3: Any) -> String {
    return L10n.tr("Localizable", "playback_2024_top_spot_description", String(describing: p1), String(describing: p2), String(describing: p3), fallback: "You listened to %1$@ episodes for a total of %2$@ of \"%3$@\".")
  }
  /// A title used for the Playback 2024 Top Podcast screen
  internal static var playback2024TopSpotTitle: String { return L10n.tr("Localizable", "playback_2024_top_spot_title", fallback: "This was your top podcast in 2024") }
  /// Label of the Playback 2024 call to action buton
  internal static var playback2024ViewYear: String { return L10n.tr("Localizable", "playback_2024_view_year", fallback: "View My Playback 2024") }
  /// A title shown on the Year over Year Comparison screen for listening time which stayed the same from 2023 in Playback 2024
  internal static var playback2024YearOverYearCompareDescriptionDown: String { return L10n.tr("Localizable", "playback_2024_year_over_year_compare_description_down", fallback: "Aaaah... there’s a life to be lived, right?") }
  /// A description shown on the Year over Year Comparison screen for listening time which stayed the same from 2023 in Playback 2024
  internal static var playback2024YearOverYearCompareDescriptionSame: String { return L10n.tr("Localizable", "playback_2024_year_over_year_compare_description_same", fallback: "And they say consistency is the key to success... or something like that!") }
  /// A title shown on the Year over Year Comparison screen for listening time which stayed the same from 2023 in Playback 2024
  internal static var playback2024YearOverYearCompareDescriptionUp: String { return L10n.tr("Localizable", "playback_2024_year_over_year_compare_description_up", fallback: "Ready to top it in 2025?") }
  /// A title shown on the Year over Year Comparison screen for a small decrease in listening time from 2023 in Playback 2024
  internal static var playback2024YearOverYearCompareTitleDownLittle: String { return L10n.tr("Localizable", "playback_2024_year_over_year_compare_title_down_little", fallback: "Compared to 2023, your listening time went down a little") }
  /// A title shown on the Year over Year Comparison screen for a large decrease in listening time from 2023 in Playback 2024
  internal static func playback2024YearOverYearCompareTitleDownLot(_ p1: Any) -> String {
    return L10n.tr("Localizable", "playback_2024_year_over_year_compare_title_down_lot", String(describing: p1), fallback: "Compared to 2023, your listening time went down a whopping %1$@")
  }
  /// A title shown on the Year over Year Comparison screen for a large decrease in listening time from 2023 which exceeds 500% in Playback 2024
  internal static func playback2024YearOverYearCompareTitleDownOver500(_ p1: Any) -> String {
    return L10n.tr("Localizable", "playback_2024_year_over_year_compare_title_down_over_500", String(describing: p1), fallback: "Compared to 2023, your listening time went down more than %1$@")
  }
  /// A title shown on the Year over Year Comparison screen for listening time which stayed the same from 2023 in Playback 2024
  internal static var playback2024YearOverYearCompareTitleSame: String { return L10n.tr("Localizable", "playback_2024_year_over_year_compare_title_same", fallback: "Compared to 2023, your listening time stayed pretty consistent") }
  /// A title shown on the Year over Year Comparison screen for a increase more than 500$ in listening time from 2023 in Playback 2024
  internal static func playback2024YearOverYearCompareTitleUpAboveMaximum(_ p1: Any) -> String {
    return L10n.tr("Localizable", "playback_2024_year_over_year_compare_title_up_above_maximum", String(describing: p1), fallback: "Compared to 2023, your listening time went up more than %1$@")
  }
  /// A title shown on the Year over Year Comparison screen for a small increase in listening time from 2023 in Playback 2024
  internal static var playback2024YearOverYearCompareTitleUpLittle: String { return L10n.tr("Localizable", "playback_2024_year_over_year_compare_title_up_little", fallback: "Compared to 2023, your listening time went up a little") }
  /// A title shown on the Year over Year Comparison screen for a large increase in listening time from 2023 in Playback 2024
  internal static func playback2024YearOverYearCompareTitleUpLot(_ p1: Any) -> String {
    return L10n.tr("Localizable", "playback_2024_year_over_year_compare_title_up_lot", String(describing: p1), fallback: "Compared to 2023, your listening time went up a whopping %1$@")
  }
  /// A title shown on the Year over Year Comparison screen for a large increase in listening time from 2023 which exceeds 500% in Playback 2024
  internal static func playback2024YearOverYearCompareTitleUpOver500(_ p1: Any) -> String {
    return L10n.tr("Localizable", "playback_2024_year_over_year_compare_title_up_over_500", String(describing: p1), fallback: "Compared to 2023, your listening time went up more than %1$@")
  }
  /// Playback 2025: Description for the completion rate story: %1$@ represent the started episodes count and %2$@ the finished episodes count
  internal static func playback2025CompletionRateMessage(_ p1: Any, _ p2: Any) -> String {
    return L10n.tr("Localizable", "playback_2025_completion_rate_message", String(describing: p1), String(describing: p2), fallback: "Out of %1$@ episodes started, you finished %2$@. A stronger follow‑through than most gym memberships")
  }
  /// Playback 2025: Title for the completion rate story: %1$@ represent the percentage of completion rate, like 10%
  internal static func playback2025CompletionRateTitle(_ p1: Any) -> String {
    return L10n.tr("Localizable", "playback_2025_completion_rate_title", String(describing: p1), fallback: "Your completion rate was %1$@")
  }
  /// See your top podcasts, categories, listening stats and more. Share with friends and shout out your favourite creators!
  internal static var playback2025Description: String { return L10n.tr("Localizable", "playback_2025_description", fallback: "See your top podcasts, categories, listening stats and more. Share with friends and shout out your favourite creators!") }
  /// Playback 2025: Description for the last story
  internal static var playback2025EndStoryDescription: String { return L10n.tr("Localizable", "playback_2025_end_story_description", fallback: "Share your Playback with friends and show some love to the podcasters who kept you company all year") }
  /// Playback 2025: Title for the last story
  internal static var playback2025EndStoryTitle: String { return L10n.tr("Localizable", "playback_2025_end_story_title", fallback: "Thanks for spending your year with Pocket Casts") }
  /// Message to shown when playback 2025 failed to load
  internal static var playback2025FailedToLoad: String { return L10n.tr("Localizable", "playback_2025_failed_to_load", fallback: "Sorry, we couldn’t load Playback") }
  /// See your listening stats, top podcasts, and more.
  internal static var playback2025FeatureDescription: String { return L10n.tr("Localizable", "playback_2025_feature_description", fallback: "See your listening stats, top podcasts, and more.") }
  /// Playback is here!
  internal static var playback2025FeatureTitle: String { return L10n.tr("Localizable", "playback_2025_feature_title", fallback: "Playback is here!") }
  /// Your year in podcasts, wrapped and ready to relive
  internal static var playback2025IntroMessage: String { return L10n.tr("Localizable", "playback_2025_intro_message", fallback: "Your year in podcasts, wrapped and ready to relive") }
  /// You tuned in to %1$@ podcasts and %2$@ episodes
  internal static func playback2025ListenedToNumbers(_ p1: Any, _ p2: Any) -> String {
    return L10n.tr("Localizable", "playback_2025_listened_to_numbers", String(describing: p1), String(describing: p2), fallback: "You tuned in to %1$@ podcasts and %2$@ episodes")
  }
  /// minutes listened
  internal static var playback2025ListeningTime: String { return L10n.tr("Localizable", "playback_2025_listening_time", fallback: "minutes listened") }
  /// Playback 2025: Footer description for the longest episode story: %1$@ represent the episode title and %2$@ the podcast title
  internal static func playback2025LongestEpisodeFooter(_ p1: Any, _ p2: Any) -> String {
    return L10n.tr("Localizable", "playback_2025_longest_episode_footer", String(describing: p1), String(describing: p2), fallback: "The longest episode was “%1$@” from “%2$@”")
  }
  /// Playback 2025: Description for the longest episode story
  internal static var playback2025LongestEpisodeMessage: String { return L10n.tr("Localizable", "playback_2025_longest_episode_message", fallback: "Hope you stretched first!") }
  /// Playback 2025: Title for the longest episode story: %1$@ represent the time
  internal static func playback2025LongestEpisodeTitle(_ p1: Any) -> String {
    return L10n.tr("Localizable", "playback_2025_longest_episode_title", String(describing: p1), fallback: "Your marathon listen: %1$@")
  }
  /// A description shown in the Playback thanks screen for Pocket Casts Plus subscribers. %1$@ argument is your subscription Tier. Ex:  Your Plus perks unlock extra stats and power features"
  internal static func playback2025PlusThanksDescription(_ p1: Any) -> String {
    return L10n.tr("Localizable", "playback_2025_plus_thanks_description", String(describing: p1), fallback: "Your %1$@ perks unlock extra stats and power features")
  }
  /// A title shown in the Playback thanks screen for Pocket Casts Plus subscription
  internal static var playback2025PlusThanksTitle: String { return L10n.tr("Localizable", "playback_2025_plus_thanks_title", fallback: "Thanks for supporting Pocket Casts!") }
  /// A title shown in the button on the upsell screen to get  Pocket Casts Plus
  internal static var playback2025PlusUpsellButtonTitle: String { return L10n.tr("Localizable", "playback_2025_plus_upsell_button_title", fallback: "Get Pocket Casts Plus") }
  /// A description shown in the upsell screen for Pocket Casts Plus subscription
  internal static var playback2025PlusUpsellDescription: String { return L10n.tr("Localizable", "playback_2025_plus_upsell_description", fallback: "Subscribe to Pocket Casts Plus for extended stats, bookmarks, folders, chapter selection, and more ways to dig into your listening habits") }
  /// A title shown in the upsell screen for Pocket Casts Plus subscription
  internal static var playback2025PlusUpsellTitle: String { return L10n.tr("Localizable", "playback_2025_plus_upsell_title", fallback: "Want the deep dive?") }
  /// Reviews help great shows get found
  internal static var playback2025RatingsDescription1To3: String { return L10n.tr("Localizable", "playback_2025_ratings_description_1_to_3", fallback: "Reviews help great shows get found") }
  /// A title shown on the Ratings Playback 2025 screen showing a bar chart of your ratings
  internal static var playback2025RatingsDescription4To5: String { return L10n.tr("Localizable", "playback_2025_ratings_description_4_to_5", fallback: "Creators everywhere appreciate the love") }
  /// A description shown in Playback 2025 to describe the new Podcast Ratings feature
  internal static var playback2025RatingsEmptyDescription: String { return L10n.tr("Localizable", "playback_2025_ratings_empty_description", fallback: "Help your favorite creators get discovered by sharing what you love") }
  /// A title shown in Playback 2025 when the user has not made any ratings.
  internal static var playback2025RatingsEmptyTitle: String { return L10n.tr("Localizable", "playback_2025_ratings_empty_title", fallback: "No ratings yet, but there's still time!") }
  /// A description shown in Playback 2025 when the user has only made ratings of 1-3/5 for Podcasts
  internal static var playback2025RatingsTitle1To3: String { return L10n.tr("Localizable", "playback_2025_ratings_title_1_to_3", fallback: "Thanks for sharing your feedback.") }
  /// A description shown in Playback 2025 when the user has made ratings of 4-5/5 for Podcasts
  internal static func playback2025RatingsTitle4To5(_ p1: Any) -> String {
    return L10n.tr("Localizable", "playback_2025_ratings_title_4_to_5", String(describing: p1), fallback: "You dropped %1$@-star ratings like confetti")
  }
  /// Playback 2025: Description for the top 5 podcasts story
  internal static var playback2025Top5PodcastsMessage: String { return L10n.tr("Localizable", "playback_2025_top_5_podcasts_message", fallback: "More favorites, more play, more you") }
  /// Playback 2025: Title for the top 5 podcasts story
  internal static var playback2025Top5PodcastsTitle: String { return L10n.tr("Localizable", "playback_2025_top_5_podcasts_title", fallback: "Your other go-to's") }
  /// %1$@ episodes, %2$@.
  /// That’s commitment!
  internal static func playback2025TopSpotDescription(_ p1: Any, _ p2: Any) -> String {
    return L10n.tr("Localizable", "playback_2025_top_spot_description", String(describing: p1), String(describing: p2), fallback: "%1$@ episodes, %2$@.\nThat’s commitment!")
  }
  /// It doesn’t get more “you” than this
  internal static var playback2025TopSpotSubtitle: String { return L10n.tr("Localizable", "playback_2025_top_spot_subtitle", fallback: "It doesn’t get more “you” than this") }
  /// Your top podcast of 2025
  internal static var playback2025TopSpotTitle: String { return L10n.tr("Localizable", "playback_2025_top_spot_title", fallback: "Your top podcast of 2025") }
  /// View My Playback 2025
  internal static var playback2025ViewYear: String { return L10n.tr("Localizable", "playback_2025_view_year", fallback: "View My Playback 2025") }
  /// Playback 2025: Message showed in the Year Over Year Comparison story when the percentage is down compared to the last year.
  internal static var playback2025YearOverYearComparisonDownMessage: String { return L10n.tr("Localizable", "playback_2025_year_over_year_comparison_down_message", fallback: "But hey, quality over quantity") }
  /// Playback 2025: Title showed in the Year Over Year Comparison story when the percentage is down compared to the last year. %1$@ represent a placeholder for the formatted percentage.
  internal static func playback2025YearOverYearComparisonDownTitle(_ p1: Any) -> String {
    return L10n.tr("Localizable", "playback_2025_year_over_year_comparison_down_title", String(describing: p1), fallback: "Your listening dipped %1$@ this year")
  }
  /// Playback 2025: Message showed in the Year Over Year Comparison story when the percentage is more than 500% to the last year. %1$@ represent a placeholder for the formatted percentage.
  internal static func playback2025YearOverYearComparisonHeroMessage(_ p1: Any) -> String {
    return L10n.tr("Localizable", "playback_2025_year_over_year_comparison_hero_message", String(describing: p1), fallback: "You listened %1$@ more this year — welcome to the club")
  }
  /// Playback 2025: Title showed in the Year Over Year Comparison story when the percentage is more than 500% compared to the last year.
  internal static var playback2025YearOverYearComparisonHeroTitle: String { return L10n.tr("Localizable", "playback_2025_year_over_year_comparison_hero_title", fallback: "From zero to hero!") }
  /// Playback 2025: Message showed in the Year Over Year Comparison story when the percentage is the same compared to the last year.
  internal static var playback2025YearOverYearComparisonSameMessage: String { return L10n.tr("Localizable", "playback_2025_year_over_year_comparison_same_message", fallback: "Consistent, dependable, like your coffee shop order") }
  /// Playback 2025: Title showed in the Year Over Year Comparison story when the percentage is the same compared to the last year.
  internal static var playback2025YearOverYearComparisonSameTitle: String { return L10n.tr("Localizable", "playback_2025_year_over_year_comparison_same_title", fallback: "Your 2025 listening held steady") }
  /// Playback 2025: Message showed in the Year Over Year Comparison story when the percentage is up compared to the last year.
  internal static var playback2025YearOverYearComparisonUpMessage: String { return L10n.tr("Localizable", "playback_2025_year_over_year_comparison_up_message", fallback: "More podcasts, more joy") }
  /// Playback 2025: Title showed in the Year Over Year Comparison story when the percentage is up compared to the last year. %1$@ represent a placeholder for the formatted percentage.
  internal static func playback2025YearOverYearComparisonUpTitle(_ p1: Any) -> String {
    return L10n.tr("Localizable", "playback_2025_year_over_year_comparison_up_title", String(describing: p1), fallback: "Compared to 2024, your listening time skyrocketed %1$@")
  }
  /// Playback settings option in the Effects Player panel
  internal static var playbackEffectAllPodcasts: String { return L10n.tr("Localizable", "playback_effect_all_podcasts", fallback: "All podcasts") }
  /// Playback settings option in the Effects Player panel
  internal static var playbackEffectThisPodcast: String { return L10n.tr("Localizable", "playback_effect_this_podcast", fallback: "This podcast") }
  /// One of the options for how aggressive to be in trimming silence. Sets it to max the highest setting.
  internal static var playbackEffectTrimSilenceMax: String { return L10n.tr("Localizable", "playback_effect_trim_silence_max", fallback: "Mad Max") }
  /// One of the options for how aggressive to be in trimming silence. Sets it to medium the middle setting.
  internal static var playbackEffectTrimSilenceMedium: String { return L10n.tr("Localizable", "playback_effect_trim_silence_medium", fallback: "Medium") }
  /// One of the options for how aggressive to be in trimming silence. Sets it to mild the lowest setting.
  internal static var playbackEffectTrimSilenceMild: String { return L10n.tr("Localizable", "playback_effect_trim_silence_mild", fallback: "Mild") }
  /// Used in the player to describe effects you can use to change audio playback. Things like speed, volume, etc.
  internal static var playbackEffects: String { return L10n.tr("Localizable", "playback_effects", fallback: "Playback effects") }
  /// A common string used throughout the app. Generic message informing the user that playback failed.
  internal static var playbackFailed: String { return L10n.tr("Localizable", "playback_failed", fallback: "Playback Failed") }
  /// Message to shown then trying to open playback from deep link but it's not available
  internal static var playbackNotAvailable: String { return L10n.tr("Localizable", "playback_not_available", fallback: "Playback unavailable") }
  /// Label indicating the current value for the playback speed. '%1$@' is a placeholder for the playback speed and 'x' is meant to read as 'times' as in '1.1 times' for '1.1x'
  internal static func playbackSpeed(_ p1: Any) -> String {
    return L10n.tr("Localizable", "playback_speed", String(describing: p1), fallback: "%1$@x")
  }
  /// Accessibility hint text informing the user that the Sleep timer is enabled.
  internal static var playerAccessibilitySleepTimerOn: String { return L10n.tr("Localizable", "player_accessibility_sleep_timer_on", fallback: "Sleep timer on") }
  /// Accessibility hint text informing the user that playback will stop when the current episode ends.
  internal static var playerAccessibilityStopAfterEpisodeOn: String { return L10n.tr("Localizable", "player_accessibility_stop_after_episode_on", fallback: "Stop after this episode on") }
  /// Subtitle for settings indicating this item operates as delete for files.
  internal static var playerActionSubtitleDelete: String { return L10n.tr("Localizable", "player_action_subtitle_delete", fallback: "Shown as Delete for custom episodes") }
  /// Subtitle for settings indicating this item is hidden for files.
  internal static var playerActionSubtitleHidden: String { return L10n.tr("Localizable", "player_action_subtitle_hidden", fallback: "Hidden for custom episodes") }
  /// Header for the available playback effect options.
  internal static var playerActionTitleEffects: String { return L10n.tr("Localizable", "player_action_title_effects", fallback: "Playback Effects") }
  /// Title for the prompt to navigate the user to the files section of the app.
  internal static var playerActionTitleGoToFile: String { return L10n.tr("Localizable", "player_action_title_go_to_file", fallback: "Go to Files") }
  /// Title for the available output device options.
  internal static var playerActionTitleOutputOptions: String { return L10n.tr("Localizable", "player_action_title_output_options", fallback: "Output Device") }
  /// Header for the available timer options for auto-pausing playback.
  internal static var playerActionTitleSleepTimer: String { return L10n.tr("Localizable", "player_action_title_sleep_timer", fallback: "Sleep Timer") }
  /// Title for the player shelf action that stops playback when the current episode ends.
  internal static var playerActionTitleStopAfterEpisode: String { return L10n.tr("Localizable", "player_action_title_stop_after_episode", fallback: "Stop After This Episode") }
  /// Title for the prompt to remove an episode from the favorites.
  internal static var playerActionTitleUnstarEpisode: String { return L10n.tr("Localizable", "player_action_title_unstar_episode", fallback: "Unstar Episode") }
  /// Title for a page where you can rearrange common actions (eg sort/reorder and move the ones you like more to the top)
  internal static var playerActionsRearrangeTitle: String { return L10n.tr("Localizable", "player_actions_rearrange_title", fallback: "Rearrange Actions") }
  /// Confirmation prompt for archiving an episode.
  internal static var playerArchivedConfirmation: String { return L10n.tr("Localizable", "player_archived_confirmation", fallback: "Archive this episode?") }
  /// Message body shown in the confirmation prompt for archiving an episode.
  internal static var playerArchivedConfirmationMessage: String { return L10n.tr("Localizable", "player_archived_confirmation_message", fallback: "Hidden from your feed, not deleted.") }
  /// Accessibility label calling out the current artwork that's being displayed. '%1$@' is a placeholder for either the episode name or the chapter title.
  internal static func playerArtwork(_ p1: Any) -> String {
    return L10n.tr("Localizable", "player_artwork", String(describing: p1), fallback: "%1$@ Artwork")
  }
  /// Information label that includes the current chapter and total chapter count example '1 of 3'. '%1$@' is a placeholder for the current chapter. '%2$@' is a placeholder for the total chapters.
  internal static func playerChapterCount(_ p1: Any, _ p2: Any) -> String {
    return L10n.tr("Localizable", "player_chapter_count", String(describing: p1), String(describing: p2), fallback: "%1$@ of %2$@")
  }
  /// Accessibility label for the player control that rewinds the current playback position by a customizable time.
  internal static var playerDecrementTime: String { return L10n.tr("Localizable", "player_decrement_time", fallback: "Decrement time") }
  /// Detail text explaining that trim silence feature.
  internal static var playerEffectsTrimSilenceDetails: String { return L10n.tr("Localizable", "player_effects_trim_silence_details", fallback: "Reduces the length of an episode by trimming silence in conversations.") }
  /// Detail text celebrating how much time has been saved using the trim silence feature. '%1$@' is a placeholder for the amount of time saved using the feature.
  internal static func playerEffectsTrimSilenceProgress(_ p1: Any) -> String {
    return L10n.tr("Localizable", "player_effects_trim_silence_progress", String(describing: p1), fallback: "In total you've saved %1$@ using this feature.")
  }
  /// Toast message when episode download is cancelled
  internal static var playerEpisodeDownloadCancelled: String { return L10n.tr("Localizable", "player_episode_download_cancelled", fallback: "Episode download cancelled") }
  /// Toast message when episode is queued for download
  internal static var playerEpisodeQueuedForDownload: String { return L10n.tr("Localizable", "player_episode_queued_for_download", fallback: "Episode queued for download") }
  /// Toast message when episode download is removed
  internal static var playerEpisodeWasRemoved: String { return L10n.tr("Localizable", "player_episode_was_removed", fallback: "Episode was removed") }
  /// Generic error used when playback fails but the episode has a downloaded file. Warns the user that playback is failing because the associated file likely has been corrupted.
  internal static var playerErrorCorruptedFile: String { return L10n.tr("Localizable", "player_error_corrupted_file", fallback: "The episode might be corrupted, but you can try to play it again.") }
  /// Generic error used when playback fails because we are unable to access the episode file.
  internal static var playerErrorEpisodeNotAvailable: String { return L10n.tr("Localizable", "player_error_episode_not_available", fallback: "This episode can't be played.") }
  /// Generic error used when playback fails while streaming. Asks the user to verify their internet connection.
  internal static var playerErrorInternetConnection: String { return L10n.tr("Localizable", "player_error_internet_connection", fallback: "Check your Internet connection and try again.") }
  /// Generic error used when no internet connection is available.
  internal static var playerErrorShortNoConnection: String { return L10n.tr("Localizable", "player_error_short_no_connection", fallback: "You’re offline") }
  /// Generic error used when playback fails.
  internal static var playerErrorShortPlaybackError: String { return L10n.tr("Localizable", "player_error_short_playback_error", fallback: "Playback failed, please try again") }
  /// Accessibility label for the player control that fast-forwards the current playback position by a customizable time.
  internal static var playerIncrementTime: String { return L10n.tr("Localizable", "player_increment_time", fallback: "Increment time") }
  /// Confirmation prompt for marking an episode as played.
  internal static var playerMarkAsPlayedConfirmation: String { return L10n.tr("Localizable", "player_mark_as_played_confirmation", fallback: "Mark this episode as played?") }
  /// Message body shown in the confirmation prompt for marking an episode as played.
  internal static var playerMarkAsPlayedConfirmationMessage: String { return L10n.tr("Localizable", "player_mark_as_played_confirmation_message", fallback: "It'll move out of Up Next and into your history.") }
  /// Warning that comes along with selecting to play all. Informs the user that their queue will be cleared.
  internal static var playerOptionsPlayAllMessage: String { return L10n.tr("Localizable", "player_options_play_all_message", fallback: "This will clear your current Up Next queue.") }
  /// Prompt to play a single episode from a multi-select screen.
  internal static var playerOptionsPlayEpisodeSingular: String { return L10n.tr("Localizable", "player_options_play_episode_singular", fallback: "Play 1 Episode") }
  /// Prompt to play a multiple episodes from a multi-select screen. '%1$@' is a placeholder for the number of episodes; the value will be more than one.
  internal static func playerOptionsPlayEpisodesPlural(_ p1: Any) -> String {
    return L10n.tr("Localizable", "player_options_play_episodes_plural", String(describing: p1), fallback: "Play %1$@ Episodes")
  }
  /// Section header for organizing which options will show in the player vs in the menu.
  internal static var playerOptionsShortcutOnPlayer: String { return L10n.tr("Localizable", "player_options_shortcut_on_player", fallback: "SHORTCUT ON PLAYER") }
  /// Accessibility label for the Route selector control. Opens the Apple menu for selecting the playback device such as headphones or a Bluetooth speaker.
  internal static var playerRouteSelection: String { return L10n.tr("Localizable", "player_route_selection", fallback: "Route Selector") }
  /// Header for the share menu where the user selects to share the podcast, episode, or episode at the current position
  internal static var playerShareHeader: String { return L10n.tr("Localizable", "player_share_header", fallback: "SHARE LINK TO") }
  /// Title of a tab in the player that shows the episode description (show notes).
  internal static var playerShowNotesTitle: String { return L10n.tr("Localizable", "player_show_notes_title", fallback: "Details") }
  /// Error title when there is a download error.
  internal static var playerUserEpisodeDownloadError: String { return L10n.tr("Localizable", "player_user_episode_download_error", fallback: "Download Error") }
  /// Error title when there is a playback error.
  internal static var playerUserEpisodePlaybackError: String { return L10n.tr("Localizable", "player_user_episode_playback_error", fallback: "Playback Error") }
  /// Navigation title that appears when adding episodes to a playlist. %@ is the playlist name.
  internal static func playlistAddToTitle(_ p1: Any) -> String {
    return L10n.tr("Localizable", "playlist_add_to_title", String(describing: p1), fallback: "Add to \"%@\"")
  }
  /// Used on the screen to create a new playlist. The description about why the list of filtered episodes is empty. The 
  ///  represent a new line
  internal static var playlistCreateNoEpisodesDescription: String { return L10n.tr("Localizable", "playlist_create_no_episodes_description", fallback: "None of the episodes in your podcasts match these rules.\n\nTry adjusting the rules, or save this playlist for future episodes that might fit.") }
  /// Title for the button used during the Playlist creation
  internal static var playlistCreationCreatePlaylistButton: String { return L10n.tr("Localizable", "playlist_creation_create_playlist_button", fallback: "Create playlist") }
  /// Subtitle for the button used to open the rules during the Playlist creation
  internal static var playlistCreationCreateSmartPlaylistButtonSubtitle: String { return L10n.tr("Localizable", "playlist_creation_create_smart_playlist_button_subtitle", fallback: "Automatically add episodes based on rules.") }
  /// Title for the button used to open the rules during the Playlist creation
  internal static var playlistCreationCreateSmartPlaylistButtonTitle: String { return L10n.tr("Localizable", "playlist_creation_create_smart_playlist_button_title", fallback: "Make into smart playlist") }
  /// Button that adds a new condition row to a rule group
  internal static var playlistCustomAddCondition: String { return L10n.tr("Localizable", "playlist_custom_add_condition", fallback: "Add condition") }
  /// Button that adds a nested rule group inside a rule group
  internal static var playlistCustomAddGroup: String { return L10n.tr("Localizable", "playlist_custom_add_group", fallback: "Add group") }
  /// Shown inside an empty rule group before any conditions are added
  internal static var playlistCustomBuilderEmptyDescription: String { return L10n.tr("Localizable", "playlist_custom_builder_empty_description", fallback: "Add conditions to choose which episodes appear in this playlist.") }
  /// Warning shown when some builder conditions still need a value before saving
  internal static var playlistCustomBuilderIncompleteWarning: String { return L10n.tr("Localizable", "playlist_custom_builder_incomplete_warning", fallback: "Fill in every condition to save this playlist.") }
  /// Button that opens the podcast multi-select for a podcast condition
  internal static var playlistCustomChoosePodcasts: String { return L10n.tr("Localizable", "playlist_custom_choose_podcasts", fallback: "Choose podcasts") }
  /// Menu label for choosing which episode or podcast field a condition applies to
  internal static var playlistCustomConditionField: String { return L10n.tr("Localizable", "playlist_custom_condition_field", fallback: "Field") }
  /// Menu label for choosing a condition's comparison operator
  internal static var playlistCustomConditionOperator: String { return L10n.tr("Localizable", "playlist_custom_condition_operator", fallback: "Operator") }
  /// Subtitle for the custom playlist creation button explaining the feature
  internal static var playlistCustomCreationButtonSubtitle: String { return L10n.tr("Localizable", "playlist_custom_creation_button_subtitle", fallback: "Build advanced rules or write your own query.") }
  /// Title for the button on the new playlist screen that creates a custom (advanced query) playlist
  internal static var playlistCustomCreationButtonTitle: String { return L10n.tr("Localizable", "playlist_custom_creation_button_title", fallback: "Make into custom playlist") }
  /// Episode type choice: a bonus episode
  internal static var playlistCustomEpisodeTypeBonus: String { return L10n.tr("Localizable", "playlist_custom_episode_type_bonus", fallback: "Bonus") }
  /// Episode type choice: a regular full-length episode
  internal static var playlistCustomEpisodeTypeFull: String { return L10n.tr("Localizable", "playlist_custom_episode_type_full", fallback: "Full episode") }
  /// Episode type choice: a trailer episode
  internal static var playlistCustomEpisodeTypeTrailer: String { return L10n.tr("Localizable", "playlist_custom_episode_type_trailer", fallback: "Trailer") }
  /// Validation error: the query is empty
  internal static var playlistCustomErrorEmpty: String { return L10n.tr("Localizable", "playlist_custom_error_empty", fallback: "Enter a query to validate.") }
  /// Validation error: the query failed while running; '%1$@' is the database's error message
  internal static func playlistCustomErrorExecution(_ p1: Any) -> String {
    return L10n.tr("Localizable", "playlist_custom_error_execution", String(describing: p1), fallback: "The query failed to run: %1$@")
  }
  /// Validation error: more than one SQL statement was entered
  internal static var playlistCustomErrorMultipleStatements: String { return L10n.tr("Localizable", "playlist_custom_error_multiple_statements", fallback: "Only a single query is allowed.") }
  /// Validation error: the query tries to modify data
  internal static var playlistCustomErrorNotReadOnly: String { return L10n.tr("Localizable", "playlist_custom_error_not_read_only", fallback: "Only read-only queries are allowed.") }
  /// Validation error: the query contains parameter placeholders which aren't allowed
  internal static var playlistCustomErrorPlaceholders: String { return L10n.tr("Localizable", "playlist_custom_error_placeholders", fallback: "Remove parameter placeholders like '?' or ':name' — custom queries can't take parameters.") }
  /// Validation error for a SQL syntax problem; '%1$@' is the database's error message
  internal static func playlistCustomErrorSyntax(_ p1: Any) -> String {
    return L10n.tr("Localizable", "playlist_custom_error_syntax", String(describing: p1), fallback: "Syntax error: %1$@")
  }
  /// Validation error: the query exceeds the maximum length; '%1$@' is the character limit
  internal static func playlistCustomErrorTooLong(_ p1: Any) -> String {
    return L10n.tr("Localizable", "playlist_custom_error_too_long", String(describing: p1), fallback: "This query is too long. Keep it under %1$@ characters.")
  }
  /// Queryable field: when the episode was added to the library
  internal static var playlistCustomFieldAddedDate: String { return L10n.tr("Localizable", "playlist_custom_field_added_date", fallback: "Added date") }
  /// Queryable field: whether the episode is downloaded
  internal static var playlistCustomFieldDownloadStatus: String { return L10n.tr("Localizable", "playlist_custom_field_download_status", fallback: "Download status") }
  /// Queryable field: the episode's duration in seconds
  internal static var playlistCustomFieldDuration: String { return L10n.tr("Localizable", "playlist_custom_field_duration", fallback: "Duration (seconds)") }
  /// Queryable field: the episode's show notes description
  internal static var playlistCustomFieldEpisodeDescription: String { return L10n.tr("Localizable", "playlist_custom_field_episode_description", fallback: "Episode description") }
  /// Queryable field: the episode's number within its season
  internal static var playlistCustomFieldEpisodeNumber: String { return L10n.tr("Localizable", "playlist_custom_field_episode_number", fallback: "Episode number") }
  /// Queryable field: the episode's title
  internal static var playlistCustomFieldEpisodeTitle: String { return L10n.tr("Localizable", "playlist_custom_field_episode_title", fallback: "Episode title") }
  /// Queryable field: the episode's type (full episode, trailer or bonus)
  internal static var playlistCustomFieldEpisodeType: String { return L10n.tr("Localizable", "playlist_custom_field_episode_type", fallback: "Episode type") }
  /// Queryable field: the episode's file size in bytes
  internal static var playlistCustomFieldFileSize: String { return L10n.tr("Localizable", "playlist_custom_field_file_size", fallback: "File size (bytes)") }
  /// Queryable field: when the episode was last played
  internal static var playlistCustomFieldLastPlayedDate: String { return L10n.tr("Localizable", "playlist_custom_field_last_played_date", fallback: "Last played date") }
  /// Queryable field: whether the episode is audio or video
  internal static var playlistCustomFieldMediaType: String { return L10n.tr("Localizable", "playlist_custom_field_media_type", fallback: "Media type") }
  /// Queryable field: how far the episode has been played, in seconds
  internal static var playlistCustomFieldPlayedUpTo: String { return L10n.tr("Localizable", "playlist_custom_field_played_up_to", fallback: "Played up to (seconds)") }
  /// Queryable field: whether the episode is unplayed, in progress or played
  internal static var playlistCustomFieldPlayingStatus: String { return L10n.tr("Localizable", "playlist_custom_field_playing_status", fallback: "Play status") }
  /// Queryable field: the podcast the episode belongs to
  internal static var playlistCustomFieldPodcast: String { return L10n.tr("Localizable", "playlist_custom_field_podcast", fallback: "Podcast") }
  /// Queryable field: whether the episode's podcast is one the user follows
  internal static var playlistCustomFieldPodcastSubscribed: String { return L10n.tr("Localizable", "playlist_custom_field_podcast_subscribed", fallback: "Following podcast") }
  /// Queryable field: the podcast's title
  internal static var playlistCustomFieldPodcastTitle: String { return L10n.tr("Localizable", "playlist_custom_field_podcast_title", fallback: "Podcast title") }
  /// Queryable field: percentage of the episode already played
  internal static var playlistCustomFieldProgressPercent: String { return L10n.tr("Localizable", "playlist_custom_field_progress_percent", fallback: "Progress (%)") }
  /// Queryable field: when the episode was published
  internal static var playlistCustomFieldPublishedDate: String { return L10n.tr("Localizable", "playlist_custom_field_published_date", fallback: "Published date") }
  /// Queryable field: the episode's season number
  internal static var playlistCustomFieldSeasonNumber: String { return L10n.tr("Localizable", "playlist_custom_field_season_number", fallback: "Season number") }
  /// Queryable field: full-text search over the episode's transcript
  internal static var playlistCustomFieldTranscriptMentions: String { return L10n.tr("Localizable", "playlist_custom_field_transcript_mentions", fallback: "Transcript mentions") }
  /// Footnote under the transcript mentions condition explaining it only sees episodes whose transcripts are indexed on this device
  internal static var playlistCustomFieldTranscriptMentionsFootnote: String { return L10n.tr("Localizable", "playlist_custom_field_transcript_mentions_footnote", fallback: "Only episodes with a searchable transcript can match.") }
  /// Segmented option for a rule group where every rule must match
  internal static var playlistCustomGroupAll: String { return L10n.tr("Localizable", "playlist_custom_group_all", fallback: "All") }
  /// Segmented option for a rule group where any rule may match
  internal static var playlistCustomGroupAny: String { return L10n.tr("Localizable", "playlist_custom_group_any", fallback: "Any") }
  /// Caption next to a rule group set to require every rule to match
  internal static var playlistCustomGroupMatchAllDescription: String { return L10n.tr("Localizable", "playlist_custom_group_match_all_description", fallback: "of the following are true") }
  /// Caption next to a rule group set to require any rule to match
  internal static var playlistCustomGroupMatchAnyDescription: String { return L10n.tr("Localizable", "playlist_custom_group_match_any_description", fallback: "of the following is true") }
  /// Number of matching episodes for the current query; '%1$@' is the count
  internal static func playlistCustomMatchCountPlural(_ p1: Any) -> String {
    return L10n.tr("Localizable", "playlist_custom_match_count_plural", String(describing: p1), fallback: "%1$@ matching episodes")
  }
  /// One matching episode for the current query; '%1$@' is the number 1 formatted
  internal static func playlistCustomMatchCountSingular(_ p1: Any) -> String {
    return L10n.tr("Localizable", "playlist_custom_match_count_singular", String(describing: p1), fallback: "%1$@ matching episode")
  }
  /// Segmented control option showing the visual rule builder in the custom playlist editor
  internal static var playlistCustomModeBuilder: String { return L10n.tr("Localizable", "playlist_custom_mode_builder", fallback: "Builder") }
  /// Segmented control option showing the SQL editor in the custom playlist editor
  internal static var playlistCustomModeSql: String { return L10n.tr("Localizable", "playlist_custom_mode_sql", fallback: "SQL") }
  /// Footer in the custom playlist editor explaining that custom playlists stay on this device
  internal static var playlistCustomOnlyOnDeviceFooter: String { return L10n.tr("Localizable", "playlist_custom_only_on_device_footer", fallback: "Only on this device. Custom playlists don't sync to your other devices.") }
  /// Condition operator: date field is after the value
  internal static var playlistCustomOpAfter: String { return L10n.tr("Localizable", "playlist_custom_op_after", fallback: "is after") }
  /// Condition operator: numeric field is greater than or equal to the value
  internal static var playlistCustomOpAtLeast: String { return L10n.tr("Localizable", "playlist_custom_op_at_least", fallback: "is at least") }
  /// Condition operator: numeric field is less than or equal to the value
  internal static var playlistCustomOpAtMost: String { return L10n.tr("Localizable", "playlist_custom_op_at_most", fallback: "is at most") }
  /// Condition operator: date field is before the value
  internal static var playlistCustomOpBefore: String { return L10n.tr("Localizable", "playlist_custom_op_before", fallback: "is before") }
  /// Condition operator: field is between two values
  internal static var playlistCustomOpBetween: String { return L10n.tr("Localizable", "playlist_custom_op_between", fallback: "is between") }
  /// Condition operator: text field contains the value
  internal static var playlistCustomOpContains: String { return L10n.tr("Localizable", "playlist_custom_op_contains", fallback: "contains") }
  /// Condition operator: text field ends with the value
  internal static var playlistCustomOpEndsWith: String { return L10n.tr("Localizable", "playlist_custom_op_ends_with", fallback: "ends with") }
  /// Condition operator: field equals the value
  internal static var playlistCustomOpEquals: String { return L10n.tr("Localizable", "playlist_custom_op_equals", fallback: "is") }
  /// Condition operator: numeric field is greater than the value
  internal static var playlistCustomOpGreaterThan: String { return L10n.tr("Localizable", "playlist_custom_op_greater_than", fallback: "is more than") }
  /// Condition operator: field matches any of the chosen values
  internal static var playlistCustomOpIn: String { return L10n.tr("Localizable", "playlist_custom_op_in", fallback: "is any of") }
  /// Condition operator: date field falls within the last N days; the day count input follows this label
  internal static var playlistCustomOpInLastDays: String { return L10n.tr("Localizable", "playlist_custom_op_in_last_days", fallback: "is in the last") }
  /// Condition operator: field has no value
  internal static var playlistCustomOpIsNotSet: String { return L10n.tr("Localizable", "playlist_custom_op_is_not_set", fallback: "is not set") }
  /// Condition operator: field has any value at all
  internal static var playlistCustomOpIsSet: String { return L10n.tr("Localizable", "playlist_custom_op_is_set", fallback: "is set") }
  /// Condition operator: numeric field is less than the value
  internal static var playlistCustomOpLessThan: String { return L10n.tr("Localizable", "playlist_custom_op_less_than", fallback: "is less than") }
  /// Condition operator: the episode's transcript contains the phrase
  internal static var playlistCustomOpMentions: String { return L10n.tr("Localizable", "playlist_custom_op_mentions", fallback: "mentions") }
  /// Condition operator: text field does not contain the value
  internal static var playlistCustomOpNotContains: String { return L10n.tr("Localizable", "playlist_custom_op_not_contains", fallback: "doesn't contain") }
  /// Condition operator: field does not equal the value
  internal static var playlistCustomOpNotEquals: String { return L10n.tr("Localizable", "playlist_custom_op_not_equals", fallback: "is not") }
  /// Condition operator: field matches none of the chosen values
  internal static var playlistCustomOpNotIn: String { return L10n.tr("Localizable", "playlist_custom_op_not_in", fallback: "is none of") }
  /// Condition operator: text field starts with the value
  internal static var playlistCustomOpStartsWith: String { return L10n.tr("Localizable", "playlist_custom_op_starts_with", fallback: "starts with") }
  /// Number of podcasts chosen for a podcast condition; '%1$@' is the count
  internal static func playlistCustomPodcastsSelected(_ p1: Any) -> String {
    return L10n.tr("Localizable", "playlist_custom_podcasts_selected", String(describing: p1), fallback: "%1$@ selected")
  }
  /// Accessibility label for the button that removes a rule or rule group
  internal static var playlistCustomRemoveRule: String { return L10n.tr("Localizable", "playlist_custom_remove_rule", fallback: "Remove rule") }
  /// Navigation bar save button in the custom playlist editor when editing an existing playlist
  internal static var playlistCustomSave: String { return L10n.tr("Localizable", "playlist_custom_save", fallback: "Save") }
  /// Save button at the bottom of the custom playlist editor when creating a new playlist
  internal static var playlistCustomSaveButton: String { return L10n.tr("Localizable", "playlist_custom_save_button", fallback: "Create custom playlist") }
  /// Intro text of the schema reference sheet listing queryable fields
  internal static var playlistCustomSchemaDescription: String { return L10n.tr("Localizable", "playlist_custom_schema_description", fallback: "Query these fields using the episode and podcast table aliases. Values are compared with standard SQL operators.") }
  /// Button that opens a reference sheet listing the queryable fields
  internal static var playlistCustomSchemaReference: String { return L10n.tr("Localizable", "playlist_custom_schema_reference", fallback: "Schema reference") }
  /// Schema reference type label for true/false fields
  internal static var playlistCustomSchemaTypeBoolean: String { return L10n.tr("Localizable", "playlist_custom_schema_type_boolean", fallback: "Boolean") }
  /// Schema reference type label for date fields
  internal static var playlistCustomSchemaTypeDate: String { return L10n.tr("Localizable", "playlist_custom_schema_type_date", fallback: "Date") }
  /// Schema reference type label for fields with a fixed set of values
  internal static var playlistCustomSchemaTypeEnum: String { return L10n.tr("Localizable", "playlist_custom_schema_type_enum", fallback: "Choice") }
  /// Schema reference type label for numeric fields
  internal static var playlistCustomSchemaTypeNumber: String { return L10n.tr("Localizable", "playlist_custom_schema_type_number", fallback: "Number") }
  /// Schema reference type label for the podcast picker field
  internal static var playlistCustomSchemaTypePodcast: String { return L10n.tr("Localizable", "playlist_custom_schema_type_podcast", fallback: "Podcasts") }
  /// Schema reference type label for text fields
  internal static var playlistCustomSchemaTypeText: String { return L10n.tr("Localizable", "playlist_custom_schema_type_text", fallback: "Text") }
  /// Schema reference type label for the transcript full-text search field
  internal static var playlistCustomSchemaTypeTranscript: String { return L10n.tr("Localizable", "playlist_custom_schema_type_transcript", fallback: "Transcript") }
  /// Hint explaining what to type in the SQL editor
  internal static var playlistCustomSqlHint: String { return L10n.tr("Localizable", "playlist_custom_sql_hint", fallback: "Write the conditions of a query over the episode and podcast tables. The playlist updates automatically as your library changes.") }
  /// Button that pre-fills the SQL editor from the playlist's current smart rules
  internal static var playlistCustomStartFromRules: String { return L10n.tr("Localizable", "playlist_custom_start_from_rules", fallback: "Start from current rules") }
  /// Button that checks the SQL query for errors
  internal static var playlistCustomValidateButton: String { return L10n.tr("Localizable", "playlist_custom_validate_button", fallback: "Validate") }
  /// Shown while the SQL query is being checked
  internal static var playlistCustomValidating: String { return L10n.tr("Localizable", "playlist_custom_validating", fallback: "Validating…") }
  /// Hint under the SQL editor before the query has been validated
  internal static var playlistCustomValidationNeeded: String { return L10n.tr("Localizable", "playlist_custom_validation_needed", fallback: "Validate your query to enable saving.") }
  /// Label for a condition's date picker
  internal static var playlistCustomValueDate: String { return L10n.tr("Localizable", "playlist_custom_value_date", fallback: "Date") }
  /// Placeholder for the number-of-days input of an 'in the last N days' condition
  internal static var playlistCustomValueDays: String { return L10n.tr("Localizable", "playlist_custom_value_days", fallback: "Days") }
  /// Suffix label after the number-of-days input, completing 'in the last N days'
  internal static var playlistCustomValueDaysSuffix: String { return L10n.tr("Localizable", "playlist_custom_value_days_suffix", fallback: "days") }
  /// Label for the end date of a date range condition
  internal static var playlistCustomValueEndDate: String { return L10n.tr("Localizable", "playlist_custom_value_end_date", fallback: "To") }
  /// Placeholder for the upper bound of a numeric between condition
  internal static var playlistCustomValueMax: String { return L10n.tr("Localizable", "playlist_custom_value_max", fallback: "Max") }
  /// Placeholder for the lower bound of a numeric between condition
  internal static var playlistCustomValueMin: String { return L10n.tr("Localizable", "playlist_custom_value_min", fallback: "Min") }
  /// Placeholder for a condition's value input
  internal static var playlistCustomValuePlaceholder: String { return L10n.tr("Localizable", "playlist_custom_value_placeholder", fallback: "Value") }
  /// Label for the start date of a date range condition
  internal static var playlistCustomValueStartDate: String { return L10n.tr("Localizable", "playlist_custom_value_start_date", fallback: "From") }
  /// Playlist detail description. %1$@ represent the number of total episodes. %2$@ represents the total time.
  internal static func playlistDetailDescription(_ p1: Any, _ p2: Any) -> String {
    return L10n.tr("Localizable", "playlist_detail_description", String(describing: p1), String(describing: p2), fallback: "%1$@ episodes • %2$@")
  }
  /// Playlist detail description when the playlist has one single episode. %1$@ represent the total time.
  internal static func playlistDetailDescriptionOneEpisode(_ p1: Any) -> String {
    return L10n.tr("Localizable", "playlist_detail_description_one_episode", String(describing: p1), fallback: "1 episode • %1$@")
  }
  /// Navigation title shown after adding a single episode to a playlist. %@ is the playlist name.
  internal static func playlistEpisodeAddedTitle(_ p1: Any) -> String {
    return L10n.tr("Localizable", "playlist_episode_added_title", String(describing: p1), fallback: "1 episode added to \"%@\"")
  }
  /// Navigation title shown after adding multiple episodes to a playlist. %1$@ is the episode count. %2$@ is the playlist name.
  internal static func playlistEpisodesAddedTitle(_ p1: Any, _ p2: Any) -> String {
    return L10n.tr("Localizable", "playlist_episodes_added_title", String(describing: p1), String(describing: p2), fallback: "%1$@ episodes added to \"%2$@\"")
  }
  /// Toast message when an episode is added to multiple playlists from the playlists chooser. %1$@ is the number of playlists added to.
  internal static func playlistEpisodesAddedToMultiplePlaylists(_ p1: Any) -> String {
    return L10n.tr("Localizable", "playlist_episodes_added_to_multiple_playlists", String(describing: p1), fallback: "Added to %1$@ playlists")
  }
  /// Toast message when an episode is added to a single playlist from the playlists chooser. %1$@ is the playlist name.
  internal static func playlistEpisodesAddedToSinglePlaylist(_ p1: Any) -> String {
    return L10n.tr("Localizable", "playlist_episodes_added_to_single_playlist", String(describing: p1), fallback: "Added to %1$@")
  }
  /// Playlist cell subtitle. It appears in the manual playlist add episode from podcast detail or player
  internal static func playlistEpisodesCount(_ p1: Any) -> String {
    return L10n.tr("Localizable", "playlist_episodes_count", String(describing: p1), fallback: "%1$@ episodes")
  }
  /// Toast message when the playlist is full
  internal static var playlistManualAddEpisodeFullPlaylistToast: String { return L10n.tr("Localizable", "playlist_manual_add_episode_full_playlist_toast", fallback: "This playlist is full. Remove a few episodes or start a new one.") }
  /// Manual Playlist: header button title to add new episodes to the playlist
  internal static var playlistManualAddEpisodes: String { return L10n.tr("Localizable", "playlist_manual_add_episodes", fallback: "Add episodes") }
  /// Toast message when adding episodes to a playlist that would exceed the 1000 episode limit
  internal static var playlistManualAddEpisodesAlmostFullToast: String { return L10n.tr("Localizable", "playlist_manual_add_episodes_almost_full_toast", fallback: "Playlist is almost full. Try adding fewer episodes.") }
  /// Toast message when trying to add files (user episodes) to a playlist
  internal static var playlistManualAddFilesNotSupportedToast: String { return L10n.tr("Localizable", "playlist_manual_add_files_not_supported_toast", fallback: "Playlists can only contain podcast episodes.") }
  /// Toast message when trying to add more than the max number of episodes to a playlist at once, or creating a new playlist with more than the max. '%1$@' is the max episode count, localized for the user's locale.
  internal static func playlistManualAddTooManyEpisodesToast(_ p1: Any) -> String {
    return L10n.tr("Localizable", "playlist_manual_add_too_many_episodes_toast", String(describing: p1), fallback: "Playlists can only contain up to %1$@ episodes.")
  }
  /// Text of the placeholder used in the manual playlist detail screen when one episode is archived.
  internal static var playlistManualArchivedEpisodePlaceholder: String { return L10n.tr("Localizable", "playlist_manual_archived_episode_placeholder", fallback: "Your episode in this playlist has been archived") }
  /// Text of the placeholder used in the manual playlist detail screen when all episodes are archived. '%1$@' represents the number of archived episodes
  internal static func playlistManualArchivedEpisodesPlaceholder(_ p1: Any) -> String {
    return L10n.tr("Localizable", "playlist_manual_archived_episodes_placeholder", String(describing: p1), fallback: "All %1$@ episodes of this playlist have been archived")
  }
  /// Manual Playlist: title when no episodes are added and there are nosubscribed podcasts
  internal static var playlistManualBrowseShowsTitle: String { return L10n.tr("Localizable", "playlist_manual_browse_shows_title", fallback: "Browse podcasts") }
  /// Toast message displayed in case something goes wrong with the manual creation
  internal static var playlistManualCreateErrorMessage: String { return L10n.tr("Localizable", "playlist_manual_create_error_message", fallback: "Sorry, something went wrong while creating your playlist.") }
  /// Manual Playlist: empty state subtitle when no episodes are added and there are nosubscribed podcasts
  internal static var playlistManualEmptyStateSubtitleNoPodcasts: String { return L10n.tr("Localizable", "playlist_manual_empty_state_subtitle_no_podcasts", fallback: "Swipe left on an episode to add it your playlist.") }
  /// Manual Playlist: empty state title when no episodes are added
  internal static var playlistManualEmptyStateTitle: String { return L10n.tr("Localizable", "playlist_manual_empty_state_title", fallback: "Start building your playlist") }
  /// Manual Playlist: empty state title when no episodes are added and there are nosubscribed podcasts
  internal static var playlistManualEmptyStateTitleNoPodcasts: String { return L10n.tr("Localizable", "playlist_manual_empty_state_title_no_podcasts", fallback: "Add episodes to your playlist") }
  /// Manual Playlist: when adding an episode to a manual playlist. It can appear as CTA or title
  internal static var playlistManualEpisodeAddToPlaylist: String { return L10n.tr("Localizable", "playlist_manual_episode_add_to_playlist", fallback: "Add to playlist") }
  /// Manual Playlist: manual episodes order option that appears when showing the options sheet
  internal static var playlistManualEpisodesOrderOption: String { return L10n.tr("Localizable", "playlist_manual_episodes_order_option", fallback: "Reorder episodes") }
  /// Toast message displayed when a user tries to play all archived episodes in a manual playlist
  internal static var playlistManualPlayAllEmptyList: String { return L10n.tr("Localizable", "playlist_manual_play_all_empty_list", fallback: "All episodes archived. Add or unarchive to play.") }
  /// Menu prompt to open the Playlist options. Also used for the title of the playlist options screen.
  internal static var playlistOptions: String { return L10n.tr("Localizable", "playlist_options", fallback: "Playlist Options") }
  /// Picker option showed when tapping Play all
  internal static var playlistPlayAllOptionSaveQueue: String { return L10n.tr("Localizable", "playlist_play_all_option_save_queue", fallback: "Save current queue") }
  /// Picker message showed when tapping Play all
  internal static var playlistPlayAllPickerMessage: String { return L10n.tr("Localizable", "playlist_play_all_picker_message", fallback: "Your current Up Next will be replaced when you play this playlist. Save it first to keep it.") }
  /// Picker title showed when tapping Play all
  internal static var playlistPlayAllPickerTitle: String { return L10n.tr("Localizable", "playlist_play_all_picker_title", fallback: "Save your Up Next queue?") }
  /// Picker message showed when tapping replace after showing the first Play all picker
  internal static var playlistPlayAllReplacePickerMessage: String { return L10n.tr("Localizable", "playlist_play_all_replace_picker_message", fallback: "This will clear your current Up Next queue and start playing this playlist.") }
  /// Picker title showed when tapping replace after showing the first Play all picker
  internal static var playlistPlayAllReplacePickerTitle: String { return L10n.tr("Localizable", "playlist_play_all_replace_picker_title", fallback: "Replace current Up Next?") }
  /// Play all sheet button title
  internal static var playlistPlayAllSheetButtonTitle: String { return L10n.tr("Localizable", "playlist_play_all_sheet_button_title", fallback: "Replace and play") }
  /// Play all sheet description
  internal static var playlistPlayAllSheetDescription: String { return L10n.tr("Localizable", "playlist_play_all_sheet_description", fallback: "Playing this will replace your current Up Next.") }
  /// Play all sheet title
  internal static var playlistPlayAllSheetTitle: String { return L10n.tr("Localizable", "playlist_play_all_sheet_title", fallback: "Replace your Up Next?") }
  /// Play all sheet toggle description
  internal static var playlistPlayAllSheetToggle: String { return L10n.tr("Localizable", "playlist_play_all_sheet_toggle", fallback: "Save your current Up Next queue as a playlist.") }
  /// Toast message displayed when the current Up Next is saved
  internal static var playlistPlayAllUpNextSaved: String { return L10n.tr("Localizable", "playlist_play_all_up_next_saved", fallback: "Up Next saved as playlist") }
  /// Toast message displayed when the current Up Next is saved in more than one playlists
  internal static var playlistPlayAllUpNextSavedPlural: String { return L10n.tr("Localizable", "playlist_play_all_up_next_saved_plural", fallback: "Up Next saved as playlists") }
  /// Button title used to create a new smart playlist
  internal static var playlistPreviewCreateSmartPlaylist: String { return L10n.tr("Localizable", "playlist_preview_create_smart_playlist", fallback: "Create smart playlist") }
  /// Used on the screen to create a new playlist. The %@ represent the placeholder for the playlist name.
  internal static func playlistPreviewTitle(_ p1: Any) -> String {
    return L10n.tr("Localizable", "playlist_preview_title", String(describing: p1), fallback: "Preview %@")
  }
  /// Search placeholder used in the add episode to manual playlist search from podcast and player
  internal static var playlistSearch: String { return L10n.tr("Localizable", "playlist_search", fallback: "Find playlist") }
  /// Message shown when you have no episodes in a playlist
  internal static var playlistSmartNoEpisodesMsg: String { return L10n.tr("Localizable", "playlist_smart_no_episodes_msg", fallback: "Either it’s time to celebrate completing this list, or edit your rules to get some more.") }
  /// Smart Playlist preview: description that appears when initially there are no rules set
  internal static var playlistSmartPreviewDescription: String { return L10n.tr("Localizable", "playlist_smart_preview_description", fallback: "Set up smart rules to automatically add episodes to your smart playlist.") }
  /// Smart Playlist preview: title for the enabled rules section
  internal static var playlistSmartPreviewEnabledRules: String { return L10n.tr("Localizable", "playlist_smart_preview_enabled_rules", fallback: "Enabled rules") }
  /// Smart Playlist preview: title for the available rules section
  internal static var playlistSmartPreviewMoreRules: String { return L10n.tr("Localizable", "playlist_smart_preview_more_rules", fallback: "More rules") }
  /// Header subtitle for smart rule podcasts when select all is on
  internal static var playlistSmartRulePodcastsHeaderSubtitleAutoAdd: String { return L10n.tr("Localizable", "playlist_smart_rule_podcasts_header_subtitle_auto_add", fallback: "New podcasts you follow will be automatically added.") }
  /// Header subtitle for smart rule podcasts when select all is off
  internal static var playlistSmartRulePodcastsHeaderSubtitleManualAdd: String { return L10n.tr("Localizable", "playlist_smart_rule_podcasts_header_subtitle_manual_add", fallback: "New podcasts you follow will not be automatically added.") }
  /// Header title for smart rule podcasts
  internal static var playlistSmartRulePodcastsHeaderTitle: String { return L10n.tr("Localizable", "playlist_smart_rule_podcasts_header_title", fallback: "All followed podcasts") }
  /// Title of the save button dislayed in each smart rule
  internal static var playlistSmartRuleSaveButton: String { return L10n.tr("Localizable", "playlist_smart_rule_save_button", fallback: "Save smart rule") }
  /// Header subtitle for smart rule starred when the toggle is off
  internal static var playlistSmartRuleStarredHeaderSubtitleToggleOff: String { return L10n.tr("Localizable", "playlist_smart_rule_starred_header_subtitle_toggle_off", fallback: "Starred episodes can still appear if they match your other rules.") }
  /// Header subtitle for smart rule starred when the toggle is on
  internal static var playlistSmartRuleStarredHeaderSubtitleToggleOn: String { return L10n.tr("Localizable", "playlist_smart_rule_starred_header_subtitle_toggle_on", fallback: "Only include starred episodes that match your other rules.") }
  /// Header title for smart rule starred
  internal static var playlistSmartRuleStarredHeaderTitle: String { return L10n.tr("Localizable", "playlist_smart_rule_starred_header_title", fallback: "Starred episodes") }
  /// Smart Playlist preview: title when editing the Smart Playlist rules
  internal static var playlistSmartRulesTitle: String { return L10n.tr("Localizable", "playlist_smart_rules_title", fallback: "Smart rules") }
  /// A common string used throughout the app. Often refers to the Playlists screen.
  internal static var playlists: String { return L10n.tr("Localizable", "playlists", fallback: "Playlists") }
  /// Subtitle for the auto download setting. This is displayed when the option is turned off.
  internal static var playlistsAutoDownloadOffSubtitle: String { return L10n.tr("Localizable", "playlists_auto_download_off_subtitle", fallback: "Enable to auto download episodes in this playlist") }
  /// Subtitle for the auto download setting. This is displayed when the option is turned on. '%1$@' is a placeholder for the number of episodes, this will be more than one.
  internal static func playlistsAutoDownloadOnPluralFormat(_ p1: Any) -> String {
    return L10n.tr("Localizable", "playlists_auto_download_on_plural_format", String(describing: p1), fallback: "The first %1$@ episodes in this playlist will be automatically downloaded")
  }
  /// A placeholder title for a new playlist.
  internal static var playlistsDefaultNewPlaylist: String { return L10n.tr("Localizable", "playlists_default_new_playlist", fallback: "New playlist") }
  /// Option to delete the playlist. It appears in the edit panel from the playlist detail.
  internal static var playlistsDelete: String { return L10n.tr("Localizable", "playlists_delete", fallback: "Delete Playlist") }
  /// Alert message used when a user taps on the delete option to cancel a playlist
  internal static var playlistsDeleteAlertMessage: String { return L10n.tr("Localizable", "playlists_delete_alert_message", fallback: "Are you sure you want to delete your playlist? There's no way to undo this.") }
  /// Alert title used when a user taps on the delete option to cancel a playlist
  internal static var playlistsDeleteAlertTitle: String { return L10n.tr("Localizable", "playlists_delete_alert_title", fallback: "Delete Playlist?") }
  /// Playlists Empty State: description for the empty state visible when no playlists are displayed
  internal static var playlistsEmptyStateDescription: String { return L10n.tr("Localizable", "playlists_empty_state_description", fallback: "Playlists let you organize episodes manually or automatically with Smart Rules.") }
  /// Playlists Empty State: title for the empty state visible when no playlists are displayed
  internal static var playlistsEmptyStateTitle: String { return L10n.tr("Localizable", "playlists_empty_state_title", fallback: "Organize episodes your way") }
  /// Playlists Onboarding screen: description for the manual playlist card
  internal static var playlistsOnboardingManualDescription: String { return L10n.tr("Localizable", "playlists_onboarding_manual_description", fallback: "Take control of your listening. Build custom playlists for trips, themes, or whatever vibe you’re in. Whether Smart or custom, playlists fit the way you listen.") }
  /// Playlists Onboarding screen: title for the manual playlist card
  internal static var playlistsOnboardingManualTitle: String { return L10n.tr("Localizable", "playlists_onboarding_manual_title", fallback: "Introducing Playlists") }
  /// Playlists Onboarding screen: description for the smart playlist card
  internal static var playlistsOnboardingSmartDescription: String { return L10n.tr("Localizable", "playlists_onboarding_smart_description", fallback: "They still work exactly the same, using rules to auto-add your episodes. All your existing Filters are right here, nothing’s changed but the name.") }
  /// Playlists Onboarding screen: title for the smart playlist card
  internal static var playlistsOnboardingSmartTitle: String { return L10n.tr("Localizable", "playlists_onboarding_smart_title", fallback: "Filters are now Smart Playlists") }
  /// Playlist Play all button
  internal static var playlistsPlayAll: String { return L10n.tr("Localizable", "playlists_play_all", fallback: "Play all") }
  /// The description shown in a Tip View when the user creates the first playlist
  internal static var playlistsTipDragAndDropDescription: String { return L10n.tr("Localizable", "playlists_tip_drag_and_drop_description", fallback: "Press and hold a playlist to move it.") }
  /// The title shown in a Tip View when the user creates the first playlist
  internal static var playlistsTipDragAndDropTitle: String { return L10n.tr("Localizable", "playlists_tip_drag_and_drop_title", fallback: "Reorder your playlists") }
  /// A common string used throughout the app. Catch all prompt to suggest to the user to try the task again.
  internal static var pleaseTryAgain: String { return L10n.tr("Localizable", "please_try_again", fallback: "Please try again") }
  /// A common string used throughout the app. Catch all prompt to suggest to the user to try the task again later.
  internal static var pleaseTryAgainLater: String { return L10n.tr("Localizable", "please_try_again_later", fallback: "Please try again later.") }
  /// Prompt informing the user that an account is required in order to sign up for Pocket Casts Plus
  internal static var plusAccountRequiredPrompt: String { return L10n.tr("Localizable", "plus_account_required_prompt", fallback: "A Pocket Casts account is required for Pocket Casts Plus. This ensures seamless listening across all your devices.") }
  /// Details prompt informing the user that an account is required in order to sign up for Pocket Casts Plus
  internal static var plusAccountRequiredPromptDetails: String { return L10n.tr("Localizable", "plus_account_required_prompt_details", fallback: "Create an account or sign in to redeem your access to Pocket Casts Plus.") }
  /// Details message informing the user that they'll return to a free account at the end of their trial
  internal static var plusAccountTrialDetails: String { return L10n.tr("Localizable", "plus_account_trial_details", fallback: "When your trial is over you’ll still have all the great benefits of your regular account. Happy podcasting!") }
  /// Title of the button that informs the user they can unlock all the features in plus
  internal static var plusButtonTitleUnlockAll: String { return L10n.tr("Localizable", "plus_button_title_unlock_all", fallback: "Unlock All Features") }
  /// Title of a label informing the user they can cancel their subscription at any time
  internal static var plusCancelTerms: String { return L10n.tr("Localizable", "plus_cancel_terms", fallback: "Can be canceled at any time") }
  /// Account detail message informing the user that they have been granted a lifetime membership, don't translate "Pocket Casts Champion"
  internal static var plusChampion: String { return L10n.tr("Localizable", "plus_champion", fallback: "Pocket Casts Champion") }
  /// Account detail message informing the user that they have been granted 50% discount.
  internal static var plusDiscountYearlyMembership: String { return L10n.tr("Localizable", "plus_discount_yearly_membership", fallback: "50%% off your first year") }
  /// Error message informing the user that they have already signed up for plus with this account.
  internal static var plusErrorAlreadyRegistered: String { return L10n.tr("Localizable", "plus_error_already_registered", fallback: "You already have a Pocket Casts Plus account") }
  /// Error message details informing the user that they have already signed up for plus with this account so they can't take advantage of the entered promotion.
  internal static var plusErrorAlreadyRegisteredDetails: String { return L10n.tr("Localizable", "plus_error_already_registered_details", fallback: "Thanks for your support, but unfortunately this means you can’t take part in this promotion.") }
  /// Account detail message informing the user when their Plus account will expire. '%1$@' is a placeholder for when the account will expire.
  internal static func plusExpirationFormat(_ p1: Any) -> String {
    return L10n.tr("Localizable", "plus_expiration_format", String(describing: p1), fallback: "Expires %1$@")
  }
  /// Upgrade Experiment - Features Variation: Bokmarks feature card text
  internal static var plusFeatureCardTextBookmarks: String { return L10n.tr("Localizable", "plus_feature_card_text_bookmarks", fallback: "Save your favorite bits from any episode and go back to them.") }
  /// Upgrade Experiment - Features Variation: Desktop feature card text
  internal static var plusFeatureCardTextDesktop: String { return L10n.tr("Localizable", "plus_feature_card_text_desktop", fallback: "Listen in more places with our Windows, macOS and Web apps.") }
  /// Upgrade Experiment - Features Variation: Extra feature card text
  internal static var plusFeatureCardTextExtraThemes: String { return L10n.tr("Localizable", "plus_feature_card_text_extra_themes", fallback: "Fly your true colors. Exclusive icons and themes for our subscribers.") }
  /// Upgrade Experiment - Features Variation: Folders feature card text
  internal static var plusFeatureCardTextFolders: String { return L10n.tr("Localizable", "plus_feature_card_text_folders", fallback: "Organize your podcasts in folders, and keep them in sync across all your devices.") }
  /// Upgrade Experiment - Features Variation: Slumber Studio feature card text
  internal static var plusFeatureCardTextSlumberStudio: String { return L10n.tr("Localizable", "plus_feature_card_text_slumber_studio", fallback: "Get 1 year of premium content from Slumber Studios.") }
  /// Upgrade Experiment - Features Variation: Bokmarks feature card title
  internal static var plusFeatureCardTitleBookmarks: String { return L10n.tr("Localizable", "plus_feature_card_title_bookmarks", fallback: "Bookmarks") }
  /// Upgrade Experiment - Features Variation: Desktop feature card title
  internal static var plusFeatureCardTitleDesktop: String { return L10n.tr("Localizable", "plus_feature_card_title_desktop", fallback: "Desktop and web apps") }
  /// Upgrade Experiment - Features Variation: Extra feature card title
  internal static var plusFeatureCardTitleExtraThemes: String { return L10n.tr("Localizable", "plus_feature_card_title_extra_themes", fallback: "Extra themes and icons") }
  /// Upgrade Experiment - Features Variation: Folders feature card title
  internal static var plusFeatureCardTitleFolders: String { return L10n.tr("Localizable", "plus_feature_card_title_folders", fallback: "Folders") }
  /// Upgrade Experiment - Features Variation: Slumber Studio feature card title
  internal static var plusFeatureCardTitleSlumberStudio: String { return L10n.tr("Localizable", "plus_feature_card_title_slumber_studio", fallback: "Dream with Slumber Studios") }
  /// Upgrade Experiment - Features Variation: Storage feature card title
  internal static var plusFeatureCardTitleStorage: String { return L10n.tr("Localizable", "plus_feature_card_title_storage", fallback: "20 GB of storage") }
  /// Message about our gratitude when an user subscribe to Plus
  internal static var plusFeatureGratitude: String { return L10n.tr("Localizable", "plus_feature_gratitude", fallback: "The undying gratitude of everyone here at Pocket Casts") }
  /// Message about the exclusive content from Libro.fm. Don't translate Libro.fm
  internal static var plusFeatureLibrofm: String { return L10n.tr("Localizable", "plus_feature_librofm", fallback: "Free audiobook from Libro.fm") }
  /// Message about the exclusive content from Slumber Studios. Please don't translate "Slumber Studios".
  internal static var plusFeatureSlumber: String { return L10n.tr("Localizable", "plus_feature_slumber", fallback: "1 year of exclusive content from Slumber Studios") }
  /// Message about the exclusive content from Slumber Studios. This is used with our Paywall Experiment. Please don't translate "Slumber Studios".
  internal static var plusFeatureSlumberNew: String { return L10n.tr("Localizable", "plus_feature_slumber_new", fallback: "Dream with Slumber Studios content") }
  /// Feature of Pocket Casts plus, Themes and icons. Themes for changing the way the app looks, icons to change the icon shown on your home screen
  internal static var plusFeatureThemesIcons: String { return L10n.tr("Localizable", "plus_feature_themes_icons", fallback: "Extra themes & icons") }
  /// A common string used throughout the app. often used as a section header to divide settings related to Pocket Casts Plus vs free features. 'PLUS' refers to Pocket Casts Plus.
  internal static var plusFeatures: String { return L10n.tr("Localizable", "plus_features", fallback: "PLUS FEATURES") }
  /// Account detail message informing the user that they have been granted a limited free membership. '%1$@' is a placeholder for a localized string for the free time period.
  internal static func plusFreeMembershipFormat(_ p1: Any) -> String {
    return L10n.tr("Localizable", "plus_free_membership_format", String(describing: p1), fallback: "%1$@ Free Trial")
  }
  /// Pocket Casts Plus marketing page, title of the Bookmarks feature
  internal static var plusMarketingBookmarksTitle: String { return L10n.tr("Localizable", "plus_marketing_bookmarks_title", fallback: "Bookmarks") }
  /// Pocket Casts Plus marketing page, title of the Desktop and web apps feature
  internal static var plusMarketingDesktopAppsTitle: String { return L10n.tr("Localizable", "plus_marketing_desktop_apps_title", fallback: "Desktop & web apps") }
  /// Pocket Casts Plus marketing page, title of the Folders and Bookmarks feature
  internal static var plusMarketingFoldersAndBookmarksTitle: String { return L10n.tr("Localizable", "plus_marketing_folders_and_bookmarks_title", fallback: "Folders & Bookmarks") }
  /// Pocket Casts Plus marketing page, description of the Folders feature
  internal static var plusMarketingFoldersDescription: String { return L10n.tr("Localizable", "plus_marketing_folders_description", fallback: "Create folders to organise your podcast collection.") }
  /// Pocket Casts Plus marketing page, title of the Folders feature
  internal static var plusMarketingFoldersTitle: String { return L10n.tr("Localizable", "plus_marketing_folders_title", fallback: "Folders") }
  /// Pocket Casts Plus marketing page, description of generated transcriptsg
  internal static var plusMarketingGeneratedTranscripts: String { return L10n.tr("Localizable", "plus_marketing_generated_transcripts", fallback: "Generated Transcripts") }
  /// Pocket Casts Plus marketing page, description of the hide ads feature
  internal static var plusMarketingHideAdsDescription: String { return L10n.tr("Localizable", "plus_marketing_hide_ads_description", fallback: "Ad-free experience which gives you more of what you love and less of what you don't") }
  /// Pocket Casts Plus marketing page, title of the hide ads feature
  internal static var plusMarketingHideAdsTitle: String { return L10n.tr("Localizable", "plus_marketing_hide_ads_title", fallback: "Hide Ads") }
  /// Pocket Casts Plus marketing page, learn more button. Note that Pocket Casts is a proper noun and shouldn't be translated
  internal static var plusMarketingLearnMoreButton: String { return L10n.tr("Localizable", "plus_marketing_learn_more_button", fallback: "Learn more about Pocket Casts Plus") }
  /// Pocket Casts Plus marketing page, description of removing banner ads
  internal static var plusMarketingNoBannerAds: String { return L10n.tr("Localizable", "plus_marketing_no_banner_ads", fallback: "No Banner Ads") }
  /// Subtitle of the plus marketing view
  internal static var plusMarketingSubtitle: String { return L10n.tr("Localizable", "plus_marketing_subtitle", fallback: "Get access to exclusive features and customisation options") }
  /// Pocket Casts Plus marketing page, title of the Themes & Icons feature
  internal static var plusMarketingThemesIconsTitle: String { return L10n.tr("Localizable", "plus_marketing_themes_icons_title", fallback: "Themes & Icons") }
  /// Title of the plus marketing view
  internal static var plusMarketingTitle: String { return L10n.tr("Localizable", "plus_marketing_title", fallback: "Everything you love about Pocket Casts, plus more") }
  /// Pocket Casts Plus marketing page, description of the Up Next Shuffle feature
  internal static var plusMarketingUpNextShuffle: String { return L10n.tr("Localizable", "plus_marketing_up_next_shuffle", fallback: "Up Next Shuffle") }
  /// Pocket Casts Plus marketing page, description of the Desktop Apps feature
  internal static var plusMarketingUpdatedDesktopAppsDescription: String { return L10n.tr("Localizable", "plus_marketing_updated_desktop_apps_description", fallback: "Listen in more places with our Windows, macOS and Web apps") }
  /// Pocket Casts Plus marketing page, description of the Folders feature
  internal static var plusMarketingUpdatedFoldersDescription: String { return L10n.tr("Localizable", "plus_marketing_updated_folders_description", fallback: "Organise your podcasts in folders, and keep them in sync across all your devices.") }
  /// Monthly pricing format, %1$@ is the price
  internal static func plusMonthlyFrequencyPricingFormat(_ p1: Any) -> String {
    return L10n.tr("Localizable", "plus_monthly_frequency_pricing_format", String(describing: p1), fallback: "%1$@ per month")
  }
  /// Informational message informing the user that their recurring payments for Plus have been canceled.
  internal static var plusPaymentCanceled: String { return L10n.tr("Localizable", "plus_payment_canceled", fallback: "Payment Cancelled") }
  /// Label that goes along with the yearly subscription used to indicate that the yearly plan is the best overall value.
  internal static var plusPaymentFrequencyBestValue: String { return L10n.tr("Localizable", "plus_payment_frequency_best_value", fallback: "Best Value") }
  /// Informational label that's below the monthly price of Pocket Casts Plus. This label sits below a localized price.
  internal static var plusPerMonth: String { return L10n.tr("Localizable", "plus_per_month", fallback: "per month") }
  /// The price of Pocket Casts Plus per month. '%1$@' is a localized monthly price.
  internal static func plusPricePerMonth(_ p1: Any) -> String {
    return L10n.tr("Localizable", "plus_price_per_month", String(describing: p1), fallback: "%1$@ / monthly")
  }
  /// Promotional information for Pocket Casts Plus. Please note that "Pocket Casts Plus" should not be translated because it's a product name
  internal static var plusPromoParagraph: String { return L10n.tr("Localizable", "plus_promo_paragraph", fallback: "Get Pocket Casts Plus to unlock this feature, plus lots more!") }
  /// Error message informing the user the promotion code has expired
  internal static var plusPromotionExpired: String { return L10n.tr("Localizable", "plus_promotion_expired", fallback: "Promotion Expired or Invalid") }
  /// A nudge to ask the user to continue the sign up process even though they encountered an error.
  internal static var plusPromotionExpiredNudge: String { return L10n.tr("Localizable", "plus_promotion_expired_nudge", fallback: "You’re welcome to sign up for Pocket Casts Plus anyway, create a regular account, or just dive right in.") }
  /// Error message informing the user the promotion code has already been used
  internal static var plusPromotionUsed: String { return L10n.tr("Localizable", "plus_promotion_used", fallback: "Code already used") }
  /// Payment failed error message
  internal static var plusPurchaseFailed: String { return L10n.tr("Localizable", "plus_purchase_failed", fallback: "It looks like there was a problem processing your payment. Please try again.") }
  /// The title of the purchase promo
  internal static var plusPurchasePromoTitle: String { return L10n.tr("Localizable", "plus_purchase_promo_title", fallback: "Become a Plus member and unlock all Pocket Casts features") }
  /// Heading for things that require Pocket Casts Plus to work. Please note that "Pocket Casts Plus" should not be translated because it's a product name
  internal static var plusRequiredFeature: String { return L10n.tr("Localizable", "plus_required_feature", fallback: "This feature requires Pocket Casts Plus") }
  /// Title for the screen to allow the user to choose between a monthly or yearly subscription.
  internal static var plusSelectPaymentFrequency: String { return L10n.tr("Localizable", "plus_select_payment_frequency", fallback: "Select Payment Frequency") }
  /// Label of a button to skip subscring to any plan
  internal static var plusSkip: String { return L10n.tr("Localizable", "plus_skip", fallback: "Skip") }
  /// Label of a button prompting the user to start free trial
  internal static var plusStartMyFreeTrial: String { return L10n.tr("Localizable", "plus_start_my_free_trial", fallback: "Start my free trial") }
  /// Sublabel of a button informing the trial duration and the price after. Eg.: "Try 1 month, then $99.99 per year"
  internal static func plusStartTrialDurationPrice(_ p1: Any, _ p2: Any) -> String {
    return L10n.tr("Localizable", "plus_start_trial_duration_price", String(describing: p1), String(describing: p2), fallback: "Try %1$@, then %2$@")
  }
  /// Label of a button to subscribe to Patron. Do not translate "Plus".
  internal static var plusSubscribeTo: String { return L10n.tr("Localizable", "plus_subscribe_to", fallback: "Subscribe to Plus") }
  /// Message informing the user that their Pocket Casts Plus subscription is managed by Apple's system and needs to be managed there.
  internal static var plusSubscriptionApple: String { return L10n.tr("Localizable", "plus_subscription_apple", fallback: "Your subscription is managed by the Apple App Store") }
  /// Message informing the user where to manage their Pocket Casts Plus subscription managed by Apple.
  internal static var plusSubscriptionAppleDetails: String { return L10n.tr("Localizable", "plus_subscription_apple_details", fallback: "To cancel your subscription, you’ll need to cancel via Settings.") }
  /// Message informing the user when their Pocket Casts Plus subscription will expire. %1$@ is a placeholder for the expiration date.
  internal static func plusSubscriptionExpiration(_ p1: Any) -> String {
    return L10n.tr("Localizable", "plus_subscription_expiration", String(describing: p1), fallback: "PLUS EXPIRES IN %1$@")
  }
  /// Message informing the user that their Pocket Casts Plus subscription is managed by Google's system and needs to be managed there.
  internal static var plusSubscriptionGoogle: String { return L10n.tr("Localizable", "plus_subscription_google", fallback: "It looks like you subscribed to Pocket Casts Plus from an Android device") }
  /// Message informing the user where to manage their Pocket Casts Plus subscription managed by Google.
  internal static var plusSubscriptionGoogleDetails: String { return L10n.tr("Localizable", "plus_subscription_google_details", fallback: "To cancel your subscription, you’ll need to cancel via Settings.") }
  /// Message informing the user that their Pocket Casts Plus subscription is managed by Web's system and needs to be managed there.
  internal static var plusSubscriptionWeb: String { return L10n.tr("Localizable", "plus_subscription_web", fallback: "It looks like you subscribed to Pocket Casts Plus from the web") }
  /// Message informing the user where to manage their Pocket Casts Plus subscription managed by Web.
  internal static var plusSubscriptionWebDetails: String { return L10n.tr("Localizable", "plus_subscription_web_details", fallback: "To cancel your subscription, you’ll need to cancel via Pocketcasts.com.") }
  /// Body of a message informing the user they need an internet connect to upgrade to plus
  internal static var plusUpgradeNoInternetMessage: String { return L10n.tr("Localizable", "plus_upgrade_no_internet_message", fallback: "Please check your internet connection and try again.") }
  /// Body of a message informing the user the request failed
  internal static var plusUpgradeNoInternetTitle: String { return L10n.tr("Localizable", "plus_upgrade_no_internet_title", fallback: "Unable to Load") }
  /// Yearly pricing format, %1$@ is the price
  internal static func plusYearlyFrequencyPricingFormat(_ p1: Any) -> String {
    return L10n.tr("Localizable", "plus_yearly_frequency_pricing_format", String(describing: p1), fallback: "%1$@ per year")
  }
  /// A Voice Over label for element which represents the Pocket Casts Logo
  internal static var pocketCastsLogo: String { return L10n.tr("Localizable", "pocket_casts_logo", fallback: "Pocket Casts logo") }
  /// A common string used throughout the app. Refers to the subscription program Pocket Casts Plus subscription. 'Pocket Casts' as a proper noun should not be localized.
  internal static var pocketCastsPlus: String { return L10n.tr("Localizable", "pocket_casts_plus", fallback: "Pocket Casts Plus") }
  /// A shortened version of the common string used throughout the app. Refers to the subscription program Pocket Casts Plus subscription.
  internal static var pocketCastsPlusShort: String { return L10n.tr("Localizable", "pocket_casts_plus_short", fallback: "Plus") }
  /// Indicates that the access to the podcast has ended on the specified date. '%1$@' is a placeholder for date that the access expired.
  internal static func podcastAccessEnded(_ p1: Any) -> String {
    return L10n.tr("Localizable", "podcast_access_ended", String(describing: p1), fallback: "Access ended: %1$@")
  }
  /// Indicates that the access to the podcast will end on the specified date. '%1$@' is a placeholder for date that the access will end.
  internal static func podcastAccessEnds(_ p1: Any) -> String {
    return L10n.tr("Localizable", "podcast_access_ends", String(describing: p1), fallback: "Access ends: %1$@")
  }
  /// Title for the alert that lets a user add a podcast by feed URL or import OPML.
  internal static var podcastAddAlertTitle: String { return L10n.tr("Localizable", "podcast_add_alert_title", fallback: "Add Podcast") }
  /// Button title that opens the add podcast flow.
  internal static var podcastAddButtonTitle: String { return L10n.tr("Localizable", "podcast_add_button_title", fallback: "Add Podcast") }
  /// Button title that submits a feed URL in the add podcast alert.
  internal static var podcastAddFeedUrlAction: String { return L10n.tr("Localizable", "podcast_add_feed_url_action", fallback: "Add Feed URL") }
  /// Placeholder shown in the add podcast feed URL text field.
  internal static var podcastAddFeedUrlPlaceholder: String { return L10n.tr("Localizable", "podcast_add_feed_url_placeholder", fallback: "https://example.com/feed.xml") }
  /// Sort option for bookmarks that uses Podcast name and Episodes dates
  internal static var podcastAndEpisode: String { return L10n.tr("Localizable", "podcast_and_episode", fallback: "Podcast & Episode") }
  /// Prompt to archive all of the selected items.
  internal static var podcastArchiveAll: String { return L10n.tr("Localizable", "podcast_archive_all", fallback: "Archive All") }
  /// Prompt to archive all played episodes of the current podcast.
  internal static var podcastArchiveAllPlayed: String { return L10n.tr("Localizable", "podcast_archive_all_played", fallback: "Archive All Played") }
  /// Confirmation to archive a certain number of podcast episodes. This is the singular form of an accompanying plural form.
  internal static var podcastArchiveEpisodeCountSingular: String { return L10n.tr("Localizable", "podcast_archive_episode_count_singular", fallback: "Archive 1 Episode") }
  /// Confirmation to archive a certain number of podcast episodes. '%1$@' is a placeholder for the number of episodes.
  internal static func podcastArchiveEpisodesCountPluralFormat(_ p1: Any) -> String {
    return L10n.tr("Localizable", "podcast_archive_episodes_count_plural_format", String(describing: p1), fallback: "Archive %1$@ Episodes")
  }
  /// Confirmation message that appears alongside the various bulk archive prompts.
  internal static var podcastArchivePromptMsg: String { return L10n.tr("Localizable", "podcast_archive_prompt_msg", fallback: "You should only do this if you don't want to see them anymore.") }
  /// Indicates that the episode has been archived.
  internal static var podcastArchived: String { return L10n.tr("Localizable", "podcast_archived", fallback: "Archived") }
  /// Label used to display the number or archived episodes in a podcast. '%1$@' is a placeholder for the archived episode number.
  internal static func podcastArchivedCountFormat(_ p1: Any) -> String {
    return L10n.tr("Localizable", "podcast_archived_count_format", String(describing: p1), fallback: "%1$@ archived")
  }
  /// Informational message informing the user that no episodes are being displayed because they're all archived. '%1$@' is a placeholder for the number of episodes.
  internal static func podcastArchivedMsg(_ p1: Any) -> String {
    return L10n.tr("Localizable", "podcast_archived_msg", String(describing: p1), fallback: "All %1$@ episodes of this podcast have been archived")
  }
  /// A common string used throughout the app. Displays the count of selected podcasts. '%1$@' is a placeholder for the number of podcasts, the value will be more than one.
  internal static func podcastCountPluralFormat(_ p1: Any) -> String {
    return L10n.tr("Localizable", "podcast_count_plural_format", String(describing: p1), fallback: "%1$@ podcasts")
  }
  /// A common string used throughout the app. Displays the count of selected podcasts. This is the singular version of an accompanying plural format.
  internal static var podcastCountSingular: String { return L10n.tr("Localizable", "podcast_count_singular", fallback: "1 podcast") }
  /// Error message informing the user that the episode encountered a download error.
  internal static var podcastDetailsDownloadError: String { return L10n.tr("Localizable", "podcast_details_download_error", fallback: "Episode download failed") }
  /// Message informing the user that the episode will download once the device restores a WiFi connection.
  internal static var podcastDetailsDownloadWifiQueue: String { return L10n.tr("Localizable", "podcast_details_download_wifi_queue", fallback: "This episode will automatically download when you're next on WiFi") }
  /// Message details informing the user that the episode has been unarchived manually and won't be archived when the episode limit is reached. '%1$@' is a placeholder for the episode limit.
  internal static func podcastDetailsManualUnarchiveMsg(_ p1: Any) -> String {
    return L10n.tr("Localizable", "podcast_details_manual_unarchive_msg", String(describing: p1), fallback: "It won't be auto archived by your new episode limit of %1$@")
  }
  /// Message informing the user that the episode has been unarchived manually. Used with episode limits.
  internal static var podcastDetailsManualUnarchiveTitle: String { return L10n.tr("Localizable", "podcast_details_manual_unarchive_title", fallback: "Episode Manually Unarchived") }
  /// Error message informing the user that the episode encountered a playback error.
  internal static var podcastDetailsPlaybackError: String { return L10n.tr("Localizable", "podcast_details_playback_error", fallback: "Unable to play episode") }
  /// Indicates that the episode is queued for download.
  internal static var podcastDetailsQueued: String { return L10n.tr("Localizable", "podcast_details_queued", fallback: "Queued") }
  /// Confirmation prompt to remove the episode file for the selected podcast episode.
  internal static var podcastDetailsRemoveDownload: String { return L10n.tr("Localizable", "podcast_details_remove_download", fallback: "REMOVE DOWNLOADED FILE?") }
  /// Prompt to download the selected podcast now.
  internal static var podcastDownloadNow: String { return L10n.tr("Localizable", "podcast_download_now", fallback: "Download Now") }
  /// Indicates that a file is being downloaded and includes the completed percentage. '%1$@' is a placeholder for percentage that has been downloaded so far.
  internal static func podcastDownloading(_ p1: Any) -> String {
    return L10n.tr("Localizable", "podcast_downloading", String(describing: p1), fallback: "Downloading... %1$@")
  }
  /// Label used to display the number of episodes in a podcast. '%1$@' is a placeholder for the number of episodes.
  internal static func podcastEpisodeCountPluralFormat(_ p1: Any) -> String {
    return L10n.tr("Localizable", "podcast_episode_count_plural_format", String(describing: p1), fallback: "%1$@ episodes")
  }
  /// Label used to display the number of episodes in a podcast. This is the singular form of an accompanying plural form.
  internal static var podcastEpisodeCountSingular: String { return L10n.tr("Localizable", "podcast_episode_count_singular", fallback: "1 episode") }
  /// Label used to display the episode limit for a podcast. '%1$@' is a placeholder for the episode limit.
  internal static func podcastEpisodeLimitCountFormat(_ p1: Any) -> String {
    return L10n.tr("Localizable", "podcast_episode_limit_count_format", String(describing: p1), fallback: "Limited to %1$@")
  }
  /// Message for a generic error used when a podcast fails to load without a more detailed reason why. ':(' is meant to be ASCII art for a sad face.
  internal static var podcastErrorMessage: String { return L10n.tr("Localizable", "podcast_error_message", fallback: "Unable to load podcast details :(") }
  /// Title for a generic error used when a podcast fails to load without a more detailed reason why. Meant to be a fun cultural reference.
  internal static var podcastErrorTitle: String { return L10n.tr("Localizable", "podcast_error_title", fallback: "Literally Can't Even") }
  /// Accessibility label for the explicit content badge displayed on podcasts with explicit content.
  internal static var podcastExplicitContent: String { return L10n.tr("Localizable", "podcast_explicit_content", fallback: "Explicit content") }
  /// Name for group of episodes that don't have a season defined when sorting in serial mode
  internal static var podcastExtras: String { return L10n.tr("Localizable", "podcast_extras", fallback: "Extras") }
  /// Indicates that a file has failed to download.
  internal static var podcastFailedDownload: String { return L10n.tr("Localizable", "podcast_failed_download", fallback: "Episode download failed.") }
  /// Button title we display in the podcast view sheet prompted
  internal static var podcastFeedReloadButton: String { return L10n.tr("Localizable", "podcast_feed_reload_button", fallback: "Refresh Episode List") }
  /// Message showed in the toast menu or pull down to refresh control indicating the podcast feed is reloading
  internal static var podcastFeedReloadLoading: String { return L10n.tr("Localizable", "podcast_feed_reload_loading", fallback: "Refreshing episode list...") }
  /// After the podcast feed reloading completes, this is the message we display if there's new episodes to load
  internal static var podcastFeedReloadNewEpisodesFound: String { return L10n.tr("Localizable", "podcast_feed_reload_new_episodes_found", fallback: "New episodes found!") }
  /// After the podcast feed reloading completes, this is the message we display if there's no new episodes to load
  internal static var podcastFeedReloadNoEpisodesFound: String { return L10n.tr("Localizable", "podcast_feed_reload_no_episodes_found", fallback: "No episodes found.") }
  /// Description used in the tooltip showed in the podcast view controller the first time the view appears
  internal static var podcastFeedReloadTipMessage: String { return L10n.tr("Localizable", "podcast_feed_reload_tip_message", fallback: "Pull down or use this menu to see if there's something new.") }
  /// Title used in the tooltip showed in the podcast view controller the first time the view appears
  internal static var podcastFeedReloadTipTitle: String { return L10n.tr("Localizable", "podcast_feed_reload_tip_title", fallback: "Fresh episodes, coming right up!") }
  /// Button text shown on the podcast grid when you have no podcasts, takes you to the Discover section of the app
  internal static var podcastGridDiscoverPodcasts: String { return L10n.tr("Localizable", "podcast_grid_discover_podcasts", fallback: "Discover Podcasts") }
  /// Description shown when you have no podcasts on the podcast grid
  internal static var podcastGridNoPodcastsMsg: String { return L10n.tr("Localizable", "podcast_grid_no_podcasts_msg", fallback: "Coming from another app? Import your podcasts via Profile > Settings > Import & Export.\n\n\nIf you're looking for inspiration try the Discover tab.") }
  /// Title of the message on the podcast grid when you have no podcasts
  internal static var podcastGridNoPodcastsTitle: String { return L10n.tr("Localizable", "podcast_grid_no_podcasts_title", fallback: "Time to add some Podcasts!") }
  /// Title for the options box that allows the user to pick from the various grouping options.
  internal static var podcastGroupOptionsTitle: String { return L10n.tr("Localizable", "podcast_group_options_title", fallback: "GROUP BY") }
  /// Prompt to hide archived episodes from the episode list.
  internal static var podcastHideArchived: String { return L10n.tr("Localizable", "podcast_hide_archived", fallback: "Hide Archived") }
  /// Longer form informational label informing users that this podcast is limited to a configured set of episodes. '%1$@' is a placeholder for the number of episodes.
  internal static func podcastLimitPluralFormat(_ p1: Any) -> String {
    return L10n.tr("Localizable", "podcast_limit_plural_format", String(describing: p1), fallback: "Limited to %1$@ most recent episodes")
  }
  /// Longer form informational label informing users that this podcast is limited to one episode. Singular version of an accompanying plural format.
  internal static var podcastLimitSingular: String { return L10n.tr("Localizable", "podcast_limit_singular", fallback: "Limited to 1 most recent episode") }
  /// Button title that opens the Podcasts tab from another empty state.
  internal static var podcastListGoToPodcastsAction: String { return L10n.tr("Localizable", "podcast_list_go_to_podcasts_action", fallback: "Go to Podcasts") }
  /// Progress indicator informing the user that the podcasts that have been shared or imported are currently loading.
  internal static var podcastLoading: String { return L10n.tr("Localizable", "podcast_loading", fallback: "Loading Podcast...") }
  /// Used to indicate no date was provided.
  internal static var podcastNoDate: String { return L10n.tr("Localizable", "podcast_no_date", fallback: "Date Not Set") }
  /// Label used to indicate that the podcast episode isn't grouped into a season.
  internal static var podcastNoSeason: String { return L10n.tr("Localizable", "podcast_no_season", fallback: "No Season") }
  /// Accessibility label to prompt to pause an active download.
  internal static var podcastPauseDownload: String { return L10n.tr("Localizable", "podcast_pause_download", fallback: "Pause download") }
  /// Accessibility label to prompt to pause a playback.
  internal static var podcastPausePlayback: String { return L10n.tr("Localizable", "podcast_pause_playback", fallback: "Pause playback") }
  /// Title shown in the section header for podcast podroll recommendations
  internal static var podcastPodrollHeader: String { return L10n.tr("Localizable", "podcast_podroll_header", fallback: "Shows recommended by the creator") }
  /// Indicates that a file is queued for download and includes the estimated size.
  internal static var podcastQueued: String { return L10n.tr("Localizable", "podcast_queued", fallback: "Queued") }
  /// Indicates that the episode is queued for download.
  internal static var podcastQueuing: String { return L10n.tr("Localizable", "podcast_queuing", fallback: "Queued...") }
  /// Prompt to trigger an artwork refresh on the podcast.
  internal static var podcastRefreshArtwork: String { return L10n.tr("Localizable", "podcast_refresh_artwork", fallback: "Refresh Artwork") }
  /// Entry informing which podcasts was removed from which folder, %1$@ is the podcast's title, %2$@ folder's name
  internal static func podcastRemovedFromFolder(_ p1: Any, _ p2: Any) -> String {
    return L10n.tr("Localizable", "podcast_removed_from_folder", String(describing: p1), String(describing: p2), fallback: "%1$@ removed from %2$@")
  }
  /// Format used to show the Season number of a podcast. '%1$@' is a placeholder for the Season number.
  internal static func podcastSeasonFormat(_ p1: Any) -> String {
    return L10n.tr("Localizable", "podcast_season_format", String(describing: p1), fallback: "Season %1$@")
  }
  /// Podcast settings switch: opt this podcast out of the remote transcription provider, so its automatic transcripts are generated on-device instead
  internal static var podcastSettingsLocalTranscriptionOnly: String { return L10n.tr("Localizable", "podcast_settings_local_transcription_only", fallback: "Transcribe On-Device Only") }
  /// Footer under the podcast settings on-device-only transcription switch, explaining that this show's automatic transcripts skip the remote provider
  internal static var podcastSettingsLocalTranscriptionOnlyFooter: String { return L10n.tr("Localizable", "podcast_settings_local_transcription_only_footer", fallback: "Automatic transcripts for this podcast will be generated on-device instead of using your configured transcription provider.") }
  /// Podcast settings row and screen title for the chapter smart-skip rules editor.
  internal static var podcastSettingsSkipChapters: String { return L10n.tr("Localizable", "podcast_settings_skip_chapters", fallback: "Skip Chapters") }
  /// Prompt to allow the user to share the currently selected episode.
  internal static var podcastShareEpisode: String { return L10n.tr("Localizable", "podcast_share_episode", fallback: "Share Link to Episode") }
  /// Error message used when there are no available apps that can accept the podcast file.
  internal static var podcastShareEpisodeErrorMsg: String { return L10n.tr("Localizable", "podcast_share_episode_error_msg", fallback: "You don't have any apps installed that will accept this file") }
  /// Error message for when a podcast can't be found after it has been shared.
  internal static var podcastShareErrorMsg: String { return L10n.tr("Localizable", "podcast_share_error_msg", fallback: "The podcast author may have removed it since this link was shared.") }
  /// Error title for when a podcast can't be found after it has been shared.
  internal static var podcastShareErrorTitle: String { return L10n.tr("Localizable", "podcast_share_error_title", fallback: "Unable To Find Episode") }
  /// Progress message shown while the users curated list is being synced to the server.
  internal static var podcastShareListCreating: String { return L10n.tr("Localizable", "podcast_share_list_creating", fallback: "Creating list...") }
  /// Placeholder for the description of the podcast list. Used when users create a curated list of podcasts. This item is optional.
  internal static var podcastShareListDescription: String { return L10n.tr("Localizable", "podcast_share_list_description", fallback: "Description (optional)") }
  /// Placeholder for the name of the podcast list. Used when users create a curated list of podcasts.
  internal static var podcastShareListName: String { return L10n.tr("Localizable", "podcast_share_list_name", fallback: "List Name") }
  /// Option to share the episode file to other apps.
  internal static var podcastShareOpenFile: String { return L10n.tr("Localizable", "podcast_share_open_file", fallback: "Open File in...") }
  /// Prompt to Show archived episodes in the episode list.
  internal static var podcastShowArchived: String { return L10n.tr("Localizable", "podcast_show_archived", fallback: "Show Archived") }
  /// Generic title shown in the section header for podcast recommendations
  internal static var podcastSimilarGenericHeader: String { return L10n.tr("Localizable", "podcast_similar_generic_header", fallback: "Similar shows") }
  /// Title shown in the section header for podcast recommendations
  internal static func podcastSimilarHeader(_ p1: Any) -> String {
    return L10n.tr("Localizable", "podcast_similar_header", String(describing: p1), fallback: "Shows similar to \"%@\"")
  }
  /// A common string used throughout the app. Refers to Podcasts in the singular form.
  internal static var podcastSingular: String { return L10n.tr("Localizable", "podcast_singular", fallback: "Podcast") }
  /// Used to reference that a new podcast episode will be available in the near future.
  internal static var podcastSoon: String { return L10n.tr("Localizable", "podcast_soon", fallback: "Any day now") }
  /// Title for the options box that allows the user to pick from the various sort options.
  internal static var podcastSortOrderTitle: String { return L10n.tr("Localizable", "podcast_sort_order_title", fallback: "SORT ORDER") }
  /// Confirmation option to stream the selected episode. Used in tandem with a notice that the user is not on WiFi.
  internal static var podcastStreamConfirmation: String { return L10n.tr("Localizable", "podcast_stream_confirmation", fallback: "Stream Anyway") }
  /// Prompt to warn the user that continuing with the option to stream will consume data. Used in tandem with a notice that the user is not on WiFi.
  internal static func podcastStreamDataWarningWithSettings(_ p1: Any) -> String {
    return L10n.tr("Localizable", "podcast_stream_data_warning_with_settings", String(describing: p1), fallback: "Streaming this episode will use data. You can turn off this warning in [Settings](%@).")
  }
  /// Used to reference the episode was published this month.
  internal static var podcastThisMonth: String { return L10n.tr("Localizable", "podcast_this_month", fallback: "This Month") }
  /// Indicates the remaining amount of time left in the episode. '%1$@' is a placeholder for the remaining time.
  internal static func podcastTimeLeft(_ p1: Any) -> String {
    return L10n.tr("Localizable", "podcast_time_left", String(describing: p1), fallback: "%1$@ left")
  }
  /// Used to reference tomorrow in terms of when the next episode will be available.
  internal static var podcastTomorrow: String { return L10n.tr("Localizable", "podcast_tomorrow", fallback: "Tomorrow") }
  /// Prompt to unarchive all of the selected items.
  internal static var podcastUnarchiveAll: String { return L10n.tr("Localizable", "podcast_unarchive_all", fallback: "Unarchive All") }
  /// Indicates that the episode is unavailable server side.
  internal static var podcastUnavailable: String { return L10n.tr("Localizable", "podcast_unavailable", fallback: "Unavailable") }
  /// Indicates that the updates to the podcast has ended on the specified date. '%1$@' is a placeholder for date that the updates ended.
  internal static func podcastUpdatesEnded(_ p1: Any) -> String {
    return L10n.tr("Localizable", "podcast_updates_ended", String(describing: p1), fallback: "Updates ended: %1$@")
  }
  /// Indicates that the updates to the podcast will end on the specified date. '%1$@' is a placeholder for date that the updates will end.
  internal static func podcastUpdatesEnds(_ p1: Any) -> String {
    return L10n.tr("Localizable", "podcast_updates_ends", String(describing: p1), fallback: "Updates ends: %1$@")
  }
  /// Podcast View Changes tooltip details of change
  internal static var podcastViewChangesTipDetails: String { return L10n.tr("Localizable", "podcast_view_changes_tip_details", fallback: "Tap on the podcast title to collapse or expand its description and details") }
  /// Podcast View Changes tooltip title
  internal static var podcastViewChangesTipTitle: String { return L10n.tr("Localizable", "podcast_view_changes_tip_title", fallback: "We've made some changes") }
  /// Used to reference yesterday.
  internal static var podcastYesterday: String { return L10n.tr("Localizable", "podcast_yesterday", fallback: "Yesterday") }
  /// The badge feature is set to show the number of unplayed episodes.
  internal static var podcastsBadgeAllUnplayed: String { return L10n.tr("Localizable", "podcasts_badge_all_unplayed", fallback: "Unfinished Episodes") }
  /// The badge feature is set to show an indicator if an unplayed episode exists.
  internal static var podcastsBadgeLatestEpisode: String { return L10n.tr("Localizable", "podcasts_badge_latest_episode", fallback: "Only Latest Episode") }
  /// Title for the options to configure badge display options.
  internal static var podcastsBadges: String { return L10n.tr("Localizable", "podcasts_badges", fallback: "Badges") }
  /// Prompt to enter the mode for reordering the podcasts grid.
  internal static var podcastsEdit: String { return L10n.tr("Localizable", "podcasts_edit", fallback: "Edit Podcasts") }
  /// Episodes will be displayed in custom order by drag and drop
  internal static var podcastsEpisodeSortDragAndDrop: String { return L10n.tr("Localizable", "podcasts_episode_sort_drag_and_drop", fallback: "Custom order") }
  /// Episodes will be displayed in order from the longest to the shortest.
  internal static var podcastsEpisodeSortLongestToShortest: String { return L10n.tr("Localizable", "podcasts_episode_sort_longest_to_shortest", fallback: "Longest to Shortest") }
  /// Episodes will be displayed in order from the most resent to the oldest.
  internal static var podcastsEpisodeSortNewestToOldest: String { return L10n.tr("Localizable", "podcasts_episode_sort_newest_to_oldest", fallback: "Newest to oldest") }
  /// Episodes will be displayed in order from the oldest to the most resent.
  internal static var podcastsEpisodeSortOldestToNewest: String { return L10n.tr("Localizable", "podcasts_episode_sort_oldest_to_newest", fallback: "Oldest to newest") }
  /// Episodes will be displayed in serial podcast order.
  internal static var podcastsEpisodeSortSerial: String { return L10n.tr("Localizable", "podcasts_episode_sort_serial", fallback: "Serial") }
  /// Episodes will be displayed in order from the shortest to the longest.
  internal static var podcastsEpisodeSortShortestToLongest: String { return L10n.tr("Localizable", "podcasts_episode_sort_shortest_to_longest", fallback: "Shortest to Longest") }
  /// Episodes will be displayed in order from the longest to the shortest.
  internal static var podcastsEpisodeSortTitleAToZ: String { return L10n.tr("Localizable", "podcasts_episode_sort_title_a_to_z", fallback: "Title (A-Z)") }
  /// Episodes will be displayed in order from the longest to the shortest.
  internal static var podcastsEpisodeSortTitleZToA: String { return L10n.tr("Localizable", "podcasts_episode_sort_title_z_to_a", fallback: "Title (Z-A)") }
  /// Presents the podcasts with large podcast artwork tiles.
  internal static var podcastsLargeGrid: String { return L10n.tr("Localizable", "podcasts_large_grid", fallback: "Large Grid") }
  /// Title for the set of options for the presentation styles like grid sizes vs list view.
  internal static var podcastsLayout: String { return L10n.tr("Localizable", "podcasts_layout", fallback: "Layout") }
  /// Grid Items will be sorted sorted based on the users custom ordering. This is performed by dragging and dropping a podcast to the desired order.
  internal static var podcastsLibrarySortCustom: String { return L10n.tr("Localizable", "podcasts_library_sort_custom", fallback: "Drag and Drop") }
  /// Grid Items will be sorted based on the date the user subscribed to them. Newest to oldest.
  internal static var podcastsLibrarySortDateAdded: String { return L10n.tr("Localizable", "podcasts_library_sort_date_added", fallback: "Date Added") }
  /// Grid Items will be sorted based on the recently played date.
  internal static var podcastsLibrarySortEpisodeRecentlyPlayed: String { return L10n.tr("Localizable", "podcasts_library_sort_episode_recently_played", fallback: "Recently Played") }
  /// Description of the tooltip that appears in the podcasts view that alerts a new sorting option
  internal static var podcastsLibrarySortEpisodeRecentlyPlayedTipDescription: String { return L10n.tr("Localizable", "podcasts_library_sort_episode_recently_played_tip_description", fallback: "You can now sort by Recently Played and quickly pick up where you left off.") }
  /// Title of the tooltip that appears in the podcasts view that alerts a new sorting option
  internal static var podcastsLibrarySortEpisodeRecentlyPlayedTipTitle: String { return L10n.tr("Localizable", "podcasts_library_sort_episode_recently_played_tip_title", fallback: "Sort by “Recently Played”") }
  /// Grid Items will be sorted based on the date of their newest episode. Newest to oldest.
  internal static var podcastsLibrarySortEpisodeReleaseDate: String { return L10n.tr("Localizable", "podcasts_library_sort_episode_release_date", fallback: "Episode Release Date") }
  /// Grid Items will be sorted alphabetically based on name.
  internal static var podcastsLibrarySortTitle: String { return L10n.tr("Localizable", "podcasts_library_sort_title", fallback: "Name") }
  /// Presents the podcasts in a list view.
  internal static var podcastsList: String { return L10n.tr("Localizable", "podcasts_list", fallback: "List") }
  /// A common string used throughout the app. Refers to Podcasts in the plural form as well as the Podcasts screen.
  internal static var podcastsPlural: String { return L10n.tr("Localizable", "podcasts_plural", fallback: "Podcasts") }
  /// Prompt to open the menu to share your podcasts list.
  internal static var podcastsShare: String { return L10n.tr("Localizable", "podcasts_share", fallback: "Share Podcasts") }
  /// Presents the podcasts with small podcast artwork tiles.
  internal static var podcastsSmallGrid: String { return L10n.tr("Localizable", "podcasts_small_grid", fallback: "Small Grid") }
  /// Prompt to open the menu to allow the user to sort their podcasts.
  internal static var podcastsSort: String { return L10n.tr("Localizable", "podcasts_sort", fallback: "Sort Podcasts") }
  /// Common word to denote a preview of something is being shown
  internal static var preview: String { return L10n.tr("Localizable", "preview", fallback: "Preview") }
  /// A common string used throughout the app. Prompt to move to the previously played episode.
  internal static var previousEpisode: String { return L10n.tr("Localizable", "previous_episode", fallback: "Previous Episode") }
  /// Pricing terms explaining that the user will have a discount in the first period then will pay full price, %1$@ is the full price, %2$@ the discount duration, %3$@ the date the user will pay full price
  internal static func pricingTermsAfterDiscount(_ p1: Any, _ p2: Any, _ p3: Any) -> String {
    return L10n.tr("Localizable", "pricing_terms_after_discount", String(describing: p1), String(describing: p2), String(describing: p3), fallback: "Recurring payments at %1$@ after %2$@ (%3$@)")
  }
  /// Pricing terms explaining how much will be charged after a free trial ends, %1$@ is the price ($0.99 / month)
  internal static func pricingTermsAfterTrial(_ p1: Any) -> String {
    return L10n.tr("Localizable", "pricing_terms_after_trial", String(describing: p1), fallback: "then %1$@")
  }
  /// Pricing terms explaining that the user will be charged after their free trial ends, %1$@ is the free trial duration (1 month), %2$@ is the start date of payments
  internal static func pricingTermsAfterTrialLong(_ p1: Any, _ p2: Any) -> String {
    return L10n.tr("Localizable", "pricing_terms_after_trial_long", String(describing: p1), String(describing: p2), fallback: "Recurring payments will begin after your %1$@ free trial (%2$@)")
  }
  /// A common string used throughout the app. Refers to the Profile tab.
  internal static var profile: String { return L10n.tr("Localizable", "profile", fallback: "Profile") }
  /// Body of Plus promotional section
  internal static var profileHelpSupport: String { return L10n.tr("Localizable", "profile_help_support", fallback: "Help support Pocket Casts by upgrading your account") }
  /// Informational label indicating the last time the app was refreshed. '%1$@' is a placeholder for a date string indicating when the last refresh occurred.
  internal static func profileLastAppRefresh(_ p1: Any) -> String {
    return L10n.tr("Localizable", "profile_last_app_refresh", String(describing: p1), fallback: "App last refreshed %1$@")
  }
  /// Description for the empty state on screen where the user can review the episodes they have listened to
  internal static var profileListeningHistoryEmptyDescription: String { return L10n.tr("Localizable", "profile_listening_history_empty_description", fallback: "Start listening to podcasts and revisit your listening history here.") }
  /// Title for the empty state on screen where the user can review the episodes they have listened to
  internal static var profileListeningHistoryEmptyTitle: String { return L10n.tr("Localizable", "profile_listening_history_empty_title", fallback: "Let’s get you listening!") }
  /// Displays the number of files for when there are multiple files. '%1$@' is a placeholder for the number of files.
  internal static func profileNumberOfFiles(_ p1: Any) -> String {
    return L10n.tr("Localizable", "profile_number_of_files", String(describing: p1), fallback: "%1$@ Files")
  }
  /// The percentage of file storage space that is currently being used. '%1$@' is a placeholder for a localized percentage.
  internal static func profilePercentFull(_ p1: Any) -> String {
    return L10n.tr("Localizable", "profile_percent_full", String(describing: p1), fallback: "%1$@ Full")
  }
  /// Prompt to allow the user to reset their account password.
  internal static var profileResetPassword: String { return L10n.tr("Localizable", "profile_reset_password", fallback: "Reset Password") }
  /// Placeholder for the one-time reset code field in the reset-password prompt.
  internal static var profileResetPasswordCodePlaceholder: String { return L10n.tr("Localizable", "profile_reset_password_code_placeholder", fallback: "Reset code") }
  /// Error shown when the password reset request fails.
  internal static var profileResetPasswordFailed: String { return L10n.tr("Localizable", "profile_reset_password_failed", fallback: "Unable to reset the password. Check the email address and reset code, then try again.") }
  /// Error shown when the reset code is empty or the new password is outside the server's 12–72 byte limits.
  internal static var profileResetPasswordInvalidInput: String { return L10n.tr("Localizable", "profile_reset_password_invalid_input", fallback: "Enter a valid reset code and a password between 12 and 72 bytes.") }
  /// Placeholder for the new password field in the reset-password prompt.
  internal static var profileResetPasswordNewPlaceholder: String { return L10n.tr("Localizable", "profile_reset_password_new_placeholder", fallback: "New password") }
  /// Message of the reset-password prompt asking for the administrator-issued one-time code and a new password. The 12–72 byte limits are enforced by the server.
  internal static var profileResetPasswordPromptMessage: String { return L10n.tr("Localizable", "profile_reset_password_prompt_message", fallback: "Enter the one-time reset code from your administrator and a new password between 12 and 72 bytes.") }
  /// Alert message confirming the password was reset successfully.
  internal static var profileResetPasswordSuccess: String { return L10n.tr("Localizable", "profile_reset_password_success", fallback: "Your password has been reset. Sign in with your new password.") }
  /// Notice informing the user that the email to reset their password is being prepared to be sent.
  internal static var profileSendingResetEmail: String { return L10n.tr("Localizable", "profile_sending_reset_email", fallback: "Sending Reset Email") }
  /// Notice informing the user that the email to reset their password has been successfully sent. This serves as the message body for an alert accompanied with a title. ':)' is meant to be ASCII art for a happy face.
  internal static var profileSendingResetEmailConfMsg: String { return L10n.tr("Localizable", "profile_sending_reset_email_conf_msg", fallback: "Check your email :)") }
  /// Notice informing the user that the email to reset their password has been successfully sent. This serves as the title for an alert.
  internal static var profileSendingResetEmailConfTitle: String { return L10n.tr("Localizable", "profile_sending_reset_email_conf_title", fallback: "Password Reset Link Sent") }
  /// Notice informing the user that the attempt to send the password reset email has failed.
  internal static var profileSendingResetEmailFailed: String { return L10n.tr("Localizable", "profile_sending_reset_email_failed", fallback: "Failed to send reset email, please try again later.") }
  /// Displays the number of files for when there is a single file.
  internal static var profileSingleFile: String { return L10n.tr("Localizable", "profile_single_file", fallback: "1 File") }
  /// Description for the empty state on screen where the user can review their starred (favorited) podcast episodes
  internal static var profileStarredNoEpisodesDesc: String { return L10n.tr("Localizable", "profile_starred_no_episodes_desc", fallback: "Star episodes you love and come back to them at anytime.") }
  /// Title for the empty state on screen where the user can review their starred (favorited) podcast episodes
  internal static var profileStarredNoEpisodesTitle: String { return L10n.tr("Localizable", "profile_starred_no_episodes_title", fallback: "Save your favorites") }
  /// Title for the button on the new playlist screen that opens the natural-language playlist creator
  internal static var promptedPlaylistEntryButton: String { return L10n.tr("Localizable", "prompted_playlist_entry_button", fallback: "Describe your playlist") }
  /// Subtitle for the describe-your-playlist creation button explaining the feature
  internal static var promptedPlaylistEntrySubtitle: String { return L10n.tr("Localizable", "prompted_playlist_entry_subtitle", fallback: "Tell us what to include and we'll set up the rules.") }
  /// Example playlist description chip: play state and duration rules
  internal static var promptedPlaylistExample1: String { return L10n.tr("Localizable", "prompted_playlist_example_1", fallback: "Unplayed episodes under 30 minutes") }
  /// Example playlist description chip: download state and release date rules
  internal static var promptedPlaylistExample2: String { return L10n.tr("Localizable", "prompted_playlist_example_2", fallback: "Downloaded episodes from this week") }
  /// Example playlist description chip: starred and duration rules
  internal static var promptedPlaylistExample3: String { return L10n.tr("Localizable", "prompted_playlist_example_3", fallback: "Starred episodes longer than an hour") }
  /// Notice shown on the playlist description sheet when on-device Apple Intelligence is unavailable
  internal static var promptedPlaylistFallbackNotice: String { return L10n.tr("Localizable", "prompted_playlist_fallback_notice", fallback: "Apple Intelligence isn't available on this device, so a simpler built-in interpreter will read your description.") }
  /// Button that interprets the playlist description and opens the playlist preview
  internal static var promptedPlaylistGenerate: String { return L10n.tr("Localizable", "prompted_playlist_generate", fallback: "Generate Preview") }
  /// Footnote on the playlist description sheet explaining that processing happens on device
  internal static var promptedPlaylistIntelligenceFootnote: String { return L10n.tr("Localizable", "prompted_playlist_intelligence_footnote", fallback: "Uses on-device intelligence. Your description never leaves this device.") }
  /// Placeholder in the playlist description text field showing an example description
  internal static var promptedPlaylistPlaceholder: String { return L10n.tr("Localizable", "prompted_playlist_placeholder", fallback: "e.g. Unplayed episodes under 30 minutes from this week") }
  /// Title of the natural-language playlist creation sheet
  internal static var promptedPlaylistSheetTitle: String { return L10n.tr("Localizable", "prompted_playlist_sheet_title", fallback: "Describe your playlist") }
  /// Notice listing podcast names from the description that couldn't be found in the user's library. '%1$@' is a placeholder for the comma-separated list of names.
  internal static func promptedPlaylistUnmatchedPodcasts(_ p1: Any) -> String {
    return L10n.tr("Localizable", "prompted_playlist_unmatched_podcasts", String(describing: p1), fallback: "Couldn't find these podcasts in your library: %1$@. Tap Generate Preview again to continue without them.")
  }
  /// The purchase agreement terms, the %1$@, %2$@ are intended to be "Privacy Policy" and "Terms of Use"
  internal static func purchaseTerms(_ p1: Any, _ p2: Any) -> String {
    return L10n.tr("Localizable", "purchase_terms", String(describing: p1), String(describing: p2), fallback: "By continuing, you agree to our %1$@ and %2$@")
  }
  /// Confirmation message to clear the give number of episodes from the queue. '%1$@' is a placeholder for the number of episodes, this will be more than one.
  internal static func queueClearEpisodeQueuePlural(_ p1: Any) -> String {
    return L10n.tr("Localizable", "queue_clear_episode_queue_plural", String(describing: p1), fallback: "Clear %1$@ Episodes")
  }
  /// Confirmation message to clear one episode from the queue.
  internal static var queueClearEpisodeQueueSingular: String { return L10n.tr("Localizable", "queue_clear_episode_queue_singular", fallback: "Clear 1 Episode") }
  /// Prompt to allow the user to clear their queue.
  internal static var queueClearQueue: String { return L10n.tr("Localizable", "queue_clear_queue", fallback: "CLEAR QUEUE") }
  /// A common string used throughout the app. Provides an option to add the selected item(s) to a queue instead of performing the action now. Used for downloads and uploads.
  internal static var queueForLater: String { return L10n.tr("Localizable", "queue_for_later", fallback: "Queue For Later") }
  /// Accessibility label indicating the current podcast is playing and it's episode date. '%1$@' is a placeholder for the episode date.
  internal static func queueNowPlayingAccessibility(_ p1: Any) -> String {
    return L10n.tr("Localizable", "queue_now_playing_accessibility", String(describing: p1), fallback: "Now Playing. %1$@")
  }
  /// Label indicating the amount of time remains on an episode. '%1$@' is a placeholder for a localized time format for the remaining time.
  internal static func queueTimeRemaining(_ p1: Any) -> String {
    return L10n.tr("Localizable", "queue_time_remaining", String(describing: p1), fallback: "%1$@ remaining")
  }
  /// Information label indication the total time remaining in the queue. This is a total across all episodes in the up next queue. '%1$@' is a placeholder for the total time remaining in the queue.
  internal static func queueTotalTimeRemaining(_ p1: Any) -> String {
    return L10n.tr("Localizable", "queue_total_time_remaining", String(describing: p1), fallback: "%1$@ total time remaining")
  }
  /// Title of a button that takes the user to a screen to rate a podcast
  internal static var rate: String { return L10n.tr("Localizable", "rate", fallback: "Rate") }
  /// Error message when a user rating for a podcast couldn't be submitted
  internal static var ratingError: String { return L10n.tr("Localizable", "rating_error", fallback: "Ops! There was an error.") }
  /// Message displayed when an user want to rate a podcast but hasn't listened enough to it
  internal static var ratingListenToThisPodcastMessage: String { return L10n.tr("Localizable", "rating_listen_to_this_podcast_message", fallback: "Only listeners of this podcast can give it a rating. Have a listen to a few episodes and then come back to give your rating. We look forward to hearing what you think!") }
  /// Title displayed when an user want to rate a podcast but hasn't listened enough to it
  internal static var ratingListenToThisPodcastTitle: String { return L10n.tr("Localizable", "rating_listen_to_this_podcast_title", fallback: "Please listen to this podcast first") }
  /// Toast message to alert a user to log in to leave a rating
  internal static var ratingLoginRequired: String { return L10n.tr("Localizable", "rating_login_required", fallback: "You must log in to leave a rating") }
  /// No ratings label message
  internal static var ratingNoRatings: String { return L10n.tr("Localizable", "rating_no_ratings", fallback: "No ratings") }
  /// Confirmation message that a user rating for a podcast was submitted
  internal static var ratingSubmitted: String { return L10n.tr("Localizable", "rating_submitted", fallback: "Your rating was submitted!") }
  /// Thank you message that a user rating for a podcast was submitted
  internal static var ratingThankYou: String { return L10n.tr("Localizable", "rating_thank_you", fallback: "Thank you for rating!") }
  /// Title displayed when an user want to rate a podcast. %1$@ is the podcast title.
  internal static func ratingTitle(_ p1: Any) -> String {
    return L10n.tr("Localizable", "rating_title", String(describing: p1), fallback: "Rate %1$@")
  }
  /// What's New sheet button title
  internal static var ratingWhatsNewButtonTitle: String { return L10n.tr("Localizable", "rating_whats_new_button_title", fallback: "Got it") }
  /// What's New sheet message
  internal static var ratingWhatsNewMessage: String { return L10n.tr("Localizable", "rating_whats_new_message", fallback: "Rate your top podcasts and let creators know how much you appreciate their work. Plus, your ratings help others find new favorite shows!") }
  /// What's New sheet title
  internal static var ratingWhatsNewTitle: String { return L10n.tr("Localizable", "rating_whats_new_title", fallback: "Now Available: Podcast Ratings 🎉") }
  /// Row that opens the full list of voices in every language.
  internal static var readAloudAllLanguages: String { return L10n.tr("Localizable", "read_aloud_all_languages", fallback: "All Languages") }
  /// Title of the screen listing every installed voice by language.
  internal static var readAloudAllVoicesTitle: String { return L10n.tr("Localizable", "read_aloud_all_voices_title", fallback: "All Voices") }
  /// Settings row for entering the provider API key.
  internal static var readAloudApiKey: String { return L10n.tr("Localizable", "read_aloud_api_key", fallback: "API Key") }
  /// Action that cancels a narration in progress.
  internal static var readAloudCancelNarration: String { return L10n.tr("Localizable", "read_aloud_cancel_narration", fallback: "Cancel") }
  /// Shows the size of the document being narrated, e.g. "12,400 characters".
  internal static func readAloudCharacterCount(_ p1: Any) -> String {
    return L10n.tr("Localizable", "read_aloud_character_count", String(describing: p1), fallback: "%1$@ characters")
  }
  /// Button on the Read Aloud library that opens the compose screen.
  internal static var readAloudComposeAction: String { return L10n.tr("Localizable", "read_aloud_compose_action", fallback: "Paste Text…") }
  /// Placeholder in the compose screen's text editor.
  internal static var readAloudComposePlaceholder: String { return L10n.tr("Localizable", "read_aloud_compose_placeholder", fallback: "Paste or type the text you want read aloud.") }
  /// Title of the screen for typing or pasting text to be narrated.
  internal static var readAloudComposeTitle: String { return L10n.tr("Localizable", "read_aloud_compose_title", fallback: "Paste Text") }
  /// Section header explaining that remote narration uploads the document to a third party.
  internal static var readAloudConfirmHeader: String { return L10n.tr("Localizable", "read_aloud_confirm_header", fallback: "Upload this document to ElevenLabs?") }
  /// Toggle confirming the user accepts uploading document text and spending provider quota; placeholders are character count and duration.
  internal static func readAloudConfirmToggle(_ p1: Any, _ p2: Any) -> String {
    return L10n.tr("Localizable", "read_aloud_confirm_toggle", String(describing: p1), String(describing: p2), fallback: "Upload and narrate %1$@ characters (about %2$@ of audio). ElevenLabs may retain requests in your provider history.")
  }
  /// Action that deletes a document, its recordings and its episodes.
  internal static var readAloudDeleteDocument: String { return L10n.tr("Localizable", "read_aloud_delete_document", fallback: "Delete Document") }
  /// Confirmation message when deleting a document.
  internal static var readAloudDeleteDocumentConfirmMessage: String { return L10n.tr("Localizable", "read_aloud_delete_document_confirm_message", fallback: "This removes the text and every recording made from it, including their episodes. This can't be undone.") }
  /// Confirmation title when deleting a document.
  internal static var readAloudDeleteDocumentConfirmTitle: String { return L10n.tr("Localizable", "read_aloud_delete_document_confirm_title", fallback: "Delete this document?") }
  /// Action that deletes a single narration and its episode, keeping the document.
  internal static var readAloudDeleteNarration: String { return L10n.tr("Localizable", "read_aloud_delete_narration", fallback: "Delete Recording") }
  /// Label for the editable document title field on the import sheet.
  internal static var readAloudDocumentTitle: String { return L10n.tr("Localizable", "read_aloud_document_title", fallback: "Title") }
  /// Built-in engine option: free, offline, lower quality.
  internal static var readAloudEngineBuiltin: String { return L10n.tr("Localizable", "read_aloud_engine_builtin", fallback: "Built-in voices") }
  /// Provider engine option.
  internal static var readAloudEngineElevenlabs: String { return L10n.tr("Localizable", "read_aloud_engine_elevenlabs", fallback: "ElevenLabs") }
  /// Footer disclosing the remote provider's data transfer, quota use, and provider-side retention.
  internal static var readAloudEngineFooter: String { return L10n.tr("Localizable", "read_aloud_engine_footer", fallback: "Built-in voices are free and work offline. ElevenLabs uploads your document text to its service, uses your account quota, and may retain requests in your provider history according to your account settings.") }
  /// Settings section header for choosing which engine narrates.
  internal static var readAloudEngineSection: String { return L10n.tr("Localizable", "read_aloud_engine_section", fallback: "Voice Engine") }
  /// Error shown when a document contains nothing to narrate.
  internal static var readAloudErrorEmpty: String { return L10n.tr("Localizable", "read_aloud_error_empty", fallback: "That document has no text to narrate.") }
  /// Generic error shown when narration fails.
  internal static var readAloudErrorGeneric: String { return L10n.tr("Localizable", "read_aloud_error_generic", fallback: "Something went wrong while narrating. Try again.") }
  /// Shown when narration needs a provider API key that hasn't been entered yet. Used on the import sheet and as a Shortcuts error.
  internal static var readAloudErrorKeyMissing: String { return L10n.tr("Localizable", "read_aloud_error_key_missing", fallback: "Add your provider API key in Pocket Casts settings first.") }
  /// Error shown when the remote provider cannot be reached.
  internal static var readAloudErrorNetwork: String { return L10n.tr("Localizable", "read_aloud_error_network", fallback: "ElevenLabs couldn't be reached. Check your connection and try again.") }
  /// Error shown when the provider key restricts requests to other IP addresses.
  internal static var readAloudErrorProviderIpRestricted: String { return L10n.tr("Localizable", "read_aloud_error_provider_ip_restricted", fallback: "This ElevenLabs key doesn't allow requests from your current IP address. Check its IP allowlist.") }
  /// Error shown when the provider account or key has no narration quota remaining.
  internal static var readAloudErrorProviderQuota: String { return L10n.tr("Localizable", "read_aloud_error_provider_quota", fallback: "Your ElevenLabs account or API key has no narration quota remaining.") }
  /// Error shown when a document is too long to narrate.
  internal static var readAloudErrorTooLarge: String { return L10n.tr("Localizable", "read_aloud_error_too_large", fallback: "That document is too long to narrate.") }
  /// Error shown when a document can't be read as text.
  internal static var readAloudErrorUnreadable: String { return L10n.tr("Localizable", "read_aloud_error_unreadable", fallback: "That file couldn't be read as text.") }
  /// Error shown when the selected provider voice is no longer available.
  internal static var readAloudErrorVoiceUnavailable: String { return L10n.tr("Localizable", "read_aloud_error_voice_unavailable", fallback: "That ElevenLabs voice is no longer available. Choose another voice.") }
  /// Estimated length of the finished audio, e.g. "About 14 min of audio".
  internal static func readAloudEstimatedDuration(_ p1: Any) -> String {
    return L10n.tr("Localizable", "read_aloud_estimated_duration", String(describing: p1), fallback: "About %1$@ of audio")
  }
  /// Button that starts narrating the imported document.
  internal static var readAloudGenerate: String { return L10n.tr("Localizable", "read_aloud_generate", fallback: "Narrate") }
  /// Title of the sheet shown after picking a text file, before narration starts.
  internal static var readAloudImportTitle: String { return L10n.tr("Localizable", "read_aloud_import_title", fallback: "Read Aloud") }
  /// Shortcuts error shown when the narration document can't be saved.
  internal static var readAloudIntentErrorCouldNotSave: String { return L10n.tr("Localizable", "read_aloud_intent_error_could_not_save", fallback: "The document couldn't be saved.") }
  /// Shortcuts error shown when no narration voice is installed.
  internal static var readAloudIntentErrorNoVoice: String { return L10n.tr("Localizable", "read_aloud_intent_error_no_voice", fallback: "No narration voice is installed on this device.") }
  /// Shortcuts error shown when a narration that spends provider quota runs without the shortcut's confirmation parameter enabled.
  internal static var readAloudIntentErrorPaidNotConfirmed: String { return L10n.tr("Localizable", "read_aloud_intent_error_paid_not_confirmed", fallback: "This narration uses your provider quota. Turn on Confirm Paid Narration in the shortcut to allow it.") }
  /// Shortcuts error shown when the Read Aloud feature is unavailable.
  internal static var readAloudIntentErrorUnavailable: String { return L10n.tr("Localizable", "read_aloud_intent_error_unavailable", fallback: "Read Aloud isn't available.") }
  /// Shortcuts error shown when the shared text can't be narrated.
  internal static var readAloudIntentErrorUnreadableText: String { return L10n.tr("Localizable", "read_aloud_intent_error_unreadable_text", fallback: "That text couldn't be read.") }
  /// Shown when the provider rejected the key.
  internal static var readAloudKeyInvalid: String { return L10n.tr("Localizable", "read_aloud_key_invalid", fallback: "That key was rejected.") }
  /// Shown when the key is valid but lacks text-to-speech permission.
  internal static var readAloudKeyNoPermission: String { return L10n.tr("Localizable", "read_aloud_key_no_permission", fallback: "That key can't access the ElevenLabs voice catalog. Grant it the voice and text-to-speech permissions needed for narration.") }
  /// Shown when a validated provider key could not be persisted securely.
  internal static var readAloudKeySaveFailed: String { return L10n.tr("Localizable", "read_aloud_key_save_failed", fallback: "Key works, but it couldn't be saved securely. Try again.") }
  /// Shown when the entered key works.
  internal static var readAloudKeyValid: String { return L10n.tr("Localizable", "read_aloud_key_valid", fallback: "Key can load ElevenLabs voices. Text-to-speech access and quota are checked when narration starts.") }
  /// Empty state message on the Read Aloud library screen.
  internal static var readAloudLibraryEmptyMessage: String { return L10n.tr("Localizable", "read_aloud_library_empty_message", fallback: "Import a text or Markdown file and Pocket Casts will narrate it into an episode you can listen to.") }
  /// Empty state title on the Read Aloud library screen.
  internal static var readAloudLibraryEmptyTitle: String { return L10n.tr("Localizable", "read_aloud_library_empty_title", fallback: "No documents yet") }
  /// Title of the Read Aloud library screen listing imported documents.
  internal static var readAloudLibraryTitle: String { return L10n.tr("Localizable", "read_aloud_library_title", fallback: "Read Aloud") }
  /// Files screen menu action opening the Read Aloud library.
  internal static var readAloudMenuAction: String { return L10n.tr("Localizable", "read_aloud_menu_action", fallback: "Read Aloud") }
  /// Footer explaining the cost difference between models.
  internal static var readAloudModelFooter: String { return L10n.tr("Localizable", "read_aloud_model_footer", fallback: "Higher quality models cost more of your provider quota per character.") }
  /// Settings row for choosing the provider model.
  internal static var readAloudModelLabel: String { return L10n.tr("Localizable", "read_aloud_model_label", fallback: "Model") }
  /// Action that narrates an existing document again, in another voice.
  internal static var readAloudNarrateAgain: String { return L10n.tr("Localizable", "read_aloud_narrate_again", fallback: "Narrate Again…") }
  /// Button that starts importing a text document to narrate.
  internal static var readAloudNarrateDocument: String { return L10n.tr("Localizable", "read_aloud_narrate_document", fallback: "Narrate a Document…") }
  /// Describes a finished narration; placeholders are the voice name and audio duration.
  internal static func readAloudNarrationSummary(_ p1: Any, _ p2: Any) -> String {
    return L10n.tr("Localizable", "read_aloud_narration_summary", String(describing: p1), String(describing: p2), fallback: "%1$@ · %2$@")
  }
  /// Footnote when the document's language has no installed voice; placeholder is the language name.
  internal static func readAloudNoVoiceForLanguage(_ p1: Any) -> String {
    return L10n.tr("Localizable", "read_aloud_no_voice_for_language", String(describing: p1), fallback: "No voice is installed for %1$@, so a voice in your device's language was chosen. You can pick another below.")
  }
  /// Notification body naming the finished document.
  internal static func readAloudNotificationBody(_ p1: Any) -> String {
    return L10n.tr("Localizable", "read_aloud_notification_body", String(describing: p1), fallback: "%1$@ has finished narrating.")
  }
  /// Notification title when a narration finishes while the app is in the background.
  internal static var readAloudNotificationTitle: String { return L10n.tr("Localizable", "read_aloud_notification_title", fallback: "Ready to listen") }
  /// Action that retries a failed narration.
  internal static var readAloudRetry: String { return L10n.tr("Localizable", "read_aloud_retry", fallback: "Try Again") }
  /// Section header for Read Aloud defaults in settings.
  internal static var readAloudSettingsDefaults: String { return L10n.tr("Localizable", "read_aloud_settings_defaults", fallback: "Default Voice") }
  /// Footer explaining what the default voice is used for.
  internal static var readAloudSettingsDefaultsFooter: String { return L10n.tr("Localizable", "read_aloud_settings_defaults_footer", fallback: "New documents start with this voice. You can change it for each one before narrating.") }
  /// Settings row linking to the Read Aloud library.
  internal static var readAloudSettingsLibrary: String { return L10n.tr("Localizable", "read_aloud_settings_library", fallback: "Your Documents") }
  /// Settings row showing how much space Read Aloud documents use.
  internal static var readAloudSettingsStorage: String { return L10n.tr("Localizable", "read_aloud_settings_storage", fallback: "Documents on device") }
  /// Status for a narration the user cancelled.
  internal static var readAloudStatusCancelled: String { return L10n.tr("Localizable", "read_aloud_status_cancelled", fallback: "Cancelled") }
  /// Status for a narration that failed.
  internal static var readAloudStatusFailed: String { return L10n.tr("Localizable", "read_aloud_status_failed", fallback: "Couldn't narrate") }
  /// Status for a narration waiting to start.
  internal static var readAloudStatusQueued: String { return L10n.tr("Localizable", "read_aloud_status_queued", fallback: "Waiting…") }
  /// Status while a narration renders; placeholder is a percentage, e.g. "Narrating… 40%".
  internal static func readAloudStatusRendering(_ p1: Any) -> String {
    return L10n.tr("Localizable", "read_aloud_status_rendering", String(describing: p1), fallback: "Narrating… %1$@")
  }
  /// Name of the Read Aloud feature: importing a text file and having it narrated.
  internal static var readAloudTitle: String { return L10n.tr("Localizable", "read_aloud_title", fallback: "Read Aloud") }
  /// Button that checks whether the entered API key works.
  internal static var readAloudValidateKey: String { return L10n.tr("Localizable", "read_aloud_validate_key", fallback: "Validate") }
  /// Row label for the chosen voice.
  internal static var readAloudVoice: String { return L10n.tr("Localizable", "read_aloud_voice", fallback: "Voice") }
  /// Badge on a higher-quality downloadable voice.
  internal static var readAloudVoiceEnhanced: String { return L10n.tr("Localizable", "read_aloud_voice_enhanced", fallback: "Enhanced") }
  /// Badge on the highest-quality downloadable voice.
  internal static var readAloudVoicePremium: String { return L10n.tr("Localizable", "read_aloud_voice_premium", fallback: "Premium") }
  /// Sample sentence spoken when previewing a voice.
  internal static var readAloudVoicePreviewSample: String { return L10n.tr("Localizable", "read_aloud_voice_preview_sample", fallback: "This is how your document will sound when it is read aloud.") }
  /// Explains that better-sounding voices can be downloaded, and where.
  internal static var readAloudVoiceQualityExplainer: String { return L10n.tr("Localizable", "read_aloud_voice_quality_explainer", fallback: "iOS ships compact voices that sound robotic. For much better narration, download Enhanced or Premium voices in the Settings app under Accessibility › Spoken Content › Voices, then come back here.") }
  /// Header of the voice list section showing voices matching the document's language.
  internal static var readAloudVoicesForDocument: String { return L10n.tr("Localizable", "read_aloud_voices_for_document", fallback: "Voices for this document") }
  /// Hint text in the pull to refresh custom control. Provides a notice that new Podcast episodes are being fetched.
  internal static var refreshControlFetchingEpisodes: String { return L10n.tr("Localizable", "refresh_control_fetching_episodes", fallback: "FINDING NEW PODCAST EPISODES") }
  /// Hint text in the pull to refresh custom control.
  internal static var refreshControlPullToRefresh: String { return L10n.tr("Localizable", "refresh_control_pull_to_refresh", fallback: "PULL TO REFRESH") }
  /// Hint text in the pull to refresh custom control. Informs the user that the refresh has finished successfully.
  internal static var refreshControlRefreshComplete: String { return L10n.tr("Localizable", "refresh_control_refresh_complete", fallback: "REFRESH COMPLETE") }
  /// Hint text in the pull to refresh custom control. Informs the user that the refresh has failed. ':(' is meant as sad face ASCII art.
  internal static var refreshControlRefreshFailed: String { return L10n.tr("Localizable", "refresh_control_refresh_failed", fallback: "REFRESH FAILED :(") }
  /// Hint text in the pull to refresh custom control. Provides a notice that files are being synced with the server.
  internal static var refreshControlRefreshingFiles: String { return L10n.tr("Localizable", "refresh_control_refreshing_files", fallback: "REFRESHING FILES") }
  /// Hint text in the pull to refresh custom control. Provides a prompt to release the control to trigger the refresh.
  internal static var refreshControlReleaseToRefresh: String { return L10n.tr("Localizable", "refresh_control_release_to_refresh", fallback: "RELEASE TO REFRESH") }
  /// Hint text in the pull to refresh custom control. Informs the user that the sync has failed. ':(' is meant as sad face ASCII art.
  internal static var refreshControlSyncFailed: String { return L10n.tr("Localizable", "refresh_control_sync_failed", fallback: "SYNC FAILED :(") }
  /// Hint text in the pull to refresh custom control. Provides a notice that Podcasts are being synced with the server.
  internal static var refreshControlSyncingPodcasts: String { return L10n.tr("Localizable", "refresh_control_syncing_podcasts", fallback: "SYNCING PODCASTS AND PROGRESS") }
  /// A common string used throughout the app. Error title indicating that the refresh process has failed.
  internal static var refreshFailed: String { return L10n.tr("Localizable", "refresh_failed", fallback: "Refresh failed") }
  /// A common string used throughout the app. Prompt to perform a manual refresh of the displayed data.
  internal static var refreshNow: String { return L10n.tr("Localizable", "refresh_now", fallback: "Refresh Now") }
  /// A common string used throughout the app. Informational label indicating the last time the refresh occurred. '%1$@' is a placeholder for a localized string indicating when the refresh happened.
  internal static func refreshPreviousRun(_ p1: Any) -> String {
    return L10n.tr("Localizable", "refresh_previous_run", String(describing: p1), fallback: "Last refresh: %1$@")
  }
  /// Activity indicator letting the user know that the process to refresh the current content is running.
  internal static var refreshing: String { return L10n.tr("Localizable", "refreshing", fallback: "Refreshing...") }
  /// Label used when a podcast releases daily episodes
  internal static var releaseFrequencyDaily: String { return L10n.tr("Localizable", "release_frequency_daily", fallback: "Daily") }
  /// Label used when a podcast releases episodes every two weeks
  internal static var releaseFrequencyFortnightly: String { return L10n.tr("Localizable", "release_frequency_fortnightly", fallback: "Fortnightly") }
  /// Label used when a podcast releases hourly episodes
  internal static var releaseFrequencyHourly: String { return L10n.tr("Localizable", "release_frequency_hourly", fallback: "Hourly") }
  /// Label used when a podcast releases episodes every month
  internal static var releaseFrequencyMonthly: String { return L10n.tr("Localizable", "release_frequency_monthly", fallback: "Monthly") }
  /// Label used when a podcast releases episodes every week
  internal static var releaseFrequencyWeekly: String { return L10n.tr("Localizable", "release_frequency_weekly", fallback: "Weekly") }
  /// A common string used throughout the app. Prompt to remove the selected item(s).
  internal static var remove: String { return L10n.tr("Localizable", "remove", fallback: "Remove") }
  /// A common string used throughout the app. Prompt to remove all of the selected item(s).
  internal static var removeAll: String { return L10n.tr("Localizable", "remove_all", fallback: "Remove All") }
  /// A common string used throughout the app. Prompt to delete the selected item(s) local file download.
  internal static var removeDownload: String { return L10n.tr("Localizable", "remove_download", fallback: "Remove Download") }
  /// A title used for an action to remove an episode from a playlist
  internal static var removeFromPlaylist: String { return L10n.tr("Localizable", "remove_from_playlist", fallback: "Remove from playlist") }
  /// A common string used throughout the app. Prompt to remove the selected item(s) from the up next queue.
  internal static var removeFromUpNext: String { return L10n.tr("Localizable", "remove_from_up_next", fallback: "Remove From Up Next") }
  /// A common string used throughout the app. Prompt to remove the selected item(s) from the up next queue. Shorter form of 'Remove From Up Next'.
  internal static var removeUpNext: String { return L10n.tr("Localizable", "remove_up_next", fallback: "Remove Up Next") }
  /// Button label prompting the user to renew their subscription
  internal static var renewSubscription: String { return L10n.tr("Localizable", "renew_subscription", fallback: "Renew your Subscription") }
  /// The act to restore something
  internal static var restore: String { return L10n.tr("Localizable", "restore", fallback: "Restore") }
  /// Title confirming to the user if they want to restore podcasts to original folders
  internal static var restoreFolders: String { return L10n.tr("Localizable", "restore_folders", fallback: "Restore podcasts to folders?") }
  /// Details about what will happen if they restore folders
  internal static var restoreFoldersMessage: String { return L10n.tr("Localizable", "restore_folders_message", fallback: "These podcasts will be permanently added back to the folders listed here") }
  /// Message confirming podcasts were restored to the folders
  internal static var restoreFoldersSuccess: String { return L10n.tr("Localizable", "restore_folders_success", fallback: "Podcasts restored to their original folders") }
  /// Question to the user, if they want to restore their Up Next
  internal static var restoreUpNext: String { return L10n.tr("Localizable", "restore_up_next", fallback: "Restore Up Next?") }
  /// Details about how user's Up Next will be restored
  internal static var restoreUpNextMessage: String { return L10n.tr("Localizable", "restore_up_next_message", fallback: "These episodes will be added to the bottom of your current Up Next") }
  /// A common string used throughout the app. Prompt to retry the recent request.
  internal static var retry: String { return L10n.tr("Localizable", "retry", fallback: "Retry") }
  /// VoiceOver action name on an episode row whose download failed; performing it retries the download.
  internal static var retryDownload: String { return L10n.tr("Localizable", "retry_download", fallback: "Retry download") }
  /// Title of a button that allows the user to save their changes
  internal static var saveBookmark: String { return L10n.tr("Localizable", "save_bookmark", fallback: "Save Bookmark") }
  /// Action title for saving a highlight at the current playback position (Siri shortcut, Control Center control).
  internal static var saveHighlight: String { return L10n.tr("Localizable", "save_highlight", fallback: "Save Highlight") }
  /// A common string used throughout the app. Placeholder text used in search boxes.
  internal static var search: String { return L10n.tr("Localizable", "search", fallback: "Search") }
  /// A placeholder used when searching bookmarks.
  internal static var searchBookmarks: String { return L10n.tr("Localizable", "search_bookmarks", fallback: "Search bookmarks") }
  /// A placeholder used when searchng episodes.
  internal static var searchEpisodes: String { return L10n.tr("Localizable", "search_episodes", fallback: "Search episodes") }
  /// The label of the search button in Discover. Explaining the user can search or directly add a RSS URL.
  internal static var searchLabel: String { return L10n.tr("Localizable", "search_label", fallback: "Search podcasts or add RSS URL") }
  /// A common string used throughout the app when searching podcasts. Placeholder text used in search boxes.
  internal static var searchPodcasts: String { return L10n.tr("Localizable", "search_podcasts", fallback: "Search Podcasts") }
  /// Label describing the recent searches
  internal static var searchRecent: String { return L10n.tr("Localizable", "search_recent", fallback: "Recent searches") }
  /// Current search results being displayed and the total number of results. Eg.: 1 of 10. %1$@ is the current result being shown, %2$@ is the total number of results
  internal static func searchResults(_ p1: Any, _ p2: Any) -> String {
    return L10n.tr("Localizable", "search_results", String(describing: p1), String(describing: p2), fallback: "%1$@ of %2$@")
  }
  /// Send Us Feedback
  internal static var searchResultsEmptyAction: String { return L10n.tr("Localizable", "search_results_empty_action", fallback: "Send Us Feedback") }
  /// Try a new search, or by adding a podcast feed URL
  internal static var searchResultsEmptyMessage: String { return L10n.tr("Localizable", "search_results_empty_message", fallback: "Try a new search, or by adding a podcast feed URL") }
  /// No Results
  internal static var searchResultsEmptyTitle: String { return L10n.tr("Localizable", "search_results_empty_title", fallback: "No Results") }
  /// View all results for "%1$@"
  internal static func searchResultsViewAll(_ p1: Any) -> String {
    return L10n.tr("Localizable", "search_results_view_all", String(describing: p1), fallback: "View all results for \"%1$@\"")
  }
  /// Message shown in search results when no transcript matches the search term. Explains how transcripts become searchable.
  internal static var searchTranscriptsEmptyMessage: String { return L10n.tr("Localizable", "search_transcripts_empty_message", fallback: "Episodes become searchable here when they download or when you view their transcript.") }
  /// Title shown in search results when no transcript matches the search term
  internal static var searchTranscriptsEmptyTitle: String { return L10n.tr("Localizable", "search_transcripts_empty_title", fallback: "No Transcript Matches") }
  /// Search results filter pill that shows matches found inside episode transcripts
  internal static var searchTranscriptsPill: String { return L10n.tr("Localizable", "search_transcripts_pill", fallback: "Transcripts") }
  /// Toggle above transcript search results restricting matches to episodes already played
  internal static var searchTranscriptsPlayedOnly: String { return L10n.tr("Localizable", "search_transcripts_played_only", fallback: "Played only") }
  /// Timestamp label on a transcript search result showing where in the episode the match occurs. '%1$@' is a placeholder for a time like 12:34.
  internal static func searchTranscriptsResultAtTime(_ p1: Any) -> String {
    return L10n.tr("Localizable", "search_transcripts_result_at_time", String(describing: p1), fallback: "At %1$@")
  }
  /// Speaker suffix on a transcript search result. '%1$@' is the speaker name; translators may change punctuation and spacing for their locale.
  internal static func searchTranscriptsSpeakerFormat(_ p1: Any) -> String {
    return L10n.tr("Localizable", "search_transcripts_speaker_format", String(describing: p1), fallback: "· %1$@")
  }
  /// Header for the shelf of the user's own podcasts shown on the empty search screen.
  internal static var searchYourPodcasts: String { return L10n.tr("Localizable", "search_your_podcasts", fallback: "Your Podcasts") }
  /// A common string used throughout the app. Refers to the season a podcast episode is in.
  internal static var season: String { return L10n.tr("Localizable", "season", fallback: "Season") }
  /// Shorthand format used to show the Season and the Episode number of a podcast. 'S' is short for Season. '%1$@' is a placeholder for the season number. 'E' is short for Episode. '%2$@' is a placeholder for the episode number.
  internal static func seasonEpisodeShorthandFormat(_ p1: Any, _ p2: Any) -> String {
    return L10n.tr("Localizable", "season_episode_shorthand_format", String(describing: p1), String(describing: p2), fallback: "S%1$@ E%2$@")
  }
  /// Shorthand format used to show the Season number of a podcast. 'S' is short for Season. '%1$@' is a placeholder for the season number.
  internal static func seasonOnlyShorthandFormat(_ p1: Any) -> String {
    return L10n.tr("Localizable", "season_only_shorthand_format", String(describing: p1), fallback: "S%1$@")
  }
  /// Label shown for seconds listened when it's plural, eg: 15 seconds listened.
  internal static var secondsListened: String { return L10n.tr("Localizable", "seconds_listened", fallback: "Seconds listened") }
  /// Label shown for seconds saved when it's plural, eg: 15 seconds saved.
  internal static var secondsSaved: String { return L10n.tr("Localizable", "seconds_saved", fallback: "Seconds saved") }
  /// A common string used throughout the app. Prompt to select items.
  internal static var select: String { return L10n.tr("Localizable", "select", fallback: "Select") }
  /// Message indicating at least one chapter needs to be selected
  internal static var selectAChapter: String { return L10n.tr("Localizable", "select_a_chapter", fallback: "Please select at least one chapter") }
  /// A common string used throughout the app. Prompt to select all items in the presented list.
  internal static var selectAll: String { return L10n.tr("Localizable", "select_all", fallback: "Select All") }
  /// A common string used throughout the app. Prompt to select all items above the currently selected item.
  internal static var selectAllAbove: String { return L10n.tr("Localizable", "select_all_above", fallback: "Select all above") }
  /// A common string used throughout the app. Prompt to select all items below the currently selected item.
  internal static var selectAllBelow: String { return L10n.tr("Localizable", "select_all_below", fallback: "Select all below") }
  /// Title of a menu prompt
  internal static var selectBookmarks: String { return L10n.tr("Localizable", "select_bookmarks", fallback: "Select Bookmarks") }
  /// A common string used throughout the app. Prompt to select episodes in the presented list.
  internal static var selectEpisodes: String { return L10n.tr("Localizable", "select_episodes", fallback: "Select Episodes") }
  /// A common string used throughout the app. Indicates the number of selected items. '%1$@' is a placeholder for the selected items.
  internal static func selectedCountFormat(_ p1: Any) -> String {
    return L10n.tr("Localizable", "selected_count_format", String(describing: p1), fallback: "%1$@ selected")
  }
  /// info message when authorization is denied server
  internal static var serverErrorLoginAccessDenied: String { return L10n.tr("Localizable", "server_error_login_access_denied", fallback: "The user denied the authorization request") }
  /// Server error message for when the user account has been locked.
  internal static var serverErrorLoginAccountLocked: String { return L10n.tr("Localizable", "server_error_login_account_locked", fallback: "Your account has been locked due too many login attempts, please try again later.") }
  /// info message when authorization is pending on server
  internal static var serverErrorLoginAuthPending: String { return L10n.tr("Localizable", "server_error_login_auth_pending", fallback: "Authorization pending") }
  /// Server error message for when the user attempted to login without their email.
  internal static var serverErrorLoginEmailBlank: String { return L10n.tr("Localizable", "server_error_login_email_blank", fallback: "Enter an email address.") }
  /// Server error message for when the user enters an invalid email.
  internal static var serverErrorLoginEmailInvalid: String { return L10n.tr("Localizable", "server_error_login_email_invalid", fallback: "Invalid email") }
  /// Server error message for when the user's email couldn't be identified on the server .
  internal static var serverErrorLoginEmailNotFound: String { return L10n.tr("Localizable", "server_error_login_email_not_found", fallback: "Email not found") }
  /// Server error message for when the user tries to create an account for an email tied to an existing account.
  internal static var serverErrorLoginEmailTaken: String { return L10n.tr("Localizable", "server_error_login_email_taken", fallback: "Email taken") }
  /// info message when authorization is expired
  internal static var serverErrorLoginExpiredToken: String { return L10n.tr("Localizable", "server_error_login_expired_token", fallback: "The device code has expired.") }
  /// info message when authorization is invalid on server
  internal static var serverErrorLoginInvalidGrant: String { return L10n.tr("Localizable", "server_error_login_invalid_grant", fallback: "The provided grant is invalid, expired or has been revoked.") }
  /// Server error message for when the user attempted to login without their password.
  internal static var serverErrorLoginPasswordBlank: String { return L10n.tr("Localizable", "server_error_login_password_blank", fallback: "Enter a password.") }
  /// Server error message for when the user enters an invalid password.
  internal static var serverErrorLoginPasswordIncorrect: String { return L10n.tr("Localizable", "server_error_login_password_incorrect", fallback: "Incorrect password") }
  /// Server error message for when the user enters an invalid password.
  internal static var serverErrorLoginPasswordInvalid: String { return L10n.tr("Localizable", "server_error_login_password_invalid", fallback: "Invalid password") }
  /// Server error message for when the user tries to access a feature they don't have access to.
  internal static var serverErrorLoginPermissionDeniedNotAdmin: String { return L10n.tr("Localizable", "server_error_login_permission_denied_not_admin", fallback: "Permission denied") }
  /// Server error message for when the server failed to create the account fro the user.
  internal static var serverErrorLoginUnableToCreateAccount: String { return L10n.tr("Localizable", "server_error_login_unable_to_create_account", fallback: "We couldn't set up that account, sorry.") }
  /// Server error message for when the server failed to create the account fro the user.
  internal static var serverErrorLoginUserRegisterFailed: String { return L10n.tr("Localizable", "server_error_login_user_register_failed", fallback: "Unable to create account, please try again later") }
  /// Server error message for when the user tries to redeem a promo when they are already a plus subscriber.
  internal static var serverErrorPromoAlreadyPlus: String { return L10n.tr("Localizable", "server_error_promo_already_plus", fallback: "You are already a Pocket Casts Plus subscriber, there's no need to redeem any codes.") }
  /// Server error message for when the user tries to redeem a promo code that has already been used.
  internal static var serverErrorPromoAlreadyRedeemed: String { return L10n.tr("Localizable", "server_error_promo_already_redeemed", fallback: "You have already claimed this promo code. It was worth a shot though!") }
  /// Server error message for when the user attempts to redeem a promo code that is no longer active.
  internal static var serverErrorPromoCodeExpiredOrInvalid: String { return L10n.tr("Localizable", "server_error_promo_code_expired_or_invalid", fallback: "This promo code has expired or is invalid.") }
  /// Generic server error message for when an unexpected or unhandled issue occurred.
  internal static var serverErrorUnknown: String { return L10n.tr("Localizable", "server_error_unknown", fallback: "Something went wrong") }
  /// Server message thanking the user for signing up to the service.
  internal static var serverMessageLoginThanksSigningUp: String { return L10n.tr("Localizable", "server_message_login_thanks_signing_up", fallback: "Thanks for signing up!") }
  /// A common string used throughout the app. Reference to the settings menus.
  internal static var settings: String { return L10n.tr("Localizable", "settings", fallback: "Settings") }
  /// A common string used throughout the app. Refers to the About settings menu
  internal static var settingsAbout: String { return L10n.tr("Localizable", "settings_about", fallback: "About") }
  /// Settings row title for the Advanced Audio tuning screen
  internal static var settingsAdvancedAudio: String { return L10n.tr("Localizable", "settings_advanced_audio", fallback: "Advanced Audio") }
  /// Label displayed below the toggle to opt-in/out for First-Party Analytics tracking
  internal static var settingsAllowCollectionFirstParty: String { return L10n.tr("Localizable", "settings_allow_collection_first_party", fallback: "Allow us to collect analytics.") }
  /// Label displayed below the toggle to opt-in/out for Third-Party Analytics tracking
  internal static var settingsAllowCollectionThirdParty: String { return L10n.tr("Localizable", "settings_allow_collection_third_party", fallback: "Allow us to use trusted third-party services to collect anonymous data.") }
  /// Section header for analytics in privacy settings
  internal static var settingsAnalytics: String { return L10n.tr("Localizable", "settings_analytics", fallback: "Analytics") }
  /// A common string used throughout the app. Refers to the Appearance settings menu.
  internal static var settingsAppearance: String { return L10n.tr("Localizable", "settings_appearance", fallback: "Appearance") }
  /// Provides a prompt for the user to configure the settings related to Inactive Episodes. Used in places like configuring Auto Archive settings.
  internal static var settingsArchiveInactiveEpisodes: String { return L10n.tr("Localizable", "settings_archive_inactive_episodes", fallback: "Inactive Episodes") }
  /// Title for the options menu to configure the settings related to archiving Inactive Episodes.
  internal static var settingsArchiveInactiveTitle: String { return L10n.tr("Localizable", "settings_archive_inactive_title", fallback: "Archive Inactive") }
  /// Provides a prompt for the user to configure the settings related to Played Episodes. Used in places like configuring Auto Archive settings.
  internal static var settingsArchivePlayedEpisodes: String { return L10n.tr("Localizable", "settings_archive_played_episodes", fallback: "Played Episodes") }
  /// Title for the options menu to configure the settings related to archiving Played Episodes.
  internal static var settingsArchivePlayedTitle: String { return L10n.tr("Localizable", "settings_archive_played_title", fallback: "Archive Played") }
  /// A common string used throughout the app. Refers to the Auto Add to Up Next settings menu
  internal static var settingsAutoAdd: String { return L10n.tr("Localizable", "settings_auto_add", fallback: "Auto Add to Up Next") }
  /// Prompt to select the episode limit for auto adding podcasts to the Up Next Queue.
  internal static var settingsAutoAddLimit: String { return L10n.tr("Localizable", "settings_auto_add_limit", fallback: "Auto Add Limit") }
  /// Prompt to select the behavior of the app if the auto add limit has been reached.
  internal static var settingsAutoAddLimitReached: String { return L10n.tr("Localizable", "settings_auto_add_limit_reached", fallback: "If Limit Reached") }
  /// Subtitle explaining the app's behavior when the episode limit is reached and new episodes are not add to the Up Next Queue. '%1$@' is a placeholder for the auto add limit.
  internal static func settingsAutoAddLimitSubtitleStop(_ p1: Any) -> String {
    return L10n.tr("Localizable", "settings_auto_add_limit_subtitle_stop", String(describing: p1), fallback: "New episodes will stop being added when Up Next reaches %1$@ episodes.")
  }
  /// Subtitle explaining the app's behavior when the episode limit is reached and new episodes are added to the top of the Up Next Queue. '%1$@' is a placeholder for the auto add limit.
  internal static func settingsAutoAddLimitSubtitleTop(_ p1: Any) -> String {
    return L10n.tr("Localizable", "settings_auto_add_limit_subtitle_top", String(describing: p1), fallback: "When Up Next reaches %1$@, new episodes auto‑added to the top will remove the last episode in the queue. Episodes set to auto‑add to the bottom won’t be added until Up Next is below the limit.")
  }
  /// Section header that displays all of the Podcasts that will automatically add new episodes to the Up Next Queue.
  internal static var settingsAutoAddPodcasts: String { return L10n.tr("Localizable", "settings_auto_add_podcasts", fallback: "Auto-Add Podcasts") }
  /// A common string used throughout the app. Refers to the Auto Archive settings menu
  internal static var settingsAutoArchive: String { return L10n.tr("Localizable", "settings_auto_archive", fallback: "Auto Archive") }
  /// Setting to auto archive a podcast episode. This value will auto archive the episode after 1 Week has passed.
  internal static var settingsAutoArchive1Week: String { return L10n.tr("Localizable", "settings_auto_archive_1_week", fallback: "After 1 Week") }
  /// Setting to auto archive a podcast episode. This value will auto archive the episode after 24 Hours has passed.
  internal static var settingsAutoArchive24Hours: String { return L10n.tr("Localizable", "settings_auto_archive_24_hours", fallback: "After 24 Hours") }
  /// Setting to auto archive a podcast episode. This value will auto archive the episode after 2 Days has passed.
  internal static var settingsAutoArchive2Days: String { return L10n.tr("Localizable", "settings_auto_archive_2_days", fallback: "After 2 Days") }
  /// Setting to auto archive a podcast episode. This value will auto archive the episode after 2 Weeks has passed.
  internal static var settingsAutoArchive2Weeks: String { return L10n.tr("Localizable", "settings_auto_archive_2_weeks", fallback: "After 2 Weeks") }
  /// Setting to auto archive a podcast episode. This value will auto archive the episode after 30 Days has passed.
  internal static var settingsAutoArchive30Days: String { return L10n.tr("Localizable", "settings_auto_archive_30_days", fallback: "After 30 Days") }
  /// Setting to auto archive a podcast episode. This value will auto archive the episode after 3 Months has passed.
  internal static var settingsAutoArchive3Months: String { return L10n.tr("Localizable", "settings_auto_archive_3_months", fallback: "After 3 Months") }
  /// Prompt for the toggle to include starred episodes when auto archiving.
  internal static var settingsAutoArchiveIncludeStarred: String { return L10n.tr("Localizable", "settings_auto_archive_include_starred", fallback: "Include Starred Episodes") }
  /// Subtitle for the toggle to include starred episodes when auto archiving. This is the text that will be shown when the toggle is on.
  internal static var settingsAutoArchiveIncludeStarredOffSubtitle: String { return L10n.tr("Localizable", "settings_auto_archive_include_starred_off_subtitle", fallback: "Starred episodes won't be auto archived") }
  /// Subtitle for the toggle to include starred episodes when auto archiving. This is the text that will be shown when the toggle is on.
  internal static var settingsAutoArchiveIncludeStarredOnSubtitle: String { return L10n.tr("Localizable", "settings_auto_archive_include_starred_on_subtitle", fallback: "Starred episodes will be auto archived") }
  /// Subtitle for the main section of auto archive settings. This section sets the time limits or event triggers for when episodes are auto archived.
  internal static var settingsAutoArchiveSubtitle: String { return L10n.tr("Localizable", "settings_auto_archive_subtitle", fallback: "Archive episodes after set time limits. Downloads are removed when the episode is archived.") }
  /// A common string used throughout the app. Refers to the Auto Download settings menu
  internal static var settingsAutoDownload: String { return L10n.tr("Localizable", "settings_auto_download", fallback: "Auto Download") }
  /// Label indicating the number of selected filters. '%1$@' is a placeholder for the number of filters selected.
  internal static func settingsAutoDownloadsFiltersSelectedFormat(_ p1: Any) -> String {
    return L10n.tr("Localizable", "settings_auto_downloads_filters_selected_format", String(describing: p1), fallback: "%1$@ filters selected")
  }
  /// Label indicating the number of selected filters. This is the singular form for an accompanying plural option.
  internal static var settingsAutoDownloadsFiltersSelectedSingular: String { return L10n.tr("Localizable", "settings_auto_downloads_filters_selected_singular", fallback: "1 filter selected") }
  /// Label indicating no filters have been selected.
  internal static var settingsAutoDownloadsNoFiltersSelected: String { return L10n.tr("Localizable", "settings_auto_downloads_no_filters_selected", fallback: "No Filters Selected") }
  /// Label indicating no playlists have been selected.
  internal static var settingsAutoDownloadsNoPlaylistsSelected: String { return L10n.tr("Localizable", "settings_auto_downloads_no_playlists_selected", fallback: "No Playlists Selected") }
  /// Label indicating no podcasts have been selected.
  internal static var settingsAutoDownloadsNoPodcastsSelected: String { return L10n.tr("Localizable", "settings_auto_downloads_no_podcasts_selected", fallback: "No Podcasts Selected") }
  /// Auto Downloads Setting - Auto download on follow of a blog
  internal static var settingsAutoDownloadsOnFollow: String { return L10n.tr("Localizable", "settings_auto_downloads_on_follow", fallback: "On Follow") }
  /// Label indicating the number of selected playlists. '%1$@' is a placeholder for the number of playlists selected.
  internal static func settingsAutoDownloadsPlaylistsSelectedFormat(_ p1: Any) -> String {
    return L10n.tr("Localizable", "settings_auto_downloads_playlists_selected_format", String(describing: p1), fallback: "%1$@ Playlists Selected")
  }
  /// Label indicating the number of selected playlists. This is the singular form for an accompanying plural option.
  internal static var settingsAutoDownloadsPlaylistsSelectedSingular: String { return L10n.tr("Localizable", "settings_auto_downloads_playlists_selected_singular", fallback: "1 Playlist Selected") }
  /// Label indicating the number of selected podcasts. '%1$@' is a placeholder for the number of podcasts selected.
  internal static func settingsAutoDownloadsPodcastsSelectedFormat(_ p1: Any) -> String {
    return L10n.tr("Localizable", "settings_auto_downloads_podcasts_selected_format", String(describing: p1), fallback: "%1$@ podcasts selected")
  }
  /// Label indicating the number of selected podcasts. This is the singular form for an accompanying plural option.
  internal static var settingsAutoDownloadsPodcastsSelectedSingular: String { return L10n.tr("Localizable", "settings_auto_downloads_podcasts_selected_singular", fallback: "1 podcast selected") }
  /// Subtitle explaining the toggle to auto download the top episodes of a filter.
  internal static var settingsAutoDownloadsSubtitleFilters: String { return L10n.tr("Localizable", "settings_auto_downloads_subtitle_filters", fallback: "Download the top episodes in a filter.") }
  /// Subtitle explaining the toggle to auto download New Episodes.
  internal static var settingsAutoDownloadsSubtitleNewEpisodes: String { return L10n.tr("Localizable", "settings_auto_downloads_subtitle_new_episodes", fallback: "Automatically download new episodes, save episodes from newly followed shows, and manage your storage by setting a limit on how many episodes are saved.") }
  /// Subtitle explaining the toggle to auto download the top episodes of a playlist.
  internal static var settingsAutoDownloadsSubtitlePlaylists: String { return L10n.tr("Localizable", "settings_auto_downloads_subtitle_playlists", fallback: "Download the top episodes in a playlist.") }
  /// Subtitle explaining the toggle to auto download items in the Up Next Queue.
  internal static var settingsAutoDownloadsSubtitleUpNext: String { return L10n.tr("Localizable", "settings_auto_downloads_subtitle_up_next", fallback: "Download episodes added to Up Next.") }
  /// Title of the alert shown when creating a backup fails.
  internal static var settingsBackupFailed: String { return L10n.tr("Localizable", "settings_backup_failed", fallback: "Backup Failed") }
  /// Explanation under the back up button.
  internal static var settingsBackupFooter: String { return L10n.tr("Localizable", "settings_backup_footer", fallback: "Saves your podcasts, episodes, playback history and settings to a folder you choose. Downloaded audio files aren't included.") }
  /// Button that saves a backup of the library to a user-chosen location.
  internal static var settingsBackupNow: String { return L10n.tr("Localizable", "settings_backup_now", fallback: "Back Up Library") }
  /// Title for the settings screen (and row) for backing up and restoring the library.
  internal static var settingsBackupRestore: String { return L10n.tr("Localizable", "settings_backup_restore", fallback: "Backup & Restore") }
  /// Section Header for selecting the options for setting the app badge based on the user's filters.
  internal static var settingsBadgeFilterHeader: String { return L10n.tr("Localizable", "settings_badge_filter_header", fallback: "EPISODE FILTER COUNT") }
  /// Option for setting the app badge based on the new episodes since the app opened.
  internal static var settingsBadgeNewSinceOpened: String { return L10n.tr("Localizable", "settings_badge_new_since_opened", fallback: "New Since App Opened") }
  /// Section Header for selecting the options for setting the app badge based on the user's smart playlists.
  internal static var settingsBadgeSmartPlaylistHeader: String { return L10n.tr("Localizable", "settings_badge_smart_playlist_header", fallback: "SMART PLAYLIST EPISODE COUNT") }
  /// Option for setting the app badge based on the total unplayed episodes.
  internal static var settingsBadgeTotalUnplayed: String { return L10n.tr("Localizable", "settings_badge_total_unplayed", fallback: "Total Unplayed") }
  /// Label for a setting that allows the user to enable or disable playing a tone when creating a bookmark .
  internal static var settingsBookmarkConfirmationSound: String { return L10n.tr("Localizable", "settings_bookmark_confirmation_sound", fallback: "Bookmark Confirmation Sound") }
  /// Settings section subtitle that explains what the bookmark sound section does .
  internal static var settingsBookmarkSoundFooter: String { return L10n.tr("Localizable", "settings_bookmark_sound_footer", fallback: "Play a confirmation sound after creating a bookmark with your headphones.") }
  /// Title for the button that open a page to change the avatar(a.k.a. profile picture).
  internal static var settingsChangeAvatar: String { return L10n.tr("Localizable", "settings_change_avatar", fallback: "Change Avatar") }
  /// Label displayed right next the button to opt-in/out for Analytics tracking
  internal static var settingsCollectInformation: String { return L10n.tr("Localizable", "settings_collect_information", fallback: "Collect information") }
  /// Additional information about how the information collected is and how it's used
  internal static var settingsCollectInformationAdditionalInformation: String { return L10n.tr("Localizable", "settings_collect_information_additional_information", fallback: "Allowing us to collect analytics helps us build a better app. We understand if you would prefer not to share this information.") }
  /// Title of the status page, to check the status of the user's connection.
  internal static var settingsConnectionStatus: String { return L10n.tr("Localizable", "settings_connection_status", fallback: "Connection Status") }
  /// Prompt to open the menu to create a new Siri shortcut. 'Siri' refers to Apple's voice assistant.
  internal static var settingsCreateSiriShortcut: String { return L10n.tr("Localizable", "settings_create_siri_shortcut", fallback: "Create Siri Shortcut") }
  /// Informational message to accompany a prompt to create a Siri Shortcut. 'Siri' refers to Apple's voice assistant. '%1$@' is a placeholder for the podcasts name.
  internal static func settingsCreateSiriShortcutMsg(_ p1: Any) -> String {
    return L10n.tr("Localizable", "settings_create_siri_shortcut_msg", String(describing: p1), fallback: "Create a Siri Shortcut to play the newest episode of %1$@")
  }
  /// A common string used throughout the app. Indicates an option(s) to customize the settings for this podcast.
  internal static var settingsCustom: String { return L10n.tr("Localizable", "settings_custom", fallback: "Custom For This Podcast") }
  /// A message accompanying the toggle to enable auto archive settings that are specific to the selected podcast.
  internal static var settingsCustomAutoArchiveMsg: String { return L10n.tr("Localizable", "settings_custom_auto_archive_msg", fallback: "Need more fine grained control? Enable auto-archive settings for this podcast") }
  /// A message accompanying the toggle to set custom settings for a particular podcast.
  internal static var settingsCustomMsg: String { return L10n.tr("Localizable", "settings_custom_msg", fallback: "Pocket Casts will remember your last playback effects and use them on all podcasts. You can enable this if you want to create custom ones for just this podcast.") }
  /// Settings row and screen title for per-device playback rules.
  internal static var settingsDevices: String { return L10n.tr("Localizable", "settings_devices", fallback: "Devices") }
  /// Toggle to automatically resume playback when this audio device connects.
  internal static var settingsDevicesAutoResume: String { return L10n.tr("Localizable", "settings_devices_auto_resume", fallback: "Auto-Resume on Connect") }
  /// Empty state shown when no audio devices have been seen yet.
  internal static var settingsDevicesEmpty: String { return L10n.tr("Localizable", "settings_devices_empty", fallback: "Devices you listen with will appear here after they connect, so you can choose what happens when they connect or disconnect.") }
  /// Footer explaining the per-device playback rules.
  internal static var settingsDevicesFooter: String { return L10n.tr("Localizable", "settings_devices_footer", fallback: "Auto-resume starts playback when the device connects and an episode is paused. Pause on disconnect pauses playback when the device disconnects.") }
  /// Footer showing when an audio device was last seen. '%1$@' is a placeholder for a relative date like 'yesterday'.
  internal static func settingsDevicesLastSeenFormat(_ p1: Any) -> String {
    return L10n.tr("Localizable", "settings_devices_last_seen_format", String(describing: p1), fallback: "Last seen %1$@")
  }
  /// Toggle to pause playback when this audio device disconnects.
  internal static var settingsDevicesPauseOnDisconnect: String { return L10n.tr("Localizable", "settings_devices_pause_on_disconnect", fallback: "Pause on Disconnect") }
  /// Provides a prompt for the user to configure the settings related to episode limits. This controls how many episodes will be preserved before auto archiving them.
  internal static var settingsEpisodeLimit: String { return L10n.tr("Localizable", "settings_episode_limit", fallback: "Episode Limit") }
  /// Informs the user of max episode count for the up next queue. This value is configurable. '%1$@' is a placeholder for the current value as set by the user.
  internal static func settingsEpisodeLimitFormat(_ p1: Any) -> String {
    return L10n.tr("Localizable", "settings_episode_limit_format", String(describing: p1), fallback: "%1$@ Episode Limit")
  }
  /// A format for values accompanying the setting to auto archive based on a set limit. '%1$@' is a placeholder for the number of episodes that will be saved before auto archiving the oldest ones.
  internal static func settingsEpisodeLimitLimitFormat(_ p1: Any) -> String {
    return L10n.tr("Localizable", "settings_episode_limit_limit_format", String(describing: p1), fallback: "%1$@ most recent")
  }
  /// A message accompanying the episode limit settings providing a hint towards one use case for this feature.
  internal static var settingsEpisodeLimitMsg: String { return L10n.tr("Localizable", "settings_episode_limit_msg", fallback: "For shows that release hourly or daily episodes, setting an episode limit can help keep only the most recent ones, while archiving any that are older.") }
  /// A value accompanying the setting to auto archive based on a set limit. This value disables the feature.
  internal static var settingsEpisodeLimitNoLimit: String { return L10n.tr("Localizable", "settings_episode_limit_no_limit", fallback: "No Limit") }
  /// Alert title informing the user that the OPML export has encountered an error. 'OPML' refers to the file type that will be exported.
  internal static var settingsExportError: String { return L10n.tr("Localizable", "settings_export_error", fallback: "Export Error") }
  /// Alert message informing the user that the OPML export has encountered an error. 'OPML' refers to the file type that will be exported.
  internal static var settingsExportErrorMsg: String { return L10n.tr("Localizable", "settings_export_error_msg", fallback: "Unable to export OPML, please try again later.") }
  /// Alert title informing the user that the OPML export is processing. 'OPML' refers to the file type that will be exported.
  internal static var settingsExportOpml: String { return L10n.tr("Localizable", "settings_export_opml", fallback: "Exporting OPML") }
  /// Informs the user that Pocket Casts has dedicated an issue with this podcasts feed.
  internal static var settingsFeedError: String { return L10n.tr("Localizable", "settings_feed_error", fallback: "Feed Error") }
  /// Informs the user that Pocket Casts has stopped updating this feed due to too many errors. Provides a prompt to tap the refresh button that is presented above this message box.
  internal static var settingsFeedErrorMsg: String { return L10n.tr("Localizable", "settings_feed_error_msg", fallback: "The feed for this podcast stopped updating because it had too many errors. Tap above to fix this.") }
  /// Title used in a dialog box. Prompt user to try refreshing the feed after encountering an error.
  internal static var settingsFeedFixRefresh: String { return L10n.tr("Localizable", "settings_feed_fix_refresh", fallback: "Try To Update It") }
  /// The message body for a dialog box used to inform the user the request to update the feed has failed.
  internal static var settingsFeedFixRefreshFailedMsg: String { return L10n.tr("Localizable", "settings_feed_fix_refresh_failed_msg", fallback: "Unable to update this feed, please try again later.") }
  /// The title for a dialog box used to inform the user that the request to update the feed has failed.
  internal static var settingsFeedFixRefreshFailedTitle: String { return L10n.tr("Localizable", "settings_feed_fix_refresh_failed_title", fallback: "Update Failed") }
  /// The message body for a dialog box used to inform the user that the an update to the feed has been queued.
  internal static var settingsFeedFixRefreshSuccessMsg: String { return L10n.tr("Localizable", "settings_feed_fix_refresh_success_msg", fallback: "We've queued an update for this podcast. Our server will re-check it and if it works you should have new episodes soon. Please check back in about an hour.") }
  /// The title for a dialog box used to inform the user that the an update to the feed has been queued.
  internal static var settingsFeedFixRefreshSuccessTitle: String { return L10n.tr("Localizable", "settings_feed_fix_refresh_success_title", fallback: "Update Queued") }
  /// Informs the user that Pocket Casts has dedicated an issue with this podcasts feed.
  internal static var settingsFeedIssue: String { return L10n.tr("Localizable", "settings_feed_issue", fallback: "Feed Issue") }
  /// Informs the user that Pocket Casts has stopped updating this feed due to too many errors.
  internal static var settingsFeedIssueMsg: String { return L10n.tr("Localizable", "settings_feed_issue_msg", fallback: "The feed for this podcast stopped updating because it had too many errors.") }
  /// Title for the file-sync settings screen and Settings row.
  internal static var settingsFileSync: String { return L10n.tr("Localizable", "settings_file_sync", fallback: "File Sync") }
  /// Prompt to navigate the user to the files setting screen.
  internal static var settingsFiles: String { return L10n.tr("Localizable", "settings_files", fallback: "Files Settings") }
  /// Subtitle for the toggle to auto add new files to the Up Next Queue.
  internal static var settingsFilesAddUpNextSubtitle: String { return L10n.tr("Localizable", "Settings_files_add_up_next_subtitle", fallback: "Add new files to Up Next automatically") }
  /// Prompt for the toggle to enable the option to delete the local file after playing.
  internal static var settingsFilesDeleteLocalFile: String { return L10n.tr("Localizable", "settings_files_delete_local_file", fallback: "Delete Local File") }
  /// Label displayed next to the toggle to opt-in/out for First-Party Analytics tracking
  internal static var settingsFirstPartyAnalytics: String { return L10n.tr("Localizable", "settings_first_party_analytics", fallback: "First-party analytics") }
  /// A common string used throughout the app. Reference to the General settings menu.
  internal static var settingsGeneral: String { return L10n.tr("Localizable", "settings_general", fallback: "General") }
  /// Confirmation to apply a setting change to all podcasts.
  internal static var settingsGeneralApplyAllConf: String { return L10n.tr("Localizable", "settings_general_apply_all_conf", fallback: "Apply to existing") }
  /// Prompt to apply a setting change to all podcasts.
  internal static var settingsGeneralApplyAllTitle: String { return L10n.tr("Localizable", "settings_general_apply_all_title", fallback: "Apply to existing podcasts?") }
  /// Setting option to choose the default display archived episodes.
  internal static var settingsGeneralArchivedEpisodes: String { return L10n.tr("Localizable", "settings_general_archived_episodes", fallback: "Archived Episodes") }
  /// Prompt to ask the user if they'd like to show/hide archived episodes for all podcasts. '%1$@' is a placeholder for a localized string 'show' or 'hide' based on the current setting.
  internal static func settingsGeneralArchivedEpisodesPromptFormat(_ p1: Any) -> String {
    return L10n.tr("Localizable", "settings_general_archived_episodes_prompt_format", String(describing: p1), fallback: "Would you like to change all your existing podcasts to %1$@ archived episodes?")
  }
  /// Setting toggle to enable the feature to automatically open the player when playback starts.
  internal static var settingsGeneralAutoOpenPlayer: String { return L10n.tr("Localizable", "settings_general_auto_open_player", fallback: "Open Player Automatically") }
  /// Setting toggle to modify if a new episode is played after the current one ends. In most languages we believe Autoplay is understandable and might not need a translation.
  internal static var settingsGeneralAutoplay: String { return L10n.tr("Localizable", "settings_general_autoplay", fallback: "Autoplay") }
  /// Subtitle explaining the toggle to modify if a new episode will be reproduced after the current one ends.
  internal static var settingsGeneralAutoplaySubtitle: String { return L10n.tr("Localizable", "settings_general_autoplay_subtitle", fallback: "If your Up Next queue is empty, we'll play episodes from the same podcast or list you're currently listening to.") }
  /// Section header for the general settings that are more general app related.
  internal static var settingsGeneralDefaultsHeader: String { return L10n.tr("Localizable", "settings_general_defaults_header", fallback: "DEFAULTS") }
  /// Setting option to choose the primary way in which episodes are grouped.
  internal static var settingsGeneralEpisodeGroups: String { return L10n.tr("Localizable", "settings_general_episode_groups", fallback: "Podcast Episode Grouping") }
  /// Setting option to choose to hide archived episodes.
  internal static var settingsGeneralHide: String { return L10n.tr("Localizable", "settings_general_hide", fallback: "Hide") }
  /// Setting toggle to enable the app to keep your screen awake.
  internal static var settingsGeneralKeepScreenAwake: String { return L10n.tr("Localizable", "settings_general_keep_screen_awake", fallback: "Keep Screen Awake") }
  /// Setting toggle to modify which bluetooth protocol to use.
  internal static var settingsGeneralLegacyBluetooth: String { return L10n.tr("Localizable", "settings_general_legacy_bluetooth", fallback: "Legacy Bluetooth Support") }
  /// Subtitle explaining the toggle to modify which bluetooth protocol to use.
  internal static var settingsGeneralLegacyBluetoothSubtitle: String { return L10n.tr("Localizable", "settings_general_legacy_bluetooth_subtitle", fallback: "If you have a Bluetooth Device or Car Stereo that seems to be pausing Pocket Casts while it's playing, or resetting the playback position to 0, try turning this setting on to fix it.") }
  /// Setting toggle to enable the feature that disables the lock screen scrubber.
  internal static var settingsGeneralLockScreenDisabled: String { return L10n.tr("Localizable", "settings_general_lock_screen_disabled", fallback: "Enable Lock Screen Scrubbing") }
  /// Setting toggle to enable the gesture for multi-select.
  internal static var settingsGeneralMultiSelectGesture: String { return L10n.tr("Localizable", "settings_general_multi_select_gesture", fallback: "Multi-select Gesture") }
  /// Subtitle explaining the toggle to enable the gesture for multi-select.
  internal static var settingsGeneralMultiSelectGestureSubtitle: String { return L10n.tr("Localizable", "settings_general_multi_select_gesture_subtitle", fallback: "Multi-select by dragging 2 fingers down on any episode list. Turn this off if you find yourself triggering this accidentally or it interferes with the accessibility features you use.") }
  /// Option to not move forward with a prompt to apply to all podcasts.
  internal static var settingsGeneralNoThanks: String { return L10n.tr("Localizable", "settings_general_no_thanks", fallback: "No thanks") }
  /// Toggle in General settings enabling loudness normalization playback (gain to a target level, no compression)
  internal static var settingsGeneralNormalizeVolume: String { return L10n.tr("Localizable", "settings_general_normalize_volume", fallback: "Normalize Volume") }
  /// Footer explaining the Normalize Volume toggle
  internal static var settingsGeneralNormalizeVolumeSubtitle: String { return L10n.tr("Localizable", "settings_general_normalize_volume_subtitle", fallback: "Play every episode at a consistent loudness. Gentle level matching only — no compression. When Volume Boost is on it takes over, since it already normalizes.") }
  /// Setting toggle to enable the app to open the links in an external browser.
  internal static var settingsGeneralOpenInBrowser: String { return L10n.tr("Localizable", "settings_general_open_in_browser", fallback: "Open Links In Browser") }
  /// Setting toggle to modify what controls are available on the lock screen.
  internal static var settingsGeneralPlayBackActions: String { return L10n.tr("Localizable", "settings_general_play_back_actions", fallback: "Extra Playback Actions") }
  /// Subtitle explaining the toggle to modify what controls are available on the lock screen.
  internal static var settingsGeneralPlayBackActionsSubtitle: String { return L10n.tr("Localizable", "settings_general_play_back_actions_subtitle", fallback: "Adds a star option to your phone lock screen.") }
  /// Section header for the general settings that are more player related.
  internal static var settingsGeneralPlayerHeader: String { return L10n.tr("Localizable", "settings_general_player_header", fallback: "PLAYER") }
  /// Setting toggle to enable publishing chapter titles to the device's "Now Playing Info Center" data used by bluetooth and other connected devices.
  internal static var settingsGeneralPublishChapterTitles: String { return L10n.tr("Localizable", "settings_general_publish_chapter_titles", fallback: "Publish Chapter Titles") }
  /// Subtitle explaining the toggle to publish chapter titles.
  internal static var settingsGeneralPublishChapterTitlesSubtitle: String { return L10n.tr("Localizable", "settings_general_publish_chapter_titles_subtitle", fallback: "If on, this will send chapter titles over Bluetooth and other connected devices instead of the episode title.") }
  /// Setting toggle to change the behavior of the skip button on external devices.
  internal static var settingsGeneralRemoteSkipsChapters: String { return L10n.tr("Localizable", "settings_general_remote_skips_chapters", fallback: "Remote Skips Chapters") }
  /// Subtitle explaining the toggle to change the behavior of the skip button on external devices.
  internal static var settingsGeneralRemoteSkipsChaptersSubtitle: String { return L10n.tr("Localizable", "settings_general_remote_skips_chapters_subtitle", fallback: "When enabled and an episode has chapters, pressing the skip button in your car or headphones will skip to the next chapter.") }
  /// Prompt to ask the user if they'd like to remove the grouping from all podcasts.
  internal static var settingsGeneralRemoveGroupsApplyAll: String { return L10n.tr("Localizable", "settings_general_remove_groups_apply_all", fallback: "Would you like to change all your existing podcasts to be not be grouped as well?") }
  /// Setting option to choose the default action when selecting an episode row.
  internal static var settingsGeneralRowAction: String { return L10n.tr("Localizable", "settings_general_row_action", fallback: "Row Action") }
  /// Setting toggle that makes repeated skip button taps grow the skip interval.
  internal static var settingsGeneralSeekAcceleration: String { return L10n.tr("Localizable", "settings_general_seek_acceleration", fallback: "Skip Acceleration") }
  /// Subtitle explaining the toggle that makes repeated skip button taps grow the skip interval.
  internal static var settingsGeneralSeekAccelerationSubtitle: String { return L10n.tr("Localizable", "settings_general_seek_acceleration_subtitle", fallback: "Quickly tapping skip several times in a row increases how far each skip jumps.") }
  /// Prompt to ask the user if they'd like to apply the grouping to all podcasts. '%1$@' is a placeholder for a localized name for the grouping type.
  internal static func settingsGeneralSelectedGroupApplyAll(_ p1: Any) -> String {
    return L10n.tr("Localizable", "settings_general_selected_group_apply_all", String(describing: p1), fallback: "Would you like to change all your existing podcasts to be grouped by %1$@?")
  }
  /// Setting option to choose to show archived episodes.
  internal static var settingsGeneralShow: String { return L10n.tr("Localizable", "settings_general_show", fallback: "Show") }
  /// Setting toggle to enable the feature that adjusts the playback position when resuming.
  internal static var settingsGeneralSmartPlayback: String { return L10n.tr("Localizable", "settings_general_smart_playback", fallback: "Intelligent Playback Resumption") }
  /// Subtitle explaining the feature that adjusts the playback position when resuming.
  internal static var settingsGeneralSmartPlaybackSubtitle: String { return L10n.tr("Localizable", "settings_general_smart_playback_subtitle", fallback: "If on, Pocket Casts will go back a little in episodes you resume so you can catch up more comfortably.") }
  /// Setting toggle that makes tapping an episode row play it immediately instead of opening the episode details.
  internal static var settingsGeneralTapToPlay: String { return L10n.tr("Localizable", "settings_general_tap_to_play", fallback: "Play Episodes On Tap") }
  /// Subtitle explaining the toggle that makes tapping an episode row play it immediately. This is used when the toggle is off.
  internal static var settingsGeneralTapToPlayOffSubtitle: String { return L10n.tr("Localizable", "settings_general_tap_to_play_off_subtitle", fallback: "Tapping an episode in a list opens its details. Turn on to play episodes with a single tap instead.") }
  /// Subtitle explaining the toggle that makes tapping an episode row play it immediately. This is used when the toggle is on.
  internal static var settingsGeneralTapToPlayOnSubtitle: String { return L10n.tr("Localizable", "settings_general_tap_to_play_on_subtitle", fallback: "Tapping an episode in a list plays it immediately. Swipe on an episode and choose Details to see its options. Turn off to open episode details on tap.") }
  /// Setting option to choose how to handle swiping to add something to the queue.
  internal static var settingsGeneralUpNextSwipe: String { return L10n.tr("Localizable", "settings_general_up_next_swipe", fallback: "Up Next Swipe") }
  /// Setting toggle to modify how a tap is handled in the up next queue.
  internal static var settingsGeneralUpNextTap: String { return L10n.tr("Localizable", "settings_general_up_next_tap", fallback: "Play Up Next On Tap") }
  /// Subtitle explaining the toggle to modify how a tap is handled in the up next queue. This is used when the toggle is off.
  internal static var settingsGeneralUpNextTapOffSubtitle: String { return L10n.tr("Localizable", "settings_general_up_next_tap_off_subtitle", fallback: "Tapping an episode in Up Next shows the actions page. Long press plays the episode. Turn on to switch these around.") }
  /// Subtitle explaining the toggle to modify how a tap is handled in the up next queue. This is used when the toggle is on.
  internal static var settingsGeneralUpNextTapOnSubtitle: String { return L10n.tr("Localizable", "settings_general_up_next_tap_on_subtitle", fallback: "Tapping an episode in Up Next will play it. Long press shows episode options. Turn off to switch these around.") }
  /// Title for the VoiceBoostN setting in Settings > General
  internal static var settingsGeneralVoiceBoostN: String { return L10n.tr("Localizable", "settings_general_voice_boost_n", fallback: "VoiceBoostN") }
  /// Subtitle for the VoiceBoostN setting in Settings > General
  internal static var settingsGeneralVoiceBoostNSubtitle: String { return L10n.tr("Localizable", "settings_general_voice_boost_n_subtitle", fallback: "Use updated Volume Boost with more consistent voice levels.") }
  /// Title for the menu that takes you to the global up next queue settings
  internal static var settingsGlobalSettings: String { return L10n.tr("Localizable", "settings_global_settings", fallback: "Global Settings") }
  /// Label for a settings menu that allows the user to customize headphone action.
  internal static var settingsHeadphoneControls: String { return L10n.tr("Localizable", "settings_headphone_controls", fallback: "Headphone Controls") }
  /// Settings section subtitle that explains what the section does .
  internal static var settingsHeadphoneControlsFooter: String { return L10n.tr("Localizable", "settings_headphone_controls_footer", fallback: "Customise the actions done by the most common headphone controls.") }
  /// A common string used throughout the app. Refers to the Help & Feedback settings menu
  internal static var settingsHelp: String { return L10n.tr("Localizable", "settings_help", fallback: "Help & Feedback") }
  /// Settings section subtitle explaining the highlight capture confirmation options. A haptic always plays.
  internal static var settingsHighlightConfirmationFooter: String { return L10n.tr("Localizable", "settings_highlight_confirmation_footer", fallback: "Choose how saving a highlight is confirmed while listening. A gentle haptic always plays.") }
  /// Label for the setting that picks how a saved highlight is confirmed (sound, spoken, both, or nothing).
  internal static var settingsHighlightConfirmationStyle: String { return L10n.tr("Localizable", "settings_highlight_confirmation_style", fallback: "Capture Confirmation") }
  /// Title of the Highlights settings screen (capture behavior + Markdown export).
  internal static var settingsHighlights: String { return L10n.tr("Localizable", "settings_highlights", fallback: "Highlights") }
  /// Section header for capture-behavior options on the Highlights settings screen.
  internal static var settingsHighlightsCaptureSection: String { return L10n.tr("Localizable", "settings_highlights_capture_section", fallback: "Capture") }
  /// Button that starts choosing a folder for the Markdown export.
  internal static var settingsHighlightsExportChooseFolder: String { return L10n.tr("Localizable", "settings_highlights_export_choose_folder", fallback: "Choose Export Folder…") }
  /// Button that turns the folder export off.
  internal static var settingsHighlightsExportDisable: String { return L10n.tr("Localizable", "settings_highlights_export_disable", fallback: "Stop Exporting") }
  /// Row showing the currently selected export folder.
  internal static var settingsHighlightsExportFolder: String { return L10n.tr("Localizable", "settings_highlights_export_folder", fallback: "Folder") }
  /// Footer explaining the Markdown folder export.
  internal static var settingsHighlightsExportFooter: String { return L10n.tr("Localizable", "settings_highlights_export_footer", fallback: "Writes one Markdown file per episode into the folder you choose — works great with Obsidian, Logseq, or any notes vault. Files are updated automatically as you capture and edit highlights.") }
  /// Button that immediately re-exports every episode's highlights.
  internal static var settingsHighlightsExportNow: String { return L10n.tr("Localizable", "settings_highlights_export_now", fallback: "Export All Now") }
  /// Section header for the Markdown folder export on the Highlights settings screen.
  internal static var settingsHighlightsExportSection: String { return L10n.tr("Localizable", "settings_highlights_export_section", fallback: "Markdown Export") }
  /// Placeholder for the optional free-text style preference for AI highlight titles.
  internal static var settingsHighlightsPromptCustomPlaceholder: String { return L10n.tr("Localizable", "settings_highlights_prompt_custom_placeholder", fallback: "Optional style preference (e.g. \"always name the speaker\")") }
  /// Picker label for how AI writes highlight titles.
  internal static var settingsHighlightsPromptStyle: String { return L10n.tr("Localizable", "settings_highlights_prompt_style", fallback: "Title Style") }
  /// Button that validates and saves the Readwise token.
  internal static var settingsHighlightsReadwiseConnect: String { return L10n.tr("Localizable", "settings_highlights_readwise_connect", fallback: "Connect") }
  /// Row confirming the Readwise account is connected.
  internal static var settingsHighlightsReadwiseConnected: String { return L10n.tr("Localizable", "settings_highlights_readwise_connected", fallback: "Connected") }
  /// Button that removes the stored Readwise token.
  internal static var settingsHighlightsReadwiseDisconnect: String { return L10n.tr("Localizable", "settings_highlights_readwise_disconnect", fallback: "Disconnect") }
  /// Footer explaining the Readwise integration.
  internal static var settingsHighlightsReadwiseFooter: String { return L10n.tr("Localizable", "settings_highlights_readwise_footer", fallback: "New and edited highlights are pushed to your Readwise account, which can forward them to Notion, Roam, and more. Your token is stored securely on this device.") }
  /// Error shown when the Readwise token is rejected by the API.
  internal static var settingsHighlightsReadwiseInvalidToken: String { return L10n.tr("Localizable", "settings_highlights_readwise_invalid_token", fallback: "That token wasn't accepted. Copy it from readwise.io/access_token and try again.") }
  /// Shown when Readwise rejected the previously saved token (revoked or rotated on readwise.io); syncing is paused until a new token is entered.
  internal static var settingsHighlightsReadwiseReconnect: String { return L10n.tr("Localizable", "settings_highlights_readwise_reconnect", fallback: "Readwise rejected the saved token and syncing is paused. Enter a new token to resume.") }
  /// Section header for the Readwise integration on the Highlights settings screen.
  internal static var settingsHighlightsReadwiseSection: String { return L10n.tr("Localizable", "settings_highlights_readwise_section", fallback: "Readwise") }
  /// Placeholder for the Readwise access-token field.
  internal static var settingsHighlightsReadwiseTokenPlaceholder: String { return L10n.tr("Localizable", "settings_highlights_readwise_token_placeholder", fallback: "Access token") }
  /// Button label while the Readwise token is being validated.
  internal static var settingsHighlightsReadwiseValidating: String { return L10n.tr("Localizable", "settings_highlights_readwise_validating", fallback: "Validating…") }
  /// Toggle for the weekly notification resurfacing an old highlight.
  internal static var settingsHighlightsResurfacing: String { return L10n.tr("Localizable", "settings_highlights_resurfacing", fallback: "Weekly Highlight Reminder") }
  /// Toggle: open the highlight editor right after each in-app capture.
  internal static var settingsHighlightsReviewAfterCapture: String { return L10n.tr("Localizable", "settings_highlights_review_after_capture", fallback: "Review After Capture") }
  /// Title for the screen that manages the importing and exporting of podcasts.
  internal static var settingsImportExport: String { return L10n.tr("Localizable", "settings_import_export", fallback: "Import / Export") }
  /// Informs the user that the current podcast is included in one filter. '%1$@' is a placeholder for the number of filters this podcast is included in.
  internal static func settingsInFiltersPluralFormat(_ p1: Any) -> String {
    return L10n.tr("Localizable", "settings_in_filters_plural_format", String(describing: p1), fallback: "Included In %1$@ Filters")
  }
  /// Informs the user that the current podcast is included in one filter. This is the singular form of an accompanying plural string.
  internal static var settingsInFiltersSingular: String { return L10n.tr("Localizable", "settings_in_filters_singular", fallback: "Included In 1 Filter") }
  /// Setting section header. Indicates that the options in this section will appear in the menu vs an action bar.
  internal static var settingsInMenu: String { return L10n.tr("Localizable", "settings_in_menu", fallback: "IN MENU") }
  /// Informs the user that the current podcast is included in one Smart Playlist. This is the singular form of an accompanying plural string.
  internal static var settingsInSmartPlaylistSingular: String { return L10n.tr("Localizable", "settings_in_smart_playlist_singular", fallback: "Included In 1 Smart Playlist") }
  /// Informs the user that the current podcast is included in more Smart Playlists. '%1$@' is a placeholder for the number of filters this podcast is included in.
  internal static func settingsInSmartPlaylistsPluralFormat(_ p1: Any) -> String {
    return L10n.tr("Localizable", "settings_in_smart_playlists_plural_format", String(describing: p1), fallback: "Included In %1$@ Smart Playlists")
  }
  /// A message accompanying the settings for inactive episodes explaining what is considered an inactive episode.
  internal static var settingsInactiveEpisodesMsg: String { return L10n.tr("Localizable", "settings_inactive_episodes_msg", fallback: "Inactive episodes are episodes you haven't played or downloaded in the time you specify above. Downloads are removed when the episode is archived.") }
  /// Label for a setting that allows the user to custom the customize a headphone button skip next action.
  internal static var settingsNextAction: String { return L10n.tr("Localizable", "settings_next_action", fallback: "Next Action") }
  /// Informs the user that the current podcast isn't included in any filters.
  internal static var settingsNotInFilters: String { return L10n.tr("Localizable", "settings_not_in_filters", fallback: "Not Included In Any Filters") }
  /// Informs the user that the current podcast isn't included in any playlists.
  internal static var settingsNotInSmartPlaylists: String { return L10n.tr("Localizable", "settings_not_in_smart_playlists", fallback: "Not Included In Any Smart Playlists") }
  /// A common string used throughout the app. Refers to the Notifications settings menu.
  internal static var settingsNotifications: String { return L10n.tr("Localizable", "settings_notifications", fallback: "Notifications") }
  /// App badge choice to have the badge reflect the filter count
  internal static var settingsNotificationsFilterCount: String { return L10n.tr("Localizable", "settings_notifications_filter_count", fallback: "Filter count") }
  /// App badge choice to have the badge reflect the smart playlist count
  internal static var settingsNotificationsSmartPlaylistCount: String { return L10n.tr("Localizable", "settings_notifications_smart_playlist_count", fallback: "Smart Playlist count") }
  /// Subtitle explaining what notifications to expect when you enable notifications.
  internal static var settingsNotificationsSubtitle: String { return L10n.tr("Localizable", "settings_notifications_subtitle", fallback: "Notifies you when a new episode is available. Also useful for improving the reliability of auto downloads.") }
  /// A common string used throughout the app. Refers to the Import/Export OPML settings menu
  internal static var settingsOpml: String { return L10n.tr("Localizable", "settings_opml", fallback: "Import/Export OPML") }
  /// Provides a prompt for the user to configure the playback speed options.
  internal static var settingsPlaySpeed: String { return L10n.tr("Localizable", "settings_play_speed", fallback: "Play Speed") }
  /// Informational label breaking down the pricing structure for Pocket Casts Plus. '%1$@' is a placeholder for the localized price if paid per month, '%2$@' is a placeholder for the localized price if paid per year
  internal static func settingsPlusPricingFormat(_ p1: Any, _ p2: Any) -> String {
    return L10n.tr("Localizable", "settings_plus_pricing_format", String(describing: p1), String(describing: p2), fallback: "%1$@ per month / %2$@ per year")
  }
  /// Label for a setting that allows the user to custom the customize a headphone button skip back action.
  internal static var settingsPreviousAction: String { return L10n.tr("Localizable", "settings_previous_action", fallback: "Previous Action") }
  /// A common string used throughout the app. Refers to the Privacy settings menu
  internal static var settingsPrivacy: String { return L10n.tr("Localizable", "settings_privacy", fallback: "Privacy") }
  /// Title for the options to configure the queue position when a podcast is set to be auto added to the up next queue.
  internal static var settingsQueuePosition: String { return L10n.tr("Localizable", "settings_queue_position", fallback: "Position in Queue") }
  /// Label for an input that takes the user to the privacy policy
  internal static var settingsReadPrivacyPolicy: String { return L10n.tr("Localizable", "settings_read_privacy_policy", fallback: "Read privacy policy") }
  /// Settings action that re-indexes every episode and highlight into iOS Spotlight search
  internal static var settingsRebuildSpotlightIndex: String { return L10n.tr("Localizable", "settings_rebuild_spotlight_index", fallback: "Rebuild Spotlight Index") }
  /// Toast confirming the Spotlight re-index kicked off in the background
  internal static var settingsRebuildSpotlightIndexStarted: String { return L10n.tr("Localizable", "settings_rebuild_spotlight_index_started", fallback: "Rebuilding Spotlight index…") }
  /// Button that restores the library from a previously saved backup.
  internal static var settingsRestore: String { return L10n.tr("Localizable", "settings_restore", fallback: "Restore From Backup") }
  /// Message of the confirmation shown before restoring from a backup.
  internal static var settingsRestoreConfirmMessage: String { return L10n.tr("Localizable", "settings_restore_confirm_message", fallback: "This replaces your current library and settings with the backup. This can't be undone.") }
  /// Title of the confirmation shown before restoring from a backup.
  internal static var settingsRestoreConfirmTitle: String { return L10n.tr("Localizable", "settings_restore_confirm_title", fallback: "Restore From Backup?") }
  /// Message of the alert shown when a restore finishes successfully.
  internal static var settingsRestoreDoneMessage: String { return L10n.tr("Localizable", "settings_restore_done_message", fallback: "Your library has been restored. Restart Pocket Casts to make sure everything is refreshed.") }
  /// Title of the alert shown when a restore finishes successfully.
  internal static var settingsRestoreDoneTitle: String { return L10n.tr("Localizable", "settings_restore_done_title", fallback: "Restore Complete") }
  /// Title of the alert shown when restoring from a backup fails.
  internal static var settingsRestoreFailed: String { return L10n.tr("Localizable", "settings_restore_failed", fallback: "Restore Failed") }
  /// Explanation under the restore button.
  internal static var settingsRestoreFooter: String { return L10n.tr("Localizable", "settings_restore_footer", fallback: "Replaces this device's library and settings with a previously saved backup.") }
  /// Message of the alert shown when the chosen folder does not contain a valid backup.
  internal static var settingsRestoreInvalidBackup: String { return L10n.tr("Localizable", "settings_restore_invalid_backup", fallback: "The selected folder doesn't contain a Pocket Casts backup.") }
  /// Prompt to select a filter
  internal static var settingsSelectFilterSingular: String { return L10n.tr("Localizable", "settings_select_filter_singular", fallback: "Select Filter") }
  /// Prompt to select filters
  internal static var settingsSelectFiltersPlural: String { return L10n.tr("Localizable", "settings_select_filters_plural", fallback: "Select Filters") }
  /// Prompt to select a playlist
  internal static var settingsSelectPlaylistSingular: String { return L10n.tr("Localizable", "settings_select_playlist_singular", fallback: "Select Playlist") }
  /// Prompt to select playlists
  internal static var settingsSelectPlaylistsPlural: String { return L10n.tr("Localizable", "settings_select_playlists_plural", fallback: "Select Playlists") }
  /// Prompt to select smart playlists
  internal static var settingsSelectSmartPlaylistsPlural: String { return L10n.tr("Localizable", "settings_select_smart_playlists_plural", fallback: "Select Smart Playlists") }
  /// Option for the filter Siri Shortcut. This sets the app to open the filter when the shortcut is triggered.
  internal static var settingsShortcutsFilterOpenFilter: String { return L10n.tr("Localizable", "settings_shortcuts_filter_open_filter", fallback: "Open Filter") }
  /// Option for the filter Siri Shortcut. This sets the app to open the playlist when the shortcut is triggered.
  internal static var settingsShortcutsFilterOpenPlaylist: String { return L10n.tr("Localizable", "settings_shortcuts_filter_open_playlist", fallback: "Open Playlist") }
  /// Option for the filter Siri Shortcut. This sets the filter to play all episodes in the filter when the shortcut is triggered.
  internal static var settingsShortcutsFilterPlayAllEpisodes: String { return L10n.tr("Localizable", "settings_shortcuts_filter_play_all_episodes", fallback: "Play all episodes") }
  /// Option for the filter Siri Shortcut. This sets the filter to play the top episode in the filter when the shortcut is triggered.
  internal static var settingsShortcutsFilterPlayTopEpisode: String { return L10n.tr("Localizable", "settings_shortcuts_filter_play_top_episode", fallback: "Play the top episode") }
  /// Prompt to open the menu to interact with a pre-configured Siri shortcut. 'Siri' refers to Apple's voice assistant.
  internal static var settingsSiriShortcut: String { return L10n.tr("Localizable", "settings_siri_shortcut", fallback: "Siri Shortcut") }
  /// Informational message that accompanies an existing Siri shortcut for a particular podcast. 'Siri' refers to Apple's voice assistant. '%1$@' is a placeholder for the podcasts name.
  internal static func settingsSiriShortcutMsg(_ p1: Any) -> String {
    return L10n.tr("Localizable", "settings_siri_shortcut_msg", String(describing: p1), fallback: "A Siri Shortcut to play the top episode in %1$@")
  }
  /// A common string used throughout the app. Refers to the Siri Shortcuts settings menu. 'Siri' refers to Apple's voice assistant.
  internal static var settingsSiriShortcuts: String { return L10n.tr("Localizable", "settings_siri_shortcuts", fallback: "Siri Shortcuts") }
  /// Section header for the available Siri shortcuts (not yet enabled).
  internal static var settingsSiriShortcutsAvailable: String { return L10n.tr("Localizable", "settings_siri_shortcuts_available", fallback: "Available shortcuts") }
  /// Section header for the enabled Siri shortcuts.
  internal static var settingsSiriShortcutsEnabled: String { return L10n.tr("Localizable", "settings_siri_shortcuts_enabled", fallback: "Enabled shortcuts") }
  /// Option to create a Siri Shortcut to a specific filter.
  internal static var settingsSiriShortcutsSpecificFilter: String { return L10n.tr("Localizable", "settings_siri_shortcuts_specific_filter", fallback: "Shortcut to a specific filter") }
  /// Option to create a Siri Shortcut to a specific playlist.
  internal static var settingsSiriShortcutsSpecificPlaylist: String { return L10n.tr("Localizable", "settings_siri_shortcuts_specific_playlist", fallback: "Shortcut to a specific playlist") }
  /// Option to create a Siri Shortcut to a specific podcast.
  internal static var settingsSiriShortcutsSpecificPodcast: String { return L10n.tr("Localizable", "settings_siri_shortcuts_specific_podcast", fallback: "Shortcut to a specific podcast") }
  /// Prompt to open the configurable options to have the podcast skip an initial portion of the selected podcast.
  internal static var settingsSkipFirst: String { return L10n.tr("Localizable", "settings_skip_first", fallback: "Skip First") }
  /// Prompt to open the configurable options to have the podcast skip the final portion of the selected podcast.
  internal static var settingsSkipLast: String { return L10n.tr("Localizable", "settings_skip_last", fallback: "Skip Last") }
  /// Fun informational message about the skip options available in the settings.
  internal static var settingsSkipMsg: String { return L10n.tr("Localizable", "settings_skip_msg", fallback: "Skip intro and outro music like the power user you were born to be.") }
  /// A common string used throughout the app. Refers to the Stats settings menu
  internal static var settingsStats: String { return L10n.tr("Localizable", "settings_stats", fallback: "Stats") }
  /// Title for the service being checked, in this case, the Pocket Cast's Account Service.
  internal static var settingsStatusAccountService: String { return L10n.tr("Localizable", "settings_status_account_service", fallback: "Account Service") }
  /// Description for the Account Service check.
  internal static var settingsStatusAccountServiceDescription: String { return L10n.tr("Localizable", "settings_status_account_service_description", fallback: "The service used to store episode progress, subscriptions, filters, etc.") }
  /// Failure message for the Account Service check when the capability manifest cannot be fetched.
  internal static var settingsStatusCapabilitiesFailureMessage: String { return L10n.tr("Localizable", "settings_status_capabilities_failure_message", fallback: "The attested capability manifest is unavailable.") }
  /// Label explaining the purpose of the Status Page
  internal static var settingsStatusDescription: String { return L10n.tr("Localizable", "settings_status_description", fallback: "Check your connection with important services. This helps diagnose issues with your network, proxies, VPN, ad-blocking and security apps.") }
  /// Title for the service being checked, in this case, the Pocket Cast's Discover & Search.
  internal static var settingsStatusDiscover: String { return L10n.tr("Localizable", "settings_status_discover", fallback: "Discover & Search") }
  /// Description for the Discover & Search check.
  internal static var settingsStatusDiscoverDescription: String { return L10n.tr("Localizable", "settings_status_discover_description", fallback: "The discover section of the app, including podcast search.") }
  /// Failure message for the Discover & Search check when its representative routes fail.
  internal static var settingsStatusDiscoverFailureMessage: String { return L10n.tr("Localizable", "settings_status_discover_failure_message", fallback: "Representative discover or generated-artwork routes failed.") }
  /// Title for the service being checked, in this case, whether the network is considered expensive.
  internal static var settingsStatusExpensiveNetwork: String { return L10n.tr("Localizable", "settings_status_expensive_network", fallback: "Unmetered Wifi") }
  /// Description for the expensive network check.
  internal static var settingsStatusExpensiveNetworkDescription: String { return L10n.tr("Localizable", "settings_status_expensive_network_description", fallback: "If successful, this network will be used for downloads on Unmetered Wifi.") }
  /// Failure message for the expensive network check.
  internal static var settingsStatusExpensiveNetworkFailureMessage: String { return L10n.tr("Localizable", "settings_status_expensive_network_failure_message", fallback: "Your current network is marked as expensive. Try switching to Wi-Fi or disabling Low Data Mode.") }
  /// Title for the service being checked, in this case, a podcast host URL.
  internal static var settingsStatusHost: String { return L10n.tr("Localizable", "settings_status_host", fallback: "Common Podcast Hosts") }
  /// Description for the podcast host check.
  internal static var settingsStatusHostDescription: String { return L10n.tr("Localizable", "settings_status_host_description", fallback: "Podcast authors host episode files in various hosting providers not managed by Pocket Casts.") }
  /// Failure message for the podcast host check.
  internal static var settingsStatusHostFailureMessage: String { return L10n.tr("Localizable", "settings_status_host_failure_message", fallback: "The most common cause is that you have an ad-blocker configured on your phone or network. You’ll need to unblock this domain to download podcasts. Please note Pocket Casts doesn’t host or choose where podcasts are hosted, that’s up to the author of the show and is out of our control.") }
  /// Title for the service being checked, in this case, the Internet connection.
  internal static var settingsStatusInternet: String { return L10n.tr("Localizable", "settings_status_internet", fallback: "Internet") }
  /// Description for the Internet check.
  internal static var settingsStatusInternetDescription: String { return L10n.tr("Localizable", "settings_status_internet_description", fallback: "Check the status of your network.") }
  /// Failure message for the Internet check.
  internal static var settingsStatusInternetFailureMessage: String { return L10n.tr("Localizable", "settings_status_internet_failure_message", fallback: "Unable to connect to the internet. Try connecting on a different network (e.g. mobile data).") }
  /// Failure message for the Refresh Service check when the backend liveness probe does not answer.
  internal static var settingsStatusLivenessFailureMessage: String { return L10n.tr("Localizable", "settings_status_liveness_failure_message", fallback: "The configured podcast backend did not answer its liveness check.") }
  /// Title for the service being checked, in this case, the pinned podcast server origin.
  internal static var settingsStatusOrigin: String { return L10n.tr("Localizable", "settings_status_origin", fallback: "Podcast server origin") }
  /// Description for the server origin check.
  internal static var settingsStatusOriginDescription: String { return L10n.tr("Localizable", "settings_status_origin_description", fallback: "The build origin is pinned on first launch and cannot change across app updates.") }
  /// Failure message for the server origin check.
  internal static var settingsStatusOriginFailureMessage: String { return L10n.tr("Localizable", "settings_status_origin_failure_message", fallback: "Reinstall is required before this build can use its configured server.") }
  /// Line on the status page when the build's server origin is invalid.
  internal static var settingsStatusOriginInvalid: String { return L10n.tr("Localizable", "settings_status_origin_invalid", fallback: "Invalid server origin") }
  /// Line on the status page showing the pinned server origin. %1$@ is the origin URL.
  internal static func settingsStatusOriginReady(_ p1: Any) -> String {
    return L10n.tr("Localizable", "settings_status_origin_ready", String(describing: p1), fallback: "Server origin: %1$@")
  }
  /// Line on the status page when the app must be reinstalled before it can use its configured server.
  internal static var settingsStatusOriginReinstallRequired: String { return L10n.tr("Localizable", "settings_status_origin_reinstall_required", fallback: "Reinstall required") }
  /// Title for the service being checked, in this case, the Pocket Cast's Refresh Service.
  internal static var settingsStatusRefreshService: String { return L10n.tr("Localizable", "settings_status_refresh_service", fallback: "Refresh Service") }
  /// Description for the Refresh Service check.
  internal static var settingsStatusRefreshServiceDescription: String { return L10n.tr("Localizable", "settings_status_refresh_service_description", fallback: "The service used to find new episodes.") }
  /// Button that starts the diagnostic in the Status Page
  internal static var settingsStatusRun: String { return L10n.tr("Localizable", "settings_status_run", fallback: "Run now") }
  /// Summary line describing the connected server. %1$@ = server version, %2$@ = App Attest mode, %3$@, %4$@ and %5$@ = localized On/Off for the avatar, folder-suggestion and corpus features.
  internal static func settingsStatusServerDetails(_ p1: Any, _ p2: Any, _ p3: Any, _ p4: Any, _ p5: Any) -> String {
    return L10n.tr("Localizable", "settings_status_server_details", String(describing: p1), String(describing: p2), String(describing: p3), String(describing: p4), String(describing: p5), fallback: "Version %1$@ · App Attest %2$@ · Avatar %3$@ · Folders %4$@ · Corpus %5$@")
  }
  /// Failure message for a service check.
  internal static func settingsStatusServiceAdBlockerHelpSingular(_ p1: Any) -> String {
    return L10n.tr("Localizable", "settings_status_service_ad_blocker_help_singular", String(describing: p1), fallback: "The most common cause is that you have an ad-blocker configured on your phone or network. You’ll need to unblock the domain %1$@")
  }
  /// A common string used throughout the app. Refers to the Storage & Data Use settings menu.
  internal static var settingsStorage: String { return L10n.tr("Localizable", "settings_storage", fallback: "Storage & Data Use") }
  /// Prompt for the toggle that turns on the dialog that warns the user before using data.
  internal static var settingsStorageDataWarning: String { return L10n.tr("Localizable", "settings_storage_data_warning", fallback: "Warn Before Using Data") }
  /// Prompt for the toggle that will include starred files in the clean up operation.
  internal static var settingsStorageDownloadsStarred: String { return L10n.tr("Localizable", "settings_storage_downloads_starred", fallback: "Include Starred") }
  /// Section header for settings related to data usage.
  internal static var settingsStorageMobileData: String { return L10n.tr("Localizable", "settings_storage_mobile_data", fallback: "MOBILE DATA") }
  /// Section header for information about storage space used.
  internal static var settingsStorageUsage: String { return L10n.tr("Localizable", "settings_storage_usage", fallback: "USAGE") }
  /// Footer note on the Storage & Data Use screen explaining why iOS may report higher storage than the app does.
  internal static var settingsStorageUsageFooter: String { return L10n.tr("Localizable", "settings_storage_usage_footer", fallback: "This may differ from the storage shown in your iPhone Settings. iOS manages cached data automatically and frees it up when needed.") }
  /// Label displayed next to the toggle to opt-in/out for First-Party Analytics tracking
  internal static var settingsThirdPartyAnalytics: String { return L10n.tr("Localizable", "settings_third_party_analytics", fallback: "Third-party analytics") }
  /// Title for the settings screen
  internal static var settingsTitle: String { return L10n.tr("Localizable", "settings_title", fallback: "Podcast Settings") }
  /// Provides a prompt for the user to configure the sensitivity associated to the auto trimming silence setting.
  internal static var settingsTrimLevel: String { return L10n.tr("Localizable", "settings_trim_level", fallback: "Trim Level") }
  /// Provides a prompt for the user to configure the trim silence options.
  internal static var settingsTrimSilence: String { return L10n.tr("Localizable", "settings_trim_silence", fallback: "Trim Silence") }
  /// Description explaining to the user what up next dark mode means.
  internal static var settingsUpNextDarkModeFooter: String { return L10n.tr("Localizable", "settings_up_next_dark_mode_footer", fallback: "When enabled the Up Next will always use the dark theme, or will match the current theme when disabled.") }
  /// Title of a setting that lets the user use dark mode for the up next
  internal static var settingsUpNextDarkModeTitle: String { return L10n.tr("Localizable", "settings_up_next_dark_mode_title", fallback: "Use Dark Up Next Theme") }
  /// Informs the user about how the Queue will be adjusted when the episode limit is reached. '%1$@' is a placeholder for the current queue limit.
  internal static func settingsUpNextLimit(_ p1: Any) -> String {
    return L10n.tr("Localizable", "settings_up_next_limit", String(describing: p1), fallback: "Automatically add new episodes to Up Next. New episodes will stop being added when Up Next reaches %1$@.")
  }
  /// Informs the user about how the Queue will be adjusted when the episode limit is reached. '%1$@' is a placeholder for the current queue limit.
  internal static func settingsUpNextLimitAddToTop(_ p1: Any) -> String {
    return L10n.tr("Localizable", "settings_up_next_limit_add_to_top", String(describing: p1), fallback: "Automatically add new episodes to Up Next. When Up Next reaches %1$@, new episodes auto‑added to the top will remove the last episode in the queue. Episodes set to auto‑add to the bottom won’t be added until Up Next is below the limit.")
  }
  /// Provides a prompt for the user to toggle on the volume boosting setting.
  internal static var settingsVolumeBoost: String { return L10n.tr("Localizable", "settings_volume_boost", fallback: "Volume Boost") }
  /// Title for the options for the user to configure their account.
  internal static var setupAccount: String { return L10n.tr("Localizable", "setup_account", fallback: "Set Up Account") }
  /// Note on the shake-to-report sheet describing the diagnostics attached to the report
  internal static var shakeFeedbackDiagnosticsNote: String { return L10n.tr("Localizable", "shake_feedback_diagnostics_note", fallback: "Your report includes recent app logs, device and app version info, and the diagnostics session ID.") }
  /// Error shown when a shake-to-report feedback submission failed
  internal static var shakeFeedbackFailed: String { return L10n.tr("Localizable", "shake_feedback_failed", fallback: "The report couldn't be sent. Check your connection and try again.") }
  /// Send button on the shake-to-report feedback sheet
  internal static var shakeFeedbackSend: String { return L10n.tr("Localizable", "shake_feedback_send", fallback: "Send Report") }
  /// Confirmation after a shake-to-report feedback submission succeeded
  internal static var shakeFeedbackSent: String { return L10n.tr("Localizable", "shake_feedback_sent", fallback: "Thanks — your report was sent.") }
  /// Title of the shake-to-report feedback sheet shown in beta builds
  internal static var shakeFeedbackTitle: String { return L10n.tr("Localizable", "shake_feedback_title", fallback: "Report a Problem") }
  /// Name of the option to shake to restart sleep timer
  internal static var shakeToRestartSleepTimer: String { return L10n.tr("Localizable", "shake_to_restart_sleep_timer", fallback: "Shake to restart Sleep Timer") }
  /// Description of the option to shake to restart sleep timer
  internal static var shakeToRestartSleepTimerDescription: String { return L10n.tr("Localizable", "shake_to_restart_sleep_timer_description", fallback: "If on, the sleep timer will restart when you shake your phone.") }
  /// A common string used throughout the app. Prompt to open the share settings for the selected item(s).
  internal static var share: String { return L10n.tr("Localizable", "share", fallback: "Share") }
  /// A title shown after editing a clip but before sharing
  internal static var shareClip: String { return L10n.tr("Localizable", "share_clip", fallback: "Share clip") }
  /// A message shown when a share link is copied to the clipboard
  internal static var shareCopiedToClipboard: String { return L10n.tr("Localizable", "share_copied_to_clipboard", fallback: "Link copied to clipboard") }
  /// A title shown for a share option which copies a link to a podcast or episode
  internal static var shareCopyLink: String { return L10n.tr("Localizable", "share_copy_link", fallback: "Copy link") }
  /// A common string used throughout the app. Option to share the episode at the current playback position.
  internal static var shareCurrentPosition: String { return L10n.tr("Localizable", "share_current_position", fallback: "Current Position") }
  /// A message shown when sharing an image representation of a podcast or episode to social media platforms
  internal static var shareDescription: String { return L10n.tr("Localizable", "share_description", fallback: "Choose a format and a platform to share to") }
  /// A title shown when sharing an episode
  internal static var shareEpisode: String { return L10n.tr("Localizable", "share_episode", fallback: "Share episode") }
  /// A common string used throughout the app. Option to share the episode at the current playback position.
  internal static func shareEpisodeAt(_ p1: Any) -> String {
    return L10n.tr("Localizable", "share_episode_at", String(describing: p1), fallback: "Share episode at %1$@")
  }
  /// A title used when sharing artwork and link to a podcast episode
  internal static var shareEpisodeTitle: String { return L10n.tr("Localizable", "share_episode_title", fallback: "Share episode") }
  /// Message indicating that the process to subscribe to a podcast list is in progress.
  internal static var shareListSubscribing: String { return L10n.tr("Localizable", "share_list_subscribing", fallback: "Subscribing...") }
  /// A title shown for the share action which displays the system share sheet
  internal static var shareMoreActions: String { return L10n.tr("Localizable", "share_more_actions", fallback: "More") }
  /// A title shown when sharing a podcast
  internal static var sharePodcast: String { return L10n.tr("Localizable", "share_podcast", fallback: "Share podcast") }
  /// A message shown when trying to share a private podcast, which is disabled.
  internal static var sharePodcastPrivateNotAvailable: String { return L10n.tr("Localizable", "share_podcast_private_not_available", fallback: "Sharing is not available for private podcasts") }
  /// A title used when sharing artwork and link to a podcast
  internal static var sharePodcastTitle: String { return L10n.tr("Localizable", "share_podcast_title", fallback: "Share podcast") }
  /// Message indicating that all of the podcasts have been selected.
  internal static var sharePodcastsAllSelected: String { return L10n.tr("Localizable", "share_podcasts_all_selected", fallback: "ALL SELECTED") }
  /// Title for the screen to finalize options to create a list of podcasts to share.
  internal static var sharePodcastsCreateList: String { return L10n.tr("Localizable", "share_podcasts_create_list", fallback: "Create List") }
  /// Message indicating that the process to share a podcast list is in progress.
  internal static var sharePodcastsSharing: String { return L10n.tr("Localizable", "share_podcasts_sharing", fallback: "Sharing...") }
  /// Error message for when sharing fails.
  internal static var sharePodcastsSharingFailedMsg: String { return L10n.tr("Localizable", "share_podcasts_sharing_failed_msg", fallback: "Something went wrong creating your share page") }
  /// Title indicating that sharing has failed.
  internal static var sharePodcastsSharingFailedTitle: String { return L10n.tr("Localizable", "share_podcasts_sharing_failed_title", fallback: "Sharing Failed") }
  /// Message of an alert shown when a signed-out user tries to share a list of podcasts; the alert offers a Sign In button.
  internal static var sharePodcastsSigninRequiredMsg: String { return L10n.tr("Localizable", "share_podcasts_signin_required_msg", fallback: "Sharing a list of podcasts requires an account. Sign in and try again.") }
  /// Title for the share profile screen
  internal static var shareProfile: String { return L10n.tr("Localizable", "share_profile", fallback: "Share profile") }
  /// Title for the add photo and name step
  internal static var shareProfileAddPhotoAndName: String { return L10n.tr("Localizable", "share_profile_add_photo_and_name", fallback: "Add photo and name") }
  /// Placeholder text for the name input field
  internal static var shareProfileAddYourName: String { return L10n.tr("Localizable", "share_profile_add_your_name", fallback: "Add your name") }
  /// Choose photo from library
  internal static var shareProfileChoosePhoto: String { return L10n.tr("Localizable", "share_profile_choose_photo", fallback: "Choose Photo") }
  /// Label for the display name field
  internal static var shareProfileDisplayName: String { return L10n.tr("Localizable", "share_profile_display_name", fallback: "Display name") }
  /// Title for the edit profile step
  internal static var shareProfileEdit: String { return L10n.tr("Localizable", "share_profile_edit", fallback: "Edit profile") }
  /// Title for the edit photo and name screen
  internal static var shareProfileEditPhotoAndName: String { return L10n.tr("Localizable", "share_profile_edit_photo_and_name", fallback: "Edit photo and name") }
  /// Toggle label for including followed podcasts in shared profile
  internal static var shareProfileFollowedPodcasts: String { return L10n.tr("Localizable", "share_profile_followed_podcasts", fallback: "Followed podcasts") }
  /// Description text below the name input field
  internal static var shareProfileNameDescription: String { return L10n.tr("Localizable", "share_profile_name_description", fallback: "This is how you'll appear on shared profiles. You can change it later.") }
  /// Toggle label for including playlists in shared profile
  internal static var shareProfilePlaylists: String { return L10n.tr("Localizable", "share_profile_playlists", fallback: "Playlists") }
  /// Title for the preview profile step
  internal static var shareProfilePreview: String { return L10n.tr("Localizable", "share_profile_preview", fallback: "Preview profile") }
  /// Share Profile: Privacy link label
  internal static var shareProfilePrivacy: String { return L10n.tr("Localizable", "share_profile_privacy", fallback: "Privacy") }
  /// Description text for the privacy settings hint on edit profile. %1$@ is the "Privacy" link text
  internal static func shareProfilePrivacyDescription(_ p1: Any) -> String {
    return L10n.tr("Localizable", "share_profile_privacy_description", String(describing: p1), fallback: "You can manage what you're sharing in %1$@")
  }
  /// Share Profile: Privacy settings footer text
  internal static var shareProfilePrivacySettingsFooter: String { return L10n.tr("Localizable", "share_profile_privacy_settings_footer", fallback: "Control what others can see when you share your profile.") }
  /// Share Profile: Profile sharing section header in privacy settings
  internal static var shareProfileProfileSharing: String { return L10n.tr("Localizable", "share_profile_profile_sharing", fallback: "Profile sharing") }
  /// Toggle label for including recent episodes in shared profile
  internal static var shareProfileRecentEpisodes: String { return L10n.tr("Localizable", "share_profile_recent_episodes", fallback: "Recent episodes") }
  /// Remove the current profile photo
  internal static var shareProfileRemovePhoto: String { return L10n.tr("Localizable", "share_profile_remove_photo", fallback: "Remove Photo") }
  /// Generic save button
  internal static var shareProfileSave: String { return L10n.tr("Localizable", "share_profile_save", fallback: "Save") }
  /// Button label for sharing the profile
  internal static var shareProfileShareMyProfile: String { return L10n.tr("Localizable", "share_profile_share_my_profile", fallback: "Share my profile") }
  /// Take a new photo with camera
  internal static var shareProfileTakePhoto: String { return L10n.tr("Localizable", "share_profile_take_photo", fallback: "Take Photo") }
  /// Section header for the share options
  internal static var shareProfileWhatToShare: String { return L10n.tr("Localizable", "share_profile_what_to_share", fallback: "What do you want to share?") }
  /// A common string used throughout the app. Title for the screen to select multiple podcasts to share.
  internal static var shareSelectPodcasts: String { return L10n.tr("Localizable", "share_select_podcasts", fallback: "Select Podcasts") }
  /// Progress indicator informing the user that the item that has been sent to them via share is loading.
  internal static var sharedItemLoading: String { return L10n.tr("Localizable", "shared_item_loading", fallback: "Loading Shared Item...") }
  /// Title for the screen that shows the podcasts from a shared list of podcasts.
  internal static var sharedList: String { return L10n.tr("Localizable", "shared_list", fallback: "Shared List") }
  /// Confirmation option presented when a user selects to subscribe to all podcasts in a list.
  internal static var sharedListSubscribeConfAction: String { return L10n.tr("Localizable", "shared_list_subscribe_conf_action", fallback: "Heck Yes!") }
  /// Message for a dialog presented when a user selects to subscribe to all podcasts in a list. '%1$@' is a placeholder for the number of podcasts that will be subscribed to.
  internal static func sharedListSubscribeConfMsg(_ p1: Any) -> String {
    return L10n.tr("Localizable", "shared_list_subscribe_conf_msg", String(describing: p1), fallback: "Are you sure you want to subscribe to %1$@ podcasts?")
  }
  /// Title for a dialog presented when a user selects to subscribe to all podcasts in a list.
  internal static var sharedListSubscribeConfTitle: String { return L10n.tr("Localizable", "shared_list_subscribe_conf_title", fallback: "That's a lot of podcasts!") }
  /// Toast shown when exporting a shareable clip fails. %1$@ is the system error description.
  internal static func sharingClipExportFailedDescription(_ p1: Any) -> String {
    return L10n.tr("Localizable", "sharing_clip_export_failed_description", String(describing: p1), fallback: "Failed clip export: %1$@")
  }
  /// A common string used throughout the app. Refers to the Notes (show notes) tab in the player.
  internal static var showNotes: String { return L10n.tr("Localizable", "show_notes", fallback: "Notes") }
  /// A common string used throughout the app. Prompt for the user to sign into their account.
  internal static var signIn: String { return L10n.tr("Localizable", "sign_in", fallback: "Sign In") }
  /// Label of a button that lets the user login/signup with Email
  internal static var signInContinueWithEmail: String { return L10n.tr("Localizable", "sign_in_continue_with_email", fallback: "Continue with Email") }
  /// A label dividing the email with social login options. Indicating a separation of two separate sections.
  internal static var signInDividerLabel: String { return L10n.tr("Localizable", "sign_in_divider_label", fallback: "OR") }
  /// Email address field prompt
  internal static var signInEmailAddressPrompt: String { return L10n.tr("Localizable", "sign_in_email_address_prompt", fallback: "Email Address") }
  /// Button text to go to the forgot password page
  internal static var signInForgotPassword: String { return L10n.tr("Localizable", "sign_in_forgot_password", fallback: "I forgot my password") }
  /// Label for option to hide the password contents in the log in form.
  internal static var signInHidePasswordLabel: String { return L10n.tr("Localizable", "sign_in_hide_password_label", fallback: "Show Password") }
  /// Message shown below the sign in prompt to give users more details about what it does
  internal static var signInMessage: String { return L10n.tr("Localizable", "sign_in_message", fallback: "Save your podcast subscriptions in the cloud and sync your progress with other devices.") }
  /// Password field prompt
  internal static var signInPasswordPrompt: String { return L10n.tr("Localizable", "sign_in_password_prompt", fallback: "Password") }
  /// Prompt for the user to sign into their account or create an account
  internal static var signInPrompt: String { return L10n.tr("Localizable", "sign_in_prompt", fallback: "Sign in or create account") }
  /// Label for option to show the password contents in the log in form.
  internal static var signInShowPasswordLabel: String { return L10n.tr("Localizable", "sign_in_show_password_label", fallback: "Hide Password") }
  /// Label indicating which account the user is signed into. The accounts email address is displayed in close proximity to this label.
  internal static var signedInAs: String { return L10n.tr("Localizable", "signed_in_as", fallback: "SIGNED IN AS") }
  /// Label indicating which account is not signed in.
  internal static var signedOut: String { return L10n.tr("Localizable", "signed_out", fallback: "Not Signed In") }
  /// Singular indication of number of chapters
  internal static var singleChapter: String { return L10n.tr("Localizable", "single_chapter", fallback: "1 chapter") }
  /// Siri shortcut title for increasing the sleep timer by a specified amount. '%1$@' is the placeholder for the time specified amount or time.
  internal static func siriShortcutExtendSleepTimer(_ p1: Any) -> String {
    return L10n.tr("Localizable", "siri_shortcut_extend_sleep_timer", String(describing: p1), fallback: "Set sleep timer to %1$@")
  }
  /// Siri shortcut phrase for increasing the sleep timer by a specified amount.
  internal static var siriShortcutExtendSleepTimerFiveMin: String { return L10n.tr("Localizable", "siri_shortcut_extend_sleep_timer_five_min", fallback: "Extend sleep timer by 5 minutes") }
  /// Siri shortcut invocation phrase for marking the current episode as played
  internal static var siriShortcutMarkAsPlayedPhrase: String { return L10n.tr("Localizable", "siri_shortcut_mark_as_played_phrase", fallback: "Mark as Played") }
  /// Siri shortcut title for marking the current episode as played
  internal static var siriShortcutMarkAsPlayedTitle: String { return L10n.tr("Localizable", "siri_shortcut_mark_as_played_title", fallback: "Mark Current Episode as Played") }
  /// Siri shortcut title and phrase for having siri skip to the next chapter of a podcast
  internal static var siriShortcutNextChapter: String { return L10n.tr("Localizable", "siri_shortcut_next_chapter", fallback: "Next chapter") }
  /// Siri shortcut invocation phrase for opening a specified filter. '%1$@' is the placeholder for the specified filter.
  internal static func siriShortcutOpenFilterPhrase(_ p1: Any) -> String {
    return L10n.tr("Localizable", "siri_shortcut_open_filter_phrase", String(describing: p1), fallback: "Open %1$@")
  }
  /// Siri shortcut invocation phrase for pausing the current episode
  internal static var siriShortcutPausePhrase: String { return L10n.tr("Localizable", "siri_shortcut_pause_phrase", fallback: "Pause") }
  /// Siri shortcut title for pausing the current episode
  internal static var siriShortcutPauseTitle: String { return L10n.tr("Localizable", "siri_shortcut_pause_title", fallback: "Pause Current Episode") }
  /// Siri shortcut invocation phrase for playing all episodes of a particular filter. '%1$@' is a placeholder for the name of the filter to play from
  internal static func siriShortcutPlayAllPhrase(_ p1: Any) -> String {
    return L10n.tr("Localizable", "siri_shortcut_play_all_phrase", String(describing: p1), fallback: "Play all %1$@")
  }
  /// Siri shortcut title for playing all episodes of a particular filter
  internal static var siriShortcutPlayAllTitle: String { return L10n.tr("Localizable", "siri_shortcut_play_all_title", fallback: "Playing all episodes") }
  /// Siri shortcut title for playing the top episode of a particular podcast or filter
  internal static var siriShortcutPlayEpisodeTitle: String { return L10n.tr("Localizable", "siri_shortcut_play_episode_title", fallback: "Playing the top episode") }
  /// Siri shortcut invocation phrase for playing the specified filter. '%1$@' is a placeholder for the name of the filter to play from
  internal static func siriShortcutPlayFilterPhrase(_ p1: Any) -> String {
    return L10n.tr("Localizable", "siri_shortcut_play_filter_phrase", String(describing: p1), fallback: "Play top %1$@")
  }
  /// Siri shortcut invocation phrase for playing the specified podcast. '%1$@' is a placeholder for the name of the podcast
  internal static func siriShortcutPlayPodcastPhrase(_ p1: Any) -> String {
    return L10n.tr("Localizable", "siri_shortcut_play_podcast_phrase", String(describing: p1), fallback: "Play %1$@")
  }
  /// Siri shortcut phrase title for playing a suggested podcast
  internal static var siriShortcutPlaySuggestedPodcastPhrase: String { return L10n.tr("Localizable", "siri_shortcut_play_suggested_podcast_phrase", fallback: "Play a suggested episode") }
  /// Siri shortcut suggested title for playing a suggested podcast
  internal static var siriShortcutPlaySuggestedPodcastSuggestedTitle: String { return L10n.tr("Localizable", "siri_shortcut_play_suggested_podcast_suggested_title", fallback: "Surprise Me!") }
  /// Siri shortcut title for playing a suggested podcast
  internal static var siriShortcutPlaySuggestedPodcastTitle: String { return L10n.tr("Localizable", "siri_shortcut_play_suggested_podcast_title", fallback: "Playing a suggested episode") }
  /// Siri shortcut invocation phrase for playing the next episode in the queue.
  internal static var siriShortcutPlayUpNextPhrase: String { return L10n.tr("Localizable", "siri_shortcut_play_up_next_phrase", fallback: "Up Next") }
  /// Siri shortcut title for playing the next episode in the queue
  internal static var siriShortcutPlayUpNextTitle: String { return L10n.tr("Localizable", "siri_shortcut_play_up_next_title", fallback: "Playing next episode") }
  /// Siri shortcut title and phrase for having siri skip to the previous chapter of a podcast
  internal static var siriShortcutPreviousChapter: String { return L10n.tr("Localizable", "siri_shortcut_previous_chapter", fallback: "Previous chapter") }
  /// Siri shortcut invocation phrase for resuming the current episode
  internal static var siriShortcutResumePhrase: String { return L10n.tr("Localizable", "siri_shortcut_resume_phrase", fallback: "Resume") }
  /// Siri shortcut title for resuming the current episode
  internal static var siriShortcutResumeTitle: String { return L10n.tr("Localizable", "siri_shortcut_resume_title", fallback: "Resuming Current Episode") }
  /// Title for the siri shortcuts page to create a shortcut to a podcast
  internal static var siriShortcutToPodcast: String { return L10n.tr("Localizable", "siri_shortcut_to_podcast", fallback: "Create Shortcut to Podcast") }
  /// A common string used throughout the app. Prompt to rewind the playback by a configurable amount.
  internal static var skipBack: String { return L10n.tr("Localizable", "skip_back", fallback: "Skip Back") }
  /// Label that toggles the option for the user to choose which chapters of the podcast they want to skip (to not be played)
  internal static var skipChapters: String { return L10n.tr("Localizable", "skip_chapters", fallback: "Preselect chapters") }
  /// Accessibility label for the button that adds the typed chapter skip phrase to the list.
  internal static var skipChaptersAddButton: String { return L10n.tr("Localizable", "skip_chapters_add_button", fallback: "Add") }
  /// Placeholder for the text field used to add a new chapter skip phrase.
  internal static var skipChaptersAddPlaceholder: String { return L10n.tr("Localizable", "skip_chapters_add_placeholder", fallback: "Add a word or phrase") }
  /// Empty state shown when no chapter skip phrases have been added yet.
  internal static var skipChaptersEmpty: String { return L10n.tr("Localizable", "skip_chapters_empty", fallback: "No phrases yet. Try adding something like “sponsor” or “ad break”.") }
  /// Footer explaining how the chapter skip phrases are applied.
  internal static var skipChaptersExplanation: String { return L10n.tr("Localizable", "skip_chapters_explanation", fallback: "Chapters with titles containing any of these phrases will be skipped automatically for this podcast. Re-enabling a chapter in the player keeps it playable for the rest of the session.") }
  /// Prompt for Plus mentioning Pre selecting Chapters, don't translate Pocket Casts Patron
  internal static var skipChaptersPatronPrompt: String { return L10n.tr("Localizable", "skip_chapters_patron_prompt", fallback: "Preselect chapters and more with Pocket Casts Patron") }
  /// Prompt for Plus mentioning Pre selecting Chapters, don't translate Pocket Casts Plus
  internal static var skipChaptersPlusPrompt: String { return L10n.tr("Localizable", "skip_chapters_plus_prompt", fallback: "Preselect chapters and more with Pocket Casts Plus") }
  /// A common string used throughout the app. Prompt to fast-forward the playback by a configurable amount.
  internal static var skipForward: String { return L10n.tr("Localizable", "skip_forward", fallback: "Skip Forward") }
  /// The Sleep Timer feature.
  internal static var sleepTimer: String { return L10n.tr("Localizable", "sleep_timer", fallback: "Sleep Timer") }
  /// Prompt to add five minutes to an active timer.
  internal static var sleepTimerAdd5Mins: String { return L10n.tr("Localizable", "sleep_timer_add_5_mins", fallback: "+ 5 Minutes") }
  /// Prompt to cancel the active sleep timer.
  internal static var sleepTimerCancel: String { return L10n.tr("Localizable", "sleep_timer_cancel", fallback: "Cancel Timer") }
  /// Prompt to change the active sleep timer to be end of episode.
  internal static var sleepTimerEndOfEpisode: String { return L10n.tr("Localizable", "sleep_timer_end_of_episode", fallback: "End Of Episode") }
  /// Label displaying in how many episodes the sleep timer will activate. %1$@ is the number of episodes.
  internal static func sleepTimerEpisodeCount(_ p1: Any) -> String {
    return L10n.tr("Localizable", "sleep_timer_episode_count", String(describing: p1), fallback: "In %1$@ episodes")
  }
  /// Error shown when a sleep timer shortcut is run with a duration outside the supported 1 to 300 minute range.
  internal static var sleepTimerInvalidDuration: String { return L10n.tr("Localizable", "sleep_timer_invalid_duration", fallback: "Enter a sleep timer duration between 1 and 300 minutes.") }
  /// Label showing that Sleep Timer will activate after a given number of episodes. %1$@ is the number of episodes and it's always bigger than 1.
  internal static func sleepTimerSleepingAfter(_ p1: Any) -> String {
    return L10n.tr("Localizable", "sleep_timer_sleeping_after", String(describing: p1), fallback: "Sleeping in %1$@ episodes")
  }
  /// Label showing that Sleep Timer will activate at the end of current episode
  internal static var sleepTimerSleepingAfterCurrentEpisode: String { return L10n.tr("Localizable", "sleep_timer_sleeping_after_current_episode", fallback: "Sleeping at the end of the current episode") }
  /// Accessibility hint that displays the remaining amount of time for the sleep timer. '%1$@' is a placeholder for the remaining time.
  internal static func sleepTimerTimeRemaining(_ p1: Any) -> String {
    return L10n.tr("Localizable", "sleep_timer_time_remaining", String(describing: p1), fallback: "Sleep Timer on, %1$@ remaining")
  }
  /// A common string used throughout the app. Often refers to the Smart Playlist.
  internal static var smartPlaylist: String { return L10n.tr("Localizable", "smart_playlist", fallback: "Smart playlist") }
  /// The description shown in a Tip View when the user opens the new Playlist creation view for the first time
  internal static var smartPlaylistsTipViewCreationDescription: String { return L10n.tr("Localizable", "smart_playlists_tip_view_creation_description", fallback: "Pick episodes yourself, or let Smart Playlist fill it automatically based on your Smart Rules.") }
  /// The title shown in a Tip View when the user opens the new Playlist creation view for the first time
  internal static var smartPlaylistsTipViewCreationTitle: String { return L10n.tr("Localizable", "smart_playlists_tip_view_creation_title", fallback: "Build your own playlist or let us help") }
  /// The description shown in a Tip View when the user hasn't yet added a smart playlist
  internal static var smartPlaylistsTipViewDescription: String { return L10n.tr("Localizable", "smart_playlists_tip_view_description", fallback: "We made these to help you get started. They auto-update based on your listening.") }
  /// The title shown in a Tip View when the user hasn't yet added a smart playlist
  internal static var smartPlaylistsTipViewTitle: String { return L10n.tr("Localizable", "smart_playlists_tip_view_title", fallback: "Smart playlists, ready to go") }
  /// Body of the one-time social announcement sheet
  internal static var socialAnnouncementBody: String { return L10n.tr("Localizable", "social_announcement_body", fallback: "Claim your @handle and share what you're listening to — private by default, opt-in only.") }
  /// Button on the announcement sheet that opens the Join flow
  internal static var socialAnnouncementCta: String { return L10n.tr("Localizable", "social_announcement_cta", fallback: "Claim your @handle") }
  /// Title of the one-time social announcement sheet
  internal static var socialAnnouncementTitle: String { return L10n.tr("Localizable", "social_announcement_title", fallback: "Say hello to profiles") }
  /// Block action label
  internal static var socialBlock: String { return L10n.tr("Localizable", "social_block", fallback: "Block") }
  /// Message of the block confirmation alert
  internal static var socialBlockConfirmMessage: String { return L10n.tr("Localizable", "social_block_confirm_message", fallback: "You won't see each other's profiles, and they won't be able to interact with you. They aren't notified.") }
  /// Title of the block confirmation alert
  internal static var socialBlockConfirmTitle: String { return L10n.tr("Localizable", "social_block_confirm_title", fallback: "Block this person?") }
  /// Label on a profile the viewer has blocked
  internal static var socialBlockedLabel: String { return L10n.tr("Localizable", "social_blocked_label", fallback: "Blocked") }
  /// Stats share card label: total hours listened
  internal static var socialCardHoursListened: String { return L10n.tr("Localizable", "social_card_hours_listened", fallback: "listened") }
  /// Stats share card hours value. %1$d is a number of hours
  internal static func socialCardHoursValue(_ p1: Int) -> String {
    return L10n.tr("Localizable", "social_card_hours_value", p1, fallback: "%1$d hours")
  }
  /// Stats share card label: date listening started
  internal static var socialCardListeningSince: String { return L10n.tr("Localizable", "social_card_listening_since", fallback: "listening since") }
  /// Share menu action for the heatmap card
  internal static var socialCardShareHeatmap: String { return L10n.tr("Localizable", "social_card_share_heatmap", fallback: "Share activity card") }
  /// Share menu action for the stats card
  internal static var socialCardShareStats: String { return L10n.tr("Localizable", "social_card_share_stats", fallback: "Share stats card") }
  /// Stats share card label: time saved by effects
  internal static var socialCardTimeSaved: String { return L10n.tr("Localizable", "social_card_time_saved", fallback: "saved by trim & speed") }
  /// Profile tab row CTA before the account has joined social
  internal static var socialClaimHandle: String { return L10n.tr("Localizable", "social_claim_handle", fallback: "Claim your @handle") }
  /// Accessibility label for the attach-playback-timestamp toggle in the composer
  internal static var socialCommentAttachTimestamp: String { return L10n.tr("Localizable", "social_comment_attach_timestamp", fallback: "Attach current playback time") }
  /// Error alert shown when deleting a comment fails.
  internal static var socialCommentDeleteFailed: String { return L10n.tr("Localizable", "social_comment_delete_failed", fallback: "Couldn't delete that comment. Try again.") }
  /// Error when a comment edit is rejected (window closed or filter)
  internal static var socialCommentEditFailed: String { return L10n.tr("Localizable", "social_comment_edit_failed", fallback: "Couldn't save the edit. The edit window may have closed.") }
  /// Marker on a comment edited during the grace window
  internal static var socialCommentEdited: String { return L10n.tr("Localizable", "social_comment_edited", fallback: "(edited)") }
  /// Composer banner while editing an existing comment
  internal static var socialCommentEditingBanner: String { return L10n.tr("Localizable", "social_comment_editing_banner", fallback: "Editing your comment") }
  /// Placeholder for the comment compose field
  internal static var socialCommentPlaceholder: String { return L10n.tr("Localizable", "social_comment_placeholder", fallback: "Add a comment") }
  /// Transcript-reader context-menu action that quotes the tapped line into a new comment
  internal static var socialCommentQuoteAction: String { return L10n.tr("Localizable", "social_comment_quote_action", fallback: "Comment on This") }
  /// Accessibility label for the button removing a staged transcript quote from the comment composer
  internal static var socialCommentQuoteRemove: String { return L10n.tr("Localizable", "social_comment_quote_remove", fallback: "Remove quote") }
  /// Placeholder body for a deleted/removed comment whose replies survive
  internal static var socialCommentRemoved: String { return L10n.tr("Localizable", "social_comment_removed", fallback: "[removed]") }
  /// Button starting a reply to a comment
  internal static var socialCommentReply: String { return L10n.tr("Localizable", "social_comment_reply", fallback: "Reply") }
  /// Composer banner while replying. %1$@ = the @handle being replied to
  internal static func socialCommentReplyingTo(_ p1: Any) -> String {
    return L10n.tr("Localizable", "social_comment_replying_to", String(describing: p1), fallback: "Replying to %1$@")
  }
  /// Error when a comment fails to post
  internal static var socialCommentSubmitFailed: String { return L10n.tr("Localizable", "social_comment_submit_failed", fallback: "Couldn't post that comment.") }
  /// Button revealing multiple replies to a comment. %1$d = reply count.
  internal static func socialCommentViewRepliesPlural(_ p1: Int) -> String {
    return L10n.tr("Localizable", "social_comment_view_replies_plural", p1, fallback: "View %1$d replies")
  }
  /// Button revealing exactly one reply to a comment.
  internal static var socialCommentViewRepliesSingular: String { return L10n.tr("Localizable", "social_comment_view_replies_singular", fallback: "View 1 reply") }
  /// Empty state for an episode with no comments yet
  internal static var socialCommentsEmpty: String { return L10n.tr("Localizable", "social_comments_empty", fallback: "No comments yet. Be the first!") }
  /// Hint shown when the user hasn't listened enough to post a top-level comment
  internal static var socialCommentsGateHint: String { return L10n.tr("Localizable", "social_comments_gate_hint", fallback: "Listen to a bit more of this episode to join the discussion. You can still reply to others.") }
  /// Row on the episode card opening the comments screen. %1$d = comment count
  internal static func socialCommentsRow(_ p1: Int) -> String {
    return L10n.tr("Localizable", "social_comments_row", p1, fallback: "Comments (%1$d)")
  }
  /// Row on the episode card opening the comments screen when the count is unknown
  internal static var socialCommentsRowUntallied: String { return L10n.tr("Localizable", "social_comments_row_untallied", fallback: "Comments") }
  /// Title of the episode comments screen
  internal static var socialCommentsTitle: String { return L10n.tr("Localizable", "social_comments_title", fallback: "Comments") }
  /// Note on the confirmation step that all fields start private
  internal static var socialConfirmPrivateNote: String { return L10n.tr("Localizable", "social_confirm_private_note", fallback: "Only your display name and handle will be public. Everything else stays private until you change it.") }
  /// Confirmation step prompt. %1$@ is the claimed @handle
  internal static func socialConfirmPrompt(_ p1: Any) -> String {
    return L10n.tr("Localizable", "social_confirm_prompt", String(describing: p1), fallback: "Claiming %1$@ — what name should people see?")
  }
  /// Accessibility label for the curator badge (a seal icon; never says verified)
  internal static var socialCuratorBadge: String { return L10n.tr("Localizable", "social_curator_badge", fallback: "Curator") }
  /// Follower count on a curator row (plural). %1$d is the count
  internal static func socialCuratorFollowers(_ p1: Int) -> String {
    return L10n.tr("Localizable", "social_curator_followers", p1, fallback: "%1$d followers")
  }
  /// Follower count on a curator row when there is exactly one
  internal static var socialCuratorFollowersSingular: String { return L10n.tr("Localizable", "social_curator_followers_singular", fallback: "1 follower") }
  /// Section header for the operator-designated curators directory
  internal static var socialCuratorsHeader: String { return L10n.tr("Localizable", "social_curators_header", fallback: "Curators") }
  /// Placeholder for the public display name field
  internal static var socialDisplayNamePlaceholder: String { return L10n.tr("Localizable", "social_display_name_placeholder", fallback: "Display name") }
  /// Error shown when a profile edit is rejected by the server
  internal static var socialEditRejected: String { return L10n.tr("Localizable", "social_edit_rejected", fallback: "Couldn't save. Your name or bio may have been rejected.") }
  /// Body of the Explore-tab card explaining what joining unlocks
  internal static var socialExploreJoinMessage: String { return L10n.tr("Localizable", "social_explore_join_message", fallback: "Claim a handle to follow friends and see what they're listening to — right here.") }
  /// Title of the Explore-tab card inviting the user to join the social features
  internal static var socialExploreJoinTitle: String { return L10n.tr("Localizable", "social_explore_join_title", fallback: "Find your friends") }
  /// Empty state for the Explore activity feed when there is no recent activity from followed people
  internal static var socialFeedEmpty: String { return L10n.tr("Localizable", "social_feed_empty", fallback: "Follow friends to see what they're listening to.") }
  /// Section header for the friends activity feed on the Explore tab
  internal static var socialFeedHeader: String { return L10n.tr("Localizable", "social_feed_header", fallback: "Friends") }
  /// Feed line: person commented on an episode. %1$@ = display name, %2$@ = episode title
  internal static func socialFeedItemCommented(_ p1: Any, _ p2: Any) -> String {
    return L10n.tr("Localizable", "social_feed_item_commented", String(describing: p1), String(describing: p2), fallback: "%1$@ commented on %2$@")
  }
  /// Feed line: person finished an episode. %1$@ = display name, %2$@ = episode title
  internal static func socialFeedItemFinished(_ p1: Any, _ p2: Any) -> String {
    return L10n.tr("Localizable", "social_feed_item_finished", String(describing: p1), String(describing: p2), fallback: "%1$@ finished %2$@")
  }
  /// Feed line: person followed another person. %1$@ = display name, %2$@ = the @handle they followed
  internal static func socialFeedItemFollowedPerson(_ p1: Any, _ p2: Any) -> String {
    return L10n.tr("Localizable", "social_feed_item_followed_person", String(describing: p1), String(describing: p2), fallback: "%1$@ followed %2$@")
  }
  /// Feed line: person followed a podcast. %1$@ = display name, %2$@ = podcast title
  internal static func socialFeedItemFollowedShow(_ p1: Any, _ p2: Any) -> String {
    return L10n.tr("Localizable", "social_feed_item_followed_show", String(describing: p1), String(describing: p2), fallback: "%1$@ followed %2$@")
  }
  /// Feed line: person joined the social features. %1$@ = their display name
  internal static func socialFeedItemJoined(_ p1: Any) -> String {
    return L10n.tr("Localizable", "social_feed_item_joined", String(describing: p1), fallback: "%1$@ joined")
  }
  /// Feed line for joining a public group. %1$@ actor name, %2$@ group title
  internal static func socialFeedItemJoinedGroup(_ p1: Any, _ p2: Any) -> String {
    return L10n.tr("Localizable", "social_feed_item_joined_group", String(describing: p1), String(describing: p2), fallback: "%1$@ joined %2$@")
  }
  /// Feed line for an episodes-finished milestone. %1$@ actor, %2$d tier
  internal static func socialFeedItemMilestoneEpisodes(_ p1: Any, _ p2: Int) -> String {
    return L10n.tr("Localizable", "social_feed_item_milestone_episodes", String(describing: p1), p2, fallback: "%1$@ finished %2$d episodes")
  }
  /// Feed line for an hours-listened milestone. %1$@ actor, %2$d tier
  internal static func socialFeedItemMilestoneHours(_ p1: Any, _ p2: Int) -> String {
    return L10n.tr("Localizable", "social_feed_item_milestone_hours", String(describing: p1), p2, fallback: "%1$@ crossed %2$d hours listened")
  }
  /// Feed line: person published a list. %1$@ = display name, %2$@ = list title
  internal static func socialFeedItemPublishedList(_ p1: Any, _ p2: Any) -> String {
    return L10n.tr("Localizable", "social_feed_item_published_list", String(describing: p1), String(describing: p2), fallback: "%1$@ published %2$@")
  }
  /// Feed line: person reacted to an episode. %1$@ = display name, %2$@ = episode title
  internal static func socialFeedItemReacted(_ p1: Any, _ p2: Any) -> String {
    return L10n.tr("Localizable", "social_feed_item_reacted", String(describing: p1), String(describing: p2), fallback: "%1$@ reacted to %2$@")
  }
  /// Feed line: person reviewed a podcast. %1$@ = display name, %2$@ = podcast title
  internal static func socialFeedItemReviewed(_ p1: Any, _ p2: Any) -> String {
    return L10n.tr("Localizable", "social_feed_item_reviewed", String(describing: p1), String(describing: p2), fallback: "%1$@ reviewed %2$@")
  }
  /// Body of the contacts consent alert — honest about the mechanics
  internal static var socialFindContactsConsentBody: String { return L10n.tr("Localizable", "social_find_contacts_consent_body", fallback: "Your contacts' email addresses and phone numbers are scrambled (hashed) on this device and compared once for matching. Nothing is stored, and no one is notified. Only members who allow discovery can match.") }
  /// Confirm button of the contacts consent alert
  internal static var socialFindContactsConsentCta: String { return L10n.tr("Localizable", "social_find_contacts_consent_cta", fallback: "Match my contacts") }
  /// Header over contact-match results
  internal static var socialFindContactsHeader: String { return L10n.tr("Localizable", "social_find_contacts_header", fallback: "From your contacts") }
  /// Button state while contact matching runs
  internal static var socialFindContactsMatching: String { return L10n.tr("Localizable", "social_find_contacts_matching", fallback: "Matching…") }
  /// Button starting the contacts-matching flow
  internal static var socialFindFromContacts: String { return L10n.tr("Localizable", "social_find_from_contacts", fallback: "Find from contacts") }
  /// Row sharing the owner's Profile Link to invite a friend
  internal static var socialFindInvite: String { return L10n.tr("Localizable", "social_find_invite", fallback: "Invite a friend") }
  /// Error shown when a Find People search, suggestion, or contact match request fails.
  internal static var socialFindLoadFailed: String { return L10n.tr("Localizable", "social_find_load_failed", fallback: "Couldn't load people. Try again.") }
  /// Multiple mutual-connections count on a suggestion row. %1$d = count.
  internal static func socialFindMutualCountPlural(_ p1: Int) -> String {
    return L10n.tr("Localizable", "social_find_mutual_count_plural", p1, fallback: "%1$d mutual connections")
  }
  /// Exactly one mutual connection on a suggestion row.
  internal static var socialFindMutualCountSingular: String { return L10n.tr("Localizable", "social_find_mutual_count_singular", fallback: "1 mutual connection") }
  /// Button that asks for a friend's @handle to open their profile
  internal static var socialFindPeople: String { return L10n.tr("Localizable", "social_find_people", fallback: "Find People") }
  /// Confirmation button that opens the profile for the typed handle
  internal static var socialFindPeopleCta: String { return L10n.tr("Localizable", "social_find_people_cta", fallback: "View Profile") }
  /// Placeholder for the find-people search field
  internal static var socialFindPeoplePlaceholder: String { return L10n.tr("Localizable", "social_find_people_placeholder", fallback: "Search by @handle or name") }
  /// Prompt shown with a text field asking for a friend's @handle
  internal static var socialFindPeoplePrompt: String { return L10n.tr("Localizable", "social_find_people_prompt", fallback: "Enter a friend's handle to view their profile.") }
  /// Header over search results on the find-people screen
  internal static var socialFindResultsHeader: String { return L10n.tr("Localizable", "social_find_results_header", fallback: "Results") }
  /// Header over friends-of-followed suggestions
  internal static var socialFindSuggestedHeader: String { return L10n.tr("Localizable", "social_find_suggested_header", fallback: "Suggested") }
  /// Button to follow this profile's owner
  internal static var socialFollow: String { return L10n.tr("Localizable", "social_follow", fallback: "Follow") }
  /// Button to accept a pending follow request
  internal static var socialFollowAccept: String { return L10n.tr("Localizable", "social_follow_accept", fallback: "Accept") }
  /// Button to decline a pending follow request
  internal static var socialFollowDecline: String { return L10n.tr("Localizable", "social_follow_decline", fallback: "Decline") }
  /// Empty state for a followers/following list
  internal static var socialFollowListEmpty: String { return L10n.tr("Localizable", "social_follow_list_empty", fallback: "No one here yet.") }
  /// Follow-button state while a follow request awaits the owner's approval
  internal static var socialFollowRequested: String { return L10n.tr("Localizable", "social_follow_requested", fallback: "Requested") }
  /// Section header in the Inbox listing pending follow requests
  internal static var socialFollowRequestsTitle: String { return L10n.tr("Localizable", "social_follow_requests_title", fallback: "Follow Requests") }
  /// Header/label for the list of accounts that follow a profile
  internal static var socialFollowersTitle: String { return L10n.tr("Localizable", "social_followers_title", fallback: "Followers") }
  /// Follow-button state when the signed-in user already follows this profile
  internal static var socialFollowing: String { return L10n.tr("Localizable", "social_following", fallback: "Following") }
  /// Header/label for the list of accounts a profile follows
  internal static var socialFollowingTitle: String { return L10n.tr("Localizable", "social_following_title", fallback: "Following") }
  /// Generic alert shown when a group action such as join, leave, moderation, or notification changes fails
  internal static var socialGroupActionFailed: String { return L10n.tr("Localizable", "social_group_action_failed", fallback: "That action couldn’t be completed. Try again.") }
  /// Accessibility label for the per-group new-post notification toggle
  internal static var socialGroupAlertToggle: String { return L10n.tr("Localizable", "social_group_alert_toggle", fallback: "New post alerts") }
  /// Accessibility label for attaching the currently playing episode to a group post
  internal static var socialGroupAttachEpisode: String { return L10n.tr("Localizable", "social_group_attach_episode", fallback: "Attach current episode") }
  /// Owner action banning a member from a group (cannot rejoin)
  internal static var socialGroupBan: String { return L10n.tr("Localizable", "social_group_ban", fallback: "Ban from group") }
  /// Title of the group creation sheet
  internal static var socialGroupCreateTitle: String { return L10n.tr("Localizable", "social_group_create_title", fallback: "New Group") }
  /// Placeholder for the optional group description field
  internal static var socialGroupDescriptionPlaceholder: String { return L10n.tr("Localizable", "social_group_description_placeholder", fallback: "Description (optional)") }
  /// Accessibility label for the button removing the episode attached to a group post draft.
  internal static var socialGroupDetachEpisode: String { return L10n.tr("Localizable", "social_group_detach_episode", fallback: "Remove attached episode") }
  /// Attribution line on a group invite. %1$@ is the inviter's @handle
  internal static func socialGroupInviteFrom(_ p1: Any) -> String {
    return L10n.tr("Localizable", "social_group_invite_from", String(describing: p1), fallback: "Invited by %1$@")
  }
  /// Section header for pending group invites
  internal static var socialGroupInvitesTitle: String { return L10n.tr("Localizable", "social_group_invites_title", fallback: "Group Invites") }
  /// Button joining a public group
  internal static var socialGroupJoin: String { return L10n.tr("Localizable", "social_group_join", fallback: "Join Group") }
  /// Owner action removing a member from a group
  internal static var socialGroupKick: String { return L10n.tr("Localizable", "social_group_kick", fallback: "Remove from group") }
  /// Menu action to leave a group
  internal static var socialGroupLeave: String { return L10n.tr("Localizable", "social_group_leave", fallback: "Leave Group") }
  /// Member count on a group row (plural). %1$d is the count
  internal static func socialGroupMemberCount(_ p1: Int) -> String {
    return L10n.tr("Localizable", "social_group_member_count", p1, fallback: "%1$d members")
  }
  /// Member count on a group row when there is exactly one member
  internal static var socialGroupMemberCountSingular: String { return L10n.tr("Localizable", "social_group_member_count_singular", fallback: "1 member") }
  /// Title of the group members sheet
  internal static var socialGroupMembersTitle: String { return L10n.tr("Localizable", "social_group_members_title", fallback: "Members") }
  /// Inline error shown when sending a group post fails
  internal static var socialGroupPostFailed: String { return L10n.tr("Localizable", "social_group_post_failed", fallback: "Couldn’t post to this group. Try again.") }
  /// Placeholder for the group post composer
  internal static var socialGroupPostPlaceholder: String { return L10n.tr("Localizable", "social_group_post_placeholder", fallback: "Post to the group") }
  /// Empty state of a group's post feed
  internal static var socialGroupPostsEmpty: String { return L10n.tr("Localizable", "social_group_posts_empty", fallback: "No posts yet. Share an episode or start a conversation.") }
  /// Footer explaining a private group's lifecycle. Shown in the create sheet
  internal static var socialGroupPrivateFooter: String { return L10n.tr("Localizable", "social_group_private_footer", fallback: "Only people you invite can see a private group. It is deleted with your profile.") }
  /// Footer explaining a public group's lifecycle. Shown in the create sheet
  internal static var socialGroupPublicFooter: String { return L10n.tr("Localizable", "social_group_public_footer", fallback: "Anyone can find and join a public group. If you delete your profile, the group passes to its longest-standing member.") }
  /// Toggle making a group public (joinable and discoverable)
  internal static var socialGroupPublicToggle: String { return L10n.tr("Localizable", "social_group_public_toggle", fallback: "Public group") }
  /// Placeholder for the group name field
  internal static var socialGroupTitlePlaceholder: String { return L10n.tr("Localizable", "social_group_title_placeholder", fallback: "Group name") }
  /// Section header for discoverable public groups
  internal static var socialGroupsDiscoverTitle: String { return L10n.tr("Localizable", "social_groups_discover_title", fallback: "Discover") }
  /// Empty state when the account belongs to no groups
  internal static var socialGroupsEmpty: String { return L10n.tr("Localizable", "social_groups_empty", fallback: "Create a group or join a public one to share episodes with people.") }
  /// Section header for the account's own groups
  internal static var socialGroupsMineTitle: String { return L10n.tr("Localizable", "social_groups_mine_title", fallback: "My Groups") }
  /// Title of the Groups hub screen
  internal static var socialGroupsTitle: String { return L10n.tr("Localizable", "social_groups_title", fallback: "Groups") }
  /// Shown when a handle is available. %1$@ is the normalized @handle
  internal static func socialHandleAvailable(_ p1: Any) -> String {
    return L10n.tr("Localizable", "social_handle_available", String(describing: p1), fallback: "%1$@ is available")
  }
  /// Shown when the availability check could not reach the server
  internal static var socialHandleCheckFailed: String { return L10n.tr("Localizable", "social_handle_check_failed", fallback: "Couldn't check availability") }
  /// Shown while the handle availability check is running
  internal static var socialHandleChecking: String { return L10n.tr("Localizable", "social_handle_checking", fallback: "Checking availability…") }
  /// Shown when the requested handle has invalid characters or length
  internal static var socialHandleInvalid: String { return L10n.tr("Localizable", "social_handle_invalid", fallback: "3–30 lowercase letters, numbers or underscores") }
  /// Note under the handle field about immutability
  internal static var socialHandlePermanent: String { return L10n.tr("Localizable", "social_handle_permanent", fallback: "3–30 characters: lowercase letters, numbers, underscores. Handles are permanent.") }
  /// Placeholder for the handle entry field
  internal static var socialHandlePlaceholder: String { return L10n.tr("Localizable", "social_handle_placeholder", fallback: "yourname") }
  /// Prompt above the handle entry field
  internal static var socialHandlePrompt: String { return L10n.tr("Localizable", "social_handle_prompt", fallback: "Choose your handle") }
  /// Shown when the requested handle is reserved or retired
  internal static var socialHandleReserved: String { return L10n.tr("Localizable", "social_handle_reserved", fallback: "Not available") }
  /// Shown when the requested handle is already taken
  internal static var socialHandleTaken: String { return L10n.tr("Localizable", "social_handle_taken", fallback: "Already taken") }
  /// Navigation title of the handle selection step
  internal static var socialHandleTitle: String { return L10n.tr("Localizable", "social_handle_title", fallback: "Your @handle") }
  /// Footer explaining the heatmap is device-local
  internal static var socialHeatmapLocalNote: String { return L10n.tr("Localizable", "social_heatmap_local_note", fallback: "Your activity grid is computed on this device and isn't shown on your public page.") }
  /// Podcast-page line when the show has fandom hubs (plural). %1$d is the count
  internal static func socialHubsCount(_ p1: Int) -> String {
    return L10n.tr("Localizable", "social_hubs_count", p1, fallback: "%1$d groups about this show")
  }
  /// Podcast-page line when the show has exactly one fandom hub
  internal static var socialHubsCountSingular: String { return L10n.tr("Localizable", "social_hubs_count_singular", fallback: "1 group about this show") }
  /// Empty state of the podcast hubs sheet
  internal static var socialHubsEmpty: String { return L10n.tr("Localizable", "social_hubs_empty", fallback: "No groups about this show yet.") }
  /// Podcast-page entry to create the show's first group
  internal static var socialHubsStart: String { return L10n.tr("Localizable", "social_hubs_start", fallback: "Start a group") }
  /// Shown when the inbox has no items
  internal static var socialInboxEmpty: String { return L10n.tr("Localizable", "social_inbox_empty", fallback: "Nothing here yet. Episodes friends send you will show up here.") }
  /// Inbox section header for replies to the user's comments
  internal static var socialInboxRepliesTitle: String { return L10n.tr("Localizable", "social_inbox_replies_title", fallback: "Replies") }
  /// Inbox reply row: who replied. %1$@ = display name, %2$@ = @handle
  internal static func socialInboxReplyFrom(_ p1: Any, _ p2: Any) -> String {
    return L10n.tr("Localizable", "social_inbox_reply_from", String(describing: p1), String(describing: p2), fallback: "%1$@ (%2$@) replied to your comment")
  }
  /// Profile tab row label for the inbox with an unread count. %1$d is the count
  internal static func socialInboxRowUnread(_ p1: Int) -> String {
    return L10n.tr("Localizable", "social_inbox_row_unread", p1, fallback: "Inbox (%1$d)")
  }
  /// Inbox row attribution line. %1$@ is a display name, %2$@ is an @handle
  internal static func socialInboxSentBy(_ p1: Any, _ p2: Any) -> String {
    return L10n.tr("Localizable", "social_inbox_sent_by", String(describing: p1), String(describing: p2), fallback: "%1$@ (%2$@) sent you")
  }
  /// Navigation title of the shared-item inbox
  internal static var socialInboxTitle: String { return L10n.tr("Localizable", "social_inbox_title", fallback: "Inbox") }
  /// Button accepting the social terms and continuing to handle selection
  internal static var socialJoinAgree: String { return L10n.tr("Localizable", "social_join_agree", fallback: "Agree & Continue") }
  /// Button that performs the join/claim
  internal static var socialJoinCta: String { return L10n.tr("Localizable", "social_join_cta", fallback: "Claim Handle") }
  /// Error shown when the join request fails
  internal static var socialJoinFailed: String { return L10n.tr("Localizable", "social_join_failed", fallback: "Couldn't create your profile. The handle may have just been taken, or your name was rejected.") }
  /// Intro paragraph of the Join flow explaining the opt-in public identity
  internal static var socialJoinIntro: String { return L10n.tr("Localizable", "social_join_intro", fallback: "Create a public profile so friends can find you. Nothing is shared until you join, and everything starts private.") }
  /// Join flow bullet: erasure right
  internal static var socialJoinPointErase: String { return L10n.tr("Localizable", "social_join_point_erase", fallback: "Delete your profile any time; your handle is retired, never reused") }
  /// Join flow bullet: the permanent handle
  internal static var socialJoinPointHandle: String { return L10n.tr("Localizable", "social_join_point_handle", fallback: "Pick a permanent @handle — it can never be changed") }
  /// Join flow bullet: privacy default
  internal static var socialJoinPointPrivate: String { return L10n.tr("Localizable", "social_join_point_private", fallback: "Every field starts private — you choose what to show") }
  /// Join flow terms acceptance note shown above the agree button
  internal static var socialJoinTerms: String { return L10n.tr("Localizable", "social_join_terms", fallback: "By joining you agree that your display name and anything you set to public are visible to everyone.") }
  /// Title of the opt-in social Join flow and its navigation bar
  internal static var socialJoinTitle: String { return L10n.tr("Localizable", "social_join_title", fallback: "Join Social") }
  /// Attribution chip on a shared-list entry. %1$@ = adder @handle
  internal static func socialListAddedBy(_ p1: Any) -> String {
    return L10n.tr("Localizable", "social_list_added_by", String(describing: p1), fallback: "added by %1$@")
  }
  /// Byline under a shared list's title. %1$@ = owner @handle
  internal static func socialListByline(_ p1: Any) -> String {
    return L10n.tr("Localizable", "social_list_byline", String(describing: p1), fallback: "A list by %1$@")
  }
  /// Placeholder for the shared list's description field
  internal static var socialListDescriptionPlaceholder: String { return L10n.tr("Localizable", "social_list_description_placeholder", fallback: "Description (optional)") }
  /// Episode count on a shared-list row. %1$d = count
  internal static func socialListEpisodeCount(_ p1: Int) -> String {
    return L10n.tr("Localizable", "social_list_episode_count", p1, fallback: "%1$d episodes")
  }
  /// Singular of social_list_episode_count
  internal static var socialListEpisodeCountSingular: String { return L10n.tr("Localizable", "social_list_episode_count_singular", fallback: "1 episode") }
  /// Button sending a collaboration invite
  internal static var socialListInvite: String { return L10n.tr("Localizable", "social_list_invite", fallback: "Invite") }
  /// Footer of the invite field explaining consent
  internal static var socialListInviteFooter: String { return L10n.tr("Localizable", "social_list_invite_footer", fallback: "They'll get an invite to accept before they can edit. Up to 20 collaborators.") }
  /// Who invited the user to a list. %1$@ = owner @handle
  internal static func socialListInviteFrom(_ p1: Any) -> String {
    return L10n.tr("Localizable", "social_list_invite_from", String(describing: p1), fallback: "%1$@ invited you to collaborate")
  }
  /// Section header for pending list-collaboration invites
  internal static var socialListInvitesTitle: String { return L10n.tr("Localizable", "social_list_invites_title", fallback: "List Invites") }
  /// Title of the shared-list members sheet and its toolbar button
  internal static var socialListMembers: String { return L10n.tr("Localizable", "social_list_members", fallback: "Members") }
  /// Local mirror playlist name for a shared list. %1$@ = list title, %2$@ = owner handle without the @ prefix
  internal static func socialListMirrorName(_ p1: Any, _ p2: Any) -> String {
    return L10n.tr("Localizable", "social_list_mirror_name", String(describing: p1), String(describing: p2), fallback: "%1$@ · @%2$@")
  }
  /// Confirm button of the publish-list sheet
  internal static var socialListPublishCta: String { return L10n.tr("Localizable", "social_list_publish_cta", fallback: "Publish") }
  /// Error when publishing a list fails
  internal static var socialListPublishFailed: String { return L10n.tr("Localizable", "social_list_publish_failed", fallback: "Couldn't publish the list.") }
  /// Footer when publishing snapshots a smart/custom playlist's current results
  internal static var socialListPublishMaterializeNote: String { return L10n.tr("Localizable", "social_list_publish_materialize_note", fallback: "Publishes a snapshot of this playlist's current episodes as a new shared list. The playlist itself stays personal.") }
  /// Footer for publishing a manual playlist in place
  internal static var socialListPublishNote: String { return L10n.tr("Localizable", "social_list_publish_note", fallback: "Publishes this list to your profile at the visibility you choose. You can invite collaborators afterwards from Members.") }
  /// Title of the publish-list sheet
  internal static var socialListPublishTitle: String { return L10n.tr("Localizable", "social_list_publish_title", fallback: "Share as List") }
  /// Button removing a member from a shared list (owner only)
  internal static var socialListRemoveMember: String { return L10n.tr("Localizable", "social_list_remove_member", fallback: "Remove") }
  /// Role label: the account co-edits this list
  internal static var socialListRoleCollaborator: String { return L10n.tr("Localizable", "social_list_role_collaborator", fallback: "Collaborator") }
  /// Role label: invitation not yet answered
  internal static var socialListRoleInvited: String { return L10n.tr("Localizable", "social_list_role_invited", fallback: "Invited") }
  /// Role label: the account owns this list
  internal static var socialListRoleOwner: String { return L10n.tr("Localizable", "social_list_role_owner", fallback: "Owner") }
  /// Role label: the account follows this list read-only
  internal static var socialListRoleSubscriber: String { return L10n.tr("Localizable", "social_list_role_subscriber", fallback: "Subscribed") }
  /// Button to follow a shared list read-only
  internal static var socialListSubscribe: String { return L10n.tr("Localizable", "social_list_subscribe", fallback: "Subscribe") }
  /// Placeholder for the shared list's title field
  internal static var socialListTitlePlaceholder: String { return L10n.tr("Localizable", "social_list_title_placeholder", fallback: "List name") }
  /// Button to stop following a shared list
  internal static var socialListUnsubscribe: String { return L10n.tr("Localizable", "social_list_unsubscribe", fallback: "Unsubscribe") }
  /// Empty state for the shared-lists hub
  internal static var socialListsEmpty: String { return L10n.tr("Localizable", "social_lists_empty", fallback: "Lists you publish, co-edit or subscribe to will show up here.") }
  /// Title of the shared-lists hub screen
  internal static var socialListsTitle: String { return L10n.tr("Localizable", "social_lists_title", fallback: "Shared Lists") }
  /// Celebration card for your own episodes milestone. %1$d is the tier
  internal static func socialMilestoneCelebrationEpisodes(_ p1: Int) -> String {
    return L10n.tr("Localizable", "social_milestone_celebration_episodes", p1, fallback: "You finished %1$d episodes!")
  }
  /// Celebration card for your own hours milestone. %1$d is the tier
  internal static func socialMilestoneCelebrationHours(_ p1: Int) -> String {
    return L10n.tr("Localizable", "social_milestone_celebration_hours", p1, fallback: "You crossed %1$d hours listened!")
  }
  /// Share button on the milestone celebration card
  internal static var socialMilestoneShare: String { return L10n.tr("Localizable", "social_milestone_share", fallback: "Share your stats") }
  /// Overflow action that hides a person's items from the activity feed without blocking them
  internal static var socialMute: String { return L10n.tr("Localizable", "social_mute", fallback: "Mute") }
  /// Notification-settings toggle for the weekly digest push
  internal static var socialNotificationsDigest: String { return L10n.tr("Localizable", "social_notifications_digest", fallback: "Weekly digest") }
  /// Toggle: push when your follow request is approved
  internal static var socialNotificationsFollowApproved: String { return L10n.tr("Localizable", "social_notifications_follow_approved", fallback: "Request approvals") }
  /// Toggle: push when someone asks to follow you
  internal static var socialNotificationsFollowRequests: String { return L10n.tr("Localizable", "social_notifications_follow_requests", fallback: "Follow requests") }
  /// Footer under the social push toggles
  internal static var socialNotificationsFooter: String { return L10n.tr("Localizable", "social_notifications_footer", fallback: "Notifications about things addressed to you. Applies on all your devices.") }
  /// Notification-settings toggle for group invite pushes
  internal static var socialNotificationsGroupInvites: String { return L10n.tr("Localizable", "social_notifications_group_invites", fallback: "Group invites") }
  /// Notification-settings toggle for new-post pushes from groups you enabled alerts for
  internal static var socialNotificationsGroupPosts: String { return L10n.tr("Localizable", "social_notifications_group_posts", fallback: "Group posts (only groups you enable)") }
  /// Section header for social push toggles in Settings -> Notifications
  internal static var socialNotificationsHeader: String { return L10n.tr("Localizable", "social_notifications_header", fallback: "Social") }
  /// Toggle: push when someone invites you to a shared list
  internal static var socialNotificationsListInvites: String { return L10n.tr("Localizable", "social_notifications_list_invites", fallback: "List invites") }
  /// Toggle: push when someone starts following you
  internal static var socialNotificationsNewFollowers: String { return L10n.tr("Localizable", "social_notifications_new_followers", fallback: "New followers") }
  /// Toggle: push when someone replies to your comment
  internal static var socialNotificationsReplies: String { return L10n.tr("Localizable", "social_notifications_replies", fallback: "Comment replies") }
  /// Toggle: push when a friend sends you an episode
  internal static var socialNotificationsSharedItems: String { return L10n.tr("Localizable", "social_notifications_shared_items", fallback: "Sent episodes") }
  /// Trailing note on the display name row: it cannot be made private
  internal static var socialPrivacyAlwaysPublic: String { return L10n.tr("Localizable", "social_privacy_always_public", fallback: "Always public") }
  /// Toggle: new follows become requests that need the user's approval
  internal static var socialPrivacyApproveFollowers: String { return L10n.tr("Localizable", "social_privacy_approve_followers", fallback: "Approve My Followers") }
  /// Footer explaining the follow-approval toggle, including what open following means for Followers-visibility fields
  internal static var socialPrivacyApproveFollowersFooter: String { return L10n.tr("Localizable", "social_privacy_approve_followers_footer", fallback: "When on, people must ask before they can follow you. When off, anyone can follow you instantly — and every follower can see anything set to Followers.") }
  /// Privacy screen row label for the bio
  internal static var socialPrivacyBio: String { return L10n.tr("Localizable", "social_privacy_bio", fallback: "Bio") }
  /// Privacy toggle: appear in people search and suggestions
  internal static var socialPrivacyDiscoverable: String { return L10n.tr("Localizable", "social_privacy_discoverable", fallback: "Include me in search & suggestions") }
  /// Privacy screen row label for the display name
  internal static var socialPrivacyDisplayName: String { return L10n.tr("Localizable", "social_privacy_display_name", fallback: "Display name") }
  /// Privacy screen row label for followed shows
  internal static var socialPrivacyFollowedShows: String { return L10n.tr("Localizable", "social_privacy_followed_shows", fallback: "Followed shows") }
  /// Visibility option: only approved followers can see this field
  internal static var socialPrivacyFollowers: String { return L10n.tr("Localizable", "social_privacy_followers", fallback: "Followers") }
  /// Privacy screen footer explaining the toggles
  internal static var socialPrivacyFooter: String { return L10n.tr("Localizable", "social_privacy_footer", fallback: "Public fields appear on your profile page. Fields set to Followers are visible to everyone you've let follow you.") }
  /// Privacy screen row label for listening history
  internal static var socialPrivacyHistory: String { return L10n.tr("Localizable", "social_privacy_history", fallback: "Recently played") }
  /// Privacy screen section header for identity fields
  internal static var socialPrivacyIdentityHeader: String { return L10n.tr("Localizable", "social_privacy_identity_header", fallback: "Identity") }
  /// Privacy screen section header for listening data fields
  internal static var socialPrivacyListeningHeader: String { return L10n.tr("Localizable", "social_privacy_listening_header", fallback: "Listening") }
  /// Header shown when the privacy screen appears right after joining
  internal static var socialPrivacyNudgeHeader: String { return L10n.tr("Localizable", "social_privacy_nudge_header", fallback: "Your profile is private right now. Choose what to show on your public page — you can change this any time.") }
  /// Toggle subtitle when a field is private
  internal static var socialPrivacyPrivate: String { return L10n.tr("Localizable", "social_privacy_private", fallback: "Private") }
  /// Toggle subtitle when a field is public
  internal static var socialPrivacyPublic: String { return L10n.tr("Localizable", "social_privacy_public", fallback: "Public") }
  /// Error shown when saving privacy settings fails
  internal static var socialPrivacySaveFailed: String { return L10n.tr("Localizable", "social_privacy_save_failed", fallback: "Couldn't save your privacy settings. Try again.") }
  /// Privacy screen row label for listening stats
  internal static var socialPrivacyStats: String { return L10n.tr("Localizable", "social_privacy_stats", fallback: "Listening stats") }
  /// Navigation title of the social privacy screen
  internal static var socialPrivacyTitle: String { return L10n.tr("Localizable", "social_privacy_title", fallback: "Profile Privacy") }
  /// Privacy screen row label for top podcasts
  internal static var socialPrivacyTopPodcasts: String { return L10n.tr("Localizable", "social_privacy_top_podcasts", fallback: "Top podcasts") }
  /// Error shown when the picked avatar image is not a JPEG or PNG the server accepts.
  internal static var socialProfileAvatarInvalidFormat: String { return L10n.tr("Localizable", "social_profile_avatar_invalid_format", fallback: "Choose a valid JPEG or PNG image.") }
  /// Error shown when the picked avatar image could not be loaded from the photo library.
  internal static var socialProfileAvatarReadFailed: String { return L10n.tr("Localizable", "social_profile_avatar_read_failed", fallback: "Unable to read that image.") }
  /// Error shown when removing the profile avatar fails.
  internal static var socialProfileAvatarRemoveFailed: String { return L10n.tr("Localizable", "social_profile_avatar_remove_failed", fallback: "Unable to remove the avatar. Try again later.") }
  /// Error shown when the server's nudity/racy-content scan rejects the avatar image.
  internal static var socialProfileAvatarScanRejected: String { return L10n.tr("Localizable", "social_profile_avatar_scan_rejected", fallback: "That image was rejected by the nudity/racy-content filter.") }
  /// Error shown when the avatar image exceeds the 10 MB upload limit.
  internal static var socialProfileAvatarTooLarge: String { return L10n.tr("Localizable", "social_profile_avatar_too_large", fallback: "Choose a JPEG or PNG smaller than 10 MB.") }
  /// Error shown when the avatar upload fails for a reason other than format or moderation.
  internal static var socialProfileAvatarUploadFailed: String { return L10n.tr("Localizable", "social_profile_avatar_upload_failed", fallback: "Unable to update the avatar. Try again later.") }
  /// Button opening the profile edit sheet
  internal static var socialProfileEdit: String { return L10n.tr("Localizable", "social_profile_edit", fallback: "Edit Profile") }
  /// Shown when a profile does not exist or is unavailable to the viewer
  internal static var socialProfileNotFound: String { return L10n.tr("Localizable", "social_profile_not_found", fallback: "This profile isn't available") }
  /// Row that shares the public profile link
  internal static var socialProfileShareLink: String { return L10n.tr("Localizable", "social_profile_share_link", fallback: "Share Profile Link") }
  /// Navigation title of the own social profile screen
  internal static var socialProfileTitle: String { return L10n.tr("Localizable", "social_profile_title", fallback: "My Profile") }
  /// Podcast social proof, counts only. %1$d = count of followees
  internal static func socialProofCountOnly(_ p1: Int) -> String {
    return L10n.tr("Localizable", "social_proof_count_only", p1, fallback: "Followed by %1$d people you follow")
  }
  /// Singular of social_proof_count_only
  internal static var socialProofCountOnlySingular: String { return L10n.tr("Localizable", "social_proof_count_only_singular", fallback: "Followed by 1 person you follow") }
  /// Podcast social proof with names. %1$@ = comma-joined @handles
  internal static func socialProofNamed(_ p1: Any) -> String {
    return L10n.tr("Localizable", "social_proof_named", String(describing: p1), fallback: "Followed by %1$@")
  }
  /// Podcast social proof, names + remainder. %1$@ = @handles, %2$d = more count
  internal static func socialProofNamedAndMore(_ p1: Any, _ p2: Int) -> String {
    return L10n.tr("Localizable", "social_proof_named_and_more", String(describing: p1), p2, fallback: "Followed by %1$@ and %2$d more you follow")
  }
  /// Hint shown when the user hasn't listened enough to react
  internal static var socialReactionsGateHint: String { return L10n.tr("Localizable", "social_reactions_gate_hint", fallback: "Listen to a bit more of this episode to react.") }
  /// Title of the episode reactions row
  internal static var socialReactionsTitle: String { return L10n.tr("Localizable", "social_reactions_title", fallback: "Reactions") }
  /// Report action label
  internal static var socialReport: String { return L10n.tr("Localizable", "social_report", fallback: "Report") }
  /// Report reason: harassment
  internal static var socialReportHarassment: String { return L10n.tr("Localizable", "social_report_harassment", fallback: "Harassment") }
  /// Report reason: hate
  internal static var socialReportHate: String { return L10n.tr("Localizable", "social_report_hate", fallback: "Hate") }
  /// Report reason: impersonation
  internal static var socialReportImpersonation: String { return L10n.tr("Localizable", "social_report_impersonation", fallback: "Impersonation") }
  /// Report reason: other
  internal static var socialReportOther: String { return L10n.tr("Localizable", "social_report_other", fallback: "Other") }
  /// Report reason: sexual content
  internal static var socialReportSexual: String { return L10n.tr("Localizable", "social_report_sexual", fallback: "Sexual content") }
  /// Report reason: spam
  internal static var socialReportSpam: String { return L10n.tr("Localizable", "social_report_spam", fallback: "Spam") }
  /// Title of the report reason picker
  internal static var socialReportTitle: String { return L10n.tr("Localizable", "social_report_title", fallback: "Report this profile") }
  /// Destructive button deleting the user's review
  internal static var socialReviewDelete: String { return L10n.tr("Localizable", "social_review_delete", fallback: "Delete review") }
  /// Button opening the review editor to edit an existing review
  internal static var socialReviewEdit: String { return L10n.tr("Localizable", "social_review_edit", fallback: "Edit your review") }
  /// Footer of the review editor explaining attribution
  internal static var socialReviewEditorNote: String { return L10n.tr("Localizable", "social_review_editor_note", fallback: "Your review is public and shown with your @handle. Star ratings stay separate and anonymous.") }
  /// Error when a review submission is rejected
  internal static var socialReviewRejected: String { return L10n.tr("Localizable", "social_review_rejected", fallback: "Couldn't post your review. Listen to a couple of episodes first, or check your wording.") }
  /// Button opening the review editor when the user has no review yet
  internal static var socialReviewWrite: String { return L10n.tr("Localizable", "social_review_write", fallback: "Write a review") }
  /// Section header for the review list. %1$d is the number of reviews
  internal static func socialReviewsCount(_ p1: Int) -> String {
    return L10n.tr("Localizable", "social_reviews_count", p1, fallback: "Reviews (%1$d)")
  }
  /// Shown when a podcast has no written reviews yet
  internal static var socialReviewsEmpty: String { return L10n.tr("Localizable", "social_reviews_empty", fallback: "No written reviews yet. Be the first!") }
  /// Button loading the next page of reviews
  internal static var socialReviewsLoadMore: String { return L10n.tr("Localizable", "social_reviews_load_more", fallback: "Load more") }
  /// Link on the podcast page opening the reviews screen
  internal static var socialReviewsSee: String { return L10n.tr("Localizable", "social_reviews_see", fallback: "See ratings & reviews") }
  /// Navigation title of the reviews screen
  internal static var socialReviewsTitle: String { return L10n.tr("Localizable", "social_reviews_title", fallback: "Ratings & Reviews") }
  /// Save button used in social edit screens
  internal static var socialSave: String { return L10n.tr("Localizable", "social_save", fallback: "Save") }
  /// Section header for the followed shows list
  internal static var socialSectionFollowedShows: String { return L10n.tr("Localizable", "social_section_followed_shows", fallback: "Followed shows") }
  /// Section header for the listening heatmap on the own profile
  internal static var socialSectionHeatmap: String { return L10n.tr("Localizable", "social_section_heatmap", fallback: "Listening activity") }
  /// Profile section header for a person's shared lists
  internal static var socialSectionLists: String { return L10n.tr("Localizable", "social_section_lists", fallback: "Lists") }
  /// Section header for the recently played list
  internal static var socialSectionRecentlyPlayed: String { return L10n.tr("Localizable", "social_section_recently_played", fallback: "Recently played") }
  /// Section header for listening stats on a public profile
  internal static var socialSectionStats: String { return L10n.tr("Localizable", "social_section_stats", fallback: "Listening") }
  /// Section header for the top podcasts list
  internal static var socialSectionTopPodcasts: String { return L10n.tr("Localizable", "social_section_top_podcasts", fallback: "Top podcasts") }
  /// Button performing the send
  internal static var socialSendCta: String { return L10n.tr("Localizable", "social_send_cta", fallback: "Send") }
  /// Error when a send fails (unknown recipient, rejected note, or offline)
  internal static var socialSendFailed: String { return L10n.tr("Localizable", "social_send_failed", fallback: "Couldn't send. Check the handle and your note.") }
  /// Shows the listen-from position carried with the send. %1$@ is a play time like 14:30
  internal static func socialSendFromTimestamp(_ p1: Any) -> String {
    return L10n.tr("Localizable", "social_send_from_timestamp", String(describing: p1), fallback: "Starts at %1$@")
  }
  /// Section header for the optional note field
  internal static var socialSendNoteHeader: String { return L10n.tr("Localizable", "social_send_note_header", fallback: "Note") }
  /// Placeholder for the optional note field
  internal static var socialSendNotePlaceholder: String { return L10n.tr("Localizable", "social_send_note_placeholder", fallback: "Add a note (optional)") }
  /// Section header for the recipient handle field
  internal static var socialSendRecipientHeader: String { return L10n.tr("Localizable", "social_send_recipient_header", fallback: "To") }
  /// Shown when the recipient handle doesn't match a joined profile
  internal static var socialSendRecipientNotFound: String { return L10n.tr("Localizable", "social_send_recipient_not_found", fallback: "No one with that handle") }
  /// Toast after a successful send. %1$@ is the recipient @handle
  internal static func socialSendSuccess(_ p1: Any) -> String {
    return L10n.tr("Localizable", "social_send_success", String(describing: p1), fallback: "Sent to %1$@")
  }
  /// Title of the send-to-friend sheet and its share-destination button
  internal static var socialSendTitle: String { return L10n.tr("Localizable", "social_send_title", fallback: "Send to Friend") }
  /// Stats row label: total hours listened
  internal static var socialStatsHoursListened: String { return L10n.tr("Localizable", "social_stats_hours_listened", fallback: "Hours listened") }
  /// Stats row label: date listening started
  internal static var socialStatsListeningSince: String { return L10n.tr("Localizable", "social_stats_listening_since", fallback: "Listening since") }
  /// Header for the Explore trending-with-friends row
  internal static var socialTrendingHeader: String { return L10n.tr("Localizable", "social_trending_header", fallback: "Trending with friends") }
  /// Listener count under a trending podcast. %1$d = distinct friends
  internal static func socialTrendingListeners(_ p1: Int) -> String {
    return L10n.tr("Localizable", "social_trending_listeners", p1, fallback: "%1$d friends listened recently")
  }
  /// Singular of social_trending_listeners
  internal static var socialTrendingListenersSingular: String { return L10n.tr("Localizable", "social_trending_listeners_singular", fallback: "1 friend listened recently") }
  /// Unblock action label
  internal static var socialUnblock: String { return L10n.tr("Localizable", "social_unblock", fallback: "Unblock") }
  /// Menu action to stop following this profile (also cancels a pending request)
  internal static var socialUnfollow: String { return L10n.tr("Localizable", "social_unfollow", fallback: "Unfollow") }
  /// Overflow action that undoes muting a person
  internal static var socialUnmute: String { return L10n.tr("Localizable", "social_unmute", fallback: "Unmute") }
  /// Prompt to confirm when presented with a connection prompt. Used when connecting to a Sonos speaker.
  internal static var sonosConnectAction: String { return L10n.tr("Localizable", "sonos_connect_action", fallback: "CONNECT") }
  /// Prompt to connect to a Sonos speaker. 'Sonos' refers the the speaker manufacturer.
  internal static var sonosConnectPrompt: String { return L10n.tr("Localizable", "sonos_connect_prompt", fallback: "Connect To Sonos") }
  /// Notice indicating that the app is attempting to make a connection to a Sonos device. 'Sonos' refers the the speaker manufacturer.
  internal static var sonosConnecting: String { return L10n.tr("Localizable", "sonos_connecting", fallback: "CONNECTING...") }
  /// Notice indicating that the app failed to make a connection to a Sonos device because the accounts weren't successfully linked. 'Sonos' refers the the speaker manufacturer.
  internal static var sonosConnectionFailedAccountLink: String { return L10n.tr("Localizable", "sonos_connection_failed_account_link", fallback: "Unable to link Pocket Casts account at this time. Please try again later.") }
  /// Notice indicating that the app failed to make a connection to a Sonos device because because it couldn't detect the Sonos App. 'Sonos' refers the the speaker manufacturer.
  internal static var sonosConnectionFailedAppMissing: String { return L10n.tr("Localizable", "sonos_connection_failed_app_missing", fallback: "Unable to open Sonos app to complete linking process.") }
  /// Notice indicating that the app failed to make a connection to a Sonos device. 'Sonos' refers the the speaker manufacturer.
  internal static var sonosConnectionFailedTitle: String { return L10n.tr("Localizable", "sonos_connection_failed_title", fallback: "Linking Failed") }
  /// Notice informing the users about what data will be provided to the Sonos speaker upon connection. 'Sonos' refers the the speaker manufacturer.
  internal static var sonosConnectionPrivacyNotice: String { return L10n.tr("Localizable", "sonos_connection_privacy_notice", fallback: "Connecting to Sonos will allow the Sonos app to access your episode information.\n\nYour email address, password and other sensitive items are never shared.") }
  /// Notice informing the users they need Pocket Casts account and need to sign in before connecting to the Sonos speaker. 'Sonos' refers the the speaker manufacturer.
  internal static var sonosConnectionSignInPrompt: String { return L10n.tr("Localizable", "sonos_connection_sign_in_prompt", fallback: "You need to have a Pocket Casts account before you can connect with Sonos.") }
  /// A common string used throughout the app. Prompt for the sort option menus.
  internal static var sortBy: String { return L10n.tr("Localizable", "sort_by", fallback: "Sort By") }
  /// A common string used throughout the app. Title accompanying the sort option setting.
  internal static var sortEpisodes: String { return L10n.tr("Localizable", "sort_episodes", fallback: "Sort Episodes") }
  /// Title of an option in a menu prompt
  internal static var sortOptionTimestamp: String { return L10n.tr("Localizable", "sort_option_timestamp", fallback: "Timestamp") }
  /// Used next to a setting for how fast audio will play
  internal static var speed: String { return L10n.tr("Localizable", "speed", fallback: "Speed") }
  /// A common string used throughout the app. Prompt to mark an episode(s) as favorited.
  internal static var starEpisode: String { return L10n.tr("Localizable", "star_episode", fallback: "Star Episode") }
  /// A common string used throughout the app. Prompt to mark an episode(s) as favorited. Similar to 'Star Episode' but more concise.
  internal static var starEpisodeShort: String { return L10n.tr("Localizable", "star_episode_short", fallback: "Star") }
  /// A button title that prompts the user upgrade to redeem a free trial
  internal static var startFreeTrial: String { return L10n.tr("Localizable", "start_free_trial", fallback: "Start Free Trial") }
  /// Accessibility message for the cell displaying the time for how long they've listened to Pocket Casts. '%1$@' is a placeholder for how long they've listened and '%2$@' is a placeholder for a localized funny stat related to their listening history.
  internal static func statsAccessibilityListenHistoryFormat(_ p1: Any, _ p2: Any) -> String {
    return L10n.tr("Localizable", "stats_accessibility_listen_history_format", String(describing: p1), String(describing: p2), fallback: "You've listened for %1$@. %2$@")
  }
  /// Row header that displays the amount of time saved from Auto skipping episode parts.
  internal static var statsAutoSkip: String { return L10n.tr("Localizable", "stats_auto_skip", fallback: "Auto Skipping") }
  /// Error message for when stats fail to load due to internet connection error.
  internal static var statsError: String { return L10n.tr("Localizable", "stats_error", fallback: "Unable to load stats, check your Internet connection") }
  /// Message informing the user how long they've been a user. '%1$@' is a placeholder for the date for when they created their account.
  internal static func statsListenHistoryFormat(_ p1: Any) -> String {
    return L10n.tr("Localizable", "stats_listen_history_format", String(describing: p1), fallback: "Since %1$@ you’ve listened for")
  }
  /// Loading message displayed while stats are being pulled.
  internal static var statsListenHistoryLoading: String { return L10n.tr("Localizable", "stats_listen_history_loading", fallback: "You’ve listened for") }
  /// Header for the cell displaying the time for how long they've listened to Pocket Casts.
  internal static var statsListenHistoryNoDate: String { return L10n.tr("Localizable", "stats_listen_history_no_date", fallback: "You’ve listened for") }
  /// VoiceOver label for the listening activity heatmap. '%1$@' is a placeholder for the number of days with listening activity out of the last 365.
  internal static func statsListeningActivityAccessibilityLabel(_ p1: Any) -> String {
    return L10n.tr("Localizable", "stats_listening_activity_accessibility_label", String(describing: p1), fallback: "Listening activity heatmap. Days listened: %1$@ of 365.")
  }
  /// VoiceOver label for the info button next to the listening activity section header.
  internal static var statsListeningActivityInfoAccessibilityLabel: String { return L10n.tr("Localizable", "stats_listening_activity_info_accessibility_label", fallback: "About listening activity") }
  /// Body text for the sheet that explains how the listening activity heatmap is calculated.
  internal static var statsListeningActivityInfoMessage: String { return L10n.tr("Localizable", "stats_listening_activity_info_message", fallback: "An estimate of when you've been listening, based on your playback history. If you finish an episode over a few days, it shows on the last day.") }
  /// Title for the sheet that explains how the listening activity heatmap is calculated.
  internal static var statsListeningActivityInfoTitle: String { return L10n.tr("Localizable", "stats_listening_activity_info_title", fallback: "Listening activity") }
  /// Label for the low end of the heatmap legend
  internal static var statsListeningActivityLegendLess: String { return L10n.tr("Localizable", "stats_listening_activity_legend_less", fallback: "Less") }
  /// Label for the high end of the heatmap legend
  internal static var statsListeningActivityLegendMore: String { return L10n.tr("Localizable", "stats_listening_activity_legend_more", fallback: "More") }
  /// Title for the listening activity heatmap on the account screen
  internal static var statsListeningActivitySectionTitle: String { return L10n.tr("Localizable", "stats_listening_activity_section_title", fallback: "Listening Activity") }
  /// Row header that displays the amount of time saved from the Skip forward feature.
  internal static var statsSkipping: String { return L10n.tr("Localizable", "stats_skipping", fallback: "Skipping") }
  /// Section header that breaks down how much listening time has been saved across a variety of features.
  internal static var statsTimeSaved: String { return L10n.tr("Localizable", "stats_time_saved", fallback: "TIME SAVED BY") }
  /// A placeholder string for when the app fails to generate a time from the given inputs.
  internal static var statsTimeZeroSeconds: String { return L10n.tr("Localizable", "stats_time_zero_seconds", fallback: "0 seconds") }
  /// A common string used throughout the app. Status header showing the totals for accumulated stat numbers.
  internal static var statsTotal: String { return L10n.tr("Localizable", "stats_total", fallback: "Total") }
  /// Row header that displays the amount of time saved from adjusting the Playback speed feature.
  internal static var statsVariableSpeed: String { return L10n.tr("Localizable", "stats_variable_speed", fallback: "Variable Speed") }
  /// A common string used throughout the app. Status message informing the user that the episode has been downloaded.
  internal static var statusDownloaded: String { return L10n.tr("Localizable", "status_downloaded", fallback: "Downloaded") }
  /// A common string used throughout the app. Status message informing the user that the episode is downloading.
  internal static var statusDownloading: String { return L10n.tr("Localizable", "status_downloading", fallback: "Downloading") }
  /// A common string used throughout the app. Status message informing the user that the episode has not been downloaded.
  internal static var statusNotDownloaded: String { return L10n.tr("Localizable", "status_not_downloaded", fallback: "Not Downloaded") }
  /// A common string used throughout the app. Status message informing the user that the episode is currently not selected. Used with accessibility.
  internal static var statusNotSelected: String { return L10n.tr("Localizable", "status_not_selected", fallback: "Not Selected") }
  /// A common string used throughout the app. Status message informing the user that the episode has not been starred (favorited).
  internal static var statusNotStarred: String { return L10n.tr("Localizable", "status_not_starred", fallback: "Not Starred") }
  /// A common string used throughout the app. Status message informing the user that the episode has been played.
  internal static var statusPlayed: String { return L10n.tr("Localizable", "status_played", fallback: "Played") }
  /// A common string used throughout the app. Status message informing the user that the episode is currently selected. Used with accessibility.
  internal static var statusSelected: String { return L10n.tr("Localizable", "status_selected", fallback: "Selected") }
  /// A common string used throughout the app. Status message informing the user that the episode has been starred (favorited).
  internal static var statusStarred: String { return L10n.tr("Localizable", "status_starred", fallback: "Starred") }
  /// A common string used throughout the app. Status message informing the user that the episode has not been played.
  internal static var statusUnplayed: String { return L10n.tr("Localizable", "status_unplayed", fallback: "Unplayed") }
  /// A common string used throughout the app. Prompt to cancel the download for the selected item(s).
  internal static var stopDownload: String { return L10n.tr("Localizable", "stop_download", fallback: "Stop Download") }
  /// Prompt to subscribe to the selected podcast.
  internal static var subscribe: String { return L10n.tr("Localizable", "subscribe", fallback: "Subscribe") }
  /// Prompt to subscribe to all of the selected podcast.
  internal static var subscribeAll: String { return L10n.tr("Localizable", "subscribe_all", fallback: "Subscribe All") }
  /// Label indicating that the user is currently subscribed to the selected podcast.
  internal static var subscribed: String { return L10n.tr("Localizable", "subscribed", fallback: "Subscribed") }
  /// Title for the subscription details page informing the users that the selected subscription has been canceled.
  internal static var subscriptionCancelled: String { return L10n.tr("Localizable", "subscription_cancelled", fallback: "Subscription Cancelled") }
  /// Message on the subscription details page informing the users when the canceled subscription will officially end. '%1$@' is a placeholder for the date in which the subscription expires.
  internal static func subscriptionCancelledMsg(_ p1: Any) -> String {
    return L10n.tr("Localizable", "subscription_cancelled_msg", String(describing: p1), fallback: "Subscription Cancelled %1$@ ")
  }
  /// Expires in %1$@
  internal static func subscriptionExpiresIn(_ p1: Any) -> String {
    return L10n.tr("Localizable", "subscription_expires_in", String(describing: p1), fallback: "Expires in %1$@")
  }
  /// Subscription Plan title for custom upgrade screen for the bookmarks feature
  internal static var subscriptionFeatureCustomTitleBookmarks: String { return L10n.tr("Localizable", "subscription_feature_custom_title_bookmarks", fallback: "Bookmarks: no more “where was that?”") }
  /// Subscription Plan title for custom upgrade screen for the folders feature
  internal static var subscriptionFeatureCustomTitleFolders: String { return L10n.tr("Localizable", "subscription_feature_custom_title_folders", fallback: "Folders: your podcasts, perfectly placed") }
  /// Subscription Plan title for custom upgrade screen for the preselected chapters feature
  internal static var subscriptionFeatureCustomTitlePreSelectedChapters: String { return L10n.tr("Localizable", "subscription_feature_custom_title_pre_selected_chapters", fallback: "Preselect Chapters: cut to the good stuff") }
  /// Subscription Plan title for custom upgrade screen for the shuffle upnext feature
  internal static var subscriptionFeatureCustomTitleShuffleUpnext: String { return L10n.tr("Localizable", "subscription_feature_custom_title_shuffle_upnext", fallback: "Shuffle: The joy of not choosing") }
  /// Subscription pricing format, %1$@ is the price, %2$@ is the subscription period
  internal static func subscriptionFrequencyPricingFormat(_ p1: Any, _ p2: Any) -> String {
    return L10n.tr("Localizable", "subscription_frequency_pricing_format", String(describing: p1), String(describing: p2), fallback: "%1$@ per %2$@")
  }
  /// Subscription Plan text linking to feaures information
  internal static var subscriptionPlanFeaturesInfoLink: String { return L10n.tr("Localizable", "subscription_plan_features_info_link", fallback: "See all Plus features") }
  /// Subscription Plan text linking to free trial detail information
  internal static var subscriptionPlanFreeTrialInfoLink: String { return L10n.tr("Localizable", "subscription_plan_free_trial_info_link", fallback: "How does the free trial work?") }
  /// Subscription Monthly
  internal static var subscriptionPlanMonth: String { return L10n.tr("Localizable", "subscription_plan_month", fallback: "Monthly Plan") }
  /// Subscription Savings on a Yearly Plan. The %1$@ argument is the amount of saving in percentage. Ex: Save 16%
  internal static func subscriptionPlanSavings(_ p1: Any) -> String {
    return L10n.tr("Localizable", "subscription_plan_savings", String(describing: p1), fallback: "Save %1$@ ")
  }
  /// Subscription Yearly
  internal static var subscriptionPlanYear: String { return L10n.tr("Localizable", "subscription_plan_year", fallback: "Yearly Plan") }
  /// A common string used throughout the app. Thanks the user for their support. Used for paid feeds and Pocket Casts Plus.
  internal static var subscriptionsThankYou: String { return L10n.tr("Localizable", "subscriptions_thank_you", fallback: "Thanks for your support!") }
  /// Suggested Folders button title to create a custom folder
  internal static var suggestedFoldersCreateCustomFolder: String { return L10n.tr("Localizable", "suggested_folders_create_custom_folder", fallback: "Create custom folder") }
  /// Suggested Folders screen description
  internal static var suggestedFoldersDescription: String { return L10n.tr("Localizable", "suggested_folders_description", fallback: "We've organized your podcasts into folders. Save now and customize later.") }
  /// Suggested Folders screen description when user already has folders
  internal static var suggestedFoldersDescriptionWithExistingFolders: String { return L10n.tr("Localizable", "suggested_folders_description_with_existing_folders", fallback: "We've organized your podcasts into folders. Save now and customize later. This will replace any existing folders.") }
  /// Suggested Folder replace confirmation action button title
  internal static var suggestedFoldersReplaceConfirmationButton: String { return L10n.tr("Localizable", "suggested_folders_replace_confirmation_button ", fallback: "Replace folders") }
  /// Suggested Folder replace confirmation details
  internal static var suggestedFoldersReplaceConfirmationDetails: String { return L10n.tr("Localizable", "suggested_folders_replace_confirmation_details ", fallback: "Accepting suggested folders will overwrite your current folders. This can’t be undone.") }
  /// Suggested Folder replace confirmation title
  internal static var suggestedFoldersReplaceConfirmationTitle: String { return L10n.tr("Localizable", "suggested_folders_replace_confirmation_title", fallback: "Replace existing folders?") }
  /// Suggested Folders screen title
  internal static var suggestedFoldersTitle: String { return L10n.tr("Localizable", "suggested_folders_title", fallback: "Smart Folders") }
  /// Suggested Folders button title to accept suggested folders
  internal static var suggestedFoldersUseSuggestedFolders: String { return L10n.tr("Localizable", "suggested_folders_use_suggested_folders", fallback: "Use these folders") }
  /// Accessibility label for dismissing a suggested highlight.
  internal static var suggestedHighlightDismiss: String { return L10n.tr("Localizable", "suggested_highlight_dismiss", fallback: "Dismiss suggestion") }
  /// Accessibility label for accepting a suggested highlight.
  internal static var suggestedHighlightKeep: String { return L10n.tr("Localizable", "suggested_highlight_keep", fallback: "Keep highlight") }
  /// Header of the review strip listing machine-suggested highlights.
  internal static var suggestedHighlightsTitle: String { return L10n.tr("Localizable", "suggested_highlights_title", fallback: "Suggested Highlights") }
  /// A label used to identify that a user is a supporter of the selected podcast.
  internal static var supporter: String { return L10n.tr("Localizable", "supporter", fallback: "Supporter") }
  /// Menu option to open details on available podcast supporter contribution options.
  internal static var supporterContributions: String { return L10n.tr("Localizable", "supporter_contributions", fallback: "Supporter Contributions") }
  /// Subtitle to prompt the user to review their supports contribution details for more information.
  internal static var supporterContributionsSubtitle: String { return L10n.tr("Localizable", "supporter_contributions_subtitle", fallback: "Check contributions for details") }
  /// Informational message informing the user that their recurring payments for supporter contributions have been canceled.
  internal static var supporterPaymentCanceled: String { return L10n.tr("Localizable", "supporter_payment_canceled", fallback: "Supporter: Cancelled") }
  /// Notice the sync failed due to an account error.
  internal static var syncAccountError: String { return L10n.tr("Localizable", "sync_account_error", fallback: "Check your username and password.") }
  /// Sync status update notifying the user that the app is logged in.
  internal static var syncAccountLogin: String { return L10n.tr("Localizable", "sync_account_login", fallback: "Logged in...") }
  /// A common string used throughout the app. Used to indicate that the sync process has failed.
  internal static var syncFailed: String { return L10n.tr("Localizable", "sync_failed", fallback: "Sync failed") }
  /// Notice that the app is syncing the up next and history for the account.
  internal static var syncInProgress: String { return L10n.tr("Localizable", "sync_in_progress", fallback: "Syncing Up Next and History") }
  /// Progress message indicating the total number of podcasts being synced. '%1$@' serves as a placeholder for the current number of synced podcasts. '%2$@' serves as a placeholder for the total number of podcasts to sync.
  internal static func syncProgress(_ p1: Any, _ p2: Any) -> String {
    return L10n.tr("Localizable", "sync_progress", String(describing: p1), String(describing: p2), fallback: "Podcast %1$@ of %2$@")
  }
  /// Progress message indicating the total number of podcasts that have been synced. '%1$@' serves as a placeholder for the current number of synced podcasts, will be more than one.
  internal static func syncProgressUnknownCountPluralFormat(_ p1: Any) -> String {
    return L10n.tr("Localizable", "sync_progress_unknown_count_plural_format", String(describing: p1), fallback: "Synced %1$@ podcasts")
  }
  /// Progress message indicating the total number of podcasts that have been synced. Used in the singular case.
  internal static var syncProgressUnknownCountSingular: String { return L10n.tr("Localizable", "sync_progress_unknown_count_singular", fallback: "Synced 1 podcast") }
  /// A common string used throughout the app. Used to indicate that the sync process in running.
  internal static var syncing: String { return L10n.tr("Localizable", "syncing", fallback: "Syncing...") }
  /// Prompt to allow the user to review the Terms of Use.
  internal static var termsOfUse: String { return L10n.tr("Localizable", "terms_of_use", fallback: "Terms of Use") }
  /// Theme name for the Classic theme.
  internal static var themeClassic: String { return L10n.tr("Localizable", "theme_classic", fallback: "Classic") }
  /// Theme name for the Dark theme.
  internal static var themeDark: String { return L10n.tr("Localizable", "theme_dark", fallback: "Default Dark") }
  /// Theme name for the Dark Contrast theme.
  internal static var themeDarkContrast: String { return L10n.tr("Localizable", "theme_dark_contrast", fallback: "Dark Contrast") }
  /// Theme name for the Electricity theme.
  internal static var themeElectricity: String { return L10n.tr("Localizable", "theme_electricity", fallback: "Electricity") }
  /// Theme name for the Extra Dark theme.
  internal static var themeExtraDark: String { return L10n.tr("Localizable", "theme_extra_dark", fallback: "Extra Dark") }
  /// Theme name for the Indigo theme.
  internal static var themeIndigo: String { return L10n.tr("Localizable", "theme_indigo", fallback: "Indigo") }
  /// Theme name for the Light theme.
  internal static var themeLight: String { return L10n.tr("Localizable", "theme_light", fallback: "Default Light") }
  /// Theme name for the Light Contrast theme.
  internal static var themeLightContrast: String { return L10n.tr("Localizable", "theme_light_contrast", fallback: "Light Contrast") }
  /// Theme name for the Radioactivity theme.
  internal static var themeRadioactivity: String { return L10n.tr("Localizable", "theme_radioactivity", fallback: "Radioactivity") }
  /// Theme name for the Rosé theme.
  internal static var themeRose: String { return L10n.tr("Localizable", "theme_rose", fallback: "Rosé") }
  /// Open ended time format describing either unknown or truly never
  internal static var timeFormatNever: String { return L10n.tr("Localizable", "time_format_never", fallback: "never") }
  /// A placeholder when time conversions fail. Sets the value to zero seconds
  internal static var timePlaceholder: String { return L10n.tr("Localizable", "time_placeholder", fallback: "0 sec") }
  /// A common string used throughout the app. Used to reference today.
  internal static var today: String { return L10n.tr("Localizable", "today", fallback: "Today") }
  /// A common string used throughout the app. Title option to place the item at the top of the queue.
  internal static var top: String { return L10n.tr("Localizable", "top", fallback: "Top") }
  /// Spoken before jumping to a tour stop. Placeholder is the stop's title.
  internal static func tourBridgeLine(_ p1: Any) -> String {
    return L10n.tr("Localizable", "tour_bridge_line", String(describing: p1), fallback: "Next: %1$@")
  }
  /// Button that stops the running tour and returns to normal playback.
  internal static var tourExit: String { return L10n.tr("Localizable", "tour_exit", fallback: "Exit Tour") }
  /// Shown when the tour played its last highlight.
  internal static var tourFinished: String { return L10n.tr("Localizable", "tour_finished", fallback: "That's the tour!") }
  /// Spoken once at tour start. First placeholder is the number of stops, second the episode title.
  internal static func tourIntroLine(_ p1: Any, _ p2: Any) -> String {
    return L10n.tr("Localizable", "tour_intro_line", String(describing: p1), String(describing: p2), fallback: "Here's your %1$@-highlight tour of %2$@.")
  }
  /// Tour length option: about half of the episode.
  internal static var tourLengthDeep: String { return L10n.tr("Localizable", "tour_length_deep", fallback: "Deep — about half") }
  /// Tour length option: about five minutes.
  internal static var tourLengthQuick: String { return L10n.tr("Localizable", "tour_length_quick", fallback: "Quick — about 5 minutes") }
  /// Tour length option: about a quarter of the episode.
  internal static var tourLengthStandard: String { return L10n.tr("Localizable", "tour_length_standard", fallback: "Standard — about 25%") }
  /// Spoken after the last tour stop.
  internal static var tourOutroLine: String { return L10n.tr("Localizable", "tour_outro_line", fallback: "That's the tour.") }
  /// Shown when a tour can't be built (no transcript or no segments).
  internal static var tourPreparationFailed: String { return L10n.tr("Localizable", "tour_preparation_failed", fallback: "Couldn't build a tour for this episode. It needs a transcript first.") }
  /// Shown while the tour analyzes the episode.
  internal static var tourPreparing: String { return L10n.tr("Localizable", "tour_preparing", fallback: "Finding the best moments…") }
  /// Tour HUD position, e.g. "Highlight 2 of 6". First placeholder is the current index, second the total.
  internal static func tourProgress(_ p1: Any, _ p2: Any) -> String {
    return L10n.tr("Localizable", "tour_progress", String(describing: p1), String(describing: p2), fallback: "Highlight %1$@ of %2$@")
  }
  /// Player shelf action + sheet title: guided playback of an episode's best moments.
  internal static var tourShelfTitle: String { return L10n.tr("Localizable", "tour_shelf_title", fallback: "Highlights Tour") }
  /// Toggle for speaking the tour's intro and transitions aloud.
  internal static var tourSpokenTransitionsToggle: String { return L10n.tr("Localizable", "tour_spoken_transitions_toggle", fallback: "Spoken transitions") }
  /// A common string used throughout the app. Often refers to the Transcript tab in the player.
  internal static var transcript: String { return L10n.tr("Localizable", "transcript", fallback: "Transcript") }
  /// Transcript error message when transcript is empty
  internal static var transcriptErrorEmpty: String { return L10n.tr("Localizable", "transcript_error_empty", fallback: "Sorry, but it looks this transcript is empty") }
  /// Transcript error message when transcript failed to load
  internal static var transcriptErrorFailedToLoad: String { return L10n.tr("Localizable", "transcript_error_failed_to_load", fallback: "Sorry, but something went wrong while loading this transcript") }
  /// Transcript error message when transcript failed to parse
  internal static var transcriptErrorFailedToParse: String { return L10n.tr("Localizable", "transcript_error_failed_to_parse", fallback: "Sorry, but something went wrong while parsing this transcript") }
  /// Transcript error message when a transcript is not available
  internal static var transcriptErrorNotAvailable: String { return L10n.tr("Localizable", "transcript_error_not_available", fallback: "Sorry, but this episode has no transcript available") }
  /// Transcript error message when transcript format is not supported. %1$@ variable represents the format type not supported. Ex: "srt"
  internal static func transcriptErrorNotSupported(_ p1: Any) -> String {
    return L10n.tr("Localizable", "transcript_error_not_supported", String(describing: p1), fallback: "Sorry, but this transcript format is not supported: %1$@")
  }
  /// Title of the button in the transcript screen that opens the full-screen transcript reader
  internal static var transcriptReader: String { return L10n.tr("Localizable", "transcript_reader", fallback: "Reader") }
  /// Label for a toggle in the transcript reader that switches the reading font between serif and sans-serif
  internal static var transcriptReaderFontSerif: String { return L10n.tr("Localizable", "transcript_reader_font_serif", fallback: "Serif font") }
  /// Title of a button that resumes auto-scrolling the transcript reader to follow the current playback position
  internal static var transcriptReaderResumeFollowing: String { return L10n.tr("Localizable", "transcript_reader_resume_following", fallback: "Resume following") }
  /// Title of a context-menu action in the transcript reader that shares the selected transcript line as an audio/video clip
  internal static var transcriptReaderShareAsClip: String { return L10n.tr("Localizable", "transcript_reader_share_as_clip", fallback: "Share as clip") }
  /// Title of a context-menu action in the transcript reader that shares the selected transcript line as a text quote
  internal static var transcriptReaderShareQuote: String { return L10n.tr("Localizable", "transcript_reader_share_quote", fallback: "Share quote") }
  /// Accessibility label for the transcript reader control that cycles through the available text sizes
  internal static var transcriptReaderTextSize: String { return L10n.tr("Localizable", "transcript_reader_text_size", fallback: "Text size") }
  /// Toast shown when the user taps inside the transcript but the fingerprint mapping has no anchors yet, so we can't resolve an accurate seek target.
  internal static var transcriptTapToSeekStreamingUnavailable: String { return L10n.tr("Localizable", "transcript_tap_to_seek_streaming_unavailable", fallback: "Download the episode to tap to seek") }
  /// Title of the toggle allowing transcription model downloads over cellular connections
  internal static var transcriptionAllowCellularDownloads: String { return L10n.tr("Localizable", "transcription_allow_cellular_downloads", fallback: "Download Over Cellular") }
  /// Footer under the cellular downloads toggle explaining model downloads wait for Wi-Fi when it is off
  internal static var transcriptionAllowCellularFooter: String { return L10n.tr("Localizable", "transcription_allow_cellular_footer", fallback: "Model downloads can be large. When off, downloads wait for an unmetered connection like Wi-Fi.") }
  /// Battery policy option: on-device transcription runs on battery only above a 30% charge
  internal static var transcriptionBatteryPolicyAbove30: String { return L10n.tr("Localizable", "transcription_battery_policy_above_30", fallback: "Above 30%% Charge") }
  /// Battery policy option: on-device transcription may always run on battery
  internal static var transcriptionBatteryPolicyAlways: String { return L10n.tr("Localizable", "transcription_battery_policy_always", fallback: "Always") }
  /// Battery policy option: on-device transcription runs only while the device is charging
  internal static var transcriptionBatteryPolicyCharging: String { return L10n.tr("Localizable", "transcription_battery_policy_charging", fallback: "Only While Charging") }
  /// Footer under the battery policy picker; explains deferral behavior and that remote providers are unaffected
  internal static var transcriptionBatteryPolicyFooter: String { return L10n.tr("Localizable", "transcription_battery_policy_footer", fallback: "Controls when on-device transcription runs while unplugged. Deferred episodes stay queued and transcribe once you charge. Low Power Mode always pauses transcription; remote providers are unaffected.") }
  /// Section header in Transcription settings for the battery policy picker controlling when on-device transcription may run
  internal static var transcriptionBatteryPolicyHeader: String { return L10n.tr("Localizable", "transcription_battery_policy_header", fallback: "Transcribe on Battery") }
  /// Title of the consent prompt button that grants consent and starts the remote transcription
  internal static var transcriptionConsentAllow: String { return L10n.tr("Localizable", "transcription_consent_allow", fallback: "Allow and Generate") }
  /// Consent prompt body for upload-based remote transcription providers. %1$@ is the provider name, e.g. "OpenAI"
  internal static func transcriptionConsentMessageUpload(_ p1: Any) -> String {
    return L10n.tr("Localizable", "transcription_consent_message_upload", String(describing: p1), fallback: "The episode's audio will be uploaded to %1$@ and transcribed using your API key. Usage may incur charges on your %1$@ account.")
  }
  /// Consent prompt body for URL-based remote transcription providers. %1$@ is the provider name, e.g. "AssemblyAI"
  internal static func transcriptionConsentMessageUrl(_ p1: Any) -> String {
    return L10n.tr("Localizable", "transcription_consent_message_url", String(describing: p1), fallback: "The episode's public audio link will be shared with %1$@, which downloads and transcribes the audio using your API key. Usage may incur charges on your %1$@ account.")
  }
  /// Title of the consent prompt shown before the first transcription with a remote provider
  internal static var transcriptionConsentTitle: String { return L10n.tr("Localizable", "transcription_consent_title", fallback: "Send this episode to a remote service?") }
  /// Title of the destructive menu action that deletes the locally generated transcript for an episode
  internal static var transcriptionDeleteGenerated: String { return L10n.tr("Localizable", "transcription_delete_generated", fallback: "Delete Generated Transcript") }
  /// Header of the transcription settings section with speaker detection options
  internal static var transcriptionDiarizationHeader: String { return L10n.tr("Localizable", "transcription_diarization_header", fallback: "Speaker Detection") }
  /// Name of the transcription engine option that uses Apple's built-in on-device speech recognition
  internal static var transcriptionEngineApple: String { return L10n.tr("Localizable", "transcription_engine_apple", fallback: "Apple Built-in") }
  /// Name of the transcription engine option that uses downloadable on-device models
  internal static var transcriptionEngineLocalModel: String { return L10n.tr("Localizable", "transcription_engine_local_model", fallback: "Downloaded Model") }
  /// Header of the transcription settings section where the user picks which speech-to-text engine to use
  internal static var transcriptionEngineMode: String { return L10n.tr("Localizable", "transcription_engine_mode", fallback: "Engine") }
  /// Name of the transcription engine option that uses a remote transcription API
  internal static var transcriptionEngineRemote: String { return L10n.tr("Localizable", "transcription_engine_remote", fallback: "Remote Provider") }
  /// Title of the button/action that starts generating an on-device transcript for a downloaded episode
  internal static var transcriptionGenerate: String { return L10n.tr("Localizable", "transcription_generate", fallback: "Generate Transcript") }
  /// Shown (as a toast and as progress text in the transcript screen) while an on-device transcript is being generated
  internal static var transcriptionGenerating: String { return L10n.tr("Localizable", "transcription_generating", fallback: "Generating…") }
  /// Shown next to the validate-key button when the key check could not be completed (e.g. no network)
  internal static var transcriptionKeyCheckFailed: String { return L10n.tr("Localizable", "transcription_key_check_failed", fallback: "Couldn't check the key. Try again.") }
  /// Shown next to the validate-key button when the provider rejected the entered API key
  internal static var transcriptionKeyInvalid: String { return L10n.tr("Localizable", "transcription_key_invalid", fallback: "Key was rejected") }
  /// Shown next to the validate-key button when the entered API key was accepted by the provider
  internal static var transcriptionKeyValid: String { return L10n.tr("Localizable", "transcription_key_valid", fallback: "Key is valid") }
  /// Shown next to the validate-key button while the key check request is running
  internal static var transcriptionKeyValidating: String { return L10n.tr("Localizable", "transcription_key_validating", fallback: "Checking key…") }
  /// Header of the transcription settings section (and label of its text field) where the user can force a transcription language
  internal static var transcriptionLanguageOverride: String { return L10n.tr("Localizable", "transcription_language_override", fallback: "Language Override") }
  /// Footer under the transcription language override text field. The quoted example is a BCP-47 language tag and should not be translated.
  internal static var transcriptionLanguageOverrideFooter: String { return L10n.tr("Localizable", "transcription_language_override_footer", fallback: "Enter a language tag such as \"en-US\" to force a transcription language. Leave empty to use the device language.") }
  /// Label of the stepper that caps how many distinct speakers a transcript can label
  internal static var transcriptionMaxSpeakers: String { return L10n.tr("Localizable", "transcription_max_speakers", fallback: "Max Speakers") }
  /// Value shown on the max-speakers stepper when speaker count detection is automatic
  internal static var transcriptionMaxSpeakersAuto: String { return L10n.tr("Localizable", "transcription_max_speakers_auto", fallback: "Auto") }
  /// Footer under the max-speakers stepper. Explains the cap and the automatic mode
  internal static var transcriptionMaxSpeakersFooter: String { return L10n.tr("Localizable", "transcription_max_speakers_footer", fallback: "Caps how many different speakers a transcript can label. Auto lets the model decide.") }
  /// Name of the second-smallest downloadable transcription model
  internal static var transcriptionModelBase: String { return L10n.tr("Localizable", "transcription_model_base", fallback: "Base") }
  /// Alert message when a transcription model download is refused because the device is on a cellular connection
  internal static var transcriptionModelCellularBlocked: String { return L10n.tr("Localizable", "transcription_model_cellular_blocked", fallback: "You're on a cellular connection. Enable Download Over Cellular or connect to Wi-Fi to download models.") }
  /// Title of the button that deletes the selected transcription model from the device
  internal static var transcriptionModelDelete: String { return L10n.tr("Localizable", "transcription_model_delete", fallback: "Delete Model") }
  /// Label of the row showing how much disk space all downloaded transcription models use
  internal static var transcriptionModelDiskUsage: String { return L10n.tr("Localizable", "transcription_model_disk_usage", fallback: "Models on Disk") }
  /// Title of the button that downloads the selected transcription model. '%1$@' is a placeholder for the approximate download size, e.g. "500 MB"
  internal static func transcriptionModelDownload(_ p1: Any) -> String {
    return L10n.tr("Localizable", "transcription_model_download", String(describing: p1), fallback: "Download Model (~%1$@)")
  }
  /// Alert message when a transcription model download fails for network or server reasons
  internal static var transcriptionModelDownloadFailed: String { return L10n.tr("Localizable", "transcription_model_download_failed", fallback: "The model couldn't be downloaded. Check your connection and try again.") }
  /// Badge shown next to a transcription model that is already downloaded to the device
  internal static var transcriptionModelDownloaded: String { return L10n.tr("Localizable", "transcription_model_downloaded", fallback: "Downloaded") }
  /// Progress label shown while a transcription model is downloading
  internal static var transcriptionModelDownloading: String { return L10n.tr("Localizable", "transcription_model_downloading", fallback: "Downloading…") }
  /// Name of the largest downloadable transcription model (most accurate)
  internal static var transcriptionModelLargeTurbo: String { return L10n.tr("Localizable", "transcription_model_large_turbo", fallback: "Large v3 Turbo") }
  /// Header of the transcription settings section listing the downloadable on-device speech-to-text models
  internal static var transcriptionModelPickerHeader: String { return L10n.tr("Localizable", "transcription_model_picker_header", fallback: "Speech Model") }
  /// Name of the mid-size downloadable transcription model (the recommended default)
  internal static var transcriptionModelSmall: String { return L10n.tr("Localizable", "transcription_model_small", fallback: "Small") }
  /// Name of the smallest downloadable transcription model (fastest, least accurate)
  internal static var transcriptionModelTiny: String { return L10n.tr("Localizable", "transcription_model_tiny", fallback: "Tiny") }
  /// Label and placeholder of the secure text field where the user enters their remote transcription service API key
  internal static var transcriptionRemoteApiKey: String { return L10n.tr("Localizable", "transcription_remote_api_key", fallback: "API Key") }
  /// Footer under the remote transcription API key field. %1$@ is the provider name, e.g. "AssemblyAI"
  internal static func transcriptionRemoteKeyFooter(_ p1: Any) -> String {
    return L10n.tr("Localizable", "transcription_remote_key_footer", String(describing: p1), fallback: "Your key is stored securely in the device keychain and is only ever sent to %1$@.")
  }
  /// Header of the transcription settings section where the user picks which remote transcription service to use
  internal static var transcriptionRemoteProvider: String { return L10n.tr("Localizable", "transcription_remote_provider", fallback: "Provider") }
  /// Footer of the speaker rename sheet, explaining that empty fields keep the numbered speaker name
  internal static var transcriptionRenameFooter: String { return L10n.tr("Localizable", "transcription_rename_footer", fallback: "Leave a field empty to keep the numbered speaker name.") }
  /// Placeholder of a speaker name text field in the rename sheet
  internal static var transcriptionRenamePlaceholder: String { return L10n.tr("Localizable", "transcription_rename_placeholder", fallback: "Custom name") }
  /// Save button of the speaker rename sheet
  internal static var transcriptionRenameSave: String { return L10n.tr("Localizable", "transcription_rename_save", fallback: "Save") }
  /// Title of the menu action and sheet for renaming the numbered speakers of a generated transcript
  internal static var transcriptionRenameSpeakers: String { return L10n.tr("Localizable", "transcription_rename_speakers", fallback: "Rename Speakers") }
  /// Tappable AI suggestion under a speaker rename field; '%1$@' is the suggested name
  internal static func transcriptionRenameSuggestion(_ p1: Any) -> String {
    return L10n.tr("Localizable", "transcription_rename_suggestion", String(describing: p1), fallback: "Suggested: %1$@")
  }
  /// Title of the Transcription page in Settings and of its row in the settings list
  internal static var transcriptionSettingsTitle: String { return L10n.tr("Localizable", "transcription_settings_title", fallback: "Transcription") }
  /// Title of the transcript source menu option that shows the locally generated transcript
  internal static var transcriptionSourceGenerated: String { return L10n.tr("Localizable", "transcription_source_generated", fallback: "Generated Transcript") }
  /// Title of the transcript source menu option that shows the transcript provided by the podcast feed
  internal static var transcriptionSourcePodcast: String { return L10n.tr("Localizable", "transcription_source_podcast", fallback: "Podcast Transcript") }
  /// Title of the button (and its confirmation action) that deletes all generated transcripts from the device
  internal static var transcriptionStorageClearAll: String { return L10n.tr("Localizable", "transcription_storage_clear_all", fallback: "Clear All Transcripts") }
  /// Confirmation message shown before deleting all generated transcripts. '%1$@' is a placeholder for the number of transcribed episodes
  internal static func transcriptionStorageClearAllConfirmation(_ p1: Any) -> String {
    return L10n.tr("Localizable", "transcription_storage_clear_all_confirmation", String(describing: p1), fallback: "This removes the generated transcripts for %1$@ episodes from this device. Episodes can be transcribed again later.")
  }
  /// Header of the transcription settings section showing storage used by generated transcripts
  internal static var transcriptionStorageHeader: String { return L10n.tr("Localizable", "transcription_storage_header", fallback: "Generated Transcripts") }
  /// Label of the row showing how much disk space generated transcripts use.
  internal static var transcriptionStorageUsage: String { return L10n.tr("Localizable", "transcription_storage_usage", fallback: "Storage Used") }
  /// Title of the button that checks whether the entered remote transcription API key works
  internal static var transcriptionValidateKey: String { return L10n.tr("Localizable", "transcription_validate_key", fallback: "Validate Key") }
  /// Label indicating that the trial period for the subscription or promotion has ended.
  internal static var trialFinished: String { return L10n.tr("Localizable", "trial_finished", fallback: "Trial Finished") }
  /// The Trim Silence feature, removes silence from podcasts to make them shorter.
  internal static var trimSilence: String { return L10n.tr("Localizable", "trim_silence", fallback: "Trim Silence") }
  /// A common string used throughout the app. Catch all prompt to suggest to the user to try the the task again.
  internal static var tryAgain: String { return L10n.tr("Localizable", "try_again", fallback: "Try Again") }
  /// Button label for a feature that the user can enable
  internal static var tryItNow: String { return L10n.tr("Localizable", "try_it_now", fallback: "Try It Now") }
  /// tv create account banner action button title
  internal static var tvBannerCreateAccountActionTitle: String { return L10n.tr("Localizable", "tv_banner_create_account_action_title", fallback: "Create a free account") }
  /// tv create account banner subtitle
  internal static var tvBannerCreateAccountSubtitle: String { return L10n.tr("Localizable", "tv_banner_create_account_subtitle", fallback: "Your follows, your progress... exactly where you left them.") }
  /// tv create account banner title
  internal static var tvBannerCreateAccountTitle: String { return L10n.tr("Localizable", "tv_banner_create_account_title", fallback: "One account. Every screen") }
  /// tv discover more banner action button title
  internal static var tvBannerDiscoverMoreActionTitle: String { return L10n.tr("Localizable", "tv_banner_discover_more_action_title", fallback: "Discover more shows") }
  /// tv discover more banner subtitle
  internal static var tvBannerDiscoverMoreSubtitle: String { return L10n.tr("Localizable", "tv_banner_discover_more_subtitle", fallback: "Your next obsession is in here somewhere.") }
  /// tv discover more banner title
  internal static var tvBannerDiscoverMoreTitle: String { return L10n.tr("Localizable", "tv_banner_discover_more_title", fallback: "You haven't seen the half of it.") }
  /// tv create account enter code
  internal static var tvCreateAccountComeBack: String { return L10n.tr("Localizable", "tv_create_account_come_back", fallback: "Once you’ve created your account, come back and sign in") }
  /// tv create account subtitle
  internal static var tvCreateAccountSubtitle: String { return L10n.tr("Localizable", "tv_create_account_subtitle", fallback: "Scan this code to get started on your phone, it only takes a minute.") }
  /// tv create account title
  internal static var tvCreateAccountTitle: String { return L10n.tr("Localizable", "tv_create_account_title", fallback: "Create your free account") }
  /// Discover - Button title on a featured podcast card that opens the podcast.
  internal static var tvDiscoverFeaturedGoToPodcast: String { return L10n.tr("Localizable", "tv_discover_featured_go_to_podcast", fallback: "Go to podcast") }
  /// Discover - Button title on a featured podcast card that plays the podcast's most recent episode.
  internal static var tvDiscoverFeaturedPlayLatestEpisode: String { return L10n.tr("Localizable", "tv_discover_featured_play_latest_episode", fallback: "Play latest episode") }
  /// Discover - Button title on a discover episode that makes it play.
  internal static var tvDiscoverPlayEpisode: String { return L10n.tr("Localizable", "tv_discover_play_episode", fallback: "Play episode") }
  /// tv episode action to view episode info
  internal static var tvEpisodeInfo: String { return L10n.tr("Localizable", "tv_episode_info", fallback: "Episode info") }
  /// tv home Browse Categories section title
  internal static var tvHomeBrowseCategoriesSectionTitle: String { return L10n.tr("Localizable", "tv_home_browse_categories_section_title", fallback: "Browse categories") }
  /// tv home Featured section title
  internal static var tvHomeFeaturedSectionTitle: String { return L10n.tr("Localizable", "tv_home_featured_section_title", fallback: "Featured on Pocket Casts") }
  /// tv keep listening title
  internal static var tvHomeKeepListeningTitle: String { return L10n.tr("Localizable", "tv_home_keep_listening_title", fallback: "Picking up where you left off") }
  /// tv home new releases section title
  internal static var tvHomeNewReleases: String { return L10n.tr("Localizable", "tv_home_new_releases", fallback: "New releases") }
  /// tv home recently played section title
  internal static var tvHomeRecentlyPlayed: String { return L10n.tr("Localizable", "tv_home_recently_played", fallback: "Recently played") }
  /// tv home recommendations for listeners of podcast title. Ex: Loved by listeners of The Daily
  internal static func tvHomeRecommendUserPodcastSectionTitle(_ p1: Any) -> String {
    return L10n.tr("Localizable", "tv_home_recommend_user_podcast_section_title", String(describing: p1), fallback: "Loved by listeners of %1$@")
  }
  /// tv home recommended for you title
  internal static var tvHomeRecommendedForYouTitle: String { return L10n.tr("Localizable", "tv_home_recommended_for_you_title", fallback: "You'll probably want these") }
  /// tv home Trending section title
  internal static var tvHomeTrendingSectionTitle: String { return L10n.tr("Localizable", "tv_home_trending_section_title", fallback: "What everyone's on this week") }
  /// tv home Video section title
  internal static var tvHomeVideoSectionTitle: String { return L10n.tr("Localizable", "tv_home_video_section_title", fallback: "Made for TV") }
  /// tv player playback effects menu title
  internal static var tvPlayerPlaybackEffects: String { return L10n.tr("Localizable", "tv_player_playback_effects", fallback: "Playback effects") }
  /// tv player playback speed menu title
  internal static var tvPlayerPlaybackSpeed: String { return L10n.tr("Localizable", "tv_player_playback_speed", fallback: "Playback speed") }
  /// tv player toast shown when playback speed changes. %1$@ is the speed value like 1.5x
  internal static func tvPlayerPlaybackSpeedSet(_ p1: Any) -> String {
    return L10n.tr("Localizable", "tv_player_playback_speed_set", String(describing: p1), fallback: "Playback speed set to %1$@")
  }
  /// tv player trim silence section title
  internal static var tvPlayerTrimSilence: String { return L10n.tr("Localizable", "tv_player_trim_silence", fallback: "Trim silence") }
  /// tv player trim silence mad max option
  internal static var tvPlayerTrimSilenceMadMax: String { return L10n.tr("Localizable", "tv_player_trim_silence_mad_max", fallback: "Mad Max") }
  /// tv player trim silence medium option
  internal static var tvPlayerTrimSilenceMedium: String { return L10n.tr("Localizable", "tv_player_trim_silence_medium", fallback: "Medium") }
  /// tv player trim silence mild option
  internal static var tvPlayerTrimSilenceMild: String { return L10n.tr("Localizable", "tv_player_trim_silence_mild", fallback: "Mild") }
  /// tv player trim silence off option
  internal static var tvPlayerTrimSilenceOff: String { return L10n.tr("Localizable", "tv_player_trim_silence_off", fallback: "Off") }
  /// tv player toast shown when trim silence setting changes. %1$@ is the selected option name
  internal static func tvPlayerTrimSilenceSet(_ p1: Any) -> String {
    return L10n.tr("Localizable", "tv_player_trim_silence_set", String(describing: p1), fallback: "Trim silence: %1$@")
  }
  /// tv player volume boost toggle title
  internal static var tvPlayerVolumeBoost: String { return L10n.tr("Localizable", "tv_player_volume_boost", fallback: "Volume boost") }
  /// tv player toast shown when volume boost is turned off
  internal static var tvPlayerVolumeBoostOff: String { return L10n.tr("Localizable", "tv_player_volume_boost_off", fallback: "Volume boost off") }
  /// tv player toast shown when volume boost is turned on
  internal static var tvPlayerVolumeBoostOn: String { return L10n.tr("Localizable", "tv_player_volume_boost_on", fallback: "Volume boost on") }
  /// tv playlist detail episode count. '%1$@' is a placeholder for the number of episodes.
  internal static func tvPlaylistDetailEpisodeCount(_ p1: Any) -> String {
    return L10n.tr("Localizable", "tv_playlist_detail_episode_count", String(describing: p1), fallback: "%1$@ episodes")
  }
  /// tv playlist detail play all button title
  internal static var tvPlaylistDetailPlayAll: String { return L10n.tr("Localizable", "tv_playlist_detail_play_all", fallback: "Play all episodes") }
  /// tv playlists empty button action title
  internal static var tvPlaylistsEmptyActionTitle: String { return L10n.tr("Localizable", "tv_playlists_empty_action_title", fallback: "Create a playlist") }
  /// tv playlists empty subtitle
  internal static var tvPlaylistsEmptySubtitle: String { return L10n.tr("Localizable", "tv_playlists_empty_subtitle", fallback: "Build one manually or let Smart Rules do the sorting for you.") }
  /// tv playlists empty title
  internal static var tvPlaylistsEmptyTitle: String { return L10n.tr("Localizable", "tv_playlists_empty_title", fallback: "Your playlists live here") }
  /// tv podcast more info about section title
  internal static var tvPodcastDetailAbout: String { return L10n.tr("Localizable", "tv_podcast_detail_about", fallback: "About") }
  /// tv podcast detail all episodes section title
  internal static var tvPodcastDetailAllEpisodes: String { return L10n.tr("Localizable", "tv_podcast_detail_all_episodes", fallback: "All episodes") }
  /// tv podcast details follow button title
  internal static var tvPodcastDetailFollowTitle: String { return L10n.tr("Localizable", "tv_podcast_detail_follow_title", fallback: "Follow this podcast") }
  /// tv podcast details following button title
  internal static var tvPodcastDetailFollowingTitle: String { return L10n.tr("Localizable", "tv_podcast_detail_following_title", fallback: "Following") }
  /// tv podcast details more info button title
  internal static var tvPodcastDetailMoreInfoTitle: String { return L10n.tr("Localizable", "tv_podcast_detail_more_info_title", fallback: "More info") }
  /// tv podcast more info network label
  internal static var tvPodcastDetailNetwork: String { return L10n.tr("Localizable", "tv_podcast_detail_network", fallback: "Network") }
  /// tv podcast more info next episode label
  internal static var tvPodcastDetailNextEpisode: String { return L10n.tr("Localizable", "tv_podcast_detail_next_episode", fallback: "Next episode") }
  /// tv podcast more info schedule label
  internal static var tvPodcastDetailSchedule: String { return L10n.tr("Localizable", "tv_podcast_detail_schedule", fallback: "Schedule") }
  /// tv podcast detail recommended episode section title
  internal static var tvPodcastDetailStartHere: String { return L10n.tr("Localizable", "tv_podcast_detail_start_here", fallback: "The episode to try first") }
  /// tv podcast detail recommended episode section subtitle
  internal static var tvPodcastDetailStartHereSubtitle: String { return L10n.tr("Localizable", "tv_podcast_detail_start_here_subtitle", fallback: "This is the one that gets people hooked") }
  /// tv podcast more info website label
  internal static var tvPodcastDetailWebsite: String { return L10n.tr("Localizable", "tv_podcast_detail_website", fallback: "Website") }
  /// tv podcasts empty button action title
  internal static var tvPodcastsEmptyActionTitle: String { return L10n.tr("Localizable", "tv_podcasts_empty_action_title", fallback: "Discover podcasts") }
  /// tv podcasts empty subtitle
  internal static var tvPodcastsEmptySubtitle: String { return L10n.tr("Localizable", "tv_podcasts_empty_subtitle", fallback: "Followed podcasts show up here, ready to play.") }
  /// tv podcasts empty title
  internal static var tvPodcastsEmptyTitle: String { return L10n.tr("Localizable", "tv_podcasts_empty_title", fallback: "Time to fill this up.") }
  /// tv Profile button — VoiceOver hint describing what happens when activating the profile button in the top bar of the main tab view
  internal static var tvProfileButtonAccessibilityHint: String { return L10n.tr("Localizable", "tv_profile_button_accessibility_hint", fallback: "Opens profile and account options") }
  /// tv Profile button — VoiceOver label for the image-only profile button shown in the top bar of the main tab view
  internal static var tvProfileButtonAccessibilityLabel: String { return L10n.tr("Localizable", "tv_profile_button_accessibility_label", fallback: "Profile") }
  /// tv Profile menu — create account action (signed-out state)
  internal static var tvProfileMenuCreateAccount: String { return L10n.tr("Localizable", "tv_profile_menu_create_account", fallback: "Create account") }
  /// tv Profile menu — log in action (signed-out state)
  internal static var tvProfileMenuLogIn: String { return L10n.tr("Localizable", "tv_profile_menu_log_in", fallback: "Log in") }
  /// tv Profile menu — log out action
  internal static var tvProfileMenuLogOut: String { return L10n.tr("Localizable", "tv_profile_menu_log_out", fallback: "Log out") }
  /// tv Profile menu — opens the Starred Episodes list
  internal static var tvProfileMenuStarredEpisodes: String { return L10n.tr("Localizable", "tv_profile_menu_starred_episodes", fallback: "Starred Episodes") }
  /// tv search error label. '%1$@' is a placeholder for a localized error description.
  internal static func tvSearchFailed(_ p1: Any) -> String {
    return L10n.tr("Localizable", "tv_search_failed", String(describing: p1), fallback: "Search failed: %1$@")
  }
  /// tv search field placeholder prompt
  internal static var tvSearchPrompt: String { return L10n.tr("Localizable", "tv_search_prompt", fallback: "Podcasts, shows, authors") }
  /// tv search in-progress indicator label
  internal static var tvSearchSearching: String { return L10n.tr("Localizable", "tv_search_searching", fallback: "Searching...") }
  /// tv search initial placeholder shown before any query is entered
  internal static var tvSearchTypeSomething: String { return L10n.tr("Localizable", "tv_search_type_something", fallback: "Type something...") }
  /// tv sign enter code
  internal static var tvSignInEnterCode: String { return L10n.tr("Localizable", "tv_sign_in_enter_code", fallback: "or enter the following code") }
  /// tv sign enter code go url.  %1$@ is the visible url and %2$@ the full url to enter the code
  internal static func tvSignInEnterCodeGoUrl(_ p1: Any, _ p2: Any) -> String {
    return L10n.tr("Localizable", "tv_sign_in_enter_code_go_url", String(describing: p1), String(describing: p2), fallback: "going to [%1$@](%2$@)")
  }
  /// tv sign enter code. '%1$@' is the visible (white, underlined) pair URL, '%2$@' is the full URL to navigate to.
  internal static func tvSignInEnterCodeInUrl(_ p1: Any, _ p2: Any) -> String {
    return L10n.tr("Localizable", "tv_sign_in_enter_code_in_url", String(describing: p1), String(describing: p2), fallback: "or enter this code in [%1$@](%2$@)")
  }
  /// tv sign in subtitle
  internal static var tvSignInSubtitle: String { return L10n.tr("Localizable", "tv_sign_in_subtitle", fallback: "Open your camera and point to this QR code") }
  /// tv sign in title
  internal static var tvSignInTitle: String { return L10n.tr("Localizable", "tv_sign_in_title", fallback: "Log in to Pocket Casts") }
  /// tv signing in subtitle
  internal static var tvSigningInSubtitle: String { return L10n.tr("Localizable", "tv_signing_in_subtitle", fallback: "Loading your podcasts now.") }
  /// tv signing in title
  internal static var tvSigningInTitle: String { return L10n.tr("Localizable", "tv_signing_in_title", fallback: "Good to see you.") }
  /// tv app home tab
  internal static var tvTabHome: String { return L10n.tr("Localizable", "tv_tab_home", fallback: "Home") }
  /// tv app Playlists tab
  internal static var tvTabPlaylists: String { return L10n.tr("Localizable", "tv_tab_playlists", fallback: "Playlists") }
  /// tv app podcasts tab
  internal static var tvTabPodcasts: String { return L10n.tr("Localizable", "tv_tab_podcasts", fallback: "Your Podcasts") }
  /// tv app Up Next tab
  internal static var tvTabUpNext: String { return L10n.tr("Localizable", "tv_tab_up_next", fallback: "Up Next") }
  /// tv up next empty button action title
  internal static var tvUpNextEmptyActionTitle: String { return L10n.tr("Localizable", "tv_up_next_empty_action_title", fallback: "Add episodes") }
  /// tv up next empty subtitle
  internal static var tvUpNextEmptySubtitle: String { return L10n.tr("Localizable", "tv_up_next_empty_subtitle", fallback: "Add episodes to Up Next and they'll play in order, back to back") }
  /// tv up next empty title
  internal static var tvUpNextEmptyTitle: String { return L10n.tr("Localizable", "tv_up_next_empty_title", fallback: "Nothing queued up") }
  /// tv User Profile actions title
  internal static var tvUserProfileActions: String { return L10n.tr("Localizable", "tv_user_profile_actions", fallback: "User settings") }
  /// tv Sign In Login Type title
  internal static var tvUserSignInLoginType: String { return L10n.tr("Localizable", "tv_user_sign_in_login_type", fallback: "Login Type") }
  /// tv Sign In Option Username and Password
  internal static var tvUserSignInOptionManual: String { return L10n.tr("Localizable", "tv_user_sign_in_option_manual", fallback: "User/Pass") }
  /// tv Sign In Option QR
  internal static var tvUserSignInOptionQr: String { return L10n.tr("Localizable", "tv_user_sign_in_option_qr", fallback: "QR") }
  /// tv welcome browse without account
  internal static var tvWelcomeBrowseWithoutAccount: String { return L10n.tr("Localizable", "tv_welcome_browse_without_account", fallback: "Browse without an account") }
  /// tv welcome create free account
  internal static var tvWelcomeCreateFreeAccount: String { return L10n.tr("Localizable", "tv_welcome_create_free_account", fallback: "Create free account") }
  /// tv welcome sign in
  internal static var tvWelcomeSignIn: String { return L10n.tr("Localizable", "tv_welcome_sign_in", fallback: "Sign in") }
  /// tv welcome subtitle
  internal static var tvWelcomeSubtitle: String { return L10n.tr("Localizable", "tv_welcome_subtitle", fallback: "Your podcasts. On the big screen. Obviously.") }
  /// tv welcome title
  internal static var tvWelcomeTitle: String { return L10n.tr("Localizable", "tv_welcome_title", fallback: "Welcome to Pocket Casts TV") }
  /// A common string used throughout the app. Prompt to restore the selected item(s) from an archived state.
  internal static var unarchive: String { return L10n.tr("Localizable", "unarchive", fallback: "Unarchive") }
  /// Label indicating that the user is currently following to the selected podcast.
  internal static var unfollow: String { return L10n.tr("Localizable", "unfollow", fallback: "Unfollow") }
  /// A common string used throughout the app. Used to reference an unknown duration '?' is an indicator that the amount of time isn't known and 'm' is a reference for minutes.
  internal static var unknownDuration: String { return L10n.tr("Localizable", "unknown_duration", fallback: "? m") }
  /// A common string used throughout the app. Prompt to un-star the selected item (remove from favorited).
  internal static var unstar: String { return L10n.tr("Localizable", "unstar", fallback: "Unstar") }
  /// A common string used throughout the app. Prompt to unsubscribe from the selected podcast(s).
  internal static var unsubscribe: String { return L10n.tr("Localizable", "unsubscribe", fallback: "Unsubscribe") }
  /// A common string used throughout the app. Prompt to unsubscribe from all of the selected podcast.
  internal static var unsubscribeAll: String { return L10n.tr("Localizable", "unsubscribe_all", fallback: "Unsubscribe All") }
  /// A common string used throughout the app. Title for the prompt to display the queue of episodes to play next.
  internal static var upNext: String { return L10n.tr("Localizable", "up_next", fallback: "Up Next") }
  /// Description shown when your Up Next list is empty. Note that for non right to left languages "right" should be change to "left" (and translated)
  internal static var upNextEmptyDescription: String { return L10n.tr("Localizable", "up_next_empty_description", fallback: "You can queue episodes to play next by swiping right on episode rows, or tapping the icon on an episode card.") }
  /// Heading shown when your Up Next list is empty
  internal static var upNextEmptyTitle: String { return L10n.tr("Localizable", "up_next_empty_title", fallback: "Curate your listening session") }
  /// Title of a screen that display Up Next history
  internal static var upNextHistory: String { return L10n.tr("Localizable", "up_next_history", fallback: "Up Next History") }
  /// A message explaining how to use the Up Next history
  internal static var upNextHistoryExplanation: String { return L10n.tr("Localizable", "up_next_history_explanation", fallback: "A list of recent updates to Up Next due to changes on other devices. To view the episodes and have the option to restore them, tap any entry.") }
  /// Up Next Shuffle Announcement sheet dismiss button title
  internal static var upNextShuffleAnnouncementButton: String { return L10n.tr("Localizable", "up_next_shuffle_announcement_button", fallback: "Got it") }
  /// Up Next Shuffle Announcement sheet text
  internal static var upNextShuffleAnnouncementText: String { return L10n.tr("Localizable", "up_next_shuffle_announcement_text", fallback: "Easily play a random episode without changing the order of your queue.") }
  /// Up Next Shuffle Announcement sheet title
  internal static var upNextShuffleAnnouncementTitle: String { return L10n.tr("Localizable", "up_next_shuffle_announcement_title", fallback: "Introducing Shuffle") }
  /// Toast message displayed when the user enables the Up Next Shuffle option
  internal static var upNextShuffleToastMessage: String { return L10n.tr("Localizable", "up_next_shuffle_toast_message", fallback: "Shuffle is on. Episodes will play in random order.") }
  /// Up Next sort option that orders episodes by time remaining, longest first
  internal static var upNextSortLongestToShortest: String { return L10n.tr("Localizable", "up_next_sort_longest_to_shortest", fallback: "Longest to shortest") }
  /// Up Next sort option that orders episodes by release date, newest first
  internal static var upNextSortNewestToOldest: String { return L10n.tr("Localizable", "up_next_sort_newest_to_oldest", fallback: "Newest to oldest") }
  /// Up Next sort option that orders episodes by release date, oldest first
  internal static var upNextSortOldestToNewest: String { return L10n.tr("Localizable", "up_next_sort_oldest_to_newest", fallback: "Oldest to newest") }
  /// Up Next sort option that orders episodes by time remaining, shortest first
  internal static var upNextSortShortestToLongest: String { return L10n.tr("Localizable", "up_next_sort_shortest_to_longest", fallback: "Shortest to longest") }
  /// Message of a tip pointing at the sort button on the Up Next screen, explaining what tapping it does
  internal static var upNextSortTipMessage: String { return L10n.tr("Localizable", "up_next_sort_tip_message", fallback: "Tap to reorder the queue by date or duration.") }
  /// Title of a tip pointing at the sort button on the Up Next screen
  internal static var upNextSortTipTitle: String { return L10n.tr("Localizable", "up_next_sort_tip_title", fallback: "Sort your Up Next") }
  /// Title shown at the top of the Up Next sort options picker
  internal static var upNextSortTitle: String { return L10n.tr("Localizable", "up_next_sort_title", fallback: "Sort Up Next") }
  /// Label of a button that informs the user they can upgrade their account. .
  internal static var upgradeAccount: String { return L10n.tr("Localizable", "upgrade_account", fallback: "Upgrade Account") }
  /// Upgrade account information for onboarding banner
  internal static var upgradeAccountInfo: String { return L10n.tr("Localizable", "upgrade_account_info", fallback: "Unlock all paid features like Folders, Shuffle, Bookmarks and many more") }
  /// Upgrade account timeline charging day message. The %1$@ argument is the day of the charge. Ex: You’ll be charged on September 31th Cancel anytime before.
  internal static func upgradeAccountTimelineChargingDay(_ p1: Any) -> String {
    return L10n.tr("Localizable", "upgrade_account_timeline_charging_day", String(describing: p1), fallback: "You’ll be charged on %1$@. Cancel anytime before.")
  }
  /// Upgrade account timeline day 1 of free trial message.
  internal static var upgradeAccountTimelineDay1: String { return L10n.tr("Localizable", "upgrade_account_timeline_day_1", fallback: "Get access to Folders, Shuffle, Bookmarks, and exclusive content") }
  /// Upgrade account timeline one week before charging message.
  internal static var upgradeAccountTimelineWeekBefore: String { return L10n.tr("Localizable", "upgrade_account_timeline_week_before", fallback: "We’ll notify you about your trial ending.") }
  /// Upgrade account Title for onboarding banner
  internal static var upgradeAccountTitle: String { return L10n.tr("Localizable", "upgrade_account_title", fallback: "Superpowers for your podcasts") }
  /// Upgrade Experiment message informing the user that they have been granted 50% discount.
  internal static var upgradeExperimentDiscountYearlyMembership: String { return L10n.tr("Localizable", "upgrade_experiment_discount_yearly_membership", fallback: "Save 50%% off your first year") }
  /// Upgrade Experiment message informing the user that they have been granted a limited free membership. '%1$@' is a placeholder for a localized string for the free time period.
  internal static func upgradeExperimentFreeMembershipFormat(_ p1: Any) -> String {
    return L10n.tr("Localizable", "upgrade_experiment_free_membership_format", String(describing: p1), fallback: "Free %1$@ Plus trial")
  }
  /// Upgrade Experiment Paywall button title
  internal static var upgradeExperimentPaywallButton: String { return L10n.tr("Localizable", "upgrade_experiment_paywall_button", fallback: "Get Pocket Casts Plus") }
  /// Upgrade Experiment - Reviews Variation: Title for the button that redirects the user to the AppStore page
  internal static var upgradeExperimentReviewsAppStoreButton: String { return L10n.tr("Localizable", "upgrade_experiment_reviews_app_store_button", fallback: "See all reviews in the App Store") }
  /// Upgrade Experiment - Reviews Variation: the text that represents the avg stars rating and the number of reviews. The %1$@ placeholder indicates the avg rating, like 4.3. The %2$@ placeholder indicates the abbreviated number of reviews, like 5.7K.
  internal static func upgradeExperimentReviewsAppStoreInfo(_ p1: Any, _ p2: Any) -> String {
    return L10n.tr("Localizable", "upgrade_experiment_reviews_app_store_info", String(describing: p1), String(describing: p2), fallback: "%1$@ Rating (%2$@K Reviews)")
  }
  /// Upgrade Experiment - Reviews Variation: text for Review card 0
  internal static var upgradeExperimentReviewsReviewText0: String { return L10n.tr("Localizable", "upgrade_experiment_reviews_review_text_0", fallback: "I've been a long time user and the amount of functionality and customization you get with the free version is astounding. I love that it syncs across devices so I can start listening on my phone and then pick up on an Alexa device. It's my recommendation for anyone who listens to podcasts. Also love the stats!") }
  /// Upgrade Experiment - Reviews Variation: text for Review card 1
  internal static var upgradeExperimentReviewsReviewText1: String { return L10n.tr("Localizable", "upgrade_experiment_reviews_review_text_1", fallback: "8 years of excellence and continuous improvement") }
  /// Upgrade Experiment - Reviews Variation: text for Review card 2
  internal static var upgradeExperimentReviewsReviewText2: String { return L10n.tr("Localizable", "upgrade_experiment_reviews_review_text_2", fallback: "I've been a Pocket Casts user since 2017.\n\nThis is hands down the best app to listen to podcasts. It's feature rich and actively developed. There have been some complaints about the Ul change but I haven't really noticed it too much.\n\nThis app can be as simple or difficult to use as you'd like it to be. So either let it be a plug and play or set up skip outro and intro timers and any other little feature you want to enable.") }
  /// Upgrade Experiment - Reviews Variation: text for Review card 3
  internal static var upgradeExperimentReviewsReviewText3: String { return L10n.tr("Localizable", "upgrade_experiment_reviews_review_text_3", fallback: "The sync function is magic. Don't know what special magic this app has going on but it's better than any other app l've used.") }
  /// Upgrade Experiment - Reviews Variation: text for Review card 5
  internal static var upgradeExperimentReviewsReviewText5: String { return L10n.tr("Localizable", "upgrade_experiment_reviews_review_text_5", fallback: "PC has been my go-to for years. l've tried other podcast apps and always come back to PC for their simplicity, Ul and support. Definitely worth checking it out, especially if you have grown tired of your current podcast app.") }
  /// Upgrade Experiment - Reviews Variation: title for Review card 0
  internal static var upgradeExperimentReviewsReviewTitle0: String { return L10n.tr("Localizable", "upgrade_experiment_reviews_review_title_0", fallback: "Best Podcast App By FAR") }
  /// Upgrade Experiment - Reviews Variation: title for Review card 1
  internal static var upgradeExperimentReviewsReviewTitle1: String { return L10n.tr("Localizable", "upgrade_experiment_reviews_review_title_1", fallback: "The essential podcast app") }
  /// Upgrade Experiment - Reviews Variation: title for Review card 2
  internal static var upgradeExperimentReviewsReviewTitle2: String { return L10n.tr("Localizable", "upgrade_experiment_reviews_review_title_2", fallback: "Best podcasat app out there") }
  /// Upgrade Experiment - Reviews Variation: title for Review card 3
  internal static var upgradeExperimentReviewsReviewTitle3: String { return L10n.tr("Localizable", "upgrade_experiment_reviews_review_title_3", fallback: "Fantastic app") }
  /// Upgrade Experiment - Reviews Variation: title for Review card 4
  internal static var upgradeExperimentReviewsReviewTitle4: String { return L10n.tr("Localizable", "upgrade_experiment_reviews_review_title_4", fallback: "Works great and easy to find or add new pods") }
  /// Upgrade Experiment - Reviews Variation: title for Review card 5
  internal static var upgradeExperimentReviewsReviewTitle5: String { return L10n.tr("Localizable", "upgrade_experiment_reviews_review_title_5", fallback: "Go-To Podcast App") }
  /// Upgrade Experiment - Reviews Variation: Screen text
  internal static var upgradeExperimentReviewsText: String { return L10n.tr("Localizable", "upgrade_experiment_reviews_text", fallback: "See why people have upgraded to Plus") }
  /// Upgrade Experiment - Reviews Variation: Screen title
  internal static var upgradeExperimentReviewsTitle: String { return L10n.tr("Localizable", "upgrade_experiment_reviews_title", fallback: "Quite simply the best way to listen to podcasts") }
  /// A button title that prompts the user to upgrade their plan. %1$@ is the name of the tier (Plus or Patron)
  internal static func upgradeToPlan(_ p1: Any) -> String {
    return L10n.tr("Localizable", "upgrade_to_plan", String(describing: p1), fallback: "Upgrade to %1$@")
  }
  /// Prompting the user to upgrade to Plus. Don't translate "Plus"
  internal static var upgradeToPlus: String { return L10n.tr("Localizable", "upgrade_to_plus", fallback: "Upgrade to Plus") }
  /// A descending alphabetical sort option for uploaded files.
  internal static var uploadSortAlphaAToZ: String { return L10n.tr("Localizable", "upload_sort_alpha_a_to_z", fallback: "Title (A-Z)") }
  /// An ascending alphabetical sort option for uploaded files.
  internal static var uploadSortAlphaZToA: String { return L10n.tr("Localizable", "upload_sort_alpha_z_to_a", fallback: "Title (Z-A)") }
  /// A duration (longest to shortest) sort option for uploaded files.
  internal static var uploadSortLongestToShortest: String { return L10n.tr("Localizable", "upload_sort_longest_to_shortest", fallback: "Longest to shortest") }
  /// A duration (shortest to longest) sort option for uploaded files.
  internal static var uploadSortShortestToLongest: String { return L10n.tr("Localizable", "upload_sort_shortest_to_longest", fallback: "Shortest to longest") }
  /// Title displayed above the user's subscribed podcasts list when no podcast is selected.
  internal static var userEpisodesSearchPodcastsTitle: String { return L10n.tr("Localizable", "user_episodes_search_podcasts_title", fallback: "Your Podcasts") }
  /// An option to say "no" when when asked if the user enjoys the app.
  internal static var userSatisfactionSurveyNoResponse: String { return L10n.tr("Localizable", "user_satisfaction_survey_no_response", fallback: "Not really") }
  /// A subtitle shown for the user satisfaction survey to ask whether a user enjoys the app
  internal static var userSatisfactionSurveySubtitle: String { return L10n.tr("Localizable", "user_satisfaction_survey_subtitle", fallback: "Hi there! We'd love to know if you're enjoying our app.") }
  /// A title shown for the user satisfaction survey to ask whether a user enjoys the app
  internal static var userSatisfactionSurveyTitle: String { return L10n.tr("Localizable", "user_satisfaction_survey_title", fallback: "Enjoying Pocket Casts?") }
  /// An option to say "yes" when when asked if the user enjoys the app.
  internal static var userSatisfactionSurveyYesResponse: String { return L10n.tr("Localizable", "user_satisfaction_survey_yes_response", fallback: "Yes!") }
  /// Title of the Transcript excerpt in Episode detail
  internal static var viewTranscript: String { return L10n.tr("Localizable", "view_transcript", fallback: "View Transcript") }
  /// The Volume Boost feature. Makes voices louder.
  internal static var volumeBoost: String { return L10n.tr("Localizable", "volume_boost", fallback: "Volume Boost") }
  /// A short description of what the Volume Boost feature does
  internal static var volumeBoostDescription: String { return L10n.tr("Localizable", "volume_boost_description", fallback: "Voices sound louder") }
  /// A short description of what the VoiceBoostN feature does
  internal static var volumeBoostNDescription: String { return L10n.tr("Localizable", "volume_boost_n_description", fallback: "Voice levels are more consistent") }
  /// A common string used throughout the app. Informs the user that the app is waiting for wifi to reconnect.
  internal static var waitForWifi: String { return L10n.tr("Localizable", "wait_for_wifi", fallback: "Waiting for WiFi") }
  /// week
  internal static var week: String { return L10n.tr("Localizable", "week", fallback: "week") }
  /// Title of a button prompting the user find new podcasts in discover
  internal static var welcomeDiscoverButton: String { return L10n.tr("Localizable", "welcome_discover_button", fallback: "Find My Next Podcast") }
  /// Description of a section informing the user they can find new podcasts in the discover section
  internal static var welcomeDiscoverDescription: String { return L10n.tr("Localizable", "welcome_discover_description", fallback: "Find under-the-radar and trending podcasts in our hand-curated Discover page.") }
  /// Title of a section informing the user they can find new podcasts in the discover section
  internal static var welcomeDiscoverTitle: String { return L10n.tr("Localizable", "welcome_discover_title", fallback: "Discover something new") }
  /// Title of a button prompting the user to import their podcasts
  internal static var welcomeImportButton: String { return L10n.tr("Localizable", "welcome_import_button", fallback: "Import Podcasts") }
  /// Description of a section informing the user they can import their podcasts from another app
  internal static var welcomeImportDescription: String { return L10n.tr("Localizable", "welcome_import_description", fallback: "Coming from another app? Bring your podcasts with you.") }
  /// Title of a section informing the user they can import their podcasts from another app
  internal static var welcomeImportTitle: String { return L10n.tr("Localizable", "welcome_import_title", fallback: "Import your podcasts") }
  /// Title of the view displayed after a user successfully creates an account
  internal static var welcomeNewAccountTitle: String { return L10n.tr("Localizable", "welcome_new_account_title", fallback: "Welcome, now let's get you listening!") }
  /// Title of the view displayed after a user successfully upgrades to plus
  internal static var welcomePlusTitle: String { return L10n.tr("Localizable", "welcome_plus_title", fallback: "Thank you, now let's get you listening!") }
  /// Title for the announcement screen that calls out new features.
  internal static var whatsNew: String { return L10n.tr("Localizable", "whats_new", fallback: "What's New") }
  /// Text for a link that goes to our blog where people can read more about the current update
  internal static var whatsNewBlogMoreLinkText: String { return L10n.tr("Localizable", "whats_new_blog_more_link_text", fallback: "Read more about this update on our blog") }
  /// Text on the about page button to tell people's what's new in this version. %1$@ is placeholder for the version number, for example 7.1.
  internal static func whatsNewInVersion(_ p1: Any) -> String {
    return L10n.tr("Localizable", "whats_new_in_version", String(describing: p1), fallback: "What's New In %1$@")
  }
  /// What's new for 7.20 description for page one. Please leave the "\
  /// \
  /// " part in there, these are new line indicator.
  internal static var whatsNewPageOne720: String { return L10n.tr("Localizable", "whats_new_page_one_7_20", fallback: "If you love podcasts half as much as we do, you probably have a lot of them. If you're a Pocket Casts Plus subscriber, you can now sort these into folders and file them into neat groups.\n\nThanks to your support, your Home Screen has never looked better!") }
  /// Title for page one of the 7.20 what's new dialog.
  internal static var whatsNewPageOneTitle720: String { return L10n.tr("Localizable", "whats_new_page_one_title_7_20", fallback: "Folders") }
  /// What's new for 7.20 description for page two. Please leave the "\
  /// \
  /// " part in there, these are new line indicator.
  internal static var whatsNewPageTwo720: String { return L10n.tr("Localizable", "whats_new_page_two_7_20", fallback: "We now sync your Home Screen (including your sort options) across devices! And you can drag and drop in the Web Player now as well.\n\nThis means you can rest easier, knowing the hard work you put in to arranging your podcasts page is being synced to your account.") }
  /// Title for page two of the 7.20 what's new dialog.
  internal static var whatsNewPageTwoTitle720: String { return L10n.tr("Localizable", "whats_new_page_two_title_7_20", fallback: "Home Grid Syncing") }
  /// Description for the WidgetKit Control Center next chapter control.
  internal static var widgetPlaybackControlNextChapterDescription: String { return L10n.tr("Localizable", "widget_playback_control_next_chapter_description", fallback: "Skip to the next chapter of the current episode.") }
  /// Display name for the WidgetKit Control Center next chapter control.
  internal static var widgetPlaybackControlNextChapterDisplayName: String { return L10n.tr("Localizable", "widget_playback_control_next_chapter_display_name", fallback: "Next Chapter") }
  /// Description for the WidgetKit Control Center play/pause control.
  internal static var widgetPlaybackControlPlayPauseDescription: String { return L10n.tr("Localizable", "widget_playback_control_play_pause_description", fallback: "Play or pause the current episode.") }
  /// Display name for the WidgetKit Control Center play/pause control.
  internal static var widgetPlaybackControlPlayPauseDisplayName: String { return L10n.tr("Localizable", "widget_playback_control_play_pause_display_name", fallback: "Play / Pause") }
  /// Description for the WidgetKit Control Center play Up Next control.
  internal static var widgetPlaybackControlPlayUpNextDescription: String { return L10n.tr("Localizable", "widget_playback_control_play_up_next_description", fallback: "Skip to the next episode in Up Next.") }
  /// Display name for the WidgetKit Control Center play Up Next control.
  internal static var widgetPlaybackControlPlayUpNextDisplayName: String { return L10n.tr("Localizable", "widget_playback_control_play_up_next_display_name", fallback: "Play Next Episode") }
  /// Description for the WidgetKit Control Center skip back control.
  internal static var widgetPlaybackControlSkipBackDescription: String { return L10n.tr("Localizable", "widget_playback_control_skip_back_description", fallback: "Skip back in the current episode.") }
  /// Display name for the WidgetKit Control Center skip back control.
  internal static var widgetPlaybackControlSkipBackDisplayName: String { return L10n.tr("Localizable", "widget_playback_control_skip_back_display_name", fallback: "Skip Back") }
  /// Description for the WidgetKit Control Center skip forward control.
  internal static var widgetPlaybackControlSkipForwardDescription: String { return L10n.tr("Localizable", "widget_playback_control_skip_forward_description", fallback: "Skip forward in the current episode.") }
  /// Display name for the WidgetKit Control Center skip forward control.
  internal static var widgetPlaybackControlSkipForwardDisplayName: String { return L10n.tr("Localizable", "widget_playback_control_skip_forward_display_name", fallback: "Skip Forward") }
  /// Description for the WidgetKit Control Center sleep timer control.
  internal static var widgetPlaybackControlSleepTimerDescription: String { return L10n.tr("Localizable", "widget_playback_control_sleep_timer_description", fallback: "Start a 15-minute sleep timer, or extend the running one.") }
  /// Display name for the WidgetKit Control Center sleep timer control.
  internal static var widgetPlaybackControlSleepTimerDisplayName: String { return L10n.tr("Localizable", "widget_playback_control_sleep_timer_display_name", fallback: "Sleep Timer") }
  /// Description of a widget to launch the app
  internal static var widgetsAppIconDescription: String { return L10n.tr("Localizable", "widgets_app_icon_description", fallback: "Quickly Launch Pocket Casts") }
  /// Title of a widget that displays the app icon
  internal static var widgetsAppIconName: String { return L10n.tr("Localizable", "widgets_app_icon_name", fallback: "Icon") }
  /// Widget prompt message to direct the user to the discover tab to add new podcasts to their queue
  internal static var widgetsDiscoverPromptMsg: String { return L10n.tr("Localizable", "widgets_discover_prompt_msg", fallback: "Check out Discover for more") }
  /// Widget prompt title to direct the user to the discover tab to add new podcasts to their queue
  internal static var widgetsDiscoverPromptTitle: String { return L10n.tr("Localizable", "widgets_discover_prompt_title", fallback: "Nothing in Up Next") }
  /// Widget label informing the user that nothing is currently being played.
  internal static var widgetsNothingPlaying: String { return L10n.tr("Localizable", "widgets_nothing_playing", fallback: "Nothing Playing") }
  /// Description for the now playing widget.
  internal static var widgetsNowPlayingDesc: String { return L10n.tr("Localizable", "widgets_now_playing_desc", fallback: "Quickly access the currently playing episode.") }
  /// Call to action for a tap on a widget to open the Discover tab.
  internal static var widgetsNowPlayingTapDiscover: String { return L10n.tr("Localizable", "widgets_now_playing_tap_discover", fallback: "Tap to Discover") }
  /// Up Next Lock Screen Widget description
  internal static var widgetsUpNextDescription: String { return L10n.tr("Localizable", "widgets_up_next_description", fallback: "See the number of items in your Up Next queue or details about the next episode.") }
  /// Basic string used in formats like 'price / year'
  internal static var year: String { return L10n.tr("Localizable", "year", fallback: "year") }
  /// Basic string used to callout payment intervals like yearly vs monthly
  internal static var yearly: String { return L10n.tr("Localizable", "yearly", fallback: "Yearly") }
  /// Title for the You Might Like tab showing related podcasts in a Podcast
  internal static var youMightLike: String { return L10n.tr("Localizable", "you_might_like", fallback: "You might like") }
}
// swiftlint:enable explicit_type_interface function_parameter_count identifier_name line_length
// swiftlint:enable nesting type_body_length type_name vertical_whitespace_opening_braces

// MARK: - Implementation Details

nonisolated extension L10n {
  private static func tr(_ table: String, _ key: String, _ args: CVarArg..., fallback value: String) -> String {
    let format = localizedFormat(key, table, value)
    return String(format: format, locale: Locale.current, arguments: args)
  }
}

