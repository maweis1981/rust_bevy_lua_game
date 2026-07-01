-- main.lua — "Grow the Paddle" (a Pong variant)
--
-- Two-paddle Pong, but the LEFT paddle (you) changes size:
--   * hit a GREEN (good) ball -> your paddle GROWS
--   * hit a RED (bad) ball    -> your paddle SHRINKS   (so dodge red balls!)
--   * miss a GREEN ball        -> your paddle SHRINKS
--   * dodge a RED ball (let it pass) -> safe, no penalty
-- Grow until the paddle fills the whole screen height -> YOU WIN.
-- Shrink to nothing -> GAME OVER. Tap to restart.
--
-- The ball re-rolls its colour every time the AI paddle returns it, so each
-- approach is a fresh choice (telegraphed by colour). The bigger your paddle
-- gets, the harder red balls are to dodge — that's the difficulty curve.
--
-- Controls: drag (mouse held / finger) or Up/Down (W/S). See src/script.rs for
-- the host API (spawn/move_to/set_color/set_size/shake/play_sound/haptic/...).

local PADDLE_W = 20
local AI_H = 120           -- right (AI) paddle height, fixed
local BALL = 22
local MARGIN = 46
local PADDLE_SPEED = 780   -- max player paddle speed (px/s)
local AI_SPEED = 430
local AI_DEADZONE = 10
local BALL_SPEED = 360     -- serve speed (px/s)
local BALL_MAX = 720       -- total speed cap
local SPEEDUP = 1.03
local MAX_BOUNCE_ANGLE = 0.87
local MAX_DT = 1 / 30       -- clamp long frames so nothing teleports
local SERVE_DELAY = 0.8
local TRAIL_N = 12

local PLAYER_H_START = 90
local PLAYER_H_MIN = 26     -- lose at/under this height
local GROW = 34             -- good hit grows the paddle
local SHRINK = 44           -- bad hit / missed-good shrinks it
local GOOD_CHANCE = 0.58    -- probability a served/returned ball is green

local BASE_L = { 0.55, 0.78, 1.00 }   -- player paddle base colour
local BASE_R = { 1.00, 0.55, 0.30 }   -- AI paddle colour
local GOOD_COLOR = { 0.30, 0.95, 0.55 }
local BAD_COLOR = { 1.00, 0.32, 0.32 }

local left, right, ball          -- entity ids
local ly, ry = 0, 0
local lh = PLAYER_H_START         -- dynamic left paddle height
local bx, by, bvx, bvy = 0, 0, 0, 0
local ball_good = true
local wait, pending_dir = 0, -1
local playing = true
local trail, trail_cursor = {}, 0
local l_flash, l_flash_col = 0, GOOD_COLOR
local r_flash = 0
local started = false
local SCR_HW, SCR_HH = 0, 0       -- current half-extents (updated each frame)

local function clamp(v, lo, hi)
  if v < lo then return lo elseif v > hi then return hi else return v end
end

-- Blend base -> target by t, returning three colour components.
local function blend(base, target, t)
  return base[1] + (target[1] - base[1]) * t,
         base[2] + (target[2] - base[2]) * t,
         base[3] + (target[3] - base[3]) * t
end

local function refresh_hud()
  local pct = math.floor(100 * lh / (2 * SCR_HH))
  game.set_text(string.format("%d%%", pct))
end

-- Resize the player paddle sprite and keep it on-screen.
local function set_player_size()
  game.set_size(left, PADDLE_W, lh)
  local plim = math.max(0, SCR_HH - lh * 0.5)
  ly = clamp(ly, -plim, plim)
end

local function win_game()
  playing = false
  game.set_text("YOU WIN! 撑满全屏 🎉\n点击重玩")
  game.play_sound("score"); game.haptic("success"); game.shake(0.7)
  game.log("win")
end

local function lose_game()
  playing = false
  game.set_text("GAME OVER\n点击重玩")
  game.play_sound("hit"); game.haptic("heavy"); game.shake(0.7)
  game.log("lose")
end

local function grow_paddle()
  lh = math.min(lh + GROW, 2 * SCR_HH)
  set_player_size()
  if lh >= 2 * SCR_HH then win_game() else refresh_hud() end
end

local function shrink_paddle()
  lh = lh - SHRINK
  if lh <= PLAYER_H_MIN then
    lh = PLAYER_H_MIN; set_player_size(); lose_game()
  else
    set_player_size(); refresh_hud()
  end
end

-- Pick the incoming ball's type and colour it (a colour telegraph).
local function roll_type()
  ball_good = math.random() < GOOD_CHANCE
  local c = ball_good and GOOD_COLOR or BAD_COLOR
  game.set_color(ball, c[1], c[2], c[3], 1)
end

-- Freeze the ball at center and start a serve toward `dir` with a fresh type.
local function serve(dir)
  bx, by, bvx, bvy = 0, 0, 0, 0
  wait, pending_dir = SERVE_DELAY, dir
  roll_type()
end

local function launch()
  bvx = BALL_SPEED * pending_dir
  bvy = BALL_SPEED * (math.random() * 0.6 - 0.3)
end

-- Reflect the ball off a paddle: offset steers the angle, total speed capped.
local function rebound(paddle_y, face_x, dir, half_h)
  local off = clamp((by - paddle_y) / half_h, -1, 1)
  local speed = math.min(math.sqrt(bvx * bvx + bvy * bvy) * SPEEDUP, BALL_MAX)
  local angle = off * MAX_BOUNCE_ANGLE
  bx = face_x
  bvx = dir * speed * math.cos(angle)
  bvy = speed * math.sin(angle)
end

local function init(hw, hh)
  local seg, gap = 22, 16
  local step = seg + gap
  local n = math.floor((2 * hh) / step)
  local y = -(n - 1) * step * 0.5
  for _ = 1, n do
    game.spawn(0, y, 4, seg, 1, 1, 1, 0.14)
    y = y + step
  end
  for i = 1, TRAIL_N do
    local id = game.spawn(0, 0, BALL * 0.7, BALL * 0.7, 0.75, 0.85, 1.0, 0)
    trail[i] = { id = id, a = 0 }
  end
  left  = game.spawn(-hw + MARGIN, 0, PADDLE_W, PLAYER_H_START, BASE_L[1], BASE_L[2], BASE_L[3])
  right = game.spawn( hw - MARGIN, 0, PADDLE_W, AI_H, BASE_R[1], BASE_R[2], BASE_R[3])
  ball  = game.spawn(0, 0, BALL, BALL, 1, 1, 1)
  lh = PLAYER_H_START
  refresh_hud()
  serve(-1)
  started = true
end

function on_start()
  game.log("Grow the Paddle — started")
  playing = true
  started = false
  game.play_music("music")
end

local function reset_game()
  lh = PLAYER_H_START
  ly = 0
  set_player_size()
  playing = true
  serve(-1)
  refresh_hud()
end

function on_tap(_, _)
  if not playing then reset_game() end
end

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

function on_update(dt)
  local hw, hh = game.bounds()
  if hw <= 0 then return end
  SCR_HW, SCR_HH = hw, hh
  if not started then init(hw, hh) end
  if not playing then return end       -- game over: hold the frame, await a tap
  dt = math.min(dt, MAX_DT)

  local lx = -hw + MARGIN
  local rx =  hw - MARGIN
  local plimit = math.max(0, hh - lh * 0.5)
  local ai_plimit = hh - AI_H * 0.5

  move_player(dt, plimit)
  if not (wait > 0) and math.abs(by - ry) > AI_DEADZONE then
    local step = clamp(by - ry, -AI_SPEED * dt, AI_SPEED * dt)
    ry = clamp(ry + step, -ai_plimit, ai_plimit)
  end

  if wait > 0 then
    wait = wait - dt
    if wait <= 0 then launch() end
  else
    local old_x = bx
    bx = bx + bvx * dt
    by = by + bvy * dt

    local top = hh - BALL * 0.5
    if by > top then by = top; bvy = -math.abs(bvy); game.play_sound("wall"); game.shake(0.04) end
    if by < -top then by = -top; bvy = math.abs(bvy); game.play_sound("wall"); game.shake(0.04) end

    local l_half = lh * 0.5
    local l_face = lx + PADDLE_W * 0.5 + BALL * 0.5
    local r_face = rx - PADDLE_W * 0.5 - BALL * 0.5

    -- Player paddle: hit applies the good/bad size effect, then rallies right.
    if bvx < 0 and old_x >= l_face and bx <= l_face
       and math.abs(by - ly) <= l_half + BALL * 0.5 then
      rebound(ly, l_face, 1, l_half)
      if ball_good then
        l_flash, l_flash_col = 1, GOOD_COLOR
        game.play_sound("hit"); game.haptic("success"); game.shake(0.12)
        grow_paddle()
      else
        l_flash, l_flash_col = 1, BAD_COLOR
        game.play_sound("hit"); game.haptic("heavy"); game.shake(0.28)
        shrink_paddle()
      end
    -- AI paddle: returns the ball and re-rolls its colour for the next approach.
    elseif bvx > 0 and old_x <= r_face and bx >= r_face
       and math.abs(by - ry) <= AI_H * 0.5 + BALL * 0.5 then
      rebound(ry, r_face, -1, AI_H * 0.5)
      r_flash = 1
      game.play_sound("wall")
      roll_type()
    end

    -- Ball left the field.
    if playing and bx < -hw then
      if ball_good then
        game.play_sound("hit"); shrink_paddle()   -- missed a good one
      else
        game.play_sound("wall")                    -- dodged a bad one: safe
      end
      if playing then serve(-1) end
    elseif playing and bx > hw then
      serve(-1)                                    -- AI missed: neutral respawn
    end
  end

  -- Ball trail.
  if not (wait > 0) then
    trail_cursor = (trail_cursor % TRAIL_N) + 1
    trail[trail_cursor].a = 0.5
    game.move_to(trail[trail_cursor].id, bx, by)
  end
  for i = 1, TRAIL_N do
    local t = trail[i]
    if t.a > 0.001 then
      t.a = t.a * 0.86
      game.set_color(t.id, 0.75, 0.85, 1.0, t.a)
    end
  end

  -- Paddle flashes.
  l_flash = math.max(0, l_flash - dt * 4)
  r_flash = math.max(0, r_flash - dt * 4)
  local lr, lg, lb = blend(BASE_L, l_flash_col, l_flash)
  local rr, rg, rb = blend(BASE_R, { 1, 1, 1 }, r_flash)
  game.set_color(left, lr, lg, lb, 1)
  game.set_color(right, rr, rg, rb, 1)

  -- Push transforms.
  game.move_to(left, lx, ly)
  game.move_to(right, rx, ry)
  game.move_to(ball, bx, by)
end
