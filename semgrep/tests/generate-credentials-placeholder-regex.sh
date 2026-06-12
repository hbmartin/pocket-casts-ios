#!/usr/bin/env bash

credentials_file=$1

# ruleid: pocketcasts.credential-placeholder-regex-allows-empty-token
placeholders=$(grep -E 'static let [a-zA-Z0-9_]+[^=]*=[[:space:]]*"%\{[^}]+\}"' "$credentials_file" || true)

# ruleid: pocketcasts.credential-placeholder-regex-allows-type-annotation
placeholders=$(grep -E 'static let [a-zA-Z0-9_]+[[:space:]]*=[[:space:]]*"%\{[^}]*\}"' "$credentials_file" || true)

# ok: pocketcasts.credential-placeholder-regex-allows-empty-token
# ok: pocketcasts.credential-placeholder-regex-allows-type-annotation
placeholders=$(grep -E 'static let [a-zA-Z0-9_]+[^=]*=[[:space:]]*"%\{[^}]*\}"' "$credentials_file" || true)

# ruleid: pocketcasts.shell-bsd-sed-in-place
sed -i '' -e 's/%{[^}]*}//g' "$credentials_file"

# ok: pocketcasts.shell-bsd-sed-in-place
sed -e 's/%{[^}]*}//g' "$credentials_file" > "$credentials_file.tmp"
