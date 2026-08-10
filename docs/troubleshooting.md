# Troubleshooting

Real errors real devices hit while running `android/termux-setup.sh`,
what caused them, and how they got fixed. All of these are already
handled in the current script. If you hit one of these on a fresh
`git clone`, you're probably running a stale copy, `git pull` first.

If you hit something not on this list, open an issue with the exact
error text. That's how everything below got fixed in the first place.

## "Installing pip is forbidden, this will break the python-pip package (termux)"

Termux's own `python-pip` package refuses to let pip upgrade itself,
on purpose, so pip stays in sync with whatever Termux's package manager
thinks is installed. The script used to run `pip install --upgrade pip`
before installing Aider, which aborted the whole setup right there.
Fixed by removing that line. Aider installs fine on whatever pip
version Termux ships.

## "ERROR: Could not find a version that satisfies the requirement aider-chat>=0.85"

Two separate causes, both fixed:

- pip's resolver was backtracking into an old `aider-chat` release with
  a broken `numpy` pin. Fixed by giving `aider-chat>=0.85` as an
  explicit floor.
- `aider-chat`'s own metadata caps its supported Python version below
  what Termux ships. Fixed with `--ignore-requires-python` on the
  install.

## "Failed to build 'fastuuid' when installing"

`aider-chat` pulls in `fastuuid`, a Rust extension with no prebuilt
wheel for Termux's platform tag, so pip tries to build it from source.
That build needs a Rust toolchain, and `rustup`'s own bootstrap doesn't
know how to install one for Termux's host triple, so it fails outright,
not flakily. Fixed by installing Termux's own `rust` package before the
pip install ever runs, so `cargo`/`rustc` are already on `PATH` and the
broken rustup bootstrap path never gets hit.

## "python-source is set to ..., but the python module at ... does not exist" (hf-xet)

`aider-chat` pins `hf-xet`, a `huggingface_hub` acceleration package,
but the published source distribution for that pin is missing its own
Python bindings, an upstream packaging bug, not a Termux problem.
`huggingface_hub` itself already falls back gracefully to a normal HTTP
download when `hf-xet` isn't available. The script excludes it from
install entirely rather than fighting a package that was never actually
needed.

## "platform android is not supported" (psutil)

`psutil`'s own build script checks `sys.platform` and refuses to build
on anything it doesn't explicitly recognize, and Termux's Python
reports `"android"`, not `"linux"`. Termux ships its own native
`python-psutil` package at the exact version `aider-chat` needs, so the
script installs that through `pkg` first instead of letting pip try to
build it from source.

## "Unknown compiler(s): [['gfortran'], ...]" (scipy)

`scipy` needs a working Fortran compiler to build from source, and
Termux doesn't ship one by default. Termux's own package maintainers
mark on-device `scipy` builds as unsupported, even in their own build
farm it needs a hand-written Fortran wrapper and cross-compilation
scaffolding that isn't practical to replicate here. Nothing in
`aider-chat`'s actual code path imports `scipy`, so it's excluded from
install the same way `hf-xet` is.

## `ModuleNotFoundError` on `audioop` when running `aider --version`

Python removed the `audioop` standard library module in 3.13. `aider`
imports `pydub` unconditionally at startup (not just for voice
features), and `pydub` imports `audioop` unconditionally too, so this
breaks Aider's entire CLI on Termux's Python, whether you ever touch
voice input or not. Fixed with a guarded install of `audioop-lts`, the
official backport, only if the real `audioop` module isn't already
present.

## "The headers or library files could not be found for jpeg" (Pillow)

`aider-chat` depends on Pillow for image handling. Termux has no
prebuilt wheel for it, so pip builds it from source, and that build
needs jpeg, freetype, png, and zlib headers Termux doesn't install by
default. Fixed with `pkg install libjpeg-turbo freetype libpng zlib`
plus explicit `INCLUDE`/`LDFLAGS` exports before the pip install step.
Both parts matter: the headers alone aren't enough, because Pillow's
own build script doesn't check Termux's real install prefix from
inside pip's isolated build environment.

## "fatal error: 'tree_sitter/parser.h' file not found" (tree-sitter-c-sharp)

`aider-chat` pins `tree-sitter-c-sharp==0.23.1`, whose published source
distribution is missing its own bundled header file, an upstream
packaging bug fixed in a later release. The script excludes the broken
pinned version the same way as `hf-xet`/`scipy`, then installs
`tree-sitter-c-sharp>=0.23.5` for real, which bundles the header it
needs and builds clean.

## Model download keeps failing checksum verification

Older versions of this script deleted a partial download and started
over on every failure, and scraped an unreliable header to figure out
the expected checksum. Both fixed: downloads now resume with `curl -C -`
instead of restarting, and the expected checksum comes from
HuggingFace's own git-lfs pointer file, not a header that can vary
across CDN redirects.

## `https://huggingface.co/.../resolve/b3/dist.tar.gz` returns 404 (llama.cpp UI assets)

llama.cpp's own build derives a UI asset version from `git rev-list
--count HEAD`, which returns a bogus value on the shallow `--depth 1`
clone this script uses. Fixed by exporting `HF_UI_VERSION=latest`
before configuring the build.
