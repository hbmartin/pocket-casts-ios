# frozen_string_literal: true

class GenerateCredentialsEnvTest
  def unsafe_run_script(env_overrides = {})
    # ruleid: pocketcasts.generate-credentials-test-preserve-nil-env-unsets
    env = {
      'BUILT_PRODUCTS_DIR' => '/tmp/build-products',
      'SOURCE_ROOT' => '/tmp/source'
    }.merge(env_overrides).compact

    Open3.capture3(env, 'bash', 'script.sh')
  end

  def safe_run_script(env_overrides = {})
    # ok: pocketcasts.generate-credentials-test-preserve-nil-env-unsets
    env = {
      'BUILT_PRODUCTS_DIR' => '/tmp/build-products',
      'SOURCE_ROOT' => '/tmp/source'
    }.merge(env_overrides)

    Open3.capture3(env, 'bash', 'script.sh')
  end
end
