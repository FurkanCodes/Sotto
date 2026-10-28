#!/usr/bin/env python3
"""Makes the video's audio with ElevenLabs: narration, sound effects and the
ambient bed. The key comes from the Keychain item "elevenlabs".

    scripts/elevenlabs.py

Anything already generated is kept (narration is redone only when its line or
the voice changes), so re-runs spend no credits. Writes public/sfx/*.wav,
public/narration/<scene>.mp3 and public/narration/timing.json.
"""
import base64
import hashlib
import json
import pathlib
import subprocess
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parent.parent
SFX = ROOT / "public" / "sfx"
RAW = SFX / "raw"
NARRATION = ROOT / "public" / "narration"

VOICE = "bIHbv24MWmeRgasZH58o"  # Will: relaxed, conversational
MODEL = "eleven_v3"

EFFECTS = {
    "keydown": ("A single soft press of a low-profile laptop keyboard key, close-miked, dry, quiet room", 0.6),
    "keyup": ("Releasing a low-profile laptop keyboard key, soft plastic click, close-miked, dry, quiet room", 0.5),
    "keytap": ("One quick light tap on a laptop keyboard key, close-miked, dry", 0.5),
    "thunk": ("Pressing the return key on a laptop keyboard firmly, satisfying soft thock, dry", 0.6),
    "pop": ("Very soft subtle bubble pop, gentle and airy, interface sound, no music", 0.5),
    "tick": ("Tiny soft wooden tick, like a pencil tapping paper once, dry", 0.5),
    "whoosh": ("Very soft airy whoosh, like a page turning quickly, subtle, no music", 0.9),
    "rise": ("Soft breathy rising swell of air, gentle, subtle", 1.2),
    "chime": ("A single warm felt piano note, soft, with a long natural decay", 3),
    "bed": ("Slow warm ambient felt piano chords with soft room tone, calm and intimate, late at night, no drums, gentle and continuous", 22),
}


def key():
    return subprocess.run(["security", "find-generic-password", "-s", "elevenlabs", "-w"], capture_output=True, text=True, check=True).stdout.strip()


def post(url, body):
    request = urllib.request.Request(url, data=json.dumps(body).encode(), headers={"xi-api-key": key(), "Content-Type": "application/json"})
    with urllib.request.urlopen(request) as response:
        return response.read()


def ffmpeg(*args):
    subprocess.run(["ffmpeg", "-v", "error", "-y", *args], check=True)


def duration(path):
    out = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", str(path)], capture_output=True, text=True, check=True)
    return float(out.stdout.strip())


def effects():
    RAW.mkdir(parents=True, exist_ok=True)
    for name, (prompt, seconds) in EFFECTS.items():
        raw = RAW / f"{name}.mp3"
        if not raw.exists():
            raw.write_bytes(post("https://api.elevenlabs.io/v1/sound-generation", {"text": prompt, "duration_seconds": seconds, "prompt_influence": 0.6 if name != "bed" else 0.5}))
            print(f"generated {name}")
        if name == "bed":
            continue
        # Trim the silence before the sound starts, so it lands on its frame.
        ffmpeg("-i", str(raw), "-af", "silenceremove=start_periods=1:start_threshold=-50dB,afade=t=out:st=%.2f:d=0.08" % max(0.05, seconds - 0.1), "-ar", "44100", "-ac", "2", str(SFX / f"{name}.wav"))
    # The bed is 22 s; six copies crossfaded over 4 s cover the whole video.
    bed = str(RAW / "bed.mp3")
    inputs = [arg for _ in range(6) for arg in ("-i", bed)]
    chain, last = [], "[0]"
    for i in range(1, 6):
        chain.append(f"{last}[{i}]acrossfade=d=4:c1=qsin:c2=qsin[b{i}]")
        last = f"[b{i}]"
    ffmpeg(*inputs, "-filter_complex", ";".join(chain), "-map", last, "-ar", "44100", "-ac", "2", str(SFX / "bed.wav"))


def words_from_alignment(alignment):
    words, current, start, last_end = [], "", None, 0.0
    for char, char_start, char_end in zip(alignment["characters"], alignment["character_start_times_seconds"], alignment["character_end_times_seconds"]):
        if char.isspace():
            if current:
                words.append({"text": current, "start": start, "end": last_end})
            current, start = "", None
            continue
        if start is None:
            start = char_start
        current += char
        last_end = char_end
    if current:
        words.append({"text": current, "start": start, "end": last_end})
    return words


def narration():
    lines = json.loads((ROOT / "scripts" / "lines.json").read_text())
    NARRATION.mkdir(parents=True, exist_ok=True)
    timing_path = NARRATION / "timing.json"
    old = json.loads(timing_path.read_text())["clips"] if timing_path.exists() else {}
    ids = list(lines)
    clips = {}
    for index, scene in enumerate(ids):
        text = lines[scene]
        digest = hashlib.sha256(f"{VOICE}\n{MODEL}\n{text}".encode()).hexdigest()[:16]
        mp3 = NARRATION / f"{scene}.mp3"
        if old.get(scene, {}).get("hash") == digest and mp3.exists():
            clips[scene] = old[scene]
            continue
        body = {"text": text, "model_id": MODEL}
        result = json.loads(post(f"https://api.elevenlabs.io/v1/text-to-speech/{VOICE}/with-timestamps?output_format=mp3_44100_128", body))
        mp3.write_bytes(base64.b64decode(result["audio_base64"]))
        clips[scene] = {"file": f"narration/{scene}.mp3", "duration": round(duration(mp3), 3), "words": words_from_alignment(result["alignment"]), "hash": digest}
        print(f"{scene}: {clips[scene]['duration']} s, {len(text)} characters")
    timing_path.write_text(json.dumps({"voice": VOICE, "model": MODEL, "clips": clips}, indent=1) + "\n")


if __name__ == "__main__":
    effects()
    narration()
