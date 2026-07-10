#!/usr/bin/env python3
"""gen_ant_ui.py — UI textures for Ant Art, matched to the reference game.

Writes (Pillow):
  assets/textures/tile_sq.png   rounded SQUARE candy tile, grayscale w/ baked
                                bevel+gloss so game.set_color tints it into any
                                colour and it still reads 3D (slots + queue).
  assets/textures/cat_face.png  the decorative cat mascot banner (full colour).
  assets/textures/hole.png      the nest hole (dark funnel).
  assets/textures/ad_play.png   little red rewarded-video play badge.
"""
import os
from PIL import Image, ImageDraw

os.makedirs("assets/textures", exist_ok=True)
SS = 4


def save(im, name):
    im.save(f"assets/textures/{name}.png")
    print("wrote", name, im.size)


def candy_tile():
    N = 96
    im = Image.new("RGBA", (N * SS, N * SS), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    r = N * SS * 0.24
    lift = N * SS * 0.10
    # base (bottom bevel = mid gray), top face = white, gloss = brighter
    d.rounded_rectangle([0, 0, N * SS - 1, N * SS - 1], radius=r, fill=(150, 150, 150, 255))
    d.rounded_rectangle([0, 0, N * SS - 1, N * SS - 1 - lift], radius=r, fill=(235, 235, 235, 255))
    d.rounded_rectangle([N * SS * 0.14, N * SS * 0.10, N * SS * 0.86, N * SS * 0.40],
                        radius=r * 0.5, fill=(255, 255, 255, 210))
    save(im.resize((N, N), Image.LANCZOS), "tile_sq")


def hole():
    N = 96
    im = Image.new("RGBA", (N * SS, N * SS), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.ellipse([2, N * SS * 0.18, N * SS - 2, N * SS - 2], fill=(70, 50, 38, 255))
    d.ellipse([N * SS * 0.12, N * SS * 0.30, N * SS * 0.88, N * SS * 0.92], fill=(40, 28, 20, 255))
    d.ellipse([N * SS * 0.26, N * SS * 0.42, N * SS * 0.74, N * SS * 0.80], fill=(22, 15, 10, 255))
    save(im.resize((N, N), Image.LANCZOS), "hole")


def ad_play():
    N = 48
    im = Image.new("RGBA", (N * SS, N * SS), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.rounded_rectangle([2, N * SS * 0.22, N * SS - 2, N * SS * 0.78], radius=N * SS * 0.16,
                        fill=(224, 84, 84, 255))
    cx, cy, s = N * SS * 0.5, N * SS * 0.5, N * SS * 0.16
    d.polygon([(cx - s * 0.7, cy - s), (cx - s * 0.7, cy + s), (cx + s, cy)], fill=(255, 255, 255, 255))
    save(im.resize((N, N), Image.LANCZOS), "ad_play")


def cat_face():
    """Decorative mascot banner: a fluffy white cat head, drawn wide."""
    Wd, Hd = 320, 130
    im = Image.new("RGBA", (Wd * SS, Hd * SS), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    cx = Wd * SS / 2
    fur = (250, 247, 242, 255)
    # ears
    for sx in (-1, 1):
        d.polygon([(cx + sx * 118 * SS, 46 * SS), (cx + sx * 60 * SS, 6 * SS), (cx + sx * 64 * SS, 74 * SS)], fill=fur)
        d.polygon([(cx + sx * 100 * SS, 46 * SS), (cx + sx * 70 * SS, 22 * SS), (cx + sx * 74 * SS, 60 * SS)], fill=(245, 196, 206, 255))
    # head
    d.ellipse([cx - 150 * SS, 20 * SS, cx + 150 * SS, Hd * SS + 60 * SS], fill=fur)
    # eyes (closed happy), blush, mouth
    for sx in (-1, 1):
        d.arc([cx + sx * 52 * SS - 18 * SS, 62 * SS, cx + sx * 52 * SS + 18 * SS, 98 * SS], 200, 340,
              fill=(120, 96, 88, 255), width=5 * SS)
        d.ellipse([cx + sx * 84 * SS - 13 * SS, 86 * SS, cx + sx * 84 * SS + 13 * SS, 104 * SS], fill=(250, 204, 204, 255))
    d.arc([cx - 20 * SS, 88 * SS, cx + 20 * SS, 112 * SS], 20, 160, fill=(120, 96, 88, 255), width=5 * SS)
    # whiskers
    for sx in (-1, 1):
        for k in (-1, 0, 1):
            d.line([(cx + sx * 96 * SS, 96 * SS + k * 10 * SS), (cx + sx * 140 * SS, 92 * SS + k * 16 * SS)],
                   fill=(210, 200, 190, 255), width=2 * SS)
    save(im.resize((Wd, Hd), Image.LANCZOS), "cat_face")


def ant_shadow():
    """A soft round drop-shadow to ground each ant (semi-transparent, feathered)."""
    N = 64
    im = Image.new("RGBA", (N * SS, N * SS), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    cx, cy = N * SS / 2, N * SS / 2
    for k in range(14, 0, -1):
        rr = (N * SS / 2) * (k / 14)
        a = int(70 * (1 - k / 14) ** 1.4)
        d.ellipse([cx - rr, cy - rr * 0.62, cx + rr, cy + rr * 0.62], fill=(30, 22, 18, a))
    save(im.resize((N, N), Image.LANCZOS), "ant_shadow")


candy_tile(); hole(); ad_play(); cat_face(); ant_shadow()
