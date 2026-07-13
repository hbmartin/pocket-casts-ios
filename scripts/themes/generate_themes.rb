# frozen_string_literal: true

# Generate iOS theme colours from exported CSV from Google Sheet
# To use: ruby generate_themes.rb themes.csv
#
# Emits:
#   podcasts/Theme/ThemeColors.json - per-token, per-theme colours for the simple tokens,
#                                     loaded at runtime by ThemeColorTable
#   podcasts/ThemeColor.swift       - accessors; simple tokens delegate to ThemeColorTable,
#                                     while the parameterized podcast*/playerBackground*/
#                                     playerHighlight*/filter* families keep their generated
#                                     overlay colour math
#   podcasts/ThemeStyle.swift       - the token enum
require 'csv'
require 'json'

file_path_colors = './podcasts/ThemeColor.swift'
file_path_styles = './podcasts/ThemeStyle.swift'
file_path_json = './podcasts/Theme/ThemeColors.json'

class String
  def uncapitalize
    self[0, 1].downcase + self[1..]
  end
end

# Theme name used in generated identifiers => key used in ThemeColors.json.
# The JSON keys match the ThemeType case names; the classic theme reads the
# "Classic Light" CSV columns.
THEME_JSON_KEYS = {
  'Light' => 'light',
  'Dark' => 'dark',
  'ExtraDark' => 'extraDark',
  'ClassicLight' => 'classic',
  'Electric' => 'electric',
  'Indigo' => 'indigo',
  'Rosé' => 'rosé',
  'ContrastLight' => 'contrastLight',
  'ContrastDark' => 'contrastDark'
}.freeze

def filter_token?(token_name)
  token_name.start_with?('filterU', 'filterI', 'filterT')
end

def podcast_token?(token_name)
  token_name.start_with?('podcast', 'playerBackground', 'playerHighlight')
end

# The filter/podcast families take a parameter colour at runtime, so they stay as
# generated code instead of moving into the JSON table.
def special_token?(token_name)
  filter_token?(token_name) || podcast_token?(token_name)
end

# Returns the generated per-theme Swift function for a filter/podcast family token.
def special_theme_function(hex_val, opacity, token_name, theme_name)
  if filter_token?(token_name)
    str = ''
    # deal with special filter overlay colours
    if ['filter', '$filter', '#filter'].include?(hex_val)
      # the ones without any custom opacity are easy
      if opacity == '100%' || opacity.nil? || opacity.empty?
        str = "
    static func #{token_name}#{theme_name}(filterColor: UIColor) -> UIColor {
        filterColor
    }\n"
      else
        # tokenize the filter colour to figure out what it should be
        # example string: filter 15% on white
        words = opacity.split

        actual_opacity = words[1].gsub('%', '')
        original_color = if words[3] == 'white'
                           'UIColor(hex: "#FFFFFF")'
                         elsif words[3].start_with?('#')
                           "UIColor(hex: \"#{words[3]}\")"
                         else
                           'UIColor(hex: "#000000")'
                         end
        overlay_color = "filterColor.withAlphaComponent(#{actual_opacity.to_f / 100.0})"

        str = "
    static func #{token_name}#{theme_name}(filterColor: UIColor) -> UIColor {
        UIColor.calculateColor(orgColor: #{original_color}, overlayColor: #{overlay_color})
    }\n"
      end

    else
      str = "
    static func #{token_name}#{theme_name}(filterColor: UIColor) -> UIColor { UIColor(hex: \"#{hex_val}\") }\n"
    end

    return str
  end

  str = ''
  # deal with special podcast overlay colours
  if ['podcast', '$podcast', '#podcast'].include?(hex_val)
    # the ones without any custom opacity are easy
    if opacity == '100%' || opacity.nil? || opacity.empty?
      str = "
    static func #{token_name}#{theme_name}(podcastColor: UIColor) -> UIColor {\n        podcastColor\n    }\n"
    elsif opacity.split.size == 1
      opacity = opacity.gsub('%', '')
      str = "
    static func #{token_name}#{theme_name}(podcastColor: UIColor) -> UIColor {
        podcastColor.withAlphaComponent(#{opacity.to_f / 100.0})
    }\n"
    else
      # tokenize the podcast colour to figure out what it should be
      # example string: podcast 15% on #3D3D3D
      words = opacity.split

      actual_opacity = words[1].gsub('%', '')
      original_color = "UIColor(hex: \"#{words[3]}\")"
      overlay_color = "podcastColor.withAlphaComponent(#{actual_opacity.to_f / 100.0})"

      str = "
    static func #{token_name}#{theme_name}(podcastColor: UIColor) -> UIColor {
        UIColor.calculateColor(orgColor: #{original_color}, overlayColor: #{overlay_color})
    }\n"
    end
  elsif opacity == '100%' || opacity.nil? || opacity.empty?
    str = "
    static func #{token_name}#{theme_name}(podcastColor: UIColor) -> UIColor { UIColor(hex: \"#{hex_val}\") }\n"
  elsif opacity.split.size == 1
    opacity = opacity.gsub('%', '')
    str = "
    static func #{token_name}#{theme_name}(podcastColor: UIColor) -> UIColor {
        UIColor(hex: \"#{hex_val}\").withAlphaComponent(#{opacity.to_f / 100.0})
    }\n"
  end

  str
end

# Returns the ThemeColors.json value for a simple token: "#RRGGBB" when fully opaque,
# or {"hex": "#RRGGBB", "alpha": 0.5} when the CSV specifies an opacity. The alpha is
# kept as a decimal (not folded into the hex) so it stays exactly equal to the value
# the previous generated `.withAlphaComponent(...)` constants used.
def simple_theme_entry(hex_val, opacity, token_name)
  unless hex_val.start_with?('#')
    puts "Invalid hex value found #{hex_val}, found in #{token_name} ignoring"
    return nil
  end

  return hex_val if opacity == '100%' || opacity.nil? || opacity.empty?

  { 'hex' => hex_val, 'alpha' => opacity.gsub('%', '').to_f / 100.0 }
end

special_functions = +''
json_colors = {}
all_token_names = []

CSV.foreach(ARGV[0]) do |row|
  token_name = row[0]

  light_hex_value = row[2]
  light_opacity = row[3]

  dark_hex_value = row[4]
  dark_opacity = row[5]

  extra_dark_hex_value = row[6]
  extra_dark_opacity = row[7]

  classic_light_hex_value = row[8]
  classic_light_opacity = row[9]

  # These are unused but left here for reference and future use
  # classic_dark_hex_value = row[10]
  # classic_dark_opacity = row[11]

  electric_hex_value = row[12]
  electric_opacity = row[13]

  indigo_hex_value = row[14]
  indigo_opacity = row[15]

  rosé_hex_value = row[16]
  rosé_opacity = row[17]

  high_contrast_light_hex_value = row[18]
  high_contrast_light_opacity = row[19]

  high_contrast_dark_hex_value = row[20]
  high_contrast_dark_opacity = row[21]

  next if token_name.nil? || token_name == ' ' || token_name == 'Token' || light_hex_value.nil? || dark_hex_value.nil?

  token_name = token_name.gsub('$', '').split('-').collect(&:capitalize).join.uncapitalize
  all_token_names << token_name

  theme_values = [
    [light_hex_value, light_opacity, 'Light'],
    [dark_hex_value, dark_opacity, 'Dark'],
    [extra_dark_hex_value, extra_dark_opacity, 'ExtraDark'],
    [classic_light_hex_value, classic_light_opacity, 'ClassicLight'],
    [electric_hex_value, electric_opacity, 'Electric'],
    [indigo_hex_value, indigo_opacity, 'Indigo'],
    [rosé_hex_value, rosé_opacity, 'Rosé'],
    [high_contrast_light_hex_value, high_contrast_light_opacity, 'ContrastLight'],
    [high_contrast_dark_hex_value, high_contrast_dark_opacity, 'ContrastDark']
  ]

  if special_token?(token_name)
    theme_values.each do |hex_val, opacity, theme_name|
      special_functions << special_theme_function(hex_val, opacity, token_name, theme_name)
    end
  else
    entries = {}
    theme_values.each do |hex_val, opacity, theme_name|
      entry = simple_theme_entry(hex_val, opacity, token_name)
      entries[THEME_JSON_KEYS[theme_name]] = entry unless entry.nil?
    end
    json_colors[token_name] = entries
  end
end

accessors = +''
all_token_names.each do |token|
  token_str = if podcast_token?(token)
                "    static func #{token}(podcastColor: UIColor, for theme: Theme.ThemeType? = nil) -> UIColor {
        let theme = theme ?? Theme.sharedTheme.nonisolatedActiveTheme
        switch theme {
        case .light:
            return ThemeColor.#{token}Light(podcastColor: podcastColor)
        case .dark:
            return ThemeColor.#{token}Dark(podcastColor: podcastColor)
        case .extraDark:
            return ThemeColor.#{token}ExtraDark(podcastColor: podcastColor)
        case .electric:
            return ThemeColor.#{token}Electric(podcastColor: podcastColor)
        case .classic:
            return ThemeColor.#{token}ClassicLight(podcastColor: podcastColor)
        case .indigo:
            return ThemeColor.#{token}Indigo(podcastColor: podcastColor)
        case .rosé:
            return ThemeColor.#{token}Rosé(podcastColor: podcastColor)
        case .contrastLight:
            return ThemeColor.#{token}ContrastLight(podcastColor: podcastColor)
        case .contrastDark:
            return ThemeColor.#{token}ContrastDark(podcastColor: podcastColor)
        }
    }\n\n"
              elsif filter_token?(token)
                "    static func #{token}(filterColor: UIColor, for theme: Theme.ThemeType? = nil) -> UIColor {
        let theme = theme ?? Theme.sharedTheme.nonisolatedActiveTheme
        switch theme {
        case .light:
            return ThemeColor.#{token}Light(filterColor: filterColor)
        case .dark:
            return ThemeColor.#{token}Dark(filterColor: filterColor)
        case .extraDark:
            return ThemeColor.#{token}ExtraDark(filterColor: filterColor)
        case .electric:
            return ThemeColor.#{token}Electric(filterColor: filterColor)
        case .classic:
            return ThemeColor.#{token}ClassicLight(filterColor: filterColor)
        case .indigo:
            return ThemeColor.#{token}Indigo(filterColor: filterColor)
        case .rosé:
            return ThemeColor.#{token}Rosé(filterColor: filterColor)
        case .contrastLight:
            return ThemeColor.#{token}ContrastLight(filterColor: filterColor)
        case .contrastDark:
            return ThemeColor.#{token}ContrastDark(filterColor: filterColor)
        }
    }\n\n"
              else
                "    static func #{token}(for theme: Theme.ThemeType? = nil) -> UIColor {
        ThemeColorTable.color(\"#{token}\", for: theme ?? Theme.sharedTheme.nonisolatedActiveTheme)
    }\n\n"
              end
  accessors << token_str
end

colors_file = +"import PocketCastsUtils\nimport PocketCastsServer\nimport UIKit\n\n"
colors_file << "// ************ WARNING AUTO GENERATED, DO NOT EDIT ************\n"
colors_file << "// Simple tokens resolve through ThemeColorTable, backed by Theme/ThemeColors.json.\n"
colors_file << "nonisolated struct ThemeColor {\n"
colors_file << special_functions
colors_file << "\n\n"
colors_file << accessors
colors_file.sub!("ThemeColor {\n\n", "ThemeColor {\n") # no blank line after the opening brace
colors_file.sub!(/\n+\z/, "\n") # no blank lines before the closing brace
colors_file << "}\n"
File.write(file_path_colors, colors_file)

styles_file = +"// ************ WARNING AUTO GENERATED, DO NOT EDIT ************\nnonisolated enum ThemeStyle {\n"
all_token_names.each_with_index do |token, index|
  styles_file << if index.zero?
                   "    case #{token},\n"
                 else
                   "         #{token},\n"
                 end
end
styles_file.sub!(/,\n\z/, "\n") # remove the trailing comma
styles_file << "}\n"
File.write(file_path_styles, styles_file)

json_lines = json_colors.map do |token, entries|
  "  #{token.to_json}: #{JSON.generate(entries)}"
end
File.write(file_path_json, "{\n#{json_lines.join(",\n")}\n}\n")
