#!/usr/bin/env python3
"""Render an Ant Art recording (tools/record_ant_clear.lua) into a gameplay
video + GIF, in the reference game's look. Reads build/ant_clear_frames.jsonl —
each entity is [x,y,w,h,r,g,b,a,tex,str,rot,frame] — and draws:
  cat_face  -> mascot banner        tile_sq -> candy square (board cells, slots,
  hole      -> nest funnel                     queue tiles), tinted by colour
  ant_sheet -> walking ant, cropped to `frame` and rotated to `rot`
  rect      -> a pixel being carried            text -> CJK labels (game.ttf)

Outputs docs/media/ant_clear.{mp4,gif,png}. Pillow (+ imageio-ffmpeg for mp4).
"""
import json, math, os, subprocess, sys, tempfile
from PIL import Image, ImageDraw, ImageFont

SRC = sys.argv[1] if len(sys.argv) > 1 else "build/ant_clear_frames.jsonl"
OUT_DIR = "docs/media"
FONT = "assets/fonts/game.ttf"

HW, HH = 200, 430
W, H = 390, 838
SS = 2
CW, CH = W * SS, H * SS
SCALE = CW / (2 * HW)

BG_T, BG_B = (236, 224, 205), (214, 189, 160)
INK = (70, 52, 44)
CAP = {"stuck": ("卡住了 · 取消一个槽位", (196, 72, 72)),
       "cancel": ("看广告 · 槽位已释放", (70, 150, 90)),
       "done": ("恭喜完成！", (70, 150, 90))}

TEX = {}
for n in ("ant_sheet", "cat_face", "hole", "ad_play", "ant_shadow", "ant_icon",
          "icon_speed", "icon_x2", "icon_gift", "game_bg", "btn_pill"):
    p = f"assets/textures/{n}.png"
    TEX[n] = Image.open(p).convert("RGBA") if os.path.exists(p) else None
AF = TEX["ant_sheet"].width // 8 if TEX["ant_sheet"] else 48

_f = {}
def font(px):
    px = max(8, int(px))
    if px not in _f:
        try: _f[px] = ImageFont.truetype(FONT, px)
        except Exception: _f[px] = ImageFont.load_default()
    return _f[px]

def wx(x): return CW / 2 + x * SCALE
def wy(y): return CH / 2 - y * SCALE
def lerp(a, b, t): return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))
def darker(c, k=0.78): return tuple(int(x * k) for x in c[:3])
def lighter(c, k=0.3): return tuple(int(x + (255 - x) * k) for x in c[:3])

def make_bg():
    if TEX.get("game_bg") is not None:
        src = TEX["game_bg"].convert("RGB")
        sc = max(CW / src.width, CH / src.height)          # cover-fit
        r = src.resize((int(src.width * sc), int(src.height * sc)), Image.LANCZOS)
        x = (r.width - CW) // 2; y = (r.height - CH) // 2
        return r.crop((x, y, x + CW, y + CH))
    bg = Image.new("RGB", (CW, CH)); px = bg.load()
    for j in range(CH):
        c = lerp(BG_T, BG_B, j / (CH - 1))
        for i in range(CW): px[i, j] = c
    return bg

def candy(dr, box, color):
    x0, y0, x1, y1 = box
    r = min(x1 - x0, y1 - y0) * 0.26
    lift = (y1 - y0) * 0.13
    dr.rounded_rectangle([x0, y0 + lift, x1, y1 + lift], r, (0, 0, 0, 36))
    dr.rounded_rectangle([x0, y0, x1, y1], r, darker(color))
    dr.rounded_rectangle([x0, y0, x1, y1 - lift], r, tuple(color[:3]))
    dr.rounded_rectangle([x0 + (x1 - x0) * 0.14, y0 + (y1 - y0) * 0.10,
                          x1 - (x1 - x0) * 0.14, y0 + (y1 - y0) * 0.34], r * 0.6,
                         lighter(color) + (120,))

def draw_frame(bg, rec):
    im = bg.copy(); dr = ImageDraw.Draw(im, "RGBA")
    E = rec["ents"]
    def bytex(t): return [e for e in E if e[8] == t and e[7] > 0.02]
    # decor
    for e in bytex("cat_face"):
        t = TEX["cat_face"]; w = int(e[2] * SCALE); h = int(t.height * w / t.width)
        s = t.resize((w, h), Image.LANCZOS); im.paste(s, (int(wx(e[0]) - w / 2), int(wy(e[1]) - h / 2)), s)
    for e in bytex("hole"):
        t = TEX["hole"]; w = int(e[2] * SCALE); s = t.resize((w, w), Image.LANCZOS)
        im.paste(s, (int(wx(e[0]) - w / 2), int(wy(e[1]) - w / 2)), s)
    for e in bytex("ad_play"):
        t = TEX["ad_play"]; w = int(e[2] * SCALE); h = int(t.height * w / t.width)
        s = t.resize((w, h), Image.LANCZOS); im.paste(s, (int(wx(e[0]) - w / 2), int(wy(e[1]) - h / 2)), s)
    for nm in ("icon_speed", "icon_x2", "icon_gift"):
        t = TEX[nm]
        if t is None: continue
        for e in bytex(nm):
            w = max(1, int(e[2] * SCALE)); h = max(1, int(e[3] * SCALE))
            s = t.resize((w, h), Image.LANCZOS)
            if nm == "icon_x2":   # tinted dark in-game
                rr, gg, bb, aa = s.split()
                s = Image.merge("RGBA", (rr.point(lambda v:int(v*e[4])), gg.point(lambda v:int(v*e[5])), bb.point(lambda v:int(v*e[6])), aa))
            im.paste(s, (int(wx(e[0]) - w / 2), int(wy(e[1]) - h / 2)), s)
    for e in bytex("icon_find"):
        cxp, cyp, rr = wx(e[0]), wy(e[1]), e[2] * SCALE * 0.5
        dr.ellipse([cxp - rr, cyp - rr, cxp + rr, cyp + rr], fill=(74, 58, 50, 255))
        dr.ellipse([cxp - rr * 0.4, cyp - rr * 0.4, cxp + rr * 0.4, cyp + rr * 0.4], fill=(230, 220, 208, 255))
    for e in bytex("btn_back"):
        candy(dr, [wx(e[0]) - e[2] * SCALE / 2, wy(e[1]) - e[3] * SCALE / 2,
                   wx(e[0]) + e[2] * SCALE / 2, wy(e[1]) + e[3] * SCALE / 2], (196, 150, 96))
        dr.text((wx(e[0]), wy(e[1])), "←", font=font(int(e[3] * SCALE * 0.6)), fill=(255, 255, 255), anchor="mm")
    # candy tiles: board cells + slots + queue
    for e in bytex("tile_sq"):
        col = (int(e[4] * 255), int(e[5] * 255), int(e[6] * 255))
        hw, hh = e[2] * 0.5 * SCALE, e[3] * 0.5 * SCALE
        candy(dr, [wx(e[0]) - hw, wy(e[1]) - hh, wx(e[0]) + hw, wy(e[1]) + hh], col)
    # pill buttons (generated art, tinted)
    tp = TEX["btn_pill"]
    if tp is not None:
        for e in bytex("btn_pill"):
            w = max(1, int(e[2] * SCALE)); h = max(1, int(e[3] * SCALE))
            s = tp.resize((w, h), Image.LANCZOS)
            rr, gg, bb, aa = s.split()
            s = Image.merge("RGBA", (rr.point(lambda v: int(v*e[4])), gg.point(lambda v: int(v*e[5])),
                                     bb.point(lambda v: int(v*e[6])), aa))
            im.paste(s, (int(wx(e[0]) - w/2), int(wy(e[1]) - h/2)), s)
    # carried pixels
    for e in bytex("rect"):
        col = (int(e[4] * 255), int(e[5] * 255), int(e[6] * 255), int(e[7] * 255))
        hw, hh = e[2] * 0.5 * SCALE, e[3] * 0.5 * SCALE
        dr.rounded_rectangle([wx(e[0]) - hw, wy(e[1]) - hh, wx(e[0]) + hw, wy(e[1]) + hh], hw * 0.3, col)
    # ant shadows (under the ants, above the board)
    ts = TEX["ant_shadow"]
    if ts is not None:
        for e in bytex("ant_shadow"):
            w = int(e[2] * SCALE); h = int(e[3] * SCALE)
            s = ts.resize((max(1, w), max(1, h)), Image.LANCZOS)
            if e[7] < 0.999:
                al = s.split()[3].point(lambda v: int(v * e[7])); s.putalpha(al)
            im.paste(s, (int(wx(e[0]) - w / 2), int(wy(e[1]) - h / 2)), s)
    # walking dust puffs (from game.emit("dust", ...))
    for em in rec.get("emits", []):
        ex, ey = wx(em[0]), wy(em[1])
        for k, rr in enumerate((7, 4.5)):
            dr.ellipse([ex - rr * SS, ey - rr * SS, ex + rr * SS, ey + rr * SS],
                       fill=(210, 194, 170, 90 - k * 30))
    # ants — tinted to the entity colour (= its slot colour), so a red slot's
    # ants are red. Multiply RGB, keep alpha, then rotate to face travel.
    t = TEX["ant_sheet"]
    for e in bytex("ant_sheet"):
        fr = max(0, min(7, int(e[11])))
        sp = t.crop((fr * AF, 0, fr * AF + AF, t.height)).convert("RGBA")
        rch, gch, bch, ach = sp.split()
        rch = rch.point(lambda v: int(v * e[4]))
        gch = gch.point(lambda v: int(v * e[5]))
        bch = bch.point(lambda v: int(v * e[6]))
        sp = Image.merge("RGBA", (rch, gch, bch, ach))
        sp = sp.rotate(-math.degrees(e[10]), expand=True, resample=Image.BICUBIC)
        d = int(e[2] * SCALE)
        sp = sp.resize((d, d), Image.LANCZOS)
        im.paste(sp, (int(wx(e[0]) - d / 2), int(wy(e[1]) - d / 2)), sp)
    # tile bug-icons (single-frame ant, tinted dark)
    ti = TEX["ant_icon"]
    if ti is not None:
        for e in bytex("ant_icon"):
            d = max(1, int(e[2] * SCALE))
            s = ti.resize((d, d), Image.LANCZOS)
            rr, gg, bb, aa = s.split()
            s = Image.merge("RGBA", (rr.point(lambda v: int(v*e[4])), gg.point(lambda v: int(v*e[5])),
                                     bb.point(lambda v: int(v*e[6])), aa))
            im.paste(s, (int(wx(e[0]) - d / 2), int(wy(e[1]) - d / 2)), s)
    # labels
    for e in bytex("text"):
        if not e[9]: continue
        col = (int(e[4] * 255), int(e[5] * 255), int(e[6] * 255))
        f = font(e[3] * SCALE)
        lines = e[9].split("\n")
        for k, line in enumerate(lines):
            yoff = (k - (len(lines) - 1) / 2) * e[3] * SCALE * 1.05
            dr.text((wx(e[0]), wy(e[1]) + yoff), line, font=f, fill=col, anchor="mm")
    # HUD line
    hud = rec.get("hud", "")
    if hud:
        dr.text((14 * SS, 150 * SS), hud.split("\n")[0].split("\\n")[0], font=font(15 * SS), fill=INK, anchor="lm")
    # caption
    cap = CAP.get(rec.get("phase"))
    if cap:
        txt, col = cap; f = font(24 * SS)
        bb = dr.textbbox((0, 0), txt, font=f); tw = bb[2] - bb[0]; y = CH * 0.28
        dr.rounded_rectangle([CW/2 - tw/2 - 16*SS, y - 22*SS, CW/2 + tw/2 + 16*SS, y + 22*SS],
                             14*SS, (255, 255, 255, 225))
        dr.text((CW/2, y), txt, font=f, fill=col, anchor="mm")
    return im.resize((W, H), Image.LANCZOS)

def main():
    frames = [json.loads(l) for l in open(SRC) if l.strip()]
    bg = make_bg(); os.makedirs(OUT_DIR, exist_ok=True)
    picked = frames[::2]
    rendered = [draw_frame(bg, r) for r in picked]
    print(f"rendered {len(rendered)} frames")
    rendered[len(rendered) // 3].save(f"{OUT_DIR}/ant_clear.png")
    try:
        import imageio_ffmpeg
        ff = imageio_ffmpeg.get_ffmpeg_exe()
        with tempfile.TemporaryDirectory() as td:
            for i, imm in enumerate(rendered): imm.save(f"{td}/f_{i:05d}.png")
            mp4 = f"{OUT_DIR}/ant_clear.mp4"
            subprocess.run([ff, "-y", "-framerate", "30", "-i", f"{td}/f_%05d.png",
                            "-pix_fmt", "yuv420p", "-vf", "scale=trunc(iw/2)*2:trunc(ih/2)*2",
                            "-movflags", "+faststart", mp4], check=True, capture_output=True)
        print("wrote", mp4)
    except Exception as ex:
        print("mp4 skipped:", ex)
    q = [im.quantize(colors=96, dither=Image.FLOYDSTEINBERG) for im in rendered[::3]]
    q[0].save(f"{OUT_DIR}/ant_clear.gif", save_all=True, append_images=q[1:], duration=90, loop=0, optimize=True, disposal=2)
    print("wrote gif", len(q))

if __name__ == "__main__":
    main()
