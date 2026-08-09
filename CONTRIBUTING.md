# Contributing to OfflineTweaker

Thanks for looking at this. It's a small project, so the bar is mostly
"does it work and is it explained" rather than a formal process.

## Before you start

For anything more than a small fix, open an issue first describing what
you want to change and why -- saves both of us from a PR that doesn't fit
where the project's headed. Small fixes (typos, broken commands, a
clarified comment) can just be a PR.

## Repo layout

- `setup.sh` -- generates the Docker desktop stack (Ollama + code-server +
  open-webui + Continue config). Idempotent: re-running it must never
  clobber a file a user has already customized (see the `[ ! -f ... ]`
  guards throughout).
- `android/` -- on-device setup via Termux + native llama.cpp
  (`termux-setup.sh`) and its build-loop wrapper (`agent-loop.sh`).
- `cloud/agent-loop.sh` -- points the build loop at a rented VM (SSH
  tunnel) or a third-party hosted API instead of a local model.
- `agent/build-loop.sh` -- the shared autonomous build loop every wrapper
  above calls into. Changes here affect desktop, Android, and cloud at
  once, so test against more than one call site if you touch it.

## Making changes

- **Shell style**: match what's already there -- `set -e`/`set -u` at the
  top, long-option flags (`--foo bar`), comments that explain *why* a line
  exists when it's not obvious from the code (see existing scripts for the
  tone). Keep lines readable in a phone-width terminal where reasonable,
  since Android is a first-class target here.
- **Run ShellCheck locally** before opening a PR -- this is exactly what CI
  runs, so catching it locally saves a round-trip:
  ```bash
  shellcheck --severity=warning $(git ls-files '*.sh')
  ```
- **Test what you can, say what you couldn't.** Most of this repo is shell
  scripts gluing together Docker, Termux, and hosted APIs -- there's no
  unit test suite. If you can run the actual flow (bring the Docker stack
  up, run the script on a real or emulated Android device, exercise the
  build loop against a real model), do that and say so in the PR. If you
  can't (no device, no network access to some service), say that too
  instead of leaving it implied -- reviewers need to know what was and
  wasn't actually exercised.
- **Update the README** alongside any change to setup/usage -- a script
  change with no doc update is often what created the drift this project
  is trying to avoid (see git history for prior instances of the two going
  out of sync).

## Safety-relevant changes

`agent/build-loop.sh` runs a model unattended with auto-commit enabled
(`--yes-always --auto-commits`), and the Android/cloud paths run it with no
sandbox. Changes that widen what it can do unattended (removing a
confirmation gate, defaulting to more autonomy, disabling a safety check)
need a clear explanation of why in the PR description -- don't loosen these
quietly as a side effect of something else.

## Opening the PR

- Keep the diff scoped to what the issue/description says -- unrelated
  drive-by fixes make review harder, split them out.
- Fill in the PR template's testing section honestly, per above.
