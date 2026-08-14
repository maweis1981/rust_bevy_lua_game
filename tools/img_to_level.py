#!/usr/bin/env python3
"""img_to_level.py — turn ANY image into a solvable "Ant Art" (ant_clear) level.

Pipeline (the math is written up in docs/ant-clear-math.md §7):
  1. decode the image (built-in stdlib PNG decoder; Pillow is used automatically
     when installed, adding JPEG/GIF/BMP/WebP support),
  2. box-downsample to a W-cells-wide grid (height follows the aspect ratio),
     alpha-weighted so transparent pixels don't muddy edge colours,
  3. decide empty cells: real alpha if the image has it, otherwise the dominant
     border colour is taken as background and matching cells become empty,
  4. quantize every painted cell to the game's 5-colour food palette (or a
     k-means auto palette with --auto-palette) under the "redmean" metric,
  5. despeckle (isolated single cells take their neighbourhood's colour) and
     trim empty border rows/columns,
  6. run gen_level.py's peeling oracle + replay validator on the result and
     emit a ready-to-paste `LEVELS` entry for ant_clear.lua.

Because the board is always peelable from its frontier (see the lemma in the
math note), *every* image yields a solvable level — the oracle just proves it
and prices its difficulty (batches + peak simultaneous frontier colours).

Usage:
  python3 tools/img_to_level.py photo.png                    # 24-cell-wide level
  python3 tools/img_to_level.py logo.png --w 32 --batch 6
  python3 tools/img_to_level.py pic.png --check              # stats + preview only
  python3 tools/img_to_level.py pic.png --auto-palette 5     # fit palette to image
"""
import argparse
import os
import struct
import sys
import zlib

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gen_level import make_tray, validate  # the exact in-game frontier rule

# The pack's PALETTE5 (ant_clear.lua): chocolate / bread / sugar / berry / mint.
GAME_PALETTE = [
    (0.290, 0.208, 0.251),
    (0.969, 0.604, 0.298),
    (0.992, 0.902, 0.784),
    (0.949, 0.478, 0.584),
    (0.388, 0.812, 0.651),
]


# --- image loading -----------------------------------------------------------
def load_image(path):
    """Return (w, h, pixels) with pixels a flat list of (r, g, b, a) 0..255.
    Tries Pillow first (any format), falls back to the stdlib PNG decoder."""
    try:
        from PIL import Image  # optional; repo tools are stdlib-only by default
        im = Image.open(path).convert("RGBA")
        return im.width, im.height, list(im.getdata())
    except ImportError:
        pass
    return decode_png(path)


def decode_png(path):
    """Minimal PNG decoder: 8-bit depth, colour types 0/2/3/4/6, no interlace.
    Covers everything the project's own stdlib encoders emit, plus typical
    exported pixel art. For JPEG/WebP install Pillow."""
    with open(path, "rb") as f:
        data = f.read()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise SystemExit(f"{path}: not a PNG (install Pillow for other formats)")
    pos, w = 8, 0
    h = bitdepth = ctype = interlace = 0
    idat, plte, trns = b"", [], b""
    while pos < len(data):
        (length,) = struct.unpack(">I", data[pos:pos + 4])
        tag = data[pos + 4:pos + 8]
        body = data[pos + 8:pos + 8 + length]
        pos += 12 + length
        if tag == b"IHDR":
            w, h, bitdepth, ctype, _, _, interlace = struct.unpack(">IIBBBBB", body)
        elif tag == b"PLTE":
            plte = [tuple(body[i:i + 3]) for i in range(0, len(body), 3)]
        elif tag == b"tRNS":
            trns = body
        elif tag == b"IDAT":
            idat += body
        elif tag == b"IEND":
            break
    if bitdepth != 8 or interlace != 0:
        raise SystemExit(f"{path}: only 8-bit non-interlaced PNG supported "
                         f"(got depth={bitdepth} interlace={interlace}); install Pillow")
    nch = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}.get(ctype)
    if nch is None:
        raise SystemExit(f"{path}: unsupported PNG colour type {ctype}")
    raw = zlib.decompress(idat)
    stride = w * nch
    out_rows, prev = [], bytearray(stride)
    p = 0
    for _ in range(h):
        filt = raw[p]; p += 1
        line = bytearray(raw[p:p + stride]); p += stride
        if filt == 1:    # Sub
            for i in range(nch, stride):
                line[i] = (line[i] + line[i - nch]) & 0xFF
        elif filt == 2:  # Up
            for i in range(stride):
                line[i] = (line[i] + prev[i]) & 0xFF
        elif filt == 3:  # Average
            for i in range(stride):
                a = line[i - nch] if i >= nch else 0
                line[i] = (line[i] + ((a + prev[i]) >> 1)) & 0xFF
        elif filt == 4:  # Paeth
            for i in range(stride):
                a = line[i - nch] if i >= nch else 0
                b = prev[i]
                c = prev[i - nch] if i >= nch else 0
                pa, pb, pc = abs(b - c), abs(a - c), abs(a + b - 2 * c)
                pr = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                line[i] = (line[i] + pr) & 0xFF
        out_rows.append(bytes(line))
        prev = line
    pixels = []
    for row in out_rows:
        for x in range(w):
            v = row[x * nch:(x + 1) * nch]
            if ctype == 0:
                pixels.append((v[0], v[0], v[0], 255))
            elif ctype == 2:
                pixels.append((v[0], v[1], v[2], 255))
            elif ctype == 3:
                r, g, b = plte[v[0]]
                a = trns[v[0]] if v[0] < len(trns) else 255
                pixels.append((r, g, b, a))
            elif ctype == 4:
                pixels.append((v[0], v[0], v[0], v[1]))
            else:
                pixels.append((v[0], v[1], v[2], v[3]))
    return w, h, pixels


# --- colour math -------------------------------------------------------------
def redmean(c1, c2):
    """Perceptual-ish squared distance between two 0..255 RGB triples."""
    rbar = (c1[0] + c2[0]) / 2
    dr, dg, db = c1[0] - c2[0], c1[1] - c2[1], c1[2] - c2[2]
    return (2 + rbar / 256) * dr * dr + 4 * dg * dg + (2 + (255 - rbar) / 256) * db * db


def kmeans(samples, k, iters=24):
    """Tiny deterministic k-means (k-means++-lite seeding by max distance)."""
    centers = [samples[0]]
    while len(centers) < k:
        far = max(samples, key=lambda s: min(redmean(s, c) for c in centers))
        centers.append(far)
    for _ in range(iters):
        buckets = [[] for _ in range(k)]
        for s in samples:
            buckets[min(range(k), key=lambda i: redmean(s, centers[i]))].append(s)
        moved = False
        for i, b in enumerate(buckets):
            if not b:
                continue
            m = tuple(sum(p[j] for p in b) / len(b) for j in range(3))
            if m != centers[i]:
                centers[i] = m
                moved = True
        if not moved:
            break
    return [tuple(int(round(v)) for v in c) for c in centers]


# --- grid building -----------------------------------------------------------
def downsample(iw, ih, pixels, gw, gh):
    """Alpha-weighted box filter. Returns per-cell (mean_rgb, coverage 0..1)."""
    cells = []
    for r in range(gh):
        row = []
        y0, y1 = ih * r // gh, max(ih * (r + 1) // gh, ih * r // gh + 1)
        for c in range(gw):
            x0, x1 = iw * c // gw, max(iw * (c + 1) // gw, iw * c // gw + 1)
            sr = sg = sb = sa = 0.0
            n = 0
            for y in range(y0, y1):
                base = y * iw
                for x in range(x0, x1):
                    pr, pg, pb, pa = pixels[base + x]
                    sr += pr * pa; sg += pg * pa; sb += pb * pa; sa += pa
                    n += 1
            if sa > 0:
                row.append(((sr / sa, sg / sa, sb / sa), sa / (n * 255.0)))
            else:
                row.append(((0.0, 0.0, 0.0), 0.0))
        cells.append(row)
    return cells


def border_background(cells, gw, gh):
    """Dominant border-cell colour = background (images with no real alpha).
    'Dominant' = the border colour with the most border cells within the empty
    threshold of it (a 1-round medoid, robust to a few outliers)."""
    border = [cells[r][c][0] for r in range(gh) for c in range(gw)
              if r in (0, gh - 1) or c in (0, gw - 1)]
    best, bestn = border[0], -1
    for cand in border:
        n = sum(1 for b in border if redmean(cand, b) < 2200)
        if n > bestn:
            best, bestn = cand, n
    return best


def build_grid(cells, gw, gh, palette255, bg, bg_eps, alpha_cut):
    grid = []
    for r in range(gh):
        row = []
        for c in range(gw):
            rgb, cov = cells[r][c]
            if cov < alpha_cut or (bg is not None and redmean(rgb, bg) < bg_eps):
                row.append(0)
            else:
                row.append(1 + min(range(len(palette255)),
                                   key=lambda i: redmean(rgb, palette255[i])))
        grid.append(row)
    return grid


def despeckle(grid, gw, gh):
    """Isolated cells (no same-colour 4-neighbour) take the mode colour of
    their painted 3x3 neighbourhood — single-cell specks make tray dust."""
    changed = 0
    out = [row[:] for row in grid]
    for r in range(gh):
        for c in range(gw):
            v = grid[r][c]
            if v == 0:
                continue
            if any(0 <= r + dr < gh and 0 <= c + dc < gw and grid[r + dr][c + dc] == v
                   for dr, dc in ((1, 0), (-1, 0), (0, 1), (0, -1))):
                continue
            counts = {}
            for dr in (-1, 0, 1):
                for dc in (-1, 0, 1):
                    if dr == dc == 0:
                        continue
                    rr, cc = r + dr, c + dc
                    if 0 <= rr < gh and 0 <= cc < gw and grid[rr][cc] != 0:
                        counts[grid[rr][cc]] = counts.get(grid[rr][cc], 0) + 1
            if counts:
                out[r][c] = max(sorted(counts), key=lambda k: counts[k])
                changed += 1
    return out, changed


def trim(grid):
    rows = [r for r in grid if any(r)]
    if not rows:
        raise SystemExit("image quantized to an empty board — try --alpha-cut / "
                         "--bg-eps lower, or --no-bg to keep the background")
    cols = [c for c in range(len(rows[0])) if any(r[c] for r in rows)]
    return [[r[c] for c in cols] for r in rows]


# --- output ------------------------------------------------------------------
def to_lua_entry(name, grid, tray, slots):
    h, w = len(grid), len(grid[0])
    n = sum(1 for row in grid for v in row if v)
    out = [f"    {{ -- {name} ({w}x{h}, {n} cells) — generated by tools/img_to_level.py"]
    out.append(f"      slots = {slots}, w = {w}, h = {h},")
    out.append("      grid = {")
    for row in grid:
        out.append("        {" + ",".join(str(v) for v in row) + "},")
    out.append("      },")
    tray_s = ", ".join(f"{{{c},{m}}}" for (c, m) in tray)
    out.append(f"      tray = {{ {tray_s} }},")
    out.append("    },")
    return "\n".join(out)


PREVIEW_CHARS = ".12345678"


def preview(grid):
    return "\n".join("".join(PREVIEW_CHARS[v] for v in row) for row in grid)


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("image", help="input image (PNG built-in; others need Pillow)")
    ap.add_argument("--w", type=int, default=24, help="level width in cells (default 24)")
    ap.add_argument("--max-h", type=int, default=64, help="cap on level height in cells")
    ap.add_argument("--batch", type=int, default=6, help="max cells per tray batch")
    ap.add_argument("--slots", type=int, default=4, help="slots to validate against")
    ap.add_argument("--auto-palette", type=int, default=0, metavar="K",
                    help="fit a K-colour palette to the image (k-means) instead of "
                         "the game's fixed 5-food palette; prints it for the pack")
    ap.add_argument("--alpha-cut", type=float, default=0.5,
                    help="cells with alpha coverage below this are empty (default 0.5)")
    ap.add_argument("--bg-eps", type=float, default=2200.0,
                    help="redmean^2 distance to the border background under which an "
                         "opaque cell counts as empty (default 2200)")
    ap.add_argument("--no-bg", action="store_true",
                    help="keep the background: only alpha makes cells empty")
    ap.add_argument("--no-despeckle", action="store_true")
    ap.add_argument("--name", default=None, help="comment name (default: image basename)")
    ap.add_argument("--check", action="store_true", help="stats + ASCII preview only")
    args = ap.parse_args()

    iw, ih, pixels = load_image(args.image)
    gw = max(4, args.w)
    gh = max(4, min(args.max_h, round(gw * ih / iw)))
    cells = downsample(iw, ih, pixels, gw, gh)

    has_alpha = any(p[3] < 250 for p in pixels)
    bg = None
    if not has_alpha and not args.no_bg:
        bg = border_background(cells, gw, gh)

    if args.auto_palette > 0:
        samples = [cells[r][c][0] for r in range(gh) for c in range(gw)
                   if cells[r][c][1] >= args.alpha_cut
                   and (bg is None or redmean(cells[r][c][0], bg) >= args.bg_eps)]
        if not samples:
            raise SystemExit("no foreground samples for --auto-palette")
        palette255 = kmeans(samples, min(args.auto_palette, len(samples)))
    else:
        palette255 = [tuple(v * 255 for v in p) for p in GAME_PALETTE]

    grid = build_grid(cells, gw, gh, palette255, bg, args.bg_eps, args.alpha_cut)
    speckles = 0
    if not args.no_despeckle:
        grid, speckles = despeckle(grid, gw, gh)
    grid = trim(grid)
    H, W = len(grid), len(grid[0])

    tray, peak = make_tray(grid, W, H, args.batch)
    ok, steps = validate(grid, tray, W, H, args.slots)

    total = sum(1 for row in grid for v in row if v)
    ncol = len(set(v for row in grid for v in row if v))
    name = args.name or os.path.splitext(os.path.basename(args.image))[0]
    sys.stderr.write(
        f"[img_to_level] {name}: {iw}x{ih}px -> {W}x{H} cells painted={total} "
        f"colours={ncol} despeckled={speckles} batches={len(tray)} "
        f"peak_frontier_colours={peak} min_slots_for_no_wait={peak} "
        f"solvable@{args.slots}slots={ok} replay_steps={steps}\n")
    sys.stderr.write(preview(grid) + "\n")
    if args.auto_palette > 0:
        pal_s = ", ".join("{%.3f,%.3f,%.3f}" % (r / 255, g / 255, b / 255)
                          for (r, g, b) in palette255)
        sys.stderr.write(f"[img_to_level] auto palette (replace the pack's PALETTE5 "
                         f"to match): {{ {pal_s} }}\n")
    if not ok:
        sys.exit("VALIDATION FAILED: generated level did not replay to empty")
    if not args.check:
        print(to_lua_entry(name, grid, tray, args.slots))


if __name__ == "__main__":
    main()
