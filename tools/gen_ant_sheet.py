#!/usr/bin/env python3
"""gen_ant_sheet.py — a top-down ant walk-cycle sprite sheet for Ant Art.

Draws a clean top-down worker ant (head + thorax + abdomen, antennae, six legs)
pointing UP (+y), across N frames of a tripod-gait walk cycle: the legs swing
fore/aft in two alternating tripods so the ant reads as *walking* when the frame
cycles. The engine spawns it with game.spawn_sheet(...,"ant_sheet",N,N) and
rotates the whole sprite to face its travel direction (set_rotation), so one
upward-facing cycle covers every heading.

Writes assets/textures/ant_sheet.png (single row of N frames) plus a zoomed
preview strip for review. Pillow only.
"""
import math
import os
import sys

from PIL import Image, ImageDraw

FRAMES = 8
CELL = 48                     # px per frame in the sheet
OUT = "assets/textures/ant_sheet.png"

BODY = (34, 26, 24)           # near-black brown
BODY_HI = (70, 54, 48)        # rim light
LEG = (24, 18, 16)
EYE = (12, 9, 8)


def ellipse(dr, cx, cy, rx, ry, fill):
    dr.ellipse([cx - rx, cy - ry, cx + rx, cy + ry], fill=fill)


def draw_ant(im, phase):
    """Draw one ant frame centred, pointing up. `phase` in [0,1) drives the gait."""
    SS = 4
    big = Image.new("RGBA", (CELL * SS, CELL * SS), (0, 0, 0, 0))
    dr = ImageDraw.Draw(big)
    cx, cy = CELL * SS / 2, CELL * SS / 2
    u = SS                      # unit scale helper

    # body axis: head up (−y), abdomen down (+y)
    head_y = cy - 11 * u
    thorax_y = cy - 1 * u
    abdo_y = cy + 11 * u

    # --- legs (6): three per side, tripod gait -------------------------------
    # Tripod A = L1,R2,L3 ; Tripod B = R1,L2,R3. Each leg swings fore/aft.
    swing = math.sin(phase * 2 * math.pi)          # −1..1
    def leg(side, row, tripod):
        # anchor on the thorax
        ax = cx + side * 3.2 * u
        ay = thorax_y + (row - 1) * 4.2 * u
        s = swing if tripod == 0 else -swing
        # foot reaches out to the side and swings along the body axis
        reach = 9.0 * u
        fx = ax + side * reach
        fy = ay - s * 5.0 * u
        # knee kink
        kx = ax + side * reach * 0.55
        ky = ay - s * 2.0 * u - 1.5 * u
        dr.line([ax, ay, kx, ky, fx, fy], fill=LEG, width=max(2, int(1.6 * u)), joint="curve")
        dr.ellipse([fx - 1.2 * u, fy - 1.2 * u, fx + 1.2 * u, fy + 1.2 * u], fill=LEG)
    for row, tri in ((0, 0), (1, 1), (2, 0)):
        leg(-1, row, tri)
    for row, tri in ((0, 1), (1, 0), (2, 1)):
        leg(1, row, tri)

    # --- antennae ------------------------------------------------------------
    wig = math.sin(phase * 2 * math.pi) * 1.5 * u
    for side in (-1, 1):
        bx, by = cx + side * 1.8 * u, head_y - 3.0 * u
        tx, ty = cx + side * 4.5 * u + wig * side, head_y - 8.5 * u
        mx, my = cx + side * 3.6 * u, head_y - 6.5 * u
        dr.line([bx, by, mx, my, tx, ty], fill=LEG, width=max(1, int(1.2 * u)), joint="curve")
        dr.ellipse([tx - 1.1 * u, ty - 1.1 * u, tx + 1.1 * u, ty + 1.1 * u], fill=LEG)

    # --- body: abdomen, thorax, head (back to front) -------------------------
    ellipse(dr, cx, abdo_y, 7.2 * u, 9.2 * u, BODY)          # abdomen
    ellipse(dr, cx, abdo_y - 2.5 * u, 4.6 * u, 5.6 * u, BODY_HI)   # sheen
    ellipse(dr, cx, abdo_y - 2.5 * u, 4.0 * u, 5.0 * u, BODY)
    ellipse(dr, cx, thorax_y, 4.4 * u, 5.6 * u, BODY)        # thorax
    ellipse(dr, cx, head_y, 5.0 * u, 4.6 * u, BODY)          # head
    ellipse(dr, cx, head_y - 1.0 * u, 3.0 * u, 2.4 * u, BODY_HI)   # head sheen
    ellipse(dr, cx, head_y - 1.0 * u, 2.4 * u, 1.9 * u, BODY)
    # mandibles + eyes
    for side in (-1, 1):
        ellipse(dr, cx + side * 2.6 * u, head_y - 1.2 * u, 1.0 * u, 1.2 * u, EYE)
        dr.line([cx + side * 2.2 * u, head_y - 3.6 * u, cx + side * 3.4 * u, head_y - 5.4 * u],
                fill=LEG, width=max(1, int(1.1 * u)))

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

    # zoomed preview strip on a light card for review
    z = 5
    prev = Image.new("RGB", (CELL * FRAMES * z, CELL * z), (238, 230, 216))
    prev.paste(sheet.resize((CELL * FRAMES * z, CELL * z), Image.NEAREST),
               (0, 0), sheet.resize((CELL * FRAMES * z, CELL * z), Image.NEAREST))
    pv = sys.argv[1] if len(sys.argv) > 1 else "build/ant_sheet_preview.png"
    os.makedirs(os.path.dirname(pv), exist_ok=True)
    prev.save(pv)
    print(f"wrote {pv}")


if __name__ == "__main__":
    main()
