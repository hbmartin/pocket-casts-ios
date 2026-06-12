# frozen_string_literal: true

require 'json'

devices_json = ARGV[0] ? File.read(ARGV[0]) : `xcrun simctl list devices available --json`
devices_by_runtime = JSON.parse(devices_json).fetch('devices')
requested_runtime_version = ENV['IOS_SIMULATOR_RUNTIME_VERSION'].to_s.strip
requested_runtime_version = ENV['SIMULATOR_OS'].to_s.strip if requested_runtime_version.empty?
requested_runtime_version = nil if requested_runtime_version.empty?
requested_runtime_version_components = requested_runtime_version&.split('.')&.map(&:to_i)
requested_simulator_name = ENV['SIMULATOR_NAME'].to_s.strip
requested_simulator_name = nil if requested_simulator_name.empty?
candidates = []
available_runtime_versions = []

devices_by_runtime.each do |runtime, devices|
  next unless runtime.include?('iOS')

  version = runtime.scan(/\d+/).map(&:to_i)
  version_string = version.join('.')
  runtime_has_candidate_device = false

  devices.each do |device|
    next unless device['isAvailable']

    is_iphone = device['name'].start_with?('iPhone')

    # An explicit SIMULATOR_NAME may target any device type (e.g. an iPad);
    # without one, only iPhones are considered. The same scope decides which
    # runtimes the not-found error lists as available.
    if requested_simulator_name
      runtime_has_candidate_device = true
      next unless device['name'] == requested_simulator_name
    else
      runtime_has_candidate_device = true if is_iphone
      next unless is_iphone
    end

    if requested_runtime_version_components &&
       version.take(requested_runtime_version_components.length) != requested_runtime_version_components
      next
    end

    preference = device['name'].include?(' Pro') ? 1 : 0
    candidates << [version, preference, device['name'], device['udid']]
  end

  available_runtime_versions << version_string if runtime_has_candidate_device
end

if candidates.empty?
  device_description = requested_simulator_name ? "simulator named #{requested_simulator_name}" : 'iPhone simulator'
  message = "No available #{device_description} found"
  message += " for iOS #{requested_runtime_version}" if requested_runtime_version
  unless available_runtime_versions.empty?
    message += ". Available iOS simulator runtimes: #{available_runtime_versions.uniq.join(', ')}"
  end
  abort(message)
end

selected = candidates.max_by { |version, preference, name, _udid| [version, preference, name] }
puts "platform=iOS Simulator,id=#{selected[3]}"
