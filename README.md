# OfflineTweaker
## Offline AI Coding Powerhouse (exceeds Replit Pro/Base44)

Models: Qwen2.5-Coder series (desktop) / DeepSeek-R1 distills (on-device)
Agent modes:
- **Autonomous build loop** (`agent/build-loop.sh`): give it a task, it
  writes code, runs your tests, reads the failures, and fixes it itself —
  see [Autonomous Build Loop](#autonomous-build-loop) below.
- Continue.dev in VS Code: /edit, /run, codebase chat, autonomous refactoring
- Aider: `aider --model ollama/qwen2.5-coder:14b` in terminal
- Jupyter notebooks for scripts/REPL

Tips:
- Change PASSWORD in docker-compose.yml
- For GPU: add NVIDIA section in compose
- Workspace: ./workspace (persisted forever)
- Fully offline after model pull
- Export to GitHub anytime

## On-Device (Android / Termux)

For running fully offline directly on a phone (no server, no Docker) via
[Termux](https://f-droid.org/packages/com.termux/) + native llama.cpp:

```bash
cd android
./termux-setup.sh pixel9a    # or: motog5g
termux-wake-lock
~/run-model.sh
```

Then either:
- open `http://127.0.0.1:8080` in Chrome for a built-in chat UI, or
- in a second Termux session, run `~/aider-local.sh` inside a project
  directory for an agentic coding CLI (reads/edits files, runs commands)
  backed by the same local model — no cloud API key needed.

Model picked per device, sized to fit in RAM:

| Device       | RAM  | Model                              | Quant   | Size    |
|--------------|------|-------------------------------------|---------|---------|
| Pixel 9a     | 8GB  | DeepSeek-R1-Distill-Qwen-7B         | Q4_K_M  | ~4.4GB  |
| Moto G 5G    | 4GB  | DeepSeek-R1-Distill-Qwen-1.5B       | Q4_K_M  | ~1.1GB  |

Notes:
- Install Termux from F-Droid — the Play Store build is outdated and can't
  build native code.
- Run `termux-setup-storage` (the setup script does this for you) so the
  model file survives Termux updates.
- `termux-wake-lock` prevents Android from suspending inference mid-response.
- Both models are DeepSeek-R1 reasoning distills, so expect `<think>` traces
  in output — trim them client-side if you just want the final answer.

## Autonomous Build Loop

This is the piece that makes it a *builder* rather than a chat window, the
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

# Android, against the on-device model (run-model.sh must already be running):
cd android
./agent-loop.sh pixel9a --dir ~/projects/my-app \
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

**Context budget matters on small local models.** A verbose response plus
Aider's repo map plus a large failure dump can eat a small context window
before the model even sees the code. Two flags tune that:
- `--max-feedback-chars N` — how much test-failure output gets fed back on
  retry.
- `--map-tokens N` — forwarded to Aider's own repo-map budget.

`android/agent-loop.sh` sets both automatically per device so the
4096-token (pixel9a) and 2048-token (motog5g) context windows aren't blown
by overhead before the actual fix gets written:

| Profile  | Context | `--map-tokens` | `--max-feedback-chars` |
|----------|---------|----------------|--------------------------|
| pixel9a  | 4096    | 512            | 3000                     |
| motog5g  | 2048    | 0 (disabled)   | 1200                     |

Leave both unset on desktop (as in the example above) to use Aider's normal
defaults — a full-size context window doesn't need the trim.
