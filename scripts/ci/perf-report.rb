# frozen_string_literal: true

# Parses XCTest `measure` output from an xcodebuild log and produces a markdown
# table of each performance test's metrics with deltas against the committed
# baselines (Deferred Item 39). Reporting-only: exits 0 regardless of deltas —
# gating waits until variance is characterized across enough runs.
#
# A measured line looks like:
#   Test Case '-[PocketCastsUITests.PerformanceUITests testColdLaunchPerformance]' \
#     measured [Duration (AppLaunch), s] average: 1.234, relative standard deviation: 5.6%, ...
#
# Usage: ruby scripts/ci/perf-report.rb <xcodebuild-log> [baselines-json]
module PerfReport
  LINE = /Test Case '-\[[^ ]+ (test\w+)\]' measured \[([^\]]+)\] average: ([\d.]+), relative standard deviation: ([\d.]+)%/

  Entry = Struct.new(:test, :metric, :average, :rsd)

  def self.parse(log_path)
    entries = []
    File.foreach(log_path) do |line|
      match = LINE.match(line)
      next unless match

      entries << Entry.new(match[1], match[2], match[3].to_f, match[4].to_f)
    end
    entries
  end

  def self.markdown(entries, baselines)
    return "No performance measurements found in the log.\n" if entries.empty?

    rows = entries.map do |entry|
      key = "#{entry.test}|#{entry.metric}"
      baseline = baselines[key]
      delta = if baseline && baseline.positive?
        format("%+.1f%%", ((entry.average - baseline) / baseline) * 100)
      else
        "n/a (no baseline)"
      end
      baseline_text = baseline ? format("%.3f", baseline) : "—"
      "| #{entry.test} | #{entry.metric} | #{format('%.3f', entry.average)} | #{baseline_text} | #{delta} | #{format('%.1f%%', entry.rsd)} |"
    end

    <<~MARKDOWN
      ### Performance baselines (reporting-only)

      | Test | Metric | Average | Baseline | Delta | RSD |
      |---|---|---:|---:|---:|---:|
      #{rows.join("\n")}

      Baselines live in `scripts/ci/perf-baselines.json` (key: `test|metric`). Update them deliberately after reviewing a run; deltas never fail CI yet.
    MARKDOWN
  end
end

if $PROGRAM_NAME == __FILE__
  require "json"

  log_path = ARGV[0] or abort("usage: perf-report.rb <xcodebuild-log> [baselines-json]")
  baselines_path = ARGV[1] || File.join(__dir__, "perf-baselines.json")
  baselines = File.exist?(baselines_path) ? JSON.parse(File.read(baselines_path)) : {}

  puts PerfReport.markdown(PerfReport.parse(log_path), baselines)
end
