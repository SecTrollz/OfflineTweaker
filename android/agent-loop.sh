#!/data/data/com.termux/files/usr/bin/bash
# OfflineTweaker :: Android wrapper for the autonomous build loop.
#
# Thin wrapper around ../agent/build-loop.sh that reads the profile saved by
# android/termux-setup.sh (model alias, context-budget flags) so you don't
# have to remember or re-specify them each time. Whatever tier
# termux-setup.sh last set up is what runs.
#
# Prereqs: ~/run-model.sh already running in another Termux session
# (started via android/termux-setup.sh).
#
# Usage:
#   ./agent-loop.sh --dir <project-dir> --task "<task>" \
#                    [--test-cmd "<command>"] [--max-iters N]

set -e

PROFILE_FILE="$HOME/.offlinetweaker/profile.env"

if [ ! -f "$PROFILE_FILE" ]; then
  echo "No OfflineTweaker profile found at $PROFILE_FILE." >&2
  echo "Run android/termux-setup.sh first to detect your device's tier and download a model." >&2
  exit 1
fi

# shellcheck source=/dev/null
. "$PROFILE_FILE"

if [ -z "${MODEL_ALIAS:-}" ]; then
  echo "Profile at $PROFILE_FILE is missing MODEL_ALIAS. Re-run android/termux-setup.sh." >&2
  exit 1
fi

echo "Using saved profile: ${DEVICE_TIER:-unknown tier} -> ${MODEL_LABEL:-$MODEL_ALIAS}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

exec "$SCRIPT_DIR/../agent/build-loop.sh" \
  --model "$MODEL_ALIAS" \
  --api-base "http://127.0.0.1:8080/v1" \
  --api-key "sk-local-no-key-required" \
  --map-tokens "${MAP_TOKENS:-0}" \
  --max-feedback-chars "${MAX_FEEDBACK_CHARS:-2000}" \
  "$@"
