"""Draws the app's brand mark for the website (#289): the SVG logo and its
PNG fallbacks, from one definition so they cannot drift apart.

The mark is the logo at the top of the app's sidebar (`_Logo` in
lib/features/shell/sidebar.dart): a 40 x 40 square with corner radius 14
(`AppRadius.cardLarge`), a top-left -> bottom-right gradient from `accent`
(leaf) to `accent2` (sand), and Material's `auto_awesome_outlined` sparkle
at size 22 in `ink0`. The colours are the dark "study lamp" palette
(`AppPalette.dark` in lib/theme/tokens.dart) in both site themes: the mark
is a coloured tile and reads on the warm paper of the light theme as well.

Writes, under public/assets/:
- logo.svg              the mark, used in the header and as the favicon;
- favicon-32.png        32 x 32 fallback for browsers without SVG favicons;
- apple-touch-icon.png  180 x 180, full-bleed (iOS rounds the corners itself).

Standard library only (no Pillow): the sparkle is straight line segments, so
a small supersampled even-odd rasteriser is enough. Run from the repo root:

    python tooling/site/make_icons.py
"""

from __future__ import annotations

import struct
import zlib
from pathlib import Path

ACCENT = (0x7D, 0xC8, 0x9F)  # AppPalette.dark.accent  — leaf
ACCENT2 = (0xDC, 0xCF, 0x9A)  # AppPalette.dark.accent2 — sand
INK0 = (0x21, 0x1D, 0x18)  # AppPalette.dark.ink0

SIZE = 40  # the sidebar logo's box
RADIUS = 14  # AppRadius.cardLarge
GLYPH = 22  # Icon size in the sidebar

# Material Icons "auto_awesome" (outlined), on its 24-unit grid. Four closed
# polygons: the small star top right, the big star, the big star's hollow
# centre, and the small star bottom right. Filled with the even-odd rule.
SPARKLE_PATH = (
    "M19 9l1.25-2.75L23 5l-2.75-1.25L19 1l-1.25 2.75L15 5l2.75 1.25z"
    "m-7.5.5L9 4 6.5 9.5 1 12l5.5 2.5L9 20l2.5-5.5L17 12l-5.5-2.5z"
    "m-1.51 3.49L9 15.17l-.99-2.18L5.83 12l2.18-.99L9 8.83l.99 2.18"
    " 2.18.99-2.18.99z"
    "M19 15l-1.25 2.75L15 19l2.75 1.25L19 23l1.25-2.75L23 19l-2.75-1.25z"
)
SPARKLE = [
    [(19, 9), (20.25, 6.25), (23, 5), (20.25, 3.75), (19, 1), (17.75, 3.75), (15, 5), (17.75, 6.25)],
    [(11.5, 9.5), (9, 4), (6.5, 9.5), (1, 12), (6.5, 14.5), (9, 20), (11.5, 14.5), (17, 12)],
    [(9.99, 12.99), (9, 15.17), (8.01, 12.99), (5.83, 12), (8.01, 11.01), (9, 8.83), (9.99, 11.01), (12.17, 12)],
    [(19, 15), (17.75, 17.75), (15, 19), (17.75, 20.25), (19, 23), (20.25, 20.25), (23, 19), (20.25, 17.75)],
]

OUT = Path(__file__).resolve().parents[2] / "public" / "assets"


def hex_colour(rgb: tuple[int, int, int]) -> str:
    return "#%02X%02X%02X" % rgb


def svg() -> str:
    offset = (SIZE - GLYPH) / 2
    scale = GLYPH / 24
    return (
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 40 40" width="40" height="40">\n'
        "  <title>AI Tutor</title>\n"
        '  <defs>\n'
        '    <linearGradient id="mark" x1="0" y1="0" x2="1" y2="1">\n'
        f'      <stop offset="0" stop-color="{hex_colour(ACCENT)}"/>\n'
        f'      <stop offset="1" stop-color="{hex_colour(ACCENT2)}"/>\n'
        "    </linearGradient>\n"
        "  </defs>\n"
        f'  <rect width="{SIZE}" height="{SIZE}" rx="{RADIUS}" fill="url(#mark)"/>\n'
        f'  <path transform="translate({offset:g} {offset:g}) scale({scale:.6f})"'
        f' fill="{hex_colour(INK0)}" fill-rule="evenodd"\n'
        f'        d="{SPARKLE_PATH}"/>\n'
        "</svg>\n"
    )


def inside_sparkle(x: float, y: float) -> bool:
    """Even-odd point-in-polygon over all four sparkle polygons."""
    hit = False
    for poly in SPARKLE:
        j = len(poly) - 1
        for i in range(len(poly)):
            xi, yi = poly[i]
            xj, yj = poly[j]
            if (yi > y) != (yj > y) and x < (xj - xi) * (y - yi) / (yj - yi) + xi:
                hit = not hit
            j = i
    return hit


def inside_rounded(x: float, y: float, size: float, r: float) -> bool:
    if r <= 0:
        return 0 <= x <= size and 0 <= y <= size
    cx = min(max(x, r), size - r)
    cy = min(max(y, r), size - r)
    return (x - cx) ** 2 + (y - cy) ** 2 <= r * r


def raster(px: int, rounded: bool, samples: int = 4) -> bytes:
    """The mark at `px` x `px` pixels as RGBA rows (PNG filter byte included)."""
    unit = SIZE / px  # mark units per pixel
    radius = RADIUS if rounded else 0
    offset = (SIZE - GLYPH) / 2
    glyph_scale = 24 / GLYPH
    rows = bytearray()
    for py in range(px):
        rows.append(0)
        for pxx in range(px):
            cover = 0  # samples inside the tile
            ink = 0  # of those, samples on the sparkle
            for sy in range(samples):
                for sx in range(samples):
                    x = (pxx + (sx + 0.5) / samples) * unit
                    y = (py + (sy + 0.5) / samples) * unit
                    if not inside_rounded(x, y, SIZE, radius):
                        continue
                    cover += 1
                    gx = (x - offset) * glyph_scale
                    gy = (y - offset) * glyph_scale
                    if inside_sparkle(gx, gy):
                        ink += 1
            n = samples * samples
            if cover == 0:
                rows += b"\x00\x00\x00\x00"
                continue
            cx = (pxx + 0.5) * unit
            cy = (py + 0.5) * unit
            t = min(max((cx + cy) / (2 * SIZE), 0.0), 1.0)
            tile = [a + (b - a) * t for a, b in zip(ACCENT, ACCENT2)]
            f = ink / cover
            colour = [round(c * (1 - f) + i * f) for c, i in zip(tile, INK0)]
            rows += bytes(colour) + bytes([round(255 * cover / n)])
    return bytes(rows)


def png(px: int, data: bytes) -> bytes:
    def chunk(kind: bytes, body: bytes) -> bytes:
        crc = zlib.crc32(kind + body) & 0xFFFFFFFF
        return struct.pack(">I", len(body)) + kind + body + struct.pack(">I", crc)

    header = struct.pack(">IIBBBBB", px, px, 8, 6, 0, 0, 0)  # 8-bit RGBA
    return (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", header)
        + chunk(b"IDAT", zlib.compress(data, 9))
        + chunk(b"IEND", b"")
    )


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / "logo.svg").write_text(svg(), encoding="utf-8", newline="\n")
    (OUT / "favicon-32.png").write_bytes(png(32, raster(32, rounded=True)))
    (OUT / "apple-touch-icon.png").write_bytes(png(180, raster(180, rounded=False)))
    for name in ("logo.svg", "favicon-32.png", "apple-touch-icon.png"):
        print(OUT / name)


if __name__ == "__main__":
    main()
