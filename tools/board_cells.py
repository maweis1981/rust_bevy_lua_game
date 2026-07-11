#!/usr/bin/env python3
"""board_cells.py — refined mosaic CELL textures for the picture board.

Why: the board previously reused the big food tokens (3/4-view cubes with a
baked drop shadow) at ~22px per cell — every cell read as a separate little
object, with obvious texture repetition and shadow noise. A refined mosaic
(like the reference) reads as ONE continuous surface: flat matte cells, a
subtle bevel, thin uniform seams, and no per-cell shadow.

For each food we crop FOUR different windows out of the high-res render's
face (different offsets + mirrored), so adjacent same-colour cells don't
repeat visibly. Each variant gets: gentle brightness normalisation, a soft
top-light/bottom-shade bevel, a thin dark seam border and rounded corners.

Output: assets/textures/cell_<food>_<1..4>.png (96px, alpha).
"""
import sys

from PIL import Image, ImageDraw, ImageEnhance, ImageFilter, ImageOps

sys.path.insert(0, "tools")
import floniks_sprite as fs

N = 96
SRC = {
    "choc":  "build/floniks_src/food_choc.png",
    "bread": "build/floniks_src/food_bread.png",
    "sugar": "build/floniks_src/food_sugar.png",
    "berry": "build/floniks_src/food_berry.png",
    "mint":  "build/floniks_src/food_mint.png",
}
# window offsets within the face (fractions of the big cutout), one per variant
WINDOWS = [(0.30, 0.42), (0.52, 0.40), (0.34, 0.60), (0.54, 0.62)]


def bevel(im):
    """Flat-cell finish: soft top light + bottom shade, thin seam, round corners."""
    im = im.convert("RGBA")
    w, h = im.size
    ov = Image.new("RGBA", im.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(ov)
    # top-edge light and bottom-edge shade (soft, painted as gradients)
    for i in range(int(h * 0.16)):
        a = int(70 * (1 - i / (h * 0.16)))
        d.line([(0, i), (w, i)], fill=(255, 255, 255, a))
    for i in range(int(h * 0.14)):
        a = int(60 * (1 - i / (h * 0.14)))
        d.line([(0, h - 1 - i), (w, h - 1 - i)], fill=(30, 15, 8, a))
    # side hints
    for i in range(int(w * 0.06)):
        a = int(30 * (1 - i / (w * 0.06)))
        d.line([(i, 0), (i, h)], fill=(255, 255, 255, a // 2))
        d.line([(w - 1 - i, 0), (w - 1 - i, h)], fill=(30, 15, 8, a // 2))
    im = Image.alpha_composite(im, ov)
    # thin dark seam border + rounded-corner mask
    d2 = ImageDraw.Draw(im)
    d2.rounded_rectangle([0, 0, w - 1, h - 1], 14, outline=(40, 22, 12, 160), width=3)
    mask = Image.new("L", im.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, w - 1, h - 1], 14, fill=255)
    im.putalpha(mask)
    return im


def main():
    for food, src in SRC.items():
        big = fs.build(src, 512, 512, tol=60, bg="blue", margin=0.02).convert("RGB")
        for k, (fx, fy) in enumerate(WINDOWS):
            win = int(512 * 0.30)
            x0 = int(512 * fx - win / 2)
            y0 = int(512 * fy - win / 2)
            tile = big.crop((x0, y0, x0 + win, y0 + win))
            if k % 2 == 1:
                tile = ImageOps.mirror(tile)
            # normalise: gentle autocontrast so all variants sit at the same tone
            tile = ImageEnhance.Contrast(tile).enhance(0.96)
            tile = ImageEnhance.Sharpness(tile).enhance(1.15)
            tile = tile.resize((N, N), Image.LANCZOS)
            bevel(tile).save(f"assets/textures/cell_{food}_{k + 1}.png")
        print("cell_%s x4" % food)

    # contact sheet: a mini mosaic so the seams/repetition can be judged
    import random
    random.seed(3)
    z = 34
    sheet = Image.new("RGB", (z * 12 + 20, z * 6 + 20), (150, 108, 70))
    foods = ["mint"] * 4 + ["bread"] * 4 + ["sugar"] * 2 + ["choc"] + ["berry"]
    for r in range(6):
        for c in range(12):
            f = foods[(r * 5 + c) % len(foods)]
            v = (r * 7 + c * 13) % 4 + 1
            t = Image.open(f"assets/textures/cell_{f}_{v}.png").resize((z, z), Image.LANCZOS)
            sheet.paste(t, (10 + c * z, 10 + r * z), t)
    sheet.save("build/cell_mosaic.png")
    print("wrote build/cell_mosaic.png")


if __name__ == "__main__":
    main()
