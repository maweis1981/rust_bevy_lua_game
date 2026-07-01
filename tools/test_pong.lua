-- Automated gameplay tests for assets/scripts/main.lua.
--
-- The real Rust `game` API is mocked here so the Lua gameplay can run headless
-- under `lua5.4`. We assert the "game feel" invariants the effects work
-- promised, across two scenarios:
--
--   Rally scenario (player perfectly tracks the ball -> long rallies):
--     * no teleport   — paddles/ball never jump more than their speed allows
--     * no tunneling   — the ball never penetrates a paddle it overlaps
--     * bounded speed  — total ball speed never exceeds the cap
--     * wall containment
--     * effects fire    — every paddle rebound plays hit sound + shake + haptic
--
--   Miss scenario (player idle -> the ball scores):
--     * serve pause    — after a score the ball is frozen at center for a beat
--     * score effects   — score sound + success haptic + shake
--
-- Run: lua5.4 tools/test_pong.lua   (exits non-zero on any failure)

local DT = 1 / 60
local HW, HH = 215, 466

----------------------------------------------------------------------
-- Mock host API
----------------------------------------------------------------------
local dims, pos, max_id = {}, {}, 0
local frame_events            -- events captured during the current callback
local ptr_y, ptr_down = nil, false

local function record(name, arg)
  if frame_events then frame_events[#frame_events + 1] = { name, arg } end
end

game = {
  log = function(_) end,
  bounds = function() return HW, HH end,
  spawn = function(x, y, w, h)
    max_id = max_id + 1
    dims[max_id] = { w = w, h = h }
    pos[max_id] = { x = x, y = y }
    return max_id
  end,
  move_to = function(id, x, y) pos[id] = { x = x, y = y } end,
  set_color = function() end,
  despawn = function(id) pos[id] = nil end,
  set_text = function() end,
  shake = function(v) record("shake", v) end,
  play_sound = function(n) record("sound", n) end,
  play_music = function(n) record("music", n) end,
  haptic = function(k) record("haptic", k) end,
  pointer = function() return nil, ptr_y, ptr_down end,
  key = function() return false end,
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
local function check_once(key, cond, msg)  -- record a repeating failure once
  checks = checks + 1
  if not cond and not seen[key] then
    seen[key] = true
    failures[#failures + 1] = msg
  end
end

----------------------------------------------------------------------
-- Load once; on_start rebuilds state each call.
----------------------------------------------------------------------
dofile("assets/scripts/main.lua")

-- Boot a fresh game and return the (left, right, ball) entity ids. The first
-- on_update builds the scene; its last three spawns are left, right, ball.
local function boot()
  frame_events = {}
  on_start()
  check(events_have("music"), "background music should start on_start")
  frame_events = {}
  on_update(DT)  -- builds scene
  return max_id - 2, max_id - 1, max_id
end

----------------------------------------------------------------------
-- Scenario 1: long rallies (player tracks the ball perfectly)
----------------------------------------------------------------------
local function rally_scenario(frames)
  local left_id, right_id, ball_id = boot()
  check(dims[ball_id].w == dims[ball_id].h, "ball sprite should be square")
  local ball_hw = dims[ball_id].w * 0.5
  local pad_hw = dims[left_id].w * 0.5
  local pad_hh = dims[left_id].h * 0.5

  local prev_ball, prev_left, prev_right, prev_dx = nil, nil, nil, 0
  local hits, sign_flips, peak = 0, 0, 0

  for _ = 1, frames do
    ptr_down, ptr_y = true, pos[ball_id].y  -- perfect tracking
    frame_events = {}
    on_update(DT)

    local b, l, r = pos[ball_id], pos[left_id], pos[right_id]
    local scored = events_have("sound", "score")
    local at_origin = math.abs(b.x) < 0.001 and math.abs(b.y) < 0.001

    if events_have("sound", "hit") then
      hits = hits + 1
      check_once("hit_shake", events_have("shake"),
        "paddle rebound must trigger screen shake")
      check_once("hit_haptic", events_have("haptic", "light"),
        "paddle rebound must fire a light haptic")
    end

    if prev_ball and not scored and not at_origin then
      local dx = b.x - prev_ball.x
      local dy = b.y - prev_ball.y
      local speed = math.sqrt(dx * dx + dy * dy) / DT
      peak = math.max(peak, speed)
      check_once("ballspeed", speed <= 785,
        string.format("ball total speed %.1f exceeded the ~780 cap", speed))
      -- No stuck-vertical ball: outside rebound frames the ball keeps real
      -- horizontal motion (the bounce-angle cap guarantees this).
      if not events_have("sound", "hit") then
        check_once("horiz_floor", math.abs(dx) / DT >= 120,
          string.format("ball horizontal speed dropped to %.0f (near-stuck)", math.abs(dx) / DT))
      end
      if prev_dx ~= 0 and dx ~= 0 and (prev_dx < 0) ~= (dx < 0) then
        sign_flips = sign_flips + 1
      end
      prev_dx = dx
    end

    check_once("wall", math.abs(b.y) <= HH - ball_hw + 0.5,
      string.format("ball y=%.1f left the vertical bounds", b.y))

    local l_face = l.x + pad_hw + ball_hw
    local r_face = r.x - pad_hw - ball_hw
    if math.abs(b.y - l.y) <= pad_hh + ball_hw then
      check_once("tunnel_l", b.x >= l_face - 1.0,
        string.format("ball tunneled the LEFT paddle (x=%.1f, face=%.1f)", b.x, l_face))
    end
    if math.abs(b.y - r.y) <= pad_hh + ball_hw then
      check_once("tunnel_r", b.x <= r_face + 1.0,
        string.format("ball tunneled the RIGHT paddle (x=%.1f, face=%.1f)", b.x, r_face))
    end

    if prev_left then
      local dl = math.abs(l.y - prev_left.y)
      check_once("pad_teleport", dl <= 760 * DT + 0.5,
        string.format("left (player) paddle jumped %.1f px in one frame (teleport)", dl))
    end
    if prev_right then
      local dr = math.abs(r.y - prev_right.y)
      check_once("ai_teleport", dr <= 430 * DT + 0.5,
        string.format("right (AI) paddle jumped %.1f px in one frame (teleport)", dr))
    end

    prev_ball = { x = b.x, y = b.y }
    prev_left = { y = l.y }
    prev_right = { y = r.y }
  end

  -- Every physical rebound (horizontal direction flip) should pair with a hit
  -- sound. They're measured one frame apart, so allow a small slack.
  check(hits > 10, string.format("expected many rallies, saw %d hit sounds", hits))
  check(math.abs(hits - sign_flips) <= 2,
    string.format("hit sounds (%d) should match physical rebounds (%d)", hits, sign_flips))
  return peak, hits
end

----------------------------------------------------------------------
-- Scenario 2: player idle -> the ball gets past and scores
----------------------------------------------------------------------
local function miss_scenario(frames)
  local _, _, ball_id = boot()
  local scores, serve_pauses_ok, checked_pause = 0, 0, false
  local origin_run = 0

  for _ = 1, frames do
    ptr_down, ptr_y = false, nil  -- idle player
    frame_events = {}
    on_update(DT)

    local b = pos[ball_id]
    if events_have("sound", "score") then
      scores = scores + 1
      check_once("score_haptic", events_have("haptic", "success"),
        "a score must fire the success haptic")
      check_once("score_shake", events_have("shake"),
        "a score must trigger screen shake")
    end

    -- Track how long the ball sits frozen at the center (the serve pause).
    if math.abs(b.x) < 0.001 and math.abs(b.y) < 0.001 then
      origin_run = origin_run + 1
    else
      if origin_run > 0 and checked_pause == false then
        -- A completed pause: SERVE_DELAY (0.9s ~ 54 frames), allow slack.
        check(origin_run >= 45,
          string.format("serve pause was only %d frames (~expected 54)", origin_run))
        serve_pauses_ok = serve_pauses_ok + 1
        if serve_pauses_ok >= 2 then checked_pause = true end
      end
      origin_run = 0
    end
  end

  check(scores >= 1, "player idle should concede at least one score")
  check(serve_pauses_ok >= 1, "should observe at least one serve pause after a score")
  return scores
end

----------------------------------------------------------------------
-- Scenario 3: frame hitches / low FPS (big dt, e.g. app resume on mobile).
-- The ball must never tunnel a paddle or teleport across the screen, no matter
-- how large a single dt is. Physics should internally clamp the step.
----------------------------------------------------------------------
local function hitch_scenario(frames, big_dt)
  local left_id, right_id, ball_id = boot()
  local ball_hw = dims[ball_id].w * 0.5
  local pad_hw = dims[left_id].w * 0.5
  local pad_hh = dims[left_id].h * 0.5
  local prev_ball = nil
  local max_step = 0

  for _ = 1, frames do
    ptr_down, ptr_y = true, pos[ball_id].y
    frame_events = {}
    on_update(big_dt)  -- a huge frame time

    local b, l, r = pos[ball_id], pos[left_id], pos[right_id]
    local scored = events_have("sound", "score")
    local at_origin = math.abs(b.x) < 0.001 and math.abs(b.y) < 0.001
    if prev_ball and not scored and not at_origin then
      local step = math.sqrt((b.x - prev_ball.x) ^ 2 + (b.y - prev_ball.y) ^ 2)
      max_step = math.max(max_step, step)
      -- Even on a huge dt the ball must not leap more than a clamped step
      -- (cap 780 px/s * clamp 1/30 s ~= 26 px, plus slack).
      check_once("hitch_step", step <= 30,
        string.format("ball leapt %.1f px on a hitch frame (dt=%.2f) — dt not clamped", step, big_dt))
    end

    local l_face = l.x + pad_hw + ball_hw
    local r_face = r.x - pad_hw - ball_hw
    if math.abs(b.y - l.y) <= pad_hh + ball_hw then
      check_once("hitch_tunnel_l", b.x >= l_face - 1.0,
        string.format("ball tunneled LEFT paddle on a hitch (x=%.1f, face=%.1f)", b.x, l_face))
    end
    if math.abs(b.y - r.y) <= pad_hh + ball_hw then
      check_once("hitch_tunnel_r", b.x <= r_face + 1.0,
        string.format("ball tunneled RIGHT paddle on a hitch (x=%.1f, face=%.1f)", b.x, r_face))
    end
    prev_ball = { x = b.x, y = b.y }
  end
  return max_step
end

----------------------------------------------------------------------
local peak, hits = rally_scenario(6000)
local scores = miss_scenario(4000)
local hitch_step = hitch_scenario(3000, 0.2)  -- 200 ms frames (5 FPS)
print(string.format("hitch: max_step=%.1f px (dt=0.20)", hitch_step))

print(string.format("rally: hits=%d peak_speed=%.0f | miss: scores=%d | checks=%d",
  hits, peak, scores, checks))
if #failures == 0 then
  print("PASS — all gameplay invariants held")
  os.exit(0)
else
  print(string.format("FAIL — %d invariant(s) violated:", #failures))
  for _, f in ipairs(failures) do print("  - " .. f) end
  os.exit(1)
end
