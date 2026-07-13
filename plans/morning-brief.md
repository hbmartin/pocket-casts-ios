# Daily Briefing / Highlights Feed — Implementation Plan

## Context

`docs/DeferredFeatures.md` records "Daily briefing / highlights feed" as the top deliberately-deferred
AI feature: a morning surface summarizing what's new across subscriptions — new-episode summaries,
key takeaways, and recent highlights — assembled on-device. It was deferred because the product shape,
refresh economics (FoundationModels runs × subscriptions), and notification fatigue needed design
time. All primitives shipped in the July 2026 AI UX round; this plan turns them into the feature.

**Product decisions (user, this session):**
- **Shape:** "Morning Edition" editorial feed, **highly user-configurable**: greeting header,
  per-new-episode summary cards with tap-to-seek takeaway chips, recent-highlights strip,
  catch-me-up (partially played) section — each section toggleable and reorderable, episode cap and
  schedule hour configurable.
- **Placement:** a **top toggle replacing the "Podcasts" nav title** — a two-segment switcher
  (Podcasts | Briefing) in the Podcasts tab that swaps the tab's content.
- **Delivery layers (v1):** morning local notification (quiet-day rule: nothing new → no
  notification) + home/lock-screen widget. **No TTS narration in v1.**
- **Constraints:** on-device only, free, behind new flag `.dailyBriefing`.

**Verified facts that shaped the design:**
- Takeaways are never cached today — `EpisodeSummaryViewModel.loadTakeaways()` regenerates on every
  card appearance. Summaries ARE cached (`GeneratedEpisodeMetadataRetriever`, URLCache 10MB).
- `RefreshOperation` sets `addedDate = Date()` only for genuinely-new rows, but first install /
  new subscription floods the back catalog with `addedDate = now` (guarded below).
- `AppDelegate.handleAppRefresh` (line ~342) has ~30s total budget — no room for FM inference.
- `PodcastListViewController.swift:68` sets `title = L10n.podcastsPlural`; `PCViewController`
  explicitly supports the `navigationItem.titleView` + empty-title pattern
  (`PCViewController.swift:78-85`) — but `setupNavBar` is gated on non-empty title, so the toggle
  install must ensure bar appearance is still configured (see §2 risk note).
- New files under `podcasts/` are picked up automatically (`PBXFileSystemSynchronizedRootGroup`).

## Architecture overview

```
RefreshOperation ──firePodcastRefreshSucceeded──▶ DailyBriefingCoordinator (@MainActor singleton)
AppDelegate.handleAppRefresh (BG, no FM) ────────▶       │ conforms to DailyBriefingProviding
app-activation day-rollover check ───────────────▶       │
                                                         ▼
                                          DailyBriefingAssembler (actor)
                                          queries ▸ summaries ▸ takeaways (top-3, FG only)
                                                         │
                     ┌───────────────────────────────────┼─────────────────────────┐
                     ▼                                   ▼                         ▼
          DailyBriefingStore (JSON,          .dailyBriefing notification    BriefingWidgetData →
          Documents/daily_briefing/)         (UNCalendarNotificationTrigger, app-group defaults →
          + TakeawayStore cache              quiet-day cancel)              WidgetCenter reload
                     │
                     ▼
          BriefingView (SwiftUI) behind Podcasts-tab title toggle
```

New directory: `podcasts/Daily Briefing/` (repo convention uses spaces, e.g. `Up Next History/`).

## 1. Foundation: flag, settings, model, stores

- **Flag**: `case dailyBriefing` in `Modules/Sources/PocketCastsUtils/Feature Flags/FeatureFlag.swift`,
  `default:` → `BuildEnvironment.current != .appStore` (matches other AI flags); `remoteKey`
  auto-derives `daily_briefing`.
- **Settings** — single Codable blob following the `Settings.audioTuning` pattern
  (`podcasts/Settings.swift:1506`): `Settings.dailyBriefing: DailyBriefingSettings`
  (device-local, NOT synced):
  ```swift
  struct DailyBriefingSettings: Codable, Equatable {
      var enabledSections: Set<BriefingSection>     // default all
      var sectionOrder: [BriefingSection]           // default [.newEpisodes, .highlights, .catchUp]
      var episodeCap: Int                           // default 10
      var scheduleHour: Int                         // default 8
      var notificationsEnabled: Bool                // default true (quiet-day rule guards fatigue)
  }
  enum BriefingSection: String, Codable, CaseIterable { case newEpisodes, highlights, catchUp }
  ```
- **Model** — `podcasts/Daily Briefing/Model/DailyBriefing.swift`: Codable/Sendable value types:
  `DailyBriefing { dayKey ("yyyy-MM-dd" local), assembledAt, episodeCursor (addedDate high-water
  mark), newEpisodes: [BriefingEpisodeItem], highlights: [BriefingHighlightItem],
  catchUp: [BriefingCatchUpItem], isEmpty }`. `BriefingEpisodeItem { episodeUuid, podcastUuid,
  titles, publishedDate, duration, summary: String?, takeaways: [BriefingTakeaway], takeawayLayer }`
  (`BriefingTakeaway` is a Codable mirror of `Takeaway`, which isn't Codable).
- **Stores** — `DailyBriefingStore` mirrors `podcasts/Transcription/TranscriptionArtifactStore.swift`:
  `Documents/daily_briefing/briefing-{dayKey}.json`, `setDontBackupFlag`, `read/write/prune(keepingDays: 7)`,
  injectable `directoryURL`. `TakeawayStore`: `daily_briefing/takeaways/{episodeUuid}.json` —
  checked before any FM run; written by assembler AND (follow-up) by `EpisodeSummaryViewModel`.

## 2. Assembler + coordinator (`podcasts/Daily Briefing/`)

**`DailyBriefingAssembler` (actor, app target)** — injected seams: `BriefingDataProviding`
(wraps `DataManager.sharedManager`), `BriefingSummaryProviding` (wraps
`ShowInfoCoordinator.shared.loadEpisodeSummary`), `IntelligenceProviding`
(default `OnDeviceIntelligence.shared`), stores, `now: () -> Date`, `Calendar`.
`assemble(context:)` is idempotent per (dayKey, cursor); **additive rebuild**: append episodes with
`addedDate > episodeCursor`, never regenerate existing summaries/takeaways; highlights/catch-up
re-snapshot wholesale (cheap).

- **New episodes query** (via `DataManager.findEpisodesWhere`, `DataManager.swift:563`):
  `addedDate > cursor AND publishedDate > now-7d AND archived = 0 AND playingStatus = 1 (notPlayed)
  ORDER BY publishedDate DESC` — then cap 2/podcast, total `episodeCap`. Cursor is `addedDate`
  (only monotonic "new to this device" signal); `publishedDate` window + per-podcast cap +
  cursor seeded to `now - 24h` (never distantPast) guard the first-install flood.
- **Catch-me-up**: `playingStatus = 2 (inProgress) AND archived = 0 AND
  lastPlaybackInteractionDate > 0 AND playedUpTo > 60 ORDER BY lastPlaybackInteractionDate DESC`,
  cap 5, exclude today's new-episode uuids. (`PlayingStatus` in
  `Modules/Sources/PocketCastsDataModel/Public/Enums.swift:42`.)
- **Highlights**: `DataManager.sharedManager.bookmarks.allBookmarks(includeDeleted: false,
  sorted: .newestToOldest)`, filter `created >= now-7d`, prefer non-nil `excerpt`, cap 5.
- **Summaries**: per-item `try?` fetch, ≤4 concurrent, whole-phase budget (20s FG / 8s BG).
  nil summary → headline-only card. Offline/FM-unavailable degrade to headline mode — assembly
  never fails.
- **Takeaways**: only when `context.allowsGeneration` && FM available; only top **K=3** episodes
  (newest first); check `TakeawayStore` first. Reuses the exact `EpisodeSummaryViewModel.loadTakeaways`
  recipe: `TranscriptManager.loadTranscript()` → `SummaryTakeawayGenerator.timedCues` →
  generated chapters as key moments → `generator.takeaways(...)`. Remaining episodes get takeaways
  lazily when the surface opens (same path, written back to both stores).

**`DailyBriefingCoordinator` (@MainActor singleton)** — conforms to the UI-facing protocol:
```swift
@MainActor protocol DailyBriefingProviding {
    var state: DailyBriefingState { get }   // idle | generating | ready(DailyBriefing) | quietDay | unavailable(reason)
    var hasUnseenBriefing: Bool { get }     // lastSeenBriefingDayKey (UserDefaults) != current dayKey
    func refresh() async
    func markBriefingSeen()
}
```
Triggers (all behind the flag, wired in `AppDelegate` setup):
- Foreground: observe `ServerNotifications.podcastsRefreshed`
  (`Modules/Sources/PocketCastsServer/Public/ServerNotifications.swift:11`), debounce 5s, assemble
  with `allowsGeneration = thermalState <= .fair && !isLowPowerModeEnabled`.
- App activation: if stored `dayKey != today`, assemble ("first open of the morning" without BG).
- Background: in `AppDelegate.handleAppRefresh` after `performBackgroundSync()`, before
  `setTaskCompleted` — `allowsGeneration: false`, 8s summary budget. **No FM in background, ever,
  in v1**; no separate BGProcessingTask (notification/widget only need counts+titles+summaries).
- After every assembly: publish widget data, reschedule/cancel notification, post typed message
  `DailyBriefingUpdated` (pattern: `podcasts/Notifications/ChromeMessages.swift`).

## 3. Notification (`podcasts/Notifications/NotificationsCoordinator.swift`)

- New `case dailyBriefing` in `NotificationType`: dynamic body computed at schedule time from the
  stored briefing ("5 new episodes — starting with '{top title}'"), precedent
  `.reengagementDownloads`. `link = "pktc://briefing"`, `isRepeatable = true`, `shouldSend` gated on
  flag + `Settings.dailyBriefing.notificationsEnabled`.
- **Do not add a `NotificationsGroup` case** (fixed hours, drives grouped settings UI); the
  coordinator schedules directly: `UNCalendarNotificationTrigger(dateMatching:
  DateComponents(hour: settings.scheduleHour), repeats: false)`.
- **Quiet-day rule**: after assembly, `briefing.isEmpty` (respecting enabled sections) →
  `cancelNotification(.dailyBriefing)`; else cancel + reschedule (identifier = rawValue, so
  reschedule replaces content; overnight BG refresh re-bakes the body).
- Deep link: `static let dailyBriefingPageKey` in `podcasts/NavigationManager.swift`; JLRoutes
  `/briefing` route in `AppDelegate+UrlHandling.setupRoutes()` → switches the Podcasts tab to the
  briefing surface. (Delivery already flows via `DEEP_LINK` category → `destination_url`.)

## 4. Widget

- `podcasts/SharedConstants.swift`: add `GroupUserDefaults.dailyBriefing = "dailyBriefingData"`.
- `BriefingWidgetData` (Codable; target membership app + WidgetExtension, like `CommonUpNextItem`):
  dayKey, assembledAt, counts, top-3 items {episodeUuid, titles, imageUrl via
  `ServerHelper.image(podcastUuid:size: 340)`}.
- Coordinator publishes JSON to app-group defaults + `WidgetCenter.shared.reloadTimelines(ofKind:
  "Daily_Briefing_Widget")` (kept out of `WidgetHelper` to avoid its playback wiring); day rollover
  publishes an empty marker so the widget shows its placeholder.
- Read side: `WidgetExtension/Common/CommonWidgetHelper.swift` gains `loadDailyBriefingData()`;
  new `DailyBriefingWidget` (systemMedium + accessoryRectangular) added to
  `WidgetExtension/PocketCastsWidgetBundle.swift`; deep-link `pktc://briefing`; static single-entry
  timeline (data changes only on app assembly).

## 5. The top toggle (Podcasts | Briefing)

**Approach: titleView switcher + lazy child-VC swap inside `PodcastListViewController`** (rejected:
nav-stack sibling — wrong back-button semantics; container VC — `PodcastListViewController` actively
owns its `navigationItem`/search/`TappedOnSelectedTab` machinery and proxying it all is far more
invasive).

- `podcasts/Daily Briefing/BriefingSurfaceToggleView.swift` — SwiftUI two-segment capsule
  (visual language of `ExploreView.genreChip`; selected = `primaryInteractive01` capsule),
  `matchedGeometryEffect` thumb (gated on reduce-motion), 6pt unseen-dot on the Briefing segment,
  segments as Buttons with `.isSelected` traits.
- `podcasts/Daily Briefing/PodcastListViewController+Briefing.swift` — all switcher logic:
  - `installBriefingToggleIfNeeded()` from `viewDidLoad`: flag-gated; `title = nil`,
    `navigationItem.titleView = UIHostingController(rootView: toggle).view` with
    `sizingOptions = [.intrinsicContentSize]` + `.environmentObject(Theme.sharedTheme)`.
    **Risk note:** `PCViewController.setupNavBar` is gated on non-empty title
    (`PCViewController.swift:78-85`) — verify bar appearance after clearing title; call
    `setupNavBar`/appearance restore explicitly if needed (iOS 26 Liquid Glass path is a no-op).
  - `switchTo(_:animated:)`: `.briefing` lazily creates `BriefingViewController`, adds as child
    pinned over the collection view, cross-dissolve (reduce-motion-gated); swaps nav buttons
    (folder button → gear that pushes briefing settings) via existing `updateNavigationButtons()` /
    `setCustomRightBtn`; calls `markBriefingSeen()`. `.podcasts` restores.
  - Persist selection: new `Constants.UserDefaults.podcastsHomeSurface` key
    (`podcasts/Constants.swift:65` area); restore on install.
  - `TappedOnSelectedTab` (observed at `PodcastListViewController.swift:148`): route to briefing
    scroll-to-top when the child is active. `SearchRequested`/`ExternalSearchRequested` handlers
    first `switchTo(.podcasts, animated: false)`.
- Mini-player insets already handled by `MainTabBarController.additionalSafeAreaInsets` — no work.

## 6. BriefingView (SwiftUI, `podcasts/Daily Briefing/`)

- **`BriefingViewController`**: `PCHostingController<BriefingView>` (pattern:
  `podcasts/Main/Explore/ExploreViewController.swift`).
- **`BriefingViewModel`**: `@Observable @MainActor final class` (pattern-setter:
  `podcasts/AdvancedAudio/AdvancedAudioSettingsViewModel.swift`). Mirrors `DailyBriefingProviding.state`,
  re-reads `Settings.dailyBriefing` on appear, computes `visibleSections` (order ∩ enabled, cap),
  time-bucketed greeting (pure function of injected Date), scroll-to-top token, action funcs,
  fixture initializer for previews/snapshots (mirrors `EpisodeSummaryViewModel.init(fixtureSummary:)`).
- **`BriefingView`**: ScrollView + LazyVStack; state branches — `.generating` (spinner +
  "Putting your briefing together…"), `.quietDay` ("You're all caught up", still shows non-empty
  enabled sections), `.unavailable` (degraded headline cards + footnote, or retry). `.refreshable`.
- **Section views**: `BriefingGreetingHeader` (large-title font, counts subtitle,
  `.isHeader` trait), `BriefingEpisodeCardView` (chassis copied from
  `podcasts/Episode/Summary/EpisodeSummaryCardView.swift`: rounded 8, `primaryUi02Active`;
  `EpisodeImage` at `@ScaledMetricWithMaxSize` 56pt; 2-line summary via `TimestampLinkifier` +
  `pocketcasts-summary` OpenURLAction; takeaway chips; Play pill + "+ Up Next" capsule with 2s
  checkmark; contextMenu: Archive / Mark Played / Go to Episode),
  `BriefingHighlightsStrip` (horizontal quote cards ~280×140, `.viewAligned`, vertical stack at
  `.accessibilityLarge`+), `BriefingCatchUpSection` (progress bar + "N min left" via
  `TimeFormatter.shared` + resume pill), `BriefingEmptyStateView` (shared empty/loading layout).
- **Shared extractions (pure refactors, done first)**:
  - `podcasts/Episode/Summary/TakeawayChipRow.swift` — extracted from
    `EpisodeSummaryCardView.takeawayRow` (lines 119-140).
  - `podcasts/Episode/Summary/SummarySeekAction.swift` — extracted from
    `EpisodeSummaryViewModel.seek(to:source:)` (lines 140-159; now-playing check +
    `FingerprintTimingManager` mapping + `PlaybackManager.play(episodeUuid:podcastUuid:at:)`).
- **Actions (existing helpers, verified)**: Play → `PlaybackActionHelper.play(episode:)`
  (`podcasts/PlaybackActionHelper.swift:9`); Up Next →
  `PlaybackManager.shared.addToUpNext(episode:...)` (`PlaybackManager.swift:871`); Mark Played /
  Archive → `EpisodeManager` (`podcasts/EpisodeManager.swift:9,157`); Go to Episode →
  `EpisodeDetailViewController(episode:podcast:source:)` (call-site pattern
  `podcasts/UpNextViewController.swift:481-489`), new `AnalyticsSource` case.
- **Theming/a11y**: theme tokens only (`primaryUi04` bg, `primaryUi02Active` cards,
  `primaryText01/02`, `primaryInteractive01/02`); `.font(size:style:weight:)` helper everywhere;
  `.natural`/leading alignment (RTL); reduce-motion gates all animations.

## 7. Settings UI (`podcasts/Daily Briefing/Settings/`)

- `BriefingSettingsViewModel` (`@Observable`, `didSet` → `Settings.dailyBriefing`) +
  `BriefingSettingsView` cloning the `AdvancedAudioSettingsView` chassis: Sections (toggles in
  `sectionOrder`, `.onMove` reordering), Content (episode-cap menu Picker 3/5/10/15), Schedule
  (notification toggle + hour picker; footer explains regeneration), Widget hint row.
- Reachable from the gear on the briefing surface AND a new flag-gated `case dailyBriefing` row in
  `podcasts/SettingsViewController.swift` (`TableRow` enum ~line 8, push pattern at lines 214-218).

## 8. Analytics + L10n

- `podcasts/Analytics/AnalyticsEvent.swift`: `dailyBriefingAssembled` (trigger, counts,
  duration_ms), `dailyBriefingGenerationFailed` (IntelligenceError reason),
  `dailyBriefingNotificationScheduled/Skipped`, `dailyBriefingShown`, `dailyBriefingSurfaceToggled`,
  `dailyBriefingEpisodePlayTapped`, `dailyBriefingTakeawayTapped`.
- L10n keys (`daily_briefing_*`) in `podcasts/en.lproj/Localizable.strings`, positional specifiers,
  manual singular/plural pairs; regenerate SwiftGen.

## 9. Tests

- `PocketCastsTests/Tests/DailyBriefing/`:
  - Assembler: cursor advance + idempotent re-assembly, per-podcast/total caps, first-install guard,
    FM-unavailable degradation, takeaway-cache hit skips FM, quiet-day cancel, day rollover,
    widget projection — via protocol fakes (`MockIntelligenceProvider` shape from
    `SummaryTakeawayGeneratorTests`), temp-dir stores, injected clock/calendar.
  - `BriefingViewModelTests` (state mapping, section filter/order/cap, greeting buckets),
    `BriefingSettingsViewModelTests` (blob round-trip, reorder integrity).
- Snapshots: `Modules/Tests/SnapshotTests` can't import the app target, so add
  swift-snapshot-testing to `PocketCastsTests` + copy the `assertThemedSnapshots` helper; snapshot
  BriefingView states (ready/quietDay/generating/unavailable × light/dark × .large/.accessibilityXXL)
  and the toggle with/without dot, using fixture VMs + placeholder artwork. Fallback if too heavy:
  `#Preview` fixtures now, snapshots follow-up.

## 10. PR sequence

1. **Foundation** (no behavior change): flag; `DailyBriefingSettings` + `Settings.dailyBriefing`
   blob; model types; `DailyBriefingStore` + `TakeawayStore` + tests; `TakeawayChipRow` +
   `SummarySeekAction` extractions (summary card parity); L10n keys.
2. **Assembler**: seams + queries + summary/takeaway pipeline + analytics; unit tests. Not wired.
3. **Coordinator + triggers**: refresh observer, activation rollover, BG hook in
   `handleAppRefresh`, thermal/low-power gate, `DailyBriefingUpdated` message. Assembles end-to-end
   behind the flag.
4. **Surface skeleton + toggle**: `DailyBriefingProviding` conformance; BriefingViewModel/View with
   greeting + empty/generating/unavailable states; toggle + child-swap +
   `Constants.UserDefaults.podcastsHomeSurface`; unseen dot.
5. **Sections + actions**: episode cards, highlights strip, catch-up, Play/UpNext/seek/context
   menu, lazy takeaway generation on open (writes back to stores).
6. **Notification**: `.dailyBriefing` NotificationType, quiet-day rule,
   `NavigationManager.dailyBriefingPageKey` + `/briefing` route.
7. **Widget**: shared data type + publisher + `DailyBriefingWidget` in the bundle.
8. **Settings UI + polish**: settings screen, SettingsViewController row, snapshots, a11y audit.
9. **Optional follow-up**: `EpisodeSummaryViewModel` adopts `TakeawayStore`.

## Risks / flagged decisions

- **First-install flood**: triple guard (cursor ≥ now-24h, publishedDate 7d window, 2/podcast cap);
  watch in beta.
- **titleView under iOS 26 Liquid Glass**: intrinsic-size hosting + max-width clamp; verify
  `setupNavBar`'s empty-title gate doesn't leave the bar unconfigured.
- **BG budget**: briefing BG pass is FM-free, 8s-bounded, runs before `setTaskCompleted`; app
  activation covers correctness if BG is squeezed.
- **Notification staleness**: body baked at assembly (possibly 11pm for an 8am fire); counts+title
  keeps staleness low-harm; overnight BG refresh re-bakes.
- **Timezone/DST**: dayKey from local Calendar; hour-only calendar trigger handles DST; midnight
  travel may produce an extra briefing — acceptable.
- **Default notificationsEnabled = true** (user explicitly chose the notification layer for their
  fork; quiet-day rule guards fatigue). Flip to opt-in if this ever heads upstream.

## Verification

1. `mise run check:static` and `mise run format` after each PR.
2. Unit tests: `ONLY_TESTING=PocketCastsTests mise run test:staging` (SIMULATOR_OS=26.5).
3. End-to-end in Simulator (drive-app skill): build staging, subscribe to a few podcasts, pull to
   refresh → toggle to Briefing → verify greeting/cards/takeaway-seek (tap chip → player seeks),
   Play/Up Next actions, quiet-day state (re-open with nothing new), settings toggles reorder/hide
   sections live, deep link `xcrun simctl openurl booted "pktc://briefing"` lands on the surface.
4. Notification: set scheduleHour to next minute-adjacent hour (or use
   `xcrun simctl push` with the payload), verify quiet-day cancellation by assembling an empty day.
5. Widget: add DailyBriefingWidget in the simulator, assemble, verify counts/artwork and tap-through.
6. FM-unavailable path: run on a simulator (FoundationModels unavailable) — cards must degrade to
   summary/headline mode without errors.
