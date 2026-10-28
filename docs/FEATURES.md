# Sotto feature list

The features we're coming back to. Tick each one off when it ships. Details for each one (where the idea comes from, effort, and whether it needs the network) are in `ROADMAP.md`. Current order: the in-house parts of B next (13, 12, 17), then D. C becomes a separate plugin system, designed later.

## A. Daily-use basics (all offline)

- [x] 1. **History window:** search, copy, star, delete, retention (on by default, 7 days, text only). Still to do: keeping the audio and re-transcribing it.
- [x] 2. **Clear failure notices:** silent or muted mic, missing mic, denied mic, missing model. The pill says how to fix it, and the menu links to setup. Still to do: a clickable fix button in the pill.
- [x] 3. **Auto-send:** press Enter or ⌘Enter after pasting, per app, or say "…send it".
- [x] 4. **Snippets:** say "my address" and the full address is typed, with date, time and clipboard variables.
- [x] 5. **Exact replacements:** "gee mail" → "Gmail", "dot com" → ".com"; import your dictionary from Handy.
- [x] 6. **Lower music and video volume while you dictate.**
- [~] 7. **More triggers:** ☑ a mouse button (middle, back or forward). Still to do: a separate toggle shortcut and a choice of cancel key.
- [x] 8. **Transcribe a file:** drop in a voice memo or video and get the text.
- [x] 9. **Apps to skip:** the dictation key does nothing in password managers, games and similar apps.
- [x] 10. **Live text in the pill** as each piece finishes.
- [x] 11. **Usage stats** (words dictated, time saved), stored only on your Mac.

## B. Smart formatting

Built in-house, with rules instead of an AI model: 13, 12 and 17, in that order. 14 and 15 need an AI model and are on hold, because Sotto shouldn't depend on something outside it.

- [ ] 12. **Self-correction (rule-based):** clear corrections like "at 2, actually 3" → "at 3" and "Ali, no wait, Mehmet" → "Mehmet"; vaguer ones stay as spoken.
- [ ] 13. **A style per app (rule-based):** capitalization and punctuation rules per app type (casual in chat, proper sentences in email, no auto-punctuation in code editors and terminals), editable per app.
- [ ] 14. *(On hold: needs an AI model.)* **Custom modes:** "Polish", "Make it shorter", "Write as a prompt", "Translate to English", each with its own key or spoken trigger.
- [ ] 15. *(On hold: needs an AI model.)* **Voice editing:** select text and say "make this more formal".
- [ ] 16. **Context awareness:** knowing the app drives 13. Rewriting from the surrounding text is on hold, because it needs an AI model.
- [ ] 17. **The dictionary learns:** after a paste, Sotto watches the field briefly; if you fix a word, it offers to add it.

## C. Plugins (separate system, designed later)

Plugins get their own design. Buffer will be one plugin. The items below are ideas to fold into that design.

- [ ] 18. **Send to an Apple Shortcut:** the "send to Buffer" path, with no network code in Sotto.
- [ ] 19. **Send to a local script.**
- [ ] 20. **Send to an app link:** Things, Obsidian, Mail and similar.
- [ ] 21. **Send to a webhook:** Zapier, Make, n8n. Needs the internet.
- [ ] 22. **Choosing where it goes:** say "…send to Buffer", set a default per app, or hold Shift to pick from a list.
- [ ] 23. **Confirm before posting** anything publicly.
- [ ] 24. **A built-in Buffer integration:** paste your key, pick a channel.
- [ ] 25. **Control Sotto from Raycast, Alfred, Stream Deck and Shortcuts** (a `sotto://` link scheme and App Intents).
- [ ] 26. **Command line:** `sotto transcribe file.m4a`.
- [ ] 27. **Let Claude or Cursor on your Mac read your Sotto history** (optional, local only).

## D. More models and languages

- [ ] 28. **Whisper Large v3 Turbo:** Turkish and about 100 languages.
- [ ] 29. **Language switch,** or automatic.
- [ ] 30. **Nemotron and Parakeet Unified:** transcribe while you talk; Nemotron also does Turkish.
- [ ] 31. **Translate any language to English.**
- [ ] 32. **Intel Mac support.**

## E. Meeting notes, fully offline

- [ ] 33. **Record meetings:** mic plus system audio.
- [ ] 34. **Speaker labels:** who said what.
- [ ] 35. **Notes saved as Markdown** in a folder you choose.
- [ ] 36. **On-device summaries** and action items.

## F. Other platforms

- [ ] 37. **iPhone keyboard.**
- [ ] 38. **Windows and Linux.**

## Open decisions

1. **Integrations and the network rule:** "Sotto itself never needs the network; text leaves only when you send it to a destination you set up". Allow webhooks, or Shortcuts only?
2. **History:** off by default, or on with a 7-day limit? Keep audio?
3. **AI formatting:** Apple's on-device model only, or also a local AI server like Ollama?
4. **Turkish:** move it ahead of milestone B?
