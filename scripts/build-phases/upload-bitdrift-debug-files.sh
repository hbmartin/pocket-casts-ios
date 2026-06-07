#!/usr/bin/env bash

set -eu -o pipefail

if [[ "${CONFIGURATION}" != "Release" ]]; then
    echo "Skipping Bitdrift debug file upload for configuration ${CONFIGURATION}"
    exit 0
fi

if [[ -z "${BITDRIFT_API_KEY:-}" ]]; then
    if [[ -n "${BUILDKITE:-}" || -n "${CI:-}" ]]; then
        echo "error: BITDRIFT_API_KEY is required to upload Release dSYMs to Bitdrift."
        exit 1
    fi

    echo "warning: BITDRIFT_API_KEY is not set; skipping Bitdrift debug file upload."
    exit 0
fi

if [[ "$(uname -m)" == arm64 ]]; then
    BD_ARCH=arm64
else
    BD_ARCH=x86_64
fi

BD_URL="https://dl.bitdrift.io/bd-cli/latest/bd-cli-mac-${BD_ARCH}.tar.gz/bd"
BD="${TEMP_DIR}/bd"
dsym_files=()

if [[ "${ENABLE_USER_SCRIPT_SANDBOXING:-NO}" == "YES" ]]; then
    if [[ "${SCRIPT_INPUT_FILE_COUNT:-0}" -le 0 ]]; then
        echo 'error: ENABLE_USER_SCRIPT_SANDBOXING is enabled. Add the dSYM binary to the build phase input files.'
        exit 1
    fi

    for ((n = 0; n < SCRIPT_INPUT_FILE_COUNT; n++)); do
        name="SCRIPT_INPUT_FILE_${n}"
        if [[ -f "${!name}" && "${!name}" == *".dSYM/Contents/Resources/DWARF/"* ]]; then
            dsym_files+=("${!name}")
        fi
    done
else
    dsym_files+=("${DWARF_DSYM_FOLDER_PATH}")
fi

if [[ ${#dsym_files[@]} -eq 0 ]]; then
    echo "Did not find any dSYM files to upload to Bitdrift."
    exit 0
fi

if [[ ! -f "$BD" ]]; then
    curl -fSL "$BD_URL" -o "$BD"
    curl -fSL "$BD_URL.sha256" -o "$BD.sha256" || {
        echo "error: Failed to download bd CLI checksum from $BD_URL.sha256"
        rm -f "$BD"
        exit 1
    }

    expected_checksum="$(cat "$BD.sha256")"
    actual_checksum="$(shasum -a 256 "$BD" | awk '{print $1}')"

    if [[ "$expected_checksum" != "$actual_checksum" ]]; then
        echo "error: bd CLI checksum verification failed"
        echo "Expected: $expected_checksum"
        echo "Actual:   $actual_checksum"
        rm -f "$BD" "$BD.sha256"
        exit 1
    fi

    chmod a+x "$BD"
    rm -f "$BD.sha256"
fi

for path in "${dsym_files[@]}"; do
    echo "Uploading to Bitdrift: $path"
    "$BD" debug-files upload --api-key="$BITDRIFT_API_KEY" "$path"
done
