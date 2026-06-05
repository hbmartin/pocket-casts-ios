#!/usr/bin/env bash
set -euo pipefail

buildkite-agent pipeline upload .buildkite/pipeline.yml
