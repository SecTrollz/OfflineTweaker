#!/usr/bin/env bash
# OfflineTweaker :: cloud wrapper for the autonomous build loop.
#
# Points agent/build-loop.sh at a model that isn't running on this machine,
# in one of two ways:
#
#   1. Your own rented server (a VPS or cloud GPU box running setup.sh's
#      docker-compose stack). By default this opens a private SSH local
#      port-forward so the model's port is never exposed to the public
#      internet -- setup.sh already binds those ports to 127.0.0.1 on the
#      remote host for exactly this reason. If the box is already on a
#      private network (e.g. Tailscale), skip the tunnel with --no-tunnel.
#
#   2. A third-party hosted OpenAI-compatible API (OpenRouter, Together,
#      Groq, Fireworks, or a custom endpoint). This sends your task and
#      code to that provider over the network -- it is no longer offline,
#      and the script prints a warning every time you use it.
#
# Usage:
#   # Your own server, private SSH tunnel (recommended):
#   ./cloud/agent-loop.sh --host user@1.2.3.4 --model qwen2.5-coder:14b \
#     --dir ./myproj --task "Add input validation" --test-cmd "pytest -q"
#
#   # Your own server, already on a private network (e.g. Tailscale) --
#   # no tunnel needed, connect directly:
#   ./cloud/agent-loop.sh --host 100.x.y.z --no-tunnel \
#     --model qwen2.5-coder:14b --dir ./myproj --task "..."
#
#   # Third-party hosted API:
#   ./cloud/agent-loop.sh --provider openrouter --api-key "$OPENROUTER_API_KEY" \
#     --model deepseek/deepseek-r1 --dir ./myproj --task "..."
#
# Any flag agent/build-loop.sh accepts (--test-cmd, --max-iters,
# --map-tokens, --max-feedback-chars, ...) can also be passed through here.

set -u

HOST=""
NO_TUNNEL=0
REMOTE_PORT=11434
LOCAL_PORT=11434
PROVIDER=""
CUSTOM_API_BASE=""
API_KEY=""
PASSTHROUGH_ARGS=()

usage() {
  echo "Usage:"
  echo "  Self-hosted:   $0 --host <user@host> [--no-tunnel] [--remote-port N] [--local-port N] --model <model> ..."
  echo "  Hosted API:    $0 --provider <openrouter|together|groq|fireworks|custom> [--api-base <url>] --api-key <key> --model <model> ..."
  echo "  (remaining flags are passed through to agent/build-loop.sh: --dir, --task, --test-cmd, --max-iters, --map-tokens, --max-feedback-chars, ...)"
  exit 1
}

# MODEL is captured here (not just passed through) because it's needed to
# validate required-arg combinations before handing off to build-loop.sh.
MODEL=""

while [ $# -gt 0 ]; do
  case "$1" in
    --host) HOST="$2"; shift 2 ;;
    --no-tunnel) NO_TUNNEL=1; shift ;;
    --remote-port) REMOTE_PORT="$2"; shift 2 ;;
    --local-port) LOCAL_PORT="$2"; shift 2 ;;
    --provider) PROVIDER="$2"; shift 2 ;;
    --api-base) CUSTOM_API_BASE="$2"; shift 2 ;;
    --api-key) API_KEY="$2"; shift 2 ;;
    --model) MODEL="$2"; PASSTHROUGH_ARGS+=(--model "$2"); shift 2 ;;
    -h|--help) usage ;;
    *) PASSTHROUGH_ARGS+=("$1"); shift ;;
  esac
done

if [ -z "$MODEL" ]; then
  echo "--model is required." >&2
  usage
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_LOOP="$SCRIPT_DIR/../agent/build-loop.sh"

if [ -n "$HOST" ] && [ -n "$PROVIDER" ]; then
  echo "Pass either --host (your own server) or --provider (hosted API), not both." >&2
  exit 1
fi

if [ -n "$HOST" ]; then
  # --- Your own server ---
  if [ "$NO_TUNNEL" -eq 1 ]; then
    API_BASE="http://${HOST#*@}:${REMOTE_PORT}/v1"
    echo "Connecting directly to $API_BASE (--no-tunnel: assuming $HOST is already reachable, e.g. via Tailscale)."
  else
    if ! command -v ssh >/dev/null 2>&1; then
      echo "ssh not found on PATH. Install openssh (e.g. pkg/apt/brew install openssh)." >&2
      exit 1
    fi
    echo "Opening SSH tunnel: 127.0.0.1:$LOCAL_PORT -> $HOST:$REMOTE_PORT ..."
    ssh -N -L "${LOCAL_PORT}:localhost:${REMOTE_PORT}" "$HOST" &
    SSH_PID=$!
    trap 'echo "Closing SSH tunnel..."; kill "$SSH_PID" 2>/dev/null' EXIT

    ready=0
    for _ in $(seq 1 10); do
      if curl -s -o /dev/null "http://127.0.0.1:${LOCAL_PORT}"; then
        ready=1
        break
      fi
      sleep 1
    done
    if [ "$ready" -eq 0 ]; then
      echo "Tunnel did not come up after 10s -- check that $HOST is reachable and sshd is running." >&2
      exit 1
    fi
    API_BASE="http://127.0.0.1:${LOCAL_PORT}/v1"
    echo "Tunnel is up. Using $API_BASE"
  fi
  API_KEY="${API_KEY:-sk-local-no-key-required}"

elif [ -n "$PROVIDER" ]; then
  # --- Third-party hosted API ---
  case "$PROVIDER" in
    openrouter) API_BASE="https://openrouter.ai/api/v1" ;;
    together)   API_BASE="https://api.together.xyz/v1" ;;
    groq)       API_BASE="https://api.groq.com/openai/v1" ;;
    fireworks)  API_BASE="https://api.fireworks.ai/inference/v1" ;;
    custom)
      if [ -z "$CUSTOM_API_BASE" ]; then
        echo "--provider custom requires --api-base <url>." >&2
        exit 1
      fi
      API_BASE="$CUSTOM_API_BASE"
      ;;
    *)
      echo "Unknown provider '$PROVIDER'. Valid: openrouter, together, groq, fireworks, custom" >&2
      exit 1
      ;;
  esac
  if [ -z "$API_KEY" ]; then
    echo "--api-key is required for --provider $PROVIDER." >&2
    exit 1
  fi
  echo "WARNING: sending your task and code to $PROVIDER ($API_BASE) over the network. This is not offline."

else
  echo "Specify either --host (your own server) or --provider (hosted API)." >&2
  usage
fi

exec "$BUILD_LOOP" --api-base "$API_BASE" --api-key "$API_KEY" "${PASSTHROUGH_ARGS[@]}"
