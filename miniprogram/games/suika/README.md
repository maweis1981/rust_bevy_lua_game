# Suika — watermelon merge-drop (TikTok Mini Games / HTML runtime)

A dependency-free **plain JS + Canvas 2D** Suika (merge-drop) game, mirroring the
sibling `../watersort` conventions: a `platform` adapter (`canvas` / touch /
`storage` / `rewardAd` / `raf` / `now`), the exact seeded LCG for a reproducible
next-fruit sequence, a browser `require`-shim bundle, and rewarded video as the
only monetization primitive. Runs headless in **Node** (the test) and in a
**headless browser** (the standalone harness).

## Play it

```bash
cd miniprogram/games/suika
sh build.sh                 # bundle *.js -> bundle.js (browser require registry)
python3 -m http.server      # open index.html — SDK no-ops outside TikTok
```

Tap/click a column to drop the current fruit. Two fruit of the **same tier** that
touch **merge** into one fruit of tier+1 at their midpoint (score += that tier's
value). Only small fruit (tiers 0..4) ever drop; bigger fruit arise only from
merges. If any fruit **rests above the danger line for ~2 s**, the run ends.
Merging two **max-tier** (watermelon) fruit **pops** both for a bonus.

## Files

| File | Role |
|------|------|
| `logic.js` | pure, headless-steppable **simulation**: seeded next-fruit rng, circle physics (gravity, walls, position-based separation + light impulse), same-tier **merge**, danger-line **game-over** predicate, revive. No DOM/platform — runs in Node. |
| `config.js` | tunables: tier radii/colors/points, physics constants, rules. Pure data. |
| `game.js` | game core: sim + pixel layout (bin, danger line, buttons) + tap/aim input + reward actions + best-score persistence + its **own full-frame `draw(ctx)`**. `createGame(platform)`. |
| `render.js` | Canvas 2D drawing. `createRenderer(ctx).draw(game)` (reads `game.view()`). |
| `main.js` | standalone frame loop: computes real `dt`, drives `update(dt,tSec)` + `draw(ctx)`. |
| `index.html` | HTML-runtime harness (DOM adapter + `TTMinis` rewarded-ad hook, auto-grant fallback in preview). |
| `build.sh` | generates `bundle.js` (gitignored). |
| `test.js` | Node invariant harness (21 checks). Run: `node test.js`. |

## Physics (stability notes)

The sim advances in **fixed timesteps** (`FIXED_DT = 1/120 s`, `MAX_STEPS_PER_FRAME`
caps catch-up so a frame hitch can't explode the sim). Each fixed step runs
`SUBSTEPS` integration substeps, each with `ITERS` **position-relaxation** passes:
walls confine, then pairwise **position-based separation** (mass ∝ area, 0.8
relaxation to avoid overshoot) plus a **tiny** normal-impulse restitution so
stacks settle without jitter or blow-up. Velocities are clamped, coincident
centers use a deterministic fallback normal (never NaN), and every integrate
guards against non-finite values. `test.js` drives **5000+ steps** of random
drops on two bins and asserts **zero NaN**, all fruit **inside the bin**, count
≤ `MAX_FRUIT`, and peak speed under the clamp.

## Two integration surfaces

1. **Standalone** — `main.js`'s `startGame(platform)` + `index.html` (same DOM
   adapter, mouse+touch, `localStorage`, TTMinis rewarded-ad hook with auto-grant
   fallback). `build.sh` bundles `config,logic,game,render,main`.
2. **Collection contract** — `game.js` exports `createGame(platform)` returning a
   router-friendly object:
   - `setSize(W, H, topInset)` — canvas pixels; `topInset` (default 0) reserves
     the top of the canvas empty for a router-drawn back button (HUD + bin are
     laid out below it).
   - `tap(px, py)` — drop at that column (or hit a game-over overlay button).
   - `pointer(px, py, down)` — drag to move the aim guide (optional).
   - `update(dt, tSec)` — advance the sim (fixed-step internally).
   - `draw(ctx)` — renders the **entire** frame (delegates to `render.js`; the
     renderer is cached and rebound if the router passes a different `ctx`).
   - also `view()` and a `DEBUG` surface for headless probing.

## Rewarded-video placements (the point)

All opt-in, gated on ad completion (`reward === true`), tied to the natural
game-over beat so they never nag mid-play:

- **REVIVE ▶** — watch a rewarded video → clear the top few fruit above the
  danger line and resume (once per run).
- **×2 SCORE ▶** — watch a rewarded video → double the final score before it's
  recorded as `best` (once per run).
- **RESTART** — free.

## Status

Verified headless: `node test.js` (21/21) and a Chromium playtest (390×844,
dpr 2) that drops a dozen fruit across columns and screenshots stacked/**merged**
fruit (tiers up to 6 from tier-0..4 drops, score climbing, no NaN, run alive).
Not yet wired into a JS collection router; the `createGame` contract above is
ready for one to own the loop.
