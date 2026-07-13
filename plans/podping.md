# Podping/WebSub Instant Feed Updates for `.localFeed` Podcasts (Item 57)

## Context

`docs/DeferredWork.md` Item 57 describes a deferred concept: subscribe to Podping for
followed feeds with `refreshSource == .localFeed`, and trigger a targeted refresh on ping,
with WebSub as a fallback for feeds advertising hubs. It was deferred until Track A's
on-device refresh work shipped and soaked (`docs/LocalFirstProgramSummary-2026-07.md`,
`docs/LocalFirst.md`) — that has now happened, so this un-defers it.

Research this session established a hard constraint the original one-line concept didn't
account for: **neither protocol has a consumer-friendly client story**. Podping has no
hosted subscriber relay — `podping.cloud` is a *publisher* write path only; consuming it
means watching the Hive blockchain directly. WebSub requires a hub to `POST` to a public
HTTPS callback URL, which a phone cannot host. iOS also won't sustain a background
WebSocket without special entitlements. This repo is iOS-client-only (confirmed — no
server code lives here).

**Decision (made by the user for this plan):** build a small **companion relay server
outside this repo** that does the actual blockchain-watching and WebSub-hub-subscribing,
and notifies this app via a normal silent APNs push naming the affected podcast. This
plan covers the full iOS-side contract with that relay, at production-readiness depth
(not just a wire-it-up MVP): privacy/consent, failure handling, rollout, and safeguards.
The relay's own internal implementation is a separate, out-of-repo effort — treat every
mention of it here as "the contract this app depends on," not something to build.

This also intersects with the fork's local-first philosophy directly:
`.localFeed` podcasts exist specifically so a signed-out library never touches any
Pocket Casts server (`docs/LocalFirst.md`). Sending those feed URLs + a push token to a
new relay is a real privacy trade-off, so this must be **opt-in, off by default**, not
folded into the feature flag alone.

## Architecture summary

- Relay (out of repo): watches Hive for `podping` custom_json ops filtered to a
  per-device set of watched feed URLs; independently WebSub-subscribes to any feed that
  advertises a hub; sends a silent APNs push identifying the changed podcast.
- iOS app: registers/reconciles its `.localFeed` watch list + push token with the relay;
  recognizes the relay's push via a discriminator key; triggers a **single-podcast**
  refresh (a new `RefreshManager` entry point, since none exists today); keeps existing
  `BGTaskScheduler`/foreground-timer polling as the fallback — the relay is a latency
  optimization on top of it, never the sole path to freshness.

## 1. `RefreshManager` — new single-podcast entry point

`Modules/Sources/PocketCastsServer/Public/Refresh/RefreshManager.swift` currently only
exposes `refresh(podcast:from:)` (sync, line 39, and async, line 57), both of which set
`podcast.forceRefreshEpisodeFrom = episodeUuid` and then, on completion, synchronously
pull server episode-sync state via `ApiServerHandler.retrieveEpisodeTaskSynchronouusly`
when signed in. That sync branch exists for `.server`-sourced podcasts; `.localFeed`
podcasts never account-sync, so reusing it would be a wasted round trip.

Add a new overload next to the existing pair:

```swift
/// Refreshes a single podcast with no episode anchor — the relay-push entry point.
/// Callers must only pass `.localFeed` podcasts (asserted/guarded by the caller);
/// unlike `refresh(podcast:from:)` this never touches the account episode-sync path.
public func refresh(podcast: Podcast) {
    refresh(podcasts: [podcast])
}

public func refresh(podcast: Podcast) async {
    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
        refresh(podcasts: [podcast]) { continuation.resume() }
    }
}
```

This calls the existing private `refresh(podcasts:completion:)` (line 93) directly, which
already routes through `CompositeFeedRefreshProvider` (`FeedRefreshProviding.swift:37-46`)
and partitions purely on `isLocalFeedSourced` — a single `.localFeed` podcast correctly
lands in `LocalFeedRefreshProvider` with no new plumbing.

## 2. WebSub hub-URL parsing (feed side)

`FeedParser.swift` (`Modules/Sources/PocketCastsServer/Public/LocalFeed/FeedParser.swift`)
parses `<atom:link>` in `handleLink(namespaceURI:attributes:)` (line 188) but only
recognizes `rel="enclosure"` and `rel="next"`. Add:

- `public var hubURL: String?` to `ParsedFeed` (line ~5-23).
- A `rel == "hub"` branch in `handleLink`, parallel to the existing `rel == "next"` branch
  (line 197): `else if rel == "hub", let href = attributes["href"] { feed.hubURL = href }`.

**The app parses and forwards the hub URL; the relay does not need to independently
discover it.** `LocalFeedFetcher`/`FeedParser` already fetch and parse every `.localFeed`
feed on every normal refresh (`LocalFeedRefreshProvider.swift:36-86`), so capturing
`hubURL` there is a zero-marginal-cost byproduct, kept fresh by the app's own existing
refresh cadence. Having the relay re-fetch every watched feed itself just to check for a
hub would duplicate load across every client's feeds for no benefit.

Wire it through `LocalFeedRefreshProvider.fetchUpdates` (line 36-86): when a refresh
produces a `hubURL` that differs from what's currently registered for that podcast, mark
the podcast for re-registration (see `podpingRegistered` below).

## 3. New relay client module

New directory `Modules/Sources/PocketCastsServer/Public/Relay/`, mirroring the
`LocalFeed/` style exactly (`LocalFeedFetcher.swift`: `Sendable` struct, injectable
`URLSession = .shared`, async/await, typed error enum — no Alamofire in this module).

**`PodpingRelayClient.swift`**:
```swift
public struct PodpingRelayClient: Sendable {
    public enum RelayError: Error { case invalidURL, httpError(statusCode: Int) }
    public struct Watch: Codable, Sendable { public let feedURL: String; public let podcastUuid: String }

    public init(session: URLSession = .shared, baseURL: String = ServerConstants.Urls.podpingRelay()) { ... }

    /// Full reconciliation: replaces the relay's watch set for this install.
    public func syncWatches(installId: String, secret: String, deviceToken: String, watches: [Watch]) async throws
    /// Deregisters a device entirely (toggle-off).
    public func removeDevice(installId: String, secret: String) async throws
}
```

Add `ServerConstants.Urls.podpingRelay()` in
`Modules/Sources/PocketCastsServer/Public/Sharing/Structs/ServerConstants.swift`
following the exact `production()`-gated pattern already used by `main()`/`cache()`
(lines 5-15, 67-70).

**Reconciliation is full-set replace, not incremental diffing** — watch-list sizes per
device are small, and a full resync is self-healing against missed calls, drift, and
multi-device state, at the cost of a slightly larger payload. `PodpingRelayReconciler`
(same directory) owns:
- A debounced `enqueueSync()` (coalesce bursts like OPML import — cancel-and-replace a
  pending `Task` with ~2s delay before actually calling `syncWatches`).
- Bounded retry/backoff on failure, reusing the existing poll-backoff table at
  `Modules/Sources/PocketCastsServer/Public/Search/PodcastSearchTask.swift:117-166`
  rather than inventing a new scheme.
- A `disable()` that fires `removeDevice` best-effort and clears local state.

**Identity, not the account ID.** Generate a relay-scoped `install_id` (random UUID) and a
`registration_secret` (random 256-bit value) on first opt-in; store both in Keychain
under new keys, separate from `ServerSettings`'s existing push-token storage (recommend a
new `RelaySettings.swift` in the same `Relay/` directory, so "wipe relay data" is one
auditable code path, not entangled with `ServerSettings.removePushToken()`). **Never**
send `ServerConfig.syncDelegate?.uniqueAppId()` (the identifier tying this device to the
main PC account/sync system) to the relay — reusing it would let a compromised relay
correlate an otherwise-anonymous local-first user with their signed-in identity later.
The `registration_secret` must be echoed back on unregister/reconcile calls so a party
that merely observes `install_id` can't deregister or probe another device's watches.
Exclude both from iCloud Keychain sync (match the `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`
precedent at `ServerSettings.swift:204-233`) — a restored backup on a new device should
not silently inherit consent.

**DB field**: add `SJPodcast.podpingRegistered` (`Bool`, default `false`) via
`SchemaMigration(toVersion: 82)` in
`Modules/Sources/PocketCastsDataModel/Private/Managers/Util/DatabaseHelper.swift`
(current latest is `toVersion: 81`, line 138), mirroring migration 76's style:
```swift
SchemaMigration(toVersion: 82) { db in
    try db.executeUpdate("ALTER TABLE SJPodcast ADD COLUMN podpingRegistered INTEGER DEFAULT 0;", values: nil)
}
```
Mirror onto `Podcast` (`Modules/Sources/PocketCastsDataModel/Public/Model/Podcast.swift`,
next to `refreshSource` at line ~70/161) as `public var podpingRegistered = false`. This
lets reconciliation ask "which subscribed `.localFeed` podcasts still need to be told to
the relay" via `DataManager.sharedManager.allPodcasts(includeUnsubscribed: false).filter
{ $0.isLocalFeedSourced && !$0.podpingRegistered }` without resending the whole library
every time. Flip to `false` on: toggle re-enable, hub-URL change, unsubscribe (irrelevant
after delete, but reset before resubscribe). Flip to `true` after a `syncWatches` succeeds
for that row.

## 4. Registration/reconciliation lifecycle — exact hook points

Verified subscribe/unsubscribe call sites in `ServerPodcastManager.swift`:
- `effectiveRefreshSource` (pure, unit-tested) at lines 357-365; called at lines 298-303
  inside private `addPodcast` (lines 250-341), which is the single DB-writing subscribe
  path reached by both public entry points `addFromJson` (94-105) and `addLocalFeed`
  (110-137).
- `addPodcast` already has the established pattern for "just became `.localFeed` via
  subscribe" follow-up work: `refreshAfterSignedOutFlip(podcast:)`, called right after
  save (lines 305-338), guarded on `effectiveSource == .localFeed`. Add
  `PodpingRelayReconciler.shared.enqueueSync()` alongside that call — not a synchronous
  inline network call, so subscribe stays fast and offline-tolerant.
- Unsubscribe: `podcasts/PodcastManager+Delete.swift`, the single `unsubscribe(podcast:)`
  method (lines 6-45) — both the signed-in soft-unsubscribe branch (lines 11-27) and the
  signed-out hard-delete branch (lines 28-32) already converge on
  `PlaylistManager.handlePodcastUnsubscribed(podcastUuid:)` (line 35) and
  `NotificationCenter.postOnMainThread(PodcastDeleted(uuid:))` (line 43). Add
  `PodpingRelayReconciler.shared.enqueueSync()` there too — the next full-set resync
  naturally drops the removed feed.
- Toggle on (Settings): `enqueueSync(forceFullResync: true)` — mark every `.localFeed`
  podcast `podpingRegistered = false` first so the resync sends the complete library.
- Toggle off: `PodpingRelayReconciler.shared.disable()` — best-effort `removeDevice`,
  then clear local `podpingRegistered` flags and stop enqueuing. The real safety net is
  client-side: `handlePodpingPush` (below) re-checks the toggle at delivery time, so a
  relay that keeps pushing after a failed unregister call is still a no-op.
- Token refresh: `podcasts/AppDelegate.swift`
  `didRegisterForRemoteNotificationsWithDeviceToken` (line 246) already calls
  `PodcastManager.shared.didReceiveToken(token)` (`PodcastManager.swift:98-106`, which
  early-outs on an unchanged token). Add
  `PodpingRelayReconciler.shared.deviceTokenDidChange(token)` after it, with its own dedup
  (don't rely on `didReceiveToken`'s gate — the reconciler also needs to fire after a
  prior sync failure even when the token itself didn't change).
- App launch: in `handleBecomeActive()` (`AppDelegate.swift:214-231`), if
  `Settings.podpingRelayEnabled()`, call `enqueueSync()` unconditionally — cheap
  self-healing; the query above is empty (no network call) unless something's actually
  out of sync.

## 5. Push handling — `AppDelegate.swift`

Payload discriminator: a top-level `relay` key, absent from the existing PC-server push
shape (that endpoint only registers the token via `MainServerHandler.createRefreshRequest`,
`MainServerHandler.swift:177-206`; it defines no push *payload* shape, so no collision).

```json
{"aps": {"content-available": 1}, "relay": "podping", "podcastUuid": "<uuid>", "pingId": "<nonce>"}
```

`didReceiveRemoteNotification` (line 238) branches before the existing blanket refresh:

```swift
func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any], fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
    if (userInfo["relay"] as? String) == "podping", let podcastUuid = userInfo["podcastUuid"] as? String {
        handlePodpingPush(podcastUuid: podcastUuid, pingId: userInfo["pingId"] as? String, completion: completionHandler)
        return
    }
    // ...existing unconditional refreshPodcasts() path, unchanged
}
```

`handlePodpingPush` — extract as a small, independently-testable helper (not left inline)
that validates, in order, before doing anything:
1. `FeatureFlag.podpingRelay.enabled` and `Settings.podpingRelayEnabled()` — both gates
   re-checked at delivery time, not just at registration time.
2. The podcast exists locally, is currently subscribed, and `isLocalFeedSourced` — a push
   for an unsubscribed or `.server` podcast (stale registration, race with a recent
   unsubscribe) is a silent no-op, logged, never acted on. This bounds a
   buggy/compromised relay's blast radius to "can force refreshes of feeds this device
   already explicitly opted to watch" — it can't make the app fetch or leak anything
   about a podcast never registered, and can't make it hit an arbitrary attacker-supplied
   URL (refresh always uses the podcast's own stored `podcastUrl`, never a URL from the
   push).
3. `pingId` dedup against a small persisted (not just in-memory — a push can arrive after
   a relaunch) rolling set of recently-processed IDs per podcast, to absorb APNs/relay
   redelivery.
4. A **per-podcast cooldown** (see §7) — if within cooldown, drop and log, don't queue for
   later (avoids delayed bursts).

On passing all checks: `await RefreshManager.shared.refresh(podcast: podcast)`, update the
cooldown timestamp, call `badgeHelper.updateBadge()`, complete with `.newData`.

## 6. FeatureFlag + Settings toggle + consent UX

**FeatureFlag**: add `case podpingRelay` to
`Modules/Sources/PocketCastsUtils/Feature Flags/FeatureFlag.swift` (after `.episodeCredits`,
line 99), with `default` gated `BuildEnvironment.current != .appStore` exactly like
`.diarizedTranscription` (line 141-142). This gates whether the Settings toggle is even
shown (existence kill switch) — separate from user consent.

**Settings toggle** — `podcasts/Settings.swift`, next to `localFeedIngestEnabledKey`
(lines 118-128), same shape:
```swift
private static let podpingRelayEnabledKey = "SJPodpingRelayEnabled"

class func podpingRelayEnabled() -> Bool {
    UserDefaults.standard.bool(forKey: Settings.podpingRelayEnabledKey)
}

class func setPodpingRelayEnabled(_ enabled: Bool) {
    UserDefaults.standard.set(enabled, forKey: Settings.podpingRelayEnabledKey)
}
```
Default `false` (unset key reads `false` — no migration needed).

**Placement**: `podcasts/GeneralSettingsViewController.swift`, immediately after
`.localFeedIngest` in the `TableRow` enum/section array (lines 15, 17), same
`SwitchCell`/target-action pattern as lines 155-167 and 568.

**Consent flow**: because this sends data off-device (stronger bar than the on-device
`localFeedIngest` toggle, which has no confirmation today), add a one-time confirmation
sheet before flipping the switch on — reuse the existing `OptionsPicker`-style confirm
pattern already in this file (`promptToApplyGroupingToAll`, lines 515-529). Copy must
state, concretely: what leaves the device (feed URLs of `.localFeed` podcasts only, plus
push token and a relay-scoped random ID — not account identity, not listening history,
not episode data); where it goes (a relay service distinct from Pocket Casts' main sync
servers); why (faster updates than periodic background refresh, which keeps working
either way); and that it's reversible from the same screen. **v1 ships all-or-nothing at
the library level** (one toggle governs all current and future `.localFeed` podcasts) —
per-podcast opt-out is a reasonable fast-follow, not required now (see open questions).

Toggle off must, regardless of network success: clear local Keychain `install_id`/secret,
stop all future sync attempts, and best-effort fire the unregister call in the background
(never block the UI on it).

## 7. Failure modes, resilience, and safeguards

| Scenario | Handling |
|---|---|
| Relay unreachable / errors at registration | Bounded backoff retry (mirror `PodcastSearchTask.pollWaitingTime`); toggle UI reflects "enabled, pending" vs "enabled, active" vs "enabled, relay unreachable" rather than a bare on/off; background refresh is unaffected regardless. |
| Duplicate/replayed ping | `pingId` dedup + per-podcast cooldown (§5.3-4). |
| Push for an already-unsubscribed podcast | Delivery-time re-check of subscription + `isLocalFeedSourced` (§5.2) — silent no-op. |
| Multiple devices | Each device has its own `install_id`/token/cooldown state; cooldown/rate-limit state is purely local per device. |
| Reinstall / new device token | New install → new Keychain → fresh `install_id` → consent resets to off (a privacy feature must not silently survive backup/restore). Token change on an existing install → update-in-place via the same `didReceiveToken`-adjacent hook (§4), not a new registration. |
| Force-quit / backgrounded / foregrounded | Silent push still wakes the app via the existing `fetchCompletionHandler` path; must stay within the background-fetch time budget (one feed fetch, not a full-library refresh — already satisfied by using the new single-podcast `refresh(podcast:)`). Foregrounded delivery should also nudge any open Podcast screen (existing `ServerNotificationsHelper` notification plumbing) so it reflects new episodes without a manual pull-to-refresh. |
| Feature flag killed remotely mid-rollout | Delivery-time `FeatureFlag.podpingRelay.enabled` check (§5.1) stops processing immediately; best-effort unregister; local consent preference is left intact so re-enabling the flag can silently resume without re-prompting (flag as open question if legal wants stricter re-consent-on-re-enable). |

**Battery/data caps**: a per-podcast cooldown longer than the existing library-wide
`RefreshManager.minTimeBetweenRefreshes` (`RefreshManager.swift:26`, 15s) — e.g. 5
minutes, since a relay-triggered refresh is meant to be rare/event-driven, not a
substitute for polling — tracked in a small persisted `[podcastUuid: Date]`. Add a global
per-device ceiling on relay-triggered refreshes per rolling hour (e.g. 20) to bound a
misbehaving relay that pings a whole large library at once; sustained rate-limit hits
should auto-suspend relay processing until the next reconcile, logged distinctly (a
relay-side bug the client can't fix, but shouldn't let drain the battery). The push
handler never does more than the one bounded feed fetch — no chained re-register/reconcile
work inside the push path itself.

## 8. Rollout & telemetry

Staged rollout via the `FeatureFlag` remote-config override (internal/TestFlight → small
percentage → full), same mechanism already used for `.diarizedTranscription`/
`.episodeCredits`. Track via the existing `Analytics.track(.event, properties:)`
convention (`TranscriptionQueueManager.swift` lines 346/447/551/566/582):
`relayOptInShown` / `relayOptInAccepted` / `relayOptInDeclined` / `relayOptOut`,
`relayRegistrationSucceeded` / `Failed`, `relayPushReceived` (with a valid/invalid/
duplicate/stale/rate-limited reason — the key signal for relay misbehavior),
`relayRefreshTriggered` (ping-to-refresh latency, the feature's core value metric),
`relayRefreshThrottled`, `relayReconcileCompleted`/`Failed`. Prefer counts/booleans over
identifiers in analytics properties for this feature specifically, given the privacy
framing — don't reflexively copy the `episode_uuid`-in-properties precedent without a
deliberate check.

## 9. Testing strategy

**Unit-testable in this repo:**
- `RefreshManager.refresh(podcast:)` — inject a fake `FeedRefreshProviding` via the
  existing `init(feedRefreshProvider:)` seam (line 15-17); assert it's called with
  exactly one podcast, no `forceRefreshEpisodeFrom`, and no `ApiServerHandler`/
  `SyncManager` interaction.
- `PodpingRelayClient` — mock `URLSession` via `URLProtocol` stub; assert request shape
  and error mapping.
- `FeedParser` hub-URL parsing — extend the existing corpus/fixture tests
  (`FeedParserCorpusTests`) with a `rel="hub"` fixture.
- `PodpingRelayReconciler`'s "which podcasts need syncing" logic — a pure function over
  `[Podcast]`, independently testable; plus the debounce and backoff behavior.
- `handlePodpingPush`'s validation chain — extract as a plain function of `userInfo` +
  app state so it's testable without booting `AppDelegate`.

**Requires manual QA / the relay (or a stand-in) to exist:**
- Real push delivery and real Podping/WebSub behavior aren't exercisable from this repo.
- Add a "Simulate Podping Push" action to the debug menu (`podcasts/DeveloperMenu.swift`)
  that either invokes `handlePodpingPush` directly for a chosen `.localFeed` podcast, or
  drives `application(_:didReceiveRemoteNotification:fetchCompletionHandler:)` with a
  fabricated `userInfo`, exercising the real discriminator branch.
- Use `xcrun simctl push` with a canned `.apns` payload file (see `ios-simulator` skill)
  as the manual QA script of record for actual APNs-delivery-path testing.
- A trivial local HTTP stub can stand in for the relay's registration endpoint during
  manual QA of the reconciliation lifecycle while the real relay is still being built,
  unblocking iOS work in parallel.

## 10. Open questions / risks needing a human decision

1. **Relay ownership, hosting, and uptime SLA** — affects whether product copy can say
   "faster updates" vs. must hedge as best-effort (the architecture already treats it as
   best-effort via the fallback design; this is a product/business framing question).
2. **Legal/privacy-policy update** and **App Store privacy nutrition label** — a new
   outbound data flow (feed URLs + push token to a non-Pocket-Casts-primary endpoint)
   likely needs a privacy-policy amendment and an App Store Connect "identifiers shared
   with a third-party partner" label update before shipping beyond internal builds.
   Needs legal/App-Store-submission sign-off, not just the in-app consent sheet.
3. **Full-resync vs. incremental register/unregister verbs** — this plan assumes full-set
   replace is simplest given small per-user watch counts; if the relay team wants
   incremental diffing at scale, the client contract and reconciler need real diffing
   logic instead.
4. **Consent re-prompt policy on flag re-enable after a kill-switch event** — currently
   planned to silently resume without re-prompting; confirm that's acceptable or whether
   policy requires fresh consent each time.
5. **Per-podcast opt-out** — confirm all-or-nothing is acceptable for v1, or whether
   privacy-sensitive local-first users need finer control from day one.
6. **Push-payload trust model** — no HMAC/signing of the relay's push payload is proposed
   beyond APNs' own TLS-authenticated delivery plus the delivery-time validation in §5;
   confirm that's sufficient given the relay is treated as first-party-ish.

## Verification

- Unit tests: `ONLY_TESTING=PocketCastsServerTests mise run test:staging` (new
  `RefreshManager`/`PodpingRelayClient`/`FeedParser` cases) and
  `ONLY_TESTING=PocketCastsDataModelTests mise run test:staging` (migration 82).
- Manual: enable the feature flag + toggle on a simulator build, use the debug-menu
  "Simulate Podping Push" action (or `xcrun simctl push` with a fabricated payload)
  against a subscribed `.localFeed` podcast, and confirm via `FileLog`/breakpoints that
  exactly one podcast refreshes, the cooldown suppresses an immediate repeat ping, and
  toggling off stops further processing.
