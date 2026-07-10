#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"
checker="$repo_root/scripts/ci/check-test-targets.sh"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

expected="$tmp_dir/expected.txt"
complete="$tmp_dir/complete.json"
missing="$tmp_dir/missing.json"

cat > "$expected" <<'EOF'
# comments and blank lines are ignored

PocketCastsTests
PocketCastsDataModelTests
EOF

cat > "$complete" <<'EOF'
{
  "testNodes": [
    {
      "name": "UnitTests",
      "children": [
        {
          "nodeType": "Unit test bundle",
          "name": "PocketCastsTests",
          "result": "Passed",
          "children": [
            { "nodeType": "Test Case", "name": "testApp()", "result": "Passed" }
          ]
        },
        {
          "nodeType": "Unit test bundle",
          "name": "PocketCastsDataModelTests.xctest",
          "result": "Failed",
          "children": [
            { "nodeType": "Test Case", "name": "testDatabase()", "result": "Failed" }
          ]
        }
      ]
    }
  ]
}
EOF

cat > "$missing" <<'EOF'
{
  "testNodes": [
    {
      "nodeType": "Unit test bundle",
      "name": "PocketCastsTests",
      "result": "Passed",
      "children": [
        { "nodeType": "Test Case", "name": "testApp()", "result": "Passed" }
      ]
    },
    {
      "nodeType": "Unit test bundle",
      "name": "PocketCastsDataModelTests",
      "result": "Passed",
      "children": []
    }
  ]
}
EOF

"$checker" --json-report "$complete" unused.xcresult "$expected"

if "$checker" --json-report "$missing" unused.xcresult "$expected" 2>/dev/null; then
  echo "FAIL: missing test target was accepted" >&2
  exit 1
fi

echo "All check-test-targets tests passed."
