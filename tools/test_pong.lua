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
  despawn = function(id) pos[id] = nil; dims[id] = nil end,
  set_text = function() end,
  shake = function(v) record("shake", v) end,
  set_bg_theme = function(v) record("bg_theme", v) end,
  set_native_bg = function(n) record("native_bg", n) end,
  play_sound = function(n) record("sound", n) end,
  play_music = function(n) record("music", n) end,
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
dofile("assets/scripts/match3.lua")
dofile("assets/scripts/umami.lua")
dofile("assets/scripts/packs/catch.lua")
dofile("assets/scripts/packs/ponies.lua")
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
  for _, key in ipairs({ "grow", "breakout", "snake", "roguelike", "game2048", "shooter", "world", "match3", "umami", "catch", "ponies" }) do
    local d = enter(key)
    check(d and d.game == key, "menu tile should enter game '" .. key .. "'")
    check(d.back ~= nil, "game '" .. key .. "' should expose a back button")
    on_tap(d.back.x, d.back.y); step()      -- press the BACK button -> menu
    local d2 = enter(key)                   -- re-entering should work (menu was active)
    check(d2 and d2.game == key, "back button should return to the menu (re-enter '" .. key .. "')")
    on_tap(d2.back.x, d2.back.y); step()
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

-- Queens / Star Battle pack: generator validity, unique solution, tap cycle,
-- mistake hearts, play-to-win, retry, and BACK — all through real taps.
local function ponies_tests()
  boot()
  local d = enter("ponies")
  check(d.game == "ponies", "ponies (AI pack) loads and enters")
  check(d.back ~= nil, "ponies exposes a back button")
  local n = d.n()
  check(n == 5, "ponies level 1 is a 5x5 board")

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
      local p = table.remove(stack)
      local rr, cc = p[1], p[2]
      local key = rr * 100 + cc
      if rr >= 1 and rr <= n and cc >= 1 and cc <= n and not seen[key] and d.region(rr, cc) == k then
        seen[key] = true; found = found + 1
        stack[#stack + 1] = { rr + 1, cc }; stack[#stack + 1] = { rr - 1, cc }
        stack[#stack + 1] = { rr, cc + 1 }; stack[#stack + 1] = { rr, cc - 1 }
      end
    end
    check(found == cnt[k], "ponies: region " .. k .. " is contiguous")
  end

  -- The stored solution obeys every rule (perm + one per region + no touching).
  local usedc, usedk, solok = {}, {}, true
  for r = 1, n do
    local c = d.solution(r)
    local k = d.region(r, c)
    if usedc[c] or usedk[k] then solok = false end
    usedc[c], usedk[k] = true, true
    if r > 1 and math.abs(c - d.solution(r - 1)) < 2 then solok = false end
  end
  check(solok, "ponies: generated solution satisfies rows/cols/regions/adjacency")

  -- Independent solver: the shipped board has exactly one solution.
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

  -- Tap cycle on a legal cell: empty -> X -> pony -> empty.
  local sc = d.solution(1)
  local x1, y1 = d.cell_center(1, sc)
  on_tap(x1, y1); step()
  check(d.state(1, sc) == 1, "ponies: first tap marks an X")
  on_tap(x1, y1); step()
  check(d.state(1, sc) == 2 and d.placed() == 1, "ponies: second tap places a pony")
  on_tap(x1, y1); step()
  check(d.state(1, sc) == 0 and d.placed() == 0, "ponies: third tap clears the cell")

  -- Mistake: with a pony on row 1, a touching row-2 pony is rejected + costs a heart.
  on_tap(x1, y1); on_tap(x1, y1); step()
  local bc = math.max(1, sc - 1)          -- within one column of the row-1 pony
  local h0 = d.hearts()
  local bx, by = d.cell_center(2, bc)
  on_tap(bx, by)                          -- X
  on_tap(bx, by)                          -- rejected pony
  check(d.hearts() == h0 - 1, "ponies: an illegal pony costs a heart")
  check(d.state(2, bc) == 1, "ponies: the rejected pony stays an X mark")
  check(d.placed() == 1, "ponies: a rejected pony is not placed")
  check(events_have("haptic", "heavy"), "ponies: a mistake buzzes a heavy haptic")
  step()

  -- Play to win: tap out the full solution -> won, with a celebration.
  boot(); d = enter("ponies"); n = d.n()
  for r = 1, n do
    local cx, cy = d.cell_center(r, d.solution(r))
    on_tap(cx, cy); on_tap(cx, cy)
  end
  check(d.won(), "ponies: placing the full solution wins the level")
  check(events_have("sound", "score"), "ponies: winning plays the score sound")
  check(events_have("haptic", "success"), "ponies: winning fires the success haptic")
  step()
  on_tap(0, 0); step()
  check(d.level() == 2 and not d.won() and d.placed() == 0,
    "ponies: tap after a win deals the next level")

  -- Hearts drain to a game over; tap deals a fresh board with full hearts.
  boot(); d = enter("ponies")
  local s1 = d.solution(1)
  local px, py = d.cell_center(1, s1)
  on_tap(px, py); on_tap(px, py)          -- legal pony on row 1
  local wc = math.max(1, s1 - 1)
  local wx, wy = d.cell_center(2, wc)
  on_tap(wx, wy)                          -- X
  on_tap(wx, wy); on_tap(wx, wy); on_tap(wx, wy) -- three rejects -> 0 hearts
  check(d.dead(), "ponies: three mistakes end the round")
  step()
  on_tap(0, 0); step()
  check(not d.dead() and d.hearts() == 3 and d.placed() == 0,
    "ponies: tap after game over deals a fresh board with full hearts")

  -- BACK returns to the menu.
  boot(); d = enter("ponies")
  on_tap(d.back.x, d.back.y); step()
  check(DEBUG.game == "menu", "ponies: BACK returns to the menu")
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
match3_tests()
umami_tests()
catch_tests()
ponies_tests()
settings_tests()

print(string.format("checks=%d", checks))
if #failures == 0 then
  print("PASS — all games' invariants held")
  os.exit(0)
else
  print(string.format("FAIL — %d violated:", #failures))
  for _, f in ipairs(failures) do print("  - " .. f) end
  os.exit(1)
end
