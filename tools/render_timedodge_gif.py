#!/usr/bin/env python3
"""Render the Time Dodge recording into shareable GIFs (marketing material).

Reads build/timedodge_frames.jsonl (from tools/record_timedodge.lua) and draws
each frame in the game's look — dark aurora background, icy player orb with a
dash trail, red bullets with speed streaks, screen shake — plus overlay copy
("TIME MOVES WHEN YOU MOVE", HUD, a timescale meter). Outputs:

  docs/media/timedodge-hero.gif   — the full run: freeze/dash cycles -> death card
  docs/media/timedodge-loop.gif   — a short seamless-ish loop around a near-miss
  docs/media/timedodge-poster.png — a still poster frame (store/social cover)

Stdlib + Pillow only:  python3 tools/render_timedodge_gif.py
"""
import json
import math
import os

from PIL import Image, ImageDraw, ImageFilter, ImageFont

SRC = "build/timedodge_frames.jsonl"
OUT_DIR = "docs/media"
FONT = "assets/fonts/game.ttf"

W, H = 360, 780              # output size (phone-shaped)
SS = 2                       # supersample factor
HW, HH = 195, 422            # world half-extents used by the recorder
SCALE = (W * SS) / (2 * HW)  # world px -> canvas px

FROZEN = (140, 215, 255)
FLOW = (255, 80, 64)
BG_TOP = (8, 11, 26)
BG_BOT = (24, 13, 44)


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def wx(x, ox=0.0):
    return (x + HW) * SCALE + ox * SS


def wy(y, oy=0.0):
    return (HH - y) * SCALE + oy * SS


def make_background():
    """Vertical gradient + two soft aurora glows, precomputed once."""
    bg = Image.new("RGB", (W * SS, H * SS))
    px = bg.load()
    for j in range(H * SS):
        t = j / (H * SS - 1)
        c = lerp(BG_TOP, BG_BOT, t)
        for i in range(W * SS):
            px[i, j] = c
    return bg


def glow_disc(radius, color, alpha):
    d = radius * 2
    im = Image.new("RGBA", (d, d), (0, 0, 0, 0))
    dr = ImageDraw.Draw(im)
    steps = 24
    for s in range(steps, 0, -1):
        r = radius * s / steps
        a = int(alpha * (1 - s / steps) ** 2)
        dr.ellipse([radius - r, radius - r, radius + r, radius + r],
                   fill=color + (a,))
    return im


def load_frames():
    with open(SRC) as f:
        return [json.loads(line) for line in f]


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    frames = load_frames()
    bg = make_background()
    f_big = ImageFont.truetype(FONT, 30 * SS)
    f_mid = ImageFont.truetype(FONT, 17 * SS)
    f_sml = ImageFont.truetype(FONT, 12 * SS)
    glow_cache = {}

    def glow(radius, color, alpha=110):
        key = (radius, color, alpha)
        if key not in glow_cache:
            glow_cache[key] = glow_disc(radius, color, alpha)
        return glow_cache[key]

    trauma, zoomv, energy = 0.0, 0.0, 0.0
    prev_pos = {}
    death_frame = None
    rendered = []          # (sim_index, PIL image)

    for idx, fr in enumerate(frames):
        # --- camera / energy state advances EVERY sim frame -----------------
        for name, val in fr["fx"]:
            if name == "shake":
                trauma = min(1.0, trauma + float(val))
            elif name == "zoom":
                zoomv = min(1.0, zoomv + float(val))
        energy = max(energy * 0.985, min(1.0, trauma))
        trauma *= 0.92
        zoomv *= 0.90
        alive = fr["alive"]
        if not alive and death_frame is None:
            death_frame = idx

        ents = {e[0]: e for e in fr["ents"]}
        cur_pos = {eid: (e[1], e[2]) for eid, e in ents.items()
                   if e[9] == "orb"}

        take = idx % 3 == 0 or (death_frame is not None and idx - death_frame < 3)
        if not take:
            prev_pos = cur_pos
            continue

        # --- draw ------------------------------------------------------------
        ts = fr["ts"]
        n = fr["n"]
        shk = trauma * trauma * 10
        ox = shk * math.sin(n * 1.7)
        oy = shk * math.cos(n * 2.3)

        # drifting aurora glows, brightened by gameplay energy
        g1 = glow(150 * SS, (40, 90, 160), int(50 + 90 * energy))
        g2 = glow(180 * SS, (90, 40, 130), int(40 + 70 * energy))
        im = bg.copy().convert("RGB")
        im.paste(g1,(int(W * SS * 0.15 + 30 * SS * math.sin(n * 0.01)) - g1.size[0] // 2,
                      int(H * SS * 0.25 + 20 * SS * math.cos(n * 0.013)) - g1.size[1] // 2), g1)
        im.paste(g2, (int(W * SS * 0.8 + 25 * SS * math.cos(n * 0.008)) - g2.size[0] // 2,
                      int(H * SS * 0.7 + 30 * SS * math.sin(n * 0.011)) - g2.size[1] // 2), g2)
        dr = ImageDraw.Draw(im, "RGBA")

        # world entities: trails (rects) under bullets under player
        player = None
        bullets = []
        for eid, e in ents.items():
            tex = e[9]
            if tex == "orb":
                if abs(e[3] - 26) < 2:
                    player = e
                else:
                    bullets.append(e)
            elif tex == "rect" and e[8] > 0.01:   # dash-trail ghosts
                x, y, s = wx(e[1], ox), wy(e[2], oy), e[3] * SCALE * 0.5
                a = int(e[8] * 160)
                dr.ellipse([x - s, y - s, x + s, y + s], fill=(150, 210, 255, a))

        for e in bullets:
            x, y = wx(e[1], ox), wy(e[2], oy)
            r = e[3] * SCALE * 0.55
            col = (int(e[5] * 255), int(e[6] * 255), int(e[7] * 255))
            # speed streak: line from previous sim position, length ∝ motion
            pp = prev_pos.get(e[0])
            if pp:
                px_, py_ = wx(pp[0], ox), wy(pp[1], oy)
                dx, dy = x - px_, y - py_
                dr.line([x - dx * 3, y - dy * 3, x, y],
                        fill=col + (90,), width=int(r * 1.1))
            g = glow(int(r * 3), col, 100)
            im.paste(g, (int(x) - g.size[0] // 2, int(y) - g.size[1] // 2), g)
            dr = ImageDraw.Draw(im, "RGBA")
            dr.ellipse([x - r, y - r, x + r, y + r], fill=col + (255,))
            dr.ellipse([x - r * 0.45, y - r * 0.45, x + r * 0.45, y + r * 0.45],
                       fill=(255, 230, 220, 230))

        if player is not None and alive:
            x, y = wx(player[1], ox), wy(player[2], oy)
            r = player[3] * SCALE * 0.55
            pc = lerp((255, 255, 255), FROZEN, 1 - ts)
            g = glow(int(r * 3.2), (170, 220, 255), 130)
            im.paste(g, (int(x) - g.size[0] // 2, int(y) - g.size[1] // 2), g)
            dr = ImageDraw.Draw(im, "RGBA")
            dr.ellipse([x - r, y - r, x + r, y + r], fill=pc + (255,))
            ring = r * (1.7 + 0.5 * (1 - ts))
            dr.ellipse([x - ring, y - ring, x + ring, y + ring],
                       outline=FROZEN + (int(90 + 100 * (1 - ts)),), width=2 * SS)

        # frozen vignette: icy edges when time is (nearly) stopped
        if ts < 0.2 and alive:
            k = 1 - ts / 0.2
            edge = Image.new("RGBA", im.size, (0, 0, 0, 0))
            ed = ImageDraw.Draw(edge)
            m = int(26 * SS * k)
            for i in range(m):
                a = int(70 * k * (1 - i / m) ** 2)
                ed.rectangle([i, i, im.size[0] - 1 - i, im.size[1] - 1 - i],
                             outline=FROZEN + (a,))
            im = Image.alpha_composite(im.convert("RGBA"), edge).convert("RGB")
            dr = ImageDraw.Draw(im, "RGBA")

        # ---- overlays (screen space) ----------------------------------------
        def ctext(cy, txt, font, fill):
            bb = dr.textbbox((0, 0), txt, font=font)
            dr.text(((W * SS - (bb[2] - bb[0])) / 2, cy), txt, font=font, fill=fill)

        ctext(14 * SS, "TIME DODGE", f_mid, (255, 255, 255, 230))
        hud = fr["hud"].split("\n")[0]
        ctext(38 * SS, hud, f_sml, FROZEN + (220,) if "FROZEN" in hud
              else (255, 255, 255, 160))

        # timescale meter (right edge): icy when frozen -> hot when flowing
        mx, mh = W * SS - 12 * SS, 200 * SS
        my = (H * SS - mh) // 2
        dr.rounded_rectangle([mx - 3 * SS, my, mx + 3 * SS, my + mh],
                             radius=3 * SS, fill=(255, 255, 255, 30))
        fh = int(mh * ts)
        dr.rounded_rectangle([mx - 3 * SS, my + mh - fh, mx + 3 * SS, my + mh],
                             radius=3 * SS, fill=lerp(FROZEN, FLOW, ts) + (200,))

        if alive:
            ctext(H * SS - 64 * SS, "TIME MOVES", f_big, (255, 255, 255, 235))
            ctext(H * SS - 32 * SS, "WHEN  YOU  MOVE", f_mid,
                  lerp(FROZEN, FLOW, ts) + (235,))
        else:
            k = min(1.0, (idx - death_frame) / 6)
            if k < 0.5:      # impact flash
                fl = Image.new("RGB", im.size, (255, 245, 240))
                im = Image.blend(im, fl, 1 - k * 2)
                dr = ImageDraw.Draw(im, "RGBA")
            dr.rectangle([0, 0, im.size[0], im.size[1]], fill=(90, 10, 20, int(110 * k)))
            survived = ""
            for part in fr["hud"].split("\n"):
                if part.startswith("TIME"):
                    survived = part.strip()
            ctext(H * SS * 0.42, "SO CLOSE", f_big, (255, 255, 255, 250))
            ctext(H * SS * 0.50, survived, f_mid, (255, 200, 190, 240))
            ctext(H * SS - 48 * SS, "TIME MOVES WHEN YOU MOVE", f_sml,
                  (255, 255, 255, 200))

        prev_pos = cur_pos
        rendered.append((idx, im.resize((W, H), Image.LANCZOS)))

    # ---- write outputs -------------------------------------------------------
    imgs = [im.quantize(colors=128, dither=Image.FLOYDSTEINBERG)
            for _, im in rendered]
    durations = [50] * len(imgs)
    durations[-1] = 1800                     # hold the death card
    imgs[0].save(f"{OUT_DIR}/timedodge-hero.gif", save_all=True,
                 append_images=imgs[1:], duration=durations, loop=0, optimize=True)

    # short loop: a window around the first near-miss graze ("wall" sfx)
    near = [i for i, fr in enumerate(frames)
            if any(n == "sound" and v == "wall" for n, v in fr["fx"])]
    mid = near[0] if near else len(frames) // 2
    lo, hi = max(0, mid - 100), min(len(frames), mid + 70)
    loop = [im for i, im in rendered if lo <= i < hi]
    if loop:
        loop[0].save(f"{OUT_DIR}/timedodge-loop.gif", save_all=True,
                     append_images=loop[1:], duration=50, loop=0, optimize=True)

    # poster: the busiest alive frame (most bullets on screen)
    def busy(i):
        fr = frames[i]
        return sum(1 for e in fr["ents"] if e[9] == "orb") if fr["alive"] else -1
    pi = max((i for i, _ in rendered), key=busy)
    poster = dict(rendered)[pi]
    poster.save(f"{OUT_DIR}/timedodge-poster.png")

    sizes = {p: os.path.getsize(f"{OUT_DIR}/{p}") // 1024
             for p in os.listdir(OUT_DIR) if p.startswith("timedodge")}
    print("rendered", len(imgs), "hero frames;", len(loop), "loop frames")
    print("outputs:", {k: f"{v}KB" for k, v in sizes.items()})


if __name__ == "__main__":
    main()
