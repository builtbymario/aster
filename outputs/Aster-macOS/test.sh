#!/bin/zsh
# Runs every XCTest suite. Extra arguments go to `swift test`, e.g. `zsh test.sh --filter ComputerTests`.
# The relay round trip is skipped unless a local relay is running; see test-remote.sh.
set -eu
PROJECT_DIR="${0:A:h}"
xcrun swift test --package-path "$PROJECT_DIR" "$@"
