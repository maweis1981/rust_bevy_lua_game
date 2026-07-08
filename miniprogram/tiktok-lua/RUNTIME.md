# fengari runtime — "one Lua, everywhere" (TikTok / web)

This directory is a **production runtime** of the single Lua game source. It runs
the *unmodified* native scripts (`assets/scripts/main.lua` + the shipped
`assets/scripts/packs/*.lua`, byte-for-byte) on the TikTok / web target via
[fengari](https://fengari.io) — a Lua 5.3 VM compiled to JS — over a JS `game.*`
bridge (`engine.js`) and a Canvas 2D renderer that is this platform's
"native presentation" backend. The Lua is identical to what mlua (iOS) and
ottavino (wasm) run; only the host differs. See `docs/PLATFORM_BLUEPRINT.md`.

It began as a feasibility spike (does the same Lua even load under fengari?). It
now implements the **full** `game.*` surface the shipped packs use, for real.

## What's here

- `vendor/fengari-web.js` — the Lua VM in JS (~220 KB raw, ~70 KB gz).
- `engine.js` — the runtime: the `game.*` bridge + Canvas renderer. Implements
  every core call (spawn/move/color/size/rotate/despawn/text, pointer/touches/
  key/bounds/date_utc) **and** the juice layer for real:
  - **particles** — the 4 native presets (spark/dust/confetti/splash) with matching
    speed/gravity/ttl/colours, additive-glow draw, 512 cap.
  - **audio** — Web Audio: `play_sound` (overlap + same-frame dedup), `play_music`
    (one loop, no restart on re-request), `play_voice` (single channel, stops the
    previous line), `stop_music`/`stop_voice`, per-channel `set_volume`. Missing
    files degrade to silence.
  - **camera** — `zoom` punch-in (native `zoom_scale`), `cam(dx,dy,zoom)`, `shake`
    trauma jitter.
  - **background** — a reactive cosmic/nebula backdrop; `space_mode(true)` and
    `set_bg_theme(n)` switch it; drifting stars + nebula blooms brighten with
    gameplay energy (smoothed shake trauma), echoing the native aurora shader.
  - **postFx** — energy bloom flash + vignette.
  - `haptic` → `navigator.vibrate`; `open_url` → new tab; `track` → no-op (the
    analytics sink lives in the native Rust bridge).
  - showcase-only heavy calls (`spawn_rig`/`play_anim`/`set_bone`/`tilemap`/
    `set_tile`) are safe stubs; `showcase` is not in the ship bundle.
- `main.lua`, `packs/` — the assembled Lua (from `prepare.sh`; a verbatim copy of
  the native scripts — the diff is empty, that's the point).
- `textures/`, `audio/` — the assets those scripts reference.
- `manifest.json` — pack load order (packs self-register into `PACKS`, then
  `main.lua` reads it in `on_start`).
- `index.html` — loads fengari + engine, fetches the manifest, boots. Append
  `?scene=<key>` to jump straight into one game (ad-campaign landing); the native
  `AUTOBOOT` global does the rest.
- `prepare.sh` — re-assembles the bundle from `assets/` after any Lua/asset change.

## Shipped games

The whole collection, from the one source — kept in sync with the native
`EXTRA_SCRIPTS` list + `scripts/packs/`:

- **main.lua**: Grow, Breakout, Snake
- **top-level games** (`games/`, native `EXTRA_SCRIPTS`): Rogue, 2048, Shooter,
  Cozy Isle, Craft, Gem Match, Umami Cup
- **packs** (`packs/`): Time Dodge, Catch, Forge, Glow (fireflies), Ponies,
  Mystery (gallery)

= **17 games**, identical to what the web (ottavino) build shows.
`showcase` is excluded (engine tech-demo; the only module needing rigs/tilemap).

The **TikTok** package (`package-tiktok.sh`) ships the tight **arcade subset** —
the top-level games + Catch/Forge/Glow/Time Dodge (14 games), dropping the
visual-novel packs (Ponies, Mystery) and their heavy VN backdrops/BGM to stay
lean. Web/native keep the full 17.

## Verified (headless Chromium, portrait 450×800)

Menu (full collection), Time Dodge (cosmic bg + modes), Grow (paddles/ball/trail),
Forge (glow core + HUD): all **60 fps, zero page errors, zero Lua errors**. See
`verify_*.png`. The remaining gate before this replaces the hand-written JS port
is on-device frame rate on a real low-end Android webview — correctness is proven;
that one measurement is not.

## Rebuild / run

```sh
sh miniprogram/tiktok-lua/prepare.sh          # refresh Lua + assets from source
cd miniprogram/tiktok-lua && python3 -m http.server 8099
# open http://localhost:8099/  (or ?scene=timedodge)
```
