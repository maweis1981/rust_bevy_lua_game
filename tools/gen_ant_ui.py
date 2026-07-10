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


def icon_speed():
    """Blue upgrade drop with an up-arrow (速度升级)."""
    N = 48; im = Image.new("RGBA", (N*SS, N*SS), (0,0,0,0)); d = ImageDraw.Draw(im)
    cx, cy = N*SS/2, N*SS*0.56
    d.pieslice([cx-15*SS, cy-15*SS, cx+15*SS, cy+15*SS], 30, 330, fill=(70,150,220,255))
    d.polygon([(cx, N*SS*0.10),(cx-11*SS, cy-6*SS),(cx+11*SS, cy-6*SS)], fill=(70,150,220,255))
    d.polygon([(cx, cy-8*SS),(cx-7*SS, cy),(cx-3*SS, cy),(cx-3*SS, cy+8*SS),
               (cx+3*SS, cy+8*SS),(cx+3*SS, cy),(cx+7*SS, cy)], fill=(255,255,255,255))
    save(im.resize((N,N), Image.LANCZOS), "icon_speed")


def icon_x2():
    """Fast-forward chevrons (速度x2)."""
    N = 48; im = Image.new("RGBA", (N*SS, N*SS), (0,0,0,0)); d = ImageDraw.Draw(im)
    for off in (-9*SS, 1*SS):
        cx = N*SS/2 + off
        d.polygon([(cx-6*SS, N*SS*0.28),(cx+8*SS, N*SS*0.5),(cx-6*SS, N*SS*0.72)], fill=(255,255,255,255))
    save(im.resize((N,N), Image.LANCZOS), "icon_x2")


def icon_gift():
    """Gift box (level-unlock buttons)."""
    N = 48; im = Image.new("RGBA", (N*SS, N*SS), (0,0,0,0)); d = ImageDraw.Draw(im)
    d.rounded_rectangle([N*SS*0.2, N*SS*0.42, N*SS*0.8, N*SS*0.82], N*SS*0.06, fill=(230,120,110,255))
    d.rounded_rectangle([N*SS*0.16, N*SS*0.34, N*SS*0.84, N*SS*0.48], N*SS*0.05, fill=(245,150,140,255))
    d.rectangle([N*SS*0.46, N*SS*0.34, N*SS*0.54, N*SS*0.82], fill=(255,220,150,255))
    d.ellipse([N*SS*0.32, N*SS*0.22, N*SS*0.5, N*SS*0.38], outline=(255,220,150,255), width=3*SS)
    d.ellipse([N*SS*0.5, N*SS*0.22, N*SS*0.68, N*SS*0.38], outline=(255,220,150,255), width=3*SS)
    save(im.resize((N,N), Image.LANCZOS), "icon_gift")


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


def leaf():
    """A small soft leaf that drifts across the background (grayscale so the pack
    can tint it warm-green/amber; a lighter midrib keeps it readable)."""
    N = 48
    im = Image.new("RGBA", (N * SS, N * SS), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    cx, cy = N * SS / 2, N * SS / 2
    w, h = N * SS * 0.30, N * SS * 0.46
    d.ellipse([cx - w, cy - h, cx + w, cy + h], fill=(190, 190, 190, 255))     # blade
    d.polygon([(cx, cy - h), (cx - w * 0.5, cy), (cx, cy + h), (cx + w * 0.5, cy)],
              fill=(215, 215, 215, 255))                                        # pointed tip
    d.line([(cx, cy - h * 0.82), (cx, cy + h * 0.82)], fill=(245, 245, 245, 230),
           width=max(1, int(SS * 1.2)))                                         # midrib
    save(im.resize((N, N), Image.LANCZOS), "leaf")


def petal():
    """A soft glowing bokeh dot — feathered, near-white, for gentle floating motes."""
    N = 40
    im = Image.new("RGBA", (N * SS, N * SS), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    cx, cy = N * SS / 2, N * SS / 2
    for k in range(16, 0, -1):
        rr = (N * SS / 2) * (k / 16)
        a = int(150 * (1 - k / 16) ** 1.6)
        d.ellipse([cx - rr, cy - rr, cx + rr, cy + rr], fill=(255, 252, 240, a))
    save(im.resize((N, N), Image.LANCZOS), "petal")


candy_tile(); hole(); ad_play(); cat_face(); ant_shadow()
icon_speed(); icon_x2(); icon_gift()
leaf(); petal()
