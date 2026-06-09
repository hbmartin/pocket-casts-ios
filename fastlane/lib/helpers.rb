# frozen_string_literal: true

# Use this to ensure all env vars a lane requires are set.
#
# The best place to call this is at the start of a lane, to fail early.
def require_env_vars!(*keys)
  keys.each { |key| get_required_env!(key) }
end

# Use this instead of getting values from `ENV` directly. It will throw an error if the requested value is missing.
def get_required_env!(key, env_file_path: USER_ENV_FILE_PATH)
  return ENV.fetch(key) if ENV.key?(key)

  message = "Environment variable '#{key}' is not set."

  if is_ci
    UI.user_error!(message)
  elsif File.exist?(env_file_path)
    UI.user_error!("#{message} Consider adding it to #{env_file_path}.")
  else
    env_file_example_path = 'fastlane/example.env'
    env_file_dir = File.dirname(env_file_path)
    env_file_name = File.basename(env_file_path)

    UI.user_error! <<~MSG
      #{env_file_name} not found in #{env_file_dir}!

      Please copy #{env_file_example_path} to #{env_file_path} and fill in the values for the automation you require.

      mkdir -p #{env_file_dir} && cp #{env_file_example_path} #{env_file_path}
    MSG
  end
end

# Fails loudly to make it clear that the WordPress-backed translation sync is
# disabled.
#
# The GlotPress project that previously hosted the Pocket Casts iOS strings and
# App Store metadata has been removed. Until a replacement translation source is
# wired up, the lanes that downloaded localized strings/metadata or checked
# translation progress must fail explicitly rather than silently skip
# translation work.
def glotpress_translation_sync_disabled!
  UI.user_error! <<~MSG
    WordPress-backed translation sync is disabled.

    The GlotPress project that previously hosted these translations has been
    removed, so downloading localized strings/metadata and checking translation
    progress are no longer available. Implement a replacement translation source
    and re-enable these lanes before running the release/localization flow.
  MSG
end
