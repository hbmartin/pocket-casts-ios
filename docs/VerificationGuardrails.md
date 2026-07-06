# Verification Guardrails

The Swift 6.2 default-MainActor adoption (PR #243) shipped with green unit suites and still
crashed on every cold start (fixed in PR #244). The gap: unit tests share one long-lived
test-host process and never re-exercise cold start, background launch work, or real
refresh/playback pipelines — and an intermittent race can kill the test host *between* tests
without failing the run. These guardrails close those gaps.

## Per-run (wired into `mise run test*` and per-PR CI)

### Crash-report sweep — `scripts/ci/check-crash-reports.sh`

Snapshots `podcasts-*.ips` crash reports before each test run and fails the run if new ones
appear, even when every suite passed. This is the only signal for "tests green but a process
died" (exactly how the AVFileUtil use-after-free surfaced). Wired into `mise run test`,
`test:staging`, `test:tsan`, `test:smoke-ui`, and `scripts/ci/build-and-test.sh`.

### Launch smoke test — `scripts/ci/smoke-launch.sh` / `mise run smoke:launch`

Installs the built app on a simulator, launches it, and fails if the process dies or leaves a
crash report within the settle window (default 30s), saving a screenshot artifact. Catches
launch-path executor traps deterministically (the SiriShortcutsManager and
NotificationCenter-selector crashes died at ~200ms and ~3s). Runs at the end of CI's
build-and-test job using the just-built products.

## On demand / nightly

### UI smoke plan — `mise run test:smoke-ui`

`PocketCastsUITests` (test plan `SmokeUITests`, referenced from the Pocket Casts Staging
scheme) drives cold start + settle, tab navigation, background/foreground cycling, and a
Discover browse against staging. These are the lifecycle and network paths unit tests
structurally cannot reach. Not part of the default unit test plan, so `mise run test:staging`
stays fast.

### Thread Sanitizer — `mise run test:tsan`

The unit suites under TSan. Races like AVFileUtil's non-atomic `self` reads from concurrent
tasks are diagnosed directly instead of appearing as one-in-N crashes.

### Nightly workflow — `.github/workflows/nightly-runtime-checks.yml`

Runs TSan, the unit suites on the newer installed iOS runtime (26.5), and the UI smoke plan.
Executor and isolated-deinit behavior differ across OS runtimes (see swiftlang/swift#87316),
so green on 18.6 does not imply green elsewhere.

## Semgrep lock-ins (`semgrep/swift-security.yml`)

- `pocketcasts.server-module-post-on-main-thread` — Server-module code must post
  notifications via `NotificationCenter.postOnMainThread`; selector observers are delivered
  synchronously on the posting thread and main-actor selectors trap off-main.
- `pocketcasts.isolated-deinit-requires-justification` — `isolated deinit` needs a
  justification comment; it routes deallocation through `swift_task_deinitOnExecutor`, which
  crashes with task-local bindings on current runtimes and hides lifetime bugs by hopping to
  the main actor to die.

## Off-main deallocation harness

`PocketCastsTests/Tests/Concurrency/OffMainDeallocationTests.swift` asserts that nonisolated
utility/IO classes deallocate synchronously off the main actor (a wrongly-@MainActor class
with an isolated deinit fails this, and the compiler will not flag it). When you mark a class
`nonisolated` because production releases it off-main, add it to this suite — including a
rapid create/release stress loop if the class starts async work in `init` (the AVFileUtil
pattern).

## Known flip crash classes (compiler-silent)

These crash at runtime under `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` with no compile error:

1. **Off-main NotificationCenter selector delivery** — a main-actor `@objc` selector observer traps
   when its notification is posted off-main. Post via `NotificationCenter.postOnMainThread`.
2. **`.shared` touched from a background launch path** — if the singleton's type or base class is
   main-actor, the first access off-main traps at launch. Hop with `Task { @MainActor }`.
3. **Combine operator before `receive(on:)`** — `.filter`/`.map`/`.compactMap` closures are
   `@MainActor` under the flip and run synchronously on the thread that called `.send()`. If the
   subject is sent off-main (e.g. `PlaylistMetadataLoader`'s async Task, the nonisolated
   `BookmarkManager` called from playback), the operator traps a main-queue assertion. **Hoist
   `.receive(on: DispatchQueue.main)` to the front of the chain, before any operator that reads
   main-actor state.** Audit every UI Combine subscription whose upstream can send off-main.

## Device canary

The simulator cannot validate real audio sessions, pointer authentication, or the watchdog.
After concurrency-sensitive changes (anything touching playback, downloads, or isolation
boundaries), push a build through the personal TestFlight pipeline
(`.github/workflows/testflight-personal.yml`, see `docs/PersonalTestFlight.md`) and use it
for a day of real listening — Bitdrift symbol upload is wired, so field crashes surface with
symbolicated stacks.
