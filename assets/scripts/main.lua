-- main.lua — game logic, hot-reloadable on desktop.
--
-- Available host API (provided by Rust, see src/script.rs):
--   game.log(message)
--   game.set_player_pos(x, y)
--   game.spawn_box(x, y, w, h, r, g, b)   -- color components in 0..1

-- Player movement state (pixels, pixels/second).
local x, y = 0, 0
local vx, vy = 140, 110

-- Half-extents of the play area the player bounces inside.
local bound_x, bound_y = 180, 380

function on_start()
  game.log("hollowlullaby script started")
  x, y = 0, 0

  -- Scatter a few static background boxes so reloads are visible.
  game.spawn_box(-120, 260, 40, 40, 0.9, 0.3, 0.4)
  game.spawn_box(120, 260, 40, 40, 0.3, 0.9, 0.5)
  game.spawn_box(0, -300, 220, 24, 0.6, 0.6, 0.7)
end

function on_update(dt)
  x = x + vx * dt
  y = y + vy * dt

  if x > bound_x or x < -bound_x then
    vx = -vx
    x = math.max(-bound_x, math.min(bound_x, x))
  end
  if y > bound_y or y < -bound_y then
    vy = -vy
    y = math.max(-bound_y, math.min(bound_y, y))
  end

  game.set_player_pos(x, y)
end
