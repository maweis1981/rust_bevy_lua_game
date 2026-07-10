#!/usr/bin/env python3
"""gen_level.py — turn a cute pixel pattern into a solvable "ant clear" level.

The ant-clear game (assets/scripts/packs/ant_clear.lua) is a strategy-elimination
puzzle: a cute picture is drawn out of coloured pixels, and colour-matched ants
carry those pixels AWAY from the edges inward until the board is empty. The board
is only ever eaten from its frontier (the boundary between cleared/open space and
the still-painted picture), so a colour buried in the middle cannot be removed
until the colours around it are gone. That spatial coupling is what makes the
tray (the ordered queue of colour batches) a real puzzle to schedule.

This tool:
  1. builds a W*H grid of colour indices from a procedural pattern (stdlib only),
  2. runs a *peeling oracle* over the exact same frontier rule the game uses to
     emit a tray (an ordered list of {colour, count} batches) that is GUARANTEED
     solvable — front-to-front consumption reproduces the oracle, so even one
     active slot can finish it; more slots only add slack,
  3. validates solvability by replaying, and reports a difficulty read
     (batch count + peak simultaneous frontier colours = min slots for comfort),
  4. emits a Lua `LEVEL` table literal to paste into the pack (or --stdout).

Usage:
  python3 tools/gen_level.py                 # default heart, print Lua literal
  python3 tools/gen_level.py --pattern smiley --batch 6
  python3 tools/gen_level.py --check         # just validate + print difficulty
"""
import argparse
import sys
from collections import deque

# --- palettes ---------------------------------------------------------------
# index -> (r,g,b) in 0..1, index 0 is empty/background (never stored).
PALETTES = {
    "heart": [
        (0.92, 0.24, 0.34),   # 1 red body
        (0.72, 0.14, 0.26),   # 2 dark red (bottom shade)
        (1.00, 0.72, 0.78),   # 3 pink highlight
    ],
    "smiley": [
        (0.98, 0.82, 0.22),   # 1 yellow face
        (0.20, 0.18, 0.22),   # 2 dark (eyes/mouth)
        (0.95, 0.55, 0.20),   # 3 orange cheeks
    ],
}


# Hand-authored cute-animal pixel art (chars '0'..'K' index into the palette;
# '0' = empty). Natural colour regions give natural burial (interior colours are
# only reachable once the surrounding ones are carried away).
PIXEL_ART = {
    "cat": {
        "palette": [
            (0.22, 0.15, 0.11),   # 1 dark outline
            (0.93, 0.55, 0.22),   # 2 orange fur
            (0.99, 0.87, 0.66),   # 3 cream face
            (0.98, 0.66, 0.70),   # 4 pink (inner ear / nose)
            (0.34, 0.74, 0.46),   # 5 green eyes
        ],
        "rows": [
            "....11........11....",
            "...1441......1441...",
            "...1421......1241...",
            "..112211....112211..",
            "..1222221111222221..",
            ".12222222222222221..",
            ".12233333333333221..",
            ".12333333333333321.",
            "1233553333335533321",
            "1233553333335533321",
            "1233333334433333321",
            "1233333344443333321",
            "1223333333333333221",
            ".1223333333333221..",
            ".112223333322211...",
            "...1122222221111...",
            ".....11111111.....",
        ],
    },
}


def gradient(k):
    """k warm colours, outer (deep red) -> inner (light pink) — a shaded look."""
    a, b = (0.70, 0.10, 0.18), (1.00, 0.82, 0.86)
    if k == 1:
        return [a]
    return [tuple(a[i] + (b[i] - a[i]) * (j / (k - 1)) for i in range(3)) for j in range(k)]


def band_recolor(grid, w, h, k):
    """Recolour a shape's mask into `k` CONCENTRIC bands by peel depth: the
    outermost ring is colour 1, each ring inward is the next colour. Inner
    colours are physically BURIED behind outer ones, so committing a slot to an
    inner colour before its ring is exposed strands that slot — the burial that
    makes wrong choices (and the cancel/rewarded-ad recovery) meaningful."""
    mask = [[grid[r][c] != 0 for c in range(w)] for r in range(h)]
    layer = [[-1] * w for _ in range(h)]
    remaining = set((r, c) for r in range(h) for c in range(w) if mask[r][c])
    rnd = 0
    while remaining:
        frontier = []
        for (r, c) in remaining:
            for dr, dc in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                nr, nc = r + dr, c + dc
                if nr < 0 or nr >= h or nc < 0 or nc >= w or (nr, nc) not in remaining:
                    frontier.append((r, c)); break
        for cell in frontier:
            layer[cell[0]][cell[1]] = rnd; remaining.discard(cell)
        rnd += 1
    maxr = max(rnd - 1, 0)
    out = [[0] * w for _ in range(h)]
    for r in range(h):
        for c in range(w):
            if mask[r][c]:
                b = min(k - 1, int(layer[r][c] / (maxr + 1) * k))
                out[r][c] = b + 1
    return out


def build_grid(pattern, w, h):
    """Return grid[r][c] in 0..K (row 0 = TOP). Hand-authored art or procedural."""
    if pattern in PIXEL_ART:
        rows = PIXEL_ART[pattern]["rows"]
        ww = max(len(r) for r in rows)
        return [[0 if ch in "0." else int(ch) for ch in r.ljust(ww, "0")] for r in rows]
    grid = [[0] * w for _ in range(h)]
    if pattern == "heart":
        for r in range(h):
            for c in range(w):
                # normalise to heart space; y up.
                x = (c - (w - 1) / 2) / (w * 0.42)
                y = ((h - 1) / 2 - r) / (h * 0.42) + 0.35
                inside = (x * x + y * y - 1) ** 3 - x * x * (y ** 3) <= 0
                if not inside:
                    continue
                col = 1
                if y < -0.35:
                    col = 2                      # darker toward the point
                if x < -0.15 and y > 0.35 and (x + 0.5) ** 2 + (y - 0.7) ** 2 < 0.22:
                    col = 3                      # top-left highlight blob
                grid[r][c] = col
    elif pattern == "smiley":
        cx, cy, rad = (w - 1) / 2, (h - 1) / 2, min(w, h) * 0.46
        for r in range(h):
            for c in range(w):
                dx, dy = c - cx, r - cy
                if dx * dx + dy * dy > rad * rad:
                    continue
                col = 1
                # eyes
                for ex in (-0.42, 0.42):
                    if (dx - ex * rad) ** 2 + (dy + 0.25 * rad) ** 2 < (0.14 * rad) ** 2:
                        col = 2
                # mouth (lower arc)
                if dy > 0.15 * rad and dx * dx + (dy - 0.15 * rad) ** 2 < (0.62 * rad) ** 2 \
                        and dx * dx + (dy - 0.15 * rad) ** 2 > (0.42 * rad) ** 2 and dy > 0.2 * rad:
                    col = 2
                # cheeks
                for ex in (-0.62, 0.62):
                    if (dx - ex * rad) ** 2 + (dy - 0.2 * rad) ** 2 < (0.12 * rad) ** 2 and col == 1:
                        col = 3
                grid[r][c] = col
    else:
        raise SystemExit(f"unknown pattern: {pattern}")
    return grid


# --- frontier model (MUST match the game's rule) ----------------------------
def reachable_empty(grid, w, h):
    """Set of empty cells reachable from OUTSIDE the grid via 4-connected empties.
    Outside is treated as open, so every border-empty cell seeds the flood."""
    seen = [[False] * w for _ in range(h)]
    q = deque()
    for r in range(h):
        for c in range(w):
            if grid[r][c] == 0 and (r == 0 or c == 0 or r == h - 1 or c == w - 1):
                if not seen[r][c]:
                    seen[r][c] = True
                    q.append((r, c))
    while q:
        r, c = q.popleft()
        for dr, dc in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            nr, nc = r + dr, c + dc
            if 0 <= nr < h and 0 <= nc < w and not seen[nr][nc] and grid[nr][nc] == 0:
                seen[nr][nc] = True
                q.append((nr, nc))
    return seen


def frontier_cells(grid, w, h):
    """Painted cells the ants can currently reach: border cells (adjacent to the
    open outside) or cells touching a reachable-empty cell."""
    reach = reachable_empty(grid, w, h)
    out = []
    for r in range(h):
        for c in range(w):
            if grid[r][c] == 0:
                continue
            if r == 0 or c == 0 or r == h - 1 or c == w - 1:
                out.append((r, c))
                continue
            for dr, dc in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                nr, nc = r + dr, c + dc
                if 0 <= nr < h and 0 <= nc < w and grid[nr][nc] == 0 and reach[nr][nc]:
                    out.append((r, c))
                    break
    return out


# --- peeling oracle: emit a guaranteed-solvable tray ------------------------
def make_tray(grid, w, h, batch_cap):
    """Clear the whole board frontier-first, recording an ordered colour queue.
    Greedy: each step picks the colour with the most reachable frontier cells and
    clears up to `batch_cap` of them (re-expanding the frontier as it goes)."""
    g = [row[:] for row in grid]
    tray = []
    peak_colours = 0
    while True:
        front = frontier_cells(g, w, h)
        if not front:
            break
        by_colour = {}
        for (r, c) in front:
            by_colour.setdefault(g[r][c], []).append((r, c))
        peak_colours = max(peak_colours, len(by_colour))
        # pick colour with the largest reachable frontier (stable on ties)
        colour = max(sorted(by_colour), key=lambda k: len(by_colour[k]))
        cleared = 0
        while cleared < batch_cap:
            front = frontier_cells(g, w, h)
            cells_c = [(r, c) for (r, c) in front if g[r][c] == colour]
            if not cells_c:
                break
            r, c = cells_c[0]
            g[r][c] = 0
            cleared += 1
        tray.append((colour, cleared))
    return tray, peak_colours


def validate(grid, tray, w, h, slots):
    """Replay: fill `slots` from the tray front; each active slot clears its
    colour's reachable frontier cells. Confirms the board empties and the tray
    colour sums match the board's per-colour counts."""
    # count check
    want = {}
    for row in grid:
        for v in row:
            if v:
                want[v] = want.get(v, 0) + 1
    got = {}
    for (col, n) in tray:
        got[col] = got.get(col, 0) + n
    assert want == got, f"tray/board mismatch: board={want} tray={got}"

    g = [row[:] for row in grid]
    queue = list(tray)
    active = []  # list of [colour, remaining]
    guard = 0
    limit = sum(want.values()) * 4 + 100
    while (queue or active) and guard < limit:
        guard += 1
        while len(active) < slots and queue:
            col, n = queue.pop(0)
            active.append([col, n])
        progressed = False
        for slot in active:
            col = slot[0]
            front = frontier_cells(g, w, h)
            cells_c = [(r, c) for (r, c) in front if g[r][c] == col]
            if cells_c and slot[1] > 0:
                r, c = cells_c[0]
                g[r][c] = 0
                slot[1] -= 1
                progressed = True
        active = [s for s in active if s[1] > 0]
        if not progressed and active and not queue:
            break
    remaining = sum(1 for row in g for v in row if v)
    return remaining == 0, guard


# --- Lua emit ---------------------------------------------------------------
def to_lua(name, pal, grid, tray, w, h):
    lines = []
    lines.append(f"{name} = {{")
    lines.append(f"  w = {w}, h = {h},")
    pal_s = ", ".join(f"{{{r:.3f},{g:.3f},{b:.3f}}}" for (r, g, b) in pal)
    lines.append(f"  palette = {{ {pal_s} }},")
    lines.append("  -- grid rows, top to bottom; 0 = empty")
    lines.append("  grid = {")
    for row in grid:
        lines.append("    {" + ",".join(str(v) for v in row) + "},")
    lines.append("  },")
    tray_s = ", ".join(f"{{{c},{n}}}" for (c, n) in tray)
    lines.append(f"  tray = {{ {tray_s} }},")
    lines.append("}")
    return "\n".join(lines)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--pattern", default="heart", choices=list(PALETTES) + list(PIXEL_ART))
    ap.add_argument("--w", type=int, default=15)
    ap.add_argument("--h", type=int, default=14)
    ap.add_argument("--batch", type=int, default=6, help="max cells per tray batch")
    ap.add_argument("--slots", type=int, default=3, help="active slots to validate against")
    ap.add_argument("--bands", type=int, default=0,
                    help="recolour the shape into N concentric colour bands (buries inner "
                         "colours so wrong slot choices can strand you). 0 = keep pattern colours")
    ap.add_argument("--name", default="LEVEL", help="Lua global name for the emitted table")
    ap.add_argument("--check", action="store_true", help="only validate + report, no Lua")
    ap.add_argument("--stdout", action="store_true", help="print Lua (default if not --check)")
    args = ap.parse_args()

    grid = build_grid(args.pattern, args.w, args.h)
    W, Hn = len(grid[0]), len(grid)      # authored art carries its own dimensions
    if args.bands > 0:
        grid = band_recolor(grid, W, Hn, args.bands)
        pal = gradient(args.bands)
    elif args.pattern in PIXEL_ART:
        pal = PIXEL_ART[args.pattern]["palette"]
    else:
        pal = PALETTES[args.pattern]
    args.w, args.h = W, Hn
    tray, peak = make_tray(grid, W, Hn, args.batch)
    ok, steps = validate(grid, tray, W, Hn, args.slots)

    total = sum(1 for row in grid for v in row if v)
    ncol = len(set(v for row in grid for v in row if v))
    sys.stderr.write(
        f"[gen_level] pattern={args.pattern} bands={args.bands} {args.w}x{args.h} "
        f"painted={total} colours={ncol} batches={len(tray)} "
        f"peak_frontier_colours={peak} min_slots_for_no_wait={peak} "
        f"solvable@{args.slots}slots={ok} replay_steps={steps}\n"
    )
    if not ok:
        sys.exit("VALIDATION FAILED: level is not solvable")
    if not args.check:
        print(to_lua(args.name, pal, grid, tray, args.w, args.h))


if __name__ == "__main__":
    main()
