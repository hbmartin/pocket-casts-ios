# frozen_string_literal: true

# Parses `-Xfrontend -debug-time-function-bodies` output from an xcodebuild log
# and produces a markdown table of the slowest function bodies, so PRs surface
# compile-time regressions as a reviewable trend (program item 44).
#
# The Danger job injects the flag via POCKET_CASTS_CI_OTHER_SWIFT_FLAGS
# (.github/workflows/danger.yml) and build-and-test.sh tees the build output to
# build/github/logs/test-staging.log, which is still on disk when
# `bundle exec danger` runs in the same job.
module BuildTimeReport
  # A frontend timing line looks like:
  #   \t123.45ms\t/path/to/File.swift:42:9\tinstance method foo()
  # Location may be "<invalid loc>" for synthesized code.
  LINE = /^\s*(\d+(?:\.\d+)?)ms\t([^\t]*)\t(.*)$/

  Entry = Struct.new(:ms, :location, :decl)

  def self.parse(log_path)
    entries = []
    File.foreach(log_path) do |line|
      match = LINE.match(line)
      next unless match

      entries << Entry.new(match[1].to_f, match[2], match[3].strip)
    end
    entries
  end

  # The frontend emits one line per type-check of a body; the same declaration
  # can be re-checked many times across module variants. Report the max single
  # check per declaration (the regression signal) and the total across all
  # checks (the wall-clock cost signal).
  def self.markdown(log_path, top: 20, threshold_ms: 100)
    return nil unless File.exist?(log_path)

    entries = parse(log_path)
    return nil if entries.empty?

    total_ms = entries.sum(&:ms)
    slowest = entries
              .group_by { |e| [e.location, e.decl] }
              .map { |(location, decl), group| Entry.new(group.map(&:ms).max, location, decl) }
              .sort_by { |e| -e.ms }
              .first(top)

    over_threshold = slowest.take_while { |e| e.ms >= threshold_ms }
    shown = over_threshold.empty? ? slowest.first(5) : over_threshold

    rows = shown.map do |e|
      location = e.location.sub(%r{^.*?/(podcasts|Modules|WidgetExtension|PocketCastsTests)/}, '\1/')
      "| #{format('%.1f', e.ms)} | `#{escape(e.decl)}` | `#{escape(location)}` |"
    end

    <<~MARKDOWN
      ### Slowest function bodies (type-check time)

      Total frontend body type-check time: **#{format('%.1f', total_ms / 1000.0)}s** across #{entries.length} checks.

      | ms (max single check) | Declaration | Location |
      |---:|---|---|
      #{rows.join("\n")}
    MARKDOWN
  end

  def self.escape(text)
    text.to_s.gsub('|', '\\|')
  end
end
