#!/usr/bin/env bash
# Verifies that every expected test bundle ran at least one non-skipped test.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
json_report=""

if [[ "${1:-}" == "--json-report" ]]; then
  json_report="${2:?missing JSON report path}"
  shift 2
fi

xcresult_path="${1:-unused.xcresult}"
expected_file="${2:-$script_dir/expected-test-targets.txt}"

if [[ -n "$json_report" ]]; then
  report_json="$(<"$json_report")"
else
  report_json="$(xcrun xcresulttool get test-results tests --path "$xcresult_path" --compact)"
fi

printf '%s' "$report_json" | ruby -rjson -e '
  expected_path = ARGV.fetch(0)
  expected = File.readlines(expected_path, chomp: true)
    .map(&:strip)
    .reject { |line| line.empty? || line.start_with?("#") }

  executed_bundles = []
  contains_executed_test = lambda do |value|
    case value
    when Hash
      return true if value["nodeType"] == "Test Case" && value["result"] != "Skipped"
      value.each_value.any? { |child| contains_executed_test.call(child) }
    when Array
      value.any? { |child| contains_executed_test.call(child) }
    else
      false
    end
  end

  walk = lambda do |value|
    case value
    when Hash
      if value["nodeType"] == "Unit test bundle" && contains_executed_test.call(value)
        executed_bundles << value.fetch("name").delete_suffix(".xctest")
      end
      value.each_value { |child| walk.call(child) }
    when Array
      value.each { |child| walk.call(child) }
    end
  end
  walk.call(JSON.parse($stdin.read))

  missing = expected - executed_bundles
  unless missing.empty?
    warn "Expected test targets did not execute: #{missing.join(", ")}"
    exit 1
  end

  puts "Executed expected test targets: #{expected.join(", ")}"
' "$expected_file"
