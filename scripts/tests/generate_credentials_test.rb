# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'minitest/autorun'
require 'open3'
require 'rbconfig'
require 'tmpdir'

class GenerateCredentialsTest < Minitest::Test
  REPO_ROOT = File.expand_path('../..', __dir__)
  SCRIPT_PATH = File.join(REPO_ROOT, 'scripts/build-phases/generate-credentials.sh')
  TEMPLATE_PATH = File.join(REPO_ROOT, 'podcasts/Credentials/ApiCredentials.tpl')
  REPLACE_SECRETS_PATH = File.join(REPO_ROOT, 'podcasts/Credentials/replace_secrets.rb')

  def setup
    @tmpdir = Dir.mktmpdir('generate-credentials-test')
    @source_root = File.join(@tmpdir, 'source')
    @credentials_dir = File.join(@source_root, 'podcasts/Credentials')
    @build_products_dir = File.join(@tmpdir, 'build/Products/StagingDebug-iphonesimulator')
    @secrets_path = File.join(@tmpdir, 'secrets.json')

    FileUtils.mkdir_p(@credentials_dir)
    FileUtils.mkdir_p(@build_products_dir)
    FileUtils.cp(TEMPLATE_PATH, File.join(@credentials_dir, 'ApiCredentials.tpl'))
    FileUtils.cp(REPLACE_SECRETS_PATH, File.join(@credentials_dir, 'replace_secrets.rb'))
  end

  def teardown
    FileUtils.remove_entry(@tmpdir) if @tmpdir && File.exist?(@tmpdir)
  end

  def test_json_generation_succeeds_with_real_values
    write_secrets(bitdrift_sdk_key: 'bitdrift-real', telemetry_deck_app_id: 'telemetry-real')

    stdout, stderr, status = run_script

    assert status.success?, stdout + stderr
    assert_includes generated_credentials, 'static let bitdriftSDKKey = "bitdrift-real"'
    assert_includes generated_credentials, 'static let telemetryDeckAppID = "telemetry-real"'
  end

  def test_json_generation_allows_empty_values
    write_secrets(bitdrift_sdk_key: '', telemetry_deck_app_id: '')

    stdout, stderr, status = run_script

    assert status.success?, stdout + stderr
    assert_includes generated_credentials, 'static let bitdriftSDKKey = ""'
    assert_includes generated_credentials, 'static let telemetryDeckAppID = ""'
  end

  def test_json_generation_fails_when_placeholder_persists
    write_secrets(bitdrift_sdk_key: '%{bitdrift_sdk_key}', telemetry_deck_app_id: 'telemetry-real')

    stdout, stderr, status = run_script

    refute status.success?, stdout + stderr
    assert_match(/Unresolved placeholder\(s\) found/, stdout + stderr)
    assert_match(/static let bitdriftSDKKey = "%\{bitdrift_sdk_key\}"/, stdout + stderr)
  end

  def test_json_generation_fails_when_empty_placeholder_persists
    write_secrets(bitdrift_sdk_key: '%{}', telemetry_deck_app_id: 'telemetry-real')

    stdout, stderr, status = run_script

    refute status.success?, stdout + stderr
    assert_match(/Unresolved placeholder\(s\) found/, stdout + stderr)
    assert_match(/static let bitdriftSDKKey = "%\{\}"/, stdout + stderr)
  end

  def test_local_credentials_path_succeeds_without_placeholders
    write_local_credentials(value: 'real-value')

    stdout, stderr, status = run_script

    assert status.success?, stdout + stderr
  end

  def test_local_credentials_path_fails_with_placeholder
    write_local_credentials(value: '%{some_token}')

    stdout, stderr, status = run_script

    refute status.success?, stdout + stderr
    assert_match(/Unresolved placeholder\(s\) found/, stdout + stderr)
  end

  def test_local_credentials_path_fails_with_empty_placeholder
    write_local_credentials(value: '%{}')

    stdout, stderr, status = run_script

    refute status.success?, stdout + stderr
    assert_match(/Unresolved placeholder\(s\) found/, stdout + stderr)
  end

  def test_local_credentials_path_fails_with_typed_placeholder
    write_local_credentials(value: '%{some_token}', declaration: 'static let someKey: String')

    stdout, stderr, status = run_script

    refute status.success?, stdout + stderr
    assert_match(/Unresolved placeholder\(s\) found/, stdout + stderr)
  end

  def test_missing_xcode_environment_fails_with_named_error
    write_secrets(bitdrift_sdk_key: 'bitdrift-real', telemetry_deck_app_id: 'telemetry-real')

    stdout, stderr, status = run_script('BUILT_PRODUCTS_DIR' => nil)

    refute status.success?, stdout + stderr
    assert_match(/BUILT_PRODUCTS_DIR must be set by Xcode/, stdout + stderr)
  end

  private

  def run_script(env_overrides = {})
    env = {
      'SOURCE_ROOT' => @source_root,
      'SRCROOT' => @source_root,
      'BUILT_PRODUCTS_DIR' => @build_products_dir,
      'SECRETS_PATH' => @secrets_path,
      'RUBY_BIN' => RbConfig.ruby
    }.merge(env_overrides)

    Open3.capture3(env, 'bash', SCRIPT_PATH)
  end

  def generated_credentials
    File.read(File.expand_path('../DerivedSources/ApiCredentials.swift', @build_products_dir))
  end

  def write_secrets(bitdrift_sdk_key:, telemetry_deck_app_id:)
    File.write(
      @secrets_path,
      JSON.pretty_generate(
        'encrypted_log_key' => 'encrypted-log-key',
        'sharing_server_secret' => 'sharing-server-secret',
        'bitdrift_sdk_key' => bitdrift_sdk_key,
        'telemetry_deck_app_id' => telemetry_deck_app_id,
        'instagram_app_id' => 'instagram-app-id'
      )
    )
  end

  def write_local_credentials(value:, declaration: 'static let someKey')
    File.write(
      File.join(@credentials_dir, 'LocalApiCredentials.swift'),
      <<~SWIFT
        struct ApiCredentials {
            #{declaration} = "#{value}"
        }
      SWIFT
    )
  end
end
