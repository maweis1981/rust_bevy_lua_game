-- main.lua — Pong (juiced up)
--
-- Classic two-paddle Pong with a ball trail, a dashed center net, paddle
-- hit-flashes, screen shake, sound, music, and iOS haptics. You control the
-- left paddle; the right paddle is a capped-speed AI. All gameplay lives here
-- in Lua; Rust just provides the primitives below.
--
-- Controls:
--   Desktop : hold the left mouse button and move the mouse, OR the Up/Down
--             arrow keys (W/S also work).
--   iOS     : drag your finger up and down.
--
-- Host API (provided by Rust, see src/script.rs):
--   game.log(msg)
--   game.bounds() -> half_width, half_height
--   game.spawn(x, y, w, h, r, g, b [, a]) -> id
--   game.move_to(id, x, y)
--   game.set_color(id, r, g, b, a)
--   game.despawn(id)
--   game.set_text(string)
--   game.shake(intensity)                 -- 0..1 screen-shake impulse
--   game.play_sound(name) / game.play_music(name)
--   game.haptic("light"/"medium"/"heavy"/"success")
--   game.pointer() -> x, y, down
--   game.key(name) -> bool

local PADDLE_W, PADDLE_H = 20, 120
local BALL = 20
local MARGIN = 46          -- paddle distance from the side wall
local PADDLE_SPEED = 760   -- max player paddle speed (px/s) — bounds the follow
local AI_SPEED = 430       -- AI paddle speed cap (px/s), beatable on purpose
local AI_DEADZONE = 10     -- AI won't chase jitter within this many px
local BALL_SPEED = 380     -- serve speed (px/s)
local BALL_MAX = 780       -- TOTAL speed cap (keeps the ball fair + un-tunnelable)
local SPEEDUP = 1.045      -- ball speeds up a touch on every paddle hit
local MAX_BOUNCE_ANGLE = 0.87 -- rad (~50°): steepest rebound off a paddle edge
local MAX_DT = 1 / 30      -- clamp long frames (hitch / app-resume) so nothing leaps
local SERVE_DELAY = 0.9    -- pause at center before each serve (no teleporting)
local TRAIL_N = 12         -- ball-trail segment count

local L_COLOR = { 0.30, 0.80, 1.00 }
local R_COLOR = { 1.00, 0.55, 0.30 }

local left, right, ball          -- entity ids
local ly, ry = 0, 0              -- paddle center y
local bx, by, bvx, bvy = 0, 0, 0, 0
local score_l, score_r = 0, 0
local l_flash, r_flash = 0, 0    -- paddle hit-flash amounts (1 -> 0)
local wait, pending_dir = 0, 1   -- serve countdown + direction
local trail, trail_cursor = {}, 0
local started = false

local function clamp(v, lo, hi)
  if v < lo then return lo elseif v > hi then return hi else return v end
end

-- Blend base color toward white by t (used for the paddle flash).
local function flashed(base, t)
  return base[1] + (1 - base[1]) * t,
         base[2] + (1 - base[2]) * t,
         base[3] + (1 - base[3]) * t
end

local function refresh_hud()
  game.set_text(string.format("%d        %d", score_l, score_r))
end

-- Freeze the ball at center and start the serve countdown toward `dir`.
local function serve(dir)
  bx, by, bvx, bvy = 0, 0, 0, 0
  wait, pending_dir = SERVE_DELAY, dir
end

local function launch()
  bvx = BALL_SPEED * pending_dir
  local vsign = ((score_l + score_r) % 2 == 0) and 1 or -1
  bvy = BALL_SPEED * 0.35 * vsign
end

-- Build the scene lazily: the first frame with a known window size.
local function init(hw, hh)
  -- Dashed center net (dim, drawn behind everything since it spawns first).
  local seg, gap = 22, 16
  local step = seg + gap
  local n = math.floor((2 * hh) / step)
  local y = -(n - 1) * step * 0.5
  for _ = 1, n do
    game.spawn(0, y, 4, seg, 1, 1, 1, 0.14)
    y = y + step
  end

  -- Ball trail pool (white dots that fade where the ball has been).
  for i = 1, TRAIL_N do
    local id = game.spawn(0, 0, BALL * 0.7, BALL * 0.7, 0.75, 0.85, 1.0, 0)
    trail[i] = { id = id, a = 0 }
  end

  -- Paddles then ball (spawned last so the ball draws in front).
  left  = game.spawn(-hw + MARGIN, 0, PADDLE_W, PADDLE_H, L_COLOR[1], L_COLOR[2], L_COLOR[3])
  right = game.spawn( hw - MARGIN, 0, PADDLE_W, PADDLE_H, R_COLOR[1], R_COLOR[2], R_COLOR[3])
  ball  = game.spawn(0, 0, BALL, BALL, 1, 1, 1)

  refresh_hud()
  serve(1)
  started = true
end

function on_start()
  game.log("Pong — started")
  score_l, score_r = 0, 0
  started = false
  game.play_music("music")
end

-- Player paddle: smooth follow (never snaps), capped at PADDLE_SPEED.
local function move_player(dt, limit)
  local vy = 0
  local _, py, down = game.pointer()
  if down and py ~= nil then
    local target = clamp(py, -limit, limit)
    vy = clamp((target - ly) / dt, -PADDLE_SPEED, PADDLE_SPEED)
  else
    if game.key("up") or game.key("w") then vy = vy + PADDLE_SPEED end
    if game.key("down") or game.key("s") then vy = vy - PADDLE_SPEED end
  end
  ly = clamp(ly + vy * dt, -limit, limit)
end

-- Reflect the ball off a paddle: the hit offset steers the rebound angle, the
-- ball speeds up a touch, and the *total* speed is capped. Bounding total speed
-- (not just the horizontal part) keeps the ball fair and guarantees a single
-- frame can never carry it far enough to skip a paddle.
local function rebound(paddle_y, face_x, dir)
  local off = clamp((by - paddle_y) / (PADDLE_H * 0.5), -1, 1)
  local speed = math.min(math.sqrt(bvx * bvx + bvy * bvy) * SPEEDUP, BALL_MAX)
  local angle = off * MAX_BOUNCE_ANGLE
  bx = face_x
  bvx = dir * speed * math.cos(angle)
  bvy = speed * math.sin(angle)
  game.play_sound("hit")
  game.haptic("light")
  game.shake(0.12)
end

function on_update(dt)
  local hw, hh = game.bounds()
  if hw <= 0 then return end          -- window size not known yet
  if not started then init(hw, hh) end
  dt = math.min(dt, MAX_DT)           -- a hitch must never let anything teleport

  local lx = -hw + MARGIN
  local rx =  hw - MARGIN
  local plimit = hh - PADDLE_H * 0.5

  -- Paddles.
  move_player(dt, plimit)
  if not (wait > 0) and math.abs(by - ry) > AI_DEADZONE then
    local step = clamp(by - ry, -AI_SPEED * dt, AI_SPEED * dt)
    ry = clamp(ry + step, -plimit, plimit)
  end

  -- Serve countdown, then launch.
  if wait > 0 then
    wait = wait - dt
    if wait <= 0 then launch() end
  else
    -- Advance the ball (remember the old x for swept paddle collision).
    local old_x = bx
    bx = bx + bvx * dt
    by = by + bvy * dt

    -- Bounce off the top/bottom walls.
    local wall = hh - BALL * 0.5
    if by > wall then by = wall; bvy = -math.abs(bvy); game.play_sound("wall"); game.shake(0.05) end
    if by < -wall then by = -wall; bvy = math.abs(bvy); game.play_sound("wall"); game.shake(0.05) end

    -- Swept paddle collision (crossing the paddle face, not just overlap) so a
    -- fast ball can't tunnel through.
    local l_face = lx + (PADDLE_W + BALL) * 0.5
    local r_face = rx - (PADDLE_W + BALL) * 0.5
    if bvx < 0 and old_x >= l_face and bx <= l_face
       and math.abs(by - ly) <= (PADDLE_H + BALL) * 0.5 then
      rebound(ly, l_face, 1)
      l_flash = 1
    elseif bvx > 0 and old_x <= r_face and bx >= r_face
       and math.abs(by - ry) <= (PADDLE_H + BALL) * 0.5 then
      rebound(ry, r_face, -1)
      r_flash = 1
    end

    -- Score when the ball clears a side.
    if bx < -hw then
      score_r = score_r + 1; refresh_hud()
      game.play_sound("score"); game.haptic("success"); game.shake(0.6)
      serve(1)
    elseif bx > hw then
      score_l = score_l + 1; refresh_hud()
      game.play_sound("score"); game.haptic("success"); game.shake(0.6)
      serve(-1)
    end
  end

  -- Ball trail: drop a fresh dot at the ball, fade the rest.
  if not (wait > 0) then
    trail_cursor = (trail_cursor % TRAIL_N) + 1
    local d = trail[trail_cursor]
    d.a = 0.5
    game.move_to(d.id, bx, by)
  end
  for i = 1, TRAIL_N do
    local t = trail[i]
    if t.a > 0.001 then
      t.a = t.a * 0.86
      game.set_color(t.id, 0.75, 0.85, 1.0, t.a)
    end
  end

  -- Paddle hit-flash: decay toward the base color.
  l_flash = math.max(0, l_flash - dt * 4)
  r_flash = math.max(0, r_flash - dt * 4)
  local lr, lg, lb = flashed(L_COLOR, l_flash)
  local rr, rg, rb = flashed(R_COLOR, r_flash)
  game.set_color(left, lr, lg, lb, 1)
  game.set_color(right, rr, rg, rb, 1)

  -- Push transforms to the ECS.
  game.move_to(left, lx, ly)
  game.move_to(right, rx, ry)
  game.move_to(ball, bx, by)
end
