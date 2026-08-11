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
#   ./termux-setup.sh                     # auto-detect RAM, pick the best tier
#   ./termux-setup.sh --ram 8gb           # force a specific tier
#   ./termux-setup.sh --role coding       # code-tuned model instead of the
#                                          # default reasoning distill (only
#                                          # available on the 3gb/4gb/6gb
#                                          # tiers right now -- see below)
#   ./termux-setup.sh --ram 6gb --role coding
#   ./termux-setup.sh pixel9a             # legacy alias -> 8gb tier
#   ./termux-setup.sh motog5g             # legacy alias -> 4gb tier
#
# --role reasoning (the default) picks a DeepSeek-R1 distill -- strong at
# diagnosing tricky bugs and explaining *why* something's broken, at the
# cost of `<think>` reasoning traces that eat into the small context
# budget these devices have to work with.
# --role coding picks a Qwen2.5-Coder-Instruct model instead -- tuned
# specifically for writing/editing code rather than open-ended reasoning,
# no `<think>` overhead, same family already used on desktop. It's newer
# to this script than the reasoning lane and hasn't had the same amount
# of real-device mileage yet -- report back if `--role coding` breaks
# anything, the same way past `--ram` tier bugs got fixed here.
#
# Run inside Termux (F-Droid build, not the stale Play Store one):
# https://f-droid.org/packages/com.termux/

set -e

RAM_ARG=""
ROLE="reasoning"
while [ $# -gt 0 ]; do
  case "$1" in
    --ram)
      RAM_ARG="${2:-}"
      shift 2
      ;;
    --role)
      ROLE="${2:-}"
      shift 2
      ;;
    pixel9a)   # legacy alias
      RAM_ARG="8gb"
      shift
      ;;
    motog5g)   # legacy alias
      RAM_ARG="4gb"
      shift
      ;;
    *)
      echo "Usage: $0 [--ram <3gb|4gb|6gb|8gb|12gb|16gb>] [--role <reasoning|coding>] [pixel9a|motog5g]"
      echo "Run with no arguments to auto-detect RAM and pick a tier."
      exit 1
      ;;
  esac
done

case "$ROLE" in
  reasoning|coding) ;;
  *)
    echo "Unknown --role '$ROLE'. Valid: reasoning, coding" >&2
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

# --role coding is only wired up for the tiers below where a code-tuned
# model has actually been picked out with real license/benchmark checks
# behind it (see the header comment). Reject it early and clearly for
# every other tier rather than silently falling back to reasoning -- a
# flag that's quietly ignored is worse than one that errors.
if [ "$ROLE" = "coding" ]; then
  case "$TIER" in
    3gb|4gb|6gb) ;;
    *)
      echo "Error: --role coding isn't available yet for the $TIER tier." >&2
      echo "Only 3gb/4gb/6gb have a vetted coding-specific model right now." >&2
      echo "Use --role reasoning (the default), or drop --role entirely." >&2
      exit 1
      ;;
  esac
fi

case "$TIER" in
  3gb)
    if [ "$ROLE" = "coding" ]; then
      MODEL_REPO="unsloth/Qwen2.5-Coder-1.5B-Instruct-GGUF"
      MODEL_FILE="qwen2.5-coder-1.5b-instruct-q4_k_m.gguf"
      MODEL_LABEL="Qwen2.5-Coder-1.5B-Instruct (Q4_K_M)"
      MODEL_ALIAS="qwen2.5-coder-1.5b"
    else
      MODEL_REPO="unsloth/DeepSeek-R1-Distill-Qwen-1.5B-GGUF"
      MODEL_FILE="DeepSeek-R1-Distill-Qwen-1.5B-Q4_K_M.gguf"
      MODEL_LABEL="DeepSeek-R1-Distill-Qwen-1.5B (Q4_K_M)"
      MODEL_ALIAS="deepseek-r1-qwen-1.5b"
    fi
    CTX_SIZE=1536
    MAP_TOKENS=0
    MAX_FEEDBACK_CHARS=900
    ;;
  4gb)
    if [ "$ROLE" = "coding" ]; then
      MODEL_REPO="unsloth/Qwen2.5-Coder-1.5B-Instruct-GGUF"
      MODEL_FILE="qwen2.5-coder-1.5b-instruct-q4_k_m.gguf"
      MODEL_LABEL="Qwen2.5-Coder-1.5B-Instruct (Q4_K_M)"
      MODEL_ALIAS="qwen2.5-coder-1.5b"
    else
      MODEL_REPO="unsloth/DeepSeek-R1-Distill-Qwen-1.5B-GGUF"
      MODEL_FILE="DeepSeek-R1-Distill-Qwen-1.5B-Q4_K_M.gguf"
      MODEL_LABEL="DeepSeek-R1-Distill-Qwen-1.5B (Q4_K_M)"
      MODEL_ALIAS="deepseek-r1-qwen-1.5b"
    fi
    CTX_SIZE=2048
    MAP_TOKENS=0
    MAX_FEEDBACK_CHARS=1200
    ;;
  6gb)
    if [ "$ROLE" = "coding" ]; then
      MODEL_REPO="unsloth/Qwen2.5-Coder-1.5B-Instruct-GGUF"
      MODEL_FILE="qwen2.5-coder-1.5b-instruct-q4_k_m.gguf"
      MODEL_LABEL="Qwen2.5-Coder-1.5B-Instruct (Q4_K_M)"
      MODEL_ALIAS="qwen2.5-coder-1.5b"
    else
      MODEL_REPO="unsloth/DeepSeek-R1-Distill-Qwen-1.5B-GGUF"
      MODEL_FILE="DeepSeek-R1-Distill-Qwen-1.5B-Q4_K_M.gguf"
      MODEL_LABEL="DeepSeek-R1-Distill-Qwen-1.5B (Q4_K_M)"
      MODEL_ALIAS="deepseek-r1-qwen-1.5b"
    fi
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
# /raw/ (not /resolve/) returns the literal git-lfs pointer text for an
# LFS-tracked path -- a few plain-text lines including "oid sha256:<hex>" --
# served directly by HF's own storage backend, never redirected to a CDN.
POINTER_URL="https://huggingface.co/${MODEL_REPO}/raw/main/${MODEL_FILE}"
MODELS_DIR="$HOME/models"
LLAMA_DIR="$HOME/llama.cpp"
PROFILE_DIR="$HOME/.offlinetweaker"
PROFILE_FILE="$PROFILE_DIR/profile.env"

echo "OfflineTweaker Android setup"
echo "Tier: $TIER ($ROLE) -> $MODEL_LABEL"
echo "Threads: $THREADS (from $CORES CPU cores)"
echo

echo "[1/6] Requesting storage access (needed to persist the model download)..."
termux-setup-storage || true

echo "[2/6] Installing build toolchain..."
pkg update -y
# rust: aider-chat pulls in fastuuid (a Rust/maturin extension) with no
# Termux wheel, so pip builds it from source -- and maturin's own rustup
# bootstrap can't target Termux's host triple, failing outright. Termux's
# own `rust` package sidesteps that by putting a working cargo/rustc on
# PATH before pip ever tries. Likely also covers `tokenizers` (same
# maturin backend, same missing-wheel situation).
#
# python-psutil: psutil's setup.py hard-refuses to build when
# sys.platform == "android" (Termux's on-device Python reports that, not
# "linux"), no fallback. Termux ships a prebuilt python-psutil at the
# exact version aider-chat pins, so pip sees it already satisfied and
# never touches psutil's broken build path.
pkg install -y git cmake golang clang make curl python rust python-psutil

# libjpeg-turbo/freetype/libpng/zlib: Pillow (an aider-chat dependency)
# has no Termux wheel and needs these headers to build from source.
# Not sufficient alone -- INCLUDE/LDFLAGS also have to be set for the
# pip install itself, see the export right before step [6/6] below.
pkg install -y libjpeg-turbo freetype libpng zlib

echo "[3/6] Building llama.cpp (native, CPU-only)..."
if [ ! -d "$LLAMA_DIR" ]; then
  git clone --depth 1 https://github.com/ggml-org/llama.cpp "$LLAMA_DIR"
else
  echo "llama.cpp already cloned, pulling latest..."
  git -C "$LLAMA_DIR" pull --ff-only || true
fi

# llama.cpp derives a UI-asset version tag from `git rev-list --count
# HEAD`, which is bogus on this --depth 1 clone and 404s fetching web-UI
# assets otherwise. Must be set before `cmake -S/-B` (configure time),
# setting it before `cmake --build` doesn't take effect.
export HF_UI_VERSION=latest
cmake -S "$LLAMA_DIR" -B "$LLAMA_DIR/build" -DCMAKE_BUILD_TYPE=Release -DGGML_NATIVE=ON
cmake --build "$LLAMA_DIR/build" --config Release -j"$(nproc)"

echo "[4/6] Downloading $MODEL_LABEL..."
mkdir -p "$MODELS_DIR"
MODEL_PATH="$MODELS_DIR/$MODEL_FILE"
CHECKSUM_PATH="$MODEL_PATH.sha256"
TMP_PATH="$MODEL_PATH.part"

# Fetches the expected sha256 from HF's /raw/ git-lfs pointer file --
# a small plain-text response served directly from HF's storage, never
# redirected through the CDN -- instead of scraping a header that can
# vary across CDN redirect hops. --max-filesize caps this at 64KB (real
# pointer files are well under 200 bytes) so a wrong assumption fails
# fast instead of pulling a multi-GB response through this code path.
fetch_expected_sha256() {
  curl -sL -m 30 --max-filesize 65536 "$POINTER_URL" \
    | awk -F'sha256:' '/^oid sha256:/ {print $2}' | tr -d '[:space:]'
}

# Locks the model file read-only after verification so nothing later can
# silently modify already-verified weights. chmod 444 is the reliable
# part; chattr +i is a best-effort bonus that normally no-ops (Termux is
# unprivileged) but blocks even `rm -f` if it *does* succeed (root/tsu) --
# verify_checksum's cleanup below runs `chattr -i` first for that case.
lock_model_file() {
  chmod 444 "$MODEL_PATH" 2>/dev/null || true
  chattr +i "$MODEL_PATH" 2>/dev/null || true
}

verify_checksum() {
  # $1 = path to the file being checked, $2 = expected sha256 (may be empty
  # if HF didn't send one). Never mutates $MODEL_PATH directly -- the caller
  # decides what happens to the path that was actually checked.
  local path="$1" expected="$2" actual
  if [ -z "$expected" ]; then
    echo "WARNING: couldn't fetch an expected checksum from HuggingFace; skipping integrity check for $MODEL_FILE." >&2
    return 0
  fi
  if ! command -v sha256sum >/dev/null 2>&1; then
    echo "WARNING: sha256sum not found; skipping integrity check for $MODEL_FILE." >&2
    return 0
  fi
  actual="$(sha256sum "$path" | awk '{print $1}')"
  if [ "$actual" != "$expected" ]; then
    echo "ERROR: checksum mismatch for $MODEL_FILE." >&2
    echo "  expected: $expected" >&2
    echo "  actual:   $actual" >&2
    echo "Deleting the corrupted/tampered download. Re-run this script to retry." >&2
    # Clears the immutable attribute first in case a prior run's
    # lock_model_file() set it (root/tsu only) -- it blocks rm -f otherwise.
    chattr -i "$path" 2>/dev/null || true
    rm -f "$path"
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
    verify_checksum "$MODEL_PATH" "$(fetch_expected_sha256)"
  fi
  lock_model_file
else
  # Downloads to a temp path and verifies before anything lands at
  # MODEL_PATH, so an unverified/tampered file is never observable at the
  # canonical path. -C - resumes an interrupted download (falls back to a
  # full download if $TMP_PATH doesn't exist yet). If $TMP_PATH is already
  # larger than the real remote file, the server answers 416 and curl
  # silently no-ops without erroring -- verify_checksum below is what
  # actually catches that case, not curl's exit code.
  if [ -f "$TMP_PATH" ]; then
    have_bytes="$(wc -c < "$TMP_PATH" 2>/dev/null || echo 0)"
    echo "Found a partial download from a previous run ($have_bytes bytes) -- resuming instead of starting over."
  fi
  EXPECTED_SHA256="$(fetch_expected_sha256)"
  curl -L --fail -C - -o "$TMP_PATH" "$MODEL_URL"
  verify_checksum "$TMP_PATH" "$EXPECTED_SHA256"
  mv -f "$TMP_PATH" "$MODEL_PATH"
  lock_model_file
fi

echo "[5/6] Writing server launcher and saved profile..."
# MODEL_SIZE_MB is baked in from the real downloaded file (not guessed)
# for run-model.sh's own pre-flight memory check below.
MODEL_SIZE_MB=$(( $(wc -c < "$MODEL_PATH") / 1024 / 1024 ))
cat > "$HOME/run-model.sh" << EOF
#!/data/data/com.termux/files/usr/bin/bash
# Launches $MODEL_LABEL as a local OpenAI-compatible server.
# Acquires its own wake-lock (best-effort, ships with base Termux) and
# releases it on exit -- this only stops CPU sleep, not the low-memory
# killer, see the check below for that.
command -v termux-wake-lock >/dev/null 2>&1 && termux-wake-lock
trap 'command -v termux-wake-unlock >/dev/null 2>&1 && termux-wake-unlock' EXIT
# Refuses to launch if free RAM looks too low for the model, instead of
# starting anyway and getting Termux killed by Android's low-memory
# killer with no explanation. --force skips this (rough estimate, can be
# wrong either way -- it doesn't know the model's real KV cache size).
FORCE=""
case "\${1:-}" in
  --force) FORCE=1 ;;
esac
MODEL_SIZE_MB=$MODEL_SIZE_MB
AVAILABLE_MB="\$(awk '/MemAvailable/ {print int(\$2/1024)}' /proc/meminfo)"
NEEDED_MB=\$(( MODEL_SIZE_MB * 12 / 10 + 300 ))
if [ -n "\$AVAILABLE_MB" ] && [ "\$AVAILABLE_MB" -lt "\$NEEDED_MB" ] && [ -z "\$FORCE" ]; then
  echo "Only \${AVAILABLE_MB}MB free, this model probably needs around" >&2
  echo "\${NEEDED_MB}MB. Not starting it -- Android would likely kill" >&2
  echo "Termux partway through with no explanation, which is worse than" >&2
  echo "not starting at all." >&2
  echo >&2
  echo "Close some background apps and try again, or re-run" >&2
  echo "termux-setup.sh with a smaller --ram tier to switch to a model" >&2
  echo "that fits more comfortably." >&2
  echo >&2
  echo "Think this estimate is wrong for your case? Run again with:" >&2
  echo "  ~/run-model.sh --force" >&2
  exit 1
fi
echo "Loading $MODEL_LABEL... first launch can take a while on phone CPUs" \\
  "with no progress output in between -- that's expected, not a hang."
# Not exec'd, so the EXIT trap above (wake-unlock) still fires on exit.
"$LLAMA_DIR/build/bin/llama-server" \\
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
MODEL_ROLE=$ROLE
MODEL_ALIAS=$MODEL_ALIAS
MODEL_LABEL="$MODEL_LABEL"
CTX_SIZE=$CTX_SIZE
THREADS=$THREADS
MAP_TOKENS=$MAP_TOKENS
MAX_FEEDBACK_CHARS=$MAX_FEEDBACK_CHARS
EOF

echo "[6/6] Installing Aider (terminal coding agent) and writing its launcher..."
# INCLUDE/LDFLAGS: Pillow (an aider-chat dep) has no Termux wheel and its
# setup.py needs these to find the jpeg/freetype/png/zlib headers
# installed in step [2/6] -- it does its own probing, not pkg-config.
export INCLUDE="$PREFIX/include"
export LDFLAGS=" -lm"
# Do NOT `pip install --upgrade pip` -- Termux's python-pip package
# refuses that outright, deliberately, so pip stays in sync with what
# `pkg` tracks. Use `pkg install -y python-pip` instead if pip itself
# ever needs to be newer.
#
# aider-chat>=0.85 is a floor, not just a minimum version: letting pip
# resolve unconstrained can backtrack into an old release pinning
# numpy==1.24.3, which needs the numpy.distutils module Python removed
# in 3.12 and is unbuildable there. --ignore-requires-python works
# around aider-chat's metadata capping supported Python below what
# Termux ships (3.13); it's mostly pure Python so this is a safe bet.
#
# Three of aider-chat's own pinned dependencies don't build on Termux,
# so they're excluded from the real install below via a stub-wheel
# trick (see AIDER_TMPDIR block): pip is pointed at a hand-built decoy
# wheel for each during resolution, so it never needs their real
# (broken) metadata, then the actual install uses an explicit pinned
# list with that package's name dropped out entirely.
#   - hf-xet==1.2.0: its published sdist is missing its own Python
#     bindings (upstream packaging bug, breaks on any platform building
#     from source, not Termux-specific). huggingface_hub already
#     degrades gracefully without it, and nothing in aider-chat's own
#     code imports it, so it's simply left out.
#   - scipy==1.15.3: needs a Fortran+BLAS/LAPACK toolchain Termux
#     doesn't ship, and Termux's own maintainers mark on-device scipy
#     builds unsupported even in their own build farm. Nothing in
#     aider-chat's actually-reachable import graph touches scipy
#     (checked the full dependency tree, not just aider-chat's own
#     code), so it's left out the same way as hf-xet.
#   - tree-sitter-c-sharp==0.23.1: its sdist is missing a bundled C
#     header (upstream packaging bug, fixed in 0.23.5+). Unlike the two
#     above, this one IS needed, so a working >=0.23.5 is installed for
#     real further down, right after the audioop-lts fix.
AIDER_TMPDIR="$(mktemp -d)"
# Cleaned up via trap so a failure partway through (a real pip error, not
# the exclusion workaround) doesn't leak the tmpdir -- set -e would
# otherwise skip past explicit cleanup placed at the end of this block.
trap 'rm -rf "$AIDER_TMPDIR"' EXIT

cat > "$AIDER_TMPDIR/find_pinned_version.py" << 'PYEOF'
# Prints the exact version from aider-chat's own bare "<name>==X" pin (if
# any) for the package named in argv[2], read from a --no-deps --report.
# Prints nothing if aider-chat no longer pins it that way -- callers
# treat that as "nothing to work around", so a future aider-chat release
# dropping the pin degrades gracefully instead of assuming it forever.
import json
import re
import sys

with open(sys.argv[1]) as f:
    report = json.load(f)
target = sys.argv[2]

pin = ""
for item in report["install"]:
    meta = item["metadata"]
    for req in meta.get("requires_dist") or []:
        m = re.match(r"^\s*([A-Za-z0-9][A-Za-z0-9._-]*)\s*==\s*([^\s;]+)\s*$", req)
        if not m:
            continue
        if re.sub(r"[-_.]+", "-", m.group(1)).lower() == target:
            pin = m.group(2)
print(pin)
PYEOF

cat > "$AIDER_TMPDIR/build_stub_wheel.py" << 'PYEOF'
# Hand-builds a minimal, valid wheel (stdlib zipfile, no `wheel`/`build`
# package needed) for the given name/version. Real METADATA/WHEEL/RECORD
# files, zero actual code -- only ever needs to satisfy pip's dependency
# resolution, never gets imported, and must never end up in the real
# installed environment (see the excluded-packages note above).
import sys
import zipfile

name, version, out_dir = sys.argv[1], sys.argv[2], sys.argv[3]
dist_info = f"{name}-{version}.dist-info"
whl_path = f"{out_dir}/{name}-{version}-py3-none-any.whl"

metadata = (
    f"Metadata-Version: 2.1\nName: {name}\nVersion: {version}\n"
    "Summary: OfflineTweaker resolution-only placeholder -- never actually "
    "installed or imported. See android/termux-setup.sh.\n"
)
wheel = (
    "Wheel-Version: 1.0\nGenerator: offlinetweaker-termux-setup\n"
    "Root-Is-Purelib: true\nTag: py3-none-any\n"
)

with zipfile.ZipFile(whl_path, "w", zipfile.ZIP_DEFLATED) as zf:
    zf.writestr(f"{dist_info}/METADATA", metadata)
    zf.writestr(f"{dist_info}/WHEEL", wheel)
    zf.writestr(f"{dist_info}/RECORD", "")
print(whl_path)
PYEOF

cat > "$AIDER_TMPDIR/filter_report.py" << 'PYEOF'
# Reads a full --report for aider-chat, writes every resolved package as
# an explicit "name==version" pin except the ones named in argv[3:]
# (matched by normalized name), for a follow-up --no-deps install.
import json
import re
import sys

report_path, out_path = sys.argv[1], sys.argv[2]
exclude = set(sys.argv[3:])
with open(report_path) as f:
    report = json.load(f)

skipped = []
with open(out_path, "w") as out:
    for item in report["install"]:
        meta = item["metadata"]
        name, version = meta["name"], meta["version"]
        if re.sub(r"[-_.]+", "-", name).lower() in exclude:
            skipped.append(f"{name}=={version}")
            continue
        out.write(f"{name}=={version}\n")

if skipped:
    print("Excluding from install (broken/unsupported upstream build): " + ", ".join(skipped))
else:
    print(
        "NOTE: none of the excluded packages were in the resolved graph at "
        "all -- the stub wheels may not have been needed this run.",
        file=sys.stderr,
    )
PYEOF

echo "Checking aider-chat's own pinned versions of the packages known to be"
echo "broken/unsupported to build on Termux (hf-xet, scipy, tree-sitter-c-sharp)..."
# --force-reinstall+--dry-run: forces pip to always report aider-chat's
# real metadata even if it's already installed (a plain --dry-run report
# would come back empty on a re-run and skip the exclusion checks below
# entirely, without --force-reinstall) while --dry-run guarantees nothing
# is actually touched.
pip install --ignore-requires-python --no-deps --dry-run --force-reinstall \
  --report "$AIDER_TMPDIR/aider_only_report.json" "aider-chat>=0.85"

# Keyed by normalized name (matches filter_report.py); value is the name
# handed to build_stub_wheel.py. hf-xet's known-broken/unneeded, scipy's
# known-broken/unneeded, tree-sitter-c-sharp's exact pin is broken but a
# working newer version gets installed for real further down.
declare -A EXCLUDED_PKG_STUB_NAME=(
  [hf-xet]=hf_xet
  [scipy]=scipy
  [tree-sitter-c-sharp]=tree_sitter_c_sharp
)

mkdir -p "$AIDER_TMPDIR/stub"
EXCLUDED_FOUND=()
for pkg_norm in "${!EXCLUDED_PKG_STUB_NAME[@]}"; do
  pin="$(python3 "$AIDER_TMPDIR/find_pinned_version.py" "$AIDER_TMPDIR/aider_only_report.json" "$pkg_norm")"
  if [ -n "$pin" ]; then
    echo "aider-chat pins $pkg_norm==$pin -- excluding it (see comment above)."
    python3 "$AIDER_TMPDIR/build_stub_wheel.py" \
      "${EXCLUDED_PKG_STUB_NAME[$pkg_norm]}" "$pin" "$AIDER_TMPDIR/stub" >/dev/null
    EXCLUDED_FOUND+=("$pkg_norm")
  fi
done

if [ ${#EXCLUDED_FOUND[@]} -eq 0 ]; then
  echo "No unconditional pins for the known-broken packages found in"
  echo "aider-chat's metadata -- the workaround doesn't apply this run,"
  echo "installing normally."
  pip install --ignore-requires-python "aider-chat>=0.85"
else
  echo "Resolving with throwaway local stubs so pip never needs the excluded"
  echo "packages' real (broken/unsupported) metadata, then installing"
  echo "everything else for real."
  AIDER_VERSION="$(python3 -c "
import json
with open('$AIDER_TMPDIR/aider_only_report.json') as f:
    print(json.load(f)['install'][0]['metadata']['version'])
")"
  # Deliberately NOT --force-reinstall here (unlike the detection step
  # above): letting pip skip packages already satisfied from a previous
  # run is what makes re-running this script cheap and resumable.
  pip install --ignore-requires-python --dry-run \
    --report "$AIDER_TMPDIR/full_report.json" \
    --find-links "$AIDER_TMPDIR/stub" \
    "aider-chat==$AIDER_VERSION"
  python3 "$AIDER_TMPDIR/filter_report.py" \
    "$AIDER_TMPDIR/full_report.json" "$AIDER_TMPDIR/pinned_specs.txt" \
    "${EXCLUDED_FOUND[@]}"
  pip install --ignore-requires-python --no-deps -r "$AIDER_TMPDIR/pinned_specs.txt"
fi
# No explicit rm here -- the trap above already handles normal completion
# and (more importantly) a pip failure partway through either branch,
# which set -e would otherwise abort past before reaching cleanup here.

# aider-chat pulls in pydub, which unconditionally does `import audioop`
# (falling back to a `pyaudioop` package that doesn't exist on PyPI) via
# aider/voice.py -- imported unconditionally by aider/commands.py, so
# this breaks aider's entire CLI, not just voice, on any Python that
# doesn't have audioop. Python removed the stdlib `audioop` module in
# 3.13, which is what Termux ships. audioop-lts is the official
# CPython-team backport (installs as a drop-in top-level `audioop`
# module) and isn't in aider-chat's own dependency graph at all (pydub
# predates the removal), so it's added explicitly here. Guarded on
# import so re-runs / older Pythons that still have the stdlib module
# skip the extra pip call.
if ! python3 -c "import audioop" >/dev/null 2>&1; then
  echo "Python's stdlib audioop module is gone (removed in 3.13) and pydub"
  echo "(an aider-chat dependency, imported unconditionally by aider itself)"
  echo "needs it -- installing the official backport."
  pip install --ignore-requires-python audioop-lts
fi

# The stub exclusion above only stops aider-chat's broken 0.23.1 pin from
# being installed for real, it doesn't install a working version -- 0.23.5
# bundles the header 0.23.1's sdist is missing, so that's installed here
# instead. Guarded on import, same pattern as audioop-lts above.
if ! python3 -c "import tree_sitter_c_sharp" >/dev/null 2>&1; then
  echo "aider-chat pins a tree-sitter-c-sharp release whose sdist is"
  echo "missing a bundled header and can't build on Termux -- installing"
  echo "a newer release with the same (incomplete-sdist) bug already"
  echo "fixed upstream instead."
  pip install --ignore-requires-python --no-deps "tree-sitter-c-sharp>=0.23.5"
fi

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
echo "  1. ~/run-model.sh              # starts the model on http://127.0.0.1:8080"
echo "     (acquires its own wake-lock, no separate termux-wake-lock step needed)"
echo "  2a. Open http://127.0.0.1:8080 in Chrome for the built-in chat UI, or"
echo "  2b. In a second Termux session: cd your-project && ~/aider-local.sh"
echo "      for a manual agentic coding CLI, or android/agent-loop.sh for the"
echo "      autonomous write-test-fix loop (reads this saved profile"
echo "      automatically, no flags needed)."
echo
echo "Model: $MODEL_LABEL (alias: $MODEL_ALIAS, role: $ROLE)"
echo "Context: $CTX_SIZE tokens | Threads: $THREADS"
echo "Profile saved to: $PROFILE_FILE"
