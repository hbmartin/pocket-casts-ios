#!/usr/bin/env bash

# Regenerates the Swift protobuf files for the PocketCastsFileSync module from
# the vendored .proto sources in Modules/Sources/PocketCastsFileSync/Proto.
#
# Unlike update_proto.sh (which pulls schemas from the pocketcasts-api repo),
# the file-sync schemas are vendored in this repository so the on-disk sync
# format outlives any server: sync_records.proto is a reconstruction of the
# upstream record schema plus fork extensions, and filesync.proto is the
# file-sync envelope/snapshot format.
#
# The checked-in Generated/ files were bootstrapped by hand from the server
# module's generated code; running this script on a machine with protoc +
# protoc-gen-swift replaces them with authoritative output. Field numbers and
# types must never change once shipped — see the contract notes in the .proto
# files.

set -euo pipefail

cd "$(dirname "$0")/.."

REQUIRED_PROTOC_VERSION="${FILESYNC_PROTOC_VERSION:-libprotoc 35.1}"
REQUIRED_PROTOC_GEN_SWIFT_VERSION="${FILESYNC_PROTOC_GEN_SWIFT_VERSION:-1.36.1}"

for tool in protoc protoc-gen-swift; do
    if ! command -v "$tool" &> /dev/null; then
        echo "Error: $tool is not installed or not on PATH."
        echo "Install the pinned protobuf tools, then re-run:"
        echo "  protoc: $REQUIRED_PROTOC_VERSION"
        echo "  protoc-gen-swift: $REQUIRED_PROTOC_GEN_SWIFT_VERSION"
        exit 1
    fi
done

actual_protoc_version="$(protoc --version)"
if [[ "$actual_protoc_version" != "$REQUIRED_PROTOC_VERSION" ]]; then
    echo "Error: expected protoc $REQUIRED_PROTOC_VERSION but found $actual_protoc_version."
    echo "Set FILESYNC_PROTOC_VERSION only when intentionally regenerating with a reviewed tool version."
    exit 1
fi

actual_protoc_gen_swift_version="$(protoc-gen-swift --version)"
if [[ "$actual_protoc_gen_swift_version" != *"$REQUIRED_PROTOC_GEN_SWIFT_VERSION"* ]]; then
    echo "Error: expected protoc-gen-swift $REQUIRED_PROTOC_GEN_SWIFT_VERSION but found $actual_protoc_gen_swift_version."
    echo "Set FILESYNC_PROTOC_GEN_SWIFT_VERSION only when intentionally regenerating with a reviewed tool version."
    exit 1
fi

PROTO_DIR=./Modules/Sources/PocketCastsFileSync/Proto
PROTO_OUT=./Modules/Sources/PocketCastsFileSync/Generated

# Visibility=Public because these types are the module's public surface;
# FileNaming=DropPath keeps flat output names in Generated/.
protoc \
    --swift_out="$PROTO_OUT" \
    --swift_opt=Visibility=Public \
    --swift_opt=FileNaming=DropPath \
    --proto_path="$PROTO_DIR" \
    "$PROTO_DIR/sync_records.proto" \
    "$PROTO_DIR/filesync.proto"

echo "Generated files written to $PROTO_OUT"
echo "NOTE: sync_records.proto intentionally regenerates the same wire format"
echo "as PocketCastsServer's api.pb.swift; run the proto compatibility tests"
echo "(PocketCastsServerTests/FileSyncProtoCompatibilityTests) after regenerating."
