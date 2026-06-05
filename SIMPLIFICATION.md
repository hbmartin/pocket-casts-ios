# "Fast & Light" Simplification — Status & Hand-off

This branch (`claude/sleepy-lamport-rNVOn`) strips Pocket Casts down to core
podcast playback, deleting secondary features. Work was done in a **Linux CI
environment with no Xcode/Swift toolchain**, so nothing here has been compiled —
changes were made and verified statically (grep for dangling references). A pass
in Xcode on macOS is required to resolve any residual compile errors before merge.

## Agreed scope (from requirements interview)

**Remove:** IAP/Plus/Patron paywalls & gating, End of Year, What's New, heavy
onboarding/account nagging, Discover tab, User Episodes/file upload, CarPlay,
App Clip, watchOS & tvOS placeholder targets, dead deep-links.

**Keep intact:** podcast subscribe/refresh/download, the **player** (chapters,
sleep timer, speed, trim silence, volume boost), Up Next, sync, Search, Folders,
Bookmarks, Transcripts, Sharing, Stats, Ratings, Analytics, **all Themes**,
Widgets, Siri/Shortcuts, Share/Notification extensions, Fingerprint (audio
time-mapping that underpins chapters/bookmarks).

## Completed (committed & pushed)

| Commit | What | Net LOC |
|--------|------|--------|
| End of Year + What's New | Deleted `podcasts/End of Year/`, all What's New/announcements; de-wired tab bar, router, profile, about, launch flow | ~−10.8K |
| CarPlay | Deleted `podcasts/CarPlay/` + `CarPlayHelper`; removed scene config from AppDelegate + Info.plist | ~−1.0K |
| App Clip / watch / tvOS targets | Deleted App Clip source + empty XcodeSupport stubs; removed the 3 targets from `project.pbxproj` | ~−2.3K |
| Supporter Podcasts + Promotions | Deleted both self-contained selling features + entry points | ~−2.5K |
| Onboarding de-nag | First launch no longer shows the account-creation push flow | small |

The **Discover tab** was already removed on this branch before this work (tab bar
is Podcasts / Filters / Up Next / Profile; `navigateToDiscover*` routes to Podcasts).

### Deliberately kept despite the feature being "removed"
- **`Modules/Sources/EndOfYear`** — despite its name this is a reusable Stories/UI
  library (StoryIndicator, CircularProgressView, MarqueeText, snapshot helpers)
  still used by the Onboarding intro carousel and Profile. Only the *feature* under
  `podcasts/End of Year/` was deleted.
- **`AnnouncementFlow`** — kept as a minimal stub (`podcasts/AnnouncementFlow.swift`);
  player/profile/settings read it. With What's New gone it stays `.none`.
- **`SubscriptionHelper` / `PaidFeature` / `IAPHelper`** — the entitlement layer.
  Features are **already free** in this build (`SubscriptionHelper.featuresUnlocked
  = true`), so nothing was gated; the selling UI was removed but the status layer
  (read by ~58 files) was left intact.
- **`ServerPodcastManager+Subscription.swift`** — "Subscription" here is legacy
  naming for *following* a podcast (core, app-wide), not paid supporter subs.

## Deferred — finish in Xcode (with a compiler)

These are entangled with **kept** systems; doing them blind risks *silently*
breaking the player/Search/data layer. Each is safe to do with the compiler
pointing at every reference.

1. **Full IAP / `PaidFeature` enum removal.** Features are already free, so this is
   dead-code cleanup, not behavior change. The server subscription tasks are called
   by the kept `SubscriptionHelper`, so they can't be cut without reworking it.
   *Plan:* delete `podcasts/Unlockable/`, `PlusLockedInfo*`, paywall modals, IAPHelper/
   StoreKit; reduce `SubscriptionHelper` to an always-unlocked stub; delete
   `PaidFeature` and replace `someFeature.isUnlocked` call sites with `true`.

2. **User Episodes / file upload.** `UserEpisode` is a data-model type woven through
   playback/Up Next/downloads — not just upload UI. *Plan:* delete the upload UI
   (`Uploaded*`, `UserEpisodeDetailViewController*`, `UserEpisodeManager`,
   `CustomStorage*`, `UploadedSettings*`) + entry points (Profile `uploadedFiles`
   row, `MainTabBarController.navigateToFiles/navigateToAddCustom`, files deep-link);
   decide separately whether to remove the `UserEpisode` model (high blast radius).

3. **Discover code cleanup.** The *tab* is already gone; ~30 leftover Discover/
   Category/Featured files share types (`DiscoverItem`, `DiscoverPodcast`,
   `DiscoverCellType`) with **kept Search/podcast-browsing**. *Plan:* delete the
   Discover tab view controllers, then carefully separate shared types Search needs.

4. **Deeper onboarding slimming** toward a truly minimal "welcome → Podcasts"
   (the intro carousel reuses the EndOfYear Stories module).

## Known residual dead code (compiles, safe to delete later)
- EOY data layer: `SyncYearListeningHistoryTask`, `EndOfYearDataManager`, EOY
  feature flags, and unused `Settings`/`Analytics`/`Notification` name definitions.
- `Constants.maxCarplayItems`, `AnalyticsCoordinator` `carPlay` case,
  `AnalyticsEvent.appClipOpened`, `OnboardingFlow.Source.promoCode`.
- Server-side promo API (`RedeemPromoCodeTask`, etc.) — unreferenced by the app.
- Unused `Strings+Generated.swift` entries (regenerate via SwiftGen on next build).

## Project mechanics (important for the Xcode pass)
- The app target graph lives in the raw **`podcasts.xcodeproj/project.pbxproj`**
  (no XcodeGen, no CocoaPods; `Modules/` & `BuildTools/` are SPM).
- It uses **Xcode 16 file-system-synchronized groups** (`objectVersion = 74`), so
  deleting source files needs **no** `project.pbxproj` edit.
- **Dangling synchronized groups** for deleted folders (End of Year, Whats New,
  CarPlay, Pocket Casts App Clip) remain listed and show **red** in Xcode. They are
  harmless (a missing synchronized folder contributes no files); delete them in the
  Xcode navigator. The xcodeproj Ruby gem (1.27) cannot cleanly detach them in
  objectVersion 74, which is why they were left.
- Target removal was done with the `xcodeproj` gem (see the approach in the App Clip
  commit). `make format` / `make build_staging` / `make test_staging` require macOS.

## Suggested verification order on macOS
1. `make build_staging` — fix residual compile errors (mostly the deferred phases
   if you continue them; the completed phases were grep-clean).
2. Delete the 4 red synchronized groups in Xcode.
3. Smoke test: subscribe → download → play (chapters/sleep/speed/trim/boost) →
   Up Next → Search → Bookmarks/Folders/Transcripts → Profile. Confirm old deep
   links (EOY/What's New/App Clip) land on Podcasts/Profile, not dead screens.
4. `make test_staging`; delete tests for removed features as needed.
