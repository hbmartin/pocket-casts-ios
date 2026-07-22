#!/usr/bin/env bash
# Per-file count ratchets for code patterns that should only ever decrease.
#
# Ratchets:
#   unchecked-sendable  '@unchecked Sendable' conformances. Each one is an
#                       unverified thread-safety claim left over from the
#                       strict-concurrency migration; convert to a real
#                       Sendable, an actor, or @MainActor isolation.
#   force-cast          'as!' force casts outside test code. Each one is a
#                       potential type-mismatch crash; prefer 'as?' + guard.
#
# Counts are per tracked Swift file (git ls-files) and compared against the
# committed baselines (scripts/ci/ratchet-<name>.txt). A file whose count
# exceeds its baseline — or a new file introducing the pattern — fails the
# check. Baselines are deletion-only: regenerate to lock in improvements,
# never to admit new usage. Same philosophy as concurrency-baseline.txt
# (see MODERNIZATION.md).
#
# Usage: check-count-ratchets.sh [--update-baselines | --print-counts <name>]
#   (no args)             check all ratchets against their baselines
#   --print-counts <name> print current per-file counts for one ratchet
#   --update-baselines    rewrite the baseline files from current counts
#
# Env (used by the script tests): RATCHET_REPO_ROOT, RATCHET_BASELINE_DIR
set -euo pipefail

# Stable sort order so baselines generated locally compare correctly in CI.
export LC_ALL=C

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="${RATCHET_REPO_ROOT:-$(cd "$script_dir/../.." && pwd)}"
baseline_dir="${RATCHET_BASELINE_DIR:-$script_dir}"

RATCHET_NAMES=(unchecked-sendable force-cast)

describe() {
  case "$1" in
    unchecked-sendable) echo "'@unchecked Sendable' conformances" ;;
    force-cast) echo "'as!' force casts (excluding tests)" ;;
  esac
}

# NUL-separated list of tracked Swift files in scope for a ratchet.
# Semgrep rule fixtures and BuildTools are never first-party app code; the
# force-cast ratchet also skips test code, where force casts are idiomatic.
list_files() {
  local name="$1"
  git -C "$repo_root" ls-files -z -- '*.swift' | while IFS= read -r -d '' f; do
    case "$f" in
      semgrep/*|BuildTools/*) continue ;;
    esac
    if [[ "$name" == force-cast ]]; then
      case "$f" in
        *Tests/*|*Test.swift|*Tests.swift|*"Screenshot Automation"/*) continue ;;
      esac
    fi
    printf '%s\0' "$f"
  done
}

# Emit "path: count" lines, sorted, for every in-scope file containing the
# pattern. grep -o prints one line per occurrence; -w anchors 'as!' to a word
# boundary so e.g. "has!" does not match ('!' is a non-word char, so only the
# leading boundary is load-bearing).
current_counts() {
  local name="$1"
  local grep_flags=(-o -H -F)
  local pattern
  case "$name" in
    unchecked-sendable)
      # Count Swift tokens outside comments and string literals. A raw grep also
      # counted the required justification comment beside every conformance,
      # allowing comment edits to mask a newly added declaration.
      while IFS= read -r -d '' f; do
        count="$({
          awk '
            BEGIN { in_block = 0; in_string = 0 }
            {
              code = ""
              escaped = 0
              for (i = 1; i <= length($0); i++) {
                c = substr($0, i, 1)
                n = substr($0, i + 1, 1)
                if (in_block) {
                  if (c == "*" && n == "/") { in_block = 0; i++ }
                  continue
                }
                if (in_string) {
                  if (escaped) { escaped = 0; continue }
                  if (c == "\\") { escaped = 1; continue }
                  if (c == "\"") { in_string = 0 }
                  continue
                }
                if (c == "/" && n == "/") { break }
                if (c == "/" && n == "*") { in_block = 1; i++; continue }
                if (c == "\"") { in_string = 1; continue }
                code = code c
              }
              rest = code
              while (match(rest, /@unchecked[ \t]+Sendable/)) {
                count++
                rest = substr(rest, RSTART + RLENGTH)
              }
            }
            END { print count + 0 }
          ' "$repo_root/$f"
        } 2>/dev/null)"
        if (( count > 0 )); then
          printf '%s: %d\n' "$f" "$count"
        fi
      done < <(list_files "$name") | sort
      return
      ;;
    force-cast) pattern='as!'; grep_flags+=(-w) ;;
    *) echo "unknown ratchet: $name" >&2; return 2 ;;
  esac
  (
    cd "$repo_root"
    list_files "$name" | xargs -0 grep "${grep_flags[@]}" -e "$pattern" -- 2>/dev/null || true
  ) | awk -F: '{ counts[$1]++ } END { for (f in counts) printf "%s: %d\n", f, counts[f] }' | sort
}

baseline_header() {
  local name="$1"
  cat <<EOF
# Per-file baseline for the '$name' count ratchet: $(describe "$name").
# Enforced by scripts/ci/check-count-ratchets.sh (mise run check:ratchets).
# Deletion-only: counts may only go down. Regenerate after removing usages
# with: mise run ratchets:baseline
EOF
}

if [[ "${1:-}" == "--print-counts" ]]; then
  current_counts "${2:?--print-counts requires a ratchet name}"
  exit 0
fi

if [[ "${1:-}" == "--update-baselines" ]]; then
  for name in "${RATCHET_NAMES[@]}"; do
    baseline_file="$baseline_dir/ratchet-$name.txt"
    { baseline_header "$name"; current_counts "$name"; } > "$baseline_file"
    entries="$(grep -cEv '^[[:space:]]*(#|$)' "$baseline_file" || true)"
    echo "Wrote $entries entries to ${baseline_file#"$repo_root"/}"
  done
  exit 0
fi

failures=0
for name in "${RATCHET_NAMES[@]}"; do
  baseline_file="$baseline_dir/ratchet-$name.txt"
  if [[ ! -f "$baseline_file" ]]; then
    echo "Baseline file not found: $baseline_file (run: mise run ratchets:baseline)" >&2
    failures=$((failures + 1))
    continue
  fi

  counts="$(current_counts "$name")"

  violations="$(awk -F': ' '
    NR == FNR { if ($0 !~ /^[[:space:]]*(#|$)/) base[$1] = $2 + 0; next }
    {
      if (!($1 in base)) printf "  %s: %d (not in baseline)\n", $1, $2 + 0
      else if ($2 + 0 > base[$1]) printf "  %s: %d (baseline %d)\n", $1, $2 + 0, base[$1]
    }' "$baseline_file" <(printf '%s\n' "$counts"))"

  improved="$(awk -F': ' '
    NR == FNR { if ($0 !~ /^[[:space:]]*(#|$)/) cur[$1] = $2 + 0; next }
    $0 ~ /^[[:space:]]*(#|$)/ { next }
    { if (!($1 in cur) || cur[$1] < $2 + 0) n++ }
    END { if (n) print n }' <(printf '%s\n' "$counts") "$baseline_file")"

  if [[ -n "$improved" ]]; then
    improved_noun="files"; [[ "$improved" == 1 ]] && improved_noun="file"
    echo "Info [$name]: $improved baseline $improved_noun improved (count went down or reached zero). Lock it in with: mise run ratchets:baseline"
  fi

  if [[ -n "$violations" ]]; then
    echo "New $(describe "$name") above the baseline:" >&2
    echo "$violations" >&2
    failures=$((failures + 1))
  else
    echo "OK [$name]: no new $(describe "$name")."
  fi
done

if (( failures > 0 )); then
  echo "Remove the new usages (preferred). If a file was moved or renamed, or an" >&2
  echo "exception was explicitly agreed in review, regenerate the baselines with:" >&2
  echo "  mise run ratchets:baseline" >&2
  echo "and call out the diff in your PR." >&2
  exit 1
fi
