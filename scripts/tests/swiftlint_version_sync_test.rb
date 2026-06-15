# frozen_string_literal: true

require 'minitest/autorun'

class SwiftlintVersionSyncTest < Minitest::Test
  REPO_ROOT = File.expand_path('../..', __dir__)
  SWIFTLINT_CONFIG_PATH = File.join(REPO_ROOT, '.swiftlint.yml')
  BUILD_TOOLS_MANIFEST_PATH = File.join(REPO_ROOT, 'BuildTools/Package.swift')

  def test_swiftlint_plugin_version_matches_swiftlint_config
    swiftlint_version = File.read(SWIFTLINT_CONFIG_PATH)[/^\s*swiftlint_version:\s*([^\s#]+)/, 1]
    manifest_version = File.read(BUILD_TOOLS_MANIFEST_PATH)[
      %r{\.package\(\s*url:\s*"https://github\.com/SimplyDanny/SwiftLintPlugins"\s*,\s*exact:\s*"([^"]+)"}m,
      1
    ]

    refute_nil swiftlint_version, "Missing swiftlint_version in #{SWIFTLINT_CONFIG_PATH}"
    refute_nil manifest_version, "Missing SwiftLintPlugins exact version in #{BUILD_TOOLS_MANIFEST_PATH}"
    assert_equal swiftlint_version, manifest_version,
                 'SwiftLint version drift between .swiftlint.yml and BuildTools/Package.swift. ' \
                 'Run `mise run sync:swiftlint-version` to fix.'
  end
end
