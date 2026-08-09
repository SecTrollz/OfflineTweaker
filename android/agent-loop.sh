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
# This runs unattended and auto-commits every edit (no review step, no
# sandbox on-device), so it prompts for confirmation before starting unless
# --yes/-y is passed (required for non-interactive/scripted use).
#
# Usage:
#   ./agent-loop.sh --dir <project-dir> --task "<task>" \
#                    [--test-cmd "<command>"] [--max-iters N] [--yes]

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

# build-loop.sh runs unattended and auto-commits every edit it makes
# (--yes-always --auto-commits, up to --max-iters rounds) with no sandbox on
# this path -- it's editing real files on the device directly. That's a
# different risk on a phone than on the Docker-isolated desktop stack, so
# require an explicit nod before it starts, unless the caller already knows
# what they're doing (--yes) or this isn't an interactive session anyway.
ASSUME_YES=0
ARGS=()
for arg in "$@"; do
  case "$arg" in
    --yes|-y) ASSUME_YES=1 ;;
    *) ARGS+=("$arg") ;;
  esac
done

if [ "$ASSUME_YES" -ne 1 ]; then
  echo
  echo "WARNING: this will let the model edit files in your project directory"
  echo "and auto-commit each attempt, unattended, for up to --max-iters rounds --"
  echo "there is no review step and no sandbox on this path."
  if [ -t 0 ]; then
    read -r -p "Proceed? [y/N] " reply
    case "$reply" in
      y|Y|yes|YES) ;;
      *) echo "Aborted. Pass --yes to skip this prompt next time." >&2; exit 1 ;;
    esac
  else
    echo "Non-interactive session and no --yes given -- aborting rather than running unattended silently." >&2
    exit 1
  fi
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

exec "$SCRIPT_DIR/../agent/build-loop.sh" \
  --model "$MODEL_ALIAS" \
  --api-base "http://127.0.0.1:8080/v1" \
  --api-key "sk-local-no-key-required" \
  --map-tokens "${MAP_TOKENS:-0}" \
  --max-feedback-chars "${MAX_FEEDBACK_CHARS:-2000}" \
  "${ARGS[@]}"
