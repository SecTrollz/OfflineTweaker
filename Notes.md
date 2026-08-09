## Roadmap / Ideas

- **AICore / Private Compute Core as an additional on-device backend.**
  On Pixel 8+/9-class hardware (and Galaxy S24+, etc.), Android ships
  Gemini Nano behind the system `AICore` service, sandboxed via Private
  Compute Services. The current Android path (`android/termux-setup.sh`)
  runs its own llama.cpp + GGUF model instead, which works on any device
  but re-downloads a multi-GB model. Worth revisiting as an alternative
  backend for supported devices:
  - The only legitimate integration surfaces are Google's public,
    sanctioned ones — the ML Kit GenAI APIs (summarize / rewrite /
    proofread / image-describe) and the AI Edge SDK's Gemini Nano
    experimental-access program. `AICoreService` itself is a private
    system API; it isn't something a third-party app can bind to, and
    reverse-engineering it isn't a legitimate path to a real
    integration (also likely a ToS problem).
  - This means a real Kotlin/Java Android app, not a Termux shell
    script — a different shape of client than everything else in
    `android/` today.
  - Still needs scoping: which of those APIs (if any) covers "agentic
    coding assistant" use rather than the fixed task types ML Kit
    exposes, device/OS version coverage, and how big a lift a standalone
    app is versus the value over the existing llama.cpp path.
  - Not started — flagging here so it isn't lost, not committing to an
    approach yet.
