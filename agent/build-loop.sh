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
#                  [--max-feedback-chars N] [--map-tokens N]
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

set -u

DIR=""
TASK=""
TEST_CMD=""
MAX_ITERS=5
API_BASE=""
API_KEY="sk-local-no-key-required"
MODEL=""
MAX_FEEDBACK_CHARS=4000
MAP_TOKENS=""
SYSTEM_PREAMBLE="${OFFLINETWEAKER_SYSTEM_PROMPT:-You are a coding agent running on constrained local hardware with a small context window. Be terse: make the minimal correct change, avoid restating unchanged code, keep any reasoning brief, and address only the current task or test failure directly.}"

usage() {
  echo "Usage: $0 --dir <project-dir> --task \"<task>\" --model <model> [--api-base <url>] [--api-key <key>] [--test-cmd \"<cmd>\"] [--max-iters N] [--max-feedback-chars N] [--map-tokens N]"
  exit 1
}

while [ $# -gt 0 ]; do
  case "$1" in
    --dir) DIR="$2"; shift 2 ;;
    --task) TASK="$2"; shift 2 ;;
    --test-cmd) TEST_CMD="$2"; shift 2 ;;
    --max-iters) MAX_ITERS="$2"; shift 2 ;;
    --api-base) API_BASE="$2"; shift 2 ;;
    --api-key) API_KEY="$2"; shift 2 ;;
    --model) MODEL="$2"; shift 2 ;;
    --max-feedback-chars) MAX_FEEDBACK_CHARS="$2"; shift 2 ;;
    --map-tokens) MAP_TOKENS="$2"; shift 2 ;;
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

export OPENAI_API_BASE="$API_BASE"
export OPENAI_API_KEY="$API_KEY"

LOG_ROOT="$DIR/.offlinetweaker/agent-logs/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$LOG_ROOT"

echo "OfflineTweaker autonomous build loop"
echo "Project: $DIR"
echo "Model:   $MODEL @ $API_BASE"
echo "Test:    ${TEST_CMD:-<none — single pass, no verification loop>}"
echo "Logs:    $LOG_ROOT"
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
  aider_args+=(--message "$SYSTEM_PREAMBLE

$current_task" --auto-commits)

  aider "${aider_args[@]}" >> "$iter_log" 2>&1

  if [ -z "$TEST_CMD" ]; then
    echo "No --test-cmd given, treating this as a single-pass edit. See $iter_log."
    success=1
    break
  fi

  test_log="$LOG_ROOT/iteration-$i-tests.log"
  if run_tests "$test_log"; then
    echo "Tests passed on iteration $i."
    success=1
    break
  fi

  echo "Tests failed on iteration $i, feeding failure back for the next attempt..."
  failure_output="$(tail -c "$MAX_FEEDBACK_CHARS" "$test_log")"
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
