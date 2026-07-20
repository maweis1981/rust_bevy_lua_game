#!/usr/bin/env python3
"""gen_pixel_kit.py — a cohesive PIXEL-ART asset kit for the Ant Art game.

Everything one style: authentic chunky pixels (drawn on a small grid, upscaled
NEAREST so each source pixel becomes a crisp block; the game already runs
ImagePlugin::default_nearest). Same filenames + dimensions as the old art, so the
ant_clear layout keeps working — only the pixels change. A garden palette: grass,
dirt, wood UI, and 5 tintable food-block colours.
"""
from PIL import Image, ImageDraw

T = "assets/textures"


def grid(w, h):
    return Image.new("RGBA", (w, h), (0, 0, 0, 0))


def up(im, target):
    """Nearest-neighbour upscale a small pixel image to the target size."""
    return im.resize(target, Image.NEAREST)


def save(im, name):
    im.save(f"{T}/{name}.png"); print("wrote", name, im.size)


# --- palette (RGBA) ---
GRASS1 = (122, 196, 82); GRASS2 = (104, 178, 70); GRASS3 = (142, 210, 96)
DIRT1 = (150, 104, 66); DIRT2 = (128, 86, 52); DIRT3 = (170, 124, 82); DIRTD = (96, 62, 38)
WOOD1 = (176, 120, 70); WOOD2 = (150, 98, 54); WOODD = (104, 64, 34); WOODL = (206, 152, 100)
STONE = (210, 214, 224); STONED = (150, 156, 170)
ANTD = (60, 46, 40); ANTL = (235, 225, 215)   # ant: dark outline + light body (tintable)
INK = (46, 36, 30); WHITE = (255, 255, 255)
YEL = (255, 206, 82); YELD = (222, 166, 44)


def px(d, x, y, c):
    d.point((x, y), fill=c)


# --- background: pixel grass field with blades + tiny flowers ---
def bg():
    W, H = 96, 144
    im = Image.new("RGBA", (W, H), GRASS2 + (255,))
    d = ImageDraw.Draw(im)
    for y in range(H):
        for x in range(W):
            n = (x * 7 + y * 13) % 11
            if n == 0: px(d, x, y, GRASS1 + (255,))
            elif n == 1: px(d, x, y, GRASS3 + (255,))
    # scattered grass blades (2px verticals) + a few flowers
    for i in range(70):
        x = (i * 37 + 5) % W; y = (i * 53 + 11) % H
        d.line([(x, y), (x, y - 2)], fill=GRASS1 + (255,))
    for i in range(10):
        x = (i * 41 + 9) % W; y = (i * 61 + 20) % H
        px(d, x, y, (255, 240, 250, 255)); px(d, x+1, y, (255, 240, 250, 255))
        px(d, x, y+1, (255, 240, 250, 255)); px(d, x+1, y+1, (255, 240, 250, 255))
        px(d, x, y, YEL + (255,))   # flower centre-ish
    save(up(im, (768, 1152)), "game_bg")


# --- 9-slice pixel panel helper: fill + 1px dark outline + top light edge ---
def panel(name, small, target, fill, light, dark, noise=None):
    w, h = small
    im = Image.new("RGBA", (w, h), fill + (255,))
    d = ImageDraw.Draw(im)
    if noise:
        for y in range(h):
            for x in range(w):
                if (x * 5 + y * 9) % 7 == 0: px(d, x, y, noise + (255,))
    d.rectangle([0, 0, w-1, h-1], outline=dark + (255,))          # dark border
    d.line([(1, 1), (w-2, 1)], fill=light + (255,))               # top light edge
    d.line([(1, 1), (1, h-2)], fill=light + (255,))               # left light edge
    save(up(im, target), name)


# --- pixel circle sprite (badge / button) ---
def circle(name, small, target, fill, light, dark):
    n = small
    im = grid(n, n); d = ImageDraw.Draw(im)
    r = n/2 - 0.5; cx = cy = (n-1)/2
    for y in range(n):
        for x in range(n):
            dd = ((x-cx)**2 + (y-cy)**2) ** 0.5
            if dd <= r:
                c = light if (x + y) < n*0.7 else fill
                if dd > r - 1.1: c = dark
                px(d, x, y, c + (255,))
    save(up(im, (target, target)), name)


# --- pixel food block: white body + bevel + outline (tinted per colour) ---
def pixel_tile():
    n = 14
    im = grid(n, n); d = ImageDraw.Draw(im)
    d.rectangle([1, 1, n-2, n-2], fill=(255, 255, 255, 255))
    d.rectangle([0, 0, n-1, n-1], outline=(40, 30, 26, 150))       # dark outline (kept dark by tint)
    d.line([(1, 1), (n-2, 1)], fill=(255, 255, 255, 255))
    d.line([(1, n-2), (n-2, n-2)], fill=(150, 130, 120, 255))      # shaded bottom
    d.line([(n-2, 1), (n-2, n-2)], fill=(150, 130, 120, 255))      # shaded right
    save(up(im, (96, 96)), "pixel_tile")


# --- pixel ant, TOP-DOWN, head UP (0deg faces heading); light body + dark
#     outline so game.set_color tints it to the species colour. 16px. ---
def ant(name):
    n = 16
    im = grid(n, n); d = ImageDraw.Draw(im)
    B = ANTD + (255,); L = ANTL + (255,)
    cx = 8
    # 6 legs first (under the body): 3 pairs splayed out from the thorax
    for (ly, dy) in [(5, -2), (8, 0), (11, 2)]:
        d.line([(cx-1, ly), (cx-4, ly+dy)], fill=B)
        d.line([(cx, ly), (cx+3, ly+dy)], fill=B)
    # body: abdomen (bottom, big), thorax (mid), head (top)
    d.ellipse([cx-3, 9, cx+2, 14], fill=L, outline=B)     # abdomen
    d.ellipse([cx-2, 6, cx+1, 9], fill=L, outline=B)      # thorax
    d.ellipse([cx-2, 2, cx+1, 6], fill=L, outline=B)      # head
    # eyes + antennae
    px(d, cx-2, 3, B); px(d, cx+1, 3, B)
    d.line([(cx-1, 2), (cx-3, 0)], fill=B); d.line([(cx, 2), (cx+2, 0)], fill=B)
    save(up(im, (128, 128)), name)


# --- pixel ant TOKEN: species-colour tile + small dark ant ---
def ant_token(food, tile):
    n = 32
    im = grid(n, n); d = ImageDraw.Draw(im)
    d.rectangle([2, 2, n-3, n-3], fill=tile + (255,), outline=tuple(int(c*0.6) for c in tile) + (255,))
    d.line([(3, 3), (n-4, 3)], fill=tuple(min(255, int(c*1.15)) for c in tile) + (255,))
    # small dark ant, contrast to tile
    lum = 0.3*tile[0] + 0.6*tile[1] + 0.1*tile[2]
    a = INK if lum > 150 else (240, 232, 224)
    ac = a + (255,)
    for (bx, by, rr) in [(11, 16, 2), (16, 16, 2), (21, 16, 3)]:
        d.ellipse([bx-rr, by-rr, bx+rr, by+rr], fill=ac)
    for lx in (12, 16, 20):
        d.line([(lx, 19), (lx-3, 23)], fill=ac); d.line([(lx, 19), (lx+3, 23)], fill=ac)
    d.line([(9, 13), (6, 9)], fill=ac); d.line([(11, 13), (8, 9)], fill=ac)
    save(up(im, (256, 256)), f"antkind_{food}")


# --- pixel nest hole: dark hole in a dirt mound ---
def hole():
    n = 32
    im = grid(n, n); d = ImageDraw.Draw(im)
    d.ellipse([1, 4, n-2, n-2], fill=DIRT2 + (255,), outline=DIRTD + (255,))   # mound
    d.ellipse([3, 6, n-4, n-4], fill=DIRT1 + (255,))
    d.ellipse([7, 9, n-8, n-4], fill=(38, 26, 22, 255))                         # dark hole
    d.ellipse([9, 10, n-10, n-8], fill=(20, 12, 10, 255))
    save(up(im, (256, 256)), "hole")


# --- plain pixel square (grooves / badges), tintable white ---
def tile_sq():
    im = Image.new("RGBA", (8, 8), (255, 255, 255, 255))
    save(up(im, (64, 64)), "tile_sq")


# --- pixel icons (16px) ---
def icon_star():
    n = 16; im = grid(n, n); d = ImageDraw.Draw(im)
    pts = [(8,1),(10,6),(15,6),(11,9),(13,15),(8,11),(3,15),(5,9),(1,6),(6,6)]
    d.polygon(pts, fill=(255, 255, 255, 255))
    save(up(im, (128, 128)), "icon_star")


def icon_coin():
    n = 16; im = grid(n, n); d = ImageDraw.Draw(im)
    d.ellipse([2, 2, n-3, n-3], fill=YEL + (255,), outline=YELD + (255,))
    d.ellipse([5, 5, n-6, n-6], outline=YELD + (255,))
    save(up(im, (128, 128)), "icon_coin")


def icon_back():
    n = 16; im = grid(n, n); d = ImageDraw.Draw(im)
    d.line([(10, 3), (5, 8), (10, 13)], fill=INK + (255,), width=2, joint="curve")
    save(up(im, (128, 128)), "icon_back")


def icon_sound():
    n = 16; im = grid(n, n); d = ImageDraw.Draw(im)
    d.polygon([(4,6),(7,6),(10,3),(10,13),(7,10),(4,10)], fill=INK + (255,))
    d.line([(11,5),(13,7)], fill=INK + (255,)); d.line([(11,11),(13,9)], fill=INK + (255,))
    save(up(im, (128, 128)), "icon_sound")


# --- pixel leaf / petal drifters ---
def leaf():
    im = grid(8, 8); d = ImageDraw.Draw(im)
    d.ellipse([1, 2, 6, 5], fill=GRASS3 + (255,), outline=GRASS2 + (255,))
    save(up(im, (64, 64)), "leaf")


def petal():
    im = grid(8, 8); d = ImageDraw.Draw(im)
    d.ellipse([1, 2, 6, 5], fill=(255, 200, 220, 255), outline=(230, 160, 190, 255))
    save(up(im, (64, 64)), "petal")


FOODS = {
    "choc": (110, 70, 44), "bread": (240, 150, 40),
    "sugar": (250, 236, 205), "berry": (240, 90, 120), "mint": (90, 205, 170),
}

if __name__ == "__main__":
    bg()
    panel("soil_plot", (64, 64), (512, 512), DIRT1, DIRT3, DIRTD, noise=DIRT2)
    panel("bar_wood", (46, 16), (368, 128), WOOD1, WOODL, WOODD, noise=WOOD2)
    panel("tray_wood", (64, 64), (512, 512), WOOD1, WOODL, WOODD, noise=WOOD2)
    circle("badge_wood", 24, 192, YEL, (255, 226, 130), YELD)
    pixel_tile(); tile_sq(); hole()
    ant("ant_walk")
    for f, c in FOODS.items():
        ant_token(f, c)
    icon_star(); icon_coin(); icon_back(); icon_sound(); leaf(); petal()
    print("pixel kit done")
