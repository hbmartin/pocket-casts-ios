#!/usr/bin/env bash
# Generates an empty LocalApiCredentials.swift from the template so the app
# builds without access to the private service credentials.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOCAL_CREDENTIALS_PATH="$REPO_ROOT/podcasts/Credentials/LocalApiCredentials.swift"

cp "$REPO_ROOT/podcasts/Credentials/ApiCredentials.tpl" "$LOCAL_CREDENTIALS_PATH"
sed -i '' -e 's/%%{/__ESCAPED_PLACEHOLDER_OPEN__/g' -e 's/%{[^}]*}//g' -e 's/__ESCAPED_PLACEHOLDER_OPEN__/%{/g' "$LOCAL_CREDENTIALS_PATH"

echo "You're ready to build the app, go ahead! 🎙"
