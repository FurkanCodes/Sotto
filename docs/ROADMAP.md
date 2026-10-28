# Sotto feature roadmap

Written 2026-10-28, from two research passes:
- `~/Projects/dictation-research/notes/handy-features.md`: every Handy feature, read from its source. That's 164 features; Sotto has 13, 21 in part.
- `~/Projects/dictation-research/notes/wispr-and-competitors-features.md`: Wispr Flow, Superwhisper, VoiceInk, MacWhisper, Monologue, Aqua Voice and Spokenly, from public docs only, with a source URL for each claim. Wispr Flow was not decompiled.

Effort is a rough guess for this codebase: **S** about a day, **M** 2–4 days, **L** 1–2 weeks. "Network" marks anything that would break the current offline rule.

## Where Sotto stands

**Ahead:**
- fully offline transcription, which Wispr Flow can't do because all its transcription runs in the cloud;
- release-to-text in 50–100 ms;
- 0% idle CPU and about 26 MB idle memory;
- a clipboard that comes back intact;
- a native UI.

**Behind**, against Wispr Flow and the field:
- no history;
- no AI formatting (styles, self-correction, voice editing);
- no snippets;
- no way to send text anywhere except the focused app;
- no automation hooks;
- no meeting notes;
- English and 24 other European languages only, with no Turkish;
- Mac only.

**What nobody does well yet:** combining offline privacy with the smart features. Wispr Flow is smart but cloud-only, and even its meeting notes are stored in its cloud with no opt-out. Handy is offline but plain. The apps that do both (VoiceInk, MacWhisper, Superwhisper) do the smart part through Ollama, the user's own API keys, or cloud models. Sotto's opening is the smart features done on the device.

## Rule change needed for integrations

The current rule in `CLAUDE.md` is: no network use except the model download. Sending text to Buffer breaks it. Proposed replacement:

> **Sotto itself never needs the network.** Integrations are destinations the user sets up. Text leaves the Mac only when the user sends a dictation to one, and each destination is labeled with what it connects to.

Most integrations don't even need network code in Sotto: a Shortcut, a script or another app does the sending (milestone C). Only the webhook destination (C4) puts network code in Sotto.

---

## Milestone A: daily-use basics (all offline)

Small, high-value features that every serious dictation app has.

| # | Feature | What it does | Source | Effort |
|---|---|---|---|---|
| A1 | **History window** | Searchable list of past dictations: copy, paste again, star, delete. Retention: off, 1 day, 7 days, 30 days, forever. Optional: keep the audio and re-transcribe it with another model. | Handy, Wispr, everyone | M |
| A2 | **Clear failure notices** | Detects a silent or muted mic ("No sound from MacBook Pro Microphone"), a missing device, a denied mic, a lost permission or a missing model. Each shows in the pill and menu with a fix button. | Handy | S |
| A3 | **Auto-send** | Presses Enter or ⌘Enter after pasting, per app (Slack, Messages, ChatGPT). A spoken "…send it" at the end does it once. | Aqua Voice, Wispr, VoiceInk, Handy | S |
| A4 | **Snippets** | Say a trigger ("my address", "calendar link") and Sotto types the stored text. Variables: date, time, clipboard. | Wispr, Superwhisper, VoiceInk | M |
| A5 | **Exact replacements** | "gee mail" → "Gmail" and "dot com" → ".com", alongside the existing fuzzy custom words. Import the dictionary from Handy. | Wispr, VoiceInk, Aqua | S |
| A6 | **Lower media volume while dictating** | Pauses or ducks music and video so it doesn't bleed into the mic, then restores it. | Handy, Wispr | S |
| A7 | **More triggers** | A mouse side button as the dictation key; a separate toggle shortcut alongside hold-to-talk; a choice of cancel key. | Wispr, VoiceInk, Handy | S |
| A8 | **Transcribe a file** | Drop an audio or video file (voice memo, recording) on Sotto and get the text. It reuses the existing pipeline. | Handy, MacWhisper | M |
| A9 | **Apps to skip** | A list of apps where the dictation key does nothing: password managers, games, remote desktops. | (common request) | S |
| A10 | **Live text in the pill (optional)** | Shows the words as each piece finishes, so long dictations show progress. | Handy | M |
| A11 | **Usage stats, stored locally** | Words dictated and time saved, kept on this Mac and never sent anywhere. | Wispr | S |

## Milestone B: smart formatting on the device

Uses **Apple Foundation Models**, the on-device model in macOS 26. It's free and private, but needs a Mac with Apple Intelligence turned on, and has language limits that need checking for Turkish. An optional "local AI server" setting (Ollama or LM Studio on the same Mac) covers Macs without it. The AI step gets its own latency budget, separate from the 100 ms target, and it's off unless a style or mode asks for it.

| # | Feature | What it does | Source | Effort |
|---|---|---|---|---|
| B1 | **Self-correction** | "Let's meet at 2, actually 3" → "Let's meet at 3". "No wait" and "I mean" are handled. | Wispr (Backtrack), Monologue | M |
| B2 | **Styles per app** | Casual for chat, formal for email, plain for code editors and terminals. Picked automatically by app or website, and editable. | Wispr Styles, Superwhisper and VoiceInk modes | M |
| B3 | **Modes / custom prompts** | User-made modes such as "Polish", "Make it shorter", "Write as a prompt", "Translate to English", each with its own key or spoken trigger. The prompt can use variables: selected text, app name, clipboard. | Wispr Transforms, Superwhisper, VoiceInk, MacWhisper | L |
| B4 | **Voice editing (command mode)** | Select text, hold the key and say "make this more formal" or "turn this into bullet points"; the selection is replaced. | Wispr Command Mode, Aqua Edit Mode | M |
| B5 | **Context awareness** | Reads the app name and the text around the cursor through Accessibility, so names, replies and formatting fit. Can be turned off per app. | Wispr, Superwhisper, VoiceInk | M |
| B6 | **Learning the dictionary** | When you fix a misheard word right after dictating, Sotto offers to add it to the dictionary. | Wispr, VoiceInk | L |

## Milestone C: integrations (the plugin system)

The plugin unit is a **destination**: a place a dictation can go instead of the focused app. That covers "send this to Buffer".

| # | Feature | What it does | Network in Sotto? | Effort |
|---|---|---|---|---|
| C1 | **Shortcut destination** | Sotto runs one of your Apple Shortcuts with the text. **This is the Buffer path:** a Shortcut with "Get Contents of URL" posts to Buffer's API using your Buffer key. The same pattern works for Notion, Todoist, Slack and more. | **No**; the Shortcut sends | S–M |
| C2 | **Script destination** | Runs a local command with the text on its input and in an environment variable (`SOTTO_TEXT`), with a timeout. Power users can wire anything. | No | S |
| C3 | **App link destination** | Opens a link template with the text filled in, such as `things:///add?title={text}`, `obsidian://new?content={text}` or `mailto:`. | No | S |
| C4 | **Webhook destination** | POSTs the text as JSON to a URL (Zapier, Make, n8n, your server). The key is kept in the Keychain, with a Test button, and the destination is labeled "connects to the internet". | **Yes** (needs the rule change) | M |
| C5 | **Routing** | Choose where a dictation goes in three ways: a spoken ending ("…send to Buffer", stripped from the text), a default per app, or holding Shift on release to pick from a list. | No | M |
| C6 | **Confirm before posting** | For public destinations the pill asks "Post to Buffer?" ⏎ / Esc, showing the text first. | No | S |
| C7 | **Built-in Buffer** | A native Buffer destination: paste your key, pick a channel. Only worth doing if C1 feels too fiddly in practice. | Yes | M |
| C8 | **Controlling Sotto from outside** | A `sotto://` link scheme (start, stop, cancel, transcribe a file) for Raycast, Alfred and Stream Deck; App Intents, so Shortcuts can "Dictate with Sotto" and get the text back. | No | M |
| C9 | **Command line** | `sotto transcribe file.m4a` prints the text. The headless mode already exists. | No | S |
| C10 | **Local MCP server (opt-in)** | Lets Claude or Cursor on this Mac read your Sotto history. | No (local only) | M |

## Milestone D: more models and languages (PLAN.md Phase 4)

| # | Feature | Why | Effort |
|---|---|---|---|
| D1 | **Whisper Large v3 Turbo** in the transcribe-cpp helper | Turkish and about 100 languages | L |
| D2 | **Language switch** | Pick a model per language, or "auto"; a menu item to switch quickly | M |
| D3 | **Nemotron Streaming / Parakeet Unified** | Transcribing while you talk, natively; Nemotron also does Turkish | M |
| D4 | **Translate to English** | Whisper can output English from any language | S |
| D5 | **Intel Macs** | transcribe-cpp on the CPU, as Handy does | M |

## Milestone E: meetings and notes, fully offline

Wispr's Notetaker stores notes in its cloud. A local version is a clear selling point.

| # | Feature | What it does | Effort |
|---|---|---|---|
| E1 | **Record a meeting** | Mic plus system audio, using macOS's built-in audio capture, transcribed live on the device | L |
| E2 | **Who said what** | Speaker labels; FluidAudio already ships a speaker-diarization model | M |
| E3 | **Notes library** | Notes saved as Markdown files in a folder you choose, searchable | M |
| E4 | **Summaries** | Apple Foundation Models writes the summary and action items, on the device | M |

## Milestone F: other platforms (already decided)

- **iOS keyboard** (Swift): dictation inside any iPhone app. Keyboards have a tight memory limit, so this needs a measurement first.
- **Windows and Linux** (Rust + GPUI): passing the shared test cases in `Tests/Fixtures`.

---

## Recommended order

1. **Milestone A,** in its listed order: history, failure notices and auto-send first. This is what you'd notice every day.
2. **C1–C3 and C5** (Shortcut, script and app-link destinations, plus routing). That delivers "send this to Buffer" without any network code in Sotto.
3. **Milestone B** (on-device smart formatting). This is where Sotto beats Wispr Flow on privacy while matching its smarts.
4. **D1–D2** (Whisper for Turkish).
5. **Milestone E** (offline meeting notes).
6. **C4, C7–C10, then F,** as needed.

## Decisions for the user

1. **The rule change for integrations:** adopt the proposed wording? Allow webhooks (C4), or keep Sotto network-free and rely on Shortcuts?
2. **History:** off by default (today's privacy promise) or on with a 7-day limit? Keep audio or not?
3. **AI formatting:** use Apple Foundation Models only, or also allow a local AI server like Ollama?
4. **Turkish:** does it move ahead of milestone B?
