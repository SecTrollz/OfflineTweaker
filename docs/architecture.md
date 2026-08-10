# Architecture

How the pieces actually fit together. This is a shell-script project,
not a framework, every script here is meant to be readable end to end.

## The two runtimes

OfflineTweaker doesn't have one model backend, it has two, picked per
platform:

- **Desktop: Ollama in Docker.** `setup.sh` stands up Ollama alongside
  code-server, Continue.dev, and Open WebUI. Ollama handles model
  pulling, serving, and its own model format.
- **Android: llama.cpp, built natively.** `android/termux-setup.sh`
  clones and compiles llama.cpp directly on the phone, no prebuilt
  binary, no root. It downloads a single GGUF model file and serves it
  through `llama-server` on `127.0.0.1:8080`, an OpenAI-compatible API.

Both expose the same kind of local HTTP endpoint, which is what lets
the same agent tooling talk to either one.

## The common driver: Aider

Every coding workflow in this repo, manual or autonomous, goes through
[Aider](https://aider.chat) talking to one of those two local servers
over its OpenAI-compatible API. Aider is not a detail, it's the actual
thing doing the editing. The scripts here wrap it, they don't replace it.

## The autonomous loop

`agent/build-loop.sh` (desktop) and `android/agent-loop.sh` (Android)
implement the same idea against whichever backend is local:

1. Send Aider a task plus a short system preamble.
2. Aider edits the project.
3. Run the given `--test-cmd`.
4. On failure, feed the last N characters of test output back to Aider
   as the next instruction.
5. Repeat up to `--max-iters` times, or stop early on success.

`android/agent-loop.sh` is a thinner wrapper around the same core loop,
it reads `~/.offlinetweaker/profile.env` (written by `termux-setup.sh`)
to fill in the model alias, context size, and token budgets
automatically instead of taking them as flags.

## The saved profile

`termux-setup.sh` writes one file, `~/.offlinetweaker/profile.env`,
as the single source of truth for what got installed: RAM tier, model
role (reasoning or coding), model alias, context size, thread count,
and the per-tier token budgets. Every other Android script reads this
file instead of re-detecting or re-deriving any of it, so the tier
logic exists in exactly one place.

## The cloud bridge

`cloud/agent-loop.sh` is the same loop again, pointed at a model that
isn't local: either your own rented VM running the same `setup.sh`
stack, reached over an SSH tunnel by default, or a third-party hosted
API. Local execution is the default path through this whole repo,
cloud is an explicit opt-in that has to be asked for on the command
line every time, never a silent fallback.

## Model selection on Android

RAM gets read from `/proc/meminfo` and bucketed into a tier (3gb
through 16gb). Each tier maps to a specific GGUF model and quantization,
downloaded from HuggingFace with the checksum verified against the
repo's own git-lfs pointer file, not a header that can vary across a
CDN. Downloads resume instead of restarting on interruption, and the
finished file gets locked read-only so nothing modifies it silently
afterward.

`--role coding` swaps that tier-to-model mapping for a code-tuned model
on the tiers where one has actually been vetted, instead of the default
reasoning-focused pick. See the [model table](../README.md#on-device-android--termux)
in the README for the current mapping.
