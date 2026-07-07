#!/usr/bin/env python3
"""Render Time Dodge recordings into shareable GIFs (marketing material).

Reads a frames JSONL from tools/record_timedodge.lua and draws each frame in
the game's look — dark aurora background, icy player orb with a dash trail,
foe orbs with speed streaks (colour = foe kind), time gates, UI text, screen
shake — plus overlay copy ("TIME MOVES WHEN YOU MOVE", HUD, a timescale
meter). Default run (the ENDLESS hero clip) writes:

  docs/media/timedodge-hero.gif   — freeze/dash cycles -> death card
  docs/media/timedodge-loop.gif   — a short loop around a near-miss
  docs/media/timedodge-poster.png — a still poster frame

With arguments it renders any recording to a single GIF (used for the TRIALS
tour):  python3 tools/render_timedodge_gif.py <frames.jsonl> <outname>

Stdlib + Pillow only.
"""
import json
import math
import os
import sys

from PIL import Image, ImageDraw, ImageFont

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


def make_background():
    """Vertical gradient, precomputed once."""
    bg = Image.new("RGB", (W * SS, H * SS))
    px = bg.load()
    for j in range(H * SS):
        c = lerp(BG_TOP, BG_BOT, j / (H * SS - 1))
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


def main(src=SRC, outname=None, extras=True):
    os.makedirs(OUT_DIR, exist_ok=True)
    with open(src) as f:
        frames = [json.loads(line) for line in f]
    bg = make_background()
    fonts, glows = {}, {}

    def font(px_size):
        key = max(8, int(px_size))
        if key not in fonts:
            fonts[key] = ImageFont.truetype(FONT, key)
        return fonts[key]

    def glow(radius, color, alpha=110):
        key = (radius, color, alpha)
        if key not in glows:
            glows[key] = glow_disc(radius, color, alpha)
        return glows[key]

    f_big, f_mid, f_sml = font(30 * SS), font(17 * SS), font(12 * SS)

    def wx(x, ox=0.0):
        return (x + HW) * SCALE + ox * SS

    def wy(y, oy=0.0):
        return (HH - y) * SCALE + oy * SS

    stride = 3 if len(frames) < 1400 else (4 if len(frames) < 1650 else
             (5 if len(frames) < 1950 else 6))
    frame_ms = {3: 50, 4: 66, 5: 83, 6: 100}[stride]
    trauma, energy = 0.0, 0.0
    prev_pos, prev_alive = {}, True
    death_frame = None
    rendered = []            # (sim_index, PIL image)

    for idx, fr in enumerate(frames):
        # --- camera / energy state advances EVERY sim frame -----------------
        for name, val in fr["fx"]:
            if name == "shake":
                trauma = min(1.0, trauma + float(val))
        energy = max(energy * 0.985, min(1.0, trauma))
        trauma *= 0.92
        alive, done = fr["alive"], fr.get("done", False)
        in_run = fr.get("mode", "run") == "run"
        if prev_alive and not alive and not done:
            death_frame = idx
        prev_alive = alive

        ents = {e[0]: e for e in fr["ents"]}
        cur_pos = {eid: (e[1], e[2]) for eid, e in ents.items() if e[9] in ("orb", "meteor", "rockball")}
        take = idx % stride == 0 or (death_frame is not None and idx - death_frame < 3)
        if not take:
            prev_pos = cur_pos
            continue

        # --- draw ------------------------------------------------------------
        ts = fr["ts"]
        n = fr["n"]
        shk = trauma * trauma * 10
        ox = shk * math.sin(n * 1.7)
        oy = shk * math.cos(n * 2.3)

        g1 = glow(150 * SS, (40, 90, 160), int(50 + 90 * energy))
        g2 = glow(180 * SS, (90, 40, 130), int(40 + 70 * energy))
        im = bg.copy().convert("RGB")
        im.paste(g1, (int(W * SS * 0.15 + 30 * SS * math.sin(n * 0.01)) - g1.size[0] // 2,
                      int(H * SS * 0.25 + 20 * SS * math.cos(n * 0.013)) - g1.size[1] // 2), g1)
        im.paste(g2, (int(W * SS * 0.8 + 25 * SS * math.cos(n * 0.008)) - g2.size[0] // 2,
                      int(H * SS * 0.7 + 30 * SS * math.sin(n * 0.011)) - g2.size[1] // 2), g2)
        dr = ImageDraw.Draw(im, "RGBA")

        # bucket entities: buttons under gates under foes under player, text on top
        player, foes, texts, buttons, gates = None, [], [], [], []
        for eid, e in ents.items():
            tex = e[9]
            if tex in ("orb", "rockball"):
                player = e
            elif tex == "meteor":
                foes.append(e)
            elif tex == "text":
                texts.append(e)
            elif tex == "gem":
                gates.append(e)
            elif tex == "rect":
                if e[3] < 30:                     # dash-trail ghost
                    if e[8] > 0.01:
                        x, y, s = wx(e[1], ox), wy(e[2], oy), e[3] * SCALE * 0.5
                        dr.ellipse([x - s, y - s, x + s, y + s],
                                   fill=(150, 210, 255, int(e[8] * 160)))
                else:
                    buttons.append(e)

        for e in buttons:
            x, y = wx(e[1]), wy(e[2])
            w2, h2 = e[3] * SCALE * 0.5, e[4] * SCALE * 0.5
            col = (int(e[5] * 255), int(e[6] * 255), int(e[7] * 255), int(e[8] * 235))
            dr.rounded_rectangle([x - w2, y - h2, x + w2, y + h2],
                                 radius=10 * SS, fill=col)

        for e in gates:
            x, y, r = wx(e[1], ox), wy(e[2], oy), e[3] * SCALE * 0.62
            col = (int(e[5] * 255), int(e[6] * 255), int(e[7] * 255))
            a = e[8]
            g = glow(int(r * 2.6), col, int(120 * a))
            im.paste(g, (int(x) - g.size[0] // 2, int(y) - g.size[1] // 2), g)
            dr = ImageDraw.Draw(im, "RGBA")
            dr.polygon([(x, y - r), (x + r, y), (x, y + r), (x - r, y)],
                       fill=col + (int(255 * a),))
            dr.polygon([(x, y - r * 0.45), (x + r * 0.45, y), (x, y + r * 0.45), (x - r * 0.45, y)],
                       fill=(240, 255, 255, int(230 * a)))

        for e in foes:
            x, y = wx(e[1], ox), wy(e[2], oy)
            r = e[3] * SCALE * 0.55
            col = (int(e[5] * 255), int(e[6] * 255), int(e[7] * 255))
            rot = e[11] if len(e) > 11 else 0.0
            pp = prev_pos.get(e[0])
            if pp:                                # speed streak ∝ motion
                px_, py_ = wx(pp[0], ox), wy(pp[1], oy)
                dx, dy = x - px_, y - py_
                dr.line([x - dx * 3, y - dy * 3, x, y],
                        fill=col + (90,), width=max(1, int(r * 1.1)))
            g = glow(max(2, int(r * 3)), col, 90)
            im.paste(g, (int(x) - g.size[0] // 2, int(y) - g.size[1] // 2), g)
            dr = ImageDraw.Draw(im, "RGBA")
            # lumpy rotating rock: radius jitter seeded by entity id
            pts, dark = [], []
            for k in range(9):
                a = rot + k * math.tau / 9
                jig = 0.78 + 0.22 * math.sin(e[0] * 2.7 + k * 2.1)
                pts.append((x + r * jig * math.cos(a), y + r * jig * math.sin(a)))
            dr.polygon(pts, fill=col + (255,))
            ca = rot * 0.7 + e[0]
            for (cr, off) in ((0.32, 0.35), (0.2, -0.4)):   # craters
                cxx = x + r * off * math.cos(ca)
                cyy = y + r * off * math.sin(ca)
                rr = r * cr
                dr.ellipse([cxx - rr, cyy - rr, cxx + rr, cyy + rr],
                           fill=(int(col[0] * .55), int(col[1] * .55), int(col[2] * .55), 220))

        if player is not None and alive:
            x, y = wx(player[1], ox), wy(player[2], oy)
            r = player[3] * SCALE * 0.55
            prot = player[11] if len(player) > 11 else 0.0
            pc = lerp((235, 240, 245), FROZEN, 1 - ts)
            g = glow(int(r * 3.2), (170, 220, 255), 130)
            im.paste(g, (int(x) - g.size[0] // 2, int(y) - g.size[1] // 2), g)
            dr = ImageDraw.Draw(im, "RGBA")
            ppts = []                          # rounder rock than the foes
            for k in range(10):
                a = prot + k * math.tau / 10
                jig = 0.90 + 0.10 * math.sin(k * 2.3 + 1.1)
                ppts.append((x + r * jig * math.cos(a), y + r * jig * math.sin(a)))
            dr.polygon(ppts, fill=pc + (255,))
            ca = prot * 0.7
            for (cr, off) in ((0.30, 0.38), (0.18, -0.42)):
                cxx = x + r * off * math.cos(ca)
                cyy = y + r * off * math.sin(ca)
                rr = r * cr
                dr.ellipse([cxx - rr, cyy - rr, cxx + rr, cyy + rr],
                           fill=(int(pc[0] * .6), int(pc[1] * .6), int(pc[2] * .6), 200))
            dr.ellipse([x - r * 0.45, y - r * 0.55, x - r * 0.05, y - r * 0.15],
                       fill=(255, 255, 255, 90))
            ring = r * (1.7 + 0.5 * (1 - ts))
            dr.ellipse([x - ring, y - ring, x + ring, y + ring],
                       outline=FROZEN + (int(90 + 100 * (1 - ts)),), width=2 * SS)

        for e in texts:                           # screen text (menus, labels)
            col = (int(e[5] * 255), int(e[6] * 255), int(e[7] * 255), int(e[8] * 255))
            dr.text((wx(e[1]), wy(e[2])), e[10], font=font(e[4] * SCALE),
                    fill=col, anchor="mm")

        # frozen vignette: icy edges when time is (nearly) stopped mid-run
        if in_run and alive and ts < 0.2:
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
        def ctext(cy, txt, f, fill):
            dr.text((W * SS / 2, cy), txt, font=f, fill=fill, anchor="ma")

        if in_run:
            ctext(14 * SS, "TIME DODGE", f_mid, (255, 255, 255, 230))
            hud1 = fr["hud"].split("\n")[0]
            ctext(38 * SS, hud1, f_sml, FROZEN + (220,) if "FROZEN" in hud1
                  else (255, 255, 255, 160))

            mx, mh = W * SS - 12 * SS, 200 * SS   # timescale meter, right edge
            my = (H * SS - mh) // 2
            dr.rounded_rectangle([mx - 3 * SS, my, mx + 3 * SS, my + mh],
                                 radius=3 * SS, fill=(255, 255, 255, 30))
            fh = int(mh * ts)
            dr.rounded_rectangle([mx - 3 * SS, my + mh - fh, mx + 3 * SS, my + mh],
                                 radius=3 * SS, fill=lerp(FROZEN, FLOW, ts) + (200,))

            if alive:
                ctext(H * SS - 64 * SS, "HOLD TO STEAL TIME", f_big, (255, 255, 255, 235))
                ctext(H * SS - 32 * SS, "RELEASE  TO  FREEZE", f_mid,
                      lerp(FROZEN, FLOW, ts) + (235,))
            else:
                lines = fr["hud"].split("\n")
                if done:                          # trial cleared: star card
                    dr.rectangle([0, 0, im.size[0], im.size[1]], fill=(10, 45, 65, 110))
                    ctext(H * SS * 0.40, "MOMENT SEALED", f_big, (255, 255, 255, 250))
                    if len(lines) > 1:
                        ctext(H * SS * 0.48, lines[1].strip(), f_mid, (190, 240, 255, 245))
                else:                             # death: impact flash + card
                    k = min(1.0, (idx - death_frame) / 6) if death_frame is not None else 1.0
                    if k < 0.5:
                        im = Image.blend(im, Image.new("RGB", im.size, (255, 245, 240)), 1 - k * 2)
                        dr = ImageDraw.Draw(im, "RGBA")
                    dr.rectangle([0, 0, im.size[0], im.size[1]], fill=(90, 10, 20, int(110 * k)))
                    big = "YOU FADED AWAY" if "FADED" in fr["hud"] else "SO CLOSE"
                    ctext(H * SS * 0.40, big, f_big, (255, 255, 255, 250))
                    if len(lines) > 1:
                        ctext(H * SS * 0.48, lines[1].strip(), f_mid, (255, 200, 190, 240))
                ctext(H * SS - 48 * SS, "HOLD TO STEAL TIME - RELEASE TO FREEZE", f_sml,
                      (255, 255, 255, 200))

        prev_pos = cur_pos
        rendered.append((idx, im.resize((W, H), Image.LANCZOS)))

    # ---- write outputs -------------------------------------------------------
    name = outname or "timedodge-hero"
    imgs = [im.quantize(colors=128, dither=Image.FLOYDSTEINBERG)
            for _, im in rendered]
    durations = [frame_ms] * len(imgs)
    durations[-1] = 1800                     # hold the final card
    imgs[0].save(f"{OUT_DIR}/{name}.gif", save_all=True,
                 append_images=imgs[1:], duration=durations, loop=0, optimize=True)

    if extras:
        # short loop: a window around the first near-miss graze ("wall" sfx)
        near = [i for i, fr in enumerate(frames)
                if any(nm == "sound" and v == "wall" for nm, v in fr["fx"])]
        mid = near[0] if near else len(frames) // 2
        lo, hi = max(0, mid - 100), min(len(frames), mid + 70)
        loop = [im for i, im in rendered if lo <= i < hi]
        if loop:
            loop[0].save(f"{OUT_DIR}/timedodge-loop.gif", save_all=True,
                         append_images=loop[1:], duration=50, loop=0, optimize=True)

        def busy(i):                        # poster: busiest alive frame
            fr = frames[i]
            return sum(1 for e in fr["ents"] if e[9] == "orb") if fr["alive"] else -1
        pi = max((i for i, _ in rendered), key=busy)
        dict(rendered)[pi].save(f"{OUT_DIR}/timedodge-poster.png")

    sizes = {p: os.path.getsize(f"{OUT_DIR}/{p}") // 1024
             for p in os.listdir(OUT_DIR) if p.startswith("timedodge")}
    print(f"rendered {len(imgs)} frames -> {name}.gif")
    print("outputs:", {k: f"{v}KB" for k, v in sizes.items()})


if __name__ == "__main__":
    if len(sys.argv) >= 3:
        main(sys.argv[1], sys.argv[2], extras=False)
    else:
        main()
