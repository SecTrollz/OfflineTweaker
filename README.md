# OfflineTweaker
## Offline AI Coding Powerhouse (exceeds Replit Pro/Base44)

Models: Qwen2.5-Coder series (best open coder models 2026)
Agent modes:
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

Then open `http://127.0.0.1:8080` in Chrome for a built-in chat UI, or point
any OpenAI-compatible client at that address.

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
