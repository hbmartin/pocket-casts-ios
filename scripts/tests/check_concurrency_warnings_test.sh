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
printf '%s\npodcasts/Gone.swift: warning: type Gone does not conform to the Sendable protocol\n' "$expected_normalized" > "$baseline"
out="$("$checker" "$log" "$baseline")"
assert "stale baseline entry reported as info" grep -q "podcasts/Gone.swift" <<< "$out"

# A log with no concurrency warnings passes against an empty baseline.
echo "$repo_root/podcasts/Baz.swift:1:1: warning: 'foo()' is deprecated" > "$log"
: > "$baseline"
assert "clean log passes" "$checker" "$log" "$baseline"

if (( failures > 0 )); then
  echo "$failures test(s) failed" >&2
  exit 1
fi
echo "All check-concurrency-warnings tests passed."
