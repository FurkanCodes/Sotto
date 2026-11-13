# Third-party notices

## transcribe.cpp and ggml

The SottoEngine helper uses [transcribe.cpp](https://github.com/handy-computer/transcribe.cpp) and the ggml library bundled with it. Both are licensed under the MIT License:

```
MIT License

Copyright (c) 2026 The transcribe.cpp authors
Copyright (c) 2023-2026 The ggml authors

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

## FluidAudio

Sotto uses [FluidAudio](https://github.com/FluidInference/FluidAudio), licensed under the [Apache License 2.0](https://www.apache.org/licenses/LICENSE-2.0).

## Models and conversions

- Parakeet TDT 0.6B v3 by NVIDIA, licensed CC-BY-4.0 ([model page](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3)). Sotto uses the CoreML conversion published by FluidInference.
- Silero VAD v6.2 by the Silero Team, licensed MIT ([source](https://github.com/snakers4/silero-vad)). Sotto uses the CoreML conversion published by FluidInference.
- Parakeet TDT 0.6B Turkish, fine-tuned by Veli Furkan Turkoglu from NVIDIA's Parakeet TDT 0.6B v3, licensed CC-BY-4.0 (https://huggingface.co/velifurkan/parakeet-tdt-0.6b-tr-gguf). Trained on the ISSAI Turkish Speech Corpus (CC-BY-4.0), Mozilla Common Voice (CC0), Google FLEURS (CC-BY-4.0) and ESPnet YODAS (CC-BY-3.0).
- GGUF conversions downloaded from the `handy-computer` repositories are published by [handy-computer](https://huggingface.co/handy-computer). CoreML conversions are published by [FluidInference](https://huggingface.co/FluidInference).
- Models downloaded in Settings → Models keep their own licenses, listed for each model in `Resources/model-catalog.json` and linked from its Hugging Face page. The pinned CoreML files and their source repositories are listed in `Resources/neural-engine-models.json`.
