#!/usr/bin/env bash
# Tests for scripts/ci/check-concurrency-warnings.sh using synthetic xcodebuild logs.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"
checker="$repo_root/scripts/ci/check-concurrency-warnings.sh"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

failures=0

assert() {
  local label="$1"
  shift
  if "$@"; then
    echo "ok: $label"
  else
    echo "FAIL: $label" >&2
    failures=$((failures + 1))
  fi
}

assert_fails() {
  local label="$1"
  shift
  if "$@"; then
    echo "FAIL: $label" >&2
    failures=$((failures + 1))
  else
    echo "ok: $label"
  fi
}

log="$tmp_dir/build.log"
baseline="$tmp_dir/baseline.txt"

cat > "$log" <<EOF
$repo_root/podcasts/Foo.swift:12:5: warning: capture of 'self' with non-Sendable type 'Foo' in a '@Sendable' closure
[test:staging] $repo_root/podcasts/Foo.swift:99:1: warning: capture of 'self' with non-Sendable type 'Foo' in a '@Sendable' closure
$repo_root/Modules/Sources/PocketCastsUtils/Bar.swift:3:9: warning: static property 'x' is not concurrency-safe because it is nonisolated global shared mutable state
$repo_root/podcasts/Baz.swift:1:1: warning: 'foo()' is deprecated
/tmp/dd/SourcePackages/checkouts/Kingfisher/Thing.swift:4:4: warning: non-Sendable type crosses actor boundary
EOF

# Normalization: strips line:col, dedupes, keeps only first-party concurrency warnings.
expected_normalized="Modules/Sources/PocketCastsUtils/Bar.swift: warning: static property 'x' is not concurrency-safe because it is nonisolated global shared mutable state
podcasts/Foo.swift: warning: capture of 'self' with non-Sendable type 'Foo' in a '@Sendable' closure"
actual_normalized="$("$checker" --print-normalized "$log")"
assert "print-normalized output" [ "$actual_normalized" = "$expected_normalized" ]

# Warnings covered by the baseline pass.
printf '%s\n' "$expected_normalized" > "$baseline"
assert "baselined warnings pass" "$checker" "$log" "$baseline"

# A warning missing from the baseline fails.
echo "podcasts/Foo.swift: warning: capture of 'self' with non-Sendable type 'Foo' in a '@Sendable' closure" > "$baseline"
assert_fails "new warning fails" "$checker" "$log" "$baseline" 2>/dev/null

# Baseline entries absent from the log are info only, not failures.
# --show-resolved lists each absent entry (the default prints only a count; see output-mode tests below).
printf '%s\npodcasts/Gone.swift: warning: type Gone does not conform to the Sendable protocol\n' "$expected_normalized" > "$baseline"
out="$("$checker" --show-resolved "$log" "$baseline")"
assert "stale baseline entry reported as info" grep -q "podcasts/Gone.swift" <<< "$out"

# A log with no concurrency warnings passes against an empty baseline.
echo "$repo_root/podcasts/Baz.swift:1:1: warning: 'foo()' is deprecated" > "$log"
: > "$baseline"
assert "clean log passes" "$checker" "$log" "$baseline"

# Substring and path false positives: unrelated warnings whose words merely *contain* a keyword
# (factor/reactor/refactor -> "actor", resending -> "sending") or whose file paths contain
# concurrency terms must NOT be classified as concurrency warnings.
substr_log="$tmp_dir/substr.log"
cat > "$substr_log" <<EOF
$repo_root/podcasts/A.swift:1:1: warning: initialization of immutable value 'factor' was never used
$repo_root/podcasts/B.swift:2:2: warning: variable 'reactor' was never mutated; consider changing to 'let'
$repo_root/podcasts/C.swift:3:3: warning: stored property 'refactorCount' is never used
$repo_root/podcasts/D.swift:4:4: warning: initialization of immutable value 'resending' was never used
$repo_root/podcasts/E.swift:5:5: warning: 'RedactorView' is deprecated
$repo_root/podcasts/MainActor.swift:6:6: warning: 'foo()' is deprecated
$repo_root/podcasts/SendableHelper.swift:7:7: warning: 'bar()' is deprecated
EOF
substr_out="$("$checker" --print-normalized "$substr_log")"
assert "substring and path false positives excluded" [ -z "$substr_out" ]

# Canonical Swift concurrency phrasings must all still be classified (guards the regex against
# narrowing too far): actor-isolated, non-Sendable/@Sendable, nonisolated global shared mutable
# state (via concurrency-safe), @preconcurrency 'Sendable'-related, sending value / data races.
canon_log="$tmp_dir/canon.log"
cat > "$canon_log" <<EOF
$repo_root/podcasts/P1.swift:1:1: warning: call to main actor-isolated instance method 'foo()' in a synchronous nonisolated context
$repo_root/podcasts/P2.swift:2:2: warning: capture of 'self' with non-Sendable type 'X' in a '@Sendable' closure
$repo_root/podcasts/P3.swift:3:3: warning: static property 'x' is not concurrency-safe because it is nonisolated global shared mutable state
$repo_root/podcasts/P4.swift:4:4: warning: add '@preconcurrency' to suppress 'Sendable'-related warnings from module 'PocketCastsServer'
$repo_root/podcasts/P5.swift:5:5: warning: sending value of non-Sendable type 'Y' risks causing data races; this is an error in the Swift 6 language mode
EOF
canon_count="$("$checker" --print-normalized "$canon_log" | grep -c 'warning:')"
assert "canonical concurrency phrasings all included" [ "$canon_count" = 5 ]

# Output modes for absent baseline entries: default prints a one-line count (no per-entry path),
# --show-resolved prints the full list.
modes_log="$tmp_dir/modes.log"
echo "$repo_root/podcasts/Present.swift:1:1: warning: capture of 'self' with non-Sendable type 'P' in a '@Sendable' closure" > "$modes_log"
modes_baseline="$tmp_dir/modes_baseline.txt"
printf '%s\n%s\n' \
  "podcasts/Present.swift: warning: capture of 'self' with non-Sendable type 'P' in a '@Sendable' closure" \
  "podcasts/Absent.swift: warning: type 'Q' does not conform to the 'Sendable' protocol" > "$modes_baseline"
default_out="$("$checker" "$modes_log" "$modes_baseline")"
assert "default resolved output is a count summary" grep -q "1 baseline entry not present" <<< "$default_out"
assert_fails "default resolved output omits per-entry path" grep -q "podcasts/Absent.swift" <<< "$default_out"
show_out="$("$checker" --show-resolved "$modes_log" "$modes_baseline")"
assert "show-resolved lists the absent entry" grep -q "podcasts/Absent.swift" <<< "$show_out"

if (( failures > 0 )); then
  echo "$failures test(s) failed" >&2
  exit 1
fi
echo "All check-concurrency-warnings tests passed."
