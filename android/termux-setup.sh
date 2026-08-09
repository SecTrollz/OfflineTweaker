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
# /raw/ (not /resolve/) returns the literal git-lfs pointer text for an
# LFS-tracked path -- a few plain-text lines including "oid sha256:<hex>" --
# served directly by HF's own storage backend, never redirected to a CDN.
POINTER_URL="https://huggingface.co/${MODEL_REPO}/raw/main/${MODEL_FILE}"
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
# `rust` is here for aider-chat's transitive dependencies, not for anything
# built directly in this script. Confirmed from a real device: pip installing
# aider-chat pulls in fastuuid==0.14.0 (a Rust/maturin extension), and PyPI
# has no wheel for Termux's non-standard platform tag, so pip falls back to
# building it from source. That build's own dependency resolution needs
# maturin, and maturin's PEP 517 backend (confirmed by reading
# github.com/PyO3/maturin's maturin/__init__.py) only tries to bootstrap a
# Rust toolchain itself -- via the `puccinialin` helper, which is what prints
# the "Rust not found, installing into a temporary directory" line seen in
# the real failure -- when `shutil.which("cargo")` finds nothing on PATH.
# That bootstrap shells out to rustup, and rustup has no prebuilt toolchain
# for the `aarch64-unknown-linux-android` *host* triple Termux reports
# (rustup only knows that triple as a cross-compile target from a normal
# Linux/macOS host, not as an installable native toolchain when already
# running inside Android/Termux), so the bootstrap -- and the whole build --
# fails unconditionally on-device, not just flakily.
# Installing Termux's own `rust` package sidesteps all of that: it's built
# specifically to work as a native Termux-hosted toolchain (confirmed
# current as of writing, version 1.97.1, via
# raw.githubusercontent.com/termux/termux-packages/master/packages/rust/build.sh),
# and once its `cargo`/`rustc` land on $PREFIX/bin -- already on PATH for
# everything else in this script -- maturin's `shutil.which("cargo")` check
# finds them and never enters the broken rustup bootstrap path at all. No
# CARGO_HOME/RUSTUP_HOME exports needed: rustup is never invoked in this
# path, and pip's own build-isolation code (confirmed by reading
# pypa/pip's src/pip/_internal/build_env/{venv,virtual}.py) prepends its
# ephemeral build venv's bin dir to PATH rather than replacing it, so the
# rest of the inherited PATH -- including $PREFIX/bin -- still reaches the
# isolated build subprocess. Termux's `rust` package declares its own deps
# as clang, libandroid-execinfo, libc++, libllvm, lld, openssl, zlib, plus
# a target-specific rust-std-<triple> package it appends to its own
# DEPENDS at build time (not a literal static dependency name -- confirmed
# by reading the actual conditional in its build.sh, not just the static
# declaration at the top of the file). clang is already installed on the
# line below; `pkg`/`apt` resolves the rest on its own regardless of how
# it's assembled, so nothing else needs adding here.
#
# This same wall likely also catches `tokenizers` (HuggingFace's tokenizer
# library, another transitive aider-chat dependency, seen resolving to
# 0.22.2 in a real `pip install aider-chat --dry-run --report` run): PyPI
# publishes manylinux/musllinux/macOS/Windows/PyPy wheels for 0.22.2 but
# nothing that matches Termux's platform tag, and its own pyproject.toml
# (confirmed at github.com/huggingface/tokenizers, tag v0.22.2,
# bindings/python/pyproject.toml) declares the same `build-backend =
# "maturin"`, `requires = ["maturin>=1.0,<2.0"]` as fastuuid -- so the fix
# above should cover it too. Genuinely unverified past that point, on both
# packages, without a real Termux/aarch64 device: having a working
# rustc/cargo on PATH means the broken auto-bootstrap is skipped, but it
# doesn't guarantee either crate's Rust code actually *compiles* cleanly
# against Android's libc/linker (bionic) once a real compile is attempted --
# that's a different question than "does a toolchain exist", and neither
# this sandbox nor rustup's target list can answer it.
#
# `python-psutil` is here for a different reason than `rust` above: not a
# missing toolchain, but psutil's *own* build script deliberately refusing
# to build on Android at all. Confirmed from a real device: pip installing
# aider-chat 0.86.2 (its own bare, unconditional `psutil==7.2.2` pin --
# confirmed via pypi.org/pypi/aider-chat/0.86.2/json, requires_dist, same
# way the hf-xet pin was confirmed) fails getting build requirements for
# psutil with a one-line error: "platform android is not supported". That
# comes straight from psutil's own setup.py (confirmed by downloading the
# psutil-7.2.2 sdist directly from PyPI and reading it): it dispatches on
# LINUX/WINDOWS/MACOS/etc. constants from psutil/_common.py, where
# `LINUX = sys.platform.startswith("linux")`, and falls through to
# `sys.exit("platform {} is not supported".format(sys.platform))` if none
# match -- there's no ANDROID case and no generic fallback. The reason that
# branch is taken at all: CPython's own configure.ac (confirmed at
# github.com/python/cpython, tag v3.13.0) sets `MACHDEP="android"` for the
# `*-*-linux-android*` host triple, which becomes `sys.platform` at
# runtime -- so a CPython actually built to run *on* Android (Termux's
# on-device python, not a build-farm host python) reports "android", not
# "linux", and literally cannot take psutil's LINUX branch. This is a
# dispatch gap in psutil's own build script, not a toolchain problem
# rustc/cargo could fix and not a broken sdist like hf-xet -- there is no
# way to make a stock upstream psutil sdist build under Termux's current
# Python by adding anything to this line, or any line.
# Termux's own `python-psutil` package sidesteps this without needing to
# patch psutil: confirmed at
# raw.githubusercontent.com/termux/termux-packages/master/packages/python-psutil/build.sh
# (current as of writing; confirmed via a full listing of termux-packages'
# packages/ directory that this is the only psutil-related package name --
# no alias/rename to worry about), it pins TERMUX_PKG_VERSION="7.2.2" --
# an exact match to aider-chat's pin, unlike the hf-xet case where no
# working version existed at any pin. Its build never hits the branch
# above: termux-packages cross-compiles python packages using a *separate*
# host-side CPython built specifically to drive cross-compilation (see
# scripts/build/setup/termux_setup_build_python.sh in that same repo), and
# that host python is built for the CI machine's own triple, not
# `*-linux-android*` -- so it reports sys.platform=="linux", takes psutil's
# normal LINUX branch, and cross-compiles psutil/_psutil_linux.c for real
# against the aarch64-linux-android target via CC/LDFLAGS overrides. The
# check only ever fires on-device, which this package's build never runs
# on.
# Mechanism confirmed, not assumed, that this then makes the later
# multi-phase aider-chat install (step [6/6] below) skip building psutil
# itself: termux-packages' generic install step for any package with a
# setup.py/pyproject.toml and no more specific override -- psutil's case --
# is a plain `pip install --no-deps . --prefix $TERMUX_PREFIX` (confirmed
# in scripts/build/termux_step_make_install.sh), landing real
# dist-info/METADATA/RECORD files under
# $TERMUX_PREFIX/lib/python*/site-packages -- the same site-packages
# Termux's on-device pip/python already use, not some separate
# Termux-only registration format. Confirmed independently: that repo's
# own postinst-generation logic (scripts/build/termux_step_create_python_debscripts.sh)
# explicitly locates and reads a METADATA file at that same path, so this
# isn't just inferred from convention. Reproduced the actual pip-facing
# behavior this depends on in a throwaway venv in this sandbox: hand-planted
# a METADATA/RECORD pair for psutil==7.2.2 into site-packages (no wheel or
# sdist involved at all), then ran a plain `pip install psutil==7.2.2`
# against it -- pip printed "Requirement already satisfied: psutil==7.2.2"
# and never touched PyPI. Because aider-chat's pin (==7.2.2) and Termux's
# package version (7.2.2) match exactly, this script's step [6/6] pinned-list
# install (`pip install --no-deps -r pinned_specs.txt`, part of the hf-xet
# workaround below) should see psutil the same way and skip it -- psutil's
# setup.py is never invoked on-device at all. That step [6/6] flow installs
# straight into Termux's global site-packages, not an isolated venv --
# confirmed by reading this script, there's no `python -m venv` call in it
# -- so there's no separate-environment-invisibility concern between what
# `pkg` installs here and what pip sees later.
# Genuinely unverified without a real device: whether the live Termux apt
# repo's currently-published python-psutil .deb (TERMUX_PKG_REVISION=2 as
# of writing) actually matches what's checked into the git repo above at
# any given moment (ordinary mirror-lag risk, no different from any other
# package on this line) -- and whether `pip`'s own already-satisfied check
# (pip's internal metadata scanner, not stdlib importlib.metadata, though
# both should agree here) behaves identically on Termux's actual pip
# version as it did against pip 24.0 in this sandbox's throwaway venv.
pkg install -y git cmake golang clang make curl python rust python-psutil

echo "[3/6] Building llama.cpp (native, CPU-only)..."
if [ ! -d "$LLAMA_DIR" ]; then
  git clone --depth 1 https://github.com/ggml-org/llama.cpp "$LLAMA_DIR"
else
  echo "llama.cpp already cloned, pulling latest..."
  git -C "$LLAMA_DIR" pull --ff-only || true
fi

# llama.cpp's own build downloads its prebuilt web-UI assets from a
# HuggingFace bucket, versioned by a "b<N>" tag it derives from
# `git rev-list --count HEAD` (see its cmake/build-info.cmake). That count
# is meaningless on the --depth 1 clone above -- it only sees the handful
# of commits actually fetched, not the project's real history -- so it
# resolves to a small bogus version like "b3" that has never existed on
# HF, and the first thing the build does is 404 trying to fetch it. Their
# own script falls back to a "latest" candidate after that fails, so this
# is usually non-fatal on its own (confirmed: the build still succeeds
# either way, just without the embedded web UI if both attempts fail), but
# there's no reason to eat a guaranteed-failing request every single
# build. tools/ui/CMakeLists.txt reads this from the *environment*, not a
# -D cache flag (confirmed by testing both -- only the env var actually
# takes effect), and only at configure time, not build time -- it gets
# baked into the generated build command right then, so it has to be set
# before `cmake -S/-B`, not before `cmake --build`.
export HF_UI_VERSION=latest
cmake -S "$LLAMA_DIR" -B "$LLAMA_DIR/build" -DCMAKE_BUILD_TYPE=Release -DGGML_NATIVE=ON
cmake --build "$LLAMA_DIR/build" --config Release -j"$(nproc)"

echo "[4/6] Downloading $MODEL_LABEL..."
mkdir -p "$MODELS_DIR"
MODEL_PATH="$MODELS_DIR/$MODEL_FILE"
CHECKSUM_PATH="$MODEL_PATH.sha256"
TMP_PATH="$MODEL_PATH.part"

# Fetch the file's real sha256 before downloading so a corrupted, truncated,
# or swapped multi-GB download doesn't silently turn into "the model gives
# weird output" -- indistinguishable from normal small-model behavior to
# whoever's using this.
#
# This used to scrape the X-Linked-ETag header off a `curl -I -L` HEAD
# request to the /resolve/ URL -- but that means reading headers off every
# hop of a redirect chain through HF's CDN, and taking whichever occurrence
# came last. If more than one hop echoes that header (a CDN edge relaying
# its own copy, a stale cache, etc.) there's no guarantee the last one is
# the authoritative one from HF's own storage layer, and no way to tell
# from here. Fetching the /raw/ pointer file instead sidesteps that
# entirely: it's a small plain-text response served directly from HF's own
# git-lfs-backed storage, never redirected through the CDN, so there's
# exactly one place the hash can come from. --max-filesize caps this at
# 64KB (real pointer files are well under 200 bytes) so a wrong assumption
# here fails fast instead of accidentally pulling a multi-GB response
# through this code path.
fetch_expected_sha256() {
  curl -sL -m 30 --max-filesize 65536 "$POINTER_URL" \
    | awk -F'sha256:' '/^oid sha256:/ {print $2}' | tr -d '[:space:]'
}

# Locks the model file down once it's on disk so nothing after this point --
# another script, a buggy app, a later compromised process -- can silently
# modify weights that were already verified (or that we chose to accept
# unverified, e.g. sha256sum missing). This is best-effort, not a hard
# guarantee: Termux runs unprivileged with no root, so the ext4/f2fs
# "immutable" file attribute normally isn't available to it the way it
# would be on a rooted device or a normal Linux box -- chattr +i is
# attempted as a bonus on top of the reliable chmod 444, and its failure
# in the normal unprivileged case is expected, not a sign anything's wrong.
#
# IMPORTANT if it *does* succeed (root, a rooted phone, tsu, etc.): the
# immutable attribute blocks removal outright -- even `rm -f`, even for
# root -- until it's cleared. `chattr -i` before `rm -f` is what actually
# forces a refresh in that case; plain `rm -f` alone is only guaranteed to
# work when chattr silently no-opped, which is the common case here but
# not one this script can assume.
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
    # If a prior run's lock_model_file() got far enough to set the
    # immutable attribute on this path (only possible with elevated
    # privileges -- not the normal unprivileged-Termux case, but this must
    # not silently get stuck if it happens), that attribute blocks removal
    # outright, even with rm -f, even for root, until it's cleared first.
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
  # Download to a temp path and verify *before* anything ever lands at
  # MODEL_PATH -- an unverified or tampered file should never be
  # observable at the canonical path, even briefly.
  #
  # This is a multi-GB download over what might be a phone's cellular or
  # flaky wifi connection -- assume it can get interrupted (dropped
  # connection, Termux backgrounded and killed, phone locked mid-transfer)
  # partway through. -C - tells curl to resume from wherever $TMP_PATH
  # already left off instead of starting over from byte zero; if the file
  # doesn't exist yet (or is empty), curl transparently falls back to a
  # normal full download, so this is always the right flag to pass, not
  # just on a retry. If the final assembled file turns out wrong for any
  # reason (partial from a stale/replaced upstream file, disk corruption
  # in the already-downloaded portion, etc.), verify_checksum below still
  # catches it the same way it would a fresh download -- resuming never
  # weakens that guarantee, it only avoids re-fetching bytes that were
  # already there. Confirmed this matters, not just in theory: if
  # $TMP_PATH is somehow already *larger* than the real remote file (a
  # genuinely corrupted local state), the server correctly answers 416 and
  # curl -C - exits 0 without changing the file at all -- silently, no
  # error -- rather than detecting the mismatch itself. verify_checksum is
  # what actually catches that case, not curl's exit code.
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
# Do NOT `pip install --upgrade pip` here -- Termux's python-pip package
# refuses that outright ("Installing pip is forbidden, this will break the
# python-pip package (termux)"), deliberately, so pip stays in sync with
# what `pkg` tracks. That's not an occasional/environment-specific
# failure, it's unconditional on every Termux install, and because this
# whole script runs under `set -e`, hitting it here aborted the script
# before ever reaching the actual aider-chat install or writing the
# launcher below -- confirmed from a real user's run. If pip itself ever
# genuinely needs to be newer, the correct Termux-idiomatic way is
# `pkg install -y python-pip`, not pip upgrading itself.
# A bare `pip install aider-chat` can backtrack much further than you'd
# expect: if pip can't fully resolve the *latest* release's dependency
# tree in this environment, it keeps trying older and older releases
# looking for anything installable, and can land on one from aider-chat's
# early days that hard-pins exact old dependency versions (e.g.
# numpy==1.24.3). That specific numpy is unbuildable on Python 3.12+ --
# not slow, not flaky, unconditionally broken -- because it still depends
# on numpy.distutils, which needs the stdlib `distutils` module that
# Python removed in 3.12. A floor version keeps pip on aider-chat's modern
# dependency set (numpy pinned to something recent, which moved to the
# meson build system specifically because of the distutils removal)
# instead of ever considering those ancient pins. Bump the floor
# occasionally; the point isn't this exact number, it's staying clear of
# the old-pins era.
#
# --ignore-requires-python is separately load-bearing, confirmed from a
# real device: every current aider-chat release (0.83.0 through at least
# 0.86.2, checked live against PyPI) declares
# Requires-Python ">=3.10,<3.13" -- it hasn't yet been updated to declare
# support for 3.13, which is what Termux ships as of writing. Without this
# flag, pip refuses every version above ~0.16 outright on Python 3.13 and
# the floor above becomes unsatisfiable, which is worse than the original
# bug: it fails immediately instead of eventually backtracking into
# something installable. This bypasses that metadata check; aider-chat is
# mostly pure Python, so this is a reasonable bet, not a guaranteed fix --
# genuinely unverified past this point without a real Python 3.13/Termux
# device, since this sandbox can't simulate whether aider-chat's own
# pinned numpy version actually *builds* from source on 3.13 (no wheel for
# it exists yet), only that pip agrees to try.
#
# hf-xet: aider-chat 0.86.2's own metadata (confirmed live against
# https://pypi.org/pypi/aider-chat/0.86.2/json, requires_dist) pins
# `hf-xet==1.2.0` bare -- no environment marker, so pip must satisfy it on
# every platform, not just the x86_64/manylinux ones it presumably got
# tested on. hf-xet only ships wheels tagged manylinux/musllinux aarch64
# (and other desktop platforms) -- confirmed against
# https://pypi.org/pypi/hf-xet/1.2.0/json -- nothing matches Termux's
# platform tag, so pip falls back to the sdist. That sdist is broken:
# confirmed by downloading it directly from the URL in the same JSON and
# extracting it -- its pyproject.toml sets `[tool.maturin] python-source =
# "hf_xet/python"`, but that directory in the tarball contains only a
# `.gitkeep`, no actual `hf_xet` module. This fails identically on *any*
# platform forced to build from source, not just Termux -- confirmed by
# reproducing the exact same "Preparing metadata (pyproject.toml) ...
# error" / "python-source is set to ... does not exist" failure in a
# throwaway x86_64 venv via `pip install --no-binary=hf-xet hf-xet==1.2.0`.
# Checked a handful of neighboring releases the same way (download sdist,
# inspect python-source target): 1.1.10 and 1.2.1 have the identical
# missing-module defect; something changed by 1.3.0 -- its pyproject.toml
# drops the `python-source` key entirely (different maturin layout) -- so
# this looks like it was a real, if narrow, upstream regression window
# rather than an always-broken package. That's moot for us either way:
# aider-chat's pin is an exact `==1.2.0`, so pip won't consider 1.3.0+
# regardless of whether they're fixed.
#
# aider-chat itself never imports hf_xet or huggingface_hub's xet code
# path at all -- confirmed by extracting aider-chat's own sdist and
# grepping it for "hf_xet"/"hf-xet"; the only hit is the PKG-INFO
# dependency declaration, nothing in its actual source. huggingface_hub
# (pinned to 1.4.1 by aider-chat, also confirmed via the same PyPI JSON)
# is the thing that would use it, and is designed to degrade gracefully
# when hf_xet isn't installed -- confirmed by downloading huggingface_hub
# 1.4.1's own sdist and reading its source directly, not assuming: every
# call site (file_download.py, _commit_api.py) gates on
# utils._runtime.is_xet_available(), which is just an
# importlib.metadata-backed "is a package named hf_xet installed" check
# (_get_version() returns "N/A", caught, no exception) -- never a bare
# `import hf_xet`. The one unconditional `from hf_xet import ...` in that
# codebase lives in utils/_xet_progress_reporting.py, but that module is
# only ever imported lazily from inside _upload_xet_files(), which is
# itself only reached after is_xet_available() already gated "xet" out of
# the offered upload transfers -- so it's never actually imported when
# hf_xet is absent. file_download.py's downloader (the path aider-chat
# actually exercises, for tokenizer/model file lookups) checks the same
# flag and falls back to its normal http_get() with just a logger.warning,
# confirmed by reading that branch directly. Net effect, confirmed from
# source, not assumed: simply never installing hf_xet is safe, so long as
# it's genuinely absent -- NOT stubbed. A fake local hf_xet package would
# be actively worse than not installing it at all: is_xet_available() only
# checks that *a distribution named hf_xet is installed*, not that it
# works, so a stub would flip that check to True and then hit a real,
# confusing ImportError deep inside xet_get() on the first tokenizer
# download -- an install-time failure trading for a much worse silent
# runtime one. So the goal below is specifically "pip completes without
# hf_xet ending up installed at all", not "satisfy the requirement somehow".
#
# The obvious-looking fix -- resolve normally with `--dry-run --report`,
# then reinstall everything from that report except hf-xet -- does NOT
# work, confirmed by trying it in a throwaway venv: pip needs hf-xet's
# metadata to even finish resolving the graph "aider-chat>=0.85" pulls in,
# and *producing* metadata is exactly the step that's broken, dry run or
# not -- `pip install --dry-run --report r.json --no-binary=hf-xet
# "aider-chat>=0.85"` reproduces the identical maturin failure before ever
# writing a report. Checked pip's own docs/source for a native "resolve
# but skip this one dependency" flag too (the obvious next thing to try):
# doesn't exist -- pip 26.2.1's `install`/`download`/`wheel` --help have no
# such option, and the only `--exclude` flag anywhere in pip's source
# (checked cli/cmdoptions.py) belongs to `freeze`/`list`/`index`, for
# filtering command *output*, unrelated to dependency resolution.
#
# What actually works, confirmed end-to-end in a throwaway venv against
# the real aider-chat 0.86.2 / huggingface-hub 1.4.1 dependency graph
# (~108 packages): give pip a resolution-only decoy so it never needs
# hf-xet's real (broken) metadata in the first place, then do the actual
# install from an explicit pinned list that leaves hf-xet out entirely.
#   1. Ask pip (via --no-deps --dry-run --report) what exact version of
#      aider-chat it would pick, and pull the exact "hf-xet==X" pin out of
#      *that* package's own metadata. This step never touches hf-xet's
#      metadata at all -- --no-deps means pip only has to look at
#      aider-chat's own (working) metadata -- confirmed by running it.
#   2. Build a trivial local wheel -- hand-built with Python's stdlib
#      zipfile, no `wheel`/`build` package needed -- that just claims to
#      *be* hf-xet==X (real METADATA/WHEEL files, zero actual code inside).
#      Point pip at it with --find-links for the next step only. This
#      wheel is never installed into the real environment; see below.
#   3. Re-resolve the *full* "aider-chat==X" graph for real (no --no-deps
#      this time), with that --find-links dir available. Confirmed by
#      reading pip's own candidate-ranking code
#      (_internal/index/package_finder.py, PackageFinder._sort_key): a
#      matching wheel always outranks an sdist for the same version,
#      unconditionally, not just with --prefer-binary -- so wherever pip
#      would otherwise have had to fall back to hf-xet's broken sdist (no
#      matching real wheel for the platform), it picks our harmless local
#      stub instead and never invokes maturin on the real package at all.
#      Confirmed live (not just from reading the ranking code): simulating
#      "no real wheel available for this platform" with
#      --platform/--only-binary=:all: against the same stub reproduces
#      exactly this -- pip installs the stub with zero build attempted.
#      Genuinely unverified: watching this actual selection happen on a
#      real Termux/aarch64 run -- this sandbox is x86_64, where hf-xet
#      *does* publish a real wheel, so here pip picks PyPI's real one
#      over the stub (a more specific tag wins the tie-break) and the stub
#      sits unused -- which is fine, since step 4 excludes hf-xet by name
#      regardless of which one "won" here.
#   4. Take that resolution's --report JSON, drop the hf-xet entry (by
#      normalized name, so hf-xet/hf_xet/HF-Xet all match), and do the
#      real install from the rest as an explicit `name==version` list with
#      --no-deps. --no-deps here is what actually matters: it stops pip
#      from ever re-reading aider-chat's (or huggingface-hub's own
#      platform_machine-conditional hf-xet range's) metadata during this
#      pass, so the poisoned requirement is never seen a second time.
# Confirmed end-to-end in that throwaway venv: the final environment has
# aider-chat installed and working (`aider --version` succeeds), hf-xet
# genuinely absent (importlib.metadata can't find it), and
# huggingface_hub.utils.is_xet_available() correctly returns False. Could
# not confirm the resulting graceful-download-fallback fires on a real
# huggingface.co request in this sandbox specifically -- outbound access
# to huggingface.co (as opposed to pypi.org, which this whole
# investigation otherwise relied on) is blocked by this environment's
# proxy, unrelated to this fix.
AIDER_TMPDIR="$(mktemp -d)"
# set -e means a failure partway through this block (a real pip error, not
# the hf-xet workaround) skips straight past the cleanup at the bottom --
# trap guarantees $AIDER_TMPDIR is removed on any exit path, same pattern
# already used for the SSH tunnel in cloud/agent-loop.sh.
trap 'rm -rf "$AIDER_TMPDIR"' EXIT

cat > "$AIDER_TMPDIR/find_hfxet_pin.py" << 'PYEOF'
# Reads a --no-deps --report for aider-chat alone and prints the exact
# version from its own bare (unconditional, unmarked) "hf-xet==X" pin, if
# any. Prints nothing if aider-chat no longer pins it that way -- callers
# treat that as "nothing to work around", not an error, so a future
# aider-chat release that drops or relaxes this pin degrades gracefully
# back to a plain install instead of this script assuming a stale pin.
import json
import re
import sys

with open(sys.argv[1]) as f:
    report = json.load(f)

pin = ""
for item in report["install"]:
    meta = item["metadata"]
    for req in meta.get("requires_dist") or []:
        m = re.match(r"^\s*hf[-_.]?xet\s*==\s*([^\s;]+)\s*$", req, re.IGNORECASE)
        if m:
            pin = m.group(1)
print(pin)
PYEOF

cat > "$AIDER_TMPDIR/build_stub_wheel.py" << 'PYEOF'
# Hand-builds a minimal, valid wheel for the given name/version using only
# stdlib zipfile -- no `wheel`/`build` package needed as a bootstrap dep.
# Contains real METADATA/WHEEL/RECORD files and zero actual code: it only
# ever needs to satisfy pip's dependency *resolution*, never to be
# imported. See the big comment above this block for why it must never
# end up in the real installed environment.
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
# an explicit "name==version" pin EXCEPT hf-xet (matched by normalized
# name, so hf-xet/hf_xet/HF.Xet all count), for a follow-up --no-deps
# install. See the big comment above this block for why hf-xet must be
# excluded rather than satisfied.
import json
import re
import sys

report_path, out_path = sys.argv[1], sys.argv[2]
with open(report_path) as f:
    report = json.load(f)

skipped = []
with open(out_path, "w") as out:
    for item in report["install"]:
        meta = item["metadata"]
        name, version = meta["name"], meta["version"]
        if re.sub(r"[-_.]+", "-", name).lower() == "hf-xet":
            skipped.append(f"{name}=={version}")
            continue
        out.write(f"{name}=={version}\n")

if skipped:
    print("Excluding from install (broken upstream sdist): " + ", ".join(skipped))
else:
    print(
        "NOTE: hf-xet wasn't in the resolved graph at all -- the stub wheel "
        "may not have been needed this run.",
        file=sys.stderr,
    )
PYEOF

echo "Checking aider-chat's own pinned hf-xet version..."
# --force-reinstall is load-bearing here, confirmed by hitting the bug it
# fixes: on a *second* run (aider-chat already installed and satisfying
# ">=0.85"), a plain `--no-deps --dry-run --report` produces an install
# list -- and therefore a metadata section to inspect -- for every package
# that still needs (re)installing, which on a clean re-run is none. An
# empty report here would silently look identical to "aider-chat no longer
# pins hf-xet" and fall through to the plain-install branch below, which
# runs a normal (non-excluded) resolution and would try to satisfy hf-xet
# for real again -- reintroducing the exact broken-sdist failure this
# whole block exists to avoid. --force-reinstall makes pip always report
# aider-chat's real metadata regardless of what's already installed, while
# --dry-run still guarantees nothing is actually touched -- confirmed by
# running this exact combination twice in a throwaway venv and checking
# `pip show aider-chat` was byte-for-byte unchanged after.
pip install --ignore-requires-python --no-deps --dry-run --force-reinstall \
  --report "$AIDER_TMPDIR/aider_only_report.json" "aider-chat>=0.85"
HFXET_PIN="$(python3 "$AIDER_TMPDIR/find_hfxet_pin.py" "$AIDER_TMPDIR/aider_only_report.json")"

if [ -z "$HFXET_PIN" ]; then
  echo "No unconditional hf-xet pin found in aider-chat's metadata -- the"
  echo "known-broken-sdist workaround doesn't apply this run, installing normally."
  pip install --ignore-requires-python "aider-chat>=0.85"
else
  echo "aider-chat pins hf-xet==$HFXET_PIN, whose sdist is broken upstream (see"
  echo "comment above) -- resolving with a throwaway local stub so pip never"
  echo "needs hf-xet's real metadata, then installing everything else for real."
  AIDER_VERSION="$(python3 -c "
import json
with open('$AIDER_TMPDIR/aider_only_report.json') as f:
    print(json.load(f)['install'][0]['metadata']['version'])
")"
  mkdir -p "$AIDER_TMPDIR/stub"
  python3 "$AIDER_TMPDIR/build_stub_wheel.py" hf_xet "$HFXET_PIN" "$AIDER_TMPDIR/stub"
  # Deliberately NOT --force-reinstall here, unlike the detection step
  # above: this report is the actual install plan, and letting pip skip
  # packages already satisfied from a previous (maybe partial) run is what
  # makes re-running this script cheap and resumable -- a clean re-run
  # naturally reports zero installs and the pip call below becomes a
  # no-op, same idea as the resumable model download further up.
  pip install --ignore-requires-python --dry-run \
    --report "$AIDER_TMPDIR/full_report.json" \
    --find-links "$AIDER_TMPDIR/stub" \
    "aider-chat==$AIDER_VERSION"
  python3 "$AIDER_TMPDIR/filter_report.py" \
    "$AIDER_TMPDIR/full_report.json" "$AIDER_TMPDIR/pinned_specs.txt"
  pip install --ignore-requires-python --no-deps -r "$AIDER_TMPDIR/pinned_specs.txt"
fi
# No explicit rm here -- the trap above already handles normal completion,
# and (more importantly) also covers a pip failure partway through either
# branch above, which set -e would otherwise abort past before reaching
# any cleanup placed here.

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
