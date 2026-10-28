# Sotto

Offline voice dictation for macOS. Hold a key, speak, let go, and the text appears wherever you're typing. Nothing leaves your Mac.

*Sotto is a working name.*

## Why Sotto

- **Fully offline.** Speech recognition runs on your Mac. The only network use is downloading a model once, pinned to a fixed version. No accounts, no telemetry, no cloud.
- **Fast.** On an M5, text lands about 0.1 s after you let go of the key, including the paste. Streaming models transcribe while you talk, so long dictations stay that fast too (measured up to 46 s without a pause). Measurements, with the commands that produced them, are in [docs/measurements.md](docs/measurements.md).
- **Light.** It uses no CPU while idle, and the mic is on only while you hold the key.

## Features

- Hold right Option (or right Command, Fn, or a mouse button) to dictate. Tap to keep listening hands-free.
- Live text in a small on-screen pill while you talk.
- Built-in model: Parakeet TDT 0.6B v3 on the Neural Engine, 25 languages.
- 73 optional models, downloaded in Settings, including Whisper Large v3 Turbo (about 100 languages, Turkish included), Nemotron and Parakeet Unified (both stream as you talk).
- Cleanup: removes filler words, fixes spoken self-corrections ("at 2, actually 3" → "at 3"), and applies a writing style per app.
- A personal dictionary that learns the words you correct by hand, plus replacements and snippets (`{date}`, `{time}`, `{clipboard}`).
- Say "send it", or set per-app auto-send, to press Return after pasting.
- History (7 days by default, text only), usage stats, transcribing audio and video files, apps to skip, lowering other audio while you talk.

See [docs/FEATURES.md](docs/FEATURES.md) for what's done and what's planned.

## Install

Requires a Mac with Apple silicon and macOS 26 or later.

Download the latest zip from [Releases](../../releases). Sotto isn't notarized by Apple, so macOS blocks it the first time; [docs/INSTALL.md](docs/INSTALL.md) shows how to allow it, and which permissions it needs and why.

## Build from source

You need Xcode 26 (Swift 6.2), CMake and Ninja (`brew install cmake ninja`).

```
scripts/build-app.sh       # builds, bundles and signs build/Sotto.app
open build/Sotto.app
swift test                 # the core logic tests
```

The first build fetches and compiles [transcribe.cpp](https://github.com/handy-computer/transcribe.cpp) at a pinned commit. Without a signing certificate the app is signed ad-hoc, and macOS asks for permissions again after every build. A self-signed code-signing certificate named "Sotto Local Signing" in your login keychain avoids that.

`scripts/release.sh` packs a signed build into a zip with its SHA-256.

## How it works

```
hold key → mic → voice detection → speech model → cleanup → paste
```

While you talk, audio is cut at pauses and transcribed piece by piece, or streamed to a model built for streaming, so little is left to do when you let go. Parakeet v3 runs on the Neural Engine inside the app; other models run in a separate helper process.

- `Sources/SottoCore`: platform-independent logic (state machine, text cleanup, settings), with no AppKit, so it can be tested on its own.
- `Sources/Sotto`: the app: hotkey, audio, engines, paste, pill, menu bar, Settings.
- `Sources/SottoEngine`: the XPC helper that runs transcribe.cpp models in their own process, so a model crash never takes down the app.

## Credits

Sotto stands on open-source work:

- [Handy](https://github.com/cjpais/Handy) (MIT): the reference app; several parts are ported from it, as well as its model catalog.
- [FluidAudio](https://github.com/FluidInference/FluidAudio) (Apache 2.0): Parakeet and Silero on CoreML.
- [transcribe.cpp](https://github.com/handy-computer/transcribe.cpp) and [ggml](https://github.com/ggml-org/ggml) (MIT): every other model.
- Models from NVIDIA, OpenAI, the Silero team and others, each under its own license.

Full notices are in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
