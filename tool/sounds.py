#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.10"
# dependencies = []
# ///
"""Renders the launcher's UI sounds: the polish plan's prototype tones, as 16-bit mono WAV files in res/raw, where
`SoundPool` plays them.

    uv run tool/sounds.py
"""

import math
import struct
import wave
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RAW = ROOT / "android/app/src/main/res/raw"
RATE = 44100
ATTACK = 0.003  # seconds; a softer start than a hard edge, still instant to the ear

FOCUS_HZ = 560


def tone(freq_start, freq_end, length, level, decay):
    """A sine sweeping from freq_start to freq_end, with a short attack and an exponential decay."""
    samples = []
    phase = 0.0
    count = int(length * RATE)
    for i in range(count):
        t = i / RATE
        freq = freq_start + (freq_end - freq_start) * (i / count)
        phase += 2 * math.pi * freq / RATE
        envelope = min(1.0, t / ATTACK) * math.exp(-t / decay)
        # Fade the last 5 ms to zero so the end never clicks.
        tail = min(1.0, (count - i) / (0.005 * RATE))
        samples.append(level * envelope * tail * math.sin(phase))
    return samples


def silence(length):
    return [0.0] * int(length * RATE)


SOUNDS = {
    # Sine blip, 90 ms.
    "ui_focus": tone(FOCUS_HZ, FOCUS_HZ, 0.090, 0.5, 0.030),
    # Low thud, 170 Hz falling a little, 140 ms.
    "ui_thud": tone(170, 120, 0.140, 0.7, 0.050),
    # Short high click, 880 Hz, 60 ms.
    "ui_select": tone(880, 880, 0.060, 0.5, 0.015),
    # Two-note blips for the side panels, up to open and down to close.
    "ui_panel_open": tone(660, 660, 0.060, 0.35, 0.025) + silence(0.010) + tone(880, 880, 0.070, 0.35, 0.025),
    "ui_panel_close": tone(880, 880, 0.060, 0.35, 0.025) + silence(0.010) + tone(660, 660, 0.070, 0.35, 0.025),
    # Home: a soft low tone settling a little, quieter than the focus blip.
    "ui_home": tone(440, 392, 0.160, 0.25, 0.060),
    # The soft tick while a held key runs along a row.
    "ui_tick": tone(FOCUS_HZ, FOCUS_HZ, 0.040, 0.3, 0.012),
}


def write(name, samples):
    RAW.mkdir(parents=True, exist_ok=True)
    with wave.open(str(RAW / f"{name}.wav"), "wb") as out:
        out.setnchannels(1)
        out.setsampwidth(2)
        out.setframerate(RATE)
        out.writeframes(b"".join(struct.pack("<h", int(max(-1, min(1, s)) * 32767)) for s in samples))


def main():
    for name, samples in SOUNDS.items():
        write(name, samples)
        print(f"{name}.wav  {len(samples) / RATE * 1000:.0f} ms")


if __name__ == "__main__":
    main()
