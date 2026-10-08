#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.10"
# dependencies = ["pillow>=10"]
# ///
"""Renders the Android TV banner: the launcher's themed background with the wordmark inside a focused tile's
brass ring.

The colours mirror `Palette` in lib/theme.dart; run this again after changing them. The wordmark is set in
Roboto Medium from the Flutter SDK cache (pass --font to use another file).

    uv run tool/banner.py
"""

import argparse
import subprocess
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

WIDTH, HEIGHT = 320, 180
BG_TOP = (0x1C, 0x24, 0x19)
BG_BOTTOM = (0x0F, 0x14, 0x0E)
GLOW = (0x5A, 0x4A, 0x2A)
GLOW_OPACITY = 0.18
GLOW_CENTER = (0.5, 0.85)
GLOW_RADIUS = 0.9  # of the width
CREAM = (0xED, 0xE6, 0xD6)
BRASS = (0xC9, 0xA4, 0x5C)
WORDMARK = "Launcher"
RING_PADDING = 22  # left and right of the text; the ring is a 16:9 tile outline around it
RING_RADIUS = 12
RING_WIDTH = 3
OUTPUT = Path(__file__).resolve().parent.parent / "android/app/src/main/res/drawable-xhdpi/banner.png"


def flutter_roboto() -> Path:
    root = subprocess.run(["mise", "where", "flutter"], capture_output=True, text=True, check=True).stdout.strip()
    return Path(root) / "bin/cache/artifacts/material_fonts/Roboto-Medium.ttf"


def background(width: int, height: int) -> Image.Image:
    image = Image.new("RGB", (width, height))
    pixels = image.load()
    cx, cy = GLOW_CENTER[0] * width, GLOW_CENTER[1] * height
    radius = GLOW_RADIUS * width
    for y in range(height):
        t = y / (height - 1)
        base = tuple(round(BG_TOP[i] + (BG_BOTTOM[i] - BG_TOP[i]) * t) for i in range(3))
        for x in range(width):
            distance = ((x - cx) ** 2 + (y - cy) ** 2) ** 0.5
            alpha = GLOW_OPACITY * max(0.0, 1 - distance / radius)
            pixels[x, y] = tuple(round(base[i] + (GLOW[i] - base[i]) * alpha) for i in range(3))
    return image


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--font", type=Path, default=None, help="TTF for the wordmark")
    parser.add_argument("--output", type=Path, default=OUTPUT)
    parser.add_argument("--scale", type=int, default=4, help="supersampling factor")
    args = parser.parse_args()

    scale = args.scale
    image = background(WIDTH * scale, HEIGHT * scale)
    font = ImageFont.truetype(str(args.font or flutter_roboto()), 44 * scale)
    draw = ImageDraw.Draw(image)
    left, top, right, bottom = draw.textbbox((0, 0), WORDMARK, font=font)
    x = (WIDTH * scale - (right - left)) / 2 - left
    y = (HEIGHT * scale - (bottom - top)) / 2 - top
    draw.text((x, y), WORDMARK, font=font, fill=CREAM)
    ring_width = (right - left) + 2 * RING_PADDING * scale
    ring_height = ring_width * 9 / 16
    cx, cy = x + (left + right) / 2, y + (top + bottom) / 2
    draw.rounded_rectangle(
        (cx - ring_width / 2, cy - ring_height / 2, cx + ring_width / 2, cy + ring_height / 2),
        radius=RING_RADIUS * scale,
        outline=BRASS,
        width=RING_WIDTH * scale,
    )
    image = image.resize((WIDTH, HEIGHT), Image.LANCZOS)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    image.save(args.output, optimize=True)
    print(f"wrote {args.output}")


if __name__ == "__main__":
    main()
