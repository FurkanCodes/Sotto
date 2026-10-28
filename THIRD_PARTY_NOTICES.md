# Third-party notices

## Handy

Parts of Sotto are ported from Handy (https://github.com/cjpais/Handy). Each ported piece cites its Handy source file in a comment.

```
MIT License

Copyright (c) 2025 CJ Pais

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## transcribe.cpp and ggml

The SottoEngine helper is built from transcribe.cpp (https://github.com/handy-computer/transcribe.cpp) and the ggml library bundled with it. Both are licensed under the MIT License, with the same text as Handy's above and these copyright lines:

```
Copyright (c) 2026 The transcribe.cpp authors
Copyright (c) 2023-2026 The ggml authors
```

The list of downloadable models (`model-catalog.json`) comes from Handy's catalog.

## FluidAudio

Sotto uses FluidAudio (https://github.com/FluidInference/FluidAudio), licensed under the Apache License 2.0: https://www.apache.org/licenses/LICENSE-2.0

## Models

- Parakeet TDT 0.6B v3 by NVIDIA, licensed CC-BY-4.0 (https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3). Sotto uses the CoreML conversion published by FluidInference.
- Silero VAD v6.2 by the Silero Team, licensed MIT (https://github.com/snakers4/silero-vad). Sotto uses the CoreML conversion published by FluidInference.
- Models downloaded in Settings → Models keep their own licenses, listed for each model in `model-catalog.json` and linked from its Hugging Face page.
