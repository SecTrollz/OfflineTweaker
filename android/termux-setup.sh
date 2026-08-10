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

# libjpeg-turbo/freetype/libpng/zlib: Pillow is another aider-chat
# dependency (pulled in via aider's image handling) that has no wheel for
# Termux's platform tag, so pip falls back to building it from source --
# and that
# build fails outright with "The headers or library files could not be
# found for jpeg, a required dependency when compiling Pillow from
# source", confirmed on a real device, because Termux ships none of
# Pillow's image-codec dependencies by default. Unlike scipy, this isn't a
# missing-toolchain problem Termux's maintainers have ruled out on-device
# -- it just needs the codec libraries' headers present before Pillow's
# setup.py runs. Installing them here is necessary but not sufficient on
# its own: confirmed on a real device that a plain `pip install pillow`
# after this line still fails the same way, and only succeeds once
# INCLUDE/LDFLAGS are also set for the pip install step itself (see the
# export right before step [6/6]'s installs, below) -- Pillow's
# setup.py does its own header/library probing rather than relying on
# pkg-config, and doesn't check $PREFIX/include unless told to.
pkg install -y libjpeg-turbo freetype libpng zlib

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
MODEL_ROLE=$ROLE
MODEL_ALIAS=$MODEL_ALIAS
MODEL_LABEL="$MODEL_LABEL"
CTX_SIZE=$CTX_SIZE
THREADS=$THREADS
MAP_TOKENS=$MAP_TOKENS
MAX_FEEDBACK_CHARS=$MAX_FEEDBACK_CHARS
EOF

echo "[6/6] Installing Aider (terminal coding agent) and writing its launcher..."
# INCLUDE/LDFLAGS for Pillow's from-source build: see the pkg install of
# libjpeg-turbo/freetype/libpng/zlib in step [2/6] above for why these are
# needed at all. Pillow's own setup.py does its own dependency probing
# (not pkg-config) and doesn't look at $PREFIX/include unless told to, so
# without this export its build fails even with the libraries already
# installed -- confirmed on a real device: `pip install pillow` alone
# still fails with the same missing-jpeg error after the pkg install
# above, and only succeeds with these two variables set for that same
# call. Scoped to this step (exported here, not earlier in the script)
# because nothing before this point invokes pip, and LDFLAGS in
# particular has no reason to leak into the cmake-driven llama.cpp build
# in step [3/6].
export INCLUDE="$PREFIX/include"
export LDFLAGS=" -lm"
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
#
# scipy: aider-chat 0.86.2's own metadata pins `scipy==1.15.3` bare, the
# same unconditional/unmarked way it pins hf-xet -- confirmed against the
# same pypi.org/pypi/aider-chat/0.86.2/json requires_dist. Real failure
# from a device that got past the two fixes above: pip falls back to
# scipy's sdist (its wheels are tagged manylinux/musllinux/macOS/Windows --
# confirmed against pypi.org/pypi/scipy/1.15.3/json -- nothing matches
# Termux's platform tag, same story as hf-xet), and that sdist's meson
# build needs a working Fortran compiler: "Unknown compiler(s):
# [['gfortran'], ['flang-new'], ['flang'], ...]". Termux ships none of
# those by default -- confirmed there's no `gfortran` package anywhere in
# termux-packages at all (Termux's toolchain is clang-based throughout);
# the closest things are two optional packages, `flang` (LLVM's Fortran
# frontend) and `lfortran` (an independent compiler project).
#
# Unlike hf-xet, this isn't a narrow upstream regression -- scipy's build
# genuinely needs a Fortran+BLAS/LAPACK toolchain, full stop, and scipy is
# a large, complex C/C++/Fortran/Cython/pythran codebase, nothing like
# fastuuid's single-crate Rust build. So the question here was which of two
# strategies is actually right: get a real Fortran toolchain working on
# Termux and let scipy build for real, or exclude it the same way as
# hf-xet, generalizing that same stub-decoy mechanism to a second package.
# Checked both rather than assuming.
#
# Whether scipy can actually be *made* to build on Termux: checked Termux's
# own package recipe for it, since if anyone has solved this it's Termux's
# own maintainers, who can throw far more machinery at it than a `pkg
# install flang` in this script ever could. Confirmed at
# raw.githubusercontent.com/termux/termux-packages/master/packages/python-scipy/build.sh
# (current as of writing): building scipy needs `termux_setup_flang` plus a
# hand-written `wrapper.py` shell that stands in for the real `FC` binary
# (i.e. flang can't just be invoked directly and expected to work through
# meson's normal compiler detection), a `python-numpy-static` build
# dependency, `pythran`, and a custom meson cross-file -- real
# cross-compilation scaffolding, not just "install a compiler and go". And
# the line right at the top of that same file settles it either way:
# `TERMUX_PKG_ON_DEVICE_BUILD_NOT_SUPPORTED=true` -- Termux's own
# maintainers, with all of the above already built and working in their CI,
# have explicitly marked on-device scipy builds unsupported. (Compare
# python-numpy's build.sh, confirmed the same way: no such flag, and it
# actively branches on `TERMUX_ON_DEVICE_BUILD == "true"`, i.e. numpy *is*
# meant to support building on-device -- so this isn't a blanket policy
# against all Python C-extension packages, it's specific to scipy.) Trying
# to replicate a from-scratch version of scaffolding Termux's own package
# system won't run on-device is not something this script should attempt.
# Even setting that aside, Termux's prebuilt python-scipy is version
# 1.18.0, not aider-chat's exact `==1.15.3` pin (confirmed same file,
# TERMUX_PKG_VERSION) -- same version-mismatch problem numpy/pillow have
# below, so it wouldn't satisfy the pin via the psutil trick even if it
# could be installed.
#
# Whether scipy is actually needed at all: confirmed by extracting
# aider-chat 0.86.2's real wheel and grepping every .py file inside for
# "import scipy"/"from scipy" -- zero hits outside the dist-info METADATA
# declaration, same signature as hf-xet. Went a step further than the
# hf-xet check, though, and didn't stop at aider-chat's own code: downloaded
# and extracted every other package actually reachable from aider-chat's
# real dependency graph (litellm's full wheel -- 14.5MB, covering every
# provider integration it vendors -- plus openai, huggingface-hub, tiktoken,
# tokenizers, soundfile, sounddevice, mixpanel, posthog, grep-ast,
# tree-sitter-language-pack, watchfiles, diskcache, pydub) and grepped all
# of them the same way. The only hit anywhere in that whole surface is
# pydub's own `pydub/scipy_effects.py` -- and that module is explicitly
# opt-in (its own docstring: "When this module is imported the high and low
# pass filters ... will be used ... instead of the ... versions provided by
# pydub"), never imported by pydub's own `__init__.py` (confirmed reading
# it: only `from .audio_segment import AudioSegment`) and never imported by
# aider-chat's own code (confirmed: aider/voice.py only does `from pydub
# import AudioSegment` / `from pydub.exceptions import ...`). So nothing in
# the actually-reachable import graph touches scipy, not even indirectly.
#
# Confirmed end-to-end in the same throwaway venv as the hf-xet check,
# using the generalized (see below) two-package version of the same
# stub-decoy mechanism: final environment has aider-chat installed,
# `aider --version` and `aider --help` both succeed, and starting aider
# pointed at a fake local OPENAI_API_BASE (so it reaches its first real
# network call, exercising far more of the import graph than --version
# alone -- litellm's provider dispatch, the OpenAI client construction,
# etc.) still produces no ImportError/ModuleNotFoundError anywhere before
# it fails on the fake connection, exactly as expected. importlib.metadata
# confirms scipy is genuinely absent afterward, same as hf-xet.
# Net conclusion: exclude it, the same way as hf-xet -- not attempt the
# on-device build Termux's own maintainers have already ruled out.
#
# tree-sitter-c-sharp: aider-chat 0.86.2 pins 0.23.1 bare -- confirmed by
# reaching it via `pip install aider-chat --dry-run --report`, though not
# independently confirmed by reading aider-chat's requires_dist directly
# the way the hf-xet/scipy pins were.
# PyPI ships no wheel for Termux's platform tag (same story as every
# other package on this list), so pip falls back to its sdist, and that
# build fails outright: "src/parser.c:1:10: fatal error:
# 'tree_sitter/parser.h' file not found" -- confirmed on a real device.
# Root cause confirmed directly, not guessed: downloaded the 0.23.1
# sdist and inspected its contents -- it has no tree_sitter/ directory
# at all, so the header genuinely isn't on the device anywhere, and no
# CPATH/C_INCLUDE_PATH override can fix that (confirmed live: setting
# C_INCLUDE_PATH to $PREFIX/include and re-running the same install
# still fails identically, because $PREFIX/include has no parser.h
# either -- no native `tree-sitter` package installed, confirmed via
# `pkg list-installed`). An earlier working theory here -- that the
# fix was a missing include-path override pointing at a separately
# installed `tree-sitter` package -- was wrong and has been dropped.
# The actual fix: downloaded the 0.23.5 sdist the same way and diffed
# it against 0.23.1's -- 0.23.5 bundles its own copy of the header at
# src/tree_sitter/{alloc,array,parser}.h, right next to parser.c/
# scanner.c, which include it via a relative path, so it builds
# standalone with no external tree-sitter headers needed at all.
# Confirmed live: `pip install tree-sitter-c-sharp==0.23.5` (no env
# overrides) succeeds outright on the same device where 0.23.1 fails.
# Upstream evidently fixed an incomplete-sdist packaging bug somewhere
# between those two releases; nothing about Termux specifically is at
# fault here.
# Because the fix is "use a newer version", not "exclude it", this
# package is still stubbed below (so pip's resolution against
# aider-chat's exact ==0.23.1 pin doesn't attempt the broken sdist at
# all and never even reaches this build), but -- unlike hf-xet/scipy,
# which are genuinely unneeded and left absent -- a working newer
# release is then installed for real, explicitly, right after the
# audioop-lts fix below (same guarded-by-`import` pattern, so re-runs
# don't reinstall it once it's satisfied).
AIDER_TMPDIR="$(mktemp -d)"
# set -e means a failure partway through this block (a real pip error, not
# the hf-xet workaround) skips straight past the cleanup at the bottom --
# trap guarantees $AIDER_TMPDIR is removed on any exit path, same pattern
# already used for the SSH tunnel in cloud/agent-loop.sh.
trap 'rm -rf "$AIDER_TMPDIR"' EXIT

cat > "$AIDER_TMPDIR/find_pinned_version.py" << 'PYEOF'
# Reads a --no-deps --report for aider-chat alone and prints the exact
# version from its own bare (unconditional, unmarked) "<name>==X" pin, if
# any, for the package name given as argv[2] (matched by normalized name,
# so hf-xet/hf_xet/HF.Xet all count as the same package). Prints nothing if
# aider-chat no longer pins it that way -- callers treat that as "nothing
# to work around for this package", not an error, so a future aider-chat
# release that drops or relaxes any one of these pins degrades gracefully
# back to installing that package normally instead of this script assuming
# a stale pin forever.
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
# an explicit "name==version" pin EXCEPT the packages named in argv[3:]
# (matched by normalized name, so hf-xet/hf_xet/HF.Xet all count as one),
# for a follow-up --no-deps install. See the big comment above this block
# for why each of those packages must be excluded rather than satisfied.
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
# tree-sitter-c-sharp is a special case among these three: hf-xet/scipy
# are excluded outright because they're genuinely unneeded (see their
# own writeups above), but tree-sitter-c-sharp's exact pinned version is
# excluded only to stop pip attempting its broken sdist -- a working
# newer version is installed for real further down, right after the
# audioop-lts fix.
# --force-reinstall is load-bearing here, confirmed by hitting the bug it
# fixes: on a *second* run (aider-chat already installed and satisfying
# ">=0.85"), a plain `--no-deps --dry-run --report` produces an install
# list -- and therefore a metadata section to inspect -- for every package
# that still needs (re)installing, which on a clean re-run is none. An
# empty report here would silently look identical to "aider-chat no longer
# pins any of these" and fall through to the plain-install branch below,
# which runs a normal (non-excluded) resolution and would try to satisfy
# them for real again -- reintroducing the exact broken-build failures this
# whole block exists to avoid. --force-reinstall makes pip always report
# aider-chat's real metadata regardless of what's already installed, while
# --dry-run still guarantees nothing is actually touched -- confirmed by
# running this exact combination twice in a throwaway venv and checking
# `pip show aider-chat` was byte-for-byte unchanged after.
pip install --ignore-requires-python --no-deps --dry-run --force-reinstall \
  --report "$AIDER_TMPDIR/aider_only_report.json" "aider-chat>=0.85"

# Packages aider-chat pins bare (no environment marker) whose install is
# known broken or unsupported on Termux -- see the case-by-case writeups
# above for why each one is here. Keyed by normalized name (matches
# filter_report.py's own normalization); value is the name handed to
# build_stub_wheel.py -- underscore form for hf-xet, matching how pip's own
# resolver reports it internally, though this is cosmetic: pip normalizes
# dashes/underscores when matching requirements either way.
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
    "$AIDER_TMPDIR/full_report.json" "$AIDER_TMPDIR/pinned_specs.txt" \
    "${EXCLUDED_FOUND[@]}"
  pip install --ignore-requires-python --no-deps -r "$AIDER_TMPDIR/pinned_specs.txt"
fi
# No explicit rm here -- the trap above already handles normal completion,
# and (more importantly) also covers a pip failure partway through either
# branch above, which set -e would otherwise abort past before reaching
# any cleanup placed here.

# Discovered while smoke-testing the exclusion workaround above (running
# `aider --version` all the way through on the same Python 3.13 Termux
# actually ships, not just checking that pip's install step succeeds) --
# this is a separate bug from scipy/hf-xet, but it sits directly in the
# same import path and would be the very next failure on-device once those
# are out of the way, so it's fixed here rather than left for a future
# round: aider-chat's own dependency graph pulls in pydub==0.25.1 (via
# aider/voice.py's unconditional `from pydub import AudioSegment  # noqa`,
# confirmed by reading that file), and pydub's utils.py unconditionally
# does `import audioop`, falling back to `import pyaudioop as audioop` only
# if that raises ImportError (confirmed by reading pydub 0.25.1's own
# utils.py). Python removed the `audioop` stdlib module outright in 3.13
# (deprecated since 3.11 per PEP 594, actually removed in 3.13) -- and
# Termux ships Python 3.13, the same version this file's
# --ignore-requires-python fix further up already exists for -- so on
# Termux's on-device Python, `import audioop` always raises
# ModuleNotFoundError. pydub's fallback name, `pyaudioop`, isn't a real
# installable package on PyPI at all (confirmed: no such project exists),
# so that fallback can't succeed either. Confirmed the actual failure
# directly, not just from reading the code: reproduced it in a throwaway
# venv running the exact Python 3.13.x Termux ships, with a completed
# aider-chat install (scipy/hf-xet both correctly excluded per the workaround
# above) -- a plain `aider --version` throws ModuleNotFoundError, and the
# traceback runs all the way through aider/main.py -> aider/coders/*.py ->
# aider/commands.py -> aider/voice.py -> pydub -- meaning this breaks
# aider's entire CLI outright, not just its voice feature, because
# commands.py imports voice.py unconditionally regardless of whether the
# user ever touches voice input.
# audioop-lts (https://pypi.org/project/audioop-lts/, confirmed current
# version 0.2.2 as of writing) is the official CPython-team-maintained
# backport -- despite its distribution name, it installs as a top-level
# `audioop` module, a drop-in replacement, not a separately-named package.
# Confirmed installing it into the same throwaway venv above makes `import
# audioop` succeed and `aider --version` print "aider 0.86.2" cleanly.
# It's not in aider-chat's own dependency graph at all -- pydub 0.25.1
# predates Python 3.13's audioop removal and was never updated to declare
# this conditionally -- so it has to be added here explicitly, it will
# never show up in the multi-phase install above no matter how aider-chat's
# own pins change.
# Like hf-xet and scipy, its wheels are tagged manylinux/musllinux/macOS/
# Windows/etc (confirmed against pypi.org/pypi/audioop-lts/json) -- nothing
# matches Termux's platform tag, so pip falls back to its sdist here too.
# Unlike those two, that's not a problem: confirmed by downloading that
# sdist directly and reading it, audioop-lts is a single plain C file
# (audioop/_audioop.c) built via ordinary setuptools (no maturin, no
# meson, no Fortran) -- confirmed it actually builds from that sdist in
# this sandbox with nothing more than a C compiler, the same category of
# build as fastuuid's, and Termux already has both a working C compiler
# (clang, installed on the pkg install line above) and the Python headers
# needed to build extensions against its own on-device Python (the same
# prerequisite fastuuid's build already depends on elsewhere in this
# script). Genuinely unverified without a real device: that this sdist
# actually compiles clean against Termux's specific clang/bionic
# combination -- same category of residual uncertainty already flagged for
# fastuuid/tokenizers above, not a new kind of risk.
# Guarded on whether `audioop` is actually missing rather than installed
# unconditionally: harmless either way in principle (Python's own import
# order resolves a real stdlib module before same-named site-packages code,
# so this wouldn't shadow anything on a Python that still has it), but
# there's no reason to spend a pip call and a compiled-wheel build on every
# run when the stdlib module is already there -- any Python < 3.13, or a
# future Termux release that ships something newer where this no longer
# applies.
if ! python3 -c "import audioop" >/dev/null 2>&1; then
  echo "Python's stdlib audioop module is gone (removed in 3.13) and pydub"
  echo "(an aider-chat dependency, imported unconditionally by aider itself)"
  echo "needs it -- installing the official backport."
  pip install --ignore-requires-python audioop-lts
fi

# tree-sitter-c-sharp: see the big comment above the AIDER_TMPDIR block
# for the full story -- aider-chat's exact ==0.23.1 pin has an
# incomplete sdist that can't build on Termux (or anywhere else without
# the header it's missing), confirmed by inspecting that sdist directly,
# and the stub exclusion above only stops that broken pin from being
# installed for real; it doesn't install any working version. 0.23.5's
# sdist bundles the header it's missing and was confirmed live to build
# clean with no env overrides needed, so that's what's installed here
# instead. Guarded on import, same pattern as audioop-lts just above,
# so re-runs don't reinstall it once satisfied. Genuinely unverified:
# whether grep-ast/tree-sitter-language-pack's C# support works
# identically against 0.23.5 as it would have against the 0.23.1 they
# actually pin -- both are 0.23.x point releases of an
# auto-generated-bindings package, so a breaking API change between
# them would be unusual, but this hasn't been exercised end-to-end
# (opening an actual C# file in aider) on a real device.
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
echo "  1. termux-wake-lock            # stop Android from suspending inference"
echo "  2. ~/run-model.sh              # starts the model on http://127.0.0.1:8080"
echo "  3a. Open http://127.0.0.1:8080 in Chrome for the built-in chat UI, or"
echo "  3b. In a second Termux session: cd your-project && ~/aider-local.sh"
echo "      for a manual agentic coding CLI, or android/agent-loop.sh for the"
echo "      autonomous write-test-fix loop (reads this saved profile"
echo "      automatically, no flags needed)."
echo
echo "Model: $MODEL_LABEL (alias: $MODEL_ALIAS, role: $ROLE)"
echo "Context: $CTX_SIZE tokens | Threads: $THREADS"
echo "Profile saved to: $PROFILE_FILE"
