#!/usr/bin/env python3
"""gen_chunky_levels.py — regenerate the Ant Art levels at LOW resolution so the
mosaic reads as big chunky Animal-Crossing food blocks (like the concept), not a
fine dense grid. Reuses gen_level.py's solvable-tray oracle + validator.

Emits build/chunky_levels.lua (the LEVELS table body) and a preview PNG per level
so the shapes can be eyeballed before embedding. Colours: 1 choc, 2 bread,
3 sugar, 4 berry, 5 mint (the game's food palette).
"""
import importlib.util, os
spec = importlib.util.spec_from_file_location("gl", "tools/gen_level.py")
gl = importlib.util.module_from_spec(spec); spec.loader.exec_module(gl)
from PIL import Image

FOOD = {1: (74, 46, 32), 2: (255, 159, 28), 3: (255, 243, 220),
        4: (255, 90, 106), 5: (57, 201, 184)}

# chunky authored fox SHAPE on soil (no full backdrop) — matches the concept:
# choc ears/eyes/nose, bread fur, sugar cheeks/muzzle, berry nose, mint feet.
FOX = [
    "..1...1..",
    ".121.121.",
    ".1222221.",
    "322222223",
    "321202123",
    "222222222",
    "332434233",
    ".3344433.",
    "..53235..",
]
CAT = [
    "1.......1",
    "141.....141"[:9],
    "1441...1441"[:9],
    "12211112211"[:9],
    "1222222221",
    "1223333221"[:9],
    "1235335321"[:9],
    "1233333321"[:9],
    "1223443221"[:9],
    ".12222221.",
    "..111111..",
]


def from_rows(rows):
    ww = max(len(r) for r in rows)
    return [[0 if ch in "0. " else int(ch) for ch in r.ljust(ww, ".")] for r in rows]


def remap(grid, m):
    """Remap colour indices to food types (the board renders by index, not the
    level palette) so heart/smiley become colourful instead of brown/orange."""
    return [[m.get(v, v) if v else 0 for v in row] for row in grid]


def preview(grid, name, cell=44):
    h, w = len(grid), len(grid[0])
    im = Image.new("RGB", (w * cell, h * cell), (150, 120, 90))
    px = im.load()
    for r in range(h):
        for c in range(w):
            v = grid[r][c]
            if v == 0:
                continue
            col = FOOD[v]
            for yy in range(r * cell + 2, r * cell + cell - 2):
                for xx in range(c * cell + 2, c * cell + cell - 2):
                    px[xx, yy] = col
    im.save(f"build/level_{name}.png")


def gen(name, grid, batch, slots=4):
    w, h = len(grid[0]), len(grid)
    tray, peak = gl.make_tray(grid, w, h, batch)
    ok, _ = gl.validate(grid, tray, w, h, slots)
    total = sum(1 for row in grid for v in row if v)
    print(f"{name}: {w}x{h} painted={total} batches={len(tray)} peak={peak} solvable@{slots}={ok}")
    assert ok, f"{name} NOT solvable@{slots}"
    preview(grid, name)
    return w, h, tray


os.makedirs("build", exist_ok=True)
LEVELS = []
# 1 fox (authored), 2 heart, 3 smiley, 4 donut, 5 cat — all chunky low-res
specs = [
    ("fox", from_rows(FOX), 4),
    # heart: body->berry(red), shade->choc, highlight->sugar
    ("heart", remap(gl.build_grid("heart", 9, 8), {1: 4, 2: 1, 3: 3}), 4),
    # smiley: face->bread(yellow), eyes/mouth->choc, cheeks->berry
    ("smiley", remap(gl.build_grid("smiley", 9, 9), {1: 2, 2: 1, 3: 4}), 4),
    ("donut", gl.build_grid("donut", 11, 10), 5),
    ("cat", from_rows(CAT), 4),
]
out = []
for name, grid, batch in specs:
    w, h, tray = gen(name, grid, batch)
    gstr = ",\n        ".join("{" + ",".join(str(v) for v in row) + "}" for row in grid)
    tstr = ",".join(f"{{{c},{n}}}" for (c, n) in tray)
    out.append(f"""    {{ -- {name} (chunky)
      slots = 4, w = {w}, h = {h},
      grid = {{
        {gstr},
      }},
      tray = {{ {tstr} }},
    }},""")
open("build/chunky_levels.lua", "w").write("  local LEVELS = {\n" + "\n".join(out) + "\n  }\n")
print("wrote build/chunky_levels.lua + build/level_*.png previews")
