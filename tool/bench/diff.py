#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.10"
# dependencies = ["pillow", "numpy"]
# ///
"""Compares two BENCH_SHOTS directories: per screenshot, the share of pixels that differ and the largest
difference (0-255). Up to 8 counts as the same picture: moving content onto its own layer shifts anti-aliasing by
that much. Writes a red-on-grey diff image next to the second set for every pair that differs more. 4-returned is
not quite deterministic (up to ~35 between two runs of one build)."""
import sys
from pathlib import Path

import numpy as np
from PIL import Image

a_dir, b_dir = Path(sys.argv[1]), Path(sys.argv[2])
worst = 0
for a_path in sorted(a_dir.glob("*.png")):
    b_path = b_dir / a_path.name
    a = np.asarray(Image.open(a_path).convert("RGB"), dtype=np.int16)
    b = np.asarray(Image.open(b_path).convert("RGB"), dtype=np.int16)
    if a.shape != b.shape:
        print(f"{a_path.name}: size {a.shape} vs {b.shape}")
        worst = 255
        continue
    d = np.abs(a - b).max(axis=2)
    changed = (d > 8).mean() * 100
    print(f"{a_path.name}: {changed:.3f}% of pixels differ by more than 8, max {d.max()}")
    worst = max(worst, int(d.max()))
    if d.max() > 8:
        grey = (a.mean(axis=2) * 0.4).astype(np.uint8)
        out = np.stack([np.where(d > 8, 255, grey), grey, grey], axis=2).astype(np.uint8)
        Image.fromarray(out).save(b_dir / f"diff-{a_path.name}")
sys.exit(0 if worst <= 8 else 1)
