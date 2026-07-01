#!/usr/bin/env python3
"""Generate the games' pixel-art sprites as small RGBA PNGs (no external deps —
just zlib/struct). Bevy loads them with nearest sampling, so they stay crisp
"pixel art" when scaled up. Output goes to assets/textures/.

Grayscale sprites (orb, paddle, brick) are meant to be tinted at runtime via
game.set_color; colored ones (food, snake head/body) render as-is.
"""
import math
import os
import struct
import zlib

OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "textures")
OUT = os.environ.get("TEX_OUT", OUT)


def write_png(path, w, h, pixels):
    """pixels: flat list of (r,g,b,a) bytes, row-major, top row first."""
    raw = bytearray()
    for y in range(h):
        raw.append(0)  # filter: none
        for x in range(w):
            raw += bytes(pixels[y * w + x])

    def chunk(typ, data):
        return (struct.pack(">I", len(data)) + typ + data +
                struct.pack(">I", zlib.crc32(typ + data) & 0xffffffff))

    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n")
        f.write(chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0)))
        f.write(chunk(b"IDAT", zlib.compress(bytes(raw), 9)))
        f.write(chunk(b"IEND", b""))
    print(f"wrote {path} ({w}x{h})")


def build(w, h, fn):
    return [fn(x, y) for y in range(h) for x in range(w)]


def clampb(v):
    return max(0, min(255, int(v)))


def rounded(x, y, w, h, radius):
    """True if (x,y) is inside a rounded rectangle covering the image."""
    cx = min(x, w - 1 - x)
    cy = min(y, h - 1 - y)
    if cx >= radius or cy >= radius:
        return True
    dx, dy = radius - cx, radius - cy
    return dx * dx + dy * dy <= radius * radius


# --- grayscale, tintable ------------------------------------------------------
def orb(x, y):
    cx, cy, rad = 15.5, 15.5, 15.0
    d = math.hypot(x - cx, y - cy) / rad
    if d > 1.0:
        return (0, 0, 0, 0)
    base = 235 - 150 * d                       # bright center, darker rim
    hl = max(0.0, 1.0 - math.hypot(x - 10, y - 10) / 8.0) * 70  # top-left highlight
    v = clampb(base + hl)
    return (v, v, v, 255)


def paddle(x, y):
    w, h = 24, 24
    if not rounded(x, y, w, h, 6):
        return (0, 0, 0, 0)
    edge = min(x, w - 1 - x, y, h - 1 - y)
    if edge == 0:
        return (150, 150, 150, 255)            # dark outline
    v = clampb(255 - 5 * abs(y - h / 2))       # soft vertical shade
    if x < 6:
        v = clampb(v + 25)                      # left highlight
    return (v, v, v, 255)


def brick(x, y):
    w, h = 32, 16
    if x == 0 or y == 0 or x == w - 1 or y == h - 1:
        return (0, 0, 0, 0)                     # 1px gap so bricks read separately
    if y <= 2:
        v = 245                                  # top highlight
    elif y >= h - 3:
        v = 150                                  # bottom shadow
    else:
        v = 205
    if x <= 2 or x >= w - 3:
        v -= 30
    return (clampb(v), clampb(v), clampb(v), 255)


# --- colored ------------------------------------------------------------------
def food(x, y):
    # a little apple
    cx, cy, rad = 11.5, 13.5, 9.0
    if x >= 12 and x <= 14 and y >= 1 and y <= 5:
        return (120, 75, 45, 255)              # stem
    if x >= 14 and x <= 19 and y >= 3 and y <= 7 and (x - 14) + (y - 3) <= 7:
        return (70, 185, 80, 255)              # leaf
    d = math.hypot(x - cx, y - cy) / rad
    if d <= 1.0:
        shade = 1.0 - 0.35 * d
        hl = max(0.0, 1.0 - math.hypot(x - 8, y - 10) / 5.0) * 60
        return (clampb(225 * shade + hl), clampb(55 * shade + hl * 0.6), clampb(55 * shade), 255)
    return (0, 0, 0, 0)


def _snake_cell(x, y, base, outline, eyes):
    w, h = 32, 32
    if not rounded(x, y, w, h, 8):
        return (0, 0, 0, 0)
    edge = min(x, w - 1 - x, y, h - 1 - y)
    if edge <= 1:
        return outline + (255,)
    if eyes:
        for ex in (10, 21):
            if math.hypot(x - ex, y - 12) <= 3.2:
                return (245, 245, 245, 255)     # eye white
            if math.hypot(x - ex, y - 12) <= 1.4:
                return (20, 20, 20, 255)
    # subtle inner highlight
    hl = max(0.0, 1.0 - math.hypot(x - 12, y - 12) / 16.0) * 25
    return (clampb(base[0] + hl), clampb(base[1] + hl), clampb(base[2] + hl), 255)


def snakehead(x, y):
    return _snake_cell(x, y, (80, 205, 95), (35, 120, 55), eyes=True)


def snakebody(x, y):
    return _snake_cell(x, y, (65, 175, 82), (32, 110, 50), eyes=False)


SPRITES = {
    "orb": (32, 32, orb),
    "paddle": (24, 24, paddle),
    "brick": (32, 16, brick),
    "food": (24, 24, food),
    "snakehead": (32, 32, snakehead),
    "snakebody": (32, 32, snakebody),
}

if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    for name, (w, h, fn) in SPRITES.items():
        write_png(os.path.join(OUT, name + ".png"), w, h, build(w, h, fn))
