#!/usr/bin/env python3
"""Render an Ant Art recording (tools/record_ant_clear.lua) into a gameplay
video + GIF. Reads build/ant_clear_frames.jsonl — each line has the full entity
list for one sim frame (rects = board pixels / slots / tray tiles, "villager" =
ant, "rock" = nest, "text" = labels) — and draws them in the game's look on a
warm wood-cream board, with the HUD line and a big phase caption.

Outputs:
  docs/media/ant_clear.mp4    — the full clip (play -> mistake -> stuck ->
                                cancel/ad -> recover -> cleared)
  docs/media/ant_clear.gif    — a lighter looping preview
  docs/media/ant_clear.png    — a poster still

Stdlib + Pillow (+ the imageio-ffmpeg binary for the mp4).
"""
import json
import math
import os
import subprocess
import sys
import tempfile

from PIL import Image, ImageDraw, ImageFont

SRC = sys.argv[1] if len(sys.argv) > 1 else "build/ant_clear_frames.jsonl"
OUT_DIR = "docs/media"
FONT = "assets/fonts/game.ttf"

HW, HH = 200, 430               # world half-extents used by the recorder
W, H = 380, 817                 # output canvas (phone-shaped)
SS = 2                          # supersample
CW, CH = W * SS, H * SS
SCALE = CW / (2 * HW)

BG_TOP = (247, 238, 224)
BG_BOT = (226, 210, 188)
INK = (60, 44, 38)
CAPTION = {
    "stuck": ("STUCK — cancel a slot to re-pick", (196, 72, 72)),
    "cancel": ("WATCH AD -> slot freed", (70, 150, 90)),
    "done": ("CLEARED!", (70, 150, 90)),
}


def wx(x):
    return CW / 2 + x * SCALE


def wy(y):
    return CH / 2 - y * SCALE


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def make_bg():
    bg = Image.new("RGB", (CW, CH))
    px = bg.load()
    for j in range(CH):
        c = lerp(BG_TOP, BG_BOT, j / (CH - 1))
        for i in range(CW):
            px[i, j] = c
    return bg


_fonts = {}
def font(px):
    px = max(8, int(px))
    if px not in _fonts:
        try:
            _fonts[px] = ImageFont.truetype(FONT, px)
        except Exception:
            _fonts[px] = ImageFont.load_default()
    return _fonts[px]


def rgba(e):
    return (int(e[4] * 255), int(e[5] * 255), int(e[6] * 255), int(e[7] * 255))


def draw_frame(bg, rec):
    im = bg.copy()
    dr = ImageDraw.Draw(im, "RGBA")
    ants, texts = [], []
    for e in rec["ents"]:
        x, y, w, h, tex, s = e[0], e[1], e[2], e[3], e[8], e[9]
        if e[7] <= 0.02:
            continue
        if tex == "rect":
            cx, cy = wx(x), wy(y)
            hw, hh = w * 0.5 * SCALE, h * 0.5 * SCALE
            r = min(hw, hh) * 0.35
            dr.rounded_rectangle([cx - hw, cy - hh, cx + hw, cy + hh], radius=r,
                                 fill=rgba(e))
        elif tex == "villager":            # ant
            ants.append(e)
        elif tex == "rock":                # nest hole
            cx, cy = wx(x), wy(y)
            rr = w * 0.5 * SCALE
            dr.ellipse([cx - rr, cy - rr, cx + rr, cy + rr], fill=(35, 24, 20, 255))
            dr.ellipse([cx - rr * 0.7, cy - rr * 0.7, cx + rr * 0.7, cy + rr * 0.7],
                       fill=(20, 13, 10, 255))
        elif tex == "text":
            if s:
                texts.append(e)
        # btn_back etc. ignored
    # ants on top of the board
    for e in ants:
        cx, cy = wx(e[0]), wy(e[1])
        rr = max(e[2], 6) * 0.42 * SCALE
        col = (int(e[4] * 255), int(e[5] * 255), int(e[6] * 255), 255)
        dr.ellipse([cx - rr, cy - rr * 1.25, cx + rr, cy + rr * 1.25], fill=col)
        dr.ellipse([cx - rr * 0.55, cy - rr * 1.7, cx + rr * 0.55, cy - rr * 0.6], fill=col)
    # labels (slot / tray numbers)
    for e in texts:
        f = font(e[3] * SCALE)
        col = (int(e[4] * 255), int(e[5] * 255), int(e[6] * 255))
        dr.text((wx(e[0]), wy(e[1])), e[9], font=f, fill=col, anchor="mm")
    # HUD line (top-left, like the game)
    hud = rec.get("hud", "")
    if hud:
        first = hud.split("\n")[0]
        dr.text((14 * SS, 16 * SS), first, font=font(15 * SS), fill=INK, anchor="lm")
    # big caption per phase
    cap = CAPTION.get(rec.get("phase"))
    if cap:
        txt, col = cap
        f = font(26 * SS)
        bb = dr.textbbox((0, 0), txt, font=f)
        tw = bb[2] - bb[0]
        y = CH * 0.30
        dr.rounded_rectangle([CW / 2 - tw / 2 - 16 * SS, y - 22 * SS,
                              CW / 2 + tw / 2 + 16 * SS, y + 22 * SS],
                             radius=14 * SS, fill=(255, 255, 255, 220))
        dr.text((CW / 2, y), txt, font=f, fill=col, anchor="mm")
    # title
    dr.text((CW / 2, 44 * SS), "ANT ART", font=font(20 * SS), fill=INK, anchor="mm")
    return im.resize((W, H), Image.LANCZOS)


def main():
    frames = [json.loads(l) for l in open(SRC) if l.strip()]
    bg = make_bg()
    os.makedirs(OUT_DIR, exist_ok=True)

    # sim is 60fps; render every 2nd frame -> 30fps video
    picked = frames[::2]
    rendered = [draw_frame(bg, r) for r in picked]
    print(f"rendered {len(rendered)} frames from {len(frames)} sim frames")

    # poster: a mid-play frame
    rendered[len(rendered) // 4].save(f"{OUT_DIR}/ant_clear.png")

    # mp4 via the imageio-ffmpeg binary
    try:
        import imageio_ffmpeg
        ff = imageio_ffmpeg.get_ffmpeg_exe()
        with tempfile.TemporaryDirectory() as td:
            for i, im in enumerate(rendered):
                im.save(f"{td}/f_{i:05d}.png")
            mp4 = f"{OUT_DIR}/ant_clear.mp4"
            subprocess.run([ff, "-y", "-framerate", "30", "-i", f"{td}/f_%05d.png",
                            "-pix_fmt", "yuv420p", "-vf", "scale=trunc(iw/2)*2:trunc(ih/2)*2",
                            "-movflags", "+faststart", mp4],
                           check=True, capture_output=True)
        print(f"wrote {mp4}")
    except Exception as ex:
        print(f"mp4 skipped: {ex}")

    # lighter looping GIF (every 3rd rendered frame, quantized)
    gif_src = rendered[::3]
    q = [im.quantize(colors=96, dither=Image.FLOYDSTEINBERG) for im in gif_src]
    q[0].save(f"{OUT_DIR}/ant_clear.gif", save_all=True, append_images=q[1:],
              duration=90, loop=0, optimize=True, disposal=2)
    print(f"wrote {OUT_DIR}/ant_clear.gif ({len(q)} frames)")


if __name__ == "__main__":
    main()
