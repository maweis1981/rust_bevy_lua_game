#!/usr/bin/env python3
"""Slice a Floniks icon SHEET (a cols x rows grid of same-size icons in ONE image)
into individual clean icon PNGs. Unlike slice_sheet.py (which bottom-aligns a walk
cycle), this CENTRES each icon and applies ONE uniform scale to every cell, so a
cohesive set stays visually consistent in size — the fix for "sizes don't match".

The whole sheet is keyed once (consistent flood-key of the baked checkerboard),
split row-major into cols*rows cells, and each subject is scaled by a single
shared factor (from the largest subject) then centred on a px*px transparent box.

Usage: slice_grid.py <sheet.png> <cols> <rows> <px> <name1,name2,...> [--tol N] [--preview-scale 8]
  -> writes assets/textures/<nameK>.png (row-major order) + build/floniks_preview/<nameK>.png
"""
import os
import sys
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import floniks_sprite as fs

HERE = os.path.dirname(os.path.abspath(__file__))
TEX = os.path.join(HERE, "..", "assets", "textures")
PREVIEW = os.path.join(HERE, "..", "build", "floniks_preview")


def main():
    a = sys.argv
    sheet_path, cols, rows, px = a[1], int(a[2]), int(a[3]), int(a[4])
    names = [n.strip() for n in a[5].split(",") if n.strip()]
    tol = int(a[a.index("--tol") + 1]) if "--tol" in a else 100
    pscale = int(a[a.index("--preview-scale") + 1]) if "--preview-scale" in a else 8
    margin = 0.06
    os.makedirs(PREVIEW, exist_ok=True)

    sheet = Image.open(sheet_path).convert("RGB")
    W, H = sheet.size
    cw, ch = W // cols, H // rows
    keyed = fs.cutout(sheet, tol)

    # Cut every cell, find each subject's bbox.
    cells, boxes = [], []
    for r in range(rows):
        for c in range(cols):
            cell = keyed.crop((c * cw, r * ch, (c + 1) * cw, (r + 1) * ch))
            cells.append(cell)
            boxes.append(cell.getbbox())

    # ONE uniform scale from the largest subject dimension -> consistent sizes.
    max_dim = max(max(b[2] - b[0], b[3] - b[1]) for b in boxes if b)
    scale = px * (1 - 2 * margin) / max_dim

    for i, (cell, b) in enumerate(zip(cells, boxes)):
        if i >= len(names):
            break
        out = Image.new("RGBA", (px, px), (0, 0, 0, 0))
        if b:
            sub = cell.crop(b)
            sw, sh = max(1, round(sub.width * scale)), max(1, round(sub.height * scale))
            sub = sub.resize((sw, sh), Image.LANCZOS)
            out.paste(sub, ((px - sw) // 2, (px - sh) // 2), sub)  # centred
        path = os.path.join(TEX, names[i] + ".png")
        out.save(path)
        out.resize((px * pscale, px * pscale), Image.NEAREST).save(
            os.path.join(PREVIEW, names[i] + ".png"))
        print(f"wrote {names[i]}.png ({px}x{px}) from cell {i + 1}")


if __name__ == "__main__":
    main()
