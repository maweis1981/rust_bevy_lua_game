#!/usr/bin/env python3
"""gen_ant_sheet.py — a top-down worker-ant walk-cycle sprite sheet for Ant Art.

Redrawn to read unmistakably as an ANT (🐜 as the north star): three clearly
SEPARATED body segments — round head, small thorax, big pointed teardrop abdomen —
joined by a thin pinched waist (the petiole, an ant's signature), six bold bent
legs in a tripod gait, and two antennae. Pointing UP (+y) across N frames; the
engine rotates the whole sprite to face its travel direction (set_rotation), so
one upward cycle covers every heading.

The body is LIGHT so the engine's set_color tints each ant to its slot colour
(a red slot -> red ants); the legs, antennae, eyes and the outline stay DARK so a
tinted ant still reads as a segmented, six-legged ant on any background.

Writes assets/textures/ant_sheet.png (+ ant_icon.png, + a zoomed preview). Pillow.
"""
import math
import os
import sys

from PIL import Image, ImageDraw

FRAMES = 8
CELL = 48                     # px per frame in the sheet
SS = 5                        # supersample
OUT = "assets/textures/ant_sheet.png"

BODY = (236, 230, 224)        # light body (takes the tint)
BODY_HI = (255, 253, 250)     # rim light / sheen
BODY_LO = (198, 188, 180)     # segment shading (still tints)
LEG = (38, 27, 22)            # dark legs (stay dark after the colour multiply)
EYE = (20, 14, 12)
OUTLINE = (28, 19, 15)        # dark rim -> silhouette holds on any background


def oval(dr, cx, cy, rx, ry, fill):
    dr.ellipse([cx - rx, cy - ry, cx + rx, cy + ry], fill=fill)


def draw_ant(im, phase):
    """One ant frame, centred, pointing up (−y = forward). `phase` drives the gait."""
    big = Image.new("RGBA", (CELL * SS, CELL * SS), (0, 0, 0, 0))
    dr = ImageDraw.Draw(big)
    cx, cy = CELL * SS / 2, CELL * SS / 2
    u = SS

    # segment centres along the body axis (head up, abdomen down). Gaps + a
    # narrow petiole between thorax and abdomen make the ant's PINCHED WAIST read.
    head_y = cy - 13.0 * u
    thorax_y = cy - 4.5 * u
    waist_y = cy + 1.5 * u
    abdo_y = cy + 11.5 * u

    swing = math.sin(phase * 2 * math.pi)          # −1..1 gait phase

    # --- legs (6): three per side from the thorax, long + bold with an elbow ----
    def leg(side, row, tripod):
        ax = cx + side * 3.2 * u                    # hip on the thorax
        ay = thorax_y + (row - 1) * 3.2 * u
        s = swing if tripod == 0 else -swing
        splay = (1.5, 0.2, -1.15)[row]             # front fwd, mid out, rear back
        reach = 13.0 * u
        fx = ax + side * reach
        fy = ay + splay * 5.0 * u - s * 3.4 * u     # foot swings fore/aft
        kx = ax + side * reach * 0.52               # elbow, kicked up a bit
        ky = ay + splay * 2.4 * u - s * 1.4 * u - 2.2 * u
        dr.line([ax, ay, kx, ky, fx, fy], fill=LEG,
                width=max(2, int(2.1 * u)), joint="curve")
        oval(dr, fx, fy, 1.4 * u, 1.4 * u, LEG)     # little foot
    for row, tri in ((0, 0), (1, 1), (2, 0)):
        leg(-1, row, tri)
    for row, tri in ((0, 1), (1, 0), (2, 1)):
        leg(1, row, tri)

    # --- antennae: bent, wiggling, reaching up/out -----------------------------
    wig = swing * 1.6 * u
    for side in (-1, 1):
        bx, by = cx + side * 2.0 * u, head_y - 3.2 * u
        mx, my = cx + side * 4.4 * u, head_y - 7.0 * u
        tx, ty = cx + side * 6.0 * u + wig * side, head_y - 10.5 * u
        dr.line([bx, by, mx, my, tx, ty], fill=LEG,
                width=max(1, int(1.4 * u)), joint="curve")
        oval(dr, tx, ty, 1.3 * u, 1.3 * u, LEG)     # clubbed tip

    # --- mandibles (two little dark prongs at the front of the head) ------------
    for side in (-1, 1):
        dr.line([cx + side * 2.4 * u, head_y - 4.0 * u,
                 cx + side * 3.8 * u, head_y - 6.2 * u],
                fill=LEG, width=max(1, int(1.4 * u)))

    # --- dark OUTLINE behind every body part (draw fat, fill on top) ------------
    o = 2.0 * u
    # petiole (the pinched waist) — thin connector, drawn first so segments sit over it
    oval(dr, cx, waist_y, 1.7 * u + o, 3.2 * u + o, OUTLINE)
    oval(dr, cx, abdo_y, 8.8 * u + o, 11.0 * u + o, OUTLINE)
    # pointed tail of the abdomen
    dr.polygon([(cx - (3.0 * u + o), abdo_y + 8.0 * u),
                (cx + (3.0 * u + o), abdo_y + 8.0 * u),
                (cx, abdo_y + 13.5 * u + o)], fill=OUTLINE)
    oval(dr, cx, thorax_y, 4.1 * u + o, 5.0 * u + o, OUTLINE)
    oval(dr, cx, head_y, 6.4 * u + o, 6.0 * u + o, OUTLINE)

    # --- body fills: back-to-front so the head sits on top ----------------------
    oval(dr, cx, waist_y, 1.7 * u, 3.2 * u, BODY_LO)                 # petiole
    # abdomen (big teardrop): ellipse + pointed tail
    dr.polygon([(cx - 3.0 * u, abdo_y + 8.0 * u),
                (cx + 3.0 * u, abdo_y + 8.0 * u),
                (cx, abdo_y + 13.5 * u)], fill=BODY)
    oval(dr, cx, abdo_y, 8.8 * u, 11.0 * u, BODY)
    oval(dr, cx, abdo_y - 3.0 * u, 5.6 * u, 6.4 * u, BODY_HI)        # sheen
    oval(dr, cx, abdo_y - 3.0 * u, 4.7 * u, 5.4 * u, BODY)
    oval(dr, cx, thorax_y, 4.1 * u, 5.0 * u, BODY)                   # thorax
    oval(dr, cx, thorax_y - 1.0 * u, 2.3 * u, 2.8 * u, BODY_HI)
    oval(dr, cx, thorax_y - 1.0 * u, 1.8 * u, 2.3 * u, BODY)
    oval(dr, cx, head_y, 6.4 * u, 6.0 * u, BODY)                     # head
    oval(dr, cx, head_y - 1.2 * u, 3.8 * u, 3.1 * u, BODY_HI)        # head sheen
    oval(dr, cx, head_y - 1.2 * u, 3.0 * u, 2.4 * u, BODY)
    # eyes
    for side in (-1, 1):
        oval(dr, cx + side * 3.1 * u, head_y - 0.6 * u, 1.2 * u, 1.5 * u, EYE)

    im.alpha_composite(big.resize((CELL, CELL), Image.LANCZOS))


def main():
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    sheet = Image.new("RGBA", (CELL * FRAMES, CELL), (0, 0, 0, 0))
    for i in range(FRAMES):
        frame = Image.new("RGBA", (CELL, CELL), (0, 0, 0, 0))
        draw_ant(frame, i / FRAMES)
        sheet.paste(frame, (i * CELL, 0), frame)
    sheet.save(OUT)
    print(f"wrote {OUT}  ({CELL*FRAMES}x{CELL}, {FRAMES} frames)")

    icon = Image.new("RGBA", (CELL, CELL), (0, 0, 0, 0))
    draw_ant(icon, 0.0)
    icon.save("assets/textures/ant_icon.png")
    print("wrote assets/textures/ant_icon.png")

    # zoomed preview strip on a light card for review
    z = 6
    big = sheet.resize((CELL * FRAMES * z, CELL * z), Image.NEAREST)
    prev = Image.new("RGB", (CELL * FRAMES * z, CELL * z), (238, 230, 216))
    prev.paste(big, (0, 0), big)
    pv = sys.argv[1] if len(sys.argv) > 1 else "build/ant_sheet_preview.png"
    os.makedirs(os.path.dirname(pv), exist_ok=True)
    prev.save(pv)
    print(f"wrote {pv}")


if __name__ == "__main__":
    main()
