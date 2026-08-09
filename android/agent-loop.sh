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

case "$PROFILE" in
  pixel9a) MODEL_ALIAS="deepseek-r1-qwen-7b" ;;
  motog5g) MODEL_ALIAS="deepseek-r1-qwen-1.5b" ;;
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
  "$@"
