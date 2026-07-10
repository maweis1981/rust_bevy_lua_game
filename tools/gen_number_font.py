#!/usr/bin/env python3
"""gen_number_font.py — a chunky candy bitmap-digit atlas for Ant Art.

Bakes digits 0-9 into one sprite sheet (assets/textures/num_font.png): each glyph
is a bold rounded number with a thick dark outline, a warm gradient fill and a
soft drop shadow — the "nice styled font on one sheet, used as sprites" the
counts/coins want. The engine spawns it with game.spawn_sheet(..., FW, FH, 10, 10)
and game.set_frame(id, digit). Pillow only.
"""
import os
from PIL import Image, ImageDraw, ImageFont, ImageFilter

SS = 4
FW, FH = 52, 68                      # per-digit frame (px)
FONT = "/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc"
OUT = "assets/textures/num_font.png"

OUTLINE = (74, 46, 30)               # dark warm brown
FILL_TOP = (255, 255, 255)
FILL_BOT = (255, 226, 178)           # warm cream at the bottom (candy gradient)
SHADOW = (60, 40, 24, 120)


def glyph(ch):
    W, H = FW * SS, FH * SS
    im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    try:
        f = ImageFont.truetype(FONT, int(H * 0.82))
    except Exception:
        f = ImageFont.load_default()
    cx, cy = W / 2, H / 2
    sw = int(6 * SS)
    # soft drop shadow
    sh = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(sh).text((cx, cy + 5 * SS), ch, font=f, fill=SHADOW,
                            anchor="mm", stroke_width=sw, stroke_fill=SHADOW)
    sh = sh.filter(ImageFilter.GaussianBlur(3 * SS))
    im.alpha_composite(sh)
    # dark outline
    d.text((cx, cy), ch, font=f, fill=OUTLINE, anchor="mm", stroke_width=sw, stroke_fill=OUTLINE)
    # white/cream gradient fill (draw white, then mask a vertical gradient over it)
    fill = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(fill).text((cx, cy), ch, font=f, fill=(255, 255, 255, 255), anchor="mm")
    grad = Image.new("RGB", (1, H))
    for y in range(H):
        t = y / (H - 1)
        grad.putpixel((0, y), tuple(int(FILL_TOP[i] + (FILL_BOT[i] - FILL_TOP[i]) * t) for i in range(3)))
    grad = grad.resize((W, H))
    fill = Image.composite(grad.convert("RGBA"), Image.new("RGBA", (W, H), (0, 0, 0, 0)), fill.split()[3])
    im.alpha_composite(fill)
    return im.resize((FW, FH), Image.LANCZOS)


def main():
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    sheet = Image.new("RGBA", (FW * 10, FH), (0, 0, 0, 0))
    for i in range(10):
        sheet.paste(glyph(str(i)), (i * FW, 0), glyph(str(i)))
    sheet.save(OUT)
    print(f"wrote {OUT} ({FW*10}x{FH}, 10 digits {FW}x{FH})")
    # preview on a tinted card
    z = 4
    prev = Image.new("RGB", (FW * 10 * z, FH * z), (150, 180, 210))
    big = sheet.resize((FW * 10 * z, FH * z), Image.NEAREST)
    prev.paste(big, (0, 0), big)
    prev.save("build/num_font_preview.png")
    print("wrote build/num_font_preview.png")


if __name__ == "__main__":
    main()
