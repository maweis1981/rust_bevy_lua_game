#!/usr/bin/env python3
"""gen_pixel_tile.py — a clean, tintable "candy pixel" tile for the board.

The board picture is the game's hero visual and must read as a crisp mosaic of
PURE solid colours (not busy food textures). This makes ONE grayscale tile that
`game.set_color` tints to any palette colour:

  - a rounded square (soft, candy-like — not a crude hard pixel),
  - body kept at full white so the tint comes out as the PURE palette colour,
  - a gentle bottom shade + faint rim so it reads as a tactile block (subtle,
    so the dominant read is still "solid colour"),
  - transparent outside the rounded corners.

Output: assets/textures/pixel_tile.png (96px, RGBA).
"""
from PIL import Image, ImageDraw, ImageFilter

N = 96
R = 16  # corner radius

im = Image.new("RGBA", (N, N), (0, 0, 0, 0))
d = ImageDraw.Draw(im)

# rounded-square body, full white (tint -> pure palette colour)
d.rounded_rectangle([2, 2, N - 3, N - 3], R, fill=(255, 255, 255, 255))

# gentle bottom shade (lower third), soft — a hint of candy dimension. Multiply
# tint can only darken, so we shade the bottom to ~0.82 of the colour.
shade = Image.new("RGBA", (N, N), (0, 0, 0, 0))
sd = ImageDraw.Draw(shade)
for i in range(int(N * 0.34)):
    y = N - 3 - i
    a = int(46 * (1 - i / (N * 0.34)))  # strongest at the very bottom
    sd.line([(3, y), (N - 4, y)], fill=(40, 26, 14, a))
shade = shade.filter(ImageFilter.GaussianBlur(2))

# faint inner top sheen: lift the top edge a touch by pre-darkening the body so
# the top reads brightest. Keep it VERY subtle so the block stays "pure colour".
# (skipped brightening — multiply can't brighten; the bottom shade alone reads.)

# thin soft darker rim for definition against the soil
rim = Image.new("RGBA", (N, N), (0, 0, 0, 0))
ImageDraw.Draw(rim).rounded_rectangle([2, 2, N - 3, N - 3], R,
                                      outline=(60, 40, 24, 70), width=3)
rim = rim.filter(ImageFilter.GaussianBlur(1))

im = Image.alpha_composite(im, shade)
im = Image.alpha_composite(im, rim)

# clip everything to the rounded-square alpha (kill any blur bleed at corners)
mask = Image.new("L", (N, N), 0)
ImageDraw.Draw(mask).rounded_rectangle([2, 2, N - 3, N - 3], R, fill=255)
r, g, b, a = im.split()
a = Image.composite(a, Image.new("L", (N, N), 0), mask)
im = Image.merge("RGBA", (r, g, b, a))

im.save("assets/textures/pixel_tile.png")
print("wrote assets/textures/pixel_tile.png", im.size)
