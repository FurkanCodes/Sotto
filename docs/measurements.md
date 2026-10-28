# Measurements

## 2026-10-28: Speech pipeline, headless

Machine: Apple M5, macOS 26.5.2.

Command:
```
Sotto --transcribe-file <clip> --repeat 5
```

It runs Silero voice detection, Parakeet TDT 0.6B v3 (CoreML, FluidAudio 0.17.7) and text cleanup on a file, with no mic, hotkey or UI.

The clips are the `say`-generated ones in `~/Projects/dictation-research/bench/audio`. Peak memory is from `/usr/bin/time -l`.

| Clip | Model load (cached, with warm-up) | Voice detection | Transcription (5 runs) | Best total | Peak memory, Sotto process |
|---|---|---|---|---|---|
| 4.6 s | 269 ms | 4 ms | 42–47 ms | 45 ms | 42.6 MB |
| 15.4 s | 133 ms | 12 ms | 115–119 ms | 127 ms | 61.3 MB |
| 45.8 s | 137 ms | 35 ms | 163–170 ms | 198 ms | 87.3 MB |

**First run ever:** 40.8 s. That covers downloading 469 MB of models and CoreML compiling them for the device. It happens once.

**Comparison:** Handy v0.9.8, measured the same way (batch mode, Parakeet Unified Q8, Metal):
- transcription: 51 / 125 / 370 ms;
- load: 151–355 ms, plus a 66–556 ms slowdown on first use;
- peak memory: about 900 MB.

The Handy numbers are in `~/Projects/dictation-research/notes/handy-speed-baseline.md`.

**Caveats:**
- **Peak memory counts only the Sotto process.** CoreML can keep some model memory in system processes (the Neural Engine services), which this number misses. Measuring memory across the whole system is a Phase 2 task.
- **Synthetic speech is easy,** so these clips say nothing about accuracy on a real voice.
- **These times exclude the mic, the hotkey and pasting.** End-to-end release-to-text comes from the app's own log line, "release→paste … ms", and from the Phase 2 harness.

## 2026-10-28: Live dictation in the app

Signed build, a real mic, right Option push-to-talk, pasting into a text field. The numbers are from the app's "release→paste" log line.

| Build | Audio | Key-up until work starts | Voice detection | Transcription | Paste | Release to paste |
|---|---|---|---|---|---|---|
| Before the fixes | 11.0 s | not measured (~90 ms unexplained) | 22 ms | 125 ms | not measured | 240 ms |
| Mic closed off the critical path | 3.6 s | 10 ms (mic close 0 ms) | 15 ms | 88 ms | 4 ms | **117 ms** |

**First dictation after installing:** 11.3 s. CoreML compiled the model for the Neural Engine, which took 12.8 s. This is now done at launch instead. Later loads, including after the idle unload, take 158–224 ms.

**Idle, model loaded** (`top`, 10 s; `footprint`; `lsof -i`):
- CPU 0.00%, 0 wake-ups/s;
- phys_footprint 33.3 MB;
- no network sockets.

**Live transcription is slower than the headless test** (88 ms against 45 ms for a similar length). The likely cause is the Neural Engine waking from idle, which is unverified. The next step tests a warm-up on key-down.

## 2026-10-28: Idle slowdown and the key-down warm-up

Headless, 4.6 s clip, `--gap` = idle seconds before each run, `--warm-lead` = warm-up seconds before each run.

| Condition | Voice detection | Transcription |
|---|---|---|
| Back-to-back (no idle) | 4 ms | 42–48 ms |
| 15 s idle, no warm-up | 13–17 ms | 123–134 ms |
| 15 s idle, warm-up 2 s before | 9–14 ms | 57–91 ms |
| 10 s idle, warm-up 1 s before | 11–16 ms | 58–68 ms |
| 10 s idle, warm-up 0.5 s before | 8–15 ms | 54–91 ms |
| 10 s idle, warm-up 0.25 s before | 12–14 ms | 88–104 ms |

**Conclusion:** after idle, the pipeline is about 3x slower. The key-down warm-up recovers about half of that. It doesn't reach back-to-back speed, because the hardware is fastest while it's continuously busy.

**Next step (Phase 2):** process audio in chunks while the user is still talking, so the hardware stays busy and only the tail is left at release.

## 2026-10-28: Transcribing while the user talks

Headless `--live`: the file is fed in at real-time speed in 64 ms chunks; the time measured runs from the last chunk ("release") to the final text. The model is warm, 3 runs each. `paused.wav` is synthetic speech with normal 600–700 ms pauses between sentences.

| Clip | All at once (before) | While talking (now) | Pieces done before release | Left at release |
|---|---|---|---|---|
| short, 4.6 s | 71 ms | 52–54 ms | 1 | 0.7 s |
| paused, 35.7 s | 193 ms | 77–96 ms | 5 | 4.6 s |
| medium, 15.4 s, no pauses | 152 ms | 172–175 ms | 0 | 15.4 s |
| long, 45.8 s, no pauses | 220 ms | 225–240 ms | 0 | 45.8 s |

The text matched the all-at-once transcript in every case.

**Pause detection:** Silero scores normal sentence pauses at 0.1–0.4 per 256 ms window, against 1.0 for speech. FluidAudio's end-of-speech event needs 0.75 s of silence, so it missed them. Sotto cuts at windows scoring under 0.5.

**Rejected: forced cuts.** Cutting continuous speech at 12 s even without a pause brought the no-pause clips to 101–129 ms, but split words across pieces ("the settings file. File gets read", "almost. no CPU", "a Crash"). Sotto only cuts at real pauses; speech that never pauses stays in one piece.

**Possible follow-up:** overlapping pieces with duplicate removal at the joins (FluidAudio has TokenDeduplication).

## 2026-10-28: Other models in the SottoEngine helper

`build/Sotto.app/Contents/MacOS/Sotto --transcribe-file <clip> --model <gguf> [--language tr] --repeat 3`, through the bundled XPC helper (transcribe.cpp at 5700f12, Metal).

| Model | Clip | Load | Transcribe |
|---|---|---|---|
| Parakeet Unified en 0.6B, Q8 | short, 4.6 s | 65 ms (4.4 s the very first time: Metal shader compile) | 51–53 ms |
| Parakeet Unified en 0.6B, Q8 | long, 45.8 s | 65 ms | 382–435 ms |
| Whisper Small, Q8, `--language tr` | Turkish, 6.9 s (`say -v Yelda`) | 80–220 ms | 212–277 ms |
| Whisper Small, Q8, automatic language | Turkish, 6.9 s | 79 ms | 218–236 ms (647 ms on the model's first run) |

Whisper Small got the Turkish sentence exactly right, with and without `--language tr`: "Merhaba, yarın saat 3'te toplantımız var. Lütfen sunumu Mehmet'e gönder ve bana haber ver."

**No warm-up for the helper:** after the first load, a fresh helper's first transcription is only 15–50 ms slower than the rest. The one-time Metal compile happens in `prepareModel` at launch or when switching models.

**App size:** 20 MB with the helper (Sotto 12 MB, SottoEngine 8.1 MB). `strip -x` in release builds brings it to 15 MB (`du -sh build/Sotto.app`); the signature verifies and both engines still transcribe.

## 2026-10-28: Streaming (Nemotron, Parakeet Unified)

`Sotto --transcribe-file <clip> --model <gguf> --live --repeat 2 [--pieces]`: the clip is fed in at real-time speed in 64 ms chunks, sent to the helper in batches of at least 256 ms. Times are from the last chunk ("release") to the final text. `--pieces` uses the pause-cut pieces instead, for comparison. Q8_0 models, Metal.

| Model | Clip | Streaming | Pieces | First caption, streaming | First caption, pieces |
|---|---|---|---|---|---|
| Nemotron 3.5, `--language en` | short, 4.6 s | 29–36 ms | 66–126 ms | 1.3 s | 4.2 s |
| Nemotron 3.5 | medium, 15.4 s, no pauses | 69–102 ms¹ | 325–390 ms | 1.1 s | at release |
| Nemotron 3.5 | long, 45.8 s, no pauses | 78–79 ms | 861–1054 ms | 1.3 s | at release |
| Nemotron 3.5 | paused, 35.7 s | 77–81 ms¹ | 145–156 ms | 1.1 s | 8.9 s |
| Parakeet Unified | short, 4.6 s | 98–100 ms | | 2.3 s | |
| Parakeet Unified | long, 45.8 s, no pauses | 170–177 ms | 480–598 ms | 2.3 s | at release |

¹ Measured before batching, with one helper message per 64 ms chunk.

**Text:** streaming and pieces gave the same text on short, medium and long. On paused they differed by two punctuation marks, one better each way.

**Turkish:** Nemotron needs "tr-TR"; Sotto now maps the setting's "tr" to the model's own tag. The Yelda clip came out as "Medaba yarın sağa tüçte toplantımız var rütfen sunumu Mehmete gönder ve bınaha ber ver.", against Whisper Small's exact transcript.

**Only the Parakeet family streams.** Moonshine's streaming decodes the whole recording again on every feed, and Voxtral Realtime hasn't been measured; both still use pieces.

## 2026-10-28: Live text speed and helper threads

`Sotto --transcribe-file long.wav --model <gguf> --live --lookahead <ms>` (45.8 s, no pauses), real time, one run each. "Lookahead" is how much audio the model waits for before it writes words; the helper picks the closest trained setting. Helper CPU is the SottoEngine process's CPU time (`ps -Ao time=,ucomm=`) at the end of the run. "Diffs" counts word-level differences from the slowest setting's final text.

**Threads.** At 480 ms on Parakeet Unified, transcribe.cpp's default thread count (up to 8) cost 23.5 s of CPU; 4 threads 8.2 s, 2 threads 7.7 s, 1 thread 6.8 s, with identical text and caption timing. Release-to-text was 114–157 ms for all four. The helper now uses 2 threads on the GPU (the library default on the CPU backend). Whole-recording speed is unchanged: Parakeet Unified long 419 ms, short 54 ms; Whisper Small Turkish 207 ms.

With 2 threads:

| Model | Lookahead | First caption | Caption updates | Helper CPU | Release to text | Diffs |
|---|---|---|---|---|---|---|
| Parakeet Unified | 2080 ms (model default) | 2.5 s | 43 | 2.3 s | 192 ms | — |
| Parakeet Unified | 1120 ms | 1.8 s | 79 | 3.0 s | 96 ms | 0 |
| Parakeet Unified | **480 ms (Sotto's default)** | 1.0 s | 172 | 7.3 s | 147 ms | 0 |
| Parakeet Unified | 320 ms | 0.9 s | 174 | 7.4 s | 52 ms | 0 |
| Parakeet Unified | 160 ms (8 threads) | 0.75 s | 219 | | 79 ms | 9 (wrong words) |
| Nemotron 3.5 | 1120 ms (model default) | 1.5 s | 40 | 3.6 s | 45 ms | — |
| Nemotron 3.5 | 560 ms | 0.7 s | 78 | 4.9 s | 41 ms | 2 (punctuation) |
| Nemotron 3.5 | 320 ms | 0.6 s | 130 | 5.3 s | 36 ms | 3 (punctuation) |
| Nemotron 3.5 | 80 ms (8 threads) | 0.4 s | 226 | | 62 ms | 6 (lost a clause) |

On the 4.6 s clip, 320 ms and below dropped the final period ("Thanks"); 480 ms matched. The 160 ms and 80 ms settings aren't offered.

## 2026-10-28: Neural Engine (FluidAudio CoreML) against GPU (transcribe.cpp)

Same model, two builds. GPU: `--model <gguf>`; Neural Engine: `--model-id <id> --engine neuralEngine`, which downloads the pinned CoreML files through ModelStore (each result reports `"engine"`). Streaming models with `--live` (real time, 64 ms chunks); the others as whole clips with `--repeat`. CPU is process CPU time; GPU and Neural Engine power were not measured (that needs `sudo powermetrics`).

**Parakeet Unified**, 45.8 s clip with no pauses, streamed:

| Setting | After release, NE / GPU | First live text, NE / GPU | CPU, NE (app) / GPU (helper) | Text |
|---|---|---|---|---|
| 320 ms | 36 / 52 ms | 0.79 / 0.88 s | 4.0 / 7.4 s | same |
| 1120 ms | 36 / 96 ms | 1.7 / 1.8 s | 1.8 / 3.0 s | same |
| 2080 ms | 38 / 192 ms | 2.1 / 2.5 s | 1.5 / 2.3 s | same (NE kept the final period) |

Each setting is a separate 580 MB encoder, so Sotto ships 320 ms. Through the app's own path (`--model-id`): 33–37 ms after release, first live text at 0.87–1.0 s.

**Nemotron 3.5 Streaming**, 45.8 s clip, streamed: NE (560 ms chunks) 33–40 ms after release, first live text 1.14 s, CPU 4.9 s, 3 punctuation differences; GPU (560 ms setting) 41 ms, 0.74 s, 4.9 s. NE with 1120 ms chunks: 63 ms, 1.28 s, CPU 4.4 s. Turkish (`tr-TR`) was equally poor on both.

**Nemotron Speech Streaming (English)**, streamed: NE dropped opening words ("Here is my plan" → "Is my plan" at 560 ms; "Hey, can you" → "Can you" at 1120 ms) and wrote "hockey" for "hotkey"; the GPU build at the same settings didn't. First live text, NE / GPU: 1.12 / 0.70 s at 560 ms, 1.24 / 1.30 s at 1120 ms.

**Whole clips** (transcribe time, runs after the first; 4.6 s and 45.8 s clips):

| Model | Short, NE / GPU | Long, NE / GPU | Text |
|---|---|---|---|
| Parakeet TDT 0.6B v2 | 46 / 48–49 ms | 124 / 371–443 ms | one comma apart |
| Parakeet Ultra | 45 / 56–57 ms | 161–173 / 527–759 ms | two punctuation marks apart |
| Parakeet TDT-CTC 110M | 17 / 24 ms | 57–65 / 186–219 ms | "fifty" against "50" |
| Cohere Transcribe | 21,761–22,270 / 129–133 ms | 46,491–47,793 / 1,077–1,107 ms | same |

Cohere's CoreML encoder (1.9 GB) evidently falls back to the CPU; it isn't offered. Parakeet v2's CoreML build prints "E5RT … zero shape error" while loading, with correct output.

The first comparison of the four whole-clip models was discarded: the app bundle predated their manifest entries, so both runs used the GPU.
