#!/usr/bin/env bash
# Fail when Swift code or Interface Builder files reference an image asset
# name that no tracked asset catalog provides.
#
# Motivation: deleting an asset catalog (or a single imageset) does not break
# the build — UIImage(named:)/Image(_:) just render nothing at runtime. The
# Discover-feature removal deleted Discovery.xcassets while 8 of its image
# names were still referenced by live code and XIBs, silently blanking
# follow/subscribe checkmarks, empty-state art, and chevrons app-wide.
#
# What counts as a reference (string literals only):
#   Swift  UIImage(named: "…"), Image("…"), Image(decorative: "…")
#   IB     <image name="…"> resource declarations without catalog="system"
# Names built at runtime (interpolation, helpers appending "_dark", …) can't
# be extracted statically; list such base names in the allowlist file
# (scripts/ci/asset-reference-allowlist.txt) with a justification comment.
#
# What counts as available: every *.imageset / *.symbolset directory under
# any tracked *.xcassets, across the app target and all SPM modules. Bundle
# ownership is not checked — a name only has to exist somewhere — so this is
# a ratchet against dangling names, not a proof of correct bundle lookup.
#
# Usage: check-asset-references.sh [--print-referenced | --print-available]
#
# Env (used by the script tests): ASSET_CHECK_REPO_ROOT, ASSET_CHECK_ALLOWLIST
set -euo pipefail

export LC_ALL=C

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="${ASSET_CHECK_REPO_ROOT:-$(cd "$script_dir/../.." && pwd)}"
allowlist_file="${ASSET_CHECK_ALLOWLIST:-$script_dir/asset-reference-allowlist.txt}"

# Names provided by tracked catalogs: basename of every imageset/symbolset.
available_names() {
  git -C "$repo_root" ls-files -- '*.xcassets/*' \
    | grep -oE '[^/]+\.(imageset|symbolset)/' \
    | sed -E 's#\.(imageset|symbolset)/$##' \
    | sort -u
}

# Emit "path<TAB>name" for every literal asset reference in tracked sources.
# Tests, semgrep fixtures, and BuildTools are out of scope: they are not
# first-party app code and may reference test-bundle-only fixtures.
referenced_names() {
  local swift_pattern='UIImage\(named:[[:space:]]*"[^"]+"|Image\((decorative:[[:space:]]*)?"[^"]+"'
  (
    cd "$repo_root"
    git ls-files -z -- '*.swift' | while IFS= read -r -d '' f; do
      case "$f" in
        semgrep/*|BuildTools/*|scripts/*|*Tests/*|*Test.swift|*Tests.swift|*"Screenshot Automation"/*) continue ;;
      esac
      printf '%s\0' "$f"
    done | xargs -0 grep -oHE -e "$swift_pattern" -- 2>/dev/null || true

    # IB declares every non-system image it uses as an <image name="…"/>
    # resource; system symbols carry catalog="system" on the same element.
    git ls-files -z -- '*.xib' '*.storyboard' \
      | xargs -0 grep -oHE -e '<image name="[^"]+"[^>]*' -- 2>/dev/null \
      | grep -v 'catalog="system"' || true
  ) \
    | sed -E 's/^([^:]+):[^"]*"([^"]+)".*$/\1\t\2/' \
    | awk -F'\t' 'index($2, "\\(") == 0' \
    | sort -u
}

if [[ "${1:-}" == "--print-available" ]]; then
  available_names
  exit 0
fi

if [[ "${1:-}" == "--print-referenced" ]]; then
  referenced_names
  exit 0
fi

allowed=""
if [[ -f "$allowlist_file" ]]; then
  allowed="$(grep -Ev '^[[:space:]]*(#|$)' "$allowlist_file" || true)"
fi

missing="$(
  awk -F'\t' '
    NR == FNR { available[$0] = 1; next }
    !($2 in available) { printf "%s\t%s\n", $2, $1 }
  ' <(available_names; printf '%s\n' "$allowed") <(referenced_names) \
    | sort -u
)"

if [[ -z "$missing" ]]; then
  echo "OK: every referenced asset name resolves to a tracked imageset/symbolset."
  exit 0
fi

echo "Image references with no matching imageset/symbolset in any tracked catalog:" >&2
printf '%s\n' "$missing" | awk -F'\t' '{ printf "  %s (referenced by %s)\n", $1, $2 }' >&2
echo >&2
echo "Restore the missing asset, fix the name, or — for names composed at" >&2
echo "runtime — add the base name to ${allowlist_file#"$repo_root"/} with a comment." >&2
exit 1
