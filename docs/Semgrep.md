# Semgrep

This repo uses Semgrep for local and CI static analysis. The rules catch
security issues, correctness regressions, and project-specific patterns that
are easier to prevent automatically than to rediscover in review.

## Setup

Install the Semgrep CLI on your machine and make sure it is available on
`PATH`:

```bash
brew install semgrep
semgrep --version
```

If you do not use Homebrew, install Semgrep with your preferred Python tooling
and verify the same `semgrep --version` command works before running the make
targets.

The repo does not install Semgrep through `make install_dependencies`.

## Rule Files

The local configs live in `semgrep/`:

- `semgrep/swift-security.yml` contains the vendored Swift/iOS security rules
  plus local guardrails for security, correctness, dependency, localization,
  Makefile, and Semgrep-rule mistakes.
- `semgrep/pocket-casts.yml` contains Pocket Casts-specific Swift rules for
  app behavior that should stay consistent across future changes.
- `semgrep/tests/` contains Semgrep fixture files used by `semgrep test`.

The vendored rules in `semgrep/swift-security.yml` came from the upstream
`akabe1/akabe1-semgrep-rules` iOS Swift rules at the commit documented at the
top of that file. Keeping a local copy makes local and CI scans deterministic
and avoids network access during scans.

## Local Usage

Run the Semgrep rule tests first when changing rules:

```bash
make semgrep_tests
```

Run the Swift/iOS security and local guardrail rules:

```bash
make semgrep_swift_security
```

Run the custom Pocket Casts rules:

```bash
make semgrep_pocket_casts
```

Run Semgrep as part of the full local static-check suite:

```bash
make static_checks
```

The scan targets fail on findings by default. To inspect findings locally
without failing the command, run the relevant target in report-only mode:

```bash
SEMGREP_SWIFT_ERROR=0 make semgrep_swift_security
SEMGREP_POCKET_CASTS_ERROR=0 make semgrep_pocket_casts
```

## Direct Semgrep Commands

Use the make targets for normal development because they match the repo's
include and exclude patterns. If you need an artifact for debugging or upload,
run Semgrep directly from the repo root:

```bash
semgrep scan --config semgrep/swift-security.yml --include "*.swift" --metrics off --timeout 0 --disable-version-check --json-output semgrep.json
```

```bash
semgrep scan --config semgrep/swift-security.yml --include "*.swift" --metrics off --timeout 0 --disable-version-check --sarif-output semgrep.sarif
```

## Adding Or Updating Rules

Add or update rules when PR feedback, bug fixes, implementation surprises, or
security review findings reveal a pattern that can be checked automatically.
Project guardrails usually belong in `semgrep/swift-security.yml`; narrowly
app-specific Swift behavior belongs in `semgrep/pocket-casts.yml`.

When adding a rule:

1. Give it a stable `id`, clear `message`, useful `severity`, and the narrowest
   practical `languages` and `paths`.
2. Add fixture coverage under `semgrep/tests/`.
3. Mark expected findings with `// ruleid: your.rule.id`.
4. Mark intentional non-findings with `// ok: your.rule.id`.
5. Add the fixture to the `semgrep_tests` target in `Makefile` if it is a new
   file.
6. Run `make semgrep_tests` and the scan target for the config you changed.

Prefer precise rules with tests over broad regexes that create noisy findings.
If a rule must use `languages: [generic]`, constrain it with `paths.include`
whenever possible.

## CI

`.github/workflows/semgrep.yml` runs Semgrep for Swift and Semgrep-rule changes
on pull requests, pushes to `trunk`, and manual workflow dispatches. CI scans
both local configs with `--error` and writes `semgrep-swift.sarif`. When GitHub
token permissions allow it, the workflow uploads SARIF to GitHub code scanning.

Keep local rule tests passing before opening a PR so CI behavior matches what
you saw locally.
