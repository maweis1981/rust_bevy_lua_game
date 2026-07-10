#!/usr/bin/env python3
"""Bake real art assets for the TikTok Mini Arcade collection (games/assets/).

Stdlib + numpy only (no PIL). Supersampled, anti-aliased. Outputs:
  fruits.png  — 11-tier Suika fruit sprite sheet (glossy shaded spheres + faces)
  bg.png      — shared deep-space nebula background (gradient + glows + stars + vignette)

The JS games load these via platform.getImage(name) and fall back to procedural
drawing when an image is absent (headless/tests), so art is a pure enhancement.
"""
import os
import struct
import zlib
import numpy as np

OUT = os.path.join(os.path.dirname(__file__), "..", "miniprogram", "games", "assets")
OUT = os.environ.get("ART_OUT", OUT)
os.makedirs(OUT, exist_ok=True)

# Suika per-tier fill colors (must match games/suika/config.js COLORS).
FRUIT_HEX = [
    "#e6394a", "#ff7b29", "#f5b301", "#c3e330", "#ffa64d", "#ff5d73",
    "#b6e14b", "#f0a6c8", "#8f6df0", "#69d07a", "#37b24d",
]


def write_png(path, arr):
    """arr: HxWx4 uint8 (RGBA). Writes a PNG (stdlib zlib/struct)."""
    h, w, _ = arr.shape
    raw = bytearray()
    for y in range(h):
        raw.append(0)  # filter: none
        raw += arr[y].tobytes()

    def chunk(t, d):
        return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xffffffff)

    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n")
        f.write(chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0)))
        f.write(chunk(b"IDAT", zlib.compress(bytes(raw), 9)))
        f.write(chunk(b"IEND", b""))
    print("wrote %s (%dx%d)" % (path, w, h))


def hex_rgb(h):
    h = h.lstrip("#")
    return np.array([int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16)], float) / 255.0


def smoothstep(a, b, x):
    t = np.clip((x - a) / (b - a + 1e-9), 0, 1)
    return t * t * (3 - 2 * t)


def downsample(rgba, ss):
    """average-pool an (H*ss)x(W*ss)x4 float array down by ss -> HxWx4."""
    H, W, C = rgba.shape
    return rgba.reshape(H // ss, ss, W // ss, ss, C).mean(axis=(1, 3))


def bake_fruit(size, hexcol, ss=3):
    """A glossy shaded sphere with a cute face, on transparent bg. size = final px."""
    S = size * ss
    yy, xx = np.mgrid[0:S, 0:S].astype(float)
    cx = cy = (S - 1) / 2.0
    R = S * 0.45
    dx = (xx - cx) / R
    dy = (yy - cy) / R
    d = np.sqrt(dx * dx + dy * dy)

    nz = np.sqrt(np.clip(1 - dx * dx - dy * dy, 0, 1))
    # Cosmic Confection lighting: one warm key (top-left), one cool rim (lower-right).
    key = np.array([-0.45, -0.6, 0.66]); key = key / np.linalg.norm(key)
    ndotl = np.clip(dx * key[0] + dy * key[1] + nz * key[2], 0, 1)

    base = hex_rgb(hexcol)
    warm = np.array([1.0, 0.96, 0.86])                # key light tint
    cool = np.array([0.62, 0.80, 1.0])                # rim light tint
    diff = 0.30 + 0.82 * ndotl
    col = base[None, None, :] * diff[:, :, None] * warm[None, None, :]

    # subsurface warmth: a soft warm glow bleeding through the terminator band
    term = smoothstep(0.0, 0.35, ndotl) * (1 - smoothstep(0.35, 0.85, ndotl))
    col = col + (base * np.array([1.15, 0.8, 0.7]))[None, None, :] * (0.22 * term)[:, :, None]

    # cool fresnel rim on the lower-right edge (opposite the key) — separates from bg
    fres = np.clip(1 - nz, 0, 1) ** 2.2
    rimside = np.clip(dx * 0.6 + dy * 0.6, 0, 1)
    col = col + cool[None, None, :] * (fres * rimside * 0.55)[:, :, None]

    col *= (1 - 0.30 * smoothstep(0.80, 1.0, d))[:, :, None]   # darken the far edge

    spec = np.clip(ndotl, 0, 1) ** 42                 # tight hot specular
    hl = np.exp(-(((dx + 0.34) / 0.44) ** 2 + ((dy + 0.44) / 0.30) ** 2)) * 0.80  # broad soft gloss
    white = np.clip(spec * 1.0 + hl, 0, 1)
    col = col + (1 - col) * white[:, :, None]         # screen toward white

    # --- cute face: two eyes + a smile (subtle dark, so it reads on any hue) ---
    def disc(px, py, rr):
        return np.sqrt((xx - (cx + px * R)) ** 2 + (yy - (cy + py * R)) ** 2) - rr * R
    eye_l = disc(-0.26, -0.02, 0.115)
    eye_r = disc(0.26, -0.02, 0.115)
    for eye, hx in ((eye_l, -0.26), (eye_r, 0.26)):
        em = smoothstep(1.0, -1.0, eye)               # eye white
        col = col * (1 - 0.85 * em[:, :, None]) + np.array([1, 1, 1])[None, None, :] * (0.85 * em)[:, :, None]
        pup = np.sqrt((xx - (cx + (hx + 0.02) * R)) ** 2 + (yy - (cy + 0.02 * R)) ** 2) - 0.055 * R
        pm = smoothstep(1.0, -1.0, pup)
        col = col * (1 - 0.9 * pm[:, :, None])         # dark pupil
    # smile: a thin arc in the lower face
    my = cy + 0.16 * R
    rm = 0.22 * R
    arc = np.abs(np.sqrt((xx - cx) ** 2 + (yy - my) ** 2) - rm)
    smile = smoothstep(0.05 * R, 0.0, arc) * (yy > my)
    col = col * (1 - 0.55 * smile[:, :, None])

    edge = smoothstep(0.02, -0.03, d - 1.0)            # dark outline just inside rim
    col *= (1 - 0.35 * smoothstep(0.90, 1.0, d))[:, :, None]

    alpha = smoothstep(1.01, 0.97, d)                  # AA circular alpha
    col = np.clip(col, 0, 1)
    rgba = np.dstack([col, alpha])
    rgba = downsample(rgba, ss)
    return (np.clip(rgba, 0, 1) * 255).astype(np.uint8)


def bake_fruit_sheet(cell=132):
    n = len(FRUIT_HEX)
    sheet = np.zeros((cell, cell * n, 4), np.uint8)
    for i, hx in enumerate(FRUIT_HEX):
        sheet[:, i * cell:(i + 1) * cell, :] = bake_fruit(cell, hx)
    write_png(os.path.join(OUT, "fruits.png"), sheet)


def bake_bg(w=360, h=780):
    # Cosmic Confection stage: cool indigo void, one hero bloom, layered depth,
    # parallax stardust with halos, fine grain so gradients never band.
    yy, xx = np.mgrid[0:h, 0:w].astype(float)
    v = yy / h
    top = hex_rgb("#090c1c"); bot = hex_rgb("#141a34")
    col = top[None, None, :] * (1 - v[:, :, None]) + bot[None, None, :] * v[:, :, None]

    def glow(px, py, rad, tint, amt):
        r = np.sqrt((xx - px * w) ** 2 + (yy - py * h) ** 2) / (rad * w)
        return (np.exp(-r * r) * amt)[:, :, None] * tint[None, None, :]

    # depth layers: far cool wash, mid violet, and ONE warm-cool hero bloom low-centre
    col = col + glow(0.20, 0.26, 0.62, hex_rgb("#2a5cff"), 0.20)
    col = col + glow(0.84, 0.60, 0.66, hex_rgb("#7d34e6"), 0.20)
    col = col + glow(0.50, 0.86, 0.85, hex_rgb("#12a7c8"), 0.16)   # hero bloom
    col = col + glow(0.50, 0.86, 0.35, hex_rgb("#eaf3ff"), 0.06)   # hot core of the bloom

    # parallax stardust: three depth classes (near = larger/brighter, with halos)
    rng = np.random.RandomState(7)
    def star(sx, sy, b, halo):
        if 0 <= sx < w and 0 <= sy < h:
            col[sy, sx, :3] = np.clip(col[sy, sx, :3] + b, 0, 1)
        if halo:
            for ddx, ddy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                x2, y2 = sx + ddx, sy + ddy
                if 0 <= x2 < w and 0 <= y2 < h:
                    col[y2, x2, :3] = np.clip(col[y2, x2, :3] + b * 0.45, 0, 1)
    for _ in range(180):                      # far: faint dust
        star(rng.randint(0, w), rng.randint(0, h), rng.uniform(0.10, 0.35), False)
    for _ in range(60):                       # mid
        star(rng.randint(0, w), rng.randint(0, h), rng.uniform(0.4, 0.7), False)
    for _ in range(22):                       # near: bright with halo
        star(rng.randint(0, w), rng.randint(0, h), rng.uniform(0.75, 1.0), True)

    # fine grain (dither) to kill banding in the smooth gradients
    grain = (rng.rand(h, w) - 0.5) * 0.012
    col = col + grain[:, :, None]

    # vignette focuses the eye
    r = np.sqrt(((xx - w / 2) / (w / 2)) ** 2 + ((yy - h / 2) / (h / 2)) ** 2)
    col *= (1 - 0.38 * smoothstep(0.65, 1.28, r))[:, :, None]

    rgba = np.dstack([np.clip(col, 0, 1), np.ones((h, w))])
    write_png(os.path.join(OUT, "bg.png"), (rgba * 255).astype(np.uint8))


if __name__ == "__main__":
    bake_fruit_sheet()
    bake_bg()
    print("done ->", OUT)
