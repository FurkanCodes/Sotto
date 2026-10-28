# Sotto feature video

A Remotion project that renders Sotto's feature video. It isn't part of the app, and nothing here ships in `Sotto.app`.

```sh
npm install
python3 scripts/elevenlabs.py      # narration, sound effects and the ambient bed
npm run studio                     # preview and scrub in the browser
npm run render && npm run master   # out/sotto-promo-final.mp4, loudness-normalized
```

- **Look:** midnight and fog scenes alternate, lit by one sodium-amber accent. Bricolage Grotesque for headlines, IBM Plex Mono for notes, Fraunces italic only for the musical markings (sotto voce, pp), and the system font inside app UI. The fonts load from Google Fonts at render time.
- **Audio:** everything comes from ElevenLabs via `scripts/elevenlabs.py`. The key is read from the Keychain item `elevenlabs`. The narration is the voice Will on `eleven_v3`, from the lines in `scripts/lines.json`, and scenes time their key moments to its word timings. The sound effects and the 22 s ambient bed come from the sound-effects model, and the bed is crossfaded into a loop that dips under the voice. Anything already generated is kept, so re-runs spend no credits.
- **App UI** in `public/shots/` is real: screenshots of the Settings and Transcribe a File windows, captured at 2× in dark mode. History and Dictionary aren't captured, because they show the user's own dictations and words; those features are drawn with demo text instead.
- **Every example is real output:** the cleanup, style, custom word, replacement and "send it" examples were run through SottoCore.
- **Numbers** come from measurements only: `docs/measurements.md` and `public/data/cpu-trace.json`.
