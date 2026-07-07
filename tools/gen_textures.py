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


def meteor(x, y):
    """Lumpy cratered rock, grayscale (tinted per foe kind at runtime)."""
    cx, cy = 15.5, 15.5
    dx, dy = x - cx, y - cy
    r = math.hypot(dx, dy)
    ang = math.atan2(dy, dx)
    edge = 13.8 + 1.6 * math.sin(ang * 3 + 1.3) + 1.1 * math.sin(ang * 5 - 0.7)
    if r > edge:
        return (0, 0, 0, 0)
    d = r / edge
    lum = 200 - 90 * d * d
    lum += 45 * max(0.0, -(dx * -0.6 + dy * -0.6) / max(edge, 1))  # upper-left light
    for (px_, py_, pr) in ((10, 12, 3.4), (21, 9, 2.5), (18, 21, 3.9), (8, 22, 2.3)):
        dd = math.hypot(x - px_, y - py_)
        if dd < pr:
            lum -= 60 * (1 - dd / pr)
        elif dd < pr + 1.3:
            lum += 20
    v = clampb(lum)
    return (v, v, v, 255)


def rockball(x, y):
    """The player: a shaded rocky sphere — rounder than a meteor, with proper
    lambert shading + a specular hotspot so it reads as a lit 3D body. Grayscale
    (tinted white->icy by the timescale at runtime)."""
    cx, cy = 23.5, 23.5
    dx, dy = x - cx, y - cy
    r = math.hypot(dx, dy)
    ang = math.atan2(dy, dx)
    edge = 21.5 + 0.9 * math.sin(ang * 5 + 0.8) + 0.5 * math.sin(ang * 8)
    if r > edge:
        return (0, 0, 0, 0)
    nx, ny = dx / edge, dy / edge
    nz = math.sqrt(max(0.0, 1 - nx * nx - ny * ny))
    lum = 92 + 138 * max(0.0, -0.5 * nx - 0.5 * ny + 0.71 * nz)
    spec = max(0.0, -0.55 * nx - 0.55 * ny + 0.63 * nz)
    lum += 65 * (spec ** 8)
    for (px_, py_, pr) in ((15, 18, 4.0), (30, 14, 3.0), (26, 31, 4.5), (12, 30, 2.6)):
        dd = math.hypot(x - px_, y - py_)
        if dd < pr:
            lum -= 42 * (1 - dd / pr)
        elif dd < pr + 1.5:
            lum += 14
    v = clampb(lum)
    return (v, v, v, 255)


def starfield(x, y):
    """A 256x256 deep-space tile: dark blue-black base, a faint two-tone nebula
    from layered value noise, and sparse stars of varied brightness. Tiles
    seamlessly enough for a far backdrop. Deterministic (hashed), no deps."""
    def h2(ix, iy, s):
        n = (ix * 374761393 + iy * 668265263 + s * 2147483647) & 0xFFFFFFFF
        n = (n ^ (n >> 13)) * 1274126177 & 0xFFFFFFFF
        return ((n ^ (n >> 16)) & 0xFFFF) / 65535.0
    def vnoise(fx, fy, s):
        ix, iy = int(math.floor(fx)), int(math.floor(fy))
        tx, ty = fx - ix, fy - iy
        a = h2(ix, iy, s); b = h2(ix + 1, iy, s)
        c = h2(ix, iy + 1, s); d = h2(ix + 1, iy + 1, s)
        ux = tx * tx * (3 - 2 * tx); uy = ty * ty * (3 - 2 * ty)
        return (a * (1 - ux) + b * ux) * (1 - uy) + (c * (1 - ux) + d * ux) * uy
    # base + nebula (two coloured octaves, subtle)
    neb = 0.0
    for oc, sd in ((6.0, 11), (13.0, 29)):
        neb += vnoise(x / 256.0 * oc, y / 256.0 * oc, sd) / (oc / 6.0)
    neb = max(0.0, neb - 0.7)
    r = 6 + 42 * neb
    g = 8 + 20 * neb
    b = 18 + 60 * neb
    # stars: sparse bright points with soft 1px glow
    sv = h2(x, y, 101)
    if sv > 0.9965:
        t = (sv - 0.9965) / 0.0035
        c = 190 + 65 * t
        return (clampb(c), clampb(c), clampb(c), 255)
    if sv > 0.986:                       # dim dust stars
        c = 70 + 90 * (sv - 0.986) / 0.010
        return (clampb(r + c), clampb(g + c), clampb(b + c), 255)
    return (clampb(r), clampb(g), clampb(b), 255)


def _disc(x, y, cx, cy, r, edge=1.2):
    d = math.hypot(x - cx, y - cy)
    if d <= r - edge: return 1.0
    if d >= r + edge: return 0.0
    return (r + edge - d) / (2 * edge)

def _ring(x, y, cx, cy, r, w):
    d = math.hypot(x - cx, y - cy)
    return max(0.0, 1.0 - abs(d - r) / w)

def icon_base(x, y):
    """A tiny space-station glyph: a ringed hub with a dome — the "return to
    base" button. White on transparent, tinted cyan at runtime."""
    cx, cy = 16, 17
    a = 0.0
    a = max(a, _ring(x, y, cx, cy, 9.5, 1.6) * 0.9)     # orbit ring
    a = max(a, _disc(x, y, cx, cy, 5.2))                # hub
    # two antenna dots
    a = max(a, _disc(x, y, cx, 4, 1.6))
    if abs((x - cx)) < 1.2 and 4 < y < 12: a = max(a, 0.9)  # mast
    v = clampb(255 * a)
    return (255, 255, 255, v)

def icon_mass(x, y):
    """Hexagon outline = MASS."""
    cx, cy = 16, 16
    dx, dy = x - cx, y - cy
    ang = math.atan2(dy, dx)
    r = math.hypot(dx, dy)
    # hexagon radius as function of angle
    import math as _m
    k = _m.pi / 3
    hr = 11.0 / max(0.5, math.cos(((ang % k) - k / 2)))
    a = max(0.0, 1.0 - abs(r - min(hr, 12.0)) / 1.8)
    v = clampb(255 * a)
    return (255, 255, 255, v)

def icon_time(x, y):
    """Clock/orbit = TIME: a ring with a hand."""
    cx, cy = 16, 16
    a = _ring(x, y, cx, cy, 10.0, 1.5) * 0.9
    # hand pointing up-right
    hx, hy = x - cx, y - cy
    if hx >= -1 and hy <= 1:
        proj = abs(hx * 0.7 - hy * 0.7)
        if proj < 1.3 and math.hypot(hx, hy) < 8: a = max(a, 0.9)
    a = max(a, _disc(x, y, cx, cy, 1.8))
    return (255, 255, 255, clampb(255 * a))

def icon_star(x, y):
    """Four-point star = EATEN/score."""
    cx, cy = 16, 16
    dx, dy = abs(x - cx), abs(y - cy)
    spike = max(0.0, 1.0 - (dx + dy) / 12.0)
    spike = max(spike, max(0.0, 1.0 - (dx * 3 + dy) / 13.0))
    spike = max(spike, max(0.0, 1.0 - (dx + dy * 3) / 13.0))
    return (255, 255, 255, clampb(255 * (spike ** 1.4)))


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


def _blob(x, y, base, outline, eyes=True, w=24, h=24, ex=(7, 16), ey=9):
    if not rounded(x, y, w, h, 6):
        return (0, 0, 0, 0)
    if min(x, w - 1 - x, y, h - 1 - y) == 0:
        return outline + (255,)
    if eyes:
        for cx in ex:
            if math.hypot(x - cx, y - ey) <= 2.6:
                return (245, 245, 245, 255)
            if math.hypot(x - cx, y - ey) <= 1.2:
                return (20, 20, 20, 255)
    hl = max(0.0, 1.0 - math.hypot(x - 9, y - 8) / 14.0) * 30
    return (clampb(base[0] + hl), clampb(base[1] + hl), clampb(base[2] + hl), 255)


def hero(x, y):
    return _blob(x, y, (70, 150, 240), (30, 80, 160))       # blue adventurer


def enemy(x, y):
    return _blob(x, y, (215, 70, 90), (130, 30, 45))        # red slime


def gem(x, y):
    w = h = 16
    if abs(x - 7.5) / 7.5 + abs(y - 7.5) / 7.5 <= 1.0:      # diamond
        d = abs(x - 7.5) / 7.5 + abs(y - 7.5) / 7.5
        v = 1.0 - 0.4 * d
        return (clampb(90 * v), clampb(235 * v), clampb(220 * v), 255)
    return (0, 0, 0, 0)


def tile(x, y):
    # A clean white rounded tile with a soft top highlight — tinted at runtime
    # (e.g. the 2048 palette). Rounded corners via a generous radius.
    w = h = 40
    if not rounded(x, y, w, h, 9):
        return (0, 0, 0, 0)
    v = 255 - int(0.6 * y)                                  # subtle top->bottom shade
    return (clampb(v), clampb(v), clampb(v), 255)


SPRITES = {
    "orb": (32, 32, orb),
    "meteor": (32, 32, meteor),
    "rockball": (48, 48, rockball),
    "starfield": (256, 256, starfield),
    "icon_base": (32, 32, icon_base),
    "icon_mass": (32, 32, icon_mass),
    "icon_time": (32, 32, icon_time),
    "icon_star": (32, 32, icon_star),
    "paddle": (24, 24, paddle),
    "brick": (32, 16, brick),
    "food": (24, 24, food),
    "snakehead": (32, 32, snakehead),
    "snakebody": (32, 32, snakebody),
    "hero": (24, 24, hero),
    "enemy": (24, 24, enemy),
    "gem": (16, 16, gem),
    "tile": (40, 40, tile),
}

if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    for name, (w, h, fn) in SPRITES.items():
        write_png(os.path.join(OUT, name + ".png"), w, h, build(w, h, fn))
