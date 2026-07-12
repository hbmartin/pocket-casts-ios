#!/usr/bin/env bash
# Tests for scripts/ci/check-asset-references.sh using a synthetic git repo.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"
checker="$repo_root/scripts/ci/check-asset-references.sh"

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

fake_repo="$tmp_dir/repo"
allowlist="$tmp_dir/allowlist.txt"
mkdir -p "$fake_repo/podcasts/Images.xcassets/known-icon.imageset" \
         "$fake_repo/podcasts/Images.xcassets/symbol-icon.symbolset" \
         "$fake_repo/PocketCastsTests" "$fake_repo/semgrep/tests"
git init -q "$fake_repo"

echo '{}' > "$fake_repo/podcasts/Images.xcassets/known-icon.imageset/Contents.json"
echo '{}' > "$fake_repo/podcasts/Images.xcassets/symbol-icon.symbolset/Contents.json"

cat > "$fake_repo/podcasts/Views.swift" <<'EOF'
let a = UIImage(named: "known-icon")
let b = Image("symbol-icon")
let c = Image(decorative: "known-icon")
// System symbols and non-literal names are out of scope.
let d = Image(systemName: "checkmark")
let e = UIImage(named: "prefix-\(suffix)")
EOF

cat > "$fake_repo/podcasts/Cell.xib" <<'EOF'
<document>
  <imageView image="known-icon"/>
  <resources>
    <image name="known-icon" width="20" height="20"/>
    <image name="checkmark" catalog="system" width="10" height="10"/>
  </resources>
</document>
EOF

# Out-of-scope trees may reference anything.
echo 'let t = UIImage(named: "test-only-asset")' > "$fake_repo/PocketCastsTests/FixtureTest.swift"
echo 'let s = UIImage(named: "semgrep-only")' > "$fake_repo/semgrep/tests/fixture.swift"

: > "$allowlist"
git -C "$fake_repo" add -A

export ASSET_CHECK_REPO_ROOT="$fake_repo"
export ASSET_CHECK_ALLOWLIST="$allowlist"

# All literal references resolve; system/interpolated/test refs are ignored.
assert "resolvable references pass" "$checker" > /dev/null

expected_available="known-icon
symbol-icon"
assert "available names cover imagesets and symbolsets" \
  [ "$("$checker" --print-available)" = "$expected_available" ]

# A Swift reference to a deleted asset fails and names both sides.
echo 'let broken = UIImage(named: "gone-icon")' >> "$fake_repo/podcasts/Views.swift"
git -C "$fake_repo" add -A
assert_fails "dangling Swift reference fails" "$checker" 2>/dev/null
err="$("$checker" 2>&1 >/dev/null || true)"
assert "failure names the asset and the referencing file" \
  grep -q "gone-icon (referenced by podcasts/Views.swift)" <<< "$err"

# Allowlisted names (with comments and blank lines) are accepted.
{ echo "# runtime-composed"; echo; echo "gone-icon"; } > "$allowlist"
assert "allowlisted name passes" "$checker" > /dev/null
: > "$allowlist"

git -C "$fake_repo" checkout -q -- podcasts/Views.swift

# A xib image resource without catalog=\"system\" must resolve too.
cat > "$fake_repo/podcasts/Broken.xib" <<'EOF'
<document>
  <resources>
    <image name="missing-xib-icon" width="20" height="20"/>
  </resources>
</document>
EOF
git -C "$fake_repo" add -A
err="$("$checker" 2>&1 >/dev/null || true)"
assert "dangling xib reference fails" \
  grep -q "missing-xib-icon (referenced by podcasts/Broken.xib)" <<< "$err"
rm "$fake_repo/podcasts/Broken.xib"
git -C "$fake_repo" add -A

# Deleting an imageset that is still referenced fails (the Discovery.xcassets
# regression this guard exists for).
git -C "$fake_repo" rm -rqf podcasts/Images.xcassets/known-icon.imageset
err="$("$checker" 2>&1 >/dev/null || true)"
assert "deleting a referenced imageset fails" \
  grep -q "known-icon (referenced by" <<< "$err"

if (( failures > 0 )); then
  echo "$failures test(s) failed" >&2
  exit 1
fi
echo "All check-asset-references tests passed."
