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
  spawn_text = function(x, y) max_id = max_id + 1; dims[max_id] = { w = 0, h = 0 }; pos[max_id] = { x = x, y = y }; return max_id end,
  move_to = function(id, x, y) pos[id] = { x = x, y = y } end,
  set_color = function() end,
  set_size = function(id, w, h) dims[id] = { w = w, h = h } end,
  despawn = function(id) pos[id] = nil; dims[id] = nil end,
  set_text = function() end,
  shake = function(v) record("shake", v) end,
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

dofile("assets/scripts/main.lua")

local TILE_Y = { grow = 122, breakout = 0, snake = -122 }
local function boot() frame_events = {}; on_start(); frame_events = {}; on_update(DT) end
local function enter(key)
  clear_input(); on_tap(0, TILE_Y[key])
  frame_events = {}; on_update(DT)          -- first update builds the scene
  return DEBUG
end
local function step(dt) frame_events = {}; on_update(dt or DT) end

----------------------------------------------------------------------
-- Router navigation
----------------------------------------------------------------------
local function router_tests()
  boot()
  for _, key in ipairs({ "grow", "breakout", "snake" }) do
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
      check_once("gtele", math.abs(l.y - prev_left) <= 780 * dt + 0.5, "player paddle teleported")
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
router_tests()
grow_physics(12000, DT)
grow_miss_shrinks(6000)
breakout_win(60000)
breakout_lose(3000)
snake_tests()

print(string.format("checks=%d", checks))
if #failures == 0 then
  print("PASS — all games' invariants held")
  os.exit(0)
else
  print(string.format("FAIL — %d violated:", #failures))
  for _, f in ipairs(failures) do print("  - " .. f) end
  os.exit(1)
end
