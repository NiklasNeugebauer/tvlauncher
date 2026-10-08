#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.10"
# dependencies = ["pillow>=10"]
# ///
"""Renders the launcher's artwork from the palette: the Android TV banner, the launcher icon at every density,
and the logo shown in the About dialog. Everything is the themed background with a brass tile ring on it; the
banner carries the wordmark, the icon and logo an "L".

The colours mirror `Palette` in lib/theme.dart and the type is the bundled Source Sans 3; run this again after
changing either.

    uv run tool/artwork.py
"""

import argparse
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
RES = ROOT / "android/app/src/main/res"
FONT = ROOT / "fonts/SourceSans3-Medium.ttf"

BG_TOP = (0x1C, 0x24, 0x19)
BG_BOTTOM = (0x0F, 0x14, 0x0E)
GLOW = (0x5A, 0x4A, 0x2A)
GLOW_OPACITY = 0.18
GLOW_CENTER = (0.5, 0.85)
GLOW_RADIUS = 0.9  # of the width
CREAM = (0xED, 0xE6, 0xD6)
BRASS = (0xC9, 0xA4, 0x5C)

BANNER_SIZE = (320, 180)
BANNER_TEXT = ("Launcher", 44)
BANNER_RING_PADDING = 22  # left and right of the text; the ring is a 16:9 tile outline around it
RING_RADIUS = 12  # at banner scale; the icon scales these with its size
RING_WIDTH = 3

ICON_DENSITIES = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}
ICON_RING_WIDTH_FRACTION = 0.74  # of the icon's width
ICON_TEXT = ("L", 0.36)  # glyph and its size as a fraction of the icon's width
LOGO_SIZE = 192

SCALE = 4  # supersampling


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


def centred_text(draw: ImageDraw.ImageDraw, image: Image.Image, text: str, size: float) -> tuple[float, float]:
    """Draws [text] centred and returns its visual centre."""
    font = ImageFont.truetype(str(FONT), round(size))
    left, top, right, bottom = draw.textbbox((0, 0), text, font=font)
    x = (image.width - (right - left)) / 2 - left
    y = (image.height - (bottom - top)) / 2 - top
    draw.text((x, y), text, font=font, fill=CREAM)
    return x + (left + right) / 2, y + (top + bottom) / 2


def ring(draw: ImageDraw.ImageDraw, centre: tuple[float, float], width: float, scale: float) -> None:
    """A 16:9 tile outline, like a focused tile's ring."""
    height = width * 9 / 16
    cx, cy = centre
    draw.rounded_rectangle(
        (cx - width / 2, cy - height / 2, cx + width / 2, cy + height / 2),
        radius=RING_RADIUS * scale,
        outline=BRASS,
        width=round(RING_WIDTH * scale),
    )


def render_banner() -> Image.Image:
    width, height = BANNER_SIZE
    image = background(width * SCALE, height * SCALE)
    draw = ImageDraw.Draw(image)
    text, size = BANNER_TEXT
    font = ImageFont.truetype(str(FONT), size * SCALE)
    left, _, right, _ = draw.textbbox((0, 0), text, font=font)
    centre = centred_text(draw, image, text, size * SCALE)
    ring(draw, centre, (right - left) + 2 * BANNER_RING_PADDING * SCALE, SCALE)
    return image.resize((width, height), Image.LANCZOS)


def render_icon(size: int) -> Image.Image:
    # Rings and strokes scale with the icon so every density is the same picture.
    scale = size / 96 * SCALE
    image = background(size * SCALE, size * SCALE)
    draw = ImageDraw.Draw(image)
    glyph, fraction = ICON_TEXT
    centre = centred_text(draw, image, glyph, fraction * size * SCALE)
    ring(draw, centre, ICON_RING_WIDTH_FRACTION * size * SCALE, scale)
    return image.resize((size, size), Image.LANCZOS)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.parse_args()

    banner = RES / "drawable-xhdpi/banner.png"
    render_banner().save(banner, optimize=True)
    print(f"wrote {banner}")
    for density, size in ICON_DENSITIES.items():
        icon = RES / f"mipmap-{density}/ic_launcher.png"
        render_icon(size).save(icon, optimize=True)
        print(f"wrote {icon}")
    logo = ROOT / "assets/logo.png"
    render_icon(LOGO_SIZE).save(logo, optimize=True)
    print(f"wrote {logo}")


if __name__ == "__main__":
    main()
