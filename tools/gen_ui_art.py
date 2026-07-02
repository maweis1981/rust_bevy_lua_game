#!/usr/bin/env python3
"""Draw art-styled UI sprites with PIL (no AI needed): a bitmap number font,
a home/back button, butterflies and a drifting petal. Output -> assets/textures/.

Numbers are rendered from the bundled rounded font as a monospaced glyph set
(0-9 plus '/' and 'x') with a soft outline + drop shadow — the game-standard
"sprite number" approach, so the HUD can lay them out as sprites.
"""
import os
from PIL import Image, ImageDraw, ImageFont, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "assets", "textures")
FONT = os.path.join(HERE, "..", "assets", "fonts", "game.ttf")

GLYPH_W, GLYPH_H, PAD, FS = 40, 60, 12, 56
FILL = (253, 247, 224)
OUTLINE = (70, 46, 26)


def glyph(ch, name):
    W, H = GLYPH_W + PAD * 2, GLYPH_H + PAD * 2
    f = ImageFont.truetype(FONT, FS)
    im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    bb = d.textbbox((0, 0), ch, font=f, stroke_width=5)
    x = (W - (bb[2] - bb[0])) / 2 - bb[0]
    y = (H - (bb[3] - bb[1])) / 2 - bb[1]
    sh = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(sh).text((x, y + 3), ch, font=f, fill=(0, 0, 0, 130),
                            stroke_width=5, stroke_fill=(0, 0, 0, 130))
    im = Image.alpha_composite(im, sh.filter(ImageFilter.GaussianBlur(2)))
    ImageDraw.Draw(im).text((x, y), ch, font=f, fill=FILL, stroke_width=5, stroke_fill=OUTLINE)
    im.save(os.path.join(OUT, name + ".png"))


def rrect(d, box, r, **kw):
    d.rounded_rectangle(box, radius=r, **kw)


def back_button():
    # A cozy rounded wood button with a white house glyph (return to the lobby).
    W, H = 168, 96
    im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    rrect(d, (6, 8, W - 6, H - 6), 26, fill=(150, 104, 60), outline=(74, 46, 24), width=6)
    rrect(d, (12, 6, W - 12, H - 20), 22, fill=(190, 140, 84))       # top bevel highlight
    # left chevron
    d.polygon([(44, H // 2), (68, H // 2 - 20), (68, H // 2 + 20)], fill=(255, 252, 244), outline=(74, 46, 24))
    # little house (lobby)
    cx = 118
    d.polygon([(cx - 26, 54), (cx, 30), (cx + 26, 54)], fill=(255, 252, 244), outline=(74, 46, 24))
    rrect(d, (cx - 18, 52, cx + 18, 74), 4, fill=(255, 252, 244), outline=(74, 46, 24), width=3)
    rrect(d, (cx - 6, 60, cx + 6, 74), 2, fill=(150, 104, 60))       # door
    im.save(os.path.join(OUT, "btn_back.png"))


def butterfly(name, wing, spot):
    W, H = 96, 84
    im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    outline = (60, 40, 28)
    # upper wings
    d.ellipse((10, 8, 46, 46), fill=wing, outline=outline, width=3)
    d.ellipse((50, 8, 86, 46), fill=wing, outline=outline, width=3)
    # lower wings (smaller)
    d.ellipse((16, 40, 46, 72), fill=wing, outline=outline, width=3)
    d.ellipse((50, 40, 80, 72), fill=wing, outline=outline, width=3)
    # spots
    d.ellipse((22, 18, 34, 30), fill=spot)
    d.ellipse((62, 18, 74, 30), fill=spot)
    # body
    d.ellipse((44, 14, 52, 66), fill=(52, 36, 30), outline=outline, width=2)
    # antennae
    d.line((46, 16, 38, 4), fill=outline, width=3); d.ellipse((34, 0, 40, 6), fill=outline)
    d.line((50, 16, 58, 4), fill=outline, width=3); d.ellipse((56, 0, 62, 6), fill=outline)
    im.save(os.path.join(OUT, name + ".png"))


def petal():
    W = 40
    im = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.ellipse((8, 4, 32, 36), fill=(255, 200, 220), outline=(224, 150, 176), width=2)
    d.ellipse((14, 10, 26, 26), fill=(255, 224, 236))
    im.save(os.path.join(OUT, "petal.png"))


if __name__ == "__main__":
    for i in range(10):
        glyph(str(i), "num_" + str(i))
    glyph("/", "num_slash")
    glyph("x", "num_x")
    back_button()
    butterfly("butterfly1", (255, 176, 206), (214, 120, 158))
    butterfly("butterfly2", (170, 200, 255), (120, 150, 224))
    petal()
    print("wrote number glyphs, btn_back, butterfly1/2, petal")
