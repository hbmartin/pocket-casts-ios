#!/usr/bin/env bash
# Tests for scripts/ci/check-count-ratchets.sh using a synthetic git repo.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"
checker="$repo_root/scripts/ci/check-count-ratchets.sh"

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
baseline_dir="$tmp_dir/baselines"
mkdir -p "$fake_repo/podcasts" "$fake_repo/PocketCastsTests" "$fake_repo/semgrep/tests" "$baseline_dir"
git init -q "$fake_repo"

cat > "$fake_repo/podcasts/Player.swift" <<'EOF'
final class PlayerBox: @unchecked Sendable {
    func cast(_ any: Any) {
        let vc = any as! UIViewController
        let cell = any as! UITableViewCell
    }
    // "has!" and a plain "as" must not count as force casts.
    let has = "has!"
    let plain = 0 as Int
}
EOF
cat > "$fake_repo/podcasts/Feed.swift" <<'EOF'
struct Feed: @unchecked Sendable {}
EOF
# Test code and semgrep fixtures are out of scope for force-cast.
cat > "$fake_repo/PocketCastsTests/PlayerTest.swift" <<'EOF'
let sut = thing as! PlayerBox
EOF
cat > "$fake_repo/semgrep/tests/fixture.swift" <<'EOF'
let x = y as! Z
struct S: @unchecked Sendable {}
EOF
git -C "$fake_repo" add -A

export RATCHET_REPO_ROOT="$fake_repo"
export RATCHET_BASELINE_DIR="$baseline_dir"

# Counting: occurrences per file, word-anchored, scoped per ratchet.
expected_force_cast="podcasts/Player.swift: 2"
actual_force_cast="$("$checker" --print-counts force-cast)"
assert "force-cast counts (tests and fixtures excluded, word-anchored)" \
  [ "$actual_force_cast" = "$expected_force_cast" ]

expected_sendable="podcasts/Feed.swift: 1
podcasts/Player.swift: 1"
actual_sendable="$("$checker" --print-counts unchecked-sendable)"
assert "unchecked-sendable counts" [ "$actual_sendable" = "$expected_sendable" ]

# Missing baselines fail the check.
assert_fails "missing baselines fail" "$checker" 2>/dev/null

# Freshly generated baselines pass.
"$checker" --update-baselines > /dev/null
assert "current counts match fresh baselines" "$checker"

# A new occurrence in an existing file fails.
echo 'let extra = a as! B' >> "$fake_repo/podcasts/Player.swift"
git -C "$fake_repo" add -A
assert_fails "count increase fails" "$checker" 2>/dev/null
err="$("$checker" 2>&1 >/dev/null || true)"
assert "violation names the file and counts" grep -q "podcasts/Player.swift: 3 (baseline 2)" <<< "$err"

# A new file introducing the pattern fails.
git -C "$fake_repo" checkout -q -- . 2>/dev/null || true
cat > "$fake_repo/podcasts/Player.swift" <<'EOF'
final class PlayerBox: @unchecked Sendable {
    func cast(_ any: Any) {
        let vc = any as! UIViewController
        let cell = any as! UITableViewCell
    }
}
EOF
cat > "$fake_repo/podcasts/New.swift" <<'EOF'
let n = x as! Y
EOF
git -C "$fake_repo" add -A
err="$("$checker" 2>&1 >/dev/null || true)"
assert "new file fails as not-in-baseline" grep -q "podcasts/New.swift: 1 (not in baseline)" <<< "$err"
rm "$fake_repo/podcasts/New.swift"
git -C "$fake_repo" add -A

# A removed occurrence passes and is reported as an improvement to lock in.
sed -i '' 's/let cell = any as! UITableViewCell//' "$fake_repo/podcasts/Player.swift"
git -C "$fake_repo" add -A
out="$("$checker")"
assert "improvement passes" "$checker" > /dev/null
assert "improvement suggests locking in the baseline" grep -q "ratchets:baseline" <<< "$out"

if (( failures > 0 )); then
  echo "$failures test(s) failed" >&2
  exit 1
fi
echo "All check-count-ratchets tests passed."
