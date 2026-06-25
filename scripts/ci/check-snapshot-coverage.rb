#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'
require 'open3'
require 'optparse'

SnapshotCoverageFile = Struct.new(:name, :path, :covered_lines, :executable_lines, keyword_init: true) do
  def coverage_percent
    return 0.0 if executable_lines.zero?

    (covered_lines.to_f / executable_lines) * 100.0
  end
end

SnapshotCoverageGroup = Struct.new(
  :name,
  :files,
  :covered_lines,
  :executable_lines,
  :missing_files,
  :ambiguous_files,
  :zero_executable_files,
  keyword_init: true
) do
  def coverage_percent
    return 0.0 if executable_lines.zero?

    (covered_lines.to_f / executable_lines) * 100.0
  end
end

# Shared formatting helpers for snapshot coverage output.
module SnapshotCoverageFormat
  def self.percent(value)
    format('%.1f%%', value)
  end

  def self.overall_percent(report)
    executable_lines = report.fetch('executableLines').to_i
    return 0.0 if executable_lines.zero?

    (report.fetch('coveredLines').to_f / executable_lines) * 100.0
  end
end

# Computes per-group snapshot coverage from an xccov JSON report.
class SnapshotCoverageAnalyzer
  def initialize(groups:, threshold:)
    @groups = groups
    @threshold = threshold
  end

  def groups_for(report)
    files = coverage_files(report)
    @groups.map { |name, identifiers| coverage_for_group(name, identifiers, files) }
  end

  def failures_for(groups)
    groups.flat_map do |group|
      group_failures = []

      group_failures << "#{group.name} is missing required file(s): #{group.missing_files.join(', ')}" unless group.missing_files.empty?

      group.ambiguous_files.each do |identifier, paths|
        group_failures << "#{group.name} file #{identifier} matched multiple coverage paths: #{paths.join(', ')}"
      end

      group_failures << "#{group.name} has no executable coverage lines for: #{group.zero_executable_files.join(', ')}" unless group.zero_executable_files.empty?

      if group.coverage_percent < @threshold
        group_failures << "#{group.name} coverage is #{SnapshotCoverageFormat.percent(group.coverage_percent)}, " \
                          "below #{SnapshotCoverageFormat.percent(@threshold)}"
      end

      group_failures
    end
  end

  private

  def coverage_files(report)
    files_by_path = {}

    report.fetch('targets').each do |target|
      target.fetch('files').each do |file|
        path = file.fetch('path')
        files_by_path[path] ||= SnapshotCoverageFile.new(
          name: file.fetch('name'),
          path: path,
          covered_lines: file.fetch('coveredLines').to_i,
          executable_lines: file.fetch('executableLines').to_i
        )
      end
    end

    files_by_path.values
  end

  def coverage_for_group(name, identifiers, coverage_files)
    files = []
    missing_files = []
    ambiguous_files = {}
    zero_executable_files = []

    identifiers.each do |identifier|
      matches = matches_for(identifier, coverage_files)

      if matches.empty?
        missing_files << identifier
      elsif matches.count > 1
        ambiguous_files[identifier] = matches.map(&:path)
      elsif matches.first.executable_lines.zero?
        zero_executable_files << identifier
      else
        files << matches.first
      end
    end

    SnapshotCoverageGroup.new(
      name: name,
      files: files,
      covered_lines: files.sum(&:covered_lines),
      executable_lines: files.sum(&:executable_lines),
      missing_files: missing_files,
      ambiguous_files: ambiguous_files,
      zero_executable_files: zero_executable_files
    )
  end

  def matches_for(identifier, coverage_files)
    normalized_identifier = identifier.delete_prefix('/')

    coverage_files.select do |file|
      normalized_path = file.path.delete_prefix('/')

      if normalized_identifier.include?('/')
        normalized_path == normalized_identifier || normalized_path.end_with?("/#{normalized_identifier}")
      else
        file.name == normalized_identifier || File.basename(file.path) == normalized_identifier
      end
    end
  end
end

# Command-line entrypoint for checking required snapshot coverage groups.
class SnapshotCoverageCheck
  DEFAULT_THRESHOLD = 90.0
  DEFAULT_GROUPS = {
    'ui' => [
      'CircularProgressView.swift',
      'StoryIndicator.swift',
      'ImageView.swift',
      'GradientView.swift'
    ],
    'logic' => [
      'PlaylistQueryBuilder.swift',
      'SignificantDigitsFormatStyle.swift',
      'UIColorExtension.swift'
    ]
  }.freeze

  def self.run(argv, stdout: $stdout, stderr: $stderr)
    new(argv, stdout: stdout, stderr: stderr).run
  end

  def initialize(argv, stdout:, stderr:)
    @argv = argv.dup
    @stdout = stdout
    @stderr = stderr
    @options = {
      groups: DEFAULT_GROUPS.transform_values(&:dup),
      threshold: DEFAULT_THRESHOLD
    }
  end

  def run
    parse_options
    report = load_report
    analyzer = SnapshotCoverageAnalyzer.new(
      groups: @options.fetch(:groups),
      threshold: @options.fetch(:threshold)
    )
    groups = analyzer.groups_for(report)
    failures = analyzer.failures_for(groups)

    print_summary(report, groups)

    if failures.empty?
      0
    else
      @stderr.puts "\nSnapshot coverage check failed:"
      failures.each { |failure| @stderr.puts "- #{failure}" }
      1
    end
  rescue StandardError => e
    @stderr.puts "Error: #{e.message}"
    @stderr.puts
    @stderr.puts parser
    2
  end

  private

  def parser
    @parser ||= OptionParser.new do |opts|
      opts.banner = <<~BANNER
        Usage:
          ruby scripts/ci/check-snapshot-coverage.rb [options] <SnapshotTests.xcresult>
          ruby scripts/ci/check-snapshot-coverage.rb --json /tmp/snapshot-coverage.json
      BANNER

      opts.on('--json PATH', 'Read xccov JSON from PATH instead of invoking xcrun xccov.') do |path|
        @options[:json_path] = path
      end

      opts.on('--threshold PERCENT', Float, 'Required group coverage percentage. Defaults to 90.') do |threshold|
        @options[:threshold] = threshold
      end

      DEFAULT_GROUPS.each_key do |group_name|
        opts.on("--#{group_name} FILES", Array, "Comma-separated required #{group_name} coverage files.") do |files|
          @options.fetch(:groups)[group_name] = files
        end
      end
    end
  end

  def parse_options
    parser.parse!(@argv)
    raise OptionParser::ParseError, 'threshold must be greater than 0' unless @options.fetch(:threshold).positive?
  end

  def load_report
    json_path = @options[:json_path]
    if json_path
      raise OptionParser::ParseError, "unexpected extra argument: #{@argv.first}" unless @argv.empty?

      return JSON.parse(File.read(json_path))
    end

    source_path = @argv.shift
    raise OptionParser::ParseError, 'pass an .xcresult path or --json PATH' if source_path.nil?
    raise OptionParser::ParseError, "unexpected extra argument: #{@argv.first}" unless @argv.empty?
    return JSON.parse(File.read(source_path)) if source_path.end_with?('.json')

    output, status = Open3.capture2e('xcrun', 'xccov', 'view', '--report', '--json', source_path)
    raise "xcrun xccov failed for #{source_path}:\n#{output}" unless status.success?

    JSON.parse(output)
  end

  def print_summary(report, groups)
    @stdout.puts 'Snapshot coverage groups:'
    groups.each do |group|
      @stdout.puts "  #{group.name}: #{SnapshotCoverageFormat.percent(group.coverage_percent)} (#{group.covered_lines}/#{group.executable_lines})"
    end
    @stdout.puts "Overall linked target coverage: #{SnapshotCoverageFormat.percent(SnapshotCoverageFormat.overall_percent(report))} " \
                 "(#{report.fetch('coveredLines')}/#{report.fetch('executableLines')}) [reported only]"
  end
end

exit SnapshotCoverageCheck.run(ARGV) if $PROGRAM_NAME == __FILE__
