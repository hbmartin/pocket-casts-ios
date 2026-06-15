# frozen_string_literal: true

require 'fileutils'
require 'minitest/autorun'
require 'open3'
require 'rbconfig'
require 'tmpdir'

# Exercises the writer in scripts/sync_swiftlint_version.rb against temp fixtures. The companion
# swiftlint_version_sync_test.rb only guards the committed state; this covers the mutation path
# (rewrite, idempotent no-op, surrounding-text preservation) and the loud-failure branches.
class SyncSwiftlintVersionTest < Minitest::Test
  REPO_ROOT = File.expand_path('../..', __dir__)
  SCRIPT_PATH = File.join(REPO_ROOT, 'scripts/sync_swiftlint_version.rb')

  def setup
    @tmpdir = Dir.mktmpdir('sync-swiftlint-version-test')
    @config_path = File.join(@tmpdir, '.swiftlint.yml')
    @manifest_path = File.join(@tmpdir, 'Package.swift')
  end

  def teardown
    FileUtils.remove_entry(@tmpdir) if @tmpdir && File.exist?(@tmpdir)
  end

  def test_rewrites_manifest_pin_to_config_version
    write_config('0.63.4')
    write_manifest('0.63.2')

    stdout, stderr, status = run_script

    assert status.success?, stdout + stderr
    assert_match(/Updated SwiftLintPlugins pin 0\.63\.2 -> 0\.63\.4/, stdout)
    assert_includes File.read(@manifest_path), '"https://github.com/SimplyDanny/SwiftLintPlugins", exact: "0.63.4"'
  end

  def test_preserves_surrounding_manifest_text
    write_config('0.63.4')
    write_manifest('0.63.2')

    run_script

    manifest = File.read(@manifest_path)
    assert_includes manifest, 'name: "BuildTools"'
    assert_includes manifest, 'SwiftGen/SwiftGenPlugin' # the other dependency is left untouched
  end

  def test_noop_when_already_in_sync
    write_config('0.63.3')
    write_manifest('0.63.3')
    before = File.read(@manifest_path)

    stdout, _stderr, status = run_script

    assert status.success?
    assert_match(/already at 0\.63\.3; nothing to do/, stdout)
    assert_equal before, File.read(@manifest_path) # byte-for-byte unchanged
  end

  def test_ignores_trailing_comment_in_config
    write_config('0.63.4 # keep in sync with BuildTools')
    write_manifest('0.63.2')

    stdout, stderr, status = run_script

    assert status.success?, stdout + stderr
    assert_includes File.read(@manifest_path), 'exact: "0.63.4"'
  end

  def test_fails_loudly_when_config_version_missing
    File.write(@config_path, "# no swiftlint version declared here\n")
    write_manifest('0.63.2')

    stdout, stderr, status = run_script

    refute status.success?
    assert_match(/Missing swiftlint_version/, stdout + stderr)
    assert_equal '0.63.2', manifest_version, 'manifest must be left untouched on failure'
  end

  def test_fails_loudly_when_manifest_pin_missing
    write_config('0.63.4')
    File.write(@manifest_path, "let package = Package(name: \"BuildTools\")\n")

    stdout, stderr, status = run_script

    refute status.success?
    assert_match(/Missing SwiftLintPlugins exact pin/, stdout + stderr)
  end

  private

  def run_script
    env = {
      'SWIFTLINT_CONFIG_PATH' => @config_path,
      'BUILD_TOOLS_MANIFEST_PATH' => @manifest_path
    }
    Open3.capture3(env, RbConfig.ruby, SCRIPT_PATH)
  end

  def manifest_version
    File.read(@manifest_path)[/SwiftLintPlugins"\s*,\s*exact:\s*"([^"]+)"/, 1]
  end

  def write_config(version)
    File.write(@config_path, <<~YAML)
      swiftlint_version: #{version}

      # Project configuration
    YAML
  end

  def write_manifest(version)
    File.write(@manifest_path, <<~SWIFT)
      // swift-tools-version:5.7
      import PackageDescription

      let package = Package(
          name: "BuildTools",
          platforms: [.macOS(.v10_13)],
          dependencies: [
              .package(url: "https://github.com/SimplyDanny/SwiftLintPlugins", exact: "#{version}"),
              .package(url: "https://github.com/SwiftGen/SwiftGenPlugin", from: "6.5.1")
          ],
          targets: [.target(name: "BuildTools", path: "")]
      )
    SWIFT
  end
end
