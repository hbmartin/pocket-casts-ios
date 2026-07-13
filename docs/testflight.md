# Personal TestFlight Distribution

This guide covers shipping this fork to **your own** TestFlight, under **your
own** Apple Developer team, using the `TestFlight Personal` GitHub Actions
workflow (`.github/workflows/testflight-personal.yml`) and the
`personal_testflight` Fastlane lane.

It exists because the official release pipeline
(`.github/workflows/release-fastlane.yml`, see
[ReleaseProcess.md](./ReleaseProcess.md)) cannot be used by a fork owner: it is
hard-wired to Automattic's Apple team (`PZYM8XX95Q`), Automattic's bundle
identifier (`au.com.shiftyjelly.podcasts`), Automattic's encrypted `configure`
secrets, and Automattic's private Fastlane match bucket on S3. None of that is
available to a fork, and Apple will not let another team sign or upload
Automattic's bundle identifiers.

The personal pipeline instead uses **Xcode automatic signing with App Store
Connect API cloud signing**. There is no match storage, no certificate export,
and no `configure` decryption: the only Apple credential you manage is one App
Store Connect API key.

## Checklist: Every Step, In Order

Each step is detailed in the sections that follow.

1. [ ] Enroll in the **Apple Developer Program** (start immediately — approval
       can take up to 48 hours).
2. [ ] Choose a **bundle identifier root** and an **App Group identifier**
       (One-Time Apple Setup, step 1).
3. [ ] Note your **Team ID** from the Membership page (step 2).
4. [ ] Register the **root App ID** in the Developer Portal (step 3).
5. [ ] Create the **app record** in App Store Connect with a unique name
       (step 4).
6. [ ] Create an **App Store Connect API key** with the **Admin** role; save
       the `.p8` file, Key ID, and Issuer ID (step 5).
7. [ ] In GitHub → Settings → Secrets and variables → Actions, add the three
       **variables** (`PERSONAL_APPLE_TEAM_ID`, `PERSONAL_BUNDLE_ID_ROOT`,
       `PERSONAL_APP_GROUP_ID`) and the three **secrets**
       (`APP_STORE_CONNECT_API_KEY_KEY_ID`,
       `APP_STORE_CONNECT_API_KEY_ISSUER_ID`,
       `APP_STORE_CONNECT_API_KEY_KEY`).
8. [ ] Make sure the **self-hosted macOS runner** is online
       ([GitHubActionsLocalRunner.md](./GitHubActionsLocalRunner.md)).
9. [ ] GitHub → **Actions** → **TestFlight Personal** → **Run workflow**.
10. [ ] In App Store Connect → TestFlight, wait for the build to process,
        create an **internal tester group** with automatic distribution, and
        add yourself as a tester.
11. [ ] Install **TestFlight** on your iPhone, sign in with the same Apple ID,
        and install the build.

## How It Works

The `personal_testflight` lane builds the `pocketcasts` scheme (Release
configuration) and overrides these build settings on the `xcodebuild` command
line:

| Build setting | Source | Effect |
| --- | --- | --- |
| `DEVELOPMENT_TEAM` | `PERSONAL_APPLE_TEAM_ID` | Signs with your team instead of `PZYM8XX95Q`. |
| `PRODUCT_BUNDLE_IDENTIFIER_ROOT` | `PERSONAL_BUNDLE_ID_ROOT` | Rebrands the app and every extension. Extensions derive their identifiers from the root (`<root>.WidgetExtension`, etc.). |
| `APP_GROUP_IDENTIFIER` | `PERSONAL_APP_GROUP_ID` | Rebrands the App Group in every entitlements file **and** at runtime. Each target's Info.plist exposes it as `PCAppGroupIdentifier`, which `SharedConstants.GroupUserDefaults.groupContainerId` reads. |
| `CODE_SIGN_STYLE=Automatic`, empty `PROVISIONING_PROFILE_SPECIFIER` | fixed | Disables the `match AppStore …` manual signing from `config/PocketCasts.release.xcconfig`. |
| `VERSION_LONG` | optional `PERSONAL_BUILD_NUMBER` / workflow input | Per-run build number override without committing to `config/Version.xcconfig`. |

`xcodebuild` runs with `-allowProvisioningUpdates` plus your App Store Connect
API key (`-authenticationKeyPath/-authenticationKeyID/-authenticationKeyIssuerID`),
so on the first run it registers the bundle identifiers and the App Group in
your Developer Portal, syncs capabilities from the entitlements files, and
creates the certificates and provisioning profiles it needs. The exported IPA
is then uploaded to TestFlight with the same API key.

Because your builds use a different bundle identifier and App Group than the
App Store app, they install side by side with it and share no data.

## Prerequisites

1. **Apple Developer Program membership** (the paid one, USD 99/year).
   Enroll at <https://developer.apple.com/programs/enroll/>. Approval is
   usually fast for individuals but can take up to 48 hours — if you are not
   enrolled yet, start this first. A free account cannot upload to TestFlight.
2. **The self-hosted macOS runner** this fork already uses for CI, set up per
   [GitHubActionsLocalRunner.md](./GitHubActionsLocalRunner.md). The workflow
   runs on `[self-hosted, macOS, ARM64]` and needs a Swift 6 capable Xcode
   (`scripts/ci/select-xcode.sh` picks one automatically).
3. Network access from the runner to `appstoreconnect.apple.com` and
   `developer.apple.com`.

## One-Time Apple Setup

### 1. Choose your identifiers

Pick these once and don't change them (changing them later orphans the app
record and testers):

- **Bundle identifier root** — reverse-DNS for a domain you control, e.g.
  `ai.sparkedinnovations.pocketcasts`. It must **not** start with
  `au.com.shiftyjelly.podcasts`; the lane rejects that. The four extension
  identifiers are derived automatically:
  `<root>.NotificationContent`, `<root>.NotificationExtension`,
  `<root>.Share-Extension`, `<root>.WidgetExtension`.
- **App Group identifier** — must start with `group.` and be globally unique
  across all Apple developer teams, e.g.
  `group.ai.sparkedinnovations.pocketcasts`. You cannot reuse
  `group.au.com.shiftyjelly.pocketcasts`; it belongs to Automattic's team.

### 2. Find your Team ID

<https://developer.apple.com/account> → **Membership details** → **Team ID**
(a 10-character string like `A1B2C3D4E5`).

### 3. Register the root App ID

<https://developer.apple.com/account/resources/identifiers/list> → **+** →
**App IDs** → **App** → *explicit* bundle ID = your root identifier.

You only need to register the **root** identifier manually — it must exist
before you can create the App Store Connect app record in the next step. The
extension identifiers, the App Group, capability assignments, certificates,
and provisioning profiles are all created automatically by the first workflow
run via `-allowProvisioningUpdates`.

For reference (and for manual repair if automatic capability sync ever fails),
the capabilities each identifier needs are:

| Identifier | Capabilities |
| --- | --- |
| `<root>` (main app) | App Groups, Associated Domains, Push Notifications, Sign In with Apple, SiriKit, Access Wi-Fi Information |
| `<root>.WidgetExtension` | App Groups |
| `<root>.Share-Extension` | App Groups |
| `<root>.NotificationContent`, `<root>.NotificationExtension` | none |

### 4. Create the app record in App Store Connect

<https://appstoreconnect.apple.com> → **Apps** → **+** → **New App**:

- **Platform**: iOS.
- **Name**: must be unique across the entire App Store, so "Pocket Casts" is
  taken — use something like "Pocket Casts (Harold)". This is only what
  TestFlight displays; the home-screen name comes from the bundle.
- **Bundle ID**: the root App ID you registered in step 3.
- **SKU**: any unique string, e.g. `pocketcasts-fork`.
- **Access**: Full Access.

The app record **must exist before the first upload**, or the upload step
fails with "Could not find an app with bundle identifier …".

### 5. Create an App Store Connect API key

<https://appstoreconnect.apple.com/access/integrations/api> (**Users and
Access** → **Integrations** → **App Store Connect API** → **Team Keys**) →
**+**:

- **Role**: **Admin**. Cloud signing creates certificates on your behalf, and
  certificate management requires Admin. A Developer/App Manager key can
  upload builds but the signing step will fail with a permissions error.
- Note the **Issuer ID** (top of the page) and the key's **Key ID**.
- Download the `.p8` file — Apple lets you download it **once**. Store it
  somewhere safe (password manager).

## GitHub Configuration

In the fork's repository settings (**Settings → Secrets and variables →
Actions**), configure:

### Variables (not secret)

| Variable | Value | Example |
| --- | --- | --- |
| `PERSONAL_APPLE_TEAM_ID` | Your Team ID from Membership details | `A1B2C3D4E5` |
| `PERSONAL_BUNDLE_ID_ROOT` | Your root bundle identifier | `ai.sparkedinnovations.pocketcasts` |
| `PERSONAL_APP_GROUP_ID` | Your App Group identifier | `group.ai.sparkedinnovations.pocketcasts` |

### Secrets

| Secret | Value |
| --- | --- |
| `APP_STORE_CONNECT_API_KEY_KEY_ID` | The API key's Key ID |
| `APP_STORE_CONNECT_API_KEY_ISSUER_ID` | The Issuer ID |
| `APP_STORE_CONNECT_API_KEY_KEY` | The **full contents** of the `.p8` file, including the `-----BEGIN PRIVATE KEY-----` / `-----END PRIVATE KEY-----` lines. Multi-line paste is fine; a single line with literal `\n` sequences also works. |

Optional secrets (leave unset for a normal personal build):

| Secret | Effect when set |
| --- | --- |
| `POCKET_CASTS_CREDENTIALS_JSON` | Real service credentials (sharing server, TelemetryDeck, Instagram, …) instead of generated placeholders. Same JSON shape enforced by `scripts/ci/prepare-credentials.sh`. |
| `BITDRIFT_API_KEY` | Uploads Release dSYMs to Bitdrift. When unset, the workflow sets `POCKET_CASTS_SKIP_BITDRIFT_UPLOAD=1` and the build phase skips the upload instead of failing. |

These names deliberately don't overlap with the release pipeline's
`POCKET_CASTS_RELEASE_GITHUB_TOKEN`; the personal workflow needs no GitHub
token beyond the default read-only one.

## Shipping a Build

1. GitHub → **Actions** → **TestFlight Personal** → **Run workflow**.
2. Inputs:
   - **build_number** (optional): overrides `VERSION_LONG` for this build
     only, e.g. `8.13.0.90`. When empty, the committed value in
     `config/Version.xcconfig` is used. Every upload for the same marketing
     version must have a strictly higher/unique build number — TestFlight
     rejects duplicates.
   - **skip_upload** (optional): build and export the IPA without uploading.
     Useful as a signing dry run before the app record is ready.
3. The job checks out the branch you dispatched from, selects Xcode, installs
   the Ruby toolchain (`scripts/ci/shared-setup.sh`), prepares placeholder API
   credentials (`scripts/ci/prepare-credentials.sh`), then runs
   `bundle exec fastlane personal_testflight`.
4. Artifacts (`pocket-casts-personal.ipa`, dSYM zip) are attached to the
   workflow run for 14 days regardless of upload success.

Expect the first run to be slower: it registers six extension bundle IDs, the
App Group, capabilities, and mints certificates/profiles. Subsequent runs
reuse them.

### Installing it on your phone

1. In App Store Connect → your app → **TestFlight**, wait for the build to
   finish processing (typically 5–30 minutes after upload; you'll also get an
   email).
2. Under **Internal Testing**, create a group (e.g. "Me") with **automatic
   distribution** enabled, and add yourself as a tester. Internal testers must
   be members of your App Store Connect team (as the account holder, you
   already are). Internal builds need **no** Beta App Review.
3. Install **TestFlight** from the App Store on your iPhone, sign in with the
   same Apple ID, and install the build.

TestFlight builds expire after 90 days, so plan to dispatch the workflow at
least quarterly (or whenever you pull in upstream changes).

### Running the lane locally instead of on CI

On a Mac with Xcode and the repo set up:

```bash
export SKIP_CONFIGURE_APPLY=true
export PERSONAL_APPLE_TEAM_ID=A1B2C3D4E5
export PERSONAL_BUNDLE_ID_ROOT=ai.sparkedinnovations.pocketcasts
export PERSONAL_APP_GROUP_ID=group.ai.sparkedinnovations.pocketcasts
export APP_STORE_CONNECT_API_KEY_KEY_ID=…
export APP_STORE_CONNECT_API_KEY_ISSUER_ID=…
export APP_STORE_CONNECT_API_KEY_KEY="$(cat ~/path/to/AuthKey_XXXX.p8)"

mise run setup:credentials   # placeholder API credentials
bundle install
bundle exec fastlane personal_testflight
```

(You can also put the `PERSONAL_*` values in `~/.a8c-apps/pocket-casts-ios.env`;
see `fastlane/example.env`.)

## What Was Changed to Support This

- `config/PocketCasts.base.xcconfig` — new `APP_GROUP_IDENTIFIER` build
  setting (default: the Pocket Casts group;
  `config/PocketCasts.prototype.xcconfig` overrides it for Prototype builds).
- All `.entitlements` files reference `$(APP_GROUP_IDENTIFIER)` instead of a
  hardcoded App Group.
- Every app/extension Info.plist exposes the group as `PCAppGroupIdentifier`,
  and `SharedConstants.GroupUserDefaults.groupContainerId` (plus
  `WidgetHelper.appGroupId` / `CommonWidgetHelper.appGroupId`, which now
  delegate to it) reads it at runtime, so app ↔ extension data sharing works
  under a rebranded group.
- `fastlane/Fastfile` — `personal_testflight` lane; `before_all` skips
  `configure_apply` when `SKIP_CONFIGURE_APPLY=true`.
- `scripts/build-phases/upload-bitdrift-debug-files.sh` — honors
  `POCKET_CASTS_SKIP_BITDRIFT_UPLOAD=1` so Release builds don't require a
  Bitdrift key in CI.
- `.github/workflows/testflight-personal.yml` — the workflow.

Official Automattic builds are unaffected: every override is opt-in via the
`PERSONAL_*` environment and `SKIP_CONFIGURE_APPLY`, and the defaults resolve
to the same values as before.

## Known Limitations of a Personal Build

- **Service credentials are placeholders** unless you provide
  `POCKET_CASTS_CREDENTIALS_JSON`: encrypted log upload, the sharing server,
  TelemetryDeck analytics, and the Instagram integration are disabled. Core
  podcast browsing, playback, downloads, filters, folders, and widgets work.
- **Push notifications from the Pocket Casts servers will not arrive.** APNs
  delivery is tied to Automattic's team and push keys; your build's
  `aps-environment` belongs to your team, which their servers don't know.
  Local features (downloads, episode artwork, playback) are unaffected.
- **Universal links and password autofill won't associate.** The
  `applinks:`/`webcredentials:` associated domains point at `pocketcasts.com`,
  whose apple-app-site-association file lists only Automattic's app ID.
  `pca.st` links will open in Safari instead of the app.
- **Sign In with Apple may not work** against the Pocket Casts backend, since
  the identity token is issued for your bundle ID, not the one the server
  expects. Email/password sign-in is unaffected.
- **No data migration**: the personal build is a separate app with a separate
  App Group; it does not see the App Store app's database or downloads.
- The lane distributes to **internal testers only** (no Beta App Review, no
  external groups). Extend `upload_to_testflight` in the lane if you ever need
  external testers.

## Troubleshooting

- **"Could not find an app with bundle identifier"** during upload — the App
  Store Connect app record doesn't exist yet (One-Time Apple Setup step 4).
  The IPA from the run's artifacts can be uploaded manually after you create
  it, or just re-run the workflow.
- **"You haven't been given access to cloud-managed distribution
  certificates"** or certificate-creation errors — the API key's role is too
  low. Use an **Admin** team key (step 5).
- **"An App Group with Identifier '…' is not available"** — the group is
  registered to another team. Pick a different `PERSONAL_APP_GROUP_ID`.
- **Profile/capability mismatch ("doesn't support the App Groups
  capability")** — automatic capability sync didn't run for that identifier.
  Open the identifier on the Developer Portal and enable the capabilities
  from the table above, then re-run.
- **"The bundle version must be higher than the previously uploaded
  version"** — re-dispatch with a higher `build_number` input, or bump
  `VERSION_LONG` in `config/Version.xcconfig`.
- **"Maximum number of certificates generated"** — each CI run signs inside a
  throwaway keychain, so Xcode occasionally mints a new Apple Development
  certificate. Revoke stale "Created via API" / Xcode-managed development
  certificates at
  <https://developer.apple.com/account/resources/certificates/list>; revoking
  development certificates is harmless.
- **Build fails in the Bitdrift phase** — confirm the failure is real; the
  phase only errors when `BITDRIFT_API_KEY` is set but invalid, or when both
  the key and `POCKET_CASTS_SKIP_BITDRIFT_UPLOAD` are unset outside this
  workflow.
