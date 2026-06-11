# frozen_string_literal: true

require 'json'
require 'minitest/autorun'
require 'open3'
require 'rbconfig'
require 'tempfile'

class SelectIosSimulatorTest < Minitest::Test
  REPO_ROOT = File.expand_path('../..', __dir__)
  SCRIPT_PATH = File.join(REPO_ROOT, 'scripts/ci/select-ios-simulator.rb')

  def test_blank_requested_runtime_uses_latest_available_iphone
    stdout, stderr, status = run_script('IOS_SIMULATOR_RUNTIME_VERSION' => '')

    assert status.success?, stdout + stderr
    assert_equal "platform=iOS Simulator,id=ios-26-pro-max\n", stdout
  end

  def test_unset_requested_runtime_uses_latest_available_iphone
    stdout, stderr, status = run_script({})

    assert status.success?, stdout + stderr
    assert_equal "platform=iOS Simulator,id=ios-26-pro-max\n", stdout
  end

  def test_requested_runtime_uses_matching_iphone
    stdout, stderr, status = run_script('IOS_SIMULATOR_RUNTIME_VERSION' => '18.6.1')

    assert status.success?, stdout + stderr
    assert_equal "platform=iOS Simulator,id=ios-18-pro-max\n", stdout
  end

  def test_requested_runtime_matches_available_patch_version
    stdout, stderr, status = run_script('IOS_SIMULATOR_RUNTIME_VERSION' => '18.6')

    assert status.success?, stdout + stderr
    assert_equal "platform=iOS Simulator,id=ios-18-pro-max\n", stdout
  end

  def test_requested_runtime_ignores_surrounding_whitespace
    stdout, stderr, status = run_script('IOS_SIMULATOR_RUNTIME_VERSION' => ' 18.6 ')

    assert status.success?, stdout + stderr
    assert_equal "platform=iOS Simulator,id=ios-18-pro-max\n", stdout
  end

  def test_unavailable_requested_runtime_lists_available_versions
    stdout, stderr, status = run_script('IOS_SIMULATOR_RUNTIME_VERSION' => '18.5')

    refute status.success?, stdout + stderr
    assert_match(/No available iPhone simulator found for iOS 18\.5/, stderr)
    assert_match(/Available iOS simulator runtimes: 18\.6\.1, 26\.5/, stderr)
  end

  private

  def run_script(env)
    Tempfile.create(['simctl-devices', '.json']) do |file|
      file.write(devices_json)
      file.close

      Open3.capture3({ 'IOS_SIMULATOR_RUNTIME_VERSION' => nil }.merge(env), RbConfig.ruby, SCRIPT_PATH, file.path)
    end
  end

  def devices_json
    JSON.generate(
      'devices' => {
        'com.apple.CoreSimulator.SimRuntime.iOS-18-6-1' => [
          {
            'name' => 'iPhone 16',
            'udid' => 'ios-18',
            'isAvailable' => true
          },
          {
            'name' => 'iPhone 16 Pro Max',
            'udid' => 'ios-18-pro-max',
            'isAvailable' => true
          }
        ],
        'com.apple.CoreSimulator.SimRuntime.iOS-26-5' => [
          {
            'name' => 'iPhone 17',
            'udid' => 'ios-26',
            'isAvailable' => true
          },
          {
            'name' => 'iPhone 17 Pro Max',
            'udid' => 'ios-26-pro-max',
            'isAvailable' => true
          },
          {
            'name' => 'iPad Pro',
            'udid' => 'ipad-26-pro',
            'isAvailable' => true
          }
        ],
        'com.apple.CoreSimulator.SimRuntime.watchOS-26-5' => [
          {
            'name' => 'Apple Watch',
            'udid' => 'watch-26',
            'isAvailable' => true
          }
        ]
      }
    )
  end
end
