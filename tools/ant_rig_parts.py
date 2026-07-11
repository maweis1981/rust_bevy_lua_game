#!/usr/bin/env python3
"""ant_rig_parts.py — split the ant into skeletal-rig parts (body + leg).

The walking ant is a rig (assets/rigs/ant.rig): a BODY part (the luminance
master with its baked legs erased via a three-ellipse body mask) and six
instances of one LEG part (a dark bent capsule with a foot), swung by the
rig's tripod-gait clip. Body stays light so species tinting works; the leg
stays dark so it survives the multiply like before.

Output: assets/textures/ant_body.png (96x160), assets/textures/ant_leg.png
(28x64, pivot at the top = hip). Preview build/ant_rig_parts.png.
"""
from PIL import Image, ImageDraw, ImageFilter

SRC = "assets/textures/ant_hero.png"     # luminance master (160x160, ant centred, up)


def body():
    im = Image.open(SRC).convert("RGBA")
    w, h = im.size
    # body mask: head / thorax / abdomen ellipses + antennae corridor above head.
    # Tuned against the master's centred, upward-facing layout.
    m = Image.new("L", im.size, 0)
    d = ImageDraw.Draw(m)
    cx = w / 2
    d.ellipse([cx - 27, 16, cx + 27, 66], fill=255)          # head
    d.ellipse([cx - 20, 58, cx + 20, 102], fill=255)         # thorax
    d.ellipse([cx - 31, 92, cx + 31, 152], fill=255)         # abdomen
    d.polygon([(cx - 24, 30), (cx - 44, 0), (cx - 30, 0), (cx - 12, 26)], fill=255)  # antenna L
    d.polygon([(cx + 24, 30), (cx + 44, 0), (cx + 30, 0), (cx + 12, 26)], fill=255)  # antenna R
    m = m.filter(ImageFilter.GaussianBlur(1.5))
    r, g, b, a = im.split()
    from PIL import ImageChops
    a = ImageChops.multiply(a, m)
    out = Image.merge("RGBA", (r, g, b, a))
    # crop to content + a margin, keep centred horizontally
    bb = out.getbbox()
    pad = 6
    out = out.crop((max(0, bb[0] - pad), max(0, bb[1] - pad),
                    min(w, bb[2] + pad), min(h, bb[3] + pad)))
    out.save("assets/textures/ant_body.png")
    return out


def leg():
    # a dark bent capsule: hip at the TOP-CENTRE (pivot), knee kink, foot dot
    W, H, SS = 28, 64, 4
    im = Image.new("RGBA", (W * SS, H * SS), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    C = (48, 34, 27, 255)
    hip = (W * SS / 2, 4 * SS)
    knee = (W * SS / 2 + 4 * SS, H * SS * 0.52)
    foot = (W * SS / 2 - 2 * SS, H * SS - 7 * SS)
    d.line([hip, knee, foot], fill=C, width=7 * SS, joint="curve")
    d.ellipse([foot[0] - 5 * SS, foot[1] - 5 * SS, foot[0] + 5 * SS, foot[1] + 5 * SS], fill=C)
    d.ellipse([hip[0] - 4 * SS, hip[1] - 4 * SS, hip[0] + 4 * SS, hip[1] + 4 * SS], fill=C)
    out = im.resize((W, H), Image.LANCZOS)
    out.save("assets/textures/ant_leg.png")
    return out


def main():
    b = body()
    l = leg()
    card = Image.new("RGB", (b.width * 2 + l.width * 2 + 40, max(b.height, l.height) + 20),
                     (150, 108, 70))
    card.paste(b, (10, 10), b)
    card.paste(l, (b.width + 20, 10), l)
    card.save("build/ant_rig_parts.png")
    print("wrote ant_body", b.size, "ant_leg", l.size, "+ preview")


if __name__ == "__main__":
    main()
