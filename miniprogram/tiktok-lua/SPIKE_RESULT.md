# fengari spike — "one Lua, everywhere" (RESULT: ✅ feasible)

**Question this spike answers:** can the *exact same* native game script
(`assets/scripts/main.lua`, byte-for-byte, no fork) run on the TikTok / web
target — so TikTok stops being a hand-maintained JS re-implementation and
becomes a third runtime of the single Lua source, alongside mlua (desktop/iOS)
and ottavino (wasm)?

**Answer: yes.** This directory boots that unmodified `main.lua` inside
[fengari](https://fengari.io) (a Lua 5.3 VM compiled to JS), over a ~180-line JS
`game.*` bridge (`engine.js`) and a generic Canvas 2D renderer. No changes to the
Lua were needed.

## What runs here

- `vendor/fengari-web.js` — the Lua VM in JS (219 KB raw, ~70 KB gzipped).
- `engine.js` — the bridge: builds the global `game` table (every one of the 20
  `game.*` functions `main.lua` calls, as `lua_CFunction`s), a scene Map the Lua
  mutates via `spawn/move_to/set_color/...`, a z-sorted Canvas renderer, input
  wiring (touch + mouse → `game.pointer()` / `on_tap`), a `save`/`load` codec over
  `localStorage` matching the native `s:`/`n:`/`b:` typing, and the frame loop that
  calls `on_start` / `on_update(dt)` / `on_tap(x,y)`.
- `main.lua` — **a verbatim copy of `assets/scripts/main.lua`** (the diff is empty;
  this is the whole point). In production this would be fetched from the one source,
  not copied.
- `textures/` — the PNGs the three shipped games reference.
- `index.html` — loads fengari + engine, `fetch()`es `main.lua`, boots.

## Verified (headless Chromium, portrait 450×800)

- `on_start` runs → logs `Mini-game collection — started`.
- **Menu renders** (title, subtitle, textured Grow/Breakout/Snake tiles, Settings) —
  see `shot_menu.png`.
- **A game plays**: tapping Grow enters it; paddles, ball + motion trail, HUD, center
  line all render and animate — see `shot_game.png`.
- **60 fps** on both menu and gameplay; **zero page errors, zero 404s, zero Lua errors.**

## Caveats before this replaces the JS port

1. **Perf gate is a real low-end Android webview, not desktop SwiftShader.** 60 fps here
   proves correctness, not that a 2019 Android phone inside the TikTok webview holds frame.
   That is the one measurement that must pass before we migrate.
2. **Lua 5.3 vs 5.4.** fengari is 5.3. `main.lua` uses no 5.4-only syntax (no `//` integer
   div in hot paths, no `<close>`, no `goto`), so it loads clean — but a CI lint
   (`lua5.3 -p`-style parse of every script) should guard this permanently, per the
   blueprint.
3. **Determinism.** Seeded runs must use `GAME_KIT.rng` (LCG), not `math.random`, so a
   daily/seeded challenge matches across mlua/ottavino/fengari. Already the KIT rule.
4. **Juice fidelity.** This spike stubs sound/particles/zoom (renderer honours `shake`
   trauma only). The production fengari runtime reuses the existing
   `miniprogram/shared/{sound,particles}.js` behind the same bridge — no Lua change.

## Bottom line

The pivotal platform thesis holds: **TikTok can be a runtime of the one Lua source, not a
parallel codebase.** Recommend proceeding to the on-device perf measurement (blueprint
Phase 1); if it passes, retire the hand-written `miniprogram/shared/game.js` port in favour
of this path.
