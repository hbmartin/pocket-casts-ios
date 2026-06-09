#!/usr/bin/env bash

set -euo pipefail

DERIVED_PATH=${BUILT_PRODUCTS_DIR}/../DerivedSources
SCRIPT_PATH=${SOURCE_ROOT}/podcasts/Credentials/replace_secrets.rb
RUBY_BIN=${RUBY_BIN:-ruby}

CREDS_INPUT_PATH=${SOURCE_ROOT}/podcasts/Credentials/ApiCredentials.tpl
LOCAL_SECRETS_FILE="${SRCROOT}/podcasts/Credentials/LocalApiCredentials.swift"
CREDS_OUTPUT_PATH=${DERIVED_PATH}/ApiCredentials.swift

validate_credentials() {
    local credentials_file=$1
    local placeholders

    # Find any lines that look like: static let someKey = "%{token}"
    # and extract the value part.
    placeholders=$(grep -E 'static let [a-zA-Z0-9_]+[[:space:]]*=[[:space:]]*"%\{[^}]+\}"' "$credentials_file" || true)

    if [[ -n "$placeholders" ]]; then
        echo "error: Unresolved placeholder(s) found in ${credentials_file}:" >&2
        echo "$placeholders" | sed 's/^/  /' >&2
        echo "error: Rerun \`make external_contributor\` or regenerate credentials with \`bundle exec fastlane run configure_apply\`." >&2
        exit 1
    fi
}

mkdir -p "$DERIVED_PATH"

# If the developer has a local secrets file, use it
if [ -f "$LOCAL_SECRETS_FILE" ]; then
    echo "warning: Using local Secrets from $LOCAL_SECRETS_FILE. If you are an external contributor, this is expected and you can ignore this warning. If you are an internal contributor, make sure to use our shared credentials instead."
    echo "Applying Local Secrets"
    cp -v "$LOCAL_SECRETS_FILE" "${CREDS_OUTPUT_PATH}"
    validate_credentials "$CREDS_OUTPUT_PATH"
    exit 0
fi

## Validate Secrets!
##
if [ ! -f "${SECRETS_PATH:-}" ]; then
    echo "error: SECRETS_PATH not found! Please run \`bundle exec fastlane run configure_apply\`."
    exit 1
else
    echo ">> Loading Secrets from ${SECRETS_PATH}"

    ## Generate ApiCredentials.swift
    ##
    echo ">> Generating Credentials ${CREDS_OUTPUT_PATH}"
    "$RUBY_BIN" "${SCRIPT_PATH}" -i "${CREDS_INPUT_PATH}" -s "${SECRETS_PATH}" > "${CREDS_OUTPUT_PATH}"
    validate_credentials "$CREDS_OUTPUT_PATH"
fi
