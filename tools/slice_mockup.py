#!/usr/bin/env python3
"""slice_mockup.py — cut the approved UI concept (our own generated mockup,
build/floniks_src/ui_A.png) into the actual game textures, so the running game
uses the mockup's own pixels (pixel-level fidelity).

Slices (coordinates measured on the 1024x1024 mockup):
  mock_bar.png     the whole top status strip (badge + star groove + coin pill)
  mock_slots.png   the wooden slot strip with its 4 sockets
  mock_tray.png    the big wooden queue tray (inner area gets covered in-game)
  btn_green.png    bottom-left button (shovel)   -> 速度升级
  btn_amber.png    bottom-right button (bomb)    -> 速度x2
  hole.png         the nest hole (feathered ellipse)
  food_*.png       five cube tokens cut from the picture / slot blocks

Live data (digits, progress fill, stars, foods in sockets, queue tiles) is
drawn ON TOP of the baked art at matching fractional positions.
"""
from PIL import Image, ImageDraw, ImageFilter

SRC = "build/floniks_src/ui_A.png"
OUT = "assets/textures"


def rounded(im, radius, feather=2):
    """Apply a rounded-rect alpha mask to `im`."""
    m = Image.new("L", im.size, 0)
    d = ImageDraw.Draw(m)
    d.rounded_rectangle([0, 0, im.width - 1, im.height - 1], radius, fill=255)
    if feather:
        m = m.filter(ImageFilter.GaussianBlur(feather))
    im = im.convert("RGBA")
    im.putalpha(m)
    return im


def ellipse_mask(im, feather=6):
    m = Image.new("L", im.size, 0)
    ImageDraw.Draw(m).ellipse([2, 2, im.width - 3, im.height - 3], fill=255)
    m = m.filter(ImageFilter.GaussianBlur(feather))
    im = im.convert("RGBA")
    im.putalpha(m)
    return im


def main():
    src = Image.open(SRC).convert("RGB")

    def crop(x0, y0, x1, y1):
        return src.crop((x0, y0, x1, y1))

    # --- top status strip: badge(12) + groove/stars + coin pill --------------
    bar = rounded(crop(228, 22, 792, 110), radius=42)
    bar.save(f"{OUT}/mock_bar.png")

    # --- slot strip with 4 sockets ------------------------------------------
    slots = rounded(crop(300, 648, 716, 726), radius=30)
    slots.save(f"{OUT}/mock_slots.png")

    # --- queue tray -----------------------------------------------------------
    tray = rounded(crop(240, 728, 780, 910), radius=34)
    tray.save(f"{OUT}/mock_tray.png")

    # --- bottom buttons -------------------------------------------------------
    rounded(crop(282, 918, 480, 1006), radius=42).save(f"{OUT}/btn_green.png")
    rounded(crop(530, 918, 736, 1006), radius=42).save(f"{OUT}/btn_amber.png")

    # --- nest hole (feathered ellipse so it melts into our soil bg) ----------
    ellipse_mask(crop(415, 492, 600, 626), feather=10).save(f"{OUT}/hole.png")

    # --- cube tokens: 4 matte picture cubes + the slot red block --------------
    # picture cell size ~27px; pick clean cells (measured on the grid overlay)
    # cube tokens: auto-find the flattest window matching each colour inside the
    # picture area, so the crop lands INSIDE one cell (never on a grid junction)
    def best_window(target, region, win=18, step=2):
        rx0, ry0, rx1, ry1 = region
        px = src.load()
        best, best_score = None, None
        for y in range(ry0, ry1 - win, step):
            for x in range(rx0, rx1 - win, step):
                sr = sg = sb = 0
                srr = sgg = sbb = 0
                n = 0
                for j in range(0, win, 3):
                    for i in range(0, win, 3):
                        r, g, b = px[x + i, y + j]
                        sr += r; sg += g; sb += b
                        srr += r * r; sgg += g * g; sbb += b * b
                        n += 1
                mr, mg, mb = sr / n, sg / n, sb / n
                var = (srr / n - mr * mr) + (sgg / n - mg * mg) + (sbb / n - mb * mb)
                dist = (mr - target[0]) ** 2 + (mg - target[1]) ** 2 + (mb - target[2]) ** 2
                score = dist + var * 2.0          # flat + on-colour
                if best_score is None or score < best_score:
                    best_score, best = score, (x, y)
        return best

    PIC = (312, 140, 700, 452)
    targets = {
        "food_mint":  (150, 160, 75),
        "food_bread": (205, 95, 45),
        "food_sugar": (238, 210, 175),
        "food_choc":  (62, 44, 34),
    }
    for name, t in targets.items():
        x, y = best_window(t, PIC)
        rounded(crop(x, y, x + 18, y + 18), radius=5, feather=1).resize((96, 96), Image.LANCZOS)\
            .save(f"{OUT}/{name}.png")
        print(name, "->", (x, y))
    # red block from the slot socket (inside the glossy block face)
    rounded(crop(528, 672, 566, 708), radius=8, feather=1).resize((96, 96), Image.LANCZOS)\
        .save(f"{OUT}/food_berry.png")

    # contact sheet for review
    names = ["mock_bar", "mock_slots", "mock_tray", "btn_green", "btn_amber", "hole",
             "food_mint", "food_bread", "food_sugar", "food_choc", "food_berry"]
    tiles = [Image.open(f"{OUT}/{n}.png") for n in names]
    W = max(t.width for t in tiles) + 20
    H = sum(min(t.height, 200) for t in tiles) + 20 * len(tiles)
    sheet = Image.new("RGB", (W, H), (40, 36, 32))
    y = 10
    for t in tiles:
        if t.height > 200:
            t = t.resize((int(t.width * 200 / t.height), 200), Image.LANCZOS)
        if t.width > W - 20:
            t = t.resize((W - 20, int(t.height * (W - 20) / t.width)), Image.LANCZOS)
        sheet.paste(t, (10, y), t)
        y += t.height + 20
    sheet.save("build/mock_slices.png")
    print("wrote", len(names), "slices + build/mock_slices.png")


if __name__ == "__main__":
    main()
