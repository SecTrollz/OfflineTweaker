# Troubleshooting

Real errors real devices hit running `android/termux-setup.sh` or
`~/run-model.sh`, what caused them, and how they got fixed. All of
these are already handled in the current script. If you hit one of
these on a fresh `git clone`, you're probably running a stale copy,
`git pull` first.

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

## Termux just closes when you run `~/run-model.sh`

User-reported: on a 6-8GB phone with the RAM tier auto-detected, no
manual `--ram` override, `run-model.sh` would run and then Termux would
close on its own, no crash log, no error, the rest of the phone kept
working fine.

Root cause: `termux-wake-lock` (which the quickstart already tells you
to run first) only stops the CPU from sleeping. It does nothing to stop
Android's low-memory killer from closing Termux outright if the system
is genuinely low on RAM when `llama-server` tries to load a multi-GB
model. The RAM tier gets picked once, at `termux-setup.sh` time, based
on total device RAM (`MemTotal`), not on how much is actually free at
the moment you later run `run-model.sh`, potentially much later, after
other apps have been opened. A phone with enough total RAM for the
picked tier can still not have enough *free* RAM right now.

Fixed: `run-model.sh` now checks `MemAvailable` from `/proc/meminfo`
against the model file's actual size before launching `llama-server`,
and refuses to start if it looks like Android would kill Termux
partway through anyway, instead of trying and letting it get killed
with no explanation. An earlier version of this fix only printed a
warning and launched anyway, which didn't actually stop the crash, it
just narrated it right before it happened, so this refuses by default
now.

This is still an estimate (it doesn't know the exact KV cache size for
every model architecture), not a guaranteed prediction, so it can be
wrong in either direction. If you think it's wrong for your case, or
you'd rather try anyway, `~/run-model.sh --force` skips the check.

If it's blocking you and you don't want to force it: close background
apps to free RAM, or re-run `termux-setup.sh --ram <a smaller tier>`
to switch to a model that fits more comfortably.

## `run-model.sh` runs, but everything freezes once you open the browser

Different symptom from "Termux just closes" above, don't confuse the
two: this one is a hang, not a crash. `llama-server` stays alive
(check with `ps` in another Termux session, or just look for its
output still sitting there), but requests to `http://127.0.0.1:8080`
never come back, and the page just spins.

Likely cause, based on documented Android platform behavior, not
confirmed on a specific device: opening `http://127.0.0.1:8080` in
Chrome means switching away from Termux, which puts it in the
background. `termux-wake-lock` only stops the CPU from sleeping
entirely, the same limited guarantee already noted above for the
OOM-kill case, but this is a different mechanism than that one: it
does nothing to stop Android's Doze mode, App Standby, or an OEM's own
battery manager (Samsung, Xiaomi/MIUI, OnePlus, and others all ship
their own on top of stock Android) from throttling a *backgrounded*
app's CPU down to a crawl. `llama-server` isn't killed the way it is
in the OOM case, it's just starved, so a request that would normally
take a couple seconds can sit unanswered for minutes, indistinguishable
from a true hang unless you already know to expect it.

Not fixed by anything in this script, this is Android platform
behavior on top of a process the script has no control over once it's
launched. Two ways around it:

- Keep Termux visible. Split-screen it with Chrome instead of fully
  switching away, so Android still treats it as foreground (or
  foreground-adjacent, depending on OEM) instead of backgrounding it.
- Or turn off battery optimization for Termux entirely: Android
  Settings → Apps → Termux → Battery → set to Unrestricted. Exact menu
  wording varies by OEM/Android version.

Either one keeps Termux out of the throttled state to begin with,
rather than trying to detect or recover from it after the fact.
