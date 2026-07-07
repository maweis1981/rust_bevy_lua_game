#!/usr/bin/env python3
"""Slot the Floniks-generated showcase art into assets/textures/.

Inputs (raw Floniks outputs, 2048x1152 sheets on magenta/white):
  coin_strip.png    8 cells (2x4): spinning gold coin frames
  robot_strip.png   8 cells (2x4): cutout robot parts (2 cells empty)
  tileset_strip.png 4 tiles in one horizontal band on white

Outputs:
  coin_sheet.png    960x160 RGBA — 6 frames of 160px (game.spawn_sheet)
  tileset.png       640x160 RGB  — 4 tiles of 160px (game.tilemap)
  robot_*.png       RGBA cutout parts for assets/rigs/robot.rig

Usage: showcase_assets.py <raw_dir>   (writes into assets/textures/)
"""
import os
import sys
from PIL import Image, ImageOps

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "textures")


def key_magenta(im):
    """Magenta family (page bg AND the darker card bg) -> transparent."""
    im = im.convert("RGBA")
    px = im.load()
    w, h = im.size
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            # magenta family, including the dark drop-shadow tones: red leads,
            # green clearly below red AND below blue. Gold (g≈r) and the black
            # outline (r≈g≈b) both fail the g<r*0.62 test, so they survive.
            if r > 50 and b > 35 and g < r * 0.62 and g < b * 0.95:
                px[x, y] = (0, 0, 0, 0)
    return im


def crop_content(im, pad=6):
    box = im.getbbox()
    if not box:
        return im
    l, t, r, b = box
    return im.crop((max(0, l - pad), max(0, t - pad), min(im.width, r + pad), min(im.height, b + pad)))


def square_canvas(im, size, fill=0.86):
    """Center the part on a size x size transparent canvas at `fill` scale."""
    target = int(size * fill)
    im = ImageOps.contain(im, (target, target))
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    canvas.paste(im, ((size - im.width) // 2, (size - im.height) // 2), im)
    return canvas


def cells_2x4(im):
    w, h = im.size
    cw, ch = w // 4, h // 2
    return [im.crop((c * cw, r * ch, (c + 1) * cw, (r + 1) * ch)) for r in range(2) for c in range(4)]


def build_coin_sheet(raw):
    sheet = Image.open(os.path.join(raw, "coin_strip.png"))
    cells = [square_canvas(crop_content(key_magenta(c)), 160) for c in cells_2x4(sheet)]
    # 6-frame spin: tilt-left, falling-flat, upright, tilt-right, face-on, star face
    frames = [cells[0], cells[1], cells[2], cells[3], cells[4], cells[7]]
    strip = Image.new("RGBA", (160 * 6, 160), (0, 0, 0, 0))
    for i, f in enumerate(frames):
        strip.paste(f, (i * 160, 0), f)
    strip.save(os.path.join(OUT, "coin_sheet.png"))
    print("coin_sheet.png", strip.size)


def build_robot_parts(raw):
    sheet = Image.open(os.path.join(raw, "robot_strip.png"))
    cells = cells_2x4(sheet)
    head = square_canvas(crop_content(key_magenta(cells[0])), 220, 0.95)
    torso = square_canvas(crop_content(key_magenta(cells[1])), 220, 0.95)
    arm = square_canvas(crop_content(key_magenta(cells[3])), 160, 0.95)   # straight-down arm
    leg = square_canvas(crop_content(key_magenta(cells[6])), 160, 0.95)   # single boot
    parts = {
        "robot_head": head,
        "robot_torso": torso,
        "robot_arm_r": arm,
        "robot_arm_l": ImageOps.mirror(arm),
        "robot_leg_r": leg,
        "robot_leg_l": ImageOps.mirror(leg),
    }
    for name, im in parts.items():
        im.save(os.path.join(OUT, name + ".png"))
        print(name + ".png", im.size)


def build_tileset(raw):
    sheet = Image.open(os.path.join(raw, "tileset_strip.png")).convert("RGB")
    # tiles sit in one band on near-white; find it, then split into 4
    gray = sheet.convert("L")
    mask = gray.point(lambda v: 255 if v < 235 else 0)
    box = mask.getbbox()
    band = sheet.crop(box)
    w, h = band.size
    tw = w // 4
    strip = Image.new("RGB", (160 * 4, 160))
    for i in range(4):
        tile = band.crop((i * tw, 0, (i + 1) * tw, h))
        # inset past the rounded corners / inter-tile gaps so tiles are solid
        inset_x, inset_y = int(tile.width * 0.06), int(tile.height * 0.06)
        tile = tile.crop((inset_x, inset_y, tile.width - inset_x, tile.height - inset_y))
        side = min(tile.width, tile.height)
        tile = tile.crop(((tile.width - side) // 2, (tile.height - side) // 2,
                          (tile.width + side) // 2, (tile.height + side) // 2))
        strip.paste(tile.resize((160, 160), Image.LANCZOS), (i * 160, 0))
    strip.save(os.path.join(OUT, "tileset.png"))
    print("tileset.png", strip.size)


if __name__ == "__main__":
    raw = sys.argv[1]
    build_coin_sheet(raw)
    build_robot_parts(raw)
    build_tileset(raw)
