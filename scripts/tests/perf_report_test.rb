# frozen_string_literal: true

require "minitest/autorun"
require "tempfile"
require_relative "../ci/perf-report"

class PerfReportTest < Minitest::Test
  MEASURED_LOG = <<~LOG
    Test Case '-[PocketCastsUITests.PerformanceUITests testColdLaunchPerformance]' measured [Duration (AppLaunch), s] average: 1.500, relative standard deviation: 4.2%, values: [1.4, 1.5, 1.6]
    Test Case '-[PocketCastsUITests.PerformanceUITests testPodcastPageEntryPerformance]' measured [Clock Monotonic Time, s] average: 0.800, relative standard deviation: 9.9%, values: [0.7, 0.9]
    Test Case '-[PocketCastsUITests.PerformanceUITests testColdLaunchPerformance]' passed (12.3 seconds).
  LOG

  def with_log(content)
    Tempfile.create(["perf", ".log"]) do |file|
      file.write(content)
      file.flush
      yield file.path
    end
  end

  def test_parses_measured_lines_only
    with_log(MEASURED_LOG) do |path|
      entries = PerfReport.parse(path)
      assert_equal 2, entries.length
      assert_equal "testColdLaunchPerformance", entries[0].test
      assert_equal "Duration (AppLaunch), s", entries[0].metric
      assert_in_delta 1.5, entries[0].average
      assert_in_delta 4.2, entries[0].rsd
    end
  end

  def test_replaces_malformed_utf8_without_losing_measurements
    malformed_log = (
      "compiler output: \xFF\n".b +
      MEASURED_LOG.b +
      "undefined bytes: \xC3\x28\n".b
    )

    with_log(malformed_log) do |path|
      entries = PerfReport.parse(path)
      assert_equal 2, entries.length
      assert_equal "testColdLaunchPerformance", entries[0].test
    end
  end

  def test_markdown_reports_delta_against_baseline
    with_log(MEASURED_LOG) do |path|
      entries = PerfReport.parse(path)
      markdown = PerfReport.markdown(entries, { "testColdLaunchPerformance|Duration (AppLaunch), s" => 1.0 })

      assert_includes markdown, "+50.0%"
      assert_includes markdown, "n/a (no baseline)", "Metrics without a baseline must say so instead of failing"
    end
  end

  def test_markdown_handles_empty_log
    with_log("nothing measured here") do |path|
      markdown = PerfReport.markdown(PerfReport.parse(path), {})
      assert_includes markdown, "No performance measurements"
    end
  end
end
