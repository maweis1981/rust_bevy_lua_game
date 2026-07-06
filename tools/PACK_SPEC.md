# Game-Pack Spec — how to author a playable Lua game pack

A "game pack" is one Lua file in `assets/scripts/`. It runs on the Rust host
(Bevy) which loads Lua as an asset (hot-reload on desktop, bundled on iOS). The
pack **only** talks to the host through the global `game` table and the shared
`GAME_KIT` helpers — it never touches the engine directly. Follow this exactly or
the pack won't load / won't be accepted.

## The scene contract
Define a factory `make_<key>()` returning a table with these callbacks:
- `enter()`            — called when the scene becomes active (reset per-play flags)
- `leave()`            — called when leaving (despawn everything you spawned)
- `update(dt, hw, hh)` — per frame; `hw,hh` = screen HALF-extents (origin at centre, +y up)
- `tap(x, y)`          — a tap/click at world coords

Then **self-register** at the end of the file (keyed by `key`, reload-safe):
```lua
PACKS = PACKS or {}
PACKS["<key>"] = { slot = 20, key = "<key>", label = "Title", short = "Title",
  icon = "<texture>", color = { r, g, b }, tier = "ai", make = make_<key> }
```
`tier` is `preset` | `curated` | `ai` (use `ai` for AI-generated). `slot` orders
within a tier. The menu is built automatically from PACKS — no other edits.

## The `game` API (the ONLY host calls allowed)
- `game.spawn(x,y,w,h, r,g,b,a) -> id`         solid colour rect
- `game.spawn_sprite(x,y,w,h, name) -> id`     textured; `assets/textures/<name>.png` MUST already exist
- `game.spawn_text(x,y,size, r,g,b,a, str) -> id`   text; ASCII always safe. CJK renders ONLY if the
  glyphs are registered in tools/subset_font.py (game.ttf is a Noto Sans subset) — then re-run it
- `game.move_to(id,x,y)` · `game.set_color(id,r,g,b,a)` · `game.set_size(id,w,h)`
- `game.set_rotation(id, radians)` · `game.set_sprite_image(id, name)` · `game.despawn(id)`
- `game.set_text(str)`                          top-left HUD line (respect SETTINGS.hud; router blanks it when off)
- `game.shake(0..1)` · `game.zoom(0..1)` (camera punch-in, decays back) · `game.play_sound("hit"|"wall"|"score")` · `game.haptic("light"|"medium"|"heavy"|"success")`
- reads: `game.pointer() -> x,y,down` · `game.key(name)` · `game.bounds() -> hw,hh`

## GAME_KIT helpers (shared)
`K = GAME_KIT`: `K.clamp(v,lo,hi)`, `K.sign(v)`, `K.in_rect(rect,x,y)` (rect = {x,y,w,h}),
`K.tracker()` -> `T` with `T.spawn/T.sprite/T.text` (auto-tracked) + `T.clear()`,
`K.make_back(T,hw,hh) -> rect` (a "back to lobby" button; hit-test it in `tap`),
`K.switch("menu")` to return to the menu.

## Existing textures you may use (no new art)
orb, paddle, brick, tile, food, gem, hero, enemy, snakehead, snakebody, flower,
villager, tree, rock, ship, alien, shot, sparkle, gberry, gdaisy, gbell, gleaf,
gviola, gmush, pony, icon_heart, icon_coin, icon_bolt, icon_trophy, icon_clock, icon_bulb,
icon_trash, icon_find, icon_eye, icon_pin, rtile, rxmark, rpill, rcard, vg_coach{,_t,_f},
vg_ol{,_t,_f}, vg_teacher{,_t,_f}, vg_gallery, vg_gallery_dark (rounded UI + VN art, from
tools/gen_ui_tiles.py). (`game.set_color` tints the grayscale/white ones: orb/paddle/brick/tile/rtile/rxmark/rpill/rcard.)

## Hard rules
1. On-screen text: **ASCII is always safe**. CJK is allowed ONLY for glyphs already in
   `tools/subset_font.py`'s STRINGS list (add yours + re-run it); unregistered glyphs render blank.
2. Only reference textures that already exist (list above).
3. Errors are non-fatal (logged) — but a broken pack is rejected. Don't rely on that.
4. `update` runs on the main thread every frame — keep it O(few hundred) ops; no busy loops.
5. Clamp movers to the screen (`hw,hh`); never let sprites fly off forever.
6. Clean up in `leave()` (use `K.tracker()` so `T.clear()` despawns everything).
7. Expose a `DEBUG` table when built: `DEBUG = { game="<key>", back=<rect>, ... }` plus a
   few state readers (e.g. `score = function() return score end`, `alive = function() return playing end`)
   so the headless test harness can drive it.

## Minimal skeleton
```lua
function make_<key>()
  local K = GAME_KIT
  local T = K.tracker()
  local built, back, playing = false, nil, true
  local function build(hw, hh)
    -- spawn sprites/text via T.*; back = K.make_back(T, hw, hh)
    built = true
    DEBUG = { game = "<key>", back = back, alive = function() return playing end }
  end
  return {
    enter = function() built = false end,
    leave = function() T.clear(); built = false end,
    tap = function(x, y) if back and K.in_rect(back, x, y) then K.switch("menu") end end,
    update = function(dt, hw, hh) if not built then build(hw, hh) end
      -- gameplay here; read game.pointer()/game.key(); use game.* to draw
    end,
  }
end
PACKS = PACKS or {}
PACKS["<key>"] = { slot = 20, key = "<key>", label = "Title", short = "Title",
  icon = "food", color = { 0.6, 0.5, 0.9 }, tier = "ai", make = make_<key> }
```

## Validation (a pack is "accepted" only if all pass)
- Loads with no Lua error; `make_<key>()` returns the 4 callbacks.
- Appears in the menu and can be entered; `DEBUG.game == "<key>"`; `DEBUG.back` exists.
- Runs thousands of headless frames without error; sprites stay within `hw,hh`.
- Back button returns to the menu; a lose/again path (if any) works.
