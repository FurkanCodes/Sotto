<div align="center">

<img src="docs/assets/logo.svg" width="120" alt="Sotto logo">

# Sotto

**Offline voice dictation for macOS.**<br>
Hold a key, speak, let go. Your words appear wherever you type.

[![Release](https://img.shields.io/github/v/release/FurkanCodes/Sotto?include_prereleases&label=release&color=8E7CFF)](https://github.com/FurkanCodes/Sotto/releases)
![macOS 26+](https://img.shields.io/badge/macOS-26%2B-111?logo=apple)
![Apple silicon](https://img.shields.io/badge/Apple%20silicon-M1%2B-111)
[![License: MIT](https://img.shields.io/badge/license-MIT-111)](LICENSE)

[**Download**](https://github.com/FurkanCodes/Sotto/releases) · [Install guide](docs/INSTALL.md) · [Roadmap](docs/FEATURES.md)

</div>

---

## Why Sotto

| | |
|---|---|
| 🔒 **Private** | Runs entirely on your Mac. No account, no cloud, no telemetry. |
| ⚡ **Fast** | Text lands about 0.1 s after you let go. [Measured](docs/measurements.md). |
| 🔋 **Battery-friendly** | Models run on the Neural Engine, Apple's low-power chip for AI, whenever they can: about 6× less power than the GPU. [See below](#battery-neural-engine-vs-gpu). |
| 🪶 **Light** | Zero CPU while idle. The mic is on only while you hold the key. |

## Battery: Neural Engine vs GPU

The same model (Parakeet Unified) transcribing the same 46-second dictation, measured with Apple's `powermetrics` on an M5:

| Runs on | Power while dictating | Text | Ready after you let go |
|---|---|---|---|
| **Neural Engine** | **0.46 W** | identical | 14–37 ms |
| GPU | 2.69 W | identical | 46–53 ms |

Same words, about **6× less power**. By default Sotto uses the Neural Engine for every model with a Neural Engine version that works as well as the GPU one; you can switch to the GPU in Settings. Full numbers: [measurements](docs/measurements.md#2026-10-28-power-neural-engine-against-gpu) · [which models run where](docs/MODELS.md).

## Features

- **Hold to talk:** right Option, right Command, Fn, or a mouse button. Tap for hands-free.
- **Live text** in a small on-screen pill while you speak.
- **73 models:** Parakeet v3 is built in (25 languages). It and five more, including Parakeet Unified and Nemotron 3.5, run on the Neural Engine; the rest, like Whisper Turbo, run on the GPU. [Which runs where](docs/MODELS.md).
- **Clean output:** filler words removed, "at 2, actually 3" fixed to "at 3", style matched to each app.
- **Your words:** a dictionary that learns from your corrections, replacements and snippets.
- **Hands off:** say "send it" to press Return. Per-app auto-send.
- **And more:** history, file transcription, apps to skip, quieter music while you talk.

## Install

1. Download `Sotto-x.y.z.zip` from [Releases](https://github.com/FurkanCodes/Sotto/releases) and move `Sotto.app` to Applications.
2. Sotto isn't notarized, so allow it once: System Settings → Privacy & Security → **Open Anyway**.
3. Grant Microphone, Accessibility and Input Monitoring when asked.

Step-by-step, with a Terminal alternative: [docs/INSTALL.md](docs/INSTALL.md).

## Build from source

Requires Xcode 26 (Swift 6.2) and `brew install cmake ninja`.

```sh
scripts/build-app.sh   # build, bundle and sign build/Sotto.app
swift test             # core tests
```

## Credits

Speech runs on [FluidAudio](https://github.com/FluidInference/FluidAudio) and [transcribe.cpp](https://github.com/handy-computer/transcribe.cpp). Models keep their own licenses. See [notices](THIRD_PARTY_NOTICES.md).

## License

[MIT](LICENSE)
