#!/usr/bin/env python3
"""make_ac_art.py — process the Animal-Crossing art batch for Ant Art.

Sources (build/floniks_src/): ac_food_cubes.png, ac_bar_badge.png, ac_tray.png
Outputs (assets/textures/):
  cell_<choc|bread|sugar|berry|mint>_<1..4>.png  soft AC food-block mosaic tiles
  bar_wood.png    honey-wood status plank (9-slice)
  badge_wood.png  honey-wood round medallion
  tray_wood.png   honey-wood flat tray frame (9-slice)   [if ac_tray.png present]

Prints suggested 9-slice border px for bar/tray so the Lua T.panel calls match.
"""
import os
from PIL import Image, ImageEnhance

SRC = "build/floniks_src"
os.makedirs("assets/textures", exist_ok=True)


def key(im, lo, hi, despill=True):
    """Feathered chroma-key of a flat pure-blue background -> RGBA."""
    im = im.convert("RGB")
    W, H = im.size
    px = im.load()
    bg = px[3, 3]
    out = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    op = out.load()
    for y in range(H):
        for x in range(W):
            r, g, b = px[x, y]
            d = ((r - bg[0]) ** 2 + (g - bg[1]) ** 2 + (b - bg[2]) ** 2) ** 0.5
            a = int(max(0.0, min(1.0, (d - lo) / (hi - lo))) * 255)
            if a > 0:
                if despill:
                    mrg = max(r, g)
                    if b > mrg:
                        b = int(mrg + (b - mrg) * 0.25)
                op[x, y] = (r, g, b, a)
    return out


def column_runs(rgba, min_gap_frac=0.03, solid_frac=0.02, amin=150):
    W, H = rgba.size
    op = rgba.load()
    thr = max(3, int(H * solid_frac))
    cc = [0] * W
    for x in range(W):
        n = 0
        for y in range(H):
            if op[x, y][3] > amin:   # count only near-opaque body pixels
                n += 1
        cc[x] = n
    runs, s = [], None
    for x in range(W):
        if cc[x] >= thr and s is None:
            s = x
        elif cc[x] < thr and s is not None:
            if x - s > W * min_gap_frac:
                runs.append((s, x))
            s = None
    if s is not None:
        runs.append((s, W))
    return runs


def components(rgba, amin=150, ds=4, min_area_frac=0.004):
    """Connected-component bboxes (full-res, sorted left->right) of the opaque
    blobs — robust to narrow gaps where column projection merges neighbours."""
    W, H = rgba.size
    sw, sh = W // ds, H // ds
    small = rgba.resize((sw, sh), Image.NEAREST).load()
    mask = [[1 if small[x, y][3] > amin else 0 for x in range(sw)] for y in range(sh)]
    seen = [[False] * sw for _ in range(sh)]
    comps = []
    for y0 in range(sh):
        for x0 in range(sw):
            if mask[y0][x0] and not seen[y0][x0]:
                stack = [(x0, y0)]
                seen[y0][x0] = True
                minx = maxx = x0
                miny = maxy = y0
                area = 0
                while stack:
                    x, y = stack.pop()
                    area += 1
                    minx, maxx = min(minx, x), max(maxx, x)
                    miny, maxy = min(miny, y), max(maxy, y)
                    for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                        nx, ny = x + dx, y + dy
                        if 0 <= nx < sw and 0 <= ny < sh and mask[ny][nx] and not seen[ny][nx]:
                            seen[ny][nx] = True
                            stack.append((nx, ny))
                if area >= sw * sh * min_area_frac:
                    comps.append((area, minx * ds, miny * ds, (maxx + 1) * ds, (maxy + 1) * ds))
    comps.sort(key=lambda c: c[1])   # left -> right
    return [(c[1], c[2], c[3], c[4]) for c in comps]


def square(img, pad=1.06):
    bbox = img.getbbox()
    c = img.crop(bbox)
    w, h = c.size
    side = int(max(w, h) * pad)
    cv = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    cv.paste(c, ((side - w) // 2, (side - h) // 2), c)
    return cv


# ---- food cubes -> mosaic cells (4 tone/flip variants each) -----------------
# sheet is left->right: choc, bread, sugar, mint(green), strawberry(red=berry)
if os.path.exists(f"{SRC}/ac_food_cubes.png"):
    rgba = key(Image.open(f"{SRC}/ac_food_cubes.png"), 120, 200)
    boxes = components(rgba)
    print("food cube components:", len(boxes))
    assert len(boxes) == 5, f"expected 5 cubes, got {len(boxes)}"
    NAMES = ["choc", "bread", "sugar", "mint", "berry"]
    CELL = 240
    for i, (x0, y0, x1, y1) in enumerate(boxes):
        pad = 8
        base = square(rgba.crop((max(0, x0 - pad), max(0, y0 - pad), x1 + pad, y1 + pad)),
                      pad=1.0).resize((CELL, CELL), Image.LANCZOS)
        variants = [base,
                    base.transpose(Image.FLIP_LEFT_RIGHT),
                    base.transpose(Image.FLIP_TOP_BOTTOM),
                    base.transpose(Image.ROTATE_180)]
        tones = [1.0, 0.965, 1.03, 0.985]
        for v in range(4):
            t = ImageEnhance.Brightness(variants[v]).enhance(tones[v])
            t.save(f"assets/textures/cell_{NAMES[i]}_{v + 1}.png")
    print("wrote 20 cell_*.png tiles")

# ---- bar + badge ------------------------------------------------------------
if os.path.exists(f"{SRC}/ac_bar_badge.png"):
    rgba = key(Image.open(f"{SRC}/ac_bar_badge.png"), 80, 150)
    boxes = components(rgba)
    print("bar/badge components:", len(boxes))
    assert len(boxes) == 2, f"expected bar+badge, got {len(boxes)}"
    # left = bar, right = badge
    bx = boxes[0]
    bar = rgba.crop((bx[0], bx[1], bx[2], bx[3]))
    bw, bh = bar.size
    bar = bar.resize((int(bw * 128 / bh), 128), Image.LANCZOS)
    bar.save("assets/textures/bar_wood.png")
    print("wrote bar_wood", bar.size, "suggested 9-slice border px =", int(128 * 0.46))
    gx = boxes[1]
    badge = square(rgba.crop((gx[0], gx[1], gx[2], gx[3])), pad=1.04).resize((192, 192), Image.LANCZOS)
    badge.save("assets/textures/badge_wood.png")
    print("wrote badge_wood", badge.size)

# ---- tray (flat top-down) ---------------------------------------------------
if os.path.exists(f"{SRC}/ac_tray.png"):
    rgba = key(Image.open(f"{SRC}/ac_tray.png"), 70, 150)
    tray = square(rgba, pad=1.0).resize((512, 512), Image.LANCZOS)
    tray.save("assets/textures/tray_wood.png")
    print("wrote tray_wood", tray.size, "suggested 9-slice border px =", int(512 * 0.16))
