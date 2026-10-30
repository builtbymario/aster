#!/bin/zsh
# Development loop: incremental debug build, bundled and signed like build.sh, then opened.
# Debug builds accept a local ws:// relay for testing; release builds require wss://.
set -eu
PROJECT_DIR="${0:A:h}"
APP_DIR="${ASTER_APP_DIR:-${PROJECT_DIR:h}/Aster.app}"
if pgrep -f "$APP_DIR/Contents/MacOS/Aster" >/dev/null; then
  osascript -e "tell application \"$APP_DIR\" to quit"
  while pgrep -f "$APP_DIR/Contents/MacOS/Aster" >/dev/null; do sleep 0.2; done
fi
ASTER_CONFIGURATION=debug ASTER_APP_DIR="$APP_DIR" zsh "$PROJECT_DIR/build.sh"
open "$APP_DIR"
