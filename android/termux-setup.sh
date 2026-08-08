#!/data/data/com.termux/files/usr/bin/bash
# OfflineTweaker :: on-device setup for Android via Termux
#
# Builds llama.cpp natively (no root, no Docker) and pulls a DeepSeek-R1
# distilled model sized to fit the phone's RAM, then writes a launcher
# script you can re-run any time.
#
# Usage:
#   ./termux-setup.sh pixel9a     # 8GB RAM tier  -> DeepSeek-R1-Distill-Qwen-7B
#   ./termux-setup.sh motog5g     # 4GB RAM tier  -> DeepSeek-R1-Distill-Qwen-1.5B
#
# Run inside Termux (F-Droid build, not the stale Play Store one):
# https://f-droid.org/packages/com.termux/

set -e

PROFILE="${1:-}"

usage() {
  echo "Usage: $0 <pixel9a|motog5g>"
  echo
  echo "  pixel9a   8GB RAM tier -> DeepSeek-R1-Distill-Qwen-7B  (Q4_K_M, ~4.4GB)"
  echo "  motog5g   4GB RAM tier -> DeepSeek-R1-Distill-Qwen-1.5B (Q4_K_M, ~1.1GB)"
  exit 1
}

case "$PROFILE" in
  pixel9a)
    MODEL_REPO="unsloth/DeepSeek-R1-Distill-Qwen-7B-GGUF"
    MODEL_FILE="DeepSeek-R1-Distill-Qwen-7B-Q4_K_M.gguf"
    MODEL_LABEL="DeepSeek-R1-Distill-Qwen-7B (Q4_K_M)"
    CTX_SIZE=4096
    THREADS=6
    ;;
  motog5g)
    MODEL_REPO="unsloth/DeepSeek-R1-Distill-Qwen-1.5B-GGUF"
    MODEL_FILE="DeepSeek-R1-Distill-Qwen-1.5B-Q4_K_M.gguf"
    MODEL_LABEL="DeepSeek-R1-Distill-Qwen-1.5B (Q4_K_M)"
    CTX_SIZE=2048
    THREADS=4
    ;;
  *)
    usage
    ;;
esac

MODEL_URL="https://huggingface.co/${MODEL_REPO}/resolve/main/${MODEL_FILE}"
MODELS_DIR="$HOME/models"
LLAMA_DIR="$HOME/llama.cpp"

echo "OfflineTweaker Android setup"
echo "Profile: $PROFILE -> $MODEL_LABEL"
echo

echo "[1/5] Requesting storage access (needed to persist the model download)..."
termux-setup-storage || true

echo "[2/5] Installing build toolchain..."
pkg update -y
pkg install -y git cmake golang clang make curl

echo "[3/5] Building llama.cpp (native, CPU-only)..."
if [ ! -d "$LLAMA_DIR" ]; then
  git clone --depth 1 https://github.com/ggml-org/llama.cpp "$LLAMA_DIR"
else
  echo "llama.cpp already cloned, pulling latest..."
  git -C "$LLAMA_DIR" pull --ff-only || true
fi

cmake -S "$LLAMA_DIR" -B "$LLAMA_DIR/build" -DCMAKE_BUILD_TYPE=Release -DGGML_NATIVE=ON
cmake --build "$LLAMA_DIR/build" --config Release -j"$(nproc)"

echo "[4/5] Downloading $MODEL_LABEL..."
mkdir -p "$MODELS_DIR"
if [ -f "$MODELS_DIR/$MODEL_FILE" ]; then
  echo "Model already present at $MODELS_DIR/$MODEL_FILE, skipping download."
else
  curl -L --fail -o "$MODELS_DIR/$MODEL_FILE" "$MODEL_URL"
fi

echo "[5/5] Writing launcher script..."
cat > "$HOME/run-model.sh" << EOF
#!/data/data/com.termux/files/usr/bin/bash
# Launches $MODEL_LABEL as a local OpenAI-compatible server.
# Keep Termux in the foreground (or run 'termux-wake-lock' first) so
# Android doesn't kill the process mid-inference.
exec "$LLAMA_DIR/build/bin/llama-server" \\
  -m "$MODELS_DIR/$MODEL_FILE" \\
  -c $CTX_SIZE \\
  -t $THREADS \\
  --host 127.0.0.1 \\
  --port 8080
EOF
chmod +x "$HOME/run-model.sh"

echo
echo "Done. Recommended next steps:"
echo "  1. termux-wake-lock            # stop Android from suspending inference"
echo "  2. ~/run-model.sh              # starts the model on http://127.0.0.1:8080"
echo "  3. Open http://127.0.0.1:8080 in Chrome for the built-in chat UI,"
echo "     or point any OpenAI-compatible client at that URL."
echo
echo "Model: $MODEL_LABEL"
echo "Context: $CTX_SIZE tokens | Threads: $THREADS"
