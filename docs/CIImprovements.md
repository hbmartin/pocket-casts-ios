# CI Setup Improvements

Steps to make CI test runs reliable, ordered so the likely root-cause fixes come first.
These complement (and should land before judging the need for) the test-seam refactors
in the codebase — several test failures are expected to disappear after step 1 alone.

## 1. Switch test runs from "no signing" to ad-hoc signing

In `scripts/ci/build-and-test.sh` (and the `test:staging` task in `mise.toml`), replace:

```
CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
```

with:

```
CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO
```

for the `xcodebuild test` invocation. Unsigned simulator binaries cannot derive an app
identifier for SecItem, which is the classic cause of keychain OSStatus `-34018`
(`errSecMissingEntitlement`). Ad-hoc signing needs no team or provisioning profile on
the simulator, but gives the test host a real signature so keychain calls work.

Note: `CODE_SIGNING_ALLOWED=NO` is fine for plain simulator *builds* (e.g. the
launch instructions in CLAUDE.md); it only matters for the test host.

## 2. Validate the signing fix against the known-failing tests

Run one CI build with step 1 applied and check:

- `ServerSettingsPushTokenTests` (kept as the real-keychain integration canary)
- `TokenHelperTests`
- `PodcastManagerTests.testUnsubscribeRemovesDownloadsInPlaylist` / `...NotInPlaylist`
- `EpisodeManagerTests.testUrlForEpisodeStreamingOnlyWithUserEpisode`

If these pass, the keychain problem was environmental and the in-code seams are
quality improvements rather than requirements.

## 3. Create a fresh simulator per run

Before destination selection in `build-and-test.sh`, either `xcrun simctl create` a
dedicated test device or `xcrun simctl erase` the device that
`scripts/ci/select-ios-simulator.rb` picks. This clears stale keychain entries,
leftover download files, and old app containers between runs.

## 4. Shut down booted simulators before selection

`xcrun simctl shutdown all` before running the selector, so the selector and
`xcodebuild` cannot disagree about which device is in use.

## 5. Re-check background URLSession behavior on a fresh simulator

`DownloadManagerTests.testStuckSingleDownload` and
`PodcastManagerTests.testTaskCancellationForUnusednDeletion` intentionally still use
real background `URLSession`s — they are the canaries for `com.apple.nsurlsessiond`
availability. If they still fail with error `-1` after steps 1–4, the daemon issue is
environmental on the runners; at that point, move those tests onto injected ephemeral
sessions (the `DownloadManager` init seam already supports this) and accept losing the
canary, or fix the runner image.
