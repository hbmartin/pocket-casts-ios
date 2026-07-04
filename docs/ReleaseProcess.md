# Release Process

Pocket Casts iOS releases are driven by Fastlane and, for normal team use, by
the manual GitHub Actions workflow in `.github/workflows/release-fastlane.yml`.
The workflow runs on the self-hosted macOS runner labeled `ARM64`.

This document covers the release surfaces that are easy to confuse:
versioning, branch creation, code signing, TestFlight upload, App Store
metadata, dSYM handling, GitHub release creation, and release-lane access.

> **Shipping this fork to your own TestFlight?** The pipeline below requires
> Automattic's team, secrets, and signing storage. Fork owners should use the
> separate `TestFlight Personal` workflow instead — see
> [testflight.md](./testflight.md).

## Release Entry Points

Use the manual GitHub Actions workflow for normal release work:

1. Open the `Release Fastlane` workflow.
2. Choose a `task`.
3. Enter `release_version`, for example `8.14` or `8.13.1`.
4. For `release_build`, choose whether `beta_release` should be `true` or
   `false`.

The workflow exposes these tasks:

| Task | Purpose |
| ---- | ------- |
| `code_freeze` | Create `release/<version>` from `trunk`, bump version files, freeze strings, extract release notes, trigger the first beta build, open backmerge work, and protect the release branch. |
| `new_beta_release` | Pull the current release branch, refresh localization and metadata translations, bump the build number, trigger another beta build, and open backmerge work. |
| `finalize_release` | Prepare a normal release for the final App Store build by refreshing translations, bumping the build number, closing the milestone, triggering a final release build, and opening backmerge work. |
| `new_hotfix_release` | Create `release/<x.y.z>` from the previous release tag or release branch, then set the hotfix version and build number. |
| `finalize_hotfix_release` | Trigger a final hotfix release build from the hotfix release branch, open backmerge work, and close the hotfix milestone if present. |
| `release_build` | Build App Store artifacts, upload the app to TestFlight, and create the matching GitHub release. |
| `publish_release` | Publish the existing final draft GitHub release, create the final tag, backmerge the release branch, remove branch protection, and delete the release branch. |

Local Fastlane invocation is possible for release maintainers on a configured
machine:

```bash
bundle exec fastlane code_freeze version:"8.14"
bundle exec fastlane new_beta_release
bundle exec fastlane finalize_release
bundle exec fastlane build_app_store_connect
bundle exec fastlane upload_app_store_connect_build_to_testflight
bundle exec fastlane create_release_on_github beta_release:true
```

The workflow runs the same lanes with `skip_confirm:true` where supported.

## Who Can Run Release Lanes

Release lanes must only be run by maintainers or release engineers who are
trusted to publish builds and mutate release state. In practical terms, that
means the person or automation needs all of the following:

- Permission to manually dispatch `.github/workflows/release-fastlane.yml`.
- Access to the self-hosted macOS runner labeled `ARM64`.
- Access to `POCKET_CASTS_RELEASE_GITHUB_TOKEN`, exposed to Fastlane as
  `GITHUB_TOKEN`.
- App Store Connect API credentials for the Pocket Casts App Store team.
- Code signing access through Fastlane match.
- Permission to use the Slack webhook and Bitdrift API key needed by release
  lanes and Release builds.

Do not run release lanes for untrusted pull request code. Release lanes push
branches, create tags and releases, alter branch protection, close milestones,
upload binaries, and access signing material. Public CI and release automation
should remain separate, as described in `docs/GitHubActionsLocalRunner.md`.

The workflow itself is `workflow_dispatch`; it does not add a separate
allow-list beyond GitHub permissions, repository secrets, and runner access.
Treat those controls as the release boundary. In GitHub terms, the operator
needs enough repository permission to dispatch the workflow; in Pocket Casts
terms, they also need to be approved to use release credentials. Code ownership
alone is not enough if the person cannot dispatch the workflow or use the
required secrets.

## Required Environment

Fastlane loads secrets in `before_all`:

- `configure_apply` decrypts the local release secrets.
- `Dotenv.load(USER_ENV_FILE_PATH)` loads
  `~/.a8c-apps/pocket-casts-ios.env`.
- `setup_ci` prepares the Fastlane CI environment.

The configured runner may also rely on files under
`~/.configure/pocketcasts-ios` for decrypted release secrets. Keep those files
out of the repository checkout and out of the Actions `_work` directory.

`fastlane/example.env` documents the expected variables:

```bash
GITHUB_TOKEN=
SLACK_WEBHOOK=
BITDRIFT_API_KEY=
APP_STORE_CONNECT_API_KEY_KEY_ID=
APP_STORE_CONNECT_API_KEY_ISSUER_ID=
APP_STORE_CONNECT_API_KEY_KEY=
```

Release jobs in GitHub Actions additionally require
`POCKET_CASTS_RELEASE_GITHUB_TOKEN`; the workflow maps it to `GITHUB_TOKEN`.
That token must be able to dispatch workflows, write contents and releases,
write issues and pull requests, and manage branch protection when a lane needs
to copy, modify, or remove branch protection.

## Code Signing

Code signing is managed by Fastlane match through `sync_code_signing`.
Signing assets are stored in the S3 bucket `a8c-fastlane-match` in
`us-east-2`.

The signing lanes are:

```bash
bundle exec fastlane configure_code_signing_app_store
bundle exec fastlane configure_code_signing_enterprise
bundle exec fastlane configure_code_signing_app_store_tvos
```

The App Store team ID is `PZYM8XX95Q`. The Enterprise team ID used for
Prototype builds is `99KV9Z6BKV`.

The App Store bundle identifiers include the main app identifier
`au.com.shiftyjelly.podcasts` and each extension identifier derived from it:

- `Clip`
- `NotificationContent`
- `NotificationExtension`
- `PodcastsIntents`
- `PodcastsIntentsUI`
- `Share-Extension`
- `WidgetExtension`

Enterprise builds use `au.com.shiftyjelly.podcasts.prototype` with matching
extension identifiers. tvOS currently signs only the root
`au.com.shiftyjelly.podcasts` identifier, but it uses platform-specific match
profiles.

The signing lanes default to `readonly:true`. Keep that default for normal
release builds because it only fetches existing certificates and provisioning
profiles. Use `readonly:false` only when an authorized maintainer intentionally
needs Fastlane match to create or regenerate Developer Portal assets and write
the updated signing material back to S3.

`build_app_store_connect` calls `configure_code_signing_app_store` by default.
`build_app_store_connect_tvos` calls `configure_code_signing_app_store_tvos`.
`build_enterprise` calls `configure_code_signing_enterprise`.

## Versioning

The release version lives in `config/Version.xcconfig`:

```xcconfig
VERSION_SHORT = 8.13
VERSION_LONG = 8.13.0.2
```

`VERSION_SHORT` is the public marketing version. `VERSION_LONG` is the build
number. This project uses a four-part build number:

- Normal release code freeze: `x.y.0.0`
- Beta build increments: `x.y.0.1`, `x.y.0.2`, and so on
- Hotfix release code freeze: `x.y.z.0`

Do not manually bump these values for normal release work. The release lanes
write `config/Version.xcconfig` and commit the change with the standard
`Bump version number` commit message.

`code_freeze` computes the next normal release version unless a version is
provided. In the GitHub workflow, `release_version` is always required, so the
lane receives the explicit version from the workflow input.

`new_hotfix_release` requires an `x.y.z` version and rejects values without a
positive patch component. It creates the hotfix branch from the previous final
tag when available, otherwise from the previous release branch.

## Changelog And Release Notes

`CHANGELOG.md` is the source for build changelogs and GitHub release notes.
Each release section uses a version heading followed by an underline:

```markdown
8.14
-----
- Fix swipe action animations when adding episodes to Up Next [#4366](https://github.com/Automattic/pocket-casts-ios/pull/4366)
```

The pull request template asks authors to consider whether user-facing release
notes are needed. Release managers should review the section before code freeze
and before final release.

`code_freeze` reads the current version's `CHANGELOG.md` section and writes
the extracted copy to `podcasts/Resources/release_notes.txt`. It also updates
`CHANGELOG.md` for the next release through `ios_update_release_notes`.

`upload_app_store_connect_build_to_testflight` uses the same changelog section
as the TestFlight changelog. It removes GitHub PR links before upload. If the
section is empty, Fastlane uploads `Minor changes.`.

`create_release_on_github` also uses the same changelog section for the GitHub
release body. If the section is empty, it writes a fallback note that
`CHANGELOG.md` was empty for the version.

App Store "What's New" copy is separate from the raw changelog. The default
English App Store copy lives in `fastlane/metadata/default/release_notes.txt`.
There is currently **no automated translation pipeline**: the localized
`release_notes.txt` files under `fastlane/metadata/<locale>/` are whatever was
last committed. See
[translation-reimplementation.md](./translation-reimplementation.md) for the
plan to restore translation sync.

## Fastlane Release Flow

A normal release usually follows this shape:

1. Add and review `CHANGELOG.md` entries during development.
2. Run `code_freeze` for the target version.
3. Let the first `release_build` run, or manually run `release_build` with
   `beta_release:true` if the dispatch needs to be retried.
4. Run `new_beta_release` whenever another beta build is needed.
5. Upload App Store metadata when the release notes and translations are ready.
6. Run `finalize_release` when the final build should be produced.
7. Let the final `release_build` run with `beta_release:false`, or manually run
   it if the dispatch needs to be retried.
8. Submit or finish the App Store release in App Store Connect according to the
   release manager's checklist.
9. After Apple approval and public release, run `publish_release`.

A hotfix usually follows this shape:

1. Run `new_hotfix_release` with an `x.y.z` version.
2. Land the hotfix change on the hotfix release branch.
3. Run `finalize_hotfix_release`.
4. Let the final `release_build` run with `beta_release:false`, or manually run
   it if the dispatch needs to be retried.
5. After Apple approval and public release, run `publish_release`.

`release_build` is split into two jobs:

- `release_build` checks out the release branch, runs setup, builds the App
  Store artifacts, and uploads `artifacts/*.ipa` and `artifacts/*.zip` as a
  temporary GitHub Actions artifact.
- `release_upload` downloads those artifacts, uploads the IPA to TestFlight,
  and creates the GitHub release.

## TestFlight Upload

`build_app_store_connect` creates predictable artifact paths:

- `artifacts/pocket-casts.ipa`
- `artifacts/pocket-casts.app.dSYM.zip`
- `artifacts/pocket-casts.xcarchive`
- `artifacts/pocket-casts.xcarchive.zip`

The build uses scheme `pocketcasts`, `include_symbols:true`, `clean:true`, and
App Store export method `app-store`. It sets
`manageAppVersionAndBuildNumber:false` so App Store Connect does not rewrite
the version values from `config/Version.xcconfig`.

`upload_app_store_connect_build_to_testflight` uploads
`artifacts/pocket-casts.ipa` with these behaviors:

- Uses the App Store Connect API key from the release environment.
- Rejects a previous build that is waiting for Beta App Review.
- Distributes externally.
- Sends the build to the configured external tester groups.
- Notifies external testers.
- Uses the cleaned `CHANGELOG.md` section as the TestFlight changelog.

The external tester groups are configured in `fastlane/Fastfile`:

- `A8cs`
- `Alpha Slack`
- `Beta Slack`
- `Big Databases`
- `Reddit`
- `Stable Slack`
- `Trusted Preview Testers`

The `beta_release` workflow input does not change TestFlight distribution. It
controls whether the GitHub release is created as a prerelease or as a final
draft release.

tvOS has separate build and TestFlight lanes:

```bash
bundle exec fastlane build_app_store_connect_tvos
bundle exec fastlane upload_app_store_connect_build_to_testflight_tvos
```

The tvOS TestFlight lane currently uploads for internal testing only:
`distribute_external:false` and `skip_submission:true`.

## App Store Metadata

App Store metadata lives under `fastlane/metadata/`.

- `fastlane/metadata/default/` is the English source of truth.
- Locale folders such as `de-DE`, `fr-FR`, and `pt-BR` contain translated
  metadata. These are frozen — whatever was last committed — because the
  automated translation pipeline has been removed.

> **Note:** There is currently **no automated translation sync**. The lanes that
> previously generated source strings and downloaded translations have been
> removed; the localized strings and metadata in the repo are frozen until a
> replacement translation source is implemented — see
> [translation-reimplementation.md](./translation-reimplementation.md).

Relevant lanes:

```bash
bundle exec fastlane update_metadata_on_app_store_connect
```

`update_metadata_on_app_store_connect` uploads metadata from
`fastlane/metadata/` to App Store Connect with `skip_binary_upload:true`.
It enables phased release metadata and skips in-app purchase precheck.
Screenshots are skipped by default. Pass `with_screenshots:true` only when the
release intentionally needs screenshot updates:

```bash
bundle exec fastlane update_metadata_on_app_store_connect with_screenshots:true
```

The release GitHub Actions workflow does not currently expose
`update_metadata_on_app_store_connect` as a workflow task. Run it separately
from a configured release machine when metadata should be pushed.

## dSYM Upload And Symbolication

Release builds handle dSYMs in two ways:

1. `build_app_store_connect` uses `include_symbols:true`, which produces
   `artifacts/pocket-casts.app.dSYM.zip`.
2. The Xcode build phase `Upload Bitdrift Debug Files` runs
   `scripts/build-phases/upload-bitdrift-debug-files.sh` for Release
   configuration builds.

The Bitdrift upload requires `BITDRIFT_API_KEY`.

- In GitHub Actions, a missing `BITDRIFT_API_KEY` fails the Release build.
- In local Release builds, a missing `BITDRIFT_API_KEY` prints a warning and
  skips the upload.

The script downloads the pinned Bitdrift `bd` CLI for the current architecture,
verifies its SHA-256 checksum, and runs:

```bash
bd debug-files upload --api-key="$BITDRIFT_API_KEY" <dSYM path>
```

GitHub releases also attach `artifacts/pocket-casts.xcarchive.zip`. The
archive contains dSYMs and can be used for crash log symbolication, as noted in
`README.md`.

There is no separate Fastlane `upload_symbols` lane in this repository. For the
current release automation, the expected dSYM destinations are Bitdrift during
the Release build and the zipped xcarchive attached to the GitHub release.

## GitHub Release Creation

`create_release_on_github` creates the GitHub release after the TestFlight
upload step.

For beta builds:

- `beta_release:true`
- The release name and tag target are the build number, for example
  `8.14.0.1`.
- The release is published immediately.
- The release is marked as a prerelease.

For final builds:

- `beta_release:false`
- The release name and tag target are the app version, for example `8.14`.
- The release is created as a draft.
- The release is not marked as a prerelease.

Both release types use the current Git commit as `commitish`, attach
`artifacts/pocket-casts.xcarchive.zip`, and use the `CHANGELOG.md` section as
the description.

After the final build is approved and released publicly, run `publish_release`.
That lane publishes the existing draft GitHub release, lets GitHub create the
final tag, opens the needed backmerge work, removes release branch protection,
deletes the remote `release/<version>` branch, checks out `trunk`, and deletes
the local release branch.

## Failure And Retry Notes

- If code signing fails before build, confirm the App Store Connect API
  variables are loaded and that match can read `a8c-fastlane-match`.
- If the Release build succeeds but upload fails, rerun `release_build`; the
  workflow rebuilds and then uploads. If you need to preserve the existing
  IPA, run the upload lane locally with `ipa_path:` pointing at the artifact.
- If TestFlight rejects a duplicate build number, run `new_beta_release` for a
  beta or the appropriate finalize lane for a final build so Fastlane bumps
  `VERSION_LONG`.
- If App Store metadata is stale, note that there is currently no automated
  translation download (see
  [translation-reimplementation.md](./translation-reimplementation.md)); edit the
  localized metadata under `fastlane/metadata/` directly, then run
  `update_metadata_on_app_store_connect`.
- If Bitdrift upload fails in CI, treat the build as incomplete unless the
  release manager explicitly decides to proceed with the dSYMs attached to the
  GitHub release archive.
