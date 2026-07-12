#!/usr/bin/env python3
"""make_ac_ground.py — process the Animal-Crossing ground assets for Ant Art.

  build/floniks_src/ac_grass_bg.png  -> assets/textures/game_bg.png   (bright grass)
  build/floniks_src/ac_soil_plot.png -> assets/textures/soil_plot.png (dug plot,
     blue chroma keyed out, cropped square, for a 9-slice panel behind the mosaic)

Prints the rim border thickness (px) to use as the 9-slice border in Lua.
"""
import os
from PIL import Image

os.makedirs("assets/textures", exist_ok=True)

# --- background: bright grass, just downscale to a sane size (keep 2:3) --------
bg = Image.open("build/floniks_src/ac_grass_bg.png").convert("RGB")
bg = bg.resize((768, 1152), Image.LANCZOS)
bg.save("assets/textures/game_bg.png")
print("wrote game_bg", bg.size)

# --- soil plot: key the pure-blue background, crop to the plot, pad square -----
im = Image.open("build/floniks_src/ac_soil_plot.png").convert("RGB")
W, H = im.size
px = im.load()
bg_ref = px[3, 3]
print("plot bg ref", bg_ref)


def dist(a, b):
    return ((a[0] - b[0]) ** 2 + (a[1] - b[1]) ** 2 + (a[2] - b[2]) ** 2) ** 0.5


LO, HI = 60.0, 140.0
out = Image.new("RGBA", (W, H), (0, 0, 0, 0))
op = out.load()
for y in range(H):
    for x in range(W):
        r, g, b = px[x, y]
        a = int(max(0.0, min(1.0, (dist((r, g, b), bg_ref) - LO) / (HI - LO))) * 255)
        if a > 0:
            mrg = max(r, g)
            if b > mrg:
                b = int(mrg + (b - mrg) * 0.25)   # despill blue fringe
            op[x, y] = (r, g, b, a)

bbox = out.getbbox()
plot = out.crop(bbox)
w, h = plot.size
side = max(w, h)
canvas = Image.new("RGBA", (side, side), (0, 0, 0, 0))
canvas.paste(plot, ((side - w) // 2, (side - h) // 2), plot)
OUTSZ = 512
canvas = canvas.resize((OUTSZ, OUTSZ), Image.LANCZOS)
canvas.save("assets/textures/soil_plot.png")

# estimate rim thickness: scan the middle row inward until we leave the rim.
# the rim is the raised berm; the inner soil is flatter/darker. Simple proxy:
# thickness ~ 12% of the plot side (the generated berm width). Print for Lua.
rim = int(OUTSZ * 0.13)
print("wrote soil_plot", canvas.size, "suggested 9-slice border px =", rim)
