#!/usr/bin/env python3
"""gen_beadpop_assets.py — premium, UNIFIED art kit for the Bead Pop game.

One glossy style: rounded 3D beads, faceted gems, a rich gradient stage. All the
tintable pieces are luminance art (bright highlight -> dark edge) so game.set_color
multiplies to any hue and keeps the gloss. Output: assets/textures/bp_*.png
"""
import math
from PIL import Image, ImageDraw, ImageFilter

T = "assets/textures"


def save(im, name):
    im.save(f"{T}/{name}.png"); print("wrote", name, im.size)


def radial(size, cx, cy, r, inner, outer):
    """A radial luminance disc: `inner` at the (cx,cy) hotspot -> `outer` at r."""
    im = Image.new("L", (size, size), 0)
    px = im.load()
    for y in range(size):
        for x in range(size):
            d = math.hypot(x - cx, y - cy) / r
            if d <= 1.0:
                px[x, y] = int(max(0, min(255, outer + (inner - outer) * (1 - d) ** 1.2)))
    return im


# --- glossy bead: tintable sphere with an offset highlight + soft rim ---
def bead():
    N = 128
    im = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    body = radial(N, N * 0.42, N * 0.40, N * 0.52, 255, 150)   # bright top-left -> mid
    # circular alpha mask
    mask = Image.new("L", (N, N), 0)
    ImageDraw.Draw(mask).ellipse([6, 6, N - 7, N - 7], fill=255)
    rgb = Image.merge("RGB", (body, body, body))
    im = Image.merge("RGBA", (*rgb.split(), mask))
    # crisp specular glint (stays bright)
    g = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    gd = ImageDraw.Draw(g)
    gd.ellipse([N * 0.30, N * 0.22, N * 0.46, N * 0.40], fill=(255, 255, 255, 220))
    g = g.filter(ImageFilter.GaussianBlur(2))
    im = Image.alpha_composite(im, g)
    # dark contact rim for depth
    rim = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    ImageDraw.Draw(rim).ellipse([6, 6, N - 7, N - 7], outline=(0, 0, 0, 90), width=4)
    im = Image.alpha_composite(im, rim)
    r, gg, b, a = im.split()
    a = Image.composite(a, Image.new("L", (N, N), 0), mask)
    save(Image.merge("RGBA", (r, gg, b, a)), "bp_bead")


# --- empty socket: a subtle recessed ring (untinted, sits under beads) ---
def socket():
    N = 128
    im = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.ellipse([12, 12, N - 13, N - 13], fill=(255, 255, 255, 40))
    d.ellipse([12, 12, N - 13, N - 13], outline=(255, 255, 255, 70), width=4)
    save(im, "bp_socket")


# --- faceted gem: a brilliant-cut diamond, tintable, bright top facets ---
def gem():
    N = 128
    im = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    cx = N / 2
    top, tl, tr = 18, 24, N - 24
    mid = 52
    bot = N - 16
    # crown (table + top facets) brighter, pavilion (point) darker
    facets = [
        ([(tl, top), (cx, top - 2), (cx, mid), (tl, mid)], 230),   # top-left table
        ([(cx, top - 2), (tr, top), (tr, mid), (cx, mid)], 255),   # top-right table (glint)
        ([(tl, mid), (cx, mid), (cx, bot)], 175),                  # lower-left pavilion
        ([(cx, mid), (tr, mid), (cx, bot)], 120),                  # lower-right pavilion (dark)
        ([(tl, top), (tl, mid), (14, mid)], 200),                  # left shoulder
        ([(tr, top), (tr, mid), (N - 14, mid)], 150),              # right shoulder
    ]
    for poly, lum in facets:
        d.polygon(poly, fill=(lum, lum, lum, 255))
    # outline for crisp facet read
    d.polygon([(14, mid), (tl, top), (tr, top), (N - 14, mid), (cx, bot)],
              outline=(255, 255, 255, 200), width=3)
    d.line([(tl, mid), (tr, mid)], fill=(255, 255, 255, 160), width=2)
    d.line([(cx, top - 2), (cx, bot)], fill=(0, 0, 0, 60), width=2)
    save(im, "bp_gem")


# --- rich gradient stage background (deep indigo -> violet, soft top glow) ---
def bg():
    W, H = 768, 1152
    top = (36, 30, 74); bottom = (74, 48, 116)
    im = Image.new("RGB", (W, H))
    px = im.load()
    for y in range(H):
        t = y / (H - 1)
        px_row = tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3))
        for x in range(W):
            px[x, y] = px_row
    # soft radial glow near the top-centre (stage light)
    glow = Image.new("L", (W, H), 0)
    gp = glow.load()
    gcx, gcy, gr = W * 0.5, H * 0.28, W * 0.7
    for y in range(0, int(H * 0.7), 2):
        for x in range(0, W, 2):
            d = math.hypot(x - gcx, y - gcy) / gr
            if d < 1:
                v = int(60 * (1 - d) ** 2)
                gp[x, y] = v; gp[min(W-1,x+1), y] = v
                gp[x, min(H-1,y+1)] = v; gp[min(W-1,x+1), min(H-1,y+1)] = v
    glow = glow.filter(ImageFilter.GaussianBlur(24))
    im = Image.composite(Image.new("RGB", (W, H), (150, 130, 210)), im, glow)
    save(im.convert("RGBA"), "bp_bg")


# --- flat rounded panel (tray / progress capsule), tintable ---
def panel():
    N = 256
    im = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    ImageDraw.Draw(im).rounded_rectangle([4, 4, N - 5, N - 5], 40, fill=(255, 255, 255, 255),
                                         outline=(0, 0, 0, 40), width=4)
    save(im, "bp_panel")


if __name__ == "__main__":
    bead(); socket(); gem(); bg(); panel()
    print("bead pop art kit done")
