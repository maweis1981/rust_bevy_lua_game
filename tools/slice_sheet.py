#!/usr/bin/env python3
"""Slice a Floniks sprite SHEET (N frames in one horizontal row) into N clean
frame PNGs for playback. Each column is cut out (flood-key the baked-in
transparency checkerboard), cropped to the subject, and centred on an equal
square canvas so the frames line up when swapped in-game.

Usage: slice_sheet.py <sheet.png> <out_prefix> <n_frames> <frame_px> [--tol N]
  -> writes <out_prefix>1.png .. <out_prefix>N.png in assets/textures/
"""
import os
import sys
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import floniks_sprite as fs

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "textures")


def main():
    a = sys.argv
    sheet_path, prefix, n, px = a[1], a[2], int(a[3]), int(a[4])
    tol = int(a[a.index("--tol") + 1]) if "--tol" in a else 100
    margin = 0.08
    sheet = Image.open(sheet_path).convert("RGB")
    W, H = sheet.size
    cw = W // n
    # Cut out the WHOLE sheet once (consistent keying), then split into columns.
    keyed = fs.cutout(sheet, tol)
    cols = [keyed.crop((i * cw, 0, (i + 1) * cw, H)) for i in range(n)]
    boxes = [c.getbbox() for c in cols]
    # UNIFORM scale from the tallest subject, and align all frames to a common
    # BASELINE (feet at the bottom) so the walk cycle doesn't pulse or bob in size.
    max_h = max((b[3] - b[1]) for b in boxes if b)
    avail = px * (1 - 2 * margin)
    scale = avail / max_h
    for i, (col, b) in enumerate(zip(cols, boxes)):
        out = Image.new("RGBA", (px, px), (0, 0, 0, 0))
        if b:
            sub = col.crop(b)
            sw, sh = max(1, round(sub.width * scale)), max(1, round(sub.height * scale))
            sub = sub.resize((sw, sh), Image.LANCZOS)
            x = (px - sw) // 2                                  # horizontal centre
            y = px - round(px * margin) - sh                    # bottom-aligned feet
            out.paste(sub, (x, y), sub)
        path = os.path.join(OUT, f"{prefix}{i + 1}.png")
        out.save(path)
        print(f"wrote {path} ({px}x{px}) from column {i + 1}/{n}")


if __name__ == "__main__":
    main()
