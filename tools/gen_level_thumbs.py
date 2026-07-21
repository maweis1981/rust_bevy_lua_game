#!/usr/bin/env python3
"""Render a preview thumbnail for each Ant Art level by parsing the grids straight
out of assets/scripts/packs/ant_clear.lua (so previews never drift from the real
levels). Each thumbnail is the picture's pixel mosaic centred on a soft card,
upscaled NEAREST. Output: assets/textures/lvl_thumb_<n>.png (1-based)."""
import re
from PIL import Image

LUA = "assets/scripts/packs/ant_clear.lua"
OUT = "assets/textures"
# PALETTE5 in ant_clear.lua (0 = empty)
PAL = {1:(96,52,40), 2:(255,142,18), 3:(255,232,180), 4:(255,86,120), 5:(38,222,158)}


def parse_grids(text):
    """Return a list of grids (each a list of int rows), one per level, in order."""
    grids = []
    # each level block: grid = { {..},{..}, ... },
    for m in re.finditer(r"grid\s*=\s*\{(.*?)\}\s*,\s*\n\s*tray", text, re.S):
        block = m.group(1)
        rows = []
        for rm in re.finditer(r"\{([\d,\s]+)\}", block):
            rows.append([int(v) for v in rm.group(1).split(",") if v.strip() != ""])
        if rows:
            grids.append(rows)
    return grids


def render(grid, target=256):
    H, W = len(grid), len(grid[0])
    side = max(W, H)
    cell = 1
    im = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    ox, oy = (side - W) // 2, (side - H) // 2
    for r in range(H):
        for c in range(W):
            v = grid[r][c]
            if v:
                im.putpixel((ox + c, oy + r), PAL[v] + (255,))
    # upscale NEAREST to a chunky thumbnail
    scale = target // side
    return im.resize((side * scale, side * scale), Image.NEAREST)


if __name__ == "__main__":
    text = open(LUA).read()
    grids = parse_grids(text)
    print(f"parsed {len(grids)} level grids")
    for i, g in enumerate(grids, 1):
        render(g).save(f"{OUT}/lvl_thumb_{i}.png")
        print(f"wrote lvl_thumb_{i}  ({len(g[0])}x{len(g)})")
