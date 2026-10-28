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
