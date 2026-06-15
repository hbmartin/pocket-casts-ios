#!/usr/bin/env bash
# Strict-concurrency warning ratchet for xcodebuild logs.
#
# The Modules package opts into StrictConcurrency (Swift 5 language mode) and the app target
# builds with SWIFT_STRICT_CONCURRENCY=targeted (config/PocketCasts.base.xcconfig), so these
# diagnostics are warnings and would otherwise regress silently. Any first-party concurrency
# warning that is not listed in the baseline (scripts/ci/concurrency-baseline.txt) fails the
# check. The baseline is deletion-only: entries are removed as warnings are fixed, never added.
# See MODERNIZATION.md.
#
# Warnings are normalized to "<repo-relative-path>: warning: <message>" with line:column
# stripped so the baseline survives unrelated edits. The tradeoff: a second instance of an
# identical message in an already-baselined file passes silently. Files outside the repo
# (SPM checkouts, SDK headers) are not gated.
#
# Incremental builds only re-emit warnings for recompiled files, which is sufficient for
# regression detection: introducing a warning requires changing a file, and changed files are
# recompiled. It also means baseline entries can be absent from a log without having been
# fixed, so missing entries are reported as info instead of failing. Regenerate the baseline
# from a clean build with `mise run concurrency:baseline`.
#
# Coverage differs by caller: `mise run check:concurrency` builds the app target only, while CI
# runs this script on the test log (app + test + module targets). So some baseline entries
# (test targets, Modules/Sources files not recompiled by an app-only build) only surface in CI
# and are reported as info locally — that is expected, not a stale baseline.
#
# Usage: check-concurrency-warnings.sh [--print-normalized] [--show-resolved] <xcodebuild-log-file> [baseline-file]
#   --print-normalized  print the normalized warnings from the log and exit (baseline generation)
#   --show-resolved     list every baseline entry absent from the log (default: a one-line count)

set -euo pipefail

# Stable sort order so baselines generated locally compare correctly in CI.
export LC_ALL=C

print_normalized=0
show_resolved=0
while [[ "${1:-}" == --* ]]; do
  case "$1" in
    --print-normalized) print_normalized=1 ;;
    --show-resolved) show_resolved=1 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
  shift
done

log_file="${1:?usage: check-concurrency-warnings.sh [--print-normalized] [--show-resolved] <xcodebuild-log-file> [baseline-file]}"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"
baseline_file="${2:-$script_dir/concurrency-baseline.txt}"

# Anchor the substring-prone keywords (actor, sending) to a leading word boundary so unrelated
# diagnostics like "...value 'factor' was never used" or "...resending..." are not misclassified
# as concurrency warnings. The rest are concurrency-specific enough to match unanchored, and we
# never add a *trailing* boundary (that would miss "data races" or "@preconcurrency").
# [^[:alnum:]_] is used instead of \b for portability across BSD grep (macOS CI) and GNU grep.
# Note: the filter runs on the whole log line (path included), so a file literally named e.g.
# Actor.swift would still match regardless of message. That over-gates rather than under-gates,
# which is the safe direction for a ratchet, and is far narrower than the old unanchored filter.
keyword_filter='sendable|concurrency|isolated|data race|(^|[^[:alnum:]_])(actor|sending)'

normalized="$(
  grep -E "\.swift:[0-9]+:[0-9]+: warning:" "$log_file" \
    | grep -iE "$keyword_filter" \
    | while IFS= read -r line; do
        # Keep only warnings for files inside the repo, stripping everything before the
        # repo-relative path (absolute prefix, and any log-runner prefix like "[task] ").
        case "$line" in
          (*"$repo_root"/*) printf '%s\n' "${line#*"$repo_root"/}" ;;
        esac
      done \
    | sed -E 's/:[0-9]+:[0-9]+: warning:/: warning:/' \
    | sort -u || true
)"

if (( print_normalized )); then
  if [[ -n "$normalized" ]]; then
    printf '%s\n' "$normalized"
  fi
  exit 0
fi

baseline=""
if [[ -f "$baseline_file" ]]; then
  baseline="$(sort -u "$baseline_file")"
fi

new_warnings=""
if [[ -n "$normalized" ]]; then
  new_warnings="$(comm -23 <(printf '%s\n' "$normalized") <(printf '%s\n' "$baseline"))"
fi

resolved=""
if [[ -n "$baseline" ]]; then
  resolved="$(comm -13 <(printf '%s\n' "$normalized") <(printf '%s\n' "$baseline"))"
fi

if [[ -n "$resolved" ]]; then
  if (( show_resolved )); then
    echo "Info: baseline entries not present in this log (fixed, or not recompiled in an incremental build):"
    echo "$resolved"
    echo "If verified fixed from a clean build, remove them from ${baseline_file#"$repo_root"/} to ratchet down (or run: mise run concurrency:baseline)."
  else
    resolved_count="$(printf '%s\n' "$resolved" | wc -l | tr -d ' ')"
    resolved_noun="entries"; [[ "$resolved_count" == 1 ]] && resolved_noun="entry"
    echo "Info: $resolved_count baseline $resolved_noun not present in this log (incremental builds don't recompile every file; absence does not imply fixed). Re-run with --show-resolved to list them."
  fi
fi

if [[ -n "$new_warnings" ]]; then
  echo "Strict-concurrency warnings not in the baseline:" >&2
  echo "$new_warnings" >&2
  echo "Fix the warnings (preferred). If they are pre-existing and only surfaced by toolchain" >&2
  echo "or build-graph churn, regenerate the baseline with: mise run concurrency:baseline" >&2
  exit 1
fi

echo "No strict-concurrency warnings outside the baseline."
