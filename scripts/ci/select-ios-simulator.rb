# frozen_string_literal: true

require 'json'

devices_json = ARGV[0] ? File.read(ARGV[0]) : `xcrun simctl list devices available --json`
devices_by_runtime = JSON.parse(devices_json).fetch('devices')
requested_runtime_version = ENV['IOS_SIMULATOR_RUNTIME_VERSION'].to_s.strip
requested_runtime_version = nil if requested_runtime_version.empty?
requested_runtime_version_components = requested_runtime_version&.split('.')&.map(&:to_i)
candidates = []
available_runtime_versions = []

devices_by_runtime.each do |runtime, devices|
  next unless runtime.include?('iOS')

  version = runtime.scan(/\d+/).map(&:to_i)
  version_string = version.join('.')
  runtime_has_available_iphone = false

  devices.each do |device|
    next unless device['isAvailable']
    next unless device['name'].start_with?('iPhone')

    runtime_has_available_iphone = true
    if requested_runtime_version_components &&
       version.take(requested_runtime_version_components.length) != requested_runtime_version_components
      next
    end

    preference = device['name'].include?(' Pro') ? 1 : 0
    candidates << [version, preference, device['name'], device['udid']]
  end

  available_runtime_versions << version_string if runtime_has_available_iphone
end

if candidates.empty?
  message = requested_runtime_version ? "No available iPhone simulator found for iOS #{requested_runtime_version}" : 'No available iPhone simulator found'
  unless available_runtime_versions.empty?
    message += ". Available iOS simulator runtimes: #{available_runtime_versions.uniq.join(', ')}"
  end
  abort(message)
end

selected = candidates.max_by { |version, preference, name, _udid| [version, preference, name] }
puts "platform=iOS Simulator,id=#{selected[3]}"
