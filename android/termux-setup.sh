#!/data/data/com.termux/files/usr/bin/bash
# OfflineTweaker :: on-device setup for Android via Termux
#
# Builds llama.cpp natively (no root, no Docker), auto-detects how much RAM
# the phone has, and pulls a DeepSeek-R1 distilled model sized to fit —
# works on any Termux-capable Android device, not just a couple of named
# phones. Writes a launcher script plus a saved profile that
# android/agent-loop.sh reads automatically.
#
# Usage:
#   ./termux-setup.sh              # auto-detect RAM, pick the best tier
#   ./termux-setup.sh --ram 8gb    # force a specific tier
#   ./termux-setup.sh pixel9a      # legacy alias -> 8gb tier
#   ./termux-setup.sh motog5g      # legacy alias -> 4gb tier
#
# Run inside Termux (F-Droid build, not the stale Play Store one):
# https://f-droid.org/packages/com.termux/

set -e

RAM_ARG=""
case "${1:-}" in
  --ram) RAM_ARG="${2:-}" ;;
  pixel9a) RAM_ARG="8gb" ;;   # legacy alias
  motog5g) RAM_ARG="4gb" ;;   # legacy alias
  "") RAM_ARG="" ;;           # auto-detect
  *)
    echo "Usage: $0 [--ram <3gb|4gb|6gb|8gb|12gb|16gb>] [pixel9a|motog5g]"
    echo "Run with no arguments to auto-detect RAM and pick a tier."
    exit 1
    ;;
esac

detect_ram_tier() {
  # Reads total RAM from /proc/meminfo (no extra package needed) and buckets
  # it into a tier. Thresholds sit a bit below each round number because a
  # phone marketed as "8GB" typically reports less than that once the OS
  # reserves some memory.
  local total_mb
  total_mb="$(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo)"
  if   [ "$total_mb" -le 3200 ]; then echo "3gb"
  elif [ "$total_mb" -le 4400 ]; then echo "4gb"
  elif [ "$total_mb" -le 6400 ]; then echo "6gb"
  elif [ "$total_mb" -le 9000 ]; then echo "8gb"
  elif [ "$total_mb" -le 13000 ]; then echo "12gb"
  else echo "16gb"
  fi
}

if [ -z "$RAM_ARG" ]; then
  TIER="$(detect_ram_tier)"
  echo "Auto-detected RAM tier: $TIER (from /proc/meminfo; override with --ram if this looks wrong)"
else
  TIER="$RAM_ARG"
fi

# Thread count is a CPU question, not a RAM one — use core count, capped to
# a sane range regardless of tier.
CORES="$(nproc 2>/dev/null || echo 4)"
THREADS="$CORES"
[ "$THREADS" -gt 8 ] && THREADS=8
[ "$THREADS" -lt 2 ] && THREADS=2

case "$TIER" in
  3gb)
    MODEL_REPO="unsloth/DeepSeek-R1-Distill-Qwen-1.5B-GGUF"
    MODEL_FILE="DeepSeek-R1-Distill-Qwen-1.5B-Q4_K_M.gguf"
    MODEL_LABEL="DeepSeek-R1-Distill-Qwen-1.5B (Q4_K_M)"
    MODEL_ALIAS="deepseek-r1-qwen-1.5b"
    CTX_SIZE=1536
    MAP_TOKENS=0
    MAX_FEEDBACK_CHARS=900
    ;;
  4gb)
    MODEL_REPO="unsloth/DeepSeek-R1-Distill-Qwen-1.5B-GGUF"
    MODEL_FILE="DeepSeek-R1-Distill-Qwen-1.5B-Q4_K_M.gguf"
    MODEL_LABEL="DeepSeek-R1-Distill-Qwen-1.5B (Q4_K_M)"
    MODEL_ALIAS="deepseek-r1-qwen-1.5b"
    CTX_SIZE=2048
    MAP_TOKENS=0
    MAX_FEEDBACK_CHARS=1200
    ;;
  6gb)
    MODEL_REPO="unsloth/DeepSeek-R1-Distill-Qwen-1.5B-GGUF"
    MODEL_FILE="DeepSeek-R1-Distill-Qwen-1.5B-Q4_K_M.gguf"
    MODEL_LABEL="DeepSeek-R1-Distill-Qwen-1.5B (Q4_K_M)"
    MODEL_ALIAS="deepseek-r1-qwen-1.5b"
    CTX_SIZE=3072
    MAP_TOKENS=256
    MAX_FEEDBACK_CHARS=2000
    ;;
  8gb)
    MODEL_REPO="unsloth/DeepSeek-R1-Distill-Qwen-7B-GGUF"
    MODEL_FILE="DeepSeek-R1-Distill-Qwen-7B-Q4_K_M.gguf"
    MODEL_LABEL="DeepSeek-R1-Distill-Qwen-7B (Q4_K_M)"
    MODEL_ALIAS="deepseek-r1-qwen-7b"
    CTX_SIZE=4096
    MAP_TOKENS=512
    MAX_FEEDBACK_CHARS=3000
    ;;
  12gb)
    MODEL_REPO="unsloth/DeepSeek-R1-Distill-Llama-8B-GGUF"
    MODEL_FILE="DeepSeek-R1-Distill-Llama-8B-Q4_K_M.gguf"
    MODEL_LABEL="DeepSeek-R1-Distill-Llama-8B (Q4_K_M)"
    MODEL_ALIAS="deepseek-r1-llama-8b"
    CTX_SIZE=6144
    MAP_TOKENS=768
    MAX_FEEDBACK_CHARS=3500
    ;;
  16gb)
    MODEL_REPO="unsloth/DeepSeek-R1-Distill-Qwen-14B-GGUF"
    MODEL_FILE="DeepSeek-R1-Distill-Qwen-14B-Q4_K_M.gguf"
    MODEL_LABEL="DeepSeek-R1-Distill-Qwen-14B (Q4_K_M)"
    MODEL_ALIAS="deepseek-r1-qwen-14b"
    CTX_SIZE=8192
    MAP_TOKENS=1024
    MAX_FEEDBACK_CHARS=4000
    ;;
  *)
    echo "Unknown tier '$TIER'. Valid: 3gb, 4gb, 6gb, 8gb, 12gb, 16gb" >&2
    exit 1
    ;;
esac

MODEL_URL="https://huggingface.co/${MODEL_REPO}/resolve/main/${MODEL_FILE}"
MODELS_DIR="$HOME/models"
LLAMA_DIR="$HOME/llama.cpp"
PROFILE_DIR="$HOME/.offlinetweaker"
PROFILE_FILE="$PROFILE_DIR/profile.env"

echo "OfflineTweaker Android setup"
echo "Tier: $TIER -> $MODEL_LABEL"
echo "Threads: $THREADS (from $CORES CPU cores)"
echo

echo "[1/6] Requesting storage access (needed to persist the model download)..."
termux-setup-storage || true

echo "[2/6] Installing build toolchain..."
pkg update -y
pkg install -y git cmake golang clang make curl python

echo "[3/6] Building llama.cpp (native, CPU-only)..."
if [ ! -d "$LLAMA_DIR" ]; then
  git clone --depth 1 https://github.com/ggml-org/llama.cpp "$LLAMA_DIR"
else
  echo "llama.cpp already cloned, pulling latest..."
  git -C "$LLAMA_DIR" pull --ff-only || true
fi

cmake -S "$LLAMA_DIR" -B "$LLAMA_DIR/build" -DCMAKE_BUILD_TYPE=Release -DGGML_NATIVE=ON
cmake --build "$LLAMA_DIR/build" --config Release -j"$(nproc)"

echo "[4/6] Downloading $MODEL_LABEL..."
mkdir -p "$MODELS_DIR"
MODEL_PATH="$MODELS_DIR/$MODEL_FILE"
CHECKSUM_PATH="$MODEL_PATH.sha256"

# HuggingFace serves LFS files (which all these GGUFs are) with the file's
# sha256 in the X-Linked-ETag response header on the resolve URL. Fetch it
# before downloading so a corrupted/truncated/swapped multi-GB download
# doesn't silently turn into "the model gives weird output" -- which is
# indistinguishable from normal small-model behavior to whoever's using this.
fetch_expected_sha256() {
  curl -sIL "$MODEL_URL" | tr -d '\r' \
    | awk -F': ' 'tolower($1)=="x-linked-etag" {print $2}' \
    | tail -n1 | tr -d '"'
}

verify_checksum() {
  # $1 = expected sha256 (may be empty if HF didn't send one)
  local expected="$1" actual
  if [ -z "$expected" ]; then
    echo "WARNING: couldn't fetch an expected checksum from HuggingFace; skipping integrity check for $MODEL_FILE." >&2
    return 0
  fi
  if ! command -v sha256sum >/dev/null 2>&1; then
    echo "WARNING: sha256sum not found; skipping integrity check for $MODEL_FILE." >&2
    return 0
  fi
  actual="$(sha256sum "$MODEL_PATH" | awk '{print $1}')"
  if [ "$actual" != "$expected" ]; then
    echo "ERROR: checksum mismatch for $MODEL_FILE." >&2
    echo "  expected: $expected" >&2
    echo "  actual:   $actual" >&2
    echo "Deleting the corrupted/tampered download. Re-run this script to retry." >&2
    rm -f "$MODEL_PATH"
    exit 1
  fi
  echo "$expected" > "$CHECKSUM_PATH"
  echo "Checksum verified for $MODEL_FILE."
}

if [ -f "$MODEL_PATH" ]; then
  if [ -f "$CHECKSUM_PATH" ] && command -v sha256sum >/dev/null 2>&1 \
     && echo "$(cat "$CHECKSUM_PATH")  $MODEL_PATH" | sha256sum -c --status - 2>/dev/null; then
    echo "Model already present at $MODEL_PATH, checksum verified previously, skipping download."
  else
    echo "Model already present at $MODEL_PATH but not previously verified -- checking integrity now..."
    verify_checksum "$(fetch_expected_sha256)"
  fi
else
  EXPECTED_SHA256="$(fetch_expected_sha256)"
  curl -L --fail -o "$MODEL_PATH" "$MODEL_URL"
  verify_checksum "$EXPECTED_SHA256"
fi

echo "[5/6] Writing server launcher and saved profile..."
cat > "$HOME/run-model.sh" << EOF
#!/data/data/com.termux/files/usr/bin/bash
# Launches $MODEL_LABEL as a local OpenAI-compatible server.
# Keep Termux in the foreground (or run 'termux-wake-lock' first) so
# Android doesn't kill the process mid-inference.
exec "$LLAMA_DIR/build/bin/llama-server" \\
  -m "$MODELS_DIR/$MODEL_FILE" \\
  -c $CTX_SIZE \\
  -t $THREADS \\
  --alias "$MODEL_ALIAS" \\
  --host 127.0.0.1 \\
  --port 8080
EOF
chmod +x "$HOME/run-model.sh"

# Single source of truth for android/agent-loop.sh, so tier logic isn't
# duplicated between scripts and can't drift out of sync.
mkdir -p "$PROFILE_DIR"
cat > "$PROFILE_FILE" << EOF
DEVICE_TIER=$TIER
MODEL_ALIAS=$MODEL_ALIAS
MODEL_LABEL="$MODEL_LABEL"
CTX_SIZE=$CTX_SIZE
THREADS=$THREADS
MAP_TOKENS=$MAP_TOKENS
MAX_FEEDBACK_CHARS=$MAX_FEEDBACK_CHARS
EOF

echo "[6/6] Installing Aider (terminal coding agent) and writing its launcher..."
pip install --upgrade pip >/dev/null
pip install aider-chat

cat > "$HOME/aider-local.sh" << EOF
#!/data/data/com.termux/files/usr/bin/bash
# Runs Aider against the local llama-server started by run-model.sh.
# Start ~/run-model.sh in another Termux session first.
export OPENAI_API_BASE="http://127.0.0.1:8080/v1"
export OPENAI_API_KEY="sk-local-no-key-required"
exec aider --model "openai/$MODEL_ALIAS" "\$@"
EOF
chmod +x "$HOME/aider-local.sh"

echo
echo "Done. Recommended next steps:"
echo "  1. termux-wake-lock            # stop Android from suspending inference"
echo "  2. ~/run-model.sh              # starts the model on http://127.0.0.1:8080"
echo "  3a. Open http://127.0.0.1:8080 in Chrome for the built-in chat UI, or"
echo "  3b. In a second Termux session: cd your-project && ~/aider-local.sh"
echo "      for a manual agentic coding CLI, or android/agent-loop.sh for the"
echo "      autonomous write-test-fix loop (reads this saved profile"
echo "      automatically, no flags needed)."
echo
echo "Model: $MODEL_LABEL (alias: $MODEL_ALIAS)"
echo "Context: $CTX_SIZE tokens | Threads: $THREADS"
echo "Profile saved to: $PROFILE_FILE"
