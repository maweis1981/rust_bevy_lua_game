# Mini Arcade — the JS collection shell (TikTok Mini Games)

The **collection shell** the repo always described but the JS side never had:
one menu that routes between several dependency-free Canvas-2D games, sharing a
platform adapter and a rewarded-ad meta layer. This is what turns the individual
games (`../watersort`, `../suika`, and the Time Dodge engine in `../../shared`)
into a single shippable TikTok mini-game.

## Run it

```bash
cd miniprogram/games/shell
sh build.sh                 # bundles menu+router+admeta + each game (isolated) -> bundle.js
python3 -m http.server      # open index.html — SDK no-ops / auto-grants outside TikTok
```

## How it fits together

```
index.html ── DOM platform adapter (canvas, touch, localStorage, TTMinis rewarded ad)
   └─ main.js  startShell(platform)
        ├─ admeta.js   shared rewarded-ad layer (coins, daily spin, x2, revive)
        ├─ registry.js adapts each game's native shape to one router contract
        └─ router.js   owns the RAF loop + input; menu ⇄ game; a top "‹ MENU" bar
             └─ menu.js the game grid + daily spin
```

### The router contract (why any game drops in unchanged)

The router reserves a top **BAR** for the back button and runs the current game
in the space **below** it: it sizes the game to `(W, H-BAR)`, translates the
game's `draw(ctx)` by `(0, BAR)`, and offsets input `y` by `-BAR`. So each game
draws in its own 0-based space and never knows the shell exists. `registry.js`
wraps each game's native API into the uniform instance:

```
{ setSize(W,H), tap(px,py), pointer(px,py,down), update(dt,tSec), draw(ctx) }
```

- **Water Sort** — pixel/tap; drawn via its `createRenderer(ctx,W,H).draw(game)`.
- **Time Dodge** (`../../shared`) — world coords (centre origin, +y up), hold-to-
  flow pointer, its own sub-menu; the adapter converts pixels↔world and passes a
  time arg to its renderer.
- **Suika** — exposes its own `createGame` with `draw(ctx)`; adapter is a pass-through.

Games load as **isolated modules** on `window.__games[<id>]` (see `build.sh`),
each with its own private `require` registry, so their shared basenames
(`config.js`, `game.js`, …) never collide in one bundle.

### The rewarded-ad meta layer (`admeta.js`)

Shared, opt-in, reward-gated (`isEnded`) helpers so every game monetizes the
same non-annoying way (per `docs/tiktok-minigame-selection.md`): `rewardedDouble`
(end-of-run ×2), `rewardedContinue` (revive), a collection **coins** balance, and
a menu **DAILY SPIN**. Individual games also call `platform.rewardAd` directly
for their in-run rewards (Water Sort HINT/+TUBE, Suika REVIVE/×2).

## Adding a game

1. Drop a game dir under `miniprogram/games/<id>/` exposing `createGame(platform)`
   (see `../watersort` or `../suika` as templates).
2. Add its file list to `build.sh`'s `emit_game` calls.
3. Add an adapter + entry in `registry.js` (`buildRegistry`).
The menu, router, back-nav, and ad layer all just work.

## Status

Verified headless (Chromium 390×844): menu renders all three cards; each game
launches, plays (Suika drops+merges, Water Sort pours+animates, Time Dodge shows
its sub-menu and the hold-to-flow orb), and the ‹ MENU bar returns to the menu —
**zero page errors** across the flow. Not yet wired into the WeChat/Douyin
subpackage build (those are separate roots); the shell targets the TikTok HTML
runtime today.
