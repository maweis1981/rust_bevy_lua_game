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


# --- background: themed pixel field. One recipe (base + speckle + tufts + a few
#     accent decos) recoloured per biome, so the levels read as a JOURNEY —
#     meadow -> forest -> autumn -> desert -> snow — a sense of level progression
#     while the chunky-pixel style stays identical. `game_bg` stays the level-1
#     meadow (unchanged look); bg_2..5 are the later biomes. ---
def bg(name, base, light, hi, tuft, decos):
    """decos: list of (color, is2x) accent dots (flowers/leaves/stones/sparkles)."""
    W, H = 96, 144
    im = Image.new("RGBA", (W, H), base + (255,))
    d = ImageDraw.Draw(im)
    for y in range(H):
        for x in range(W):
            n = (x * 7 + y * 13) % 11
            if n == 0: px(d, x, y, light + (255,))
            elif n == 1: px(d, x, y, hi + (255,))
    if tuft:  # short 2px verticals = grass blades / ground texture strokes
        for i in range(70):
            x = (i * 37 + 5) % W; y = (i * 53 + 11) % H
            d.line([(x, y), (x, y - 2)], fill=tuft + (255,))
    # scattered accent decorations, cycled through the biome's deco palette
    for i in range(14):
        x = (i * 41 + 9) % W; y = (i * 61 + 20) % H
        col, big = decos[i % len(decos)]
        px(d, x, y, col + (255,))
        if big:
            px(d, x+1, y, col + (255,)); px(d, x, y+1, col + (255,)); px(d, x+1, y+1, col + (255,))
    save(up(im, (768, 1152)), name)


# --- full-screen pixel BORDER frame (a chunky wooden bezel with rounded corners
#     + light bevel, transparent centre). Drawn at the portrait screen aspect so
#     scaling keeps the border a uniform thickness on all four sides. Overlaid on
#     top of the play field so the game is nicely enclosed on every edge. ---
def frame():
    W, H = 100, 214            # ~ portrait screen aspect (0.467)
    im = grid(W, H); d = ImageDraw.Draw(im)
    def rr(inset, rad, fill):
        d.rounded_rectangle([inset, inset, W - 1 - inset, H - 1 - inset], rad, fill=fill + (255,))
    rr(0, 9, WOODD)            # outer dark outline
    rr(1, 8, WOOD1)            # wood band
    rr(2, 7, WOODL)            # top light bevel
    rr(3, 6, WOOD2)            # inner wood
    # punch the transparent play window (~4px border => ~18px on screen)
    d.rounded_rectangle([4, 4, W - 5, H - 5], 4, fill=(0, 0, 0, 0))
    save(up(im, (800, 1712)), "game_frame")


BIOMES = [
    # level 1 — meadow (the original look): bright grass + white/yellow flowers
    ("game_bg",   GRASS2, GRASS1, GRASS3, GRASS1,
     [((255, 240, 250), True), ((255, 206, 82), False)]),
    # level 2 — forest: deeper greens, denser tufts, tiny blue/violet blooms
    ("bg_forest", (66, 128, 58), (82, 146, 70), (100, 164, 84), (54, 110, 50),
     [((120, 150, 235), False), ((210, 160, 235), False), ((150, 190, 96), True)]),
    # level 3 — autumn: olive-tan grass with fallen orange/red leaves
    ("bg_autumn", (150, 150, 78), (168, 166, 92), (186, 182, 108), (132, 132, 68),
     [((222, 118, 46), True), ((196, 70, 50), False), ((236, 176, 70), False)]),
    # level 4 — desert: warm sand, scattered pebbles + tiny cactus dots
    ("bg_desert", (214, 178, 118), (228, 196, 140), (240, 210, 158), None,
     [((176, 150, 108), True), ((150, 130, 96), False), ((110, 170, 96), False)]),
    # level 5 — snow: pale blue-white drifts, icy sparkles + snow tufts
    ("bg_snow", (216, 228, 240), (232, 242, 250), (246, 250, 253), (200, 214, 232),
     [((255, 255, 255), True), ((150, 195, 235), False), ((198, 220, 244), False)]),
    # level 6 — beach: warm sand with turquoise water flecks + shells
    ("bg_beach", (232, 208, 156), (244, 224, 176), (250, 234, 192), None,
     [((90, 190, 200), True), ((60, 160, 185), False), ((255, 240, 220), False)]),
    # level 7 — candyland: bubblegum pinks + pastel sprinkles
    ("bg_candy", (236, 168, 196), (246, 186, 210), (250, 202, 222), None,
     [((255, 255, 255), False), ((150, 210, 235), False), ((255, 230, 150), False)]),
    # level 8 — twilight: deep indigo dusk with tiny stars
    ("bg_night", (54, 52, 96), (66, 64, 116), (80, 78, 138), (44, 42, 80),
     [((255, 250, 210), False), ((190, 200, 255), False), ((150, 150, 220), True)]),
    # level 9 — cave: cool grey stone with darker rubble speckle
    ("bg_cave", (108, 108, 120), (124, 124, 138), (140, 140, 154), (90, 90, 102),
     [((70, 70, 82), True), ((150, 150, 168), False), ((90, 130, 120), False)]),
    # level 10 — volcano: charcoal rock glowing with ember flecks
    ("bg_lava", (58, 46, 46), (74, 58, 56), (92, 72, 68), (44, 34, 34),
     [((255, 130, 40), False), ((230, 70, 30), True), ((255, 200, 90), False)]),
]


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


# --- pixel ant, TOP-DOWN, head UP (0deg faces heading). Drawn in LUMINANCE
#     (bright body / mid shade / dark outline+eyes) so game.set_color multiplies
#     it to the species hue while the outline & eyes stay dark and the highlight
#     reads as a sheen. Detailed like the reference: 3 clear body segments, a
#     pinched waist, six jointed legs, bent antennae + mandibles. 24px src. ---
def ant(name):
    n = 24
    im = grid(n, n); d = ImageDraw.Draw(im)
    B = (54, 43, 38, 255)          # dark outline (stays dark under any tint)
    L = (236, 228, 220, 255)       # light body (takes the tint)
    S = (168, 158, 150, 255)       # mid shade (tints to a darker hue)
    H = (252, 250, 248, 255)       # highlight sheen
    E = (30, 24, 22, 255)          # eyes / mandibles (stay dark)
    cx = 12
    # --- six jointed legs first (drawn under the body) ---
    #     each: body-anchor -> knee -> foot, mirrored across cx. Front pair
    #     reaches forward, mid pair straight out, rear pair sweeps back.
    legs = [((10, 9), (6, 6), (3, 4)),      # front
            ((10, 12), (5, 12), (2, 13)),   # middle
            ((10, 15), (6, 17), (3, 20))]   # rear
    for side in (-1, 1):
        for (a0, k, f) in legs:
            ax = cx + side * (a0[0] - cx); kx = cx + side * (k[0] - cx); fx = cx + side * (f[0] - cx)
            d.line([(ax, a0[1]), (kx, k[1])], fill=B, width=1)
            d.line([(kx, k[1]), (fx, f[1])], fill=B, width=1)
            px(d, fx, f[1], E)     # dark foot tip
    # --- antennae: from the head, angle out then bend forward ---
    for side in (-1, 1):
        b0 = (cx + side * 1, 4); b1 = (cx + side * 4, 1); b2 = (cx + side * 5, -1)
        d.line([b0, b1], fill=B, width=1); d.line([b1, b2], fill=B, width=1)
        px(d, b2[0], max(0, b2[1]), E)
    # --- mandibles: two dark forks reaching up off the head ---
    d.line([(cx - 1, 3), (cx - 3, 0)], fill=E); d.line([(cx + 1, 3), (cx + 3, 0)], fill=E)
    # --- body: abdomen (big teardrop) -> pinched waist -> thorax -> head ---
    d.ellipse([cx - 4, 13, cx + 3, 22], fill=L, outline=B)   # abdomen
    d.ellipse([cx - 2, 11, cx + 1, 14], fill=S, outline=B)   # petiole / waist
    d.ellipse([cx - 3, 6, cx + 2, 12], fill=L, outline=B)    # thorax
    d.ellipse([cx - 3, 1, cx + 2, 7], fill=L, outline=B)     # head
    # segment seams (mid-shade) so the 3 parts read distinctly
    d.line([(cx - 3, 13), (cx + 2, 13)], fill=S)             # abdomen shoulder
    d.line([(cx - 4, 17), (cx + 3, 17)], fill=S)             # abdomen belt
    # eyes on the head
    px(d, cx - 2, 4, E); px(d, cx - 2, 5, E)
    px(d, cx + 1, 4, E); px(d, cx + 1, 5, E)
    # sheen: highlight top-left of head & abdomen (reads as a glossy back)
    px(d, cx - 2, 2, H); px(d, cx - 1, 2, H)
    px(d, cx - 3, 15, H); px(d, cx - 2, 15, H); px(d, cx - 3, 16, H)
    save(up(im, (192, 192)), name)


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
    for spec in BIOMES:
        bg(*spec)
    frame()
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
