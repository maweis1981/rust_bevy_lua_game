#!/usr/bin/env python3
"""Cute placeholder sprites for the cozy-world (Animal-Crossing-like) game.

Supersampled, soft pastel shapes — recognizable stand-ins until nicer art (AI or
hand-drawn) replaces the same filenames in assets/textures/. Stdlib only.
"""
import math
import os
import struct
import zlib

OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "textures")
OUT = os.environ.get("TEX_OUT", OUT)


def write_png(path, w, h, px):
    raw = bytearray()
    for y in range(h):
        raw.append(0)
        for x in range(w):
            r, g, b, a = px[y * w + x]
            raw += bytes((r, g, b, a))

    def chunk(t, d):
        return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xffffffff)

    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n")
        f.write(chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0)))
        f.write(chunk(b"IDAT", zlib.compress(bytes(raw), 9)))
        f.write(chunk(b"IEND", b""))
    print(f"wrote {path} ({w}x{h})")


def render(w, h, fn, ss=4):
    out = []
    for y in range(h):
        for x in range(w):
            sr = sg = sb = sa = 0.0
            for sy in range(ss):
                for sx in range(ss):
                    r, g, b, a = fn(x + (sx + 0.5) / ss, y + (sy + 0.5) / ss)
                    sr += r * a; sg += g * a; sb += b * a; sa += a
            n = ss * ss
            a = sa / n
            if sa > 1e-6:
                out.append((int(min(1, sr / sa) * 255), int(min(1, sg / sa) * 255),
                            int(min(1, sb / sa) * 255), int(min(1, a) * 255)))
            else:
                out.append((0, 0, 0, 0))
    return out


def disc(px, py, cx, cy, r):
    return (px - cx) ** 2 + (py - cy) ** 2 <= r * r


def over(a, b):
    """Alpha-composite b over a (both r,g,b,a in 0..1)."""
    oa = b[3] + a[3] * (1 - b[3])
    if oa < 1e-6:
        return (0, 0, 0, 0)
    return tuple(((b[i] * b[3] + a[i] * a[3] * (1 - b[3])) / oa) for i in range(3)) + (oa,)


# --- villager: a round pastel critter with a big cute face --------------------
def villager(fx, fy):
    col = (0, 0, 0, 0)
    # ears
    for ex in (15, 33):
        if disc(fx, fy, ex, 12, 6):
            col = over(col, (0.75, 0.82, 0.95, 1))
    # body/head (one round blob)
    if disc(fx, fy, 24, 27, 18):
        d = math.hypot(fx - 20, fy - 22) / 20
        v = 1.0 - 0.25 * d
        col = over(col, (0.80 * v, 0.87 * v, 0.98 * v, 1))
    if col[3] < 0.5:
        return col
    # cheeks
    for cx in (15, 33):
        if disc(fx, fy, cx, 31, 3.2):
            col = over(col, (0.98, 0.62, 0.66, 0.85))
    # eyes
    for ex in (18, 30):
        if disc(fx, fy, ex, 25, 3.4):
            col = over(col, (1, 1, 1, 1))
        if disc(fx, fy, ex + 0.5, 25.5, 1.7):
            col = over(col, (0.15, 0.13, 0.18, 1))
    # smile
    if 21 <= fx <= 27 and disc(fx, fy, 24, 27, 5) and fy > 29 and not disc(fx, fy, 24, 27, 3.5):
        col = over(col, (0.5, 0.3, 0.32, 1))
    return col


# --- tree: brown trunk + fluffy green canopy + a couple of fruits -------------
def tree(fx, fy):
    col = (0, 0, 0, 0)
    # trunk
    if 31 <= fx <= 41 and 58 <= fy <= 90:
        t = (fx - 31) / 10
        v = 0.55 + 0.25 * (1 - abs(t - 0.4) * 2)
        col = over(col, (0.52 * v + 0.1, 0.36 * v + 0.06, 0.20 * v, 1))
    # canopy: several overlapping blobs
    blobs = [(36, 30, 26), (20, 38, 16), (52, 38, 16), (26, 20, 15), (46, 20, 15)]
    inside = False
    for (cx, cy, r) in blobs:
        if disc(fx, fy, cx, cy, r):
            inside = True; break
    if inside:
        d = math.hypot(fx - 28, fy - 22) / 34
        v = 1.05 - 0.4 * d
        col = over(col, (0.28 * v, 0.68 * v, 0.34 * v, 1))
        # fruits
        for (cx, cy) in ((24, 34), (48, 30), (36, 44)):
            if disc(fx, fy, cx, cy, 4):
                col = over(col, (0.95, 0.34, 0.34, 1))
            if disc(fx, fy, cx - 1, cy - 1, 1.4):
                col = over(col, (1, 0.7, 0.7, 0.9))
    return col


# --- rock: soft grey boulder with a top highlight -----------------------------
def rock(fx, fy):
    if not (disc(fx, fy, 24, 24, 20) and fy < 36):
        # flat-ish bottom
        if not (14 <= fx <= 34 and 30 <= fy <= 36):
            return (0, 0, 0, 0)
    d = math.hypot(fx - 18, fy - 16) / 26
    v = 0.72 - 0.32 * d
    return (0.55 + v * 0.35, 0.57 + v * 0.35, 0.62 + v * 0.33, 1)


# --- flower: five petals around a bright center -------------------------------
def flower(fx, fy):
    col = (0, 0, 0, 0)
    for k in range(5):
        a = k * (2 * math.pi / 5) - math.pi / 2
        cx, cy = 16 + math.cos(a) * 8, 16 + math.sin(a) * 8
        if disc(fx, fy, cx, cy, 5.5):
            col = over(col, (0.98, 0.55, 0.72, 1))
    if disc(fx, fy, 16, 16, 4.5):
        col = over(col, (1.0, 0.85, 0.35, 1))
    return col


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    write_png(os.path.join(OUT, "villager.png"), 48, 44, render(48, 44, villager))
    write_png(os.path.join(OUT, "tree.png"), 72, 92, render(72, 92, tree))
    write_png(os.path.join(OUT, "rock.png"), 48, 38, render(48, 38, rock))
    write_png(os.path.join(OUT, "flower.png"), 32, 32, render(32, 32, flower))
