#!/usr/bin/env python3
"""Turn a Floniks-generated image into a clean game texture.

Floniks' text_to_image models ignore the transparent-background request and
instead *bake* the transparency checkerboard (or a solid backdrop) into an RGB
image. `cutout()` recovers a true alpha cutout by flood-filling the background
inward from every border pixel, keying out pixels within `tol` colour-distance
of their seed — bridging the two checkerboard shades / a solid backdrop while
stopping at the subject's thick dark outline. `fit()` then crops to the subject
and scales to the exact target size (Lanczos, alpha-preserving).

For full-frame textures (grass) use `full_frame()` — centre-crop, no keying.

CLI: floniks_sprite.py <in> <out> <W> <H> [--tol N] [--margin F] [--bg alpha|blue|none]
"""
import sys
from collections import deque
from PIL import Image, ImageFilter


def cutout(im, tol):
    """RGBA copy of `im` with border-connected background keyed to alpha 0."""
    w, h = im.size
    px = im.load()
    alpha = Image.new("L", (w, h), 255)
    ap = alpha.load()
    seen = bytearray(w * h)
    q = deque()

    def seed(x, y):
        i = y * w + x
        if not seen[i]:
            seen[i] = 1
            q.append((x, y, px[x, y]))

    for x in range(w):
        seed(x, 0); seed(x, h - 1)
    for y in range(h):
        seed(0, y); seed(w - 1, y)

    tol2 = tol * tol
    while q:
        x, y, seedc = q.popleft()
        r, g, b = px[x, y][:3]
        sr, sg, sb = seedc[:3]
        if (r - sr) ** 2 + (g - sg) ** 2 + (b - sb) ** 2 > tol2:
            continue
        ap[x, y] = 0
        # Compare each candidate to the ORIGINAL border seed colour (not the
        # neighbour's) so the fill can't creep along a soft gradient into the
        # subject — it halts the instant a pixel diverges from the flat backdrop.
        for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
            if 0 <= nx < w and 0 <= ny < h:
                i = ny * w + nx
                if not seen[i]:
                    seen[i] = 1
                    q.append((nx, ny, seedc))

    alpha = alpha.filter(ImageFilter.GaussianBlur(0.6))  # soften the 1px key edge
    rgba = im.convert("RGBA")
    rgba.putalpha(alpha)
    return rgba


def fit(rgba, W, H, margin=0.04):
    """Crop to the subject, then scale it (keeping ITS aspect ratio) to fit
    inside the WxH box with a small margin, and centre it on a transparent
    canvas. Don't square the canvas — that would collapse extreme aspect
    targets (e.g. the 8x22 laser bolt) and under-fill non-square sprites."""
    bbox = rgba.getbbox()
    if bbox:
        rgba = rgba.crop(bbox)
    avail_w, avail_h = W * (1 - 2 * margin), H * (1 - 2 * margin)
    scale = min(avail_w / rgba.width, avail_h / rgba.height)
    fitted = rgba.resize(
        (max(1, round(rgba.width * scale)), max(1, round(rgba.height * scale))),
        Image.LANCZOS,
    )
    out = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    out.paste(fitted, ((W - fitted.width) // 2, (H - fitted.height) // 2), fitted)
    return out


def full_frame(im, W, H):
    """Centre-crop to the target aspect and resize — for edge-to-edge textures."""
    im = im.convert("RGBA")
    iw, ih = im.size
    target = W / H
    if iw / ih > target:            # too wide -> crop sides
        nw = round(ih * target)
        im = im.crop(((iw - nw) // 2, 0, (iw - nw) // 2 + nw, ih))
    else:                           # too tall -> crop top/bottom
        nh = round(iw / target)
        im = im.crop((0, (ih - nh) // 2, iw, (ih - nh) // 2 + nh))
    return im.resize((W, H), Image.LANCZOS)


def build(in_path, W, H, tol=40, bg="alpha", margin=0.04):
    im = Image.open(in_path).convert("RGB")
    if bg == "none":
        return full_frame(im, W, H)
    return fit(cutout(im, tol), W, H, margin)


def main():
    a = sys.argv
    inp, outp, W, H = a[1], a[2], int(a[3]), int(a[4])
    tol = int(a[a.index("--tol") + 1]) if "--tol" in a else 40
    margin = float(a[a.index("--margin") + 1]) if "--margin" in a else 0.04
    bg = a[a.index("--bg") + 1] if "--bg" in a else "alpha"
    build(inp, W, H, tol, bg, margin).save(outp)
    print(f"wrote {outp} ({W}x{H}) bg={bg} tol={tol}")


if __name__ == "__main__":
    main()
