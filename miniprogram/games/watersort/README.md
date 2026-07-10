# Water Sort — playable prototype (TikTok Mini Games / HTML runtime)

A dependency-free **plain JS + Canvas 2D** Ball/Water Sort puzzle, built as the
first pick from `docs/tiktok-minigame-selection.md` (lowest build cost, high
rewarded-ad opportunity, low annoyance). It reuses the same conventions as the
Time Dodge port (`../../shared`): a platform adapter (`canvas` / touch /
`storage` / `rewardAd` / `raf` / `now`), the exact seeded LCG for reproducible
levels, and rewarded video as the only monetization primitive.

## Play it

```bash
cd miniprogram/games/watersort
sh build.sh                 # bundle *.js -> bundle.js (browser require registry)
python3 -m http.server      # open index.html — SDK no-ops outside TikTok
```

Tap a tube to pick up its top color run, tap another to pour (legal onto an
empty tube or a matching top color with room). Sort every tube to one color.

## Files

| File | Role |
|------|------|
| `logic.js` | pure state machine: seeded level gen, pour rules, win, undo, **BFS solver** (guarantees solvable levels + powers the Hint reward). No DOM/platform — runs in Node. |
| `config.js` | tunables (capacity, per-level color ramp, palette). |
| `game.js` | game core: level + pixel layout + tap hit-testing + reward actions + pour animation. `createGame(platform)`. |
| `render.js` | Canvas 2D drawing. `createRenderer(ctx,W,H).draw(game)`. |
| `main.js` | standalone frame loop + tap wiring (raw pixels; it's a tap game). |
| `index.html` | HTML-runtime harness (DOM adapter + `TTMinis` rewarded-ad hook, auto-grant fallback in preview). |
| `build.sh` | generates `bundle.js` (gitignored). |
| `test.js` | Node invariant harness (24 checks). Run: `node test.js`. |

## Rewarded-video placements (the point)

All opt-in, tied to non-frustrating moments (per the selection analysis):

- **HINT ▶** — watch a rewarded video → the solver highlights the next best move.
- **+TUBE ▶** — watch a rewarded video → add one empty spare tube (rescues a
  stuck board). The reward is gated on ad completion (`isEnded`), matching the
  Time Dodge contract.
- **UNDO** — free (kept frictionless); a natural spot to gate *extra* undos
  behind an ad later.
- On solve → **tap to continue** to the next (harder) level; a natural spot for
  an end-of-level ×2-coins rewarded prompt once a coin economy exists.

## Status

Verified headless: `node test.js` (24/24) and a Chromium playtest that drives the
real tap path through a full solver plan to **SOLVED → next level**, exercising
the +TUBE and HINT reward flows. Not yet wired into a JS collection router
(there's only one JS game today); when a second lands, fold this in as a
subpackage alongside Time Dodge.
