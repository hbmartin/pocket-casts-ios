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

set -e

cd "$(dirname "$0")/.."

# Install-if-missing only: never auto-upgrade, so codegen stays reproducible
# against whatever versions the developer has pinned.
if command -v brew &> /dev/null; then
    for pkg in protobuf swift-protobuf; do
        if ! brew list --formula "$pkg" &> /dev/null; then
            brew install "$pkg"
        fi
    done
else
    echo "Brew is not installed. Make sure protoc + protoc-gen-swift is installed."
fi

for tool in protoc protoc-gen-swift; do
    if ! command -v "$tool" &> /dev/null; then
        echo "Error: $tool is not installed or not on PATH. Install protobuf and swift-protobuf and try again."
        exit 1
    fi
done

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
