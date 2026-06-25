# frozen_string_literal: true

require 'json'
require 'minitest/autorun'
require 'open3'
require 'rbconfig'
require 'tempfile'

# Shared xccov report fixtures for the snapshot coverage script tests.
module SnapshotCoverageFixtures
  private

  def default_files
    {
      'CircularProgressView.swift' => [90, 100],
      'StoryIndicator.swift' => [95, 100],
      'ImageView.swift' => [90, 100],
      'GradientView.swift' => [95, 100],
      'PlaylistQueryBuilder.swift' => [92, 100],
      'SignificantDigitsFormatStyle.swift' => [90, 100],
      'UIColorExtension.swift' => [93, 100]
    }
  end

  def report_with(files:, overall: nil)
    file_entries = files.map do |name, (covered_lines, executable_lines)|
      coverage_file(name, covered_lines: covered_lines, executable_lines: executable_lines)
    end

    covered_lines, executable_lines = overall || [
      file_entries.sum { |file| file.fetch('coveredLines') },
      file_entries.sum { |file| file.fetch('executableLines') }
    ]

    {
      'coveredLines' => covered_lines,
      'executableLines' => executable_lines,
      'lineCoverage' => executable_lines.zero? ? 0 : covered_lines.to_f / executable_lines,
      'targets' => [
        {
          'name' => 'SnapshotTests',
          'coveredLines' => covered_lines,
          'executableLines' => executable_lines,
          'lineCoverage' => executable_lines.zero? ? 0 : covered_lines.to_f / executable_lines,
          'files' => file_entries
        }
      ]
    }
  end

  def coverage_file(name, covered_lines:, executable_lines:)
    {
      'name' => name,
      'path' => File.join('/repo/Modules/Sources', name),
      'coveredLines' => covered_lines,
      'executableLines' => executable_lines,
      'lineCoverage' => executable_lines.zero? ? 0 : covered_lines.to_f / executable_lines
    }
  end
end

# Verifies the command-line behavior of the snapshot coverage checker.
class CheckSnapshotCoverageTest < Minitest::Test
  include SnapshotCoverageFixtures

  REPO_ROOT = File.expand_path('../..', __dir__)
  SCRIPT_PATH = File.join(REPO_ROOT, 'scripts/ci/check-snapshot-coverage.rb')

  def test_passes_when_snapshot_groups_meet_threshold_even_if_overall_is_low
    stdout, stderr, status = run_script(
      report_with(
        overall: [200, 1_000],
        files: default_files
      )
    )

    assert status.success?, stdout + stderr
    assert_includes stdout, 'ui: 92.5% (370/400)'
    assert_includes stdout, 'logic: 91.7% (275/300)'
    assert_includes stdout, 'Overall linked target coverage: 20.0% (200/1000) [reported only]'
    assert_empty stderr
  end

  def test_fails_when_a_snapshot_group_is_below_threshold
    files = default_files.merge('GradientView.swift' => [40, 100])

    stdout, stderr, status = run_script(report_with(files: files))

    refute status.success?, stdout + stderr
    assert_includes stdout, 'ui: 78.8% (315/400)'
    assert_includes stderr, 'ui coverage is 78.8%, below 90.0%'
  end

  def test_fails_when_required_file_is_missing
    files = default_files.except('GradientView.swift')

    stdout, stderr, status = run_script(report_with(files: files))

    refute status.success?, stdout + stderr
    assert_includes stderr, 'ui is missing required file(s): GradientView.swift'
  end

  def test_fails_when_required_file_has_no_executable_lines
    files = default_files.merge('GradientView.swift' => [0, 0])

    stdout, stderr, status = run_script(report_with(files: files))

    refute status.success?, stdout + stderr
    assert_includes stderr, 'ui has no executable coverage lines for: GradientView.swift'
  end

  def test_allows_custom_groups_and_threshold
    stdout, stderr, status = run_script(
      report_with(files: { 'CircularProgressView.swift' => [8, 10], 'PlaylistQueryBuilder.swift' => [7, 10] }),
      '--threshold',
      '70',
      '--ui',
      'CircularProgressView.swift',
      '--logic',
      'PlaylistQueryBuilder.swift'
    )

    assert status.success?, stdout + stderr
    assert_includes stdout, 'ui: 80.0% (8/10)'
    assert_includes stdout, 'logic: 70.0% (7/10)'
    assert_empty stderr
  end

  def test_rejects_extra_argument_when_reading_json_report
    stdout, stderr, status = run_script(report_with(files: default_files), 'extra.xcresult')

    refute status.success?, stdout + stderr
    assert_empty stdout
    assert_includes stderr, 'unexpected extra argument: extra.xcresult'
  end

  def test_reports_missing_json_path_without_backtrace
    stdout, stderr, status = Open3.capture3(RbConfig.ruby, SCRIPT_PATH, '--json', '/tmp/missing-snapshot-coverage.json')

    refute status.success?, stdout + stderr
    assert_empty stdout
    assert_includes stderr, 'No such file or directory'
    refute_includes stderr, 'Traceback'
  end

  private

  def run_script(report, *args)
    Tempfile.create(['snapshot-coverage', '.json']) do |file|
      file.write(JSON.pretty_generate(report))
      file.close

      Open3.capture3(RbConfig.ruby, SCRIPT_PATH, '--json', file.path, *args)
    end
  end
end
