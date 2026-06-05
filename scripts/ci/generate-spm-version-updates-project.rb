#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"

def usage
  warn "Usage: #{$PROGRAM_NAME} <Package.swift>... <Output.xcodeproj>"
  exit 1
end

usage if ARGV.length < 2

manifest_paths = ARGV[0...-1]
output_project_path = ARGV[-1]

def package_argument_lists(source)
  lists = []
  offset = 0

  while (start = source.index(".package(", offset))
    cursor = start + ".package(".length
    argument_start = cursor
    depth = 1
    in_string = false
    escaped = false

    while cursor < source.length && depth.positive?
      depth, in_string, escaped = next_package_scan_state(source[cursor], depth, in_string, escaped)
      cursor += 1
    end

    raise ArgumentError, "Unterminated .package declaration near byte #{start}" if depth.positive?

    lists << source[argument_start...(cursor - 1)]
    offset = cursor
  end

  lists
end

def next_package_scan_state(character, depth, in_string, escaped)
  if in_string
    return [depth, in_string, false] if escaped
    return [depth, in_string, true] if character == "\\"
    return [depth, false, escaped] if character == "\""

    return [depth, in_string, escaped]
  end

  case character
  when "\""
    [depth, true, escaped]
  when "("
    [depth + 1, in_string, escaped]
  when ")"
    [depth - 1, in_string, escaped]
  else
    [depth, in_string, escaped]
  end
end

def swiftlint_version(manifest_path)
  config_path = File.expand_path("../.swiftlint.yml", File.dirname(manifest_path))
  line = File.readlines(config_path).find { |entry| entry.match?(/swiftlint_version:/) }
  version = line&.split(":")&.last&.strip
  raise ArgumentError, "Unable to find swiftlint_version in #{config_path}" if version.nil? || version.empty?

  version
end

def requirement_for(arguments, manifest_path)
  if (version = arguments[/from:\s*"([^"]+)"/, 1])
    { "kind" => "upToNextMajorVersion", "minimumVersion" => version }
  elsif (version = arguments[/exact:\s*"([^"]+)"/, 1])
    { "kind" => "exactVersion", "version" => version }
  elsif arguments.match?(/exact:\s*loadSwiftLintVersion\(\)/)
    { "kind" => "exactVersion", "version" => swiftlint_version(manifest_path) }
  elsif (branch = arguments[/branch:\s*"([^"]+)"/, 1])
    { "kind" => "branch", "branch" => branch }
  elsif (revision = arguments[/revision:\s*"([^"]+)"/, 1])
    { "kind" => "revision", "revision" => revision }
  elsif (range = arguments.match(/"([^"]+)"\s*\.\.<\s*"([^"]+)"/))
    { "kind" => "versionRange", "minimumVersion" => range[1], "maximumVersion" => range[2] }
  elsif (range = arguments.match(/"([^"]+)"\s*\.\.\.\s*"([^"]+)"/))
    { "kind" => "versionRange", "minimumVersion" => range[1], "maximumVersion" => range[2] }
  end
end

def pbx_id(seed)
  Digest::SHA1.hexdigest(seed).upcase[0, 24]
end

def quoted(value)
  return value if value.match?(/\A[A-Za-z0-9_.$\/:-]+\z/)

  "\"#{value.gsub("\\", "\\\\\\").gsub("\"", "\\\"")}\""
end

def serialize_requirement(requirement)
  entries = requirement.map { |key, value| "#{key} = #{quoted(value)};" }
  "{ #{entries.join(" ")} }"
end

dependencies = manifest_paths.flat_map do |manifest_path|
  source = File.read(manifest_path)

  package_argument_lists(source).map do |arguments|
    url = arguments[/url:\s*"([^"]+)"/, 1]
    next if url.nil?

    requirement = requirement_for(arguments, manifest_path)
    raise ArgumentError, "Unsupported package requirement in #{manifest_path}: #{arguments.strip}" if requirement.nil?

    [url, requirement]
  end.compact
end

dependencies_by_url = dependencies.to_h
raise ArgumentError, "No package dependencies found" if dependencies_by_url.empty?

resolved_pins_by_location = {}

manifest_paths.each do |manifest_path|
  resolved_path = File.join(File.dirname(manifest_path), "Package.resolved")
  next unless File.exist?(resolved_path)

  contents = JSON.parse(File.read(resolved_path))
  pins = contents["pins"] || contents.dig("object", "pins") || []

  pins.each do |pin|
    location = pin["location"] || pin["repositoryURL"]
    next if location.nil?

    resolved_pins_by_location[location] = pin
  end
end

FileUtils.rm_rf(output_project_path)
FileUtils.mkdir_p(output_project_path)
FileUtils.mkdir_p(File.join(output_project_path, "project.xcworkspace", "xcshareddata", "swiftpm"))

main_group_id = pbx_id("main-group")
products_group_id = pbx_id("products-group")
project_id = pbx_id("project")
config_list_id = pbx_id("config-list")
debug_config_id = pbx_id("debug-config")
release_config_id = pbx_id("release-config")

package_objects = dependencies_by_url.map.with_index do |(url, requirement), index|
  name = File.basename(url.delete_suffix(".git"))
  id = pbx_id("package-#{index}-#{url}")

  <<~PACKAGE
  \t\t#{id} /* #{name} */ = {
  \t\t\tisa = XCRemoteSwiftPackageReference;
  \t\t\trepositoryURL = #{quoted(url)};
  \t\t\trequirement = #{serialize_requirement(requirement)};
  \t\t};
  PACKAGE
end

package_references = dependencies_by_url.map.with_index do |(url, _requirement), index|
  name = File.basename(url.delete_suffix(".git"))
  "\t\t\t\t#{pbx_id("package-#{index}-#{url}")} /* #{name} */,"
end

project_file = <<~PBXPROJ
// !$*UTF8*$!
{
\tarchiveVersion = 1;
\tclasses = {
\t};
\tobjectVersion = 56;
\tobjects = {

/* Begin PBXGroup section */
\t\t#{main_group_id} = {
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
\t\t\t);
\t\t\tsourceTree = "<group>";
\t\t};
\t\t#{products_group_id} /* Products */ = {
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
\t\t\t);
\t\t\tname = Products;
\t\t\tsourceTree = "<group>";
\t\t};
/* End PBXGroup section */

/* Begin PBXProject section */
\t\t#{project_id} /* Project object */ = {
\t\t\tisa = PBXProject;
\t\t\tattributes = {
\t\t\t\tLastSwiftUpdateCheck = 1600;
\t\t\t\tLastUpgradeCheck = 1600;
\t\t\t};
\t\t\tbuildConfigurationList = #{config_list_id} /* Build configuration list for PBXProject "PackageChecks" */;
\t\t\tcompatibilityVersion = "Xcode 16.0";
\t\t\tdevelopmentRegion = en;
\t\t\thasScannedForEncodings = 0;
\t\t\tknownRegions = (
\t\t\t\ten,
\t\t\t);
\t\t\tmainGroup = #{main_group_id};
\t\t\tpackageReferences = (
#{package_references.join("\n")}
\t\t\t);
\t\t\tpreferredProjectObjectVersion = 77;
\t\t\tproductRefGroup = #{products_group_id} /* Products */;
\t\t\tprojectDirPath = "";
\t\t\tprojectRoot = "";
\t\t\ttargets = (
\t\t\t);
\t\t};
/* End PBXProject section */

/* Begin XCBuildConfiguration section */
\t\t#{debug_config_id} /* Debug */ = {
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {
\t\t\t};
\t\t\tname = Debug;
\t\t};
\t\t#{release_config_id} /* Release */ = {
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {
\t\t\t};
\t\t\tname = Release;
\t\t};
/* End XCBuildConfiguration section */

/* Begin XCConfigurationList section */
\t\t#{config_list_id} /* Build configuration list for PBXProject "PackageChecks" */ = {
\t\t\tisa = XCConfigurationList;
\t\t\tbuildConfigurations = (
\t\t\t\t#{debug_config_id} /* Debug */,
\t\t\t\t#{release_config_id} /* Release */,
\t\t\t);
\t\t\tdefaultConfigurationIsVisible = 0;
\t\t\tdefaultConfigurationName = Release;
\t\t};
/* End XCConfigurationList section */

/* Begin XCRemoteSwiftPackageReference section */
#{package_objects.join("\n")}
/* End XCRemoteSwiftPackageReference section */
\t};
\trootObject = #{project_id} /* Project object */;
}
PBXPROJ

File.write(File.join(output_project_path, "project.pbxproj"), project_file)

resolved_file = {
  "pins" => resolved_pins_by_location.values.sort_by { |pin| pin["identity"] || pin["location"] || pin["repositoryURL"] },
  "version" => 3,
}

resolved_output_path = File.join(output_project_path, "project.xcworkspace", "xcshareddata", "swiftpm", "Package.resolved")
File.write(resolved_output_path, JSON.pretty_generate(resolved_file))

puts "Generated #{output_project_path} with #{dependencies_by_url.size} package references"
