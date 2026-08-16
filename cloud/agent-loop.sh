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
#   # Third-party hosted API (prefer exporting the key over --api-key -- see
#   # below):
#   export OPENAI_API_KEY="$OPENROUTER_API_KEY"
#   ./cloud/agent-loop.sh --provider openrouter \
#     --model deepseek/deepseek-r1 --dir ./myproj --task "..."
#
# Any flag agent/build-loop.sh accepts (--test-cmd, --max-iters,
# --map-tokens, --max-feedback-chars, ...) can also be passed through here.
#
# --api-key is still accepted directly, but prefer exporting OPENAI_API_KEY
# beforehand instead -- a key passed on the command line ends up visible to
# other users via `ps` and saved in shell history.

set -u

HOST=""
NO_TUNNEL=0
REMOTE_PORT=11434
LOCAL_PORT=11434
PROVIDER=""
CUSTOM_API_BASE=""
# Prefer an already-exported OPENAI_API_KEY over --api-key: a key passed on
# the command line is visible to other users via `ps` and gets written to
# shell history.
API_KEY="${OPENAI_API_KEY:-}"
API_KEY_FROM_ARG=0
PASSTHROUGH_ARGS=()
# Set only when a tunnel is actually opened -- see the exec-vs-not branch
# at the bottom for why this matters.
SSH_PID=""

usage() {
  echo "Usage:"
  echo "  Self-hosted:   $0 --host <user@host> [--no-tunnel] [--remote-port N] [--local-port N] --model <model> ..."
  echo "  Hosted API:    $0 --provider <openrouter|together|groq|fireworks|custom> [--api-base <url>] --model <model> ... (needs OPENAI_API_KEY exported, or pass --api-key <key>)"
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
    --api-key) API_KEY="$2"; API_KEY_FROM_ARG=1; shift 2 ;;
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
    # Verified with a real collision: if something is already listening on
    # LOCAL_PORT (e.g. a desktop docker-compose Ollama on the default
    # 11434), the readiness check below can't tell that apart from the
    # tunnel actually coming up -- "something answered" looks identical
    # either way, and every request then silently goes to the wrong
    # backend instead of the remote host. Refuse up front instead.
    if curl -s -o /dev/null "http://127.0.0.1:${LOCAL_PORT}"; then
      echo "Something is already listening on 127.0.0.1:${LOCAL_PORT} -- refusing to open a tunnel there, since it would be impossible to tell your tunnel apart from whatever's already running. Pick a free port with --local-port." >&2
      exit 1
    fi

    echo "Opening SSH tunnel: 127.0.0.1:$LOCAL_PORT -> $HOST:$REMOTE_PORT ..."
    # Verified against a real first-time connection: plain `ssh -N` in the
    # background has no TTY to prompt "accept this host key?" on, so a host
    # not already in known_hosts fails closed with "Host key verification
    # failed" instead of connecting. accept-new is the safe middle ground --
    # it trusts a *new* host automatically (fine for a VM you just rented)
    # but still hard-fails if a *known* host's key ever changes, unlike
    # disabling checking outright.
    # Verified with a real run: without redirecting ssh's output, the
    # backgrounded process inherits this script's stdout/stderr and keeps
    # holding them open for as long as the tunnel lives -- so anything
    # consuming this script's output (a pipe, `> log.txt`, a CI capture)
    # never sees EOF and hangs, even after build-loop.sh below has already
    # finished. -N has nothing useful to say on stdout anyway; send it to a
    # small log instead of /dev/null so a connection drop is still visible.
    SSH_LOG="$(mktemp -t offlinetweaker-tunnel.XXXXXX)"
    ssh -o StrictHostKeyChecking=accept-new -N -L "${LOCAL_PORT}:localhost:${REMOTE_PORT}" "$HOST" >"$SSH_LOG" 2>&1 &
    SSH_PID=$!
    trap 'echo "Closing SSH tunnel..."; kill "$SSH_PID" 2>/dev/null' EXIT

    ready=0
    for _ in $(seq 1 10); do
      if ! kill -0 "$SSH_PID" 2>/dev/null; then
        echo "ssh exited before the tunnel came up -- check the host/credentials." >&2
        break
      fi
      if curl -s -o /dev/null "http://127.0.0.1:${LOCAL_PORT}"; then
        ready=1
        break
      fi
      sleep 1
    done
    if [ "$ready" -eq 0 ]; then
      echo "Tunnel did not come up after 10s -- check that $HOST is reachable and sshd is running. ssh output:" >&2
      cat "$SSH_LOG" >&2
      exit 1
    fi
    API_BASE="http://127.0.0.1:${LOCAL_PORT}/v1"
    echo "Tunnel is up. Using $API_BASE (ssh output, if any, is logged to $SSH_LOG)"
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
    echo "An API key is required for --provider $PROVIDER -- export OPENAI_API_KEY or pass --api-key <key>." >&2
    exit 1
  fi
  echo "WARNING: sending your task and code to $PROVIDER ($API_BASE) over the network. This is not offline."

else
  echo "Specify either --host (your own server) or --provider (hosted API)." >&2
  usage
fi

if [ "$API_KEY_FROM_ARG" -eq 1 ]; then
  echo "WARNING: --api-key was passed on the command line -- it's visible to other users via 'ps' and gets saved in shell history. Prefer: export OPENAI_API_KEY=... and omit --api-key." >&2
fi

# Hand off via env var, not argv -- build-loop.sh's own process listing
# would otherwise show the key too.
export OPENAI_API_KEY="$API_KEY"

if [ -n "$SSH_PID" ]; then
  # Verified with a real run: `exec` replaces this process image entirely,
  # which means the EXIT trap above that kills the SSH tunnel never fires --
  # the tunnel leaks and keeps running forever. Only skip exec (and pay one
  # extra process) when there's actually a tunnel that needs the trap to run
  # on the way out; the no-tunnel and hosted-API paths have nothing to clean
  # up, so exec is fine there.
  "$BUILD_LOOP" --api-base "$API_BASE" "${PASSTHROUGH_ARGS[@]}"
  exit $?
else
  exec "$BUILD_LOOP" --api-base "$API_BASE" "${PASSTHROUGH_ARGS[@]}"
fi
