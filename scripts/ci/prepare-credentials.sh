#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

DEFAULT_SECRETS_PATH="$HOME/.configure/pocketcasts-ios/secrets/pocket_casts_credentials.json"
SECRETS_PATH="${SECRETS_PATH:-$DEFAULT_SECRETS_PATH}"
LOCAL_CREDENTIALS_PATH="$REPO_ROOT/podcasts/Credentials/LocalApiCredentials.swift"

generate_open_source_credentials() {
  echo "Generating open-source credentials"
  make -C "$REPO_ROOT" external_contributor
}

if [[ -n "${POCKET_CASTS_CREDENTIALS_JSON:-}" ]]; then
  echo "Writing service credentials from POCKET_CASTS_CREDENTIALS_JSON"
  if ! printf '%s' "$POCKET_CASTS_CREDENTIALS_JSON" | /usr/bin/ruby -rjson -e '
    required_keys = %w[
      zendesk_api_key
      zendesk_url
      zendesk_new_url
      dotcom_secret
      encrypted_log_key
      sharing_server_secret
      bitdrift_sdk_key
      telemetry_deck_app_id
      instagram_app_id
    ]

    begin
      secrets = JSON.parse(STDIN.read)
    rescue JSON::ParserError
      warn "POCKET_CASTS_CREDENTIALS_JSON must be valid JSON."
      exit 1
    end

    unless secrets.is_a?(Hash)
      warn "POCKET_CASTS_CREDENTIALS_JSON must be a JSON object."
      exit 1
    end

    missing_keys = required_keys.reject { |key| secrets.key?(key) }
    unless missing_keys.empty?
      warn "POCKET_CASTS_CREDENTIALS_JSON is missing required keys: #{missing_keys.join(", ")}"
      exit 1
    end
  '; then
    exit 1
  fi

  mkdir -p "$(dirname "$SECRETS_PATH")"
  umask 077
  printf '%s' "$POCKET_CASTS_CREDENTIALS_JSON" > "$SECRETS_PATH"

  rm -f "$LOCAL_CREDENTIALS_PATH"
  echo "Service credentials are ready at $SECRETS_PATH"
  exit 0
fi

if [[ "${GITHUB_ACTIONS:-}" == "true" ]]; then
  generate_open_source_credentials
  exit 0
fi

if [[ -f "$SECRETS_PATH" ]]; then
  echo "Using existing service credentials at $SECRETS_PATH"
  rm -f "$LOCAL_CREDENTIALS_PATH"
  exit 0
fi

generate_open_source_credentials
