# Sotto plan

Status key: ☐ not started · ◐ in progress · ☑ done. Update the status when it changes.

## Targets

These are checked by measurement, not by claims. On Apple Silicon, macOS 26.

| What | Target | How it's measured |
|---|---|---|
| Release-to-text, warm model, 5 s dictation | ≤ 100 ms p50, ≤ 150 ms p95, and faster than live Handy on the same machine | key-up timestamp → text visible in a test app, 30 runs |
| Release-to-text, 45 s dictation | within 50 ms of the 5 s result | same harness |
| First dictation after the model is unloaded | measured and reported; the pill shows "Loading model" | same harness, model unloaded |
| Idle memory, model unloaded | < 30 MB | `footprint` (phys_footprint), summed across all Sotto processes |
| Idle CPU | ~0%, ~0 wake-ups/s | `top`, 10 minutes, idle and while typing in another app |
| App bundle, excluding the model | < 15 MB | `du` of the signed `Sotto.app` |
| Network | only the model download | `lsof -i` and `nettop`, idle and while dictating |
| Pill appears | < 16 ms from key-down to first frame | signposts |

## Phase 0: Setup ☑ (signed with the local "Sotto Local Signing" certificate)

- Swift package with `SottoCore`, `Sotto` and test targets; `scripts/build-app.sh` builds a bundled, signed `Sotto.app`.
- `Info.plist`:
  - bundle ID `com.furkan.sotto` (working value; permanent before any public build);
  - `LSUIElement`;
  - microphone usage string.
- Entitlements: hardened runtime, audio input, no sandbox.
- **A stable signing identity,** so macOS keeps the Accessibility and Input Monitoring grants across rebuilds. The free Apple Development certificate from Xcode works; the user has to set it up.
- `THIRD_PARTY_NOTICES.md` for Handy (MIT), FluidAudio (Apache-2.0) and Parakeet (CC-BY-4.0).

**Exit:** `scripts/build-app.sh` produces an app that launches as a menu bar icon, and `swift test` passes.

## Phase 1: The whole pipeline ◐ (current goal: code written, headless engine check passed, waiting on a real-use test)

Still open in Phase 1:
- **Verify pinned models.** FluidAudio downloads the models itself; checking them against a SHA-256 list is not done yet.
- ☑ Voice detection now runs during recording (Phase 2 work, done early).

The goal is dictation working end to end in any app, with a basic pill. Polish comes later.

1. **Permissions:** check and request Microphone, Accessibility and Input Monitoring. Show what's missing in the menu.
2. **Hotkey:**
   - a listen-only `CGEventTap` on the main run loop, with right Option as a modifier-only key;
   - hold to talk; a tap under 300 ms latches hands-free mode;
   - another key pressed while holding cancels (the user is typing a character);
   - Esc cancels;
   - re-enable the tap if macOS disables it.
3. **State machine** in SottoCore, with tests: sessions, latching, cancel, stale results.
4. **Capture:** AVAudioEngine converted to 16 kHz mono Float32. The mic opens on key-down and closes on release. "Listening" starts only on the first real audio buffer.
5. **Voice detection:** Silero through FluidAudio, using Handy's timings (450 ms before speech, 60 ms to start, 450 ms after speech ends). If Silero fails, the audio counts as speech.
6. **Engine:**
   - a `SpeechEngine` protocol (load, transcribe, unload);
   - `ParakeetEngine` through FluidAudio, Parakeet TDT 0.6B v3, on the Neural Engine;
   - load on key-down, warm up after load, unload after 5 minutes idle with a one-shot timer.
7. **Text cleanup** in SottoCore: filler words, stutters, whitespace, ported from Handy with its test cases as JSON fixtures.
8. **Insert:** a lazy pasteboard promise, a layout-aware Cmd+V, and clipboard restore after the target app reads the text. Concealed and transient pasteboard types.
9. **Basic pill:** an `NSPanel` with SwiftUI and Liquid Glass. Listening shows bars driven by the mic level, transcribing shows dots, and a failure shows an error. Ordered out when idle.
10. **Basic menu bar:**
    - status;
    - last transcript and "Copy last transcript";
    - missing permissions;
    - Quit.
11. **Per-step timing signposts** from key-down to paste.

**Exit:**
- You can dictate into Notes, Safari or Chrome, Slack (an Electron app), VS Code and Terminal.
- Your clipboard comes back intact.
- Release-to-text is measured for 5 s and 45 s clips.
- Idle CPU is 0% with the model unloaded.
- `lsof` shows no network use after the model is downloaded.

## Phase 2: Measure and harden ☐

- **Timing harness** (replayed WAV plus posted key events), used to measure live Handy and Sotto on the same machine.
- ☑ **Long dictations:** audio is split at Silero pauses while recording (commit d7aa4bf). Speech with no pauses at all still goes in one piece; overlapping pieces with duplicate removal at the joins would fix that.
- **The Option A or B decision:** load and unload 50 times and check that memory comes back. Record the result in `docs/`.
- **Every failure state is visible and recoverable:**
  - no model;
  - mic denied, silent or missing;
  - nothing recognized;
  - insert failed;
  - engine crash;
  - hotkey unavailable.
- **Secure Input:** detect it on events, not by polling, and warn the user.
- **Paste test list** across target apps and keyboard layouts (US, Turkish Q, Dvorak).
- **Accuracy check** on recordings of your own voice.

## Phase 3: The real UI ☐

Built from the design canvas, in light and dark:
- every pill state;
- the menu bar menu and icon states;
- Settings: General, Shortcut, Models, Dictionary (custom words), Privacy, About;
- the first-run setup.

## Phase 4: More models and Intel ◐ (models done on `feature/all-models`; Intel still to do)

Status:
- ☑ transcribe-cpp in the SottoEngine XPC helper; it exits on unload. No versioned handshake yet: the app and helper ship together in one bundle.
- ☑ The whole catalog (73 speech models), not a subset, at the user's request.
- ☑ Downloads with progress, cancel and SHA-256 checks. Not done: resuming a broken download.
- ☐ Intel.

Plan:

- transcribe-cpp in an XPC helper, with a versioned handshake. It exits on unload.
- Handy's model catalog, offering a subset at first: Parakeet Unified, Whisper Large v3 Turbo, Nemotron 3.5 Streaming, Canary 180M.
- Intel Macs: transcribe-cpp on the CPU, as Handy does.
- Model downloads with progress, resume and SHA-256 checks.

## Phase 5: Release prep ☐

- Check the name (domains, App Store, trademarks) and pick the permanent bundle ID.
- Developer ID signing and notarization (deferred: first releases are unnotarized, see the decision log).
- Manual update process.

## Later

- iOS keyboard extension (Swift).
- Windows and Linux in Rust with GPUI, passing the shared fixtures.
- AI cleanup with Apple Foundation Models, with its own latency budget.

## Decisions log

| Date | Decision |
|---|---|
| 2026-10-28 | Native Swift for macOS and iOS; Rust + GPUI for Windows and Linux later. Based on the measured comparison in `~/Projects/dictation-research/bench/ui-shootout/RESULTS.md`. |
| 2026-10-28 | Default model: Parakeet TDT 0.6B v3 on CoreML (FluidAudio), preferring the Neural Engine. |
| 2026-10-28 | Silero voice detection; right Option hotkey; only the last transcript is kept, in memory; manual updates. |
| 2026-10-28 | Engines: CoreML runs inside the app; transcribe-cpp runs in an XPC helper (Option A). Revisit after the Phase 2 memory test. |
| 2026-10-28 | First releases ship without notarization: signed with the self-signed "Sotto Local Signing" certificate, so permissions survive updates, and opened once by hand (`docs/INSTALL.md`). `scripts/release.sh` packs the zip and its SHA-256. Developer ID and notarization stay in Phase 5 for later. |
| 2026-10-28 | Engines, revised: a catalog model with a FluidAudio CoreML build runs on the Neural Engine (battery), unless that build measured worse; the rest stay on transcribe.cpp (GPU). Settings → Models → Run models on: Automatic (default), Neural Engine, or GPU; Intel Macs always use the GPU. Neural Engine builds are pinned with SHA-256 in `Resources/neural-engine-models.json`. Details in `docs/MODELS.md`. |
