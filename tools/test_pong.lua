-- Automated tests for assets/scripts/main.lua (the mini-game collection).
--
-- Mocks the Rust `game` API and drives the router + each game headless under
-- lua5.4. Games expose a `DEBUG` table (key entities/state) so tests can find
-- them without guessing spawn order. Ball type / RNG is controlled by overriding
-- math.random; input by driving the mock pointer (relative drag) and keys.
--
-- Run: lua5.4 tools/test_pong.lua   (exits non-zero on any failure)

local HW, HH = 215, 466
local DT = 1 / 60

----------------------------------------------------------------------
-- RNG override
----------------------------------------------------------------------
local rand_mode = "mixed"
local rng = 987654321
local function lcg() rng = (1103515245 * rng + 12345) % 2147483648; return rng / 2147483648 end
math.random = function(a, b)
  local r
  if rand_mode == "good" then r = 0.1 elseif rand_mode == "bad" then r = 0.9 else r = lcg() end
  if a == nil then return r end
  if b == nil then return math.floor(r * a) + 1 end
  return math.floor(r * (b - a + 1)) + a
end

----------------------------------------------------------------------
-- Mock host API
----------------------------------------------------------------------
local dims, pos, max_id = {}, {}, 0
local frame_events
local function record(n, a) if frame_events then frame_events[#frame_events + 1] = { n, a } end end

game = {
  log = function(m) record("log", m) end,
  bounds = function() return HW, HH end,
  spawn = function(x, y, w, h) max_id = max_id + 1; dims[max_id] = { w = w, h = h }; pos[max_id] = { x = x, y = y }; return max_id end,
  spawn_sprite = function(x, y, w, h) max_id = max_id + 1; dims[max_id] = { w = w, h = h }; pos[max_id] = { x = x, y = y }; return max_id end,
  spawn_text = function(x, y) max_id = max_id + 1; dims[max_id] = { w = 0, h = 0 }; pos[max_id] = { x = x, y = y }; return max_id end,
  move_to = function(id, x, y) pos[id] = { x = x, y = y } end,
  set_color = function() end,
  set_size = function(id, w, h) dims[id] = { w = w, h = h } end,
  set_rotation = function() end,
  set_sprite_image = function() end,
  spawn_sheet = function(x, y, w, h) max_id = max_id + 1; dims[max_id] = { w = w, h = h }; pos[max_id] = { x = x, y = y }; return max_id end,
  set_frame = function() end,
  tilemap = function(x, y) max_id = max_id + 1; dims[max_id] = { w = 0, h = 0 }; pos[max_id] = { x = x, y = y }; return max_id end,
  set_tile = function() end,
  spawn_rig = function(x, y) max_id = max_id + 1; dims[max_id] = { w = 0, h = 0 }; pos[max_id] = { x = x, y = y }; return max_id end,
  play_anim = function(id, c) record("anim", c) end,
  set_bone = function() end,
  despawn = function(id) pos[id] = nil; dims[id] = nil end,
  set_text = function() end,
  shake = function(v) record("shake", v) end,
  zoom = function(v) record("zoom", v) end,
  cam = function(x, y, z) record("cam", z) end,
  set_bg_theme = function(v) record("bg_theme", v) end,
  emit = function(p) record("emit", p) end,
  set_native_bg = function(n) record("native_bg", n) end,
  play_sound = function(n) record("sound", n) end,
  play_music = function(n) record("music", n) end,
  play_voice = function(n) record("voice", n) end,
  stop_voice = function() record("stopvoice") end,
  stop_music = function() record("stopmusic") end,
  set_volume = function(c, v) record("volume", c) end,
  track = function(e, p) record("track", e) end,
  open_url = function(u) record("open_url", u) end,
  -- Ad director mock: ad_moment is a no-op log; ad_ready is always false (Null
  -- backend parity); ad_reward defers the callback to the NEXT pumped frame and
  -- fires it exactly once with granted=false/no_fill (mirrors apply_ad_events).
  _ad_pending = {},
  ad_moment = function(p) record("ad_moment", p) end,
  ad_ready = function(k) return false end,
  ad_reward = function(k, cb)
    game._ad_pending[#game._ad_pending + 1] = cb
  end,
  _store = {},
  save = function(k, v)
    local t = type(v)
    if t ~= "string" and t ~= "number" and t ~= "boolean" then return false end
    game._store[k] = v; record("save", k); return true
  end,
  load = function(k) return game._store[k] end,
  _touches = {},
  date_utc = function() return 2026, 7, 7 end,
  touches = function() return game._touches end,
  haptic = function(k) record("haptic", k) end,
  pointer = function() return game._px, game._py, game._down end,
  key = function(n) return game._keys[n] == true end,
  _px = nil, _py = nil, _down = false, _keys = {},
}
local function events_have(n, a)
  for _, e in ipairs(frame_events) do if e[1] == n and (a == nil or e[2] == a) then return true end end
  return false
end
local function clear_input() game._px, game._py, game._down, game._keys = nil, nil, false, {} end

----------------------------------------------------------------------
-- Assertions
----------------------------------------------------------------------
local failures, checks, seen = {}, 0, {}
local function check(c, m) checks = checks + 1; if not c then failures[#failures + 1] = m end end
local function check_once(k, c, m)
  checks = checks + 1
  if not c and not seen[k] then seen[k] = true; failures[#failures + 1] = m end
end

-- Mirror the engine's load order: extra game files first, then main.lua.
dofile("assets/scripts/roguelike.lua")
dofile("assets/scripts/game2048.lua")
dofile("assets/scripts/shooter.lua")
dofile("assets/scripts/world.lua")
dofile("assets/scripts/craftworld.lua")
dofile("assets/scripts/match3.lua")
dofile("assets/scripts/umami.lua")
dofile("assets/scripts/packs/catch.lua")
dofile("assets/scripts/packs/ponies.lua")
dofile("assets/scripts/packs/gallery.lua")
dofile("assets/scripts/packs/showcase.lua")
dofile("assets/scripts/packs/timedodge.lua")
dofile("assets/scripts/main.lua")

-- Reseed the LCG each boot so every test scenario is deterministic and
-- independent of how many random draws earlier tests consumed.
local function boot() rng = 987654321; frame_events = {}; on_start(); frame_events = {}; on_update(DT) end
local function enter(key)
  clear_input()
  for _, t in ipairs(DEBUG.tiles) do                 -- menu exposes its tiles
    if t.key == key then on_tap(t.x, t.y); break end
  end
  frame_events = {}; on_update(DT)          -- first update builds the scene
  return DEBUG
end
local function step(dt) frame_events = {}; on_update(dt or DT) end

----------------------------------------------------------------------
-- Router navigation
----------------------------------------------------------------------
local function router_tests()
  boot()
  -- timedodge replaced the wooden Home button with a confirm-gated "return to
  -- base" icon, so it exits via base -> confirm YES (see back_to_menu).
  local function back_to_menu(d)
    if d.base then                          -- timedodge: icon + confirm dialog
      on_tap(d.base().x, d.base().y); step()
      local c = DEBUG.confirm and DEBUG.confirm()
      if c then on_tap(c.yes.x, c.yes.y); step() end   -- confirm only during a run
    else
      on_tap(d.back.x, d.back.y); step()    -- other games: the wooden Home button
    end
  end
  for _, key in ipairs({ "grow", "breakout", "snake", "roguelike", "game2048", "shooter", "world", "craft", "match3", "umami", "catch", "ponies", "gallery", "timedodge" }) do
    local d = enter(key)
    check(d and d.game == key, "menu tile should enter game '" .. key .. "'")
    check(d.back ~= nil or d.base ~= nil, "game '" .. key .. "' should expose a way back")
    back_to_menu(d)
    local d2 = enter(key)                   -- re-entering should work (menu was active)
    check(d2 and d2.game == key, "back button should return to the menu (re-enter '" .. key .. "')")
    back_to_menu(d2)
  end
end

----------------------------------------------------------------------
-- Game 1: Grow the Paddle — physics + size mechanic (relative drag)
----------------------------------------------------------------------
local function grow_physics(frames, dt)
  boot(); rand_mode = "mixed"
  local d = enter("grow")
  local ball, left, right = d.ball, d.left, d.right
  local ball_hw = dims[ball].w * 0.5
  local pad_hw = dims[left].w * 0.5
  local ai_hh = dims[right].h * 0.5
  local prev_ball, prev_left, prev_lh = nil, nil, d.get_lh()
  local saw_grow, saw_shrink, saw_win, saw_lose = false, false, false, false
  local finger, pending_restart = 0, false

  for _ = 1, frames do
    finger = finger + (pos[ball].y - pos[left].y)
    game._down, game._py = true, finger
    step(dt)
    local skip = pending_restart; pending_restart = false
    local b, l, r = pos[ball], pos[left], pos[right]
    local lh = d.get_lh()
    local over = events_have("log")
    if events_have("log", "win") then saw_win = true end
    if events_have("log", "lose") then saw_lose = true end
    if not skip and lh > prev_lh + 1e-6 then
      saw_grow = true
      check_once("grow_fx", events_have("haptic", "success") and events_have("sound", "hit"),
        "grow (green hit) must play hit sound + success haptic")
    elseif not skip and lh < prev_lh - 1e-6 then saw_shrink = true end
    local resized = math.abs(lh - prev_lh) > 1e-6
    local at_origin = math.abs(b.x) < 0.001 and math.abs(b.y) < 0.001

    check_once("h_max", lh <= 2 * HH + 0.5, "paddle exceeded screen height")
    check_once("h_min", lh >= 26 - 0.5, "paddle went below floor")
    if prev_ball and not at_origin and not over then
      local sp = math.sqrt((b.x - prev_ball.x) ^ 2 + (b.y - prev_ball.y) ^ 2) / dt
      check_once("gspeed", sp <= 730, string.format("grow ball speed %.0f exceeded cap", sp))
    end
    check_once("gwall", math.abs(b.y) <= HH - ball_hw + 0.5, "grow ball left vertical bounds")
    if math.abs(b.y - l.y) <= lh * 0.5 + ball_hw then
      check_once("gtun_l", b.x >= l.x + pad_hw + ball_hw - 1.0, "ball tunneled player paddle")
    end
    if math.abs(b.y - r.y) <= ai_hh + ball_hw then
      check_once("gtun_r", b.x <= r.x - pad_hw - ball_hw + 1.0, "ball tunneled AI paddle")
    end
    if prev_left and not resized and not over then
      check_once("gtele", math.abs(l.y - prev_left) <= 1800 * dt + 0.5, "player paddle teleported")
    end
    if over then on_tap(0, 0); pending_restart = true end
    prev_ball, prev_left, prev_lh = { x = b.x, y = b.y }, l.y, lh
  end
  check(saw_grow, "grow: green hits should grow the paddle")
  check(saw_shrink, "grow: should also shrink sometimes")
  check(saw_win, "grow: a win should be reachable")
  check(saw_lose, "grow: a lose should be reachable")
end

local function grow_miss_shrinks(frames)
  boot(); rand_mode = "good"
  local d = enter("grow")
  local start_h, lost, finger = d.get_lh(), false, 0
  for _ = 1, frames do
    finger = finger + 500                    -- drag up: pin paddle to top, miss balls
    game._down, game._py = true, finger
    step()
    if events_have("log", "lose") then lost = true; break end
  end
  check(lost, "grow: missing green balls should shrink to a lose")
  check(d.get_lh() < start_h, "grow: paddle net-shrank while missing")
end

----------------------------------------------------------------------
-- Game 2: Breakout
----------------------------------------------------------------------
local function breakout_win(frames)
  boot(); rand_mode = "mixed"
  local d = enter("breakout")
  local ball, paddle = d.ball, d.paddle
  local ball_hw = dims[ball].w * 0.5
  on_tap(0, 0)                               -- launch
  local prev_ball, finger, won, prev_bricks = nil, 0, false, d.bricks()
  for i = 1, frames do
    -- Track the ball but aim off-center so the ball spreads and clears columns.
    local target = pos[ball].x + 50 * math.sin(i * 0.15)
    finger = finger + (target - pos[paddle].x)
    game._down, game._px = true, finger
    step()
    local b = pos[ball]
    if events_have("log", "win") then won = true; break end
    check_once("bspeed", prev_ball == nil or
      math.sqrt((b.x - prev_ball.x) ^ 2 + (b.y - prev_ball.y) ^ 2) / DT <= 580,
      "breakout ball exceeded speed cap")
    check_once("bwallx", b.x >= -HW - 1 and b.x <= HW + 1, "breakout ball left horizontal bounds")
    check_once("bwally", b.y <= HH + 1, "breakout ball went above the top")
    check(d.bricks() <= prev_bricks, "breakout brick count must never increase")
    prev_bricks = d.bricks()
    prev_ball = { x = b.x, y = b.y }
  end
  check(won, "breakout: perfect play should clear all bricks (win)")
end

local function breakout_lose(frames)
  boot()
  local d = enter("breakout")
  local lost, finger = false, 0
  game._down = true
  for _ = 1, frames do
    finger = finger + (-pos[d.ball].x - pos[d.paddle].x)   -- mirror the ball: always flee it
    game._px = finger
    on_tap(0, 0)                             -- (re)launch the ball each life
    step()
    if events_have("log", "lose") then lost = true; break end
  end
  check(lost, "breakout: letting the ball fall should lose all lives")
end

----------------------------------------------------------------------
-- Game 3: Snake
----------------------------------------------------------------------
local function snake_tests()
  boot()
  local d = enter("snake")
  check(d.game == "snake" and d.len() == 3, "snake starts length 3")

  -- Grid adjacency: head moves 0 or 1 cell per frame; auto-play toward food and
  -- confirm it can eat (grow) at least once. On death we restart; prev_head is
  -- refreshed AFTER the restart so the center-respawn is never seen as a jump.
  local grew, prev_head, prev_len = false, d.head(), d.len()
  for _ = 1, 8000 do
    local h, fd = d.head(), d.food
    game._keys = {}
    if fd then
      if h.c ~= fd.c then game._keys[h.c < fd.c and "right" or "left"] = true
      elseif h.r ~= fd.r then game._keys[h.r < fd.r and "up" or "down"] = true end
    end
    step()
    local nh = d.head()
    if nh and prev_head and d.alive() then
      local man = math.abs(nh.c - prev_head.c) + math.abs(nh.r - prev_head.r)
      check_once("snake_step", man <= 1, string.format("snake head moved %d cells in a frame", man))
    end
    if d.len() > prev_len then grew = true end
    prev_len = d.len()
    if not d.alive() then on_tap(0, 0) end   -- restart; reset respawns at center
    prev_head = d.head()                      -- refresh AFTER any restart
  end
  check(grew, "snake: should be able to eat food and grow")

  -- Death: drive straight up into the wall; the snake must die.
  boot(); d = enter("snake")
  local died = false
  game._keys = { up = true }
  for _ = 1, 400 do step(); if not d.alive() then died = true; break end end
  check(died, "snake: running into a wall should end the game")

  -- Restart: tapping after death revives at length 3.
  on_tap(0, 0); step()
  check(d.alive() and d.len() == 3, "snake: tap restarts at length 3")
end

----------------------------------------------------------------------
-- Game 4: Roguelike (loaded from its own file)
----------------------------------------------------------------------
local function pick_levelup(d)
  if d.leveling() then
    local ch = d.choices()
    if ch[1] and ch[1].rect then on_tap(ch[1].rect.x, ch[1].rect.y) end
  end
end

local function rogue_tests()
  boot()
  local d = enter("roguelike")
  check(d.game == "roguelike", "roguelike loads from its own file and enters")

  -- Play: circle around to dodge; auto-fire kills; gems level you up.
  local ang, got_kill, leveled = 0, false, false
  for _ = 1, 14000 do
    ang = ang + 0.06
    game._down, game._px, game._py = true, math.cos(ang) * 70, math.sin(ang) * 70
    step()
    check_once("rogue_bounds",
      math.abs(pos[d.player].x) <= HW + 1 and math.abs(pos[d.player].y) <= HH + 1,
      "roguelike player left the arena")
    check_once("rogue_cap", d.enemies() <= 60, "roguelike enemy count exceeded the cap")
    if d.kills() > 0 then got_kill = true end
    if d.leveling() then leveled = true; pick_levelup(d) end
    if not d.alive() then break end
  end
  check(got_kill, "roguelike: auto-fire should kill enemies")
  check(leveled, "roguelike: collecting gems should trigger a level-up")

  -- Death: stand still, get swarmed, run out of HP.
  boot(); d = enter("roguelike")
  clear_input()
  local died = false
  for _ = 1, 16000 do
    step(); pick_levelup(d)
    if not d.alive() then died = true; break end
  end
  check(died, "roguelike: standing still should eventually lose all HP")

  on_tap(0, 0); step()
  check(d.alive(), "roguelike: tap restarts after death")
end

----------------------------------------------------------------------
-- Game 5: 2048 (loaded from its own file)
----------------------------------------------------------------------
local function game2048_tests()
  boot()
  local d = enter("game2048")
  check(d.game == "game2048", "2048 loads from its own file and enters")
  local b = d.board()
  local n0 = 0
  for r = 1, 4 do for c = 1, 4 do if b[r][c] > 0 then n0 = n0 + 1 end end end
  check(n0 == 2, "2048 starts with exactly two tiles")

  -- Merge: a row of {2,2,4,0} slid left becomes {4,4,0,0}, +4 score.
  b[1] = { 2, 2, 4, 0 }; b[2] = { 0, 0, 0, 0 }; b[3] = { 0, 0, 0, 0 }; b[4] = { 0, 0, 0, 0 }
  local s0 = d.score()
  d.move("left")
  check(b[1][1] == 4 and b[1][2] == 4, "2048 merges equal tiles when sliding")
  check(d.score() >= s0 + 4, "2048 score increases on a merge")

  -- Every tile is always 0 or a power of two across many moves.
  local dirs = { "left", "right", "up", "down" }
  for i = 1, 400 do
    d.move(dirs[(i % 4) + 1])
    for r = 1, 4 do for c = 1, 4 do
      local v = d.board()[r][c]
      check_once("v2048", v == 0 or (v >= 2 and (v & (v - 1)) == 0),
        "2048 produced a non-power-of-two tile: " .. tostring(v))
    end end
    if not d.alive() then break end
  end
end

----------------------------------------------------------------------
-- Game 6: Space Shooter (loaded from its own file)
----------------------------------------------------------------------
local function shooter_tests()
  boot()
  local d = enter("shooter")
  check(d.game == "shooter", "shooter loads from its own file and enters")
  check(d.aliens() == 20, "shooter starts with a full 5x4 formation")
  local ang, killed, sc0 = 0, false, d.score()
  for _ = 1, 6000 do
    ang = ang + 0.03
    game._down, game._px = true, math.sin(ang) * 220   -- sweep the ship
    step()
    check_once("shooter_bounds", math.abs(pos[d.ship].x) <= HW + 1, "shooter ship left the screen")
    if d.score() > sc0 then killed = true end
    if not d.alive() then break end
  end
  check(killed, "shooter: auto-fire should destroy aliens (score increases)")
  if not d.alive() then on_tap(0, 0); step(); check(d.alive(), "shooter restarts after game over") end
end

----------------------------------------------------------------------
-- Game 7: Cozy Isle (loaded from its own file)
----------------------------------------------------------------------
local function world_tests()
  boot()
  local d = enter("world")
  check(d.game == "world", "Cozy Isle loads from its own file and enters")
  local inv = d.inv()
  check(inv.wood == 0 and inv.stone == 0 and inv.flower == 0, "world starts with empty inventory")

  -- Walk to a tree, then PICK -> wood increases.
  local tree = d.trees[1]
  for _ = 1, 400 do
    game._down, game._px, game._py = true, tree.x, tree.y - 40   -- hold near the tree
    step()
    if (pos[d.villager].x - tree.x) ^ 2 + (pos[d.villager].y - (tree.y - 40)) ^ 2 < 100 then break end
  end
  clear_input()
  on_tap(d.b_act.x, d.b_act.y)                                    -- PICK
  check(d.inv().wood >= 1, "world: standing by a tree and picking gives wood")

  -- BUILD cycles the recipe; giving resources + PLACE drops a decoration.
  local r0 = d.recipe()
  on_tap(d.b_build.x, d.b_build.y)
  check(d.recipe() ~= r0, "world: BUILD button cycles the recipe")
  local iv = d.inv(); iv.wood, iv.stone, iv.flower = 9, 9, 9        -- stock up
  -- cycle to a recipe we can afford (any), then place
  local before = d.placed()
  on_tap(d.b_act.x, d.b_act.y)                                    -- PLACE (recipe selected)
  check(d.placed() == before + 1, "world: placing a recipe adds a decoration")

  -- Back button returns to the menu.
  on_tap(d.back.x, d.back.y); step()
  check(DEBUG.game == "menu", "world: BACK returns to the menu")
end

----------------------------------------------------------------------
-- Craft World (player-created sandbox, loaded from its own file)
----------------------------------------------------------------------
local function craft_tests()
  -- Fresh persistent store so the scenario is deterministic.
  game._store["craft.world"], game._store["craft.inv"], game._store["craft.met"] = nil, nil, nil
  boot()
  local d = enter("craft")
  check(d.game == "craft", "craft: loads from its own file and enters")
  check(d.dialog(), "craft: first visit auto-opens the villager dialogue")
  local inv0 = d.inv()
  check(inv0.wood == 0 and inv0.stone == 0 and inv0.flower == 0,
    "craft: inventory is empty before choosing a starter kit")

  -- Dialogue: pick the BUILDER kit -> wood + stone granted, choice remembered.
  local opts = d.options()
  check(#opts == 3, "craft: welcome dialogue offers three starter kits")
  on_tap(opts[1].x, opts[1].y); step()
  check(not d.dialog(), "craft: choosing a kit closes the dialogue")
  check(d.met(), "craft: the kit choice is remembered (met flag)")
  check(d.inv().wood == 8 and d.inv().stone == 6, "craft: BUILDER kit grants 8 wood + 6 stone")
  check(events_have("save", "craft.met") or game._store["craft.met"] == true,
    "craft: the met flag is persisted via game.save")

  -- Palette + placement economy.
  on_tap(d.palette[2].x, d.palette[2].y)                          -- FENCE (1 wood)
  check(d.sel() == 2, "craft: tapping a palette slot selects that tool")
  local cell = d.cellrect(2, 2)
  local w0 = d.inv().wood
  on_tap(cell.x, cell.y)
  check(d.get(2, 2) == 2, "craft: tapping an empty cell places the selected block")
  check(d.inv().wood == w0 - 1, "craft: placing deducts the block's cost")
  on_tap(cell.x, cell.y)
  check(d.get(2, 2) == 2 and d.inv().wood == w0 - 1,
    "craft: an occupied cell rejects a second block (no double spend)")
  on_tap(d.palette[#d.palette].x, d.palette[#d.palette].y)        -- ERASE
  on_tap(cell.x, cell.y)
  check(d.get(2, 2) == 0, "craft: the eraser clears the cell")
  check(d.inv().wood == w0, "craft: erasing refunds the block's cost")

  -- Cannot place what you cannot afford.
  on_tap(d.palette[4].x, d.palette[4].y)                          -- FLOWERS (1 flower, have 0)
  local c2 = d.cellrect(1, 1)
  on_tap(c2.x, c2.y)
  check(d.get(1, 1) == 0, "craft: placement is rejected when the cost is unaffordable")

  -- Gathering: nodes give one resource, then recharge on a cooldown.
  local tree = d.nodes[1]
  local w1 = d.inv().wood
  on_tap(tree.x, tree.y)
  check(d.inv().wood == w1 + 1, "craft: tapping a tree node gathers wood")
  on_tap(tree.x, tree.y)
  check(d.inv().wood == w1 + 1, "craft: a spent node cannot be re-gathered instantly")
  for _ = 1, 600 do step() end                                    -- 10 s > 8 s cooldown
  on_tap(tree.x, tree.y)
  check(d.inv().wood == w1 + 2, "craft: a node recharges after its cooldown")

  -- Persistence: the placed world + inventory survive leave/re-enter.
  on_tap(d.palette[2].x, d.palette[2].y)
  local c3 = d.cellrect(4, 3)
  on_tap(c3.x, c3.y)
  check(d.get(4, 3) == 2, "craft: placed a block for the save/load roundtrip")
  local saved_wood = d.inv().wood
  on_tap(d.back.x, d.back.y); step()
  check(DEBUG.game == "menu", "craft: BACK returns to the menu")
  local d2 = enter("craft")
  check(not d2.dialog(), "craft: a return visit skips the welcome dialogue")
  check(d2.get(4, 3) == 2, "craft: the world layout survives leave/re-enter")
  check(d2.inv().wood == saved_wood, "craft: the inventory survives leave/re-enter")
  check(d2.placed() == 1, "craft: exactly the saved blocks are restored")

  -- Return-visit dialogue: GIFT grants once, then goes on cooldown.
  on_tap(d2.npc.x, d2.npc.y)
  check(d2.dialog(), "craft: tapping the villager opens the dialogue")
  local o2 = d2.options()
  check(#o2 == 2, "craft: the return dialogue offers GIFT and BYE")
  local total = d2.inv().wood + d2.inv().stone + d2.inv().flower
  on_tap(o2[1].x, o2[1].y); step()
  check(d2.inv().wood + d2.inv().stone + d2.inv().flower == total + 2,
    "craft: a ready gift grants two resources")
  check(not d2.dialog(), "craft: taking the gift closes the dialogue")
  check(d2.gift() > 0, "craft: the gift goes on cooldown after being taken")
  on_tap(d2.npc.x, d2.npc.y)
  local o3 = d2.options()
  on_tap(o3[1].x, o3[1].y); step()
  check(d2.inv().wood + d2.inv().stone + d2.inv().flower == total + 2,
    "craft: a cooling-down gift grants nothing")
  on_tap(d2.npc.x, d2.npc.y)
  local o4 = d2.options()
  on_tap(o4[#o4].x, o4[#o4].y); step()                            -- BYE
  check(not d2.dialog(), "craft: BYE closes the dialogue")
  on_tap(d2.back.x, d2.back.y); step()
end

----------------------------------------------------------------------
-- Game 8: Gem Match (match-3, loaded from its own file)
----------------------------------------------------------------------
local function m3_full(d)
  for r = 1, d.rows do for c = 1, d.cols do if d.get(c, r) < 1 then return false end end end
  return true
end
local function m3_has_match(d)
  for r = 1, d.rows do
    for c = 1, d.cols do
      local v = d.get(c, r)
      if v > 0 then
        if c <= d.cols - 2 and d.get(c + 1, r) == v and d.get(c + 2, r) == v then return true end
        if r <= d.rows - 2 and d.get(c, r + 1) == v and d.get(c, r + 2) == v then return true end
      end
    end
  end
  return false
end
local function m3_settle(d) for _ = 1, 900 do if not d.busy() then return end; step() end end
-- find_move may return a special (c1==c2); swap it with a neighbour to fire it.
local function m3_pick(d)
  local c1, r1, c2, r2 = d.find_move()
  if not c1 then return end
  if c1 == c2 and r1 == r2 then c2 = (c1 < d.cols) and c1 + 1 or c1 - 1 end
  return c1, r1, c2, r2
end
local function m3_play(mode, lvl)
  boot(); enter("match3")
  DEBUG.start(mode, lvl); step()
  return DEBUG
end

local function match3_tests()
  boot()
  local d = enter("match3")
  check(d.game == "match3", "match3 loads and enters (mode-select screen)")
  check(d.back ~= nil, "match3 start screen exposes a back button")

  -- Enter Adventure level 1 and check the fresh board.
  d = m3_play("adventure", 1)
  check(d.screen == "play" and d.game == "match3", "match3 start(adventure,1) enters play")
  check(m3_full(d), "match3 board starts completely full")
  check(not m3_has_match(d), "match3 board starts with no pre-made matches")
  check(d.moves() == 18, "match3 level 1 grants 18 moves")

  -- Play legal moves; invariants must hold after each settles.
  local made = 0
  for _ = 1, 14 do
    if d.over() then break end
    local c1, r1, c2, r2 = m3_pick(d)
    if not c1 then break end
    local m0, s0 = d.moves(), d.score()
    d.swap(c1, r1, c2, r2); m3_settle(d)
    made = made + 1
    check_once("m3_full", m3_full(d), "match3 board must stay full after a move")
    check_once("m3_nomatch", not m3_has_match(d), "match3 must leave no matches once idle")
    check_once("m3_move_cost", d.moves() == m0 - 1, "match3 must spend exactly one move per swap")
    check_once("m3_scored", d.score() > s0, "match3 a legal move must increase the score")
  end
  check(made > 0, "match3: a legal move should always be available")

  -- Non-adjacent swaps are ignored.
  d = m3_play("adventure", 1)
  local m0 = d.moves()
  d.swap(1, 1, 3, 3); step()
  check(d.moves() == m0 and not d.busy(), "match3 ignores non-adjacent swaps")

  -- A 4-in-a-row forges a special piece.
  d = m3_play("endless")
  d.setcell(1, 1, 2); d.setcell(2, 1, 2); d.setcell(3, 1, 2)
  d.setcell(4, 2, 2); d.setcell(4, 1, 5); d.setcell(5, 1, 3)
  d.swap(4, 1, 4, 2)
  local special = false
  for _ = 1, 900 do
    step()
    for r = 1, d.rows do for c = 1, d.cols do if d.special(c, r) then special = true end end end
    if not d.busy() then break end
  end
  check(special, "match3: a 4-match forges a special piece")

  -- Collect objective counts gathered pieces.
  d = m3_play("adventure", 3)
  d.setcell(1, 1, 1); d.setcell(2, 1, 1); d.setcell(4, 1, 1); d.setcell(3, 1, 2); d.setcell(3, 2, 1)
  local c0 = d.collected()
  d.swap(3, 1, 3, 2); m3_settle(d)
  check(d.collected() > c0, "match3 collect objective counts gathered pieces")

  -- Jelly (vines) objective initialises its count.
  d = m3_play("adventure", 5)
  check(d.jelly_left() == 12, "match3 vines level starts with 12 vines to clear")

  -- Win: a low target is crossed by the first clear.
  d = m3_play("adventure", 1)
  d.set_target_score(1)
  local c1, r1, c2, r2 = m3_pick(d)
  d.swap(c1, r1, c2, r2)
  local won = false
  for _ = 1, 900 do step(); if events_have("log", "win") then won = true end; if not d.busy() then break end end
  check(won and d.won(), "match3: reaching the target score wins")

  -- Lose: unreachable target + a single move runs out.
  d = m3_play("adventure", 1)
  d.set_target_score(1e9); d.set_moves(1)
  c1, r1, c2, r2 = m3_pick(d)
  d.swap(c1, r1, c2, r2)
  local lost = false
  for _ = 1, 900 do step(); if events_have("log", "lose") then lost = true end; if not d.busy() then break end end
  check(lost, "match3: running out of moves loses")

  -- Regression (#2): a game-over then leave+re-enter must still be startable
  -- (a stale `over` used to swallow the Adventure/Endless taps).
  d = m3_play("adventure", 1)
  d.set_target_score(1e9); d.set_moves(1)
  local pc1, pr1, pc2, pr2 = m3_pick(d); d.swap(pc1, pr1, pc2, pr2); m3_settle(d)
  check(d.over(), "match3 regression setup reaches game-over")
  on_tap(d.back.x, d.back.y); step()             -- back: play -> map
  on_tap(DEBUG.back.x, DEBUG.back.y); step()     -- back: map -> start
  on_tap(DEBUG.back.x, DEBUG.back.y); step()     -- back: start -> menu
  check(DEBUG.game == "menu", "match3 back-chain returns to the menu")
  enter("match3")                                -- re-enter from the menu
  on_tap(0, 40); step()                          -- tap ADVENTURE on the mode screen
  check(DEBUG.screen == "map", "match3: re-enter after a game-over can still start (bug #2)")
end

local function umami_play(k)
  boot(); enter("umami"); DEBUG.start(k or "soba"); step()
  return DEBUG
end
local function umami_tests()
  boot()
  local d = enter("umami")
  check(d.game == "umami", "umami loads and enters (character select)")
  check(d.back ~= nil, "umami select screen has a back button")

  d = umami_play("soba")
  check(d.screen == "play" and d.game == "umami", "umami start(soba) enters play")
  check(d.char() == "soba", "umami: the picked character is Soba")
  check(d.cpu_char() ~= "soba", "umami: the CPU picks a different character")
  check(d.score().p == 0 and d.score().c == 0, "umami starts 0-0")

  -- Ball stays on the table across many frames.
  for _ = 1, 800 do
    step(); local b = d.ball()
    check_once("umami_bounds", math.abs(b.x) <= HW + 2 and math.abs(b.y) <= HH + 2, "umami ball left the table")
  end

  -- Flick dashes your dumpling.
  d = umami_play("soba")
  for _ = 1, 80 do step() end
  local y0 = d.you().y; d.flick(0, 1, 1); step(); step(); step()
  check(d.you().y ~= y0, "umami flick dashes the player")

  -- Ball through the top torii scores.
  d = umami_play("soba")
  for _ = 1, 80 do step() end
  local sp0 = d.score().p; d.set_ball(0, HH, 0, 400)
  for _ = 1, 60 do step(); if d.score().p > sp0 then break end end
  check(d.score().p > sp0, "umami: a ball through the top torii scores")

  -- Ultimate: fires only when the meter is full, then empties it.
  d = umami_play("chef")
  check(not d.fire_ult(), "umami: ultimate cannot fire on an empty meter")
  d.set_energy(1)
  check(d.fire_ult(), "umami: ultimate fires when the meter is full")
  check(d.energy() == 0, "umami: firing the ultimate empties the meter")

  -- Lantern's Guard Wall activates.
  d = umami_play("lantern")
  d.set_energy(1); d.fire_ult()
  check(d.guard() > 0, "umami: Lantern's Guard Wall activates")

  -- Reaching the target score wins the cup.
  d = umami_play("soba")
  local won = false
  for _ = 1, 1500 do
    step()
    if not d.serving() then d.set_ball(0, HH - 4, 0, 500) end
    if events_have("log", "win") then won = true; break end
  end
  check(won, "umami: reaching the target score wins the cup")

  -- Arena picker on the select screen cycles through the four courts.
  boot(); d = enter("umami")
  local a0 = d.arena()
  if d.arena_btn then on_tap(d.arena_btn.x, d.arena_btn.y); step()
    check(DEBUG.arena() ~= a0, "umami: arena button cycles the court") end

  -- BACK: play -> character select -> menu.
  d = umami_play("soba")
  on_tap(d.back.x, d.back.y); step()
  check(DEBUG.screen == "select", "umami: BACK from play returns to character select")
  on_tap(DEBUG.back.x, DEBUG.back.y); step()
  check(DEBUG.game == "menu", "umami: BACK from select returns to the menu")
end

-- AI-generated pack (tools/PACK_SPEC.md): same acceptance bar as hand-written games.
local function catch_tests()
  boot()
  local d = enter("catch")
  check(d.game == "catch", "catch (AI pack) loads and enters")
  check(d.back ~= nil, "catch exposes a back button")
  check(d.score() == 0 and d.lives() == 3, "catch starts 0 score / 3 lives")

  -- Catch: hold the basket at x=0 and feed fruit at x=0 -> score must rise, and
  -- the basket must never leave the screen.
  game._down, game._px, game._py = true, 0, -HH + 40
  local caught = false
  for _ = 1, 380 do
    d.spawn_fruit_at(0); step()
    check_once("catch_bounds", math.abs(pos[d.basket].x) <= HW + 1, "catch basket left the screen")
    if d.score() > 0 then caught = true; break end
    if not d.alive() then break end
  end
  check(caught, "catch: a fruit landing on the basket scores")

  -- Lose: unattended fruit drains lives to a game over; tap restarts fresh.
  boot(); d = enter("catch"); clear_input()
  local lost = false
  for _ = 1, 4000 do step(); if not d.alive() then lost = true; break end end
  check(lost, "catch: missing fruit drains lives to a game over")
  on_tap(0, 0); step()
  check(d.alive() and d.score() == 0, "catch: tap restarts a fresh round")

  -- Back returns to the menu.
  boot(); d = enter("catch")
  on_tap(d.back.x, d.back.y); step()
  check(DEBUG.game == "menu", "catch: BACK returns to the menu")
end

-- Queens / Star Battle pack (video-clone mechanics): tap places a pony
-- directly, exclusions auto-X, wrong pony costs a heart (2), countdown timer,
-- clear / find / bulb tools, colourblind + coordinate toggles.
local function ponies_tests()
  boot()
  clear_input()
  for _, t in ipairs(DEBUG.tiles) do
    if t.key == "ponies" then frame_events = {}; on_tap(t.x, t.y); break end
  end
  check(events_have("music", "ponies"), "ponies: entering starts its own BGM loop")
  on_update(DT)
  local d = DEBUG
  check(d.game == "ponies", "ponies (AI pack) loads and enters")
  check(d.back ~= nil, "ponies exposes a back button")
  local n = d.n()
  check(n == 8, "ponies level 1 is an 8x8 board (video parity)")
  check(d.hearts() == 2, "ponies starts with 2 hearts (video parity)")

  -- Generator invariants: regions 1..n partition the grid, each contiguous.
  local cnt = {}
  for r = 1, n do
    for c = 1, n do
      local k = d.region(r, c)
      check_once("ponies_regrange", k >= 1 and k <= n, "ponies: region id out of range")
      cnt[k] = (cnt[k] or 0) + 1
    end
  end
  for k = 1, n do
    check((cnt[k] or 0) >= 1, "ponies: region " .. k .. " owns at least one cell")
    local start = nil
    for r = 1, n do for c = 1, n do
      if d.region(r, c) == k and not start then start = { r, c } end
    end end
    local seen, stack, found = {}, { start }, 0
    while #stack > 0 do
      local pp = table.remove(stack)
      local rr, cc = pp[1], pp[2]
      local key = rr * 100 + cc
      if rr >= 1 and rr <= n and cc >= 1 and cc <= n and not seen[key] and d.region(rr, cc) == k then
        seen[key] = true; found = found + 1
        stack[#stack + 1] = { rr + 1, cc }; stack[#stack + 1] = { rr - 1, cc }
        stack[#stack + 1] = { rr, cc + 1 }; stack[#stack + 1] = { rr, cc - 1 }
      end
    end
    check(found == cnt[k], "ponies: region " .. k .. " is contiguous")
  end

  -- The stored solution obeys every rule.
  local usedc, usedk, solok = {}, {}, true
  for r = 1, n do
    local c = d.solution(r)
    local k = d.region(r, c)
    if usedc[c] or usedk[k] then solok = false end
    usedc[c], usedk[k] = true, true
    if r > 1 and math.abs(c - d.solution(r - 1)) < 2 then solok = false end
  end
  check(solok, "ponies: generated solution satisfies rows/cols/regions/adjacency")

  -- Independent solver: exactly one solution.
  local function count(rr, uc, uk, prev)
    if rr > n then return 1 end
    local total = 0
    for c = 1, n do
      local k = d.region(rr, c)
      if not uc[c] and not uk[k] and (rr == 1 or math.abs(c - prev) >= 2) then
        uc[c], uk[k] = true, true
        total = total + count(rr + 1, uc, uk, c)
        uc[c], uk[k] = nil, nil
        if total >= 2 then return total end
      end
    end
    return total
  end
  check(count(1, {}, {}, 0) == 1, "ponies: puzzle has a unique solution")

  -- Correct tap places a pony DIRECTLY and auto-marks every excluded cell.
  local s1 = d.solution(1)
  local x1, y1 = d.cell_center(1, s1)
  on_tap(x1, y1); step()
  check(d.state(1, s1) == 2 and d.placed() == 1, "ponies: tapping the solution cell places a pony")
  local marks_ok = true
  for r = 1, n do
    for c = 1, n do
      if d.state(r, c) ~= 2 then
        local excl = (r == 1) or (c == s1) or (d.region(r, c) == d.region(1, s1))
          or (math.abs(r - 1) <= 1 and math.abs(c - s1) <= 1)
        local want = excl and 1 or 0
        if d.state(r, c) ~= want then marks_ok = false end
      end
    end
  end
  check(marks_ok, "ponies: auto-X marks exactly the excluded cells")

  -- Tapping an auto-X cell is inert (no heart loss, no state change).
  local xc = (s1 % n) + 1                    -- some other column in row 1 (excluded)
  local ix, iy = d.cell_center(1, xc)
  local h0 = d.hearts()
  on_tap(ix, iy); step()
  check(d.hearts() == h0 and d.state(1, xc) == 1, "ponies: tapping an X cell does nothing")

  -- Removing the pony un-marks what only it excluded.
  on_tap(x1, y1); step()
  check(d.placed() == 0 and d.state(1, s1) == 0, "ponies: tapping a pony removes it")
  check(d.state(1, xc) == 0, "ponies: removal clears its auto-X marks")

  -- A wrong pony (open cell, not the solution) flashes and costs a heart.
  local wrongc = nil
  for c = 1, n do if c ~= s1 and d.state(1, c) == 0 then wrongc = c break end end
  local wx, wy = d.cell_center(1, wrongc)
  on_tap(wx, wy)
  check(d.hearts() == 1, "ponies: a wrong pony costs a heart")
  check(d.state(1, wrongc) == 0 and d.placed() == 0, "ponies: the wrong pony is not placed")
  check(events_have("haptic", "heavy"), "ponies: a mistake buzzes a heavy haptic")
  step()

  -- Second mistake -> fail; tap deals a fresh board with 2 hearts, streak 0.
  on_tap(wx, wy)
  check(d.dead(), "ponies: two mistakes fail the level")
  step()
  on_tap(0, 0); step()
  check(not d.dead() and d.hearts() == 2 and d.placed() == 0,
    "ponies: tap after a fail redeals with full hearts")
  check(d.streak() == 0, "ponies: failing resets the streak")

  -- Clear button removes all ponies (and their marks) without penalty.
  local cx, cy = d.cell_center(1, d.solution(1))
  on_tap(cx, cy); step()
  check(d.placed() == 1, "ponies: setup pony for the clear test")
  local cb = d.btn("clear")
  on_tap(cb.x, cb.y); step()
  local anyx = false
  for r = 1, n do for c = 1, n do if d.state(r, c) ~= 0 then anyx = true end end end
  check(d.placed() == 0 and not anyx and d.hearts() == 2,
    "ponies: clear wipes ponies and marks at no cost")

  -- Find tool places one correct pony and burns its charge.
  check(d.find_charges() == 1, "ponies: find tool starts with 1 charge")
  local fb = d.btn("find")
  on_tap(fb.x, fb.y); step()
  check(d.placed() == 1 and d.find_charges() == 0, "ponies: find tool places a correct pony")
  on_tap(fb.x, fb.y); step()
  check(d.placed() == 1, "ponies: an empty find tool is a no-op")

  -- Bulb tool burns a charge without placing.
  check(d.bulb_charges() == 1, "ponies: bulb starts with 1 charge")
  local bb = d.btn("bulb")
  on_tap(bb.x, bb.y); step()
  check(d.placed() == 1 and d.bulb_charges() == 0, "ponies: bulb hints without placing")

  -- Colourblind + coordinate toggles flip their state.
  on_tap(d.btn("cb").x, d.btn("cb").y); step()
  check(d.cb_on(), "ponies: colourblind mode toggles on")
  on_tap(d.btn("coord").x, d.btn("coord").y); step()
  check(d.coord_on(), "ponies: coordinates toggle on")

  -- Play to win: tap out the remaining solution -> won, streak+1, coins+20.
  local streak0, coins0 = d.streak(), d.coins()
  for r = 1, n do
    if d.state(r, d.solution(r)) ~= 2 then
      local px, py = d.cell_center(r, d.solution(r))
      on_tap(px, py)
    end
  end
  check(d.won(), "ponies: placing the full solution wins the level")
  check(events_have("sound", "score"), "ponies: winning plays the score sound")
  check(events_have("zoom"), "ponies: winning punches the camera zoom")
  check(d.streak() == streak0 + 1, "ponies: winning bumps the streak")
  check(d.coins() == coins0 + 20, "ponies: winning pays 20 coins")
  step()
  on_tap(0, 0); step()
  check(d.level() == 2 and not d.won() and d.placed() == 0,
    "ponies: tap after a win deals the next level")

  -- Countdown: a fresh 5x5 board fails after N*10 seconds of inaction.
  boot(); d = enter("ponies")
  check(d.time_left() > 0, "ponies: the countdown starts positive")
  local timed_out = false
  for _ = 1, 2600 do
    step(1 / 30)
    if d.dead() then timed_out = true; break end
  end
  check(timed_out, "ponies: running out the clock fails the level")

  -- BACK returns to the menu.
  boot(); d = enter("ponies")
  on_tap(d.back.x, d.back.y); step()
  check(DEBUG.game == "menu", "ponies: BACK returns to the menu")
end

-- Midnight Gallery: a mild-horror interrogation VN. Drives the full flow
-- (select -> three interviews -> accuse), clue collection, and both endings.
local function gallery_tests()
  boot()
  local d = enter("gallery")
  check(d.game == "gallery", "gallery (VN pack) loads and enters")
  check(d.scene() == "select", "gallery opens on the witness-select screen")
  check(d.back ~= nil, "gallery exposes a back button")
  for _, k in ipairs({ "coach", "ol", "teacher" }) do
    check(d.select_btn(k) ~= nil, "gallery select screen has witness " .. k)
  end

  -- Tapping a witness lunges her forward then opens her interview.
  local r = d.select_btn("coach")
  on_tap(r.x, r.y)
  for _ = 1, 20 do step() end
  check(d.scene() == "talk" and d.current() == "coach", "tapping a witness opens her interview")
  check(d.voice_plays() >= 1, "gallery: the opening line plays on the VOICE channel (no overlapping SFX)")

  -- Full playthrough: interview all three, always probing an uncollected clue,
  -- and assert every clue can be surfaced and each witness gets marked done.
  local function settle()
    for _ = 1, 200 do step(); if d.scene() ~= "talk" or not d.typing() then break end end
  end
  local function interview(key)
    local sr = d.select_btn(key)
    on_tap(sr.x, sr.y)
    for _ = 1, 20 do step() end
    check(d.scene() == "talk" and d.current() == key, "interview opens for " .. key)
    for _ = 1, 12 do
      settle()
      if d.scene() == "select" then break end
      local ch = d.choices()
      check(#ch > 0, "gallery: choices present for " .. key)
      local pick = ch[1]
      for _, c in ipairs(ch) do
        if c.clue and not d.has_clue(c.clue) then pick = c; break end
      end
      on_tap(pick.rect.x, pick.rect.y)
    end
    check(d.scene() == "select" and d.done(key), "gallery: " .. key .. " interview completes")
  end
  -- coach already opened above; finish it, then the other two.
  local function finish_open(key)
    for _ = 1, 12 do
      settle()
      if d.scene() == "select" then break end
      local ch = d.choices(); local pick = ch[1]
      for _, c in ipairs(ch) do if c.clue and not d.has_clue(c.clue) then pick = c; break end end
      on_tap(pick.rect.x, pick.rect.y)
    end
    check(d.scene() == "select" and d.done(key), "gallery: " .. key .. " (already open) completes")
  end
  finish_open("coach")
  interview("ol")
  interview("teacher")
  check(d.clue_count() == 3, "gallery: probing surfaces all three clues")

  -- Accuse the culprit with the clues -> good ending.
  local ab = d.accuse_btn()
  check(ab ~= nil, "gallery: accuse button appears once all three are interviewed")
  on_tap(ab.x, ab.y)
  check(d.scene() == "accuse", "gallery: accuse screen opens")
  local tr = d.accuse_of("teacher")
  on_tap(tr.x, tr.y)
  check(d.scene() == "end", "gallery: accusing the culprit reaches an ending")

  -- Back from an ending returns to the select screen; BACK from select exits.
  on_tap(d.back.x, d.back.y)
  check(d.scene() == "select", "gallery: BACK from the ending returns to select")
  on_tap(d.back.x, d.back.y)
  check(events_have("stopvoice"), "gallery: leaving the pack stops the dialogue voice channel")
  step()
  check(DEBUG.game == "menu", "gallery: BACK from select returns to the menu")

  -- A wrong accusation still resolves to an ending (no dead-end).
  boot()
  d = enter("gallery")
  local function quick(key)
    local sr = d.select_btn(key); on_tap(sr.x, sr.y)
    for _ = 1, 20 do step() end
    for _ = 1, 12 do
      for _ = 1, 200 do step(); if d.scene() ~= "talk" or not d.typing() then break end end
      if d.scene() == "select" then break end
      local ch = d.choices(); on_tap(ch[1].rect.x, ch[1].rect.y)
    end
  end
  quick("coach"); quick("ol"); quick("teacher")
  on_tap(d.accuse_btn().x, d.accuse_btn().y)
  local cr = d.accuse_of("coach")
  on_tap(cr.x, cr.y)
  check(d.scene() == "end", "gallery: a wrong accusation also resolves to an ending")
end

----------------------------------------------------------------------
-- Time Dodge — "time moves when you move" invariants (both modes)
----------------------------------------------------------------------
-- Tap a result-card action button by its act ("retry"/"modes"/"levels").
local function tap_card(act)
  for _, b in ipairs(DEBUG.card() or {}) do
    if b.act == act then on_tap(b.rect.x, b.rect.y); step(); return true end
  end
  return false
end
-- Hold still with time flowing so the aimed fire converges and kills the run.
local function kill_run()
  game._down = true; game._px, game._py = 0, 0
  for _ = 1, 30000 do step(); if not DEBUG.alive() then break end end
end

local function timedodge_tests()
  boot(); rand_mode = "mixed"
  local d = enter("timedodge")
  check(d.game == "timedodge" and d.mode() == "select", "timedodge: enters on the mode-select screen")
  check(d.btn_endless ~= nil and d.btn_trials ~= nil, "timedodge: mode select exposes both mode buttons")

  -- ENDLESS ----------------------------------------------------------
  on_tap(d.btn_endless.x, d.btn_endless.y); step()
  d = DEBUG
  check(d.mode() == "run" and d.trial() == nil, "timedodge: ENDLESS starts an endless run")

  -- Frozen: nothing touching (finger up, no keys) -> the timescale floors
  -- and world time (stolen score) crawls over 3 sim seconds.
  clear_input()
  for _ = 1, 180 do step() end
  check(d.timescale() <= 0.1, "timedodge: releasing floors the timescale")
  check(d.score() < 0.5, string.format("timedodge: frozen world time crawls (%.2fs)", d.score()))

  -- Dash: press and circle the pointer -> timescale rises, world time accrues.
  -- 90 frames is inside the safe window: the first foe spawns ~1 world-second
  -- in and still needs ~1s+ of world time to cross to the player.
  local t = 0
  game._down = true
  for _ = 1, 90 do
    t = t + DT
    game._px, game._py = 120 * math.cos(t * 6), 260 * math.sin(t * 6)
    step()
  end
  check(d.alive(), "timedodge: survives the opening dash")
  check(d.timescale() > 0.6, "timedodge: dashing raises the timescale")
  check(d.score() > 0.8, "timedodge: moving accrues world time")
  for _ = 1, 400 do                          -- keep dashing until a foe is live
    if d.bullet_count() > 0 or not d.alive() then break end
    t = t + DT
    game._px, game._py = 120 * math.cos(t * 6), 260 * math.sin(t * 6)
    step()
  end
  check(d.alive() and d.bullet_count() > 0, "timedodge: bullets spawn while time flows")

  -- Freeze again (release): live bullets must be near-stationary between frames.
  game._down = false
  for _ = 1, 60 do step() end
  local frozen = {}
  for _, id in ipairs(d.bullet_ids()) do frozen[id] = { x = pos[id].x, y = pos[id].y } end
  step()
  for id, f in pairs(frozen) do
    if pos[id] then
      local sp = math.sqrt((pos[id].x - f.x) ^ 2 + (pos[id].y - f.y) ^ 2) / DT
      check_once("td_frozen", sp <= 500 * 0.1 + 1,
        string.format("timedodge: frozen bullet still moved at %.0f px/s", sp))
    end
  end

  -- Flow: while weaving, no bullet ever exceeds the speed cap between frames
  -- (no teleport), the player stays on screen, the live-bullet cap holds, and
  -- the converging fire eventually reaches a lose.
  local prev, died, prev_p = {}, false, nil
  t = 0
  game._down = true                          -- touching: time flows
  for i = 1, 8000 do
    t = t + DT
    if i <= 3000 then                        -- weave: per-frame invariants
      game._px, game._py = 170 * math.cos(t * 5), 170 * math.sin(t * 3)
    end                                      -- then: hold still (time flows,
    step()                                   -- aimed meteors converge -> lose)
    if not d.alive() then died = true; break end
    local b = pos[d.player]
    check_once("td_px", math.abs(b.x) <= HW and math.abs(b.y) <= HH, "timedodge: player left the screen")
    check_once("td_cap", d.bullet_count() <= 40, "timedodge: live bullet cap exceeded")
    if prev_p then
      local psp = math.sqrt((b.x - prev_p.x) ^ 2 + (b.y - prev_p.y) ^ 2) / DT
      check_once("td_ptele", psp <= 820 + 1,
        string.format("timedodge: player teleported at %.0f px/s", psp))
    end
    prev_p = { x = b.x, y = b.y }
    for _, id in ipairs(d.bullet_ids()) do
      local pr = prev[id]
      if pr and pos[id] then
        local sp = math.sqrt((pos[id].x - pr.x) ^ 2 + (pos[id].y - pr.y) ^ 2) / DT
        check_once("td_bspeed", sp <= 500 + 1,
          string.format("timedodge: bullet speed %.0f exceeded cap", sp))
      end
    end
    prev = {}
    for _, id in ipairs(d.bullet_ids()) do prev[id] = { x = pos[id].x, y = pos[id].y } end
  end
  check(died, "timedodge: converging bullets reach a lose while moving")
  check(events_have("log", "lose"), "timedodge: the lose is logged with fx")

  -- Game over shows a result card with RETRY + MODES buttons (no Home button
  -- on the run screen — navigation lives on the card now).
  check(d.back == nil, "timedodge: a run has no Home button")
  check(d.card() ~= nil, "timedodge: game over shows a result card")
  clear_input()
  tap_card("retry"); d = DEBUG
  check(d.alive() and d.score() < 0.5, "timedodge: RETRY restarts a fresh endless round")
  -- Die again, then the card's MODES button returns to mode select.
  kill_run()
  check(not DEBUG.alive(), "timedodge: standing still with time flowing eventually dies")
  clear_input()
  tap_card("modes")
  check(DEBUG.mode() == "select", "timedodge: the card MODES button returns to mode select")

  -- TRIALS -----------------------------------------------------------
  clear_input()
  on_tap(DEBUG.btn_trials.x, DEBUG.btn_trials.y); step()
  local L = DEBUG
  check(L.mode() == "levels", "timedodge: TRIALS opens the level grid")
  check(L.unlocked(1), "timedodge: moment 1 starts unlocked")
  check(not L.unlocked(2), "timedodge: moment 2 starts locked")
  on_tap(L.lv_btn(2).x, L.lv_btn(2).y); step()
  check(DEBUG.mode() == "levels", "timedodge: a locked moment cannot be entered")

  on_tap(L.lv_btn(1).x, L.lv_btn(1).y); step()
  d = DEBUG
  check(d.mode() == "run" and d.trial() == 1, "timedodge: moment 1 starts a trial run")
  check(d.gate() ~= nil, "timedodge: a trial spawns its first time gate")

  -- The trial clock counts REAL seconds even while frozen (freeze is safe
  -- but never free) — release for 1s and the clock must advance ~1s.
  local e0 = d.elapsed()
  clear_input()
  for _ = 1, 60 do step() end
  check(d.elapsed() - e0 > 0.9, "timedodge: the trial clock keeps counting while frozen")
  check(d.timescale() <= 0.1, "timedodge: releasing still freezes the world in a trial")

  -- Autopilot: beeline to each gate; retry on death; must clear in budget.
  local cleared, attempts = false, 0
  for _ = 1, 12000 do
    if d.done() then cleared = true; break end
    if not d.alive() then
      attempts = attempts + 1
      if attempts > 5 then break end
      clear_input(); tap_card("retry"); d = DEBUG
    else
      local g = d.gate()
      if g then                                -- relative drag: feed deltas
        local p = pos[d.player]
        local dxg, dyg = g.x - p.x, g.y - p.y
        local m = math.sqrt(dxg * dxg + dyg * dyg)
        if m > 1 then
          game._down = true
          game._px = (game._px or 0) + dxg / m * 6
          game._py = (game._py or 0) + dyg / m * 6
        end
      end
      step()
    end
  end
  check(cleared, "timedodge: moment 1 is clearable by heading for the gates")

  -- The seal card's LEVELS button -> level grid; the clear awarded stars.
  clear_input()
  tap_card("levels")
  L = DEBUG
  check(L.mode() == "levels", "timedodge: the result card returns to the level grid")
  check(L.stars_of(1) >= 1, "timedodge: clearing a moment awards at least one star")
  check(L.unlocked(2), "timedodge: one star unlocks the next moment")

  -- The base icon on the grid steps up to mode select (menus need no confirm).
  on_tap(L.base().x, L.base().y); step()
  check(DEBUG.mode() == "select", "timedodge: base icon on the grid returns to mode select")

  -- ABSORB -----------------------------------------------------------
  check(DEBUG.btn_absorb ~= nil, "timedodge: mode select exposes the ABSORB button")
  clear_input()
  on_tap(DEBUG.btn_absorb.x, DEBUG.btn_absorb.y); step()
  d = DEBUG
  check(d.mode() == "run" and d.absorb(), "timedodge: ABSORB starts an absorb run")
  check(d.size() == 26, "timedodge: absorb starts at base mass")
  check(not d.dialog_used() and d.hit_dialog() == nil,
    "timedodge: a fresh absorb run starts with the cancel-hit offer armed")

  -- Hold still at centre: rocks converge; eating smaller ones grows you. The
  -- FIRST bigger rock must NOT chip — it opens the cancel-hit dialog instead,
  -- so until the dialog appears the mass may only ever grow.
  game._down = true
  local prev_m, saw_grow, saw_shrink = d.size(), false, false
  local mass_at_dialog = nil
  for _ = 1, 20000 do
    step()
    check_once("ab_alive1", d.alive(), "timedodge: died before the first big hit could offer the dialog")
    if not d.alive() then break end
    local m = d.size()
    if m > prev_m + 0.01 then saw_grow = true end
    check_once("ab_nochip1", m >= prev_m - 0.01,
      "timedodge: mass chipped before the first-hit dialog opened")
    check_once("ab_cap", m <= 120.5, "timedodge: absorb mass exceeded the cap")
    prev_m = m
    if d.hit_dialog() then mass_at_dialog = m; break end
  end
  check(mass_at_dialog ~= nil, "timedodge: the first big hit opens the cancel-hit dialog")
  check(d.dialog_used(), "timedodge: opening the dialog burns the once-per-run offer")
  local hd = d.hit_dialog()
  check(hd and hd.yes and hd.no, "timedodge: the dialog exposes YES and NO button rects")

  -- The world is frozen SOLID while the dialog is up: with the pointer held
  -- and wiggling, no rock moves, the player stays put, and the mass holds.
  local rock_ids = d.bullet_ids()
  check(#rock_ids > 0, "timedodge: live rocks exist while the dialog is up")
  local rock_pos = {}
  for _, id in ipairs(rock_ids) do rock_pos[id] = { x = pos[id].x, y = pos[id].y } end
  local pp = { x = pos[d.player].x, y = pos[d.player].y }
  for i = 1, 30 do
    game._down, game._px, game._py = true, 100 * math.sin(i), 100 * math.cos(i)
    step()
  end
  for id, f in pairs(rock_pos) do
    check_once("ab_dlg_frozen", pos[id] ~= nil and pos[id].x == f.x and pos[id].y == f.y,
      "timedodge: a rock moved while the cancel-hit dialog was up")
  end
  check(pos[d.player].x == pp.x and pos[d.player].y == pp.y,
    "timedodge: the player moved while the cancel-hit dialog was up")
  check(d.size() == mass_at_dialog, "timedodge: the pending chip is not applied while the dialog is up")
  check(d.hit_dialog() ~= nil, "timedodge: the dialog stays open until answered")

  -- A tap outside the two buttons is swallowed while the dialog is up.
  clear_input()
  on_tap(0, 320); step()
  check(d.hit_dialog() ~= nil and d.mode() == "run",
    "timedodge: the dialog swallows any tap outside its buttons")

  -- NO: dismiss and take the chip (mass * 0.75), run resumes.
  hd = d.hit_dialog()
  on_tap(hd.no.x, hd.no.y)
  check(d.hit_dialog() == nil, "timedodge: NO dismisses the dialog")
  check(math.abs(d.size() - mass_at_dialog * 0.75) < 0.01,
    "timedodge: NO applies the normal 25% chip")
  check(d.alive(), "timedodge: the declined chip above min mass does not kill")
  step()

  -- Resume: later big hits chip DIRECTLY (no second dialog), and the chip
  -- chain eventually fades you away exactly like before.
  game._down = true
  prev_m = d.size()
  local adied = false
  for _ = 1, 20000 do
    step()
    if not d.alive() then adied = true; break end
    check_once("ab_one_dialog", d.hit_dialog() == nil,
      "timedodge: a second dialog opened in the same run")
    local m = d.size()
    if m > prev_m + 0.01 then saw_grow = true end
    if m < prev_m - 0.01 then saw_shrink = true end
    check_once("ab_cap2", m <= 120.5, "timedodge: absorb mass exceeded the cap")
    check_once("ab_min", m >= 13 - 0.5, "timedodge: absorb mass below the floor while alive")
    prev_m = m
  end
  check(d.dialog_used(), "timedodge: dialog_used stays true for the rest of the run")
  check(saw_grow, "timedodge: eating a smaller rock grows you")
  check(saw_shrink, "timedodge: a bigger rock chips you down")
  check(adied, "timedodge: the chip chain eventually fades you away")
  check(events_have("log", "lose"), "timedodge: absorb death is logged")
  clear_input()
  tap_card("retry")
  check(DEBUG.alive() and DEBUG.absorb(), "timedodge: RETRY after fading restarts absorb")
  check(DEBUG.size() == 26, "timedodge: absorb restart resets the mass")

  -- YES path: the restart re-armed the offer. Ride to the first dialog again,
  -- answer YES -> game.open_url("https://google.com") fires, the dialog closes,
  -- and NO chip is applied (the rock shattered harmlessly).
  d = DEBUG
  check(not d.dialog_used(), "timedodge: a new run re-arms the cancel-hit offer")
  game._down = true
  mass_at_dialog = nil
  for _ = 1, 20000 do
    step()
    if not d.alive() then break end
    if d.hit_dialog() then mass_at_dialog = d.size(); break end
  end
  check(mass_at_dialog ~= nil, "timedodge: the re-armed dialog opens on the next run's first big hit")
  clear_input()
  hd = d.hit_dialog()
  on_tap(hd.yes.x, hd.yes.y)
  check(events_have("open_url", "https://google.com"),
    "timedodge: YES opens the sponsor url via game.open_url")
  check(d.hit_dialog() == nil, "timedodge: YES dismisses the dialog")
  check(d.size() == mass_at_dialog, "timedodge: YES cancels the chip (mass unchanged)")
  check(d.alive(), "timedodge: the run resumes alive after YES")
  step()

  -- Drive the absorb run to its end, then the card MODES -> select -> menu.
  kill_run()
  check(not DEBUG.alive(), "timedodge: the absorb run eventually ends")
  clear_input()
  tap_card("modes")
  check(DEBUG.mode() == "select", "timedodge: absorb card MODES returns to mode select")
  on_tap(DEBUG.base().x, DEBUG.base().y); step()
  check(DEBUG.game == "menu", "timedodge: base icon on mode select returns to the lobby")
end

local function settings_tests()
  boot()
  local opened = false
  for _, t in ipairs(DEBUG.tiles) do if t.key == "settings" then on_tap(t.x, t.y); opened = true end end
  check(opened, "menu grid includes a Settings tile")
  step()
  check(DEBUG.game == "settings", "Settings tile opens the Settings screen")
  local h0 = DEBUG.hud()
  on_tap(DEBUG.toggle.x, DEBUG.toggle.y); step()
  check(DEBUG.hud() ~= h0, "Settings toggles the HUD flag")
  check(SETTINGS.hud == DEBUG.hud(), "Settings reflects the global SETTINGS.hud")
  if not SETTINGS.hud then on_tap(DEBUG.toggle.x, DEBUG.toggle.y); step() end  -- restore ON
  on_tap(DEBUG.back.x, DEBUG.back.y); step()
  check(DEBUG.game == "menu", "Settings BACK returns to the menu")
end

-- Single-game builds: AUTOBOOT boots straight into one game and BACK
-- re-enters it (the lobby menu never shows). See tools/export_web_games.sh.
local function autoboot_tests()
  AUTOBOOT = "snake"
  boot()
  check(DEBUG.game == "snake", "autoboot: boots straight into the configured game")
  on_tap(DEBUG.back.x, DEBUG.back.y); step()
  check(DEBUG.game == "snake", "autoboot: BACK re-enters the game instead of the menu")
  AUTOBOOT = nil
end

----------------------------------------------------------------------
router_tests()
grow_physics(12000, DT)
grow_miss_shrinks(6000)
breakout_win(60000)
breakout_lose(3000)
snake_tests()
rogue_tests()
game2048_tests()
shooter_tests()
world_tests()
craft_tests()
match3_tests()
umami_tests()
catch_tests()
ponies_tests()
gallery_tests()
timedodge_tests()
settings_tests()
autoboot_tests()

----------------------------------------------------------------------
-- game.touches() multi-touch contract (roadmap P0.2 acceptance):
-- two mocked fingers drive two independent paddles simultaneously.
----------------------------------------------------------------------
local function touches_tests()
  local L = { x = -300, y = 0 }
  local R = { x = 300, y = 0 }
  local function drive_paddles() -- each finger steers the paddle on its side
    for _, t in ipairs(game.touches()) do
      if t.x < 0 then L.y = t.y else R.y = t.y end
    end
  end
  game._touches = { { x = -280, y = 120, id = 7 }, { x = 310, y = -90, id = 9 } }
  drive_paddles()
  check(L.y == 120, "touches: left finger drives left paddle")
  check(R.y == -90, "touches: right finger drives right paddle")
  game._touches = { { x = -280, y = -40, id = 7 } } -- right finger lifted
  drive_paddles()
  check(L.y == -40, "touches: left finger keeps driving after right lifts")
  check(R.y == -90, "touches: lifted finger stops driving its paddle")
  game._touches = {}
  check(#game.touches() == 0, "touches: empty when no fingers down")
end
touches_tests()

----------------------------------------------------------------------
-- Analytics + Ad-director API contract (platform pillars, first slice):
--   * game.track accepts a props TABLE (and a number, and nothing) w/o erroring
--   * game.ad_reward's callback fires EXACTLY once, granted=false/no_fill
--   * game.ad_moment / game.ad_ready exist and behave (no-op / always false)
----------------------------------------------------------------------
local function pump_ads()
  local pend = game._ad_pending
  game._ad_pending = {}
  for _, cb in ipairs(pend) do cb(false, "no_fill") end
end
local function platform_api_tests()
  frame_events = {}
  -- Back-compat + new table form: none of these may raise.
  local ok = pcall(function()
    game.track("level_start")
    game.track("score", 42)
    game.track("run_end", { score = 42, mode = "hard", win = true })
  end)
  check(ok, "track: accepts nil / number / table props without erroring")

  -- ad_ready is false with the Null backend; ad_moment is a logged no-op.
  check(game.ad_ready("rewarded") == false, "ad_ready: false with the Null backend")
  game.ad_moment("level_complete")
  check(events_have("ad_moment", "level_complete"), "ad_moment: declares the placement")

  -- ad_reward: the callback must fire exactly once, on a later pump, false/no_fill.
  local calls, seen_granted, seen_reason = 0, nil, nil
  game.ad_reward("rewarded", function(granted, reason)
    calls = calls + 1; seen_granted = granted; seen_reason = reason
  end)
  check(calls == 0, "ad_reward: callback does not fire synchronously")
  pump_ads()
  check(calls == 1, "ad_reward: callback fires exactly once")
  check(seen_granted == false and seen_reason == "no_fill",
    "ad_reward: Null backend resolves granted=false / no_fill")
  pump_ads()
  check(calls == 1, "ad_reward: callback never fires a second time")
end
platform_api_tests()

----------------------------------------------------------------------
-- Showcase pack: 9 capability stations, each with a BENCH mode
----------------------------------------------------------------------
local function showcase_tests()
  boot()
  local d = enter("showcase")
  check(d and d.game == "showcase", "menu should enter the showcase pack")
  check(d.back ~= nil, "showcase should expose a back button")
  check(d.station() == nil, "showcase starts on the hub")
  check(#d.cards() == 9, "hub should list 9 station cards")

  for _, key in ipairs({ "vault", "touch", "atlas", "camera", "mixer",
                         "sparks", "tiles", "robot", "juice" }) do
    d.enter_station(key)
    step()
    check(DEBUG.station() == key, "should enter station '" .. key .. "'")
    -- demo mode: 2 seconds of frames, with a two-finger snapshot present
    game._touches = { { x = 10, y = 20, id = 1 }, { x = -40, y = 60, id = 2 } }
    for _ = 1, 120 do step() end
    game._touches = {}
    -- bench mode: fixed headless dt never blows the budget, so the level must
    -- ramp to the cap and then freeze a score (proves cap + scoring both work)
    DEBUG.bench_start()
    local guard = 0
    while DEBUG.bench_score() == nil and guard < 3000 do step(); guard = guard + 1 end
    check(DEBUG.bench_score() ~= nil, "bench must produce a score at '" .. key .. "'")
    check(DEBUG.bench_score() == 12, "headless bench should hit the level cap at '" .. key .. "'")
    check(game._store["sc_bench_" .. key] == 12,
      "bench best score should persist via game.save at '" .. key .. "'")
  end

  -- hub round-trip + leave cleans up
  d.enter_station(nil)
  step()
  check(DEBUG.station() == nil, "HUB action should return to the hub")
  on_tap(d.back.x, d.back.y); step()
  local d2 = enter("showcase")
  check(d2 and d2.game == "showcase", "showcase should be re-enterable after back")
  check(d2.station() == nil, "re-entry lands on a fresh hub")
  on_tap(d2.back.x, d2.back.y); step()
end
showcase_tests()

print(string.format("checks=%d", checks))
if #failures == 0 then
  print("PASS — all games' invariants held")
  os.exit(0)
else
  print(string.format("FAIL — %d violated:", #failures))
  for _, f in ipairs(failures) do print("  - " .. f) end
  os.exit(1)
end
