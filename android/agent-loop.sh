#!/data/data/com.termux/files/usr/bin/bash
# OfflineTweaker :: Android wrapper for the autonomous build loop.
#
# Thin wrapper around ../agent/build-loop.sh that fills in the local
# llama-server endpoint and the model alias for your device profile, so
# you don't have to remember the API base / model name each time.
#
# Prereqs: ~/run-model.sh already running in another Termux session
# (started via android/termux-setup.sh).
#
# Usage:
#   ./agent-loop.sh <pixel9a|motog5g> --dir <project-dir> --task "<task>" \
#                    [--test-cmd "<command>"] [--max-iters N]

set -e

PROFILE="${1:-}"
shift || true

# --map-tokens / --max-feedback-chars are tuned to leave room inside each
# profile's context window (4096 tokens on pixel9a, 2048 on motog5g) after
# Aider's repo map and the retry failure-feedback dump — see
# agent/build-loop.sh for what each flag controls.
case "$PROFILE" in
  pixel9a)
    MODEL_ALIAS="deepseek-r1-qwen-7b"
    MAP_TOKENS=512
    MAX_FEEDBACK_CHARS=3000
    ;;
  motog5g)
    MODEL_ALIAS="deepseek-r1-qwen-1.5b"
    MAP_TOKENS=0
    MAX_FEEDBACK_CHARS=1200
    ;;
  *)
    echo "Usage: $0 <pixel9a|motog5g> --dir <project-dir> --task \"<task>\" [--test-cmd \"<command>\"] [--max-iters N]"
    exit 1
    ;;
esac

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

exec "$SCRIPT_DIR/../agent/build-loop.sh" \
  --model "$MODEL_ALIAS" \
  --api-base "http://127.0.0.1:8080/v1" \
  --api-key "sk-local-no-key-required" \
  --map-tokens "$MAP_TOKENS" \
  --max-feedback-chars "$MAX_FEEDBACK_CHARS" \
  "$@"
