#!/usr/bin/env bash
# Generates an empty LocalApiCredentials.swift from the template so the app
# builds without access to the private service credentials.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOCAL_CREDENTIALS_PATH="$REPO_ROOT/podcasts/Credentials/LocalApiCredentials.swift"

cp "$REPO_ROOT/podcasts/Credentials/ApiCredentials.tpl" "$LOCAL_CREDENTIALS_PATH"
tmp_credentials_path="$(mktemp "${LOCAL_CREDENTIALS_PATH}.XXXXXX")"
trap 'rm -f "$tmp_credentials_path"' EXIT
sed -e 's/%%{/__ESCAPED_PLACEHOLDER_OPEN__/g' -e 's/%{[^}]*}//g' -e 's/__ESCAPED_PLACEHOLDER_OPEN__/%{/g' "$LOCAL_CREDENTIALS_PATH" > "$tmp_credentials_path"
mv "$tmp_credentials_path" "$LOCAL_CREDENTIALS_PATH"

echo "You're ready to build the app, go ahead! 🎙"
