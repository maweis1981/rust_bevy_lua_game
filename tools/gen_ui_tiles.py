#!/usr/bin/env python3
"""Rounded, anti-aliased UI textures for the Pony Parade board & HUD.

All four are white/grayscale so `game.set_color` tints them at runtime
(the same trick as orb/paddle/brick/tile). Drawn at 8x supersampling and
downsampled with LANCZOS, so corners and the X strokes stay smooth even
when the sprite is scaled on a 120 Hz ProMotion screen.

  rtile.png   64x64   rounded board tile (subtle top-light so cells feel soft)
  rxmark.png  64x64   bold rounded X (the auto-exclusion mark)
  rpill.png  256x64   4:1 rounded pill (HUD counters, banner)
  rcard.png 192x192   rounded square card (tool buttons, overlay panel)

Run: python3 tools/gen_ui_tiles.py   (requires Pillow)
"""
import os

from PIL import Image, ImageDraw, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
TEX = os.path.join(HERE, "..", "assets", "textures")
SS = 8  # supersampling factor


def canvas(w, h):
    return Image.new("RGBA", (w * SS, h * SS), (0, 0, 0, 0))


def save(img, name, w, h):
    out = img.resize((w, h), Image.LANCZOS)
    out.save(os.path.join(TEX, name))
    print(f"  {name} {w}x{h}")


def rounded(draw, box, radius, fill):
    draw.rounded_rectangle(box, radius=radius, fill=fill)


def gen_rtile():
    w = h = 64
    img = canvas(w, h)
    d = ImageDraw.Draw(img)
    m = 1 * SS
    r = 12 * SS
    # base
    rounded(d, (m, m, w * SS - m, h * SS - m), r, (255, 255, 255, 255))
    # subtle top-light: a slightly brighter band that survives tinting as a
    # gentle vertical gradient (240 bottom -> 255 top).
    grad = Image.new("L", (1, h * SS), 0)
    for y in range(h * SS):
        grad.putpixel((0, y), int(255 - 18 * (y / (h * SS))))
    grad = grad.resize((w * SS, h * SS))
    img.putalpha(img.split()[3])
    rgb = Image.merge("RGBA", (grad, grad, grad, img.split()[3]))
    save(rgb, "rtile.png", w, h)


def gen_rxmark():
    w = h = 64
    img = canvas(w, h)
    bar = Image.new("RGBA", (w * SS, h * SS), (0, 0, 0, 0))
    bd = ImageDraw.Draw(bar)
    # one rounded bar through the center, then rotate +-45 and merge
    bw, bh = int(w * SS * 0.78), int(h * SS * 0.22)
    x0 = (w * SS - bw) // 2
    y0 = (h * SS - bh) // 2
    rounded(bd, (x0, y0, x0 + bw, y0 + bh), bh // 2, (255, 255, 255, 255))
    a = bar.rotate(45, resample=Image.BICUBIC, center=(w * SS / 2, h * SS / 2))
    b = bar.rotate(-45, resample=Image.BICUBIC, center=(w * SS / 2, h * SS / 2))
    img = Image.alpha_composite(img, a)
    img = Image.alpha_composite(img, b)
    save(img, "rxmark.png", w, h)


def gen_rpill():
    w, h = 256, 64
    img = canvas(w, h)
    d = ImageDraw.Draw(img)
    m = 2 * SS
    rounded(d, (m, m, w * SS - m, h * SS - m), (h * SS - 2 * m) // 2, (255, 255, 255, 255))
    save(img, "rpill.png", w, h)


def gen_rcard():
    w = h = 192
    img = canvas(w, h)
    d = ImageDraw.Draw(img)
    m = 2 * SS
    rounded(d, (m, m, w * SS - m, h * SS - m), 34 * SS, (255, 255, 255, 255))
    # soft inner shadow at the bottom edge so cards feel raised
    sh = canvas(w, h)
    sd = ImageDraw.Draw(sh)
    rounded(sd, (m, h * SS // 2, w * SS - m, h * SS - m), 34 * SS, (0, 0, 0, 26))
    sh = sh.filter(ImageFilter.GaussianBlur(6 * SS))
    img = Image.alpha_composite(img, sh)
    save(img, "rcard.png", w, h)


if __name__ == "__main__":
    print("writing rounded UI textures:")
    gen_rtile()
    gen_rxmark()
    gen_rpill()
    gen_rcard()
