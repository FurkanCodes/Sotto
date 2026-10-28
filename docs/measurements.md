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
