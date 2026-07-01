-- main.lua — Pong
--
-- Classic two-paddle Pong, implemented entirely in Lua on top of the host API.
-- You control the left paddle; the right paddle is a capped-speed AI. First the
-- ball gets past a paddle, the other side scores.
--
-- Controls:
--   Desktop : hold the left mouse button and move the mouse, OR use the
--             Up/Down arrow keys (W/S also work).
--   iOS     : drag your finger up and down.
--
-- Host API (provided by Rust, see src/script.rs):
--   game.log(msg)
--   game.bounds() -> half_width, half_height   (world units, origin at center)
--   game.spawn(x, y, w, h, r, g, b) -> id
--   game.move_to(id, x, y)
--   game.despawn(id)
--   game.set_text(string)
--   game.pointer() -> x, y, down               (x,y nil when unavailable)
--   game.key(name) -> bool                     ("up"/"down"/"w"/"s"/...)

local PADDLE_W, PADDLE_H = 18, 120
local BALL = 18
local MARGIN = 44          -- paddle distance from the side wall
local PADDLE_SPEED = 620   -- keyboard paddle speed (px/s)
local AI_SPEED = 430       -- AI paddle speed cap (px/s) — beatable on purpose
local BALL_SPEED = 380     -- ball speed at serve (px/s)
local SPEEDUP = 1.05       -- ball speeds up on every paddle hit

local left, right, ball    -- entity ids
local ly, ry               -- paddle center y
local bx, by, bvx, bvy     -- ball position + velocity
local score_l, score_r = 0, 0

local function clamp(v, lo, hi)
  if v < lo then return lo elseif v > hi then return hi else return v end
end

local function refresh_hud()
  game.set_text(string.format("%d        %d", score_l, score_r))
end

-- Serve the ball from the center toward `dir` (-1 left, +1 right). The vertical
-- direction alternates with total rallies so serves are not all identical.
local function serve(dir)
  bx, by = 0, 0
  bvx = BALL_SPEED * dir
  local vsign = ((score_l + score_r) % 2 == 0) and 1 or -1
  bvy = BALL_SPEED * 0.35 * vsign
end

function on_start()
  game.log("Pong — started")
  local hw, _ = game.bounds()
  ly, ry = 0, 0
  left  = game.spawn(-hw + MARGIN, 0, PADDLE_W, PADDLE_H, 0.30, 0.80, 1.00)
  right = game.spawn( hw - MARGIN, 0, PADDLE_W, PADDLE_H, 1.00, 0.55, 0.30)
  ball  = game.spawn(0, 0, BALL, BALL, 1.00, 1.00, 1.00)
  serve(1)
  refresh_hud()
end

-- Axis-aligned overlap test between the ball and a paddle centered at (px, py).
local function hits_paddle(px, py)
  return math.abs(bx - px) < (PADDLE_W + BALL) * 0.5
     and math.abs(by - py) < (PADDLE_H + BALL) * 0.5
end

function on_update(dt)
  local hw, hh = game.bounds()
  if hw <= 0 then return end          -- window size not known yet

  local lx = -hw + MARGIN
  local rx =  hw - MARGIN
  local paddle_limit = hh - PADDLE_H * 0.5

  -- Player paddle: drag the pointer when held, else fall back to the keyboard.
  local _, py, down = game.pointer()
  if down and py ~= nil then
    ly = py
  else
    if game.key("up") or game.key("w") then ly = ly + PADDLE_SPEED * dt end
    if game.key("down") or game.key("s") then ly = ly - PADDLE_SPEED * dt end
  end
  ly = clamp(ly, -paddle_limit, paddle_limit)

  -- AI paddle: chase the ball's y, but no faster than AI_SPEED.
  local step = clamp(by - ry, -AI_SPEED * dt, AI_SPEED * dt)
  ry = clamp(ry + step, -paddle_limit, paddle_limit)

  -- Advance the ball.
  bx = bx + bvx * dt
  by = by + bvy * dt

  -- Bounce off the top/bottom walls.
  local wall = hh - BALL * 0.5
  if by > wall then by = wall; bvy = -math.abs(bvy) end
  if by < -wall then by = -wall; bvy = math.abs(bvy) end

  -- Paddle collisions. The hit offset steers the rebound (edge = sharper angle)
  -- and each hit nudges the speed up for a rising-tension rally.
  if bvx < 0 and hits_paddle(lx, ly) then
    local off = clamp((by - ly) / (PADDLE_H * 0.5), -1, 1)
    local spd = math.abs(bvx) * SPEEDUP
    bx = lx + (PADDLE_W + BALL) * 0.5
    bvx, bvy = spd, off * spd
  elseif bvx > 0 and hits_paddle(rx, ry) then
    local off = clamp((by - ry) / (PADDLE_H * 0.5), -1, 1)
    local spd = math.abs(bvx) * SPEEDUP
    bx = rx - (PADDLE_W + BALL) * 0.5
    bvx, bvy = -spd, off * spd
  end

  -- Score when the ball clears a side, then re-serve toward the loser.
  if bx < -hw then
    score_r = score_r + 1; refresh_hud(); serve(1)
  elseif bx > hw then
    score_l = score_l + 1; refresh_hud(); serve(-1)
  end

  -- Push everything to the ECS.
  game.move_to(left, lx, ly)
  game.move_to(right, rx, ry)
  game.move_to(ball, bx, by)
end
