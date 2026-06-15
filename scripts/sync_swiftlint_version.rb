#!/usr/bin/env ruby
# frozen_string_literal: true

# Syncs the SwiftLintPlugins pin in BuildTools/Package.swift to the
# `swiftlint_version` declared in .swiftlint.yml, which is the source of truth.
#
# Run the matching `swift package --package-path BuildTools resolve` afterwards
# (the `sync:swiftlint-version` mise task does this) to update the lockfile.
#
# The regexes here intentionally mirror scripts/tests/swiftlint_version_sync_test.rb
# so the writer and the drift guard agree on the same shapes.

REPO_ROOT = File.expand_path('..', __dir__)
# Paths default to the repo files; the env overrides exist so scripts/tests/sync_swiftlint_version_test.rb
# can drive the script against temp fixtures without touching the real manifest.
SWIFTLINT_CONFIG_PATH = ENV.fetch('SWIFTLINT_CONFIG_PATH', File.join(REPO_ROOT, '.swiftlint.yml'))
BUILD_TOOLS_MANIFEST_PATH = ENV.fetch('BUILD_TOOLS_MANIFEST_PATH', File.join(REPO_ROOT, 'BuildTools/Package.swift'))

MANIFEST_PIN_PATTERN =
  %r{(\.package\(\s*url:\s*"https://github\.com/SimplyDanny/SwiftLintPlugins"\s*,\s*exact:\s*")([^"]+)(")}m

def abort_with(message)
  warn "sync_swiftlint_version: #{message}"
  exit 1
end

swiftlint_version = File.read(SWIFTLINT_CONFIG_PATH)[/^\s*swiftlint_version:\s*([^\s#]+)/, 1]
abort_with("Missing swiftlint_version in #{SWIFTLINT_CONFIG_PATH}") if swiftlint_version.nil?

manifest = File.read(BUILD_TOOLS_MANIFEST_PATH)
match = manifest.match(MANIFEST_PIN_PATTERN)
abort_with("Missing SwiftLintPlugins exact pin in #{BUILD_TOOLS_MANIFEST_PATH}") if match.nil?

current_version = match[2]
if current_version == swiftlint_version
  puts "SwiftLintPlugins pin already at #{swiftlint_version}; nothing to do."
  exit 0
end

updated = manifest.sub(MANIFEST_PIN_PATTERN, "\\1#{swiftlint_version}\\3")
File.write(BUILD_TOOLS_MANIFEST_PATH, updated)
puts "Updated SwiftLintPlugins pin #{current_version} -> #{swiftlint_version} in BuildTools/Package.swift."
puts "Now run: swift package --package-path BuildTools resolve"
