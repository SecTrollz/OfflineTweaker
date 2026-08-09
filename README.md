# WORLD DOMINATION PLAN NO.63

## OfflineTweaker
## Desktop (Docker)
Models: Qwen2.5-Coder series (desktop) / DeepSeek-R1 distills (on-device)
Agent modes:
- **Autonomous build loop** (`agent/build-loop.sh`): give it a task, it
  writes code, runs your tests, reads the failures, and fixes it itself —
  see [Autonomous Build Loop](#autonomous-build-loop) below.
- Continue.dev in VS Code: /edit, /run, codebase chat, autonomous refactoring
- Aider: `aider --model ollama/qwen2.5-coder:14b` in terminal
- Jupyter notebooks for scripts/REPL

Tips:
- `setup.sh` generates a random code-server password into `.env` on first
  run (printed once, never committed) and won't touch it again on re-runs —
  edit `.env` yourself to change it, then `docker compose up -d` to apply.
- Ports bind to 127.0.0.1 by default (safe on a shared/cloud box too) — see
  [Cloud](#cloud) for how to reach them from another device
- For GPU: add NVIDIA section in compose
- Image versions are pinned in `docker-compose.yml` (not `:latest`/`:main`)
  so an upstream push can't silently change a running stack. Override per
  image by setting e.g. `OLLAMA_DOCKER_TAG=latest` in `.env`, then
  `docker compose up -d` to apply.
- Workspace: ./workspace (persisted forever)
- Fully offline after model pull (unless you opt into [Cloud](#cloud))
- Export to GitHub anytime
- `docker-compose.yml`, `.env`, `workspace/requirements.txt`,
  `workspace/setup_venv.py`, and `continue-config/config.json` are generated
  by `setup.sh` and gitignored — edit `setup.sh` if you want the generated
  defaults to change, or edit the generated files directly for a local-only
  tweak (re-running `setup.sh` won't overwrite files that already exist).
  The last three live inside the directories docker-compose mounts into
  code-server (`./workspace` → `/home/coder/workspace`, `./continue-config`
  → `/home/coder/.continue`) — that placement is required, not cosmetic,
  or code-server/Continue never see them.

## On-Device (Android / Termux)

For running fully offline directly on a phone (no server, no Docker) via
Termux + native llama.cpp.
**Works on any Termux-capable Android phone** — RAM is auto-detected (via
`/proc/meminfo`) and bucketed into a tier, no need to know a specific
device's name:

```bash
git clone https://GitHub.com/SecTrollz/OfflineTweaker.git
cd OfflineTweaker/android
chmod +x termux-setup.sh
./termux-setup.sh
termux-wake-lock
~/run-model.sh
```

(Setting up the Docker desktop stack instead? See [Desktop (Docker)](#desktop-docker) above for `./setup.sh`.)

Then either:
- open `http://127.0.0.1:8080` in Chrome for a built-in chat UI, or
- in a second Termux session, run `~/aider-local.sh` inside a project
  directory for a manual agentic coding CLI, or `./agent-loop.sh` for the
  [autonomous build loop](#autonomous-build-loop) — both use the same local
  model, no cloud API key needed.

Model picked per RAM tier:

| Tier  | Typical device RAM | Model                          | Quant   | Size    |
|-------|---------------------|---------------------------------|---------|---------|
| 3gb   | ~3GB                | DeepSeek-R1-Distill-Qwen-1.5B   | Q4_K_M  | ~1.1GB  |
| 4gb   | ~4GB (e.g. Moto G 5G) | DeepSeek-R1-Distill-Qwen-1.5B | Q4_K_M  | ~1.1GB  |
| 6gb   | ~6GB                | DeepSeek-R1-Distill-Qwen-1.5B   | Q4_K_M  | ~1.1GB  |
| 8gb   | ~8GB (e.g. Pixel 9a) | DeepSeek-R1-Distill-Qwen-7B    | Q4_K_M  | ~4.4GB  |
| 12gb  | ~12GB               | DeepSeek-R1-Distill-Llama-8B    | Q4_K_M  | ~4.9GB  |
| 16gb  | 16GB+                | DeepSeek-R1-Distill-Qwen-14B   | Q4_K_M  | ~8.4GB  |

Same model at the 3/4/6GB tiers on purpose — DeepSeek only ships a 1.5B or a
7B+ distill, nothing in between, so the extra headroom on a 6GB phone goes
into a bigger context window instead. Force a specific tier with
`./termux-setup.sh --ram 8gb` if auto-detection picks wrong, or use the
legacy aliases `./setup.sh pixel9a` / `motog5g`.

Notes:
- Run `termux-setup-storage` (the setup script does this for you) so the
  model file survives Termux updates.
- `termux-wake-lock` prevents Android from suspending inference mid-response.
- All tiers use DeepSeek-R1 reasoning distills, so expect `<think>` traces
  in output — trim them client-side if you just want the final answer.
- The chosen tier/model is saved to `~/.offlinetweaker/profile.env`, which
  `android/agent-loop.sh` reads automatically — re-run `termux-setup.sh`
  with a different `--ram` to switch tiers later.
- After a model file passes checksum verification it's locked read-only
  (`chmod 444`, plus a best-effort `chattr +i` where the device allows it)
  so nothing can silently modify it afterward. To force a re-download
  (switching tiers, suspected corruption, etc.), remove it explicitly
  first: `chattr -i ~/models/*.gguf 2>/dev/null; rm -f ~/models/*.gguf*`
  (the `chattr -i` is only load-bearing if you're on a rooted device where
  it actually took effect — harmless no-op otherwise) — then re-run
  `termux-setup.sh`.

## Autonomous Build Loop

This piece makes it a *builder* rather than a chat window, the
same idea behind Replit Agent / Emergent: hand it a task, it writes code,
**runs your tests, reads the failures, and fixes it itself** — repeating
until the tests pass or it runs out of attempts. Fully offline, on top of
whichever local model you're already running.

```bash
# Desktop, against the Ollama server from setup.sh:
./agent/build-loop.sh --dir ./workspace/my-app \
  --task "Add a /health endpoint that returns 200 OK" \
  --model qwen2.5-coder:14b --api-base http://localhost:11434/v1 \
  --test-cmd "pytest -q"

# Android, against the on-device model (run-model.sh must already be running).
# No profile flag needed -- it reads whatever termux-setup.sh set up:
cd android
./agent-loop.sh --dir ~/projects/my-app \
  --task "Fix the failing tests" --test-cmd "python -m pytest -q"
```

How it works:
1. Every run gets a short built-in system preamble telling the model to
   stay terse — make the minimal change, don't restate unchanged code, keep
   reasoning brief. Override it with the `OFFLINETWEAKER_SYSTEM_PROMPT` env
   var if you want different behavior.
2. Aider gets the task (preamble + your `--task`) and edits the project in
   `--dir`.
3. Your `--test-cmd` runs against the result.
4. On failure, the last `--max-feedback-chars` of test output (default
   4000) are fed back to the model as the next instruction ("fix the code
   so this passes").
5. Repeats up to `--max-iters` (default 5).
6. Every iteration's transcript and test output is logged under
   `<project-dir>/.offlinetweaker/agent-logs/<timestamp>/` so you can see
   exactly what it tried, even on failure.

Omit `--test-cmd` for a single-pass edit with no verification loop (useful
for tasks with no obvious pass/fail check, like "add a README").

**Encrypting the logs.** Every iteration's task/response transcript and
test output lands in `.offlinetweaker/agent-logs/` as plaintext by
default. To encrypt it at rest, using
[age](https://age-encryption.org) (one-time setup, then it's automatic):

```bash
age-keygen -o ~/.offlinetweaker/logs-key.txt   # prints an age1... public key
./agent/build-loop.sh --dir ./myproj --task "..." --model ... --api-base ... \
  --encrypt-logs age1yourpublickeyhere...
# or pass the key FILE instead of the raw key text -- either works:
--encrypt-logs ~/.offlinetweaker/logs-key.txt
```

Every log this run produces (including Aider's own chat-history file) is
encrypted to that key and the plaintext is deleted, no prompt needed per
file. Decrypt later with:

```bash
age -d -i ~/.offlinetweaker/logs-key.txt iteration-1.log.age
```

`~/.offlinetweaker/logs-key.txt` is the only thing that can decrypt these
— guard it like a password (`age-keygen` already sets it `chmod 600`).
This is asymmetric (recipient-key) encryption on purpose, not a
passphrase: a passphrase would mean re-typing it at every file write,
which doesn't work for an unattended loop — age's own passphrase mode
refuses to run non-interactively for exactly that reason.

**Context budget matters on small local models.** A verbose response plus
Aider's repo map plus a large failure dump can eat a small context window
before the model even sees the code. Two flags tune that:
- `--max-feedback-chars N` — how much test-failure output gets fed back on
  retry.
- `--map-tokens N` — forwarded to Aider's own repo-map budget.

`android/agent-loop.sh` sets both automatically from the saved tier profile
so the context window isn't blown by overhead before the actual fix gets
written:

| Tier  | Context | `--map-tokens` | `--max-feedback-chars` |
|-------|---------|----------------|--------------------------|
| 3gb   | 1536    | 0 (disabled)   | 900                      |
| 4gb   | 2048    | 0 (disabled)   | 1200                     |
| 6gb   | 3072    | 256            | 2000                     |
| 8gb   | 4096    | 512            | 3000                     |
| 12gb  | 6144    | 768            | 3500                     |
| 16gb  | 8192    | 1024           | 4000                     |

Leave both unset on desktop (as in the example above) to use Aider's normal
defaults — a full-size context window doesn't need the trim.

## Cloud

Local hardware not enough for a task? Point the same build loop at a bigger
model somewhere else — either a server you rent, or a third-party hosted
API. Both go through `cloud/agent-loop.sh`:

```bash
# Your own rented VM (VPS / cloud GPU box) running setup.sh's stack.
# Opens a private SSH tunnel by default the VM's ports are bound to
# 127.0.0.1 only (see setup.sh), so this is the only way in:
./cloud/agent-loop.sh --host user@1.2.3.4 --model qwen2.5-coder:14b \
  --dir ./myproj --task "Add input validation" --test-cmd "pytest -q"

# Same, but VM is already on a private network (e.g. Tailscale) --
# skip the tunnel and connect directly:
./cloud/agent-loop.sh --host 100.x.y.z --no-tunnel \
  --model qwen2.5-coder:14b --dir ./myproj --task "..."

# Third-party hosted API (OpenRouter/Together/Groq/Fireworks/custom).
# This leaves the machine -- not offline -- and the script warns every time.
# Export the key rather than passing --api-key -- a key on the command line
# is visible to other users via `ps` and gets saved in shell history:
export OPENAI_API_KEY="$OPENROUTER_API_KEY"
./cloud/agent-loop.sh --provider openrouter \
  --model deepseek/deepseek-r1 --dir ./myproj --task "..."
```

Setup for the "your own VM" path is the same `setup.sh` used on desktop —
run it on the rented box, then connect from your phone or laptop with the
command above instead of opening the ports publicly.

Any `agent/build-loop.sh` flag (`--test-cmd`, `--max-iters`, `--map-tokens`,
`--max-feedback-chars`, ...) passes straight through.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

