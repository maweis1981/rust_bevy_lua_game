#!/usr/bin/env python3
"""High-quality supersampled sprites for the space shooter (and shared use).

Renders with 4x4 supersampling (premultiplied) for smooth anti-aliased edges and
gradient shading — a big step up from the flat pixel-art. Output: assets/textures.
Stdlib only (zlib/struct/math).
"""
import math
import os
import struct
import zlib

OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "textures")
OUT = os.environ.get("TEX_OUT", OUT)


def write_png(path, w, h, pixels):
    raw = bytearray()
    for y in range(h):
        raw.append(0)
        for x in range(w):
            r, g, b, a = pixels[y * w + x]
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
    """fn(fx,fy) -> (r,g,b,a) floats in 0..1 at continuous coords; supersampled."""
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


def clamp01(v):
    return 0.0 if v < 0 else (1.0 if v > 1 else v)


def in_poly(x, y, pts):
    inside = False
    j = len(pts) - 1
    for i in range(len(pts)):
        xi, yi = pts[i]; xj, yj = pts[j]
        if ((yi > y) != (yj > y)) and (x < (xj - xi) * (y - yi) / (yj - yi) + xi):
            inside = not inside
        j = i
    return inside


# --- Player ship: a sleek delta fighter, metallic blue with a cyan cockpit ----
SHIP = [
    (24, 1), (26, 16), (30, 24), (30, 30), (46, 40), (30, 38),
    (29, 46), (24, 42), (19, 46), (18, 38), (2, 40), (18, 30), (18, 24), (22, 16),
]


def ship(fx, fy):
    if not in_poly(fx, fy, SHIP):
        return (0, 0, 0, 0)
    cx = 24
    center = clamp01(1.0 - abs(fx - cx) / 22.0)      # bright fuselage stripe
    top = 0.7 + 0.35 * (1.0 - fy / 48.0)
    base = (0.34, 0.48, 0.66)
    lift = 0.55 + 0.7 * center
    r, g, b = base[0] * lift * top, base[1] * lift * top, base[2] * lift * top
    # cockpit glass
    if math.hypot(fx - cx, fy - 15) < 3.6:
        r, g, b = 0.35, 0.9, 1.0
    # engine glow at the tail
    eg = math.exp(-(((fx - cx) / 3.0) ** 2 + ((fy - 45) / 3.0) ** 2))
    r = clamp01(r + eg * 0.9); g = clamp01(g + eg * 0.7); b = clamp01(b + eg * 0.3)
    return (r, g, b, 1.0)


# --- Alien: a glowing green cephaloid with a bright core and tentacle lobes ----
def alien(fx, fy):
    cx = cy = 22.0
    dx, dy = fx - cx, fy - cy
    d = math.hypot(dx, dy)
    ang = math.atan2(dy, dx)
    R = 20.0
    lobe = R * (0.60 + 0.26 * math.cos(ang * 5) + 0.05 * math.cos(ang * 10))
    if d > lobe:
        return (0, 0, 0, 0)
    t = d / lobe
    body = 0.5 + 0.5 * (1.0 - t)
    r, g, b = 0.13 * body, 0.72 * body, 0.20 * body
    core = math.exp(-((d / (R * 0.34)) ** 2))         # yellow-green glow
    r = r + (0.88 - r) * core; g = g + (1.0 - g) * core; b = b + (0.35 - b) * core
    spec = math.exp(-((d / (R * 0.14)) ** 2)) * 0.7   # white-hot centre
    r = clamp01(r + spec); g = clamp01(g + spec); b = clamp01(b + spec * 0.7)
    for ex in (16.5, 27.5):                            # two dark eyes
        if math.hypot(fx - ex, fy - 20) < 1.9:
            r, g, b = 0.05, 0.15, 0.05
    return (r, g, b, 1.0)


# --- Shot: a soft glowing bolt (white core, cyan halo) ------------------------
def shot(fx, fy):
    d = abs(fx - 4.0)
    ty = 1.0
    if fy < 3:
        ty = fy / 3.0
    elif fy > 19:
        ty = (22 - fy) / 3.0
    ty = clamp01(ty)
    glow = math.exp(-((d / 3.2) ** 2))
    core = math.exp(-((d / 1.3) ** 2))
    r = 0.45 + 0.55 * core
    g = 0.9 + 0.1 * core
    b = 1.0
    return (r, g, b, glow * ty)


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    write_png(os.path.join(OUT, "ship.png"), 48, 48, render(48, 48, ship))
    write_png(os.path.join(OUT, "alien.png"), 44, 44, render(44, 44, alien))
    write_png(os.path.join(OUT, "shot.png"), 8, 22, render(8, 22, shot))
