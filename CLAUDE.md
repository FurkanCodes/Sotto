# Sotto

Offline voice dictation for macOS. Hold a key, speak, let go, and the text appears where you're typing. Nothing leaves the Mac. Sotto is a working name.

The plan and its current phase are in `PLAN.md`. Read it before starting work, and update it when a phase's status changes.

## Hard rules

- **Fully offline.**
  - The only network use allowed is the one-time model download. In Phase 1 it happens on first launch; from Phase 3 on, the user starts it from the setup screen. Models are pinned to a fixed version and verified with SHA-256.
  - No telemetry, analytics or crash-reporting SDKs, no update checks, no cloud APIs, no cloud AI.
  - Never add a dependency that phones home.
- **No code before the plan says so.** Work only on the current phase in `PLAN.md`. If something needs a design decision that isn't recorded, ask first.
- **Wispr Flow is studied from the outside only.** Never decompile it, unpack it or copy its code, assets or branding.
- **Handy (MIT) may be ported.** Keep the MIT notice (see `THIRD_PARTY_NOTICES.md`) and cite the Handy file each port came from in a short comment.
- **Measure, don't claim.** Any statement about speed, memory or battery needs a measurement command and its output. Targets are in `PLAN.md`.

## Platform and stack

- macOS 26+, Apple Silicon first. Intel follows Handy: transcribe-cpp on the CPU, in a later phase.
- Swift 6.2 with strict concurrency. AppKit for the app shell, panels and event taps; SwiftUI for views.
- Swift Package Manager; no Xcode project. `scripts/build-app.sh` builds, bundles and signs `Sotto.app`.
- Speech: FluidAudio (Apache-2.0) with Parakeet TDT 0.6B v3 on CoreML, preferring the Neural Engine. Silero for voice detection, through FluidAudio's CoreML build.
- Other models (Whisper, Nemotron, Canary, Parakeet Unified): transcribe-cpp, in an XPC helper (later phase).
- Windows and Linux come later as a separate Rust + GPUI codebase. The two share test cases, not code.

## Layout

```
Sources/SottoCore/   pure logic, no AppKit: state machine, text cleanup, settings model
Sources/Sotto/       the app: hotkey, audio, engine, insert, pill, menu bar, settings UI
Tests/SottoCoreTests/
Tests/Fixtures/      shared test cases as JSON (the Windows app must pass these too)
scripts/             build, bundle, sign, measure
docs/                decisions and measurements
```

## Code rules

- **Keep SottoCore free of AppKit, SwiftUI and FluidAudio,** so it stays testable and can serve as the reference for Windows.
- **The dictation state machine is pure:** (state, event) in, (state, effects) out, with no `await` inside a transition. Every session carries a number, and late results from an old session are dropped.
- **Nothing runs while idle:** no polling loops and no repeating timers. The event tap wakes only on key events. The mic is open only while recording. The pill is ordered out, with no frame callbacks, when hidden.
- **Nothing slow between key release and paste:** no disk writes, logging or settings reads on that path. Settings live in memory and are read from disk only at launch.
- **Text cleanup never loses text:** every step is a pure function, and a step that empties non-empty text is skipped. No force unwraps and no unchecked string indexing.
- **Paste:**
  - publish the text as a lazy pasteboard promise;
  - send Cmd+V using the layout-aware V keycode;
  - restore the user's clipboard only after the target app has read the text, and only if `changeCount` hasn't changed;
  - mark the transcript with the concealed and transient pasteboard types.
- **No failure is silent.** Each one shows in the pill or the menu bar icon, and the last transcript is always recoverable from the menu.
- **Respect the accessibility settings:** Reduce Transparency, Reduce Motion, VoiceOver labels, and dark mode everywhere.
- **Match the surrounding code's style.** Comment only what the code can't say.

## Commands

Prefix shell commands with `rtk` (see the user's global `RTK.md`).

- Build: `rtk swift build`
- Tests: `rtk swift test`
- App bundle: `scripts/build-app.sh`. It builds release and signs with `$SOTTO_SIGN_IDENTITY`, else an Apple Development certificate, else the local self-signed "Sotto Local Signing" certificate in the login keychain. A stable signature keeps macOS permissions across rebuilds. Never fall back to ad-hoc signing on purpose.

## Git

- **Implement features on a `feature/<slug>` branch,** never on `main`.
- **Commit or push only when the user asks.**

## References

- Research and measurements: `~/Projects/dictation-research/` (`notes/`, `bench/`, `concepts_brief.md`)
- Handy source, for porting: `~/Projects/dictation-research/Handy`
- FluidAudio source (v0.17.7): `~/Projects/dictation-research/FluidAudio`
- Architecture: https://claude.ai/artifact/VC6YE6YeTST8NNjja8uGFK
- UI design (light and dark): https://claude.ai/artifact/3FntRG7z3EowUNCSvMavPn
