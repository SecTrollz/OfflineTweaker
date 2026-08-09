#!/usr/bin/env bash
# OfflineTweaker :: autonomous build loop
#
# The core "vibe coding" engine: hands a task to Aider against a local
# OpenAI-compatible model, runs your test/build command, feeds any failure
# back to the model as the next instruction, and repeats until the tests
# pass or a max-iteration budget runs out. Fully offline — works against
# either the desktop Ollama server or the on-device llama-server started by
# android/termux-setup.sh.
#
# This is what makes it a *builder* rather than a chat window: write code,
# run it, read the errors, fix it, repeat — without a human relaying output
# back and forth each round.
#
# Usage:
#   build-loop.sh --dir <project-dir> --task "<what to build/fix>" \
#                  --model <model-name> [--api-base <url>] [--api-key <key>] \
#                  [--test-cmd "<command>"] [--max-iters N] \
#                  [--max-feedback-chars N] [--map-tokens N] \
#                  [--encrypt-logs <age-recipient-or-recipients-file>]
#
# Examples:
#   # Desktop, against Ollama:
#   ./agent/build-loop.sh --dir ./workspace/my-app \
#     --task "Add a /health endpoint that returns 200 OK" \
#     --model qwen2.5-coder:14b --api-base http://localhost:11434/v1 \
#     --test-cmd "pytest -q"
#
#   # Android, against the local llama-server (see android/agent-loop.sh
#   # for a thin wrapper that fills in --model/--api-base and the
#   # context-budget flags below for you):
#   ./agent/build-loop.sh --dir ~/projects/my-app \
#     --task "Fix the failing tests" --model deepseek-r1-qwen-7b \
#     --api-base http://127.0.0.1:8080/v1 --test-cmd "python -m pytest -q" \
#     --map-tokens 512 --max-feedback-chars 3000
#
# Every run gets a short built-in system preamble (override via the
# OFFLINETWEAKER_SYSTEM_PROMPT env var) that tells the model to stay terse —
# this matters most on small local models with a tight context window.
# --max-feedback-chars and --map-tokens are the two real context-budget
# levers: how much failing-test output gets fed back on retry, and how many
# tokens Aider spends on its repo map. Tune both down for small-context
# models; leave them unset for a normal desktop-sized context window.
#
# For a hosted-API key, prefer exporting OPENAI_API_KEY before running this
# rather than --api-key -- a key passed on the command line ends up visible
# to other users via `ps` and saved in shell history.
#
# --encrypt-logs encrypts every iteration log, test-output log, and Aider's
# own chat-history file (the full task + model transcript) as they're
# written, using age (https://age-encryption.org) -- and deletes the
# plaintext. This is asymmetric (recipient-key) encryption, not a
# passphrase, on purpose: a passphrase means a human re-typing it at every
# one of potentially --max-iters * 2 file writes per run, which isn't
# workable, so age's passphrase mode refuses to be scripted at all (it
# reads /dev/tty directly). One-time setup:
#   age-keygen -o ~/.offlinetweaker/logs-key.txt   # prints the public key
# then pass that public key (or the key FILE path, either works) as the
# --encrypt-logs value on every run. Decrypt later with:
#   age -d -i ~/.offlinetweaker/logs-key.txt iteration-1.log.age
# Protect ~/.offlinetweaker/logs-key.txt like the secret it is (age-keygen
# already chmod 600s it) -- anyone who reads that file can decrypt every
# log encrypted to it, past and future.

set -u

DIR=""
TASK=""
TEST_CMD=""
MAX_ITERS=5
API_BASE=""
# Prefer an already-exported OPENAI_API_KEY over --api-key: a key passed on
# the command line is visible to other users via `ps` and gets written to
# shell history. cloud/agent-loop.sh hands off this way rather than via argv
# for exactly that reason.
API_KEY="${OPENAI_API_KEY:-sk-local-no-key-required}"
API_KEY_FROM_ARG=0
MODEL=""
MAX_FEEDBACK_CHARS=4000
MAP_TOKENS=""
ENCRYPT_LOGS_TO=""
SYSTEM_PREAMBLE="${OFFLINETWEAKER_SYSTEM_PROMPT:-You are a coding agent running on constrained local hardware with a small context window. Be terse: make the minimal correct change, avoid restating unchanged code, keep any reasoning brief, and address only the current task or test failure directly.}"

usage() {
  echo "Usage: $0 --dir <project-dir> --task \"<task>\" --model <model> [--api-base <url>] [--api-key <key>] [--test-cmd \"<cmd>\"] [--max-iters N] [--max-feedback-chars N] [--map-tokens N] [--encrypt-logs <age-recipient-or-recipients-file>]"
  exit 1
}

while [ $# -gt 0 ]; do
  case "$1" in
    --dir) DIR="$2"; shift 2 ;;
    --task) TASK="$2"; shift 2 ;;
    --test-cmd) TEST_CMD="$2"; shift 2 ;;
    --max-iters) MAX_ITERS="$2"; shift 2 ;;
    --api-base) API_BASE="$2"; shift 2 ;;
    --api-key) API_KEY="$2"; API_KEY_FROM_ARG=1; shift 2 ;;
    --model) MODEL="$2"; shift 2 ;;
    --max-feedback-chars) MAX_FEEDBACK_CHARS="$2"; shift 2 ;;
    --map-tokens) MAP_TOKENS="$2"; shift 2 ;;
    --encrypt-logs) ENCRYPT_LOGS_TO="$2"; shift 2 ;;
    -h|--help) usage ;;
    *) echo "Unknown argument: $1"; usage ;;
  esac
done

if [ -z "$DIR" ] || [ -z "$TASK" ] || [ -z "$MODEL" ] || [ -z "$API_BASE" ]; then
  usage
fi

if [ ! -d "$DIR" ]; then
  echo "Project dir '$DIR' does not exist." >&2
  exit 1
fi

if ! command -v aider >/dev/null 2>&1; then
  echo "aider not found on PATH. Install it with: pip install aider-chat" >&2
  exit 1
fi

AGE_ARGS=()
if [ -n "$ENCRYPT_LOGS_TO" ]; then
  if ! command -v age >/dev/null 2>&1; then
    echo "ERROR: --encrypt-logs was given but 'age' is not installed/on PATH. Install it (apt/pkg/brew install age) or drop --encrypt-logs -- refusing to silently fall back to writing plaintext logs when encryption was explicitly requested." >&2
    exit 1
  fi
  if [ -f "$ENCRYPT_LOGS_TO" ]; then
    AGE_ARGS=(-R "$ENCRYPT_LOGS_TO")
  else
    AGE_ARGS=(-r "$ENCRYPT_LOGS_TO")
  fi
fi

encrypt_log() {
  # Encrypts $1 in place (age-encrypted "$1.age", plaintext removed) if
  # --encrypt-logs was given; no-op otherwise. On encryption failure, the
  # plaintext is left exactly where it was and this says so loudly --
  # silently losing a log, or silently leaving it unencrypted after
  # encryption was explicitly requested, are both worse than a visible
  # failure the caller has to notice.
  local f="$1"
  [ -n "$ENCRYPT_LOGS_TO" ] || return 0
  [ -f "$f" ] || return 0
  if age "${AGE_ARGS[@]}" -o "$f.age" "$f" < /dev/null 2>"$f.encrypt-error"; then
    rm -f "$f" "$f.encrypt-error"
  else
    echo "ERROR: failed to encrypt $f -- left as plaintext. See $f.encrypt-error." >&2
  fi
}

if [ "$API_KEY_FROM_ARG" -eq 1 ]; then
  echo "WARNING: --api-key was passed on the command line -- it's visible to other users via 'ps' and gets saved in shell history. Prefer: export OPENAI_API_KEY=... and omit --api-key." >&2
fi

export OPENAI_API_BASE="$API_BASE"
export OPENAI_API_KEY="$API_KEY"

LOG_ROOT="$DIR/.offlinetweaker/agent-logs/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$LOG_ROOT"

echo "OfflineTweaker autonomous build loop"
echo "Project: $DIR"
echo "Model:   $MODEL @ $API_BASE"
echo "Test:    ${TEST_CMD:-<none — single pass, no verification loop>}"
echo "Logs:    $LOG_ROOT"
[ -n "$ENCRYPT_LOGS_TO" ] && echo "Encrypting logs to: $ENCRYPT_LOGS_TO"
echo

run_tests() {
  # Runs the test command inside $DIR. Returns 0 on pass, non-zero on fail.
  # Output is captured to the caller-provided log file.
  local log_file="$1"
  (cd "$DIR" && eval "$TEST_CMD") >"$log_file" 2>&1
}

current_task="$TASK"
success=0

for ((i = 1; i <= MAX_ITERS; i++)); do
  echo "=== Iteration $i/$MAX_ITERS ==="
  iter_log="$LOG_ROOT/iteration-$i.log"

  {
    echo "--- task given to aider ---"
    echo "$current_task"
    echo
    echo "--- aider output ---"
  } > "$iter_log"

  aider_args=(--yes-always --no-stream --model "openai/$MODEL")
  [ -n "$MAP_TOKENS" ] && aider_args+=(--map-tokens "$MAP_TOKENS")
  [ -n "$TEST_CMD" ] && aider_args+=(--auto-test --test-cmd "$TEST_CMD")
  # Aider keeps its own full transcript (default .aider.chat.history.md in
  # $DIR) independent of the log redirection above. When encrypting, pull
  # it into LOG_ROOT instead of letting it land in the project dir in
  # plaintext, so it goes through encrypt_log() like everything else below.
  aider_chat_history=""
  if [ -n "$ENCRYPT_LOGS_TO" ]; then
    aider_chat_history="$LOG_ROOT/iteration-$i-aider-chat-history.md"
    aider_args+=(--chat-history-file "$aider_chat_history")
  fi
  aider_args+=(--message "$SYSTEM_PREAMBLE

$current_task" --auto-commits)

  aider "${aider_args[@]}" >> "$iter_log" 2>&1

  # Encrypt (or no-op if --encrypt-logs wasn't given) as soon as each file
  # is done being written -- iter_log and the chat history are never read
  # back by this script, so there's no reason to leave them in plaintext
  # a moment longer than necessary.
  encrypt_log "$iter_log"
  encrypt_log "$aider_chat_history"

  if [ -z "$TEST_CMD" ]; then
    # Report whichever path actually exists now -- encrypt_log() can fail
    # (bad recipient, etc.) and leave the plaintext in place instead of
    # producing the .age file, so don't unconditionally claim the .age
    # path if that's not really what's on disk.
    if [ -f "$iter_log.age" ]; then
      echo "No --test-cmd given, treating this as a single-pass edit. See $iter_log.age."
    else
      echo "No --test-cmd given, treating this as a single-pass edit. See $iter_log."
    fi
    success=1
    break
  fi

  test_log="$LOG_ROOT/iteration-$i-tests.log"
  if run_tests "$test_log"; then
    echo "Tests passed on iteration $i."
    encrypt_log "$test_log"
    success=1
    break
  fi

  echo "Tests failed on iteration $i, feeding failure back for the next attempt..."
  # Read the failure output back BEFORE encrypting -- encrypt_log deletes
  # the plaintext, and this is the one log whose content this script still
  # needs (to build the next iteration's prompt).
  failure_output="$(tail -c "$MAX_FEEDBACK_CHARS" "$test_log")"
  encrypt_log "$test_log"
  current_task="The previous attempt's tests failed with this output:

$failure_output

Fix the code so that the test command passes. Do not change the tests unless they are clearly wrong."
done

echo
if [ "$success" -eq 1 ]; then
  echo "Build loop succeeded after $i iteration(s). Logs in $LOG_ROOT"
  exit 0
else
  echo "Build loop did not converge after $MAX_ITERS iteration(s). Logs in $LOG_ROOT"
  echo "Review the failing output and either raise --max-iters or fix manually from here."
  exit 1
fi
