# Security Scanning

## Swift Semgrep Rules

Run the akabe1 Swift/iOS Semgrep rules with:

```bash
make semgrep_swift_security
```

Run Pocket Casts-specific guardrail rules with:

```bash
make semgrep_pocket_casts
```

The target runs the vendored Swift rules in
`semgrep/swift-security.yml`, copied from the upstream `ios/swift`
directory in `https://github.com/akabe1/akabe1-semgrep-rules` at
commit `db843f16c4a740c22d97c489d176ff663c1776b6`.
No dependency-specific filtering is applied; this keeps coverage for crypto,
injection, keychain, pinning, SQL, WebView, XXE, biometric-auth, and
critical-device-feature rules even when only a subset currently reports
findings.

Semgrep findings fail the build by default. To run a report-only scan while
investigating a local finding:

```bash
SEMGREP_SWIFT_ERROR=0 make semgrep_swift_security
```

The custom Pocket Casts rules flag hardcoded subscription billing state,
direct End of Year story advancement from SwiftUI `onAppear`, and
Chromecast reuse of existing persisted `PlayerAction` integer values.
Use `SEMGREP_POCKET_CASTS_ERROR=0 make semgrep_pocket_casts` for a
report-only local scan.

Run Semgrep rule tests with:

```bash
make semgrep_tests
```

To write JSON locally:

```bash
semgrep scan --config semgrep/swift-security.yml --include "*.swift" --metrics off --timeout 0 --disable-version-check --json-output semgrep.json
```

To write SARIF locally:

```bash
semgrep scan --config semgrep/swift-security.yml --include "*.swift" --metrics off --timeout 0 --disable-version-check --sarif-output semgrep.sarif
```

The GitHub Actions workflow in `.github/workflows/semgrep.yml` runs the
same local config for Swift changes and uploads SARIF results to GitHub
code scanning when token permissions allow it. The workflow fails on findings
so local and CI behavior stay aligned.

The upstream rule repository declares GPL terms in its README. The
rule YAML is copied into this repository so local and CI scans do not
fetch or clone external rule sources.
