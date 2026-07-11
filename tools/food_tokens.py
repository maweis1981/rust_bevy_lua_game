#!/usr/bin/env python3
"""food_tokens.py — build the five food cube tokens with real material + shadow.

The mockup-slice cubes (18px crops upscaled) lost all texture. This rebuilds
each token from the high-res Floniks food renders (chocolate chunk, toasted
crouton, sugar cube, strawberry jelly, mint jelly — rich texture and glossy
volume), and BAKES IN what the mosaic needs to read 3D:
  * a soft drop/contact shadow under the cube (offset down, elliptical), and
  * a subtle darkening of the cube's bottom edge (grounded, not floating).

Output: assets/textures/food_*.png (128px, alpha). Pillow only.
"""
from PIL import Image, ImageDraw, ImageEnhance, ImageFilter
import sys

sys.path.insert(0, "tools")
import floniks_sprite as fs

N = 128
FOODS = {
    "food_choc":  "build/floniks_src/food_choc.png",
    "food_bread": "build/floniks_src/food_bread.png",
    "food_sugar": "build/floniks_src/food_sugar.png",
    "food_berry": "build/floniks_src/food_berry.png",
    "food_mint":  "build/floniks_src/food_mint.png",
}


def build(src):
    # keyed cube fills most of the frame, leaving room for the shadow below
    cube = fs.build(src, int(N * 0.94), int(N * 0.90), tol=60, bg="blue", margin=0.02)
    cube = ImageEnhance.Sharpness(cube).enhance(1.25)       # keep the grain crisp
    out = Image.new("RGBA", (N, N), (0, 0, 0, 0))

    # soft contact shadow under the cube (drawn first, cube overlaps it)
    sh = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    d = ImageDraw.Draw(sh)
    d.ellipse([N * 0.10, N * 0.74, N * 0.90, N * 0.97], fill=(30, 18, 10, 110))
    sh = sh.filter(ImageFilter.GaussianBlur(5))
    out.alpha_composite(sh)

    # ground the cube: darken its bottom ~22% with a soft gradient
    grad = Image.new("L", (1, cube.height), 0)
    for y in range(cube.height):
        t = max(0.0, (y / cube.height - 0.78) / 0.22)
        grad.putpixel((0, y), int(70 * t))
    dark = Image.new("RGBA", cube.size, (20, 10, 5, 255))
    dark.putalpha(grad.resize(cube.size))
    cube = cube.copy()
    cube.alpha_composite(dark)

    out.alpha_composite(cube, ((N - cube.width) // 2, 0))
    return out


def main():
    tiles = []
    for name, src in FOODS.items():
        im = build(src)
        im.save(f"assets/textures/{name}.png")
        tiles.append(im)
        print("wrote", name)
    # contact sheet on soil-ish card
    z = 110
    card = Image.new("RGB", (z * 5 + 20, z + 20), (150, 108, 70))
    x = 10
    for t in tiles:
        s = t.resize((z, z), Image.LANCZOS)
        card.paste(s, (x, 10), s)
        x += z
    card.save("build/food_tokens.png")
    print("wrote build/food_tokens.png")


if __name__ == "__main__":
    main()
