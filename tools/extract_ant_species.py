#!/usr/bin/env python3
"""extract_ant_species.py — slice the 5 Animal-Crossing ant characters out of the
Floniks line-up sheet (build/floniks_src/ant_species_sheet.png) into five
transparent, square, centred tokens the queue/slots use.

The ants sit on a flat blue chroma background with clear vertical gaps, so we:
  1. soft-key the background by colour distance (feathered alpha, no hard matte),
  2. despill the blue edge fringe,
  3. segment the 5 subjects by empty-column runs, crop each to its bbox,
  4. centre on a transparent square, resize to 256.

Output: assets/textures/antkind_{choc,bread,sugar,berry,mint}.png
(order left->right matches palette species 1..5 = choc/bread/sugar/berry/mint).
"""
import os
from PIL import Image

SRC = "build/floniks_src/ant_species_sheet.png"
NAMES = ["antkind_choc", "antkind_bread", "antkind_sugar", "antkind_berry", "antkind_mint"]
OUT = 256

im = Image.open(SRC).convert("RGB")
W, H = im.size
px = im.load()

# background reference = average of the four corners
corners = [px[2, 2], px[W - 3, 2], px[2, H - 3], px[W - 3, H - 3]]
bg = tuple(sum(c[k] for c in corners) // 4 for k in range(3))
print("bg ref", bg)


def dist(a, b):
    return ((a[0] - b[0]) ** 2 + (a[1] - b[1]) ** 2 + (a[2] - b[2]) ** 2) ** 0.5


LO, HI = 55.0, 135.0  # alpha ramp on colour distance from bg
out = Image.new("RGBA", (W, H), (0, 0, 0, 0))
op = out.load()
colcount = [0] * W
for y in range(H):
    for x in range(W):
        r, g, b = px[x, y]
        d = dist((r, g, b), bg)
        a = int(max(0.0, min(1.0, (d - LO) / (HI - LO))) * 255)
        if a > 0:
            # despill: pull down a blue fringe that exceeds the warm channels
            mrg = max(r, g)
            if b > mrg:
                b = int(mrg + (b - mrg) * 0.25)
            op[x, y] = (r, g, b, a)
            if a > 40:
                colcount[x] += 1

# segment into runs of non-empty columns (>=1% of height of solid pixels)
thr = max(3, int(H * 0.010))
runs, s = [], None
for x in range(W):
    solid = colcount[x] >= thr
    if solid and s is None:
        s = x
    elif not solid and s is not None:
        if x - s > W * 0.03:
            runs.append((s, x))
        s = None
if s is not None:
    runs.append((s, W))
print("column runs:", len(runs), runs)
assert len(runs) == 5, f"expected 5 ant bands, got {len(runs)} — adjust thr"

os.makedirs("assets/textures", exist_ok=True)
for i, (x0, x1) in enumerate(runs):
    band = out.crop((max(0, x0 - 6), 0, min(W, x1 + 6), H))
    bbox = band.getbbox()
    ant = band.crop(bbox)
    w, h = ant.size
    side = int(max(w, h) * 1.14)  # a little breathing room
    canvas = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    canvas.paste(ant, ((side - w) // 2, (side - h) // 2), ant)
    canvas = canvas.resize((OUT, OUT), Image.LANCZOS)
    canvas.save(f"assets/textures/{NAMES[i]}.png")
    print("wrote", NAMES[i], "from bbox", bbox)
