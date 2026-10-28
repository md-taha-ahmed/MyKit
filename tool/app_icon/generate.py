"""Renders the MyKit launcher icon PNGs.

The adaptive icon (Android 8+) uses the vector drawables in
android/app/src/main/res/drawable/ic_launcher_*.xml. This script draws the
same artwork as PNGs for older Android versions and for store listings.
Geometry is in the 108x108 adaptive-icon viewport, matching the XML.

    python3 -m pip install pillow
    python3 tool/app_icon/generate.py
"""

import math
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
RES = ROOT / "android/app/src/main/res"

# Palette (keep in sync with ic_launcher_background.xml / foreground.xml).
BG_START = (0x3B, 0x16, 0x7A)  # top-left
BG_END = (0x0B, 0x16, 0x2E)  # bottom-right
TRACK = (255, 255, 255, 46)
RING = (0x4F, 0xC3, 0xF7, 255)
TILE = (255, 255, 255, 235)
TILE_ACCENT = (0x4F, 0xC3, 0xF7, 255)

# Geometry in viewport units (108).
CENTER = 54
RING_RADIUS = 24
RING_STROKE = 5.5
RING_SWEEP = 270  # degrees, clockwise from 12 o'clock
TILE_SIZE = 9.5
TILE_GAP = 3
TILE_RADIUS = 2.5

SS = 8  # supersampling factor


def _gradient(size: int) -> Image.Image:
    img = Image.new("RGB", (size, size))
    px = []
    span = 2 * (size - 1)
    for y in range(size):
        for x in range(size):
            t = (x + y) / span
            px.append(tuple(round(a + (b - a) * t) for a, b in zip(BG_START, BG_END)))
    img.putdata(px)
    return img


def render_viewport(px: int, with_background: bool = True) -> Image.Image:
    """Full 108-unit adaptive viewport rendered at px x px."""
    big = px * SS
    u = big / 108  # pixels per viewport unit

    if with_background:
        base = _gradient(big // 4).resize((big, big), Image.BICUBIC).convert("RGBA")
    else:
        base = Image.new("RGBA", (big, big), (0, 0, 0, 0))

    layer = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    c = CENTER * u
    r = RING_RADIUS * u
    w = RING_STROKE * u
    box = [c - r - w / 2, c - r - w / 2, c + r + w / 2, c + r + w / 2]

    # Track + progress arc (Pillow: 0° = 3 o'clock, clockwise).
    d.ellipse(box, outline=TRACK, width=round(w))
    d.arc(box, start=-90, end=-90 + RING_SWEEP, fill=RING, width=round(w))
    # Round caps at both ends of the arc.
    for deg in (-90, -90 + RING_SWEEP):
        a = math.radians(deg)
        x, y = c + r * math.cos(a), c + r * math.sin(a)
        d.ellipse([x - w / 2, y - w / 2, x + w / 2, y + w / 2], fill=RING)

    # 2x2 tool tiles.
    total = 2 * TILE_SIZE + TILE_GAP
    origin = CENTER - total / 2
    for row in range(2):
        for col in range(2):
            x0 = (origin + col * (TILE_SIZE + TILE_GAP)) * u
            y0 = (origin + row * (TILE_SIZE + TILE_GAP)) * u
            fill = TILE_ACCENT if (row, col) == (0, 1) else TILE
            d.rounded_rectangle(
                [x0, y0, x0 + TILE_SIZE * u, y0 + TILE_SIZE * u],
                radius=TILE_RADIUS * u,
                fill=fill,
            )

    base.alpha_composite(layer)
    return base.resize((px, px), Image.LANCZOS)


def legacy_icon(px: int, round_shape: bool) -> Image.Image:
    """Pre-Android-8 icon: the visible 72-unit center, masked to a shape."""
    full = render_viewport(round(px * 108 / 72))
    off = (full.width - px) // 2
    art = full.crop((off, off, off + px, off + px))

    mask = Image.new("L", (px * SS, px * SS), 0)
    md = ImageDraw.Draw(mask)
    inset = px * SS * 0.04
    rect = [inset, inset, px * SS - inset, px * SS - inset]
    if round_shape:
        md.ellipse(rect, fill=255)
    else:
        md.rounded_rectangle(rect, radius=px * SS * 0.22, fill=255)
    mask = mask.resize((px, px), Image.LANCZOS)

    out = Image.new("RGBA", (px, px), (0, 0, 0, 0))
    out.paste(art, (0, 0), mask)
    return out


def main() -> None:
    densities = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}
    for name, px in densities.items():
        folder = RES / f"mipmap-{name}"
        folder.mkdir(parents=True, exist_ok=True)
        legacy_icon(px, round_shape=False).save(folder / "ic_launcher.png")
        legacy_icon(px, round_shape=True).save(folder / "ic_launcher_round.png")

    out = ROOT / "assets/icon"
    out.mkdir(parents=True, exist_ok=True)
    # Store listing icon (Play Store wants 512x512, full square).
    full = render_viewport(768)
    off = (768 - 512) // 2
    full.crop((off, off, off + 512, off + 512)).save(out / "app_icon_512.png")
    legacy_icon(512, round_shape=False).save(out / "app_icon_preview.png")
    print("Icons written.")


if __name__ == "__main__":
    main()
