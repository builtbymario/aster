#!/bin/zsh
# Encrypted iPhone ↔ Mac link tests through a real local relay (`pnpm start` in Aster-Relay).
# Optional argument: a private env file with OPENAI_API_KEY to also run one real OpenAI task.
set -eu
PROJECT_DIR="${0:A:h}"
curl -fsS --max-time 2 http://127.0.0.1:8787/health >/dev/null || { echo 'Arranca primero el relay local: pnpm start en outputs/Aster-Relay.' >&2; exit 1; }
ASTER_LIVE_ENV_FILE="${1:+${1:A}}" xcrun swift test --package-path "$PROJECT_DIR" --filter RemoteTests
