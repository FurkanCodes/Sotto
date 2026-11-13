#!/usr/bin/env python3
"""Writes Resources/neural-engine-models.json: the CoreML models Sotto runs on
the Neural Engine through FluidAudio (catalog models, plus the built-in
Parakeet v3 and the Silero voice detector), each pinned to a Hugging Face commit with
the size and SHA-256 of every file it needs. Sotto downloads exactly these
files and checks each hash before loading, so a change upstream can't reach a
user until this script is run again and the result reviewed.

Usage: scripts/pin-neural-models.py [--refresh]
Without --refresh, models already in the file keep their pinned commit.
"""
import hashlib
import json
import os
import sys
import urllib.request

OUT = os.path.join(os.path.dirname(__file__), "..", "Resources", "neural-engine-models.json")

# catalogID: the model-catalog.json entry this replaces on the GPU.
# engine: which FluidAudio manager Sotto drives (Sources/Sotto/Engine/NeuralEngine*.swift).
# paths: the files or folders that engine loads, relative to the repository.
MODELS = [
    {
        "catalogID": "parakeet-unified-en-0.6b",
        "engine": "parakeet-unified-stream",
        "repository": "FluidInference/parakeet-unified-en-0.6b-coreml",
        "paths": [
            "parakeet_unified_encoder_streaming_70_2_2_int8.mlmodelc",
            "parakeet_unified_decoder.mlmodelc",
            "parakeet_unified_joint_decision_single_step.mlmodelc",
            "vocab.json",
        ],
    },
    {
        # 560 ms chunks: live text at 1.1 s against 1.3 s for 1120 ms, with the
        # same words. The full-vocabulary build, so Turkish works.
        "catalogID": "nemotron-3.5-asr-streaming-0.6b",
        "engine": "nemotron-multilingual-stream",
        "repository": "FluidInference/Nemotron-3.5-ASR-Streaming-Multilingual-0.6b-CoreML",
        "root": "multilingual/560ms",
        "chunkMs": 560,
        "paths": ["multilingual/560ms"],
    },
    {
        # Dropped opening words on the bench clips ("Here is my plan" -> "Is my
        # plan") where the GPU build didn't, so Automatic keeps the GPU build.
        "catalogID": "nemotron-speech-streaming-en-0.6b",
        "engine": "nemotron-en-stream",
        "repository": "FluidInference/nemotron-speech-streaming-en-0.6b-coreml",
        "root": "nemotron_coreml_1120ms",
        "chunkMs": 1120,
        "automatic": False,
        "paths": ["nemotron_coreml_1120ms"],
    },
    {
        "catalogID": "parakeet-tdt-0.6b-v2",
        "engine": "parakeet-v2",
        "repository": "FluidInference/parakeet-tdt-0.6b-v2-coreml",
        "paths": ["Preprocessor.mlmodelc", "Encoder.mlmodelc", "Decoder.mlmodelc", "JointDecision.mlmodelc", "parakeet_vocab.json"],
    },
    {
        "catalogID": "parakeet-ultra",
        "engine": "parakeet-ultra",
        "repository": "FluidInference/parakeet-ultra-coreml",
        "paths": ["Preprocessor.mlmodelc", "Encoder.mlmodelc", "Decoder.mlmodelc", "JointDecisionv3.mlmodelc",
                  "parakeet_vocab.json", "parakeet_v3_vocab.json"],
    },
    {
        "catalogID": "parakeet-tdt_ctc-110m",
        "engine": "parakeet-tdt-ctc-110m",
        "repository": "FluidInference/parakeet-tdt-ctc-110m-coreml",
        "paths": ["Preprocessor.mlmodelc", "Decoder.mlmodelc", "JointDecision.mlmodelc", "parakeet_vocab.json"],
    },
]
# The built-in model and the voice detector, which every install needs.
BUILT_IN = [
    {
        "catalogID": "parakeet-tdt-0.6b-v3",
        "engine": "built-in",
        "repository": "FluidInference/parakeet-tdt-0.6b-v3-coreml",
        "paths": ["Preprocessor.mlmodelc", "Encoder.mlmodelc", "Decoder.mlmodelc", "JointDecisionv3.mlmodelc",
                  "parakeet_v3_vocab.json", "parakeet_vocab.json"],
    },
    {
        "catalogID": "silero-vad",
        "engine": "built-in",
        "repository": "FluidInference/silero-vad-coreml",
        "paths": ["silero-vad-unified-256ms-v6.2.1.mlmodelc"],
    },
]

# Not here, and why (docs/MODELS.md):
# - cohere-transcribe-03-2026: FluidAudio's CoreML build took 22 s for a 4.6 s
#   clip on the Neural Engine (GPU build: 0.13 s).
# - canary-1b-v2: FluidAudio's build only transcribes English.


def get_json(url):
    with urllib.request.urlopen(url, timeout=60) as response:
        return json.load(response)


def git_blob_sha1_to_sha256(repo, revision, path, size):
    """Small files aren't in LFS, so the API gives only their Git hash; fetch them to get a SHA-256."""
    url = f"https://huggingface.co/{repo}/resolve/{revision}/{urllib.request.quote(path)}"
    with urllib.request.urlopen(url, timeout=60) as response:
        data = response.read()
    assert len(data) == size, (path, len(data), size)
    return hashlib.sha256(data).hexdigest()


def pin(spec, revision=None):
    repo = spec["repository"]
    revision = revision or get_json(f"https://huggingface.co/api/models/{repo}")["sha"]
    tree = get_json(f"https://huggingface.co/api/models/{repo}/tree/{revision}?recursive=true")
    files = []
    for entry in tree:
        if entry["type"] != "file":
            continue
        path = entry["path"]
        if not any(path == p or path.startswith(p + "/") for p in spec["paths"]):
            continue
        lfs = entry.get("lfs")
        sha256 = lfs["oid"] if lfs else git_blob_sha1_to_sha256(repo, revision, path, entry["size"])
        files.append({"path": path, "size": entry["size"], "sha256": sha256})
    found = {p for p in spec["paths"] if any(f["path"] == p or f["path"].startswith(p + "/") for f in files)}
    missing = set(spec["paths"]) - found
    if missing:
        sys.exit(f"{repo}@{revision}: missing {sorted(missing)}")
    files.sort(key=lambda f: f["path"])
    pinned = {
        "catalogID": spec["catalogID"],
        "engine": spec["engine"],
        "repository": repo,
        "revision": revision,
        "size": sum(f["size"] for f in files),
        "files": files,
    }
    for key in ("root", "chunkMs", "automatic"):
        if key in spec:
            pinned[key] = spec[key]
    return pinned


def main():
    refresh = "--refresh" in sys.argv
    old = {}
    if os.path.exists(OUT):
        existing = json.load(open(OUT))
        old = {m["catalogID"]: m for m in existing["models"] + existing.get("builtIn", [])}

    def pin_all(specs):
        pinned_list = []
        for spec in specs:
            previous = old.get(spec["catalogID"])
            keep = previous and not refresh and previous["repository"] == spec["repository"]
            pinned = pin(spec, previous["revision"] if keep else None)
            print(f'{pinned["catalogID"]}: {pinned["repository"]}@{pinned["revision"][:10]}, '
                  f'{len(pinned["files"])} files, {pinned["size"] / 1e6:.0f} MB')
            pinned_list.append(pinned)
        return pinned_list

    result = {"models": pin_all(MODELS), "builtIn": pin_all(BUILT_IN)}
    with open(OUT, "w") as out:
        json.dump(result, out, indent=1)
        out.write("\n")


if __name__ == "__main__":
    main()
