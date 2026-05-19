#!/usr/bin/env python3
"""Generate a Sidebeat Lanes chart draft from an audio file.

This is intentionally a draft generator: it detects BPM/beat positions and onset
strengths, then maps strong events to lanes. Human polishing in admin.html is
expected.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any

import librosa
import numpy as np

DIFFICULTY = {
    "easy": {"density": 0.38, "min_gap_ms": 360, "long_ratio": 0.03},
    "normal": {"density": 0.55, "min_gap_ms": 260, "long_ratio": 0.05},
    "hard": {"density": 0.74, "min_gap_ms": 180, "long_ratio": 0.08},
    "expert": {"density": 0.92, "min_gap_ms": 120, "long_ratio": 0.11},
}


def detect(audio_path: Path, difficulty: str) -> dict[str, Any]:
    y, sr = librosa.load(audio_path, mono=True)
    tempo, beat_frames = librosa.beat.beat_track(y=y, sr=sr, units="frames")
    bpm = float(np.asarray(tempo).reshape(-1)[0]) if np.asarray(tempo).size else 120.0
    onset_env = librosa.onset.onset_strength(y=y, sr=sr)
    onset_frames = librosa.onset.onset_detect(onset_envelope=onset_env, sr=sr, backtrack=True)
    onset_times = librosa.frames_to_time(onset_frames, sr=sr) * 1000
    beat_times = librosa.frames_to_time(beat_frames, sr=sr) * 1000

    cfg = DIFFICULTY[difficulty]
    candidates: list[tuple[float, float]] = []
    if len(onset_frames):
        strengths = onset_env[np.clip(onset_frames, 0, len(onset_env) - 1)]
        threshold = np.quantile(strengths, 1.0 - cfg["density"])
        for time, strength in zip(onset_times, strengths):
            if strength >= threshold:
                candidates.append((float(time), float(strength)))

    # Keep stable beat anchors so sparse songs still produce a playable chart.
    for idx, time in enumerate(beat_times):
        if idx % (2 if difficulty == "easy" else 1) == 0:
            candidates.append((float(time), 0.0))

    candidates.sort(key=lambda item: item[0])
    notes = []
    last_time = -99999.0
    beat_ms = 60000.0 / max(bpm, 1.0)
    for idx, (time, strength) in enumerate(candidates):
        if time - last_time < cfg["min_gap_ms"]:
            continue
        lane = int((idx + round(strength)) % 4)
        duration = 0
        if strength > 0 and (idx % max(2, int(1 / cfg["long_ratio"]))) == 0:
            duration = int(max(beat_ms, 450))
        notes.append({"lane": lane, "time": int(round(time)), "duration": duration})
        last_time = time

    return {
        "title": audio_path.stem,
        "format": "sidebeat-lanes-chart-v3",
        "difficulty": difficulty,
        "bpm": round(bpm, 3),
        "offset": 0,
        "latencyMs": 0,
        "audioFileName": audio_path.name,
        "generator": "tools/chartgen/generate_chart.py librosa beat+onset draft",
        "notes": notes,
    }


def main() -> None:
    parser = argparse.ArgumentParser(description="Generate a Sidebeat Lanes chart JSON draft from audio.")
    parser.add_argument("audio", type=Path)
    parser.add_argument("--difficulty", choices=DIFFICULTY.keys(), default="normal")
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()

    chart = detect(args.audio, args.difficulty)
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(chart, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"Generated {len(chart['notes'])} notes at {chart['bpm']} BPM -> {args.out}")


if __name__ == "__main__":
    main()
