# frozen_string_literal: true

github.dismiss_out_of_range_messages

# `files: []` forces rubocop to scan all files, not just the ones modified in the PR
rubocop.lint(files: [], force_exclusion: true, inline_comment: true, fail_on_inline_comment: true, include_cop_names: true)

manifest_pr_checker.check_all_manifest_lock_updated

view_changes_checker.check

xcode_result_bundle = ENV.fetch('POCKET_CASTS_XCRESULT_PATH', 'build/github/results/PocketCastsTests.xcresult')
derived_data_path = ENV.fetch('POCKET_CASTS_CI_DERIVED_DATA_PATH', 'build/github/DerivedData')

if File.exist?(xcode_result_bundle)
  xcode_summary.ignored_files = [
    '**/BuildTools/.build/**',
    '**/Modules/.build/**',
    '**/Pods/**'
  ]
  xcode_summary.ignores_warnings = ENV.fetch('DANGER_XCODE_SUMMARY_WARNINGS', '0') != '1'
  xcode_summary.collapse_parallelized_tests = true
  xcode_summary.ignore_retried_tests = true
  xcode_summary.report(xcode_result_bundle)
end

if File.directory?(derived_data_path)
  begin
    slather.configure(
      'podcasts.xcodeproj',
      'Pocket Casts Staging',
      {
        build_directory: derived_data_path,
        configuration: 'StagingDebug',
        coverage_service: :terminal,
        decimals: 2
      }
    )
    slather.show_coverage
  rescue StandardError => e
    warn("Slather coverage report could not be generated: #{e.message}")
  end

  activity_log = Dir[File.join(derived_data_path, 'Logs/Build/*.xcactivitylog')].max_by { |path| File.mtime(path) }
  if activity_log
    xcprofiler.inline_mode = true
    xcprofiler.thresholds = { warn: 1_000, fail: 10_000 }
    xcprofiler.ignored_files = [
      '**/BuildTools/.build/**',
      '**/Modules/.build/**',
      '**/Pods/**'
    ]
    begin
      xcprofiler.report(nil, nil, activity_log)
    rescue StandardError => e
      warn("Xcode build-time report could not be generated: #{e.message}")
    end
  end
end
