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

  def test_requested_simulator_name_can_include_parentheses
    stdout, stderr, status = run_script('SIMULATOR_OS' => '18.6.1', 'SIMULATOR_NAME' => 'iPhone SE (3rd generation)')

    assert status.success?, stdout + stderr
    assert_equal "platform=iOS Simulator,id=ios-18-se\n", stdout
  end

  def test_requested_simulator_name_can_target_non_iphone_devices
    stdout, stderr, status = run_script('SIMULATOR_NAME' => 'iPad Pro')

    assert status.success?, stdout + stderr
    assert_equal "platform=iOS Simulator,id=ipad-26-pro\n", stdout
  end

  def test_unknown_requested_simulator_name_reports_name_in_error
    stdout, stderr, status = run_script('SIMULATOR_NAME' => 'iPhone 99')

    refute status.success?, stdout + stderr
    assert_match(/No available simulator named iPhone 99 found/, stderr)
  end

  def test_unknown_requested_simulator_name_lists_runtimes_with_any_device
    stdout, stderr, status = run_script('SIMULATOR_NAME' => 'iPad Air 13-inch')

    refute status.success?, stdout + stderr
    assert_match(/Available iOS simulator runtimes: 17\.5, 18\.6\.1, 26\.5/, stderr)
  end

  def test_unavailable_requested_runtime_lists_available_versions
    stdout, stderr, status = run_script('IOS_SIMULATOR_RUNTIME_VERSION' => '18.5')

    refute status.success?, stdout + stderr
    assert_match(/No available iPhone simulator found for iOS 18\.5/, stderr)
    assert_match(/Available iOS simulator runtimes: 18\.6\.1, 26\.5/, stderr)
    refute_match(/17\.5/, stderr, 'iPad-only runtimes must not be listed for iPhone requests')
  end

  private

  def run_script(env)
    Tempfile.create(['simctl-devices', '.json']) do |file|
      file.write(devices_json)
      file.close

      Open3.capture3(
        { 'IOS_SIMULATOR_RUNTIME_VERSION' => nil, 'SIMULATOR_OS' => nil, 'SIMULATOR_NAME' => nil }.merge(env),
        RbConfig.ruby,
        SCRIPT_PATH,
        file.path
      )
    end
  end

  def devices_json
    JSON.generate(
      'devices' => {
        'com.apple.CoreSimulator.SimRuntime.iOS-17-5' => [
          {
            'name' => 'iPad mini (6th generation)',
            'udid' => 'ipad-17-mini',
            'isAvailable' => true
          }
        ],
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
          },
          {
            'name' => 'iPhone SE (3rd generation)',
            'udid' => 'ios-18-se',
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
