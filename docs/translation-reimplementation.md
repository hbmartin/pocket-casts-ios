# Translation Sync Re-implementation

> **Status:** The previous WordPress-hosted GlotPress translation pipeline has been
> **removed**. The release/localization fastlane lanes that depended on it now fail
> loudly (see `glotpress_translation_sync_disabled!` in
> [`fastlane/lib/helpers.rb`](../fastlane/lib/helpers.rb)). This document describes
> the state that was removed and what a replacement needs to do, so that translation
> sync can be re-implemented later.

## Background — what was removed

Historically, translation flowed through a WordPress-backed
[GlotPress](https://translate.wordpress.com/) instance hosted by Automattic:

- **Upload (source → GlotPress):** During the release process, the English source
  strings in [`podcasts/en.lproj/Localizable.strings`](../podcasts/en.lproj/Localizable.strings)
  and the App Store metadata (`fastlane/AppStoreStrings.po`) were pushed to GlotPress
  for translators to work on.
- **Download (GlotPress → app):** Before a release build was finalized, the localized
  `.strings` files for every supported locale and the localized App Store Connect
  metadata were pulled back down from GlotPress and committed into the repo.
- **Progress checks:** A lane reported the translation completion percentage of the
  "Mag16" locales across the app-strings and metadata projects.

That GlotPress project no longer exists. As part of removing it:

- The Zendesk support SDK and its credentials (`zendeskAPIKey`, `zendeskUrl`,
  `zendeskNewUrl`, `dotcomSecret`) were removed from the credentials template and
  secrets pipeline. (Zendesk and the WordPress.com "dotcom" secret were tied to the
  same Automattic integration that hosted GlotPress.)
- A Semgrep guard rule,
  [`pocketcasts.no-zendesk-or-wordpress-integration`](../semgrep/swift-security.yml),
  now fails CI if any of those credentials, a `import Zendesk*`, or a
  `translate.wordpress.com` / `wordpress-mobile` URL is reintroduced. When you wire up
  a replacement, **update or scope that rule** rather than deleting it, so the old
  WordPress/Zendesk endpoints stay forbidden while the new source is allowed.

## Current state

- `podcasts/en.lproj/Localizable.strings` remains the **single source of truth** for
  app strings. SwiftGen still generates the `L10n` enum from it on every build
  ([`docs/localization.md`](./localization.md)).
- The 16 existing `*.lproj` locale directories still contain the **last translations
  pulled from GlotPress**. These are frozen — nothing updates them until a replacement
  source is wired up.
- The following fastlane lanes are intentionally inert and raise
  `glotpress_translation_sync_disabled!` when invoked:
  - `download_localized_strings_from_glotpress`
  - `download_localized_app_store_metadata_from_glotpress`
  - `download_localized_strings_and_metadata_from_glotpress` (calls the two above)
  - `check_all_translations_progress`
- The upload-side lane `update_app_store_strings` still builds `AppStoreStrings.po`
  via `gp_update_metadata_source`; this also assumes a GlotPress backend and will need
  to be re-pointed (or replaced) by any new pipeline.

## What a replacement must provide

A re-implementation needs to restore four capabilities:

1. **Push source strings** — upload `en.lproj/Localizable.strings` (and App Store
   metadata source `.txt` files) to the translation platform.
2. **Pull translations** — download per-locale `.strings` and localized App Store
   metadata, writing them back into the `*.lproj` directories and
   `fastlane/metadata/`.
3. **Report progress** — expose per-locale completion so release managers can gate a
   release on translation readiness (restores `check_all_translations_progress`).
4. **Preserve the existing string contract** (see Constraints below), so the SwiftGen
   `L10n` codegen and the app keep working unchanged.

## Candidate approaches

| Option | Notes |
|--------|-------|
| **Self-hosted / alternative GlotPress** | Lowest-churn: the existing `.po`/`.strings` flow and fastlane GlotPress helpers (from the release toolkit) mostly still apply; only the host URL and credentials change. Requires hosting and operating the instance. |
| **Crowdin / Lokalise / Transifex (SaaS)** | First-class `.strings` + `.xcstrings` support, CLIs and fastlane plugins, built-in progress APIs. Lowest operational burden; adds a vendor dependency and per-seat cost. |
| **Apple String Catalogs (`.xcstrings`)** | Native Xcode tooling, but only solves the *file format* — you still need a service/process to get strings translated and a way to gate releases on completeness. Could be combined with any of the above. |

Pick based on who owns translation operations after the WordPress/Automattic split. If
translation is moving in-house, the SaaS options give the fastest path back to a
working pipeline.

## Integration points to touch

- **Credentials:** add the new platform's API token to the secrets pipeline. Follow
  the existing pattern — add a `%{...}` placeholder to
  [`podcasts/Credentials/ApiCredentials.tpl`](../podcasts/Credentials/ApiCredentials.tpl),
  wire it through `replace_secrets.rb`, and extend
  [`scripts/tests/generate_credentials_test.rb`](../scripts/tests/generate_credentials_test.rb).
  **Do not** reuse the old `zendesk_*` / `dotcom_secret` key names — the Semgrep guard
  will reject them.
- **Fastlane:** replace the bodies of the four disabled lanes (currently calling
  `glotpress_translation_sync_disabled!`) with real upload/download/progress logic,
  and re-point `update_app_store_strings` / `gp_update_metadata_source` at the new
  source.
- **Semgrep:** narrow `pocketcasts.no-zendesk-or-wordpress-integration` so it still
  blocks the old endpoints but permits the new platform's host/credentials.
- **Docs:** update [`docs/localization.md`](./localization.md) (the upload/download
  description in its intro currently points at GlotPress) and
  [`docs/ReleaseProcess.md`](./ReleaseProcess.md) once the pipeline is live.

## Constraints to preserve

These existing rules from [`docs/localization.md`](./localization.md) must continue to
hold regardless of the chosen platform, because the app and codegen depend on them:

- **Snake_case keys** following `feature_relevantIdentifier_description`. The old
  GlotPress truncated keys over 255 characters; verify the replacement's limit and keep
  keys short.
- **Positional specifiers** (`%1$@`, `%2$@`) only — never Swift string interpolation in
  localized values.
- **Manual pluralization** via separate `_singular` / `_plural` keys. GlotPress did not
  support `.stringsdict`; if the replacement does, that's an opportunity to migrate, but
  it is not required for parity.
- **Comments on every string**, describing context and each placeholder, so translators
  have enough information.

## Suggested re-implementation order

1. Choose the platform and seed it with the current `en.lproj` source + the frozen
   translations already in the repo (so existing work isn't lost).
2. Add credentials + the new download lane; verify a round-trip on one locale.
3. Re-enable upload (`update_app_store_strings` / source-string push).
4. Restore `check_all_translations_progress` and re-gate the release process on it.
5. Update Semgrep and the docs above; remove the `glotpress_translation_sync_disabled!`
   helper once all four lanes are live.
