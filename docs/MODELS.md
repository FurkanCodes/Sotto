# Models and where they run

Sotto runs speech models on one of two engines:

- **Neural Engine**, Apple's low-power chip for AI, through [FluidAudio](https://github.com/FluidInference/FluidAudio)'s CoreML builds. It uses less CPU and leaves the GPU free, so it's the better choice for battery.
- **GPU**, through [transcribe.cpp](https://github.com/handy-computer/transcribe.cpp), in a separate helper process. Every catalog model has a GPU build.

The built-in model, Parakeet TDT 0.6B v3, always runs on the Neural Engine.

## Run models on

Settings → Models → **Run models on**:

| Choice | What it does |
|---|---|
| **Automatic** (default) | The Neural Engine build on Apple silicon, if the model has one that works as well as its GPU build. Otherwise the GPU build. |
| **Neural Engine, to save battery** | The Neural Engine build whenever there is one, including builds Automatic skips. |
| **GPU, for the quickest live text** | Always the GPU build. |

Intel Macs have no Neural Engine, so there every model runs on the GPU and the Neural Engine choice is hidden.

The two builds of a model are separate downloads. Switching engines downloads the other build; deleting a model removes both.

## Which models use the Neural Engine

| Model | Automatic uses | Why |
|---|---|---|
| Parakeet TDT 0.6B v3 | Neural Engine | Built in. |
| Parakeet Unified | Neural Engine | Same text as the GPU build; words appear sooner and it uses about half the CPU. Streams with a fixed 320 ms setting. |
| Nemotron 3.5 Streaming | Neural Engine | Same accuracy as the GPU build. Live text starts about 0.4 s later (1.1 s against 0.7 s). |
| Nemotron Speech Streaming (English) | GPU | The Neural Engine build dropped opening words on the test clips ("Here is my plan" → "Is my plan"). Still available with **Neural Engine**. |
| Parakeet TDT 0.6B v2 | Neural Engine | Same text as the GPU build (one comma apart) and faster: 124 ms against 371–443 ms for a 46 s clip. |
| Parakeet Ultra | Neural Engine | Same words as the GPU build and 3–4× faster: 161–173 ms against 527–759 ms for a 46 s clip. |
| Parakeet TDT-CTC 110M | Neural Engine | Same words as the GPU build and 3× faster: 57–65 ms against 186–219 ms for a 46 s clip. |
| Cohere Transcribe | GPU | FluidAudio's build took 22 s for a 4.6 s clip on the Neural Engine (GPU build: 0.13 s), so Sotto doesn't offer it. |
| Canary 1B v2 | GPU | FluidAudio's build only transcribes English; the GPU build handles 25 languages. |
| Every other model (Whisper, Moonshine, Granite, Voxtral, Qwen and more) | GPU | No Neural Engine build exists. |

Measurements behind this table are in [measurements.md](measurements.md). Measured with `powermetrics`, Parakeet Unified drew 0.46 W while streaming on the Neural Engine against 2.69 W on the GPU: about 6× less power for the same text.

## Downloads are pinned and checked

Every model downloads from Hugging Face at a fixed commit and is checked with SHA-256 before Sotto uses it:

- GPU builds: `Resources/model-catalog.json`.
- Neural Engine builds: `Resources/neural-engine-models.json`, written by `scripts/pin-neural-models.py`, which lists each file's size and SHA-256. Sotto downloads these files itself; FluidAudio only loads them.

To move a Neural Engine build to a newer upstream version, run `scripts/pin-neural-models.py --refresh`, measure it again, and review the diff.

**Not yet pinned:** the built-in Parakeet v3 and the Silero voice detector still download through FluidAudio's own downloader, which fetches the latest upstream version and checks only file sizes. Moving them onto the same pinned, checked path is still to do.
