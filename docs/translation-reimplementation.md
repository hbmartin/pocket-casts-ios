# Translation Sync Re-implementation

> **Status:** The previous hosted GlotPress translation pipeline has been
> **completely removed** — the fastlane lanes, their helper, the locale-code maps,
> and the `Frozen.strings` / `AppStoreStrings.po` data files are all gone. There is
> currently **no automated translation sync**. This document describes the state that
> was removed and what a replacement needs to do, so that translation sync can be
> re-implemented later.

## Background — what was removed

Historically, translation flowed through a hosted GlotPress instance:

- **Upload (source → GlotPress):** During the release process, the English source
  strings in [`podcasts/en.lproj/Localizable.strings`](../podcasts/en.lproj/Localizable.strings)
  and the App Store metadata (`fastlane/AppStoreStrings.po`) were pushed to GlotPress
  for translators to work on.
- **Download (GlotPress → app):** Before a release build was finalized, the localized
  `.strings` files for every supported locale and the localized App Store Connect
  metadata were pulled back down from GlotPress and committed into the repo.
- **Progress checks:** A lane reported the translation completion percentage of the
  "Mag16" locales across the app-strings and metadata projects.

That GlotPress project no longer exists.

## Current state

- `podcasts/en.lproj/Localizable.strings` remains the **single source of truth** for
  app strings. SwiftGen still generates the `L10n` enum from it on every build
  ([`docs/localization.md`](./localization.md)).
- The 16 existing `*.lproj` locale directories still contain the **last translations
  pulled from GlotPress**. These are frozen — nothing updates them until a replacement
  source is wired up.
- All of the GlotPress fastlane plumbing has been **deleted**, including the lanes
  `generate_strings_file_for_glotpress`, `download_localized_strings_from_glotpress`,
  `download_localized_app_store_metadata_from_glotpress`,
  `download_localized_strings_and_metadata_from_glotpress`,
  `check_all_translations_progress`, and `update_app_store_strings`; the
  `GLOTPRESS_TO_*` locale-code maps; and the `Frozen.strings` / `AppStoreStrings.po`
  data files. The `code_freeze`, `new_beta_release`, and `finalize_release` lanes no
  longer call any of them (they still run `lint_localizations` on the committed
  `.strings`).

## What a replacement must provide

A re-implementation needs to restore four capabilities:

1. **Push source strings** — upload `en.lproj/Localizable.strings` (and App Store
   metadata source `.txt` files) to the translation platform.
2. **Pull translations** — download per-locale `.strings` and localized App Store
   metadata, writing them back into the `*.lproj` directories and
   `fastlane/metadata/`.
3. **Report progress** — expose per-locale completion so release managers can gate a
   release on translation readiness (equivalent of the removed
   `check_all_translations_progress`).
4. **Preserve the existing string contract** (see Constraints below), so the SwiftGen
   `L10n` codegen and the app keep working unchanged.

## Candidate approaches

| Option | Notes |
|--------|-------|
| **Self-hosted / alternative GlotPress** | Lowest-churn conceptually: the `.po`/`.strings` flow and the fastlane GlotPress helpers from the release toolkit still exist upstream, so the deleted lanes can be re-created against a new host URL and credentials. Requires hosting and operating the instance. |
| **Crowdin / Lokalise / Transifex (SaaS)** | First-class `.strings` + `.xcstrings` support, CLIs and fastlane plugins, built-in progress APIs. Lowest operational burden; adds a vendor dependency and per-seat cost. |
| **Apple String Catalogs (`.xcstrings`)** | Native Xcode tooling, but only solves the *file format* — you still need a service/process to get strings translated and a way to gate releases on completeness. Could be combined with any of the above. |

Pick based on who owns translation operations going forward. If translation is moving
in-house, the SaaS options give the fastest path back to a working pipeline.

## Integration points to touch

- **Credentials:** add the new platform's API token to the secrets pipeline. Follow
  the existing pattern — add a `%{...}` placeholder to
  [`podcasts/Credentials/ApiCredentials.tpl`](../podcasts/Credentials/ApiCredentials.tpl),
  wire it through `replace_secrets.rb`, and extend
  [`scripts/tests/generate_credentials_test.rb`](../scripts/tests/generate_credentials_test.rb).
  Use new platform-specific key names.
- **Fastlane:** re-create the deleted upload/download/progress lanes (and a source-
  string export equivalent to the old `update_app_store_strings`) against the new
  source, and re-add their calls in `code_freeze`, `new_beta_release`, and
  `finalize_release`. Use the prior commit that removed them as a reference for the
  expected behavior.
- **Docs:** update [`docs/localization.md`](./localization.md) and
  [`docs/ReleaseProcess.md`](./ReleaseProcess.md) once the pipeline is live.

## Constraints to preserve

These existing rules from [`docs/localization.md`](./localization.md) must continue to
hold regardless of the chosen platform, because the app and codegen depend on them:

- **Snake_case keys** following `feature_relevantIdentifier_description`. GlotPress
  truncated keys over 255 characters; verify the replacement's limit and keep keys
  short.
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
2. Add credentials + a new download lane; verify a round-trip on one locale.
3. Add the source-string/metadata upload lane (the equivalent of the removed
   `update_app_store_strings` source push).
4. Add a translation-progress check and re-gate the release process on it.
5. Re-add the lane calls in `code_freeze`, `new_beta_release`, and `finalize_release`,
   then update the docs above.
