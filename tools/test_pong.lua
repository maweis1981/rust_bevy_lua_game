-- Automated gameplay tests for assets/scripts/main.lua ("Grow the Paddle").
--
-- Mocks the Rust `game` API and drives main.lua headless under lua5.4. Ball type
-- (green/red) is forced by overriding math.random. Covers both the physics
-- "feel" contract and the new size mechanic.
--
--   Physics (all scenarios): no paddle/ball teleport, no tunneling (vs the
--     paddle's *current* height), total speed cap, wall containment, and — on a
--     big-dt hitch — nothing leaps across the screen.
--   Mechanic: hitting green grows the paddle (+ success haptic), hitting red
--     shrinks it, missing green shrinks it; growing to full screen = a "win",
--     shrinking to the floor = a "lose"; tap restarts.
--
-- Run: lua5.4 tools/test_pong.lua   (exits non-zero on any failure)

local HW, HH = 215, 466

----------------------------------------------------------------------
-- Deterministic RNG override so scenarios can force ball types.
----------------------------------------------------------------------
local rand_mode = "mixed"     -- "good" | "bad" | "mixed"
local rng = 987654321
local function lcg()
  rng = (1103515245 * rng + 12345) % 2147483648
  return rng / 2147483648
end
math.random = function(a, b)
  local r
  if rand_mode == "good" then r = 0.1
  elseif rand_mode == "bad" then r = 0.9
  else r = lcg() end
  if a == nil then return r end
  if b == nil then return math.floor(r * a) + 1 end
  return math.floor(r * (b - a + 1)) + a
end

----------------------------------------------------------------------
-- Mock host API
----------------------------------------------------------------------
local dims, pos, max_id = {}, {}, 0
local frame_events

local function record(name, arg)
  if frame_events then frame_events[#frame_events + 1] = { name, arg } end
end

game = {
  log = function(m) record("log", m) end,
  bounds = function() return HW, HH end,
  spawn = function(x, y, w, h)
    max_id = max_id + 1
    dims[max_id] = { w = w, h = h }
    pos[max_id] = { x = x, y = y }
    return max_id
  end,
  move_to = function(id, x, y) pos[id] = { x = x, y = y } end,
  set_color = function() end,
  set_size = function(id, w, h) dims[id] = { w = w, h = h } end,
  despawn = function(id) pos[id] = nil end,
  set_text = function() end,
  shake = function(v) record("shake", v) end,
  play_sound = function(n) record("sound", n) end,
  play_music = function(n) record("music", n) end,
  haptic = function(k) record("haptic", k) end,
  pointer = function() return nil, game._py, game._down end,
  key = function() return false end,
  _py = nil, _down = false,
}

local function events_have(name, arg)
  for _, e in ipairs(frame_events) do
    if e[1] == name and (arg == nil or e[2] == arg) then return true end
  end
  return false
end

----------------------------------------------------------------------
-- Assertions
----------------------------------------------------------------------
local failures, checks, seen = {}, 0, {}
local function check(cond, msg)
  checks = checks + 1
  if not cond then failures[#failures + 1] = msg end
end
local function check_once(key, cond, msg)
  checks = checks + 1
  if not cond and not seen[key] then
    seen[key] = true
    failures[#failures + 1] = msg
  end
end

dofile("assets/scripts/main.lua")

-- Boot a fresh game; the last three spawns are left, right, ball.
local function boot()
  frame_events = {}
  on_start()
  frame_events = {}
  on_update(1 / 60)
  return max_id - 2, max_id - 1, max_id
end

----------------------------------------------------------------------
-- Physics + mechanic under normal frames. Player perfectly tracks the ball;
-- the game auto-restarts on win/lose so physics keeps getting exercised.
----------------------------------------------------------------------
local function physics_scenario(frames, dt)
  rand_mode = "mixed"
  local left_id, right_id, ball_id = boot()
  local ball_hw = dims[ball_id].w * 0.5
  local pad_hw = dims[left_id].w * 0.5
  local ai_hh = dims[right_id].h * 0.5

  local prev_ball, prev_left, prev_lh = nil, nil, dims[left_id].h
  local saw_grow, saw_shrink, saw_win, saw_lose = false, false, false, false
  local pending_restart = false
  local finger = 0

  for _ = 1, frames do
    -- Relative-drag emulation: slide the finger by the paddle->ball gap so the
    -- paddle chases the ball (works regardless of DRAG_SENS thanks to the cap).
    finger = finger + (pos[ball_id].y - pos[left_id].y)
    game._down, game._py = true, finger
    frame_events = {}
    on_update(dt)

    -- A restart last frame resets the paddle size; that isn't a gameplay grow.
    local skip_size = pending_restart
    pending_restart = false

    local b, l, r = pos[ball_id], pos[left_id], pos[right_id]
    local lh = dims[left_id].h
    local l_half = lh * 0.5
    local over = events_have("log")               -- win/lose this frame
    if events_have("log", "win") then saw_win = true end
    if events_have("log", "lose") then saw_lose = true end
    if not skip_size and lh > prev_lh + 1e-6 then
      saw_grow = true
      check_once("grow_fx", events_have("haptic", "success") and events_have("sound", "hit"),
        "growing (good hit) must play the hit sound + success haptic")
    elseif not skip_size and lh < prev_lh - 1e-6 then
      saw_shrink = true
    end
    local resized = math.abs(lh - prev_lh) > 1e-6
    local at_origin = math.abs(b.x) < 0.001 and math.abs(b.y) < 0.001

    -- Bounds on the paddle height.
    check_once("h_max", lh <= 2 * HH + 0.5, string.format("paddle height %.1f exceeded the screen", lh))
    check_once("h_min", lh >= 26 - 0.5, string.format("paddle height %.1f went below the floor", lh))

    if prev_ball and not at_origin and not over then
      local dx, dy = b.x - prev_ball.x, b.y - prev_ball.y
      local speed = math.sqrt(dx * dx + dy * dy) / dt
      check_once("ballspeed", speed <= 730, string.format("ball speed %.1f exceeded the ~720 cap", speed))
    end

    check_once("wall", math.abs(b.y) <= HH - ball_hw + 0.5,
      string.format("ball y=%.1f left the vertical bounds", b.y))

    -- No tunneling vs the paddle's current height.
    local l_face = l.x + pad_hw + ball_hw
    local r_face = r.x - pad_hw - ball_hw
    if math.abs(b.y - l.y) <= l_half + ball_hw then
      check_once("tunnel_l", b.x >= l_face - 1.0,
        string.format("ball tunneled the LEFT paddle (x=%.1f face=%.1f)", b.x, l_face))
    end
    if math.abs(b.y - r.y) <= ai_hh + ball_hw then
      check_once("tunnel_r", b.x <= r_face + 1.0,
        string.format("ball tunneled the RIGHT paddle (x=%.1f face=%.1f)", b.x, r_face))
    end

    -- Player paddle no-teleport (skip on resize frames: a grow re-clamps the
    -- center inward, which is a legitimate reposition, not a movement jump).
    if prev_left and not resized and not over then
      local dl = math.abs(l.y - prev_left)
      check_once("pad_teleport", dl <= 780 * dt + 0.5,
        string.format("player paddle jumped %.1f px in one frame", dl))
    end

    if over then on_tap(0, 0); pending_restart = true end   -- restart to keep going

    prev_ball = { x = b.x, y = b.y }
    prev_left = l.y
    prev_lh = lh
  end

  check(saw_grow, "hitting green balls should grow the paddle")
  check(saw_shrink, "hitting red balls should shrink the paddle")
  check(saw_win, "growing to full screen should produce a win")
  check(saw_lose, "shrinking to the floor should produce a lose")
end

----------------------------------------------------------------------
-- Missing a green ball must shrink the paddle (player pinned away from it).
----------------------------------------------------------------------
local function miss_shrinks_scenario(frames)
  rand_mode = "good"
  local left_id, _, ball_id = boot()
  local start_h = dims[left_id].h
  local lost, finger = false, 0
  for _ = 1, frames do
    finger = finger + 500                 -- keep dragging up: paddle pins to top
    game._down, game._py = true, finger   -- ball drifts low -> the player misses
    frame_events = {}
    on_update(1 / 60)
    if events_have("log", "lose") then lost = true; break end
  end
  check(lost, "missing green balls (player out of the way) should shrink to a lose")
  check(dims[left_id].h < start_h, "paddle should have net-shrunk while missing green balls")
end

----------------------------------------------------------------------
-- Hitting red balls must shrink to a lose (player tracks -> always hits).
----------------------------------------------------------------------
local function bad_hits_lose_scenario(frames)
  rand_mode = "bad"
  local left_id, _, ball_id = boot()
  local lost, saw_heavy, finger = false, false, 0
  for _ = 1, frames do
    finger = finger + (pos[ball_id].y - pos[left_id].y)   -- track -> hits reds
    game._down, game._py = true, finger
    frame_events = {}
    on_update(1 / 60)
    if events_have("haptic", "heavy") then saw_heavy = true end
    if events_have("log", "lose") then lost = true; break end
  end
  check(lost, "repeatedly hitting red balls should lose the game")
  check(saw_heavy, "hitting a red ball should fire the heavy haptic")
end

----------------------------------------------------------------------
-- Frame hitch: no tunneling / no leap across the screen on a huge dt.
----------------------------------------------------------------------
local function hitch_scenario(frames, big_dt)
  rand_mode = "mixed"
  local left_id, right_id, ball_id = boot()
  local ball_hw = dims[ball_id].w * 0.5
  local pad_hw = dims[left_id].w * 0.5
  local prev_ball, max_step, finger = nil, 0, 0
  for _ = 1, frames do
    finger = finger + (pos[ball_id].y - pos[left_id].y)
    game._down, game._py = true, finger
    frame_events = {}
    on_update(big_dt)
    local b, l, r = pos[ball_id], pos[left_id], pos[right_id]
    local over = events_have("log")
    local at_origin = math.abs(b.x) < 0.001 and math.abs(b.y) < 0.001
    if prev_ball and not at_origin and not over then
      local step = math.sqrt((b.x - prev_ball.x) ^ 2 + (b.y - prev_ball.y) ^ 2)
      max_step = math.max(max_step, step)
      check_once("hitch_step", step <= 30,
        string.format("ball leapt %.1f px on a hitch (dt=%.2f) — dt not clamped", step, big_dt))
    end
    local l_half = dims[left_id].h * 0.5
    if math.abs(b.y - l.y) <= l_half + ball_hw then
      check_once("hitch_tunnel", b.x >= l.x + pad_hw + ball_hw - 1.0,
        string.format("ball tunneled the paddle on a hitch (x=%.1f)", b.x))
    end
    if over then on_tap(0, 0) end
    prev_ball = { x = b.x, y = b.y }
  end
  return max_step
end

----------------------------------------------------------------------
physics_scenario(12000, 1 / 60)
miss_shrinks_scenario(6000)
bad_hits_lose_scenario(4000)
local hitch_step = hitch_scenario(4000, 0.2)

print(string.format("checks=%d  hitch_max_step=%.1f", checks, hitch_step))
if #failures == 0 then
  print("PASS — all gameplay invariants held")
  os.exit(0)
else
  print(string.format("FAIL — %d invariant(s) violated:", #failures))
  for _, f in ipairs(failures) do print("  - " .. f) end
  os.exit(1)
end
