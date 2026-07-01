-- main.lua — a mini-game collection.
--
-- A tiny scene router (menu + games) on top of the Rust `game` bridge. Each game
-- is a closure returning { enter, update, tap, leave }; the menu lists them and
-- switches scenes. Games clean up their own entities on leave and expose a
-- `DEBUG` table (key entities/state) so tools/test_pong.lua can drive them.
--
-- Games:
--   1. Grow the Paddle — Pong variant: hit green to grow, red to shrink; fill
--      the screen to win. (Relative drag control.)
--   2. Breakout        — the classic Bevy example, ported: clear all bricks.
--   3. Snake           — grid snake: eat food, avoid walls and yourself.
--
-- Host API: see src/script.rs (spawn/move_to/set_color/set_size/spawn_text/
-- despawn/set_text/shake/play_sound/play_music/haptic/pointer/key/bounds).

local function clamp(v, lo, hi)
  if v < lo then return lo elseif v > hi then return hi else return v end
end
local function sign(v) if v > 0 then return 1 elseif v < 0 then return -1 else return 0 end end
local function in_rect(r, x, y)
  return math.abs(x - r.x) <= r.w * 0.5 and math.abs(y - r.y) <= r.h * 0.5
end

-- Tracks the entities a scene spawns so it can despawn them all on leave.
local function tracker()
  local ids = {}
  return {
    spawn = function(...) local id = game.spawn(...); ids[#ids + 1] = id; return id end,
    text = function(...) local id = game.spawn_text(...); ids[#ids + 1] = id; return id end,
    clear = function() for _, id in ipairs(ids) do game.despawn(id) end; ids = {} end,
  }
end

-- A "< BACK" button that stops the game and returns to the menu. Pinned to the
-- top-LEFT, well below the top edge so the iPhone Dynamic Island / status bar
-- never covers it. Games hit-test the returned rect in their tap handler.
local function make_back(T, hw, hh)
  local r = { x = -hw + 82, y = hh - 150, w = 148, h = 62 }
  T.spawn(r.x, r.y, r.w, r.h, 0.90, 0.35, 0.30, 0.95)
  T.text(r.x, r.y, 30, 1, 1, 1, 1, "< BACK")
  return r
end

local scenes = {}
local order = {}
local current = nil
local booted = false

local function switch(key)
  if current and current.leave then current.leave() end
  current = scenes[key]
  if current and current.enter then current.enter() end
end

-- ===================================================================
-- Game 1: Grow the Paddle
-- ===================================================================
local function make_grow()
  local T = tracker()
  local PADDLE_W, AI_H, BALL, MARGIN = 20, 120, 22, 46
  local PADDLE_SPEED, DRAG_SENS = 780, 1.5
  local AI_SPEED, AI_DEADZONE = 430, 10
  local BALL_SPEED, BALL_MAX, SPEEDUP, MAX_ANGLE = 360, 720, 1.03, 0.87
  local MAX_DT, SERVE_DELAY, TRAIL_N = 1 / 30, 0.8, 12
  local H_START, H_MIN, GROW, SHRINK, GOOD_CHANCE = 90, 26, 34, 44, 0.58
  local BASE_L, BASE_R = { 0.55, 0.78, 1.0 }, { 1.0, 0.55, 0.30 }
  local GOOD_C, BAD_C = { 0.30, 0.95, 0.55 }, { 1.0, 0.32, 0.32 }

  local left, right, ball, back
  local ly, ry, lh = 0, 0, H_START
  local bx, by, bvx, bvy, ball_good = 0, 0, 0, 0, true
  local wait, pdir, playing, drag_prev = 0, -1, true, nil
  local l_flash, l_col, r_flash = 0, GOOD_C, 0
  local trail, tcur, built, HH, HW = {}, 0, false, 0, 0

  local function blend(a, b, t)
    return a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t
  end
  local function hud() game.set_text(string.format("%d%%", math.floor(100 * lh / (2 * HH)))) end
  local function set_size()
    game.set_size(left, PADDLE_W, lh)
    local lim = math.max(0, HH - lh * 0.5); ly = clamp(ly, -lim, lim)
  end
  local function win() playing = false; game.set_text("YOU WIN!\nTap to restart")
    game.play_sound("score"); game.haptic("success"); game.shake(0.7); game.log("win") end
  local function lose() playing = false; game.set_text("GAME OVER\nTap to restart")
    game.play_sound("hit"); game.haptic("heavy"); game.shake(0.7); game.log("lose") end
  local function grow() lh = math.min(lh + GROW, 2 * HH); set_size()
    if lh >= 2 * HH then win() else hud() end end
  local function shrink() lh = lh - SHRINK
    if lh <= H_MIN then lh = H_MIN; set_size(); lose() else set_size(); hud() end end
  local function roll() ball_good = math.random() < GOOD_CHANCE
    local c = ball_good and GOOD_C or BAD_C; game.set_color(ball, c[1], c[2], c[3], 1) end
  local function serve(d) bx, by, bvx, bvy = 0, 0, 0, 0; wait, pdir = SERVE_DELAY, d; roll() end
  local function launch() bvx = BALL_SPEED * pdir; bvy = BALL_SPEED * (math.random() * 0.6 - 0.3) end
  local function rebound(py, fx, dir, hh)
    local off = clamp((by - py) / hh, -1, 1)
    local s = math.min(math.sqrt(bvx * bvx + bvy * bvy) * SPEEDUP, BALL_MAX)
    local a = off * MAX_ANGLE; bx = fx; bvx = dir * s * math.cos(a); bvy = s * math.sin(a)
  end
  local function build(hw, hh)
    local seg, gap = 22, 16; local st = seg + gap
    local n = math.floor((2 * hh) / st); local y = -(n - 1) * st * 0.5
    for _ = 1, n do T.spawn(0, y, 4, seg, 1, 1, 1, 0.14); y = y + st end
    for i = 1, TRAIL_N do
      trail[i] = { id = T.spawn(0, 0, BALL * 0.7, BALL * 0.7, 0.75, 0.85, 1.0, 0), a = 0 }
    end
    left = T.spawn(-hw + MARGIN, 0, PADDLE_W, H_START, BASE_L[1], BASE_L[2], BASE_L[3])
    right = T.spawn(hw - MARGIN, 0, PADDLE_W, AI_H, BASE_R[1], BASE_R[2], BASE_R[3])
    ball = T.spawn(0, 0, BALL, BALL, 1, 1, 1)
    back = make_back(T, hw, hh)
    lh, ly, ry, playing = H_START, 0, 0, true
    hud(); serve(-1); built = true
    DEBUG = { game = "grow", ball = ball, left = left, right = right, back = back, get_lh = function() return lh end }
  end
  local function move_player(dt, limit)
    local _, py, down = game.pointer(); local mx = PADDLE_SPEED * dt
    if down and py ~= nil then
      if drag_prev ~= nil then ly = clamp(ly + clamp((py - drag_prev) * DRAG_SENS, -mx, mx), -limit, limit) end
      drag_prev = py
    else
      drag_prev = nil; local vy = 0
      if game.key("up") or game.key("w") then vy = vy + PADDLE_SPEED end
      if game.key("down") or game.key("s") then vy = vy - PADDLE_SPEED end
      ly = clamp(ly + vy * dt, -limit, limit)
    end
  end

  return {
    enter = function() built = false end,
    leave = function() T.clear(); built = false end,
    tap = function(x, y)
      if back and in_rect(back, x, y) then switch("menu"); return end
      if not playing then
        lh, ly, drag_prev = H_START, 0, nil; set_size(); playing = true; serve(-1); hud()
      end
    end,
    update = function(dt, hw, hh)
      HW, HH = hw, hh
      if not built then build(hw, hh) end
      if not playing then return end
      dt = math.min(dt, MAX_DT)
      local lx, rx = -hw + MARGIN, hw - MARGIN
      local plim = math.max(0, hh - lh * 0.5); local ailim = hh - AI_H * 0.5
      move_player(dt, plim)
      if not (wait > 0) and math.abs(by - ry) > AI_DEADZONE then
        ry = clamp(ry + clamp(by - ry, -AI_SPEED * dt, AI_SPEED * dt), -ailim, ailim)
      end
      if wait > 0 then wait = wait - dt; if wait <= 0 then launch() end
      else
        local ox = bx; bx = bx + bvx * dt; by = by + bvy * dt
        local top = hh - BALL * 0.5
        if by > top then by = top; bvy = -math.abs(bvy); game.play_sound("wall"); game.shake(0.04) end
        if by < -top then by = -top; bvy = math.abs(bvy); game.play_sound("wall"); game.shake(0.04) end
        local lhalf = lh * 0.5
        local lf = lx + PADDLE_W * 0.5 + BALL * 0.5
        local rf = rx - PADDLE_W * 0.5 - BALL * 0.5
        if bvx < 0 and ox >= lf and bx <= lf and math.abs(by - ly) <= lhalf + BALL * 0.5 then
          rebound(ly, lf, 1, lhalf)
          if ball_good then l_flash, l_col = 1, GOOD_C; game.play_sound("hit"); game.haptic("success"); game.shake(0.12); grow()
          else l_flash, l_col = 1, BAD_C; game.play_sound("hit"); game.haptic("heavy"); game.shake(0.28); shrink() end
        elseif bvx > 0 and ox <= rf and bx >= rf and math.abs(by - ry) <= AI_H * 0.5 + BALL * 0.5 then
          rebound(ry, rf, -1, AI_H * 0.5); r_flash = 1; game.play_sound("wall"); roll()
        end
        if playing and bx < -hw then
          if ball_good then game.play_sound("hit"); shrink() else game.play_sound("wall") end
          if playing then serve(-1) end
        elseif playing and bx > hw then serve(-1) end
      end
      if not (wait > 0) then
        tcur = (tcur % TRAIL_N) + 1; trail[tcur].a = 0.5; game.move_to(trail[tcur].id, bx, by)
      end
      for i = 1, TRAIL_N do local t = trail[i]
        if t.a > 0.001 then t.a = t.a * 0.86; game.set_color(t.id, 0.75, 0.85, 1.0, t.a) end
      end
      l_flash = math.max(0, l_flash - dt * 4); r_flash = math.max(0, r_flash - dt * 4)
      local lr, lg, lb = blend(BASE_L, l_col, l_flash)
      local rr, rg, rb = blend(BASE_R, { 1, 1, 1 }, r_flash)
      game.set_color(left, lr, lg, lb, 1); game.set_color(right, rr, rg, rb, 1)
      game.move_to(left, lx, ly); game.move_to(right, rx, ry); game.move_to(ball, bx, by)
    end,
  }
end

-- ===================================================================
-- Game 2: Breakout (Bevy example port)
-- ===================================================================
local function make_breakout()
  local T = tracker()
  local PADDLE_W, PADDLE_H, BALL = 130, 18, 16
  local SPEED, MAXV, DRAG_SENS, PADDLE_SPEED = 320, 560, 1.4, 900
  local ROWS, COLS, BRICK_H, GAP, SIDE = 6, 8, 26, 8, 26
  local MAX_DT, START_LIVES = 1 / 30, 3
  local ROW_C = {
    { 0.90, 0.30, 0.30 }, { 0.95, 0.55, 0.25 }, { 0.95, 0.85, 0.30 },
    { 0.35, 0.80, 0.40 }, { 0.35, 0.65, 0.95 }, { 0.65, 0.45, 0.90 },
  }
  local paddle, ball, back
  local px, bx, by, bvx, bvy = 0, 0, 0, 0, 0
  local bricks, alive_count = {}, 0
  local lives, playing, launched, drag_prev = START_LIVES, true, false, nil
  local built, HW, HH, py = false, 0, 0, 0

  local function hud()
    game.set_text(string.format("BRICKS %d   LIVES %d", alive_count, lives))
  end
  local function serve() bx, by = px, py + PADDLE_H * 0.5 + BALL; bvx, bvy = 0, 0; launched = false end
  local function build(hw, hh)
    HW, HH = hw, hh
    py = -hh + 70
    local area = 2 * hw - 2 * SIDE
    local bw = (area - (COLS - 1) * GAP) / COLS
    local top = hh - 130
    bricks, alive_count = {}, 0
    for r = 1, ROWS do
      for c = 1, COLS do
        local x = -hw + SIDE + bw * 0.5 + (c - 1) * (bw + GAP)
        local y = top - (r - 1) * (BRICK_H + GAP)
        local col = ROW_C[r]
        local id = T.spawn(x, y, bw, BRICK_H, col[1], col[2], col[3])
        bricks[#bricks + 1] = { id = id, x = x, y = y, w = bw, h = BRICK_H, alive = true }
        alive_count = alive_count + 1
      end
    end
    paddle = T.spawn(0, py, PADDLE_W, PADDLE_H, 0.85, 0.9, 1.0)
    ball = T.spawn(0, 0, BALL, BALL, 1, 1, 1)
    back = make_back(T, hw, hh)
    px, lives, playing = 0, START_LIVES, true
    serve(); hud(); built = true
    DEBUG = { game = "breakout", ball = ball, paddle = paddle, back = back,
      bricks = function() return alive_count end, alive = function() return playing end }
  end
  local function move_paddle(dt)
    local px0, _, down = game.pointer(); local lim = HW - PADDLE_W * 0.5; local mx = PADDLE_SPEED * dt
    if down and px0 ~= nil then
      if drag_prev ~= nil then px = clamp(px + clamp((px0 - drag_prev) * DRAG_SENS, -mx, mx), -lim, lim) end
      drag_prev = px0
    else
      drag_prev = nil; local vx = 0
      if game.key("left") or game.key("a") then vx = vx - PADDLE_SPEED end
      if game.key("right") or game.key("d") then vx = vx + PADDLE_SPEED end
      px = clamp(px + vx * dt, -lim, lim)
    end
  end

  return {
    enter = function() built = false end,
    leave = function() T.clear(); built = false end,
    tap = function(x, y)
      if back and in_rect(back, x, y) then switch("menu"); return end
      if not playing then T.clear(); build(HW, HH); return end   -- rebuild the round
      if not launched then launched = true
        bvx = SPEED * 0.35 * (math.random() < 0.5 and -1 or 1); bvy = SPEED
      end
    end,
    update = function(dt, hw, hh)
      HW, HH = hw, hh
      if not built then build(hw, hh) end
      if not playing then return end
      dt = math.min(dt, MAX_DT)
      move_paddle(dt)
      if not launched then bx, by = px, py + PADDLE_H * 0.5 + BALL
      else
        bx = bx + bvx * dt; by = by + bvy * dt
        if bx < -hw + BALL * 0.5 then bx = -hw + BALL * 0.5; bvx = math.abs(bvx); game.play_sound("wall") end
        if bx > hw - BALL * 0.5 then bx = hw - BALL * 0.5; bvx = -math.abs(bvx); game.play_sound("wall") end
        if by > hh - BALL * 0.5 then by = hh - BALL * 0.5; bvy = -math.abs(bvy); game.play_sound("wall") end
        -- paddle
        if bvy < 0 and math.abs(bx - px) <= (PADDLE_W + BALL) * 0.5
           and math.abs(by - py) <= (PADDLE_H + BALL) * 0.5 then
          by = py + (PADDLE_H + BALL) * 0.5
          local off = clamp((bx - px) / (PADDLE_W * 0.5), -1, 1)
          local a = off * 1.0
          local s = math.min(math.sqrt(bvx * bvx + bvy * bvy) * 1.02, MAXV)
          bvx = s * math.sin(a); bvy = s * math.cos(a)
          game.play_sound("hit"); game.haptic("light"); game.shake(0.06)
        end
        -- bricks (resolve one per frame)
        for _, b in ipairs(bricks) do
          if b.alive and math.abs(bx - b.x) <= (b.w + BALL) * 0.5
             and math.abs(by - b.y) <= (b.h + BALL) * 0.5 then
            local ox = (b.w + BALL) * 0.5 - math.abs(bx - b.x)
            local oy = (b.h + BALL) * 0.5 - math.abs(by - b.y)
            if ox < oy then bvx = -bvx else bvy = -bvy end
            b.alive = false; game.despawn(b.id); alive_count = alive_count - 1
            game.play_sound("hit"); game.haptic("light"); game.shake(0.08); hud()
            if alive_count <= 0 then
              playing = false; game.set_text("YOU WIN!\nTap to restart")
              game.play_sound("score"); game.haptic("success"); game.shake(0.6); game.log("win")
            end
            break
          end
        end
        if playing and by < -hh - BALL then
          lives = lives - 1; game.haptic("heavy"); game.shake(0.4)
          if lives <= 0 then
            playing = false; game.set_text("GAME OVER\nTap to restart"); game.play_sound("hit"); game.log("lose")
          else game.play_sound("wall"); serve(); hud() end
        end
      end
      game.move_to(paddle, px, py); game.move_to(ball, bx, by)
    end,
  }
end

-- ===================================================================
-- Game 3: Snake
-- ===================================================================
local function make_snake()
  local T = tracker()
  local CELL, TICK = 34, 0.13
  local back, food_id
  local cols, rows, ox, oy = 0, 0, 0, 0
  local snake, dir, ndir, grow_by = {}, { 1, 0 }, { 1, 0 }, 0
  local food = { c = 0, r = 0 }
  local segs = {}
  local acc, playing, drag_prev, built = 0, true, nil, false
  local HW, HH, score = 0, 0, 0

  local function cell_xy(c, r) return ox + (c + 0.5) * CELL, oy + (r + 0.5) * CELL end
  local function occupied(c, r)
    for _, s in ipairs(snake) do if s.c == c and s.r == r then return true end end
    return false
  end
  local function place_food()
    for _ = 1, 200 do
      local c, r = math.random(0, cols - 1), math.random(0, rows - 1)
      if not occupied(c, r) then food.c, food.r = c, r; break end
    end
    game.move_to(food_id, cell_xy(food.c, food.r))
  end
  local function hud() game.set_text(string.format("LEN %d", #snake)) end
  local function render()
    for i, s in ipairs(snake) do
      if not segs[i] then
        segs[i] = T.spawn(0, 0, CELL - 4, CELL - 4, 0.35, 0.85, 0.45)
      end
      local x, y = cell_xy(s.c, s.r)
      game.move_to(segs[i], x, y)
      game.set_color(segs[i], i == 1 and 0.6 or 0.35, i == 1 and 1.0 or 0.85, i == 1 and 0.55 or 0.45, 1)
    end
    for i = #snake + 1, #segs do game.set_color(segs[i], 0, 0, 0, 0) end
  end
  local function die()
    playing = false; game.set_text(string.format("GAME OVER\nLEN %d\nTap to restart", #snake))
    game.play_sound("hit"); game.haptic("heavy"); game.shake(0.5); game.log("lose")
  end
  local function reset()
    snake = {}
    local cc, cr = math.floor(cols / 2), math.floor(rows / 2)
    for i = 0, 2 do snake[i + 1] = { c = cc - i, r = cr } end
    dir, ndir, grow_by, score, acc, playing = { 1, 0 }, { 1, 0 }, 0, 0, 0, true
    place_food(); render(); hud()
  end
  local function build(hw, hh)
    HW, HH = hw, hh
    cols = math.floor(2 * hw / CELL); rows = math.floor(2 * hh / CELL)
    ox = -cols * CELL * 0.5; oy = -rows * CELL * 0.5
    food_id = T.spawn(0, 0, CELL - 6, CELL - 6, 1.0, 0.35, 0.35)
    back = make_back(T, hw, hh)
    reset(); built = true
    DEBUG = { game = "snake", len = function() return #snake end, back = back,
      alive = function() return playing end, head = function() return snake[1] end, food = food }
  end
  local function set_dir(dx, dy)
    if dx ~= 0 and dir[1] == 0 then ndir = { dx, 0 }
    elseif dy ~= 0 and dir[2] == 0 then ndir = { 0, dy } end
  end
  local function step()
    dir = ndir
    local h = snake[1]
    local nc, nr = h.c + dir[1], h.r + dir[2]
    if nc < 0 or nc >= cols or nr < 0 or nr >= rows then die(); return end
    for i = 1, #snake - 1 do if snake[i].c == nc and snake[i].r == nr then die(); return end end
    table.insert(snake, 1, { c = nc, r = nr })
    if nc == food.c and nr == food.r then
      score = score + 1; game.play_sound("hit"); game.haptic("light"); place_food()
    else
      table.remove(snake)
    end
    render(); hud()
  end

  return {
    enter = function() built = false end,
    leave = function() T.clear(); segs = {}; built = false end,
    tap = function(x, y)
      if back and in_rect(back, x, y) then switch("menu"); return end
      if not playing then reset() end
    end,
    update = function(dt, hw, hh)
      if not built then build(hw, hh) end
      if not playing then return end
      -- Direction: drag-swipe (dominant axis) or arrow keys.
      local dpx, dpy, down = game.pointer()
      if down and dpy ~= nil then
        if drag_prev then
          local ddx, ddy = (dpx or drag_prev.x) - drag_prev.x, dpy - drag_prev.y
          if math.abs(ddx) > 12 or math.abs(ddy) > 12 then
            if math.abs(ddx) > math.abs(ddy) then set_dir(sign(ddx), 0) else set_dir(0, sign(ddy)) end
            drag_prev = { x = dpx or drag_prev.x, y = dpy }
          end
        else drag_prev = { x = dpx or 0, y = dpy } end
      else drag_prev = nil end
      if game.key("left") or game.key("a") then set_dir(-1, 0) end
      if game.key("right") or game.key("d") then set_dir(1, 0) end
      if game.key("up") or game.key("w") then set_dir(0, 1) end
      if game.key("down") or game.key("s") then set_dir(0, -1) end
      acc = acc + math.min(dt, 0.1)
      while playing and acc >= TICK do acc = acc - TICK; step() end
    end,
  }
end

-- ===================================================================
-- Menu
-- ===================================================================
local function make_menu()
  local T = tracker()
  local tiles, built = {}, false
  return {
    enter = function() built = false; game.set_text("") end,
    leave = function() T.clear(); tiles = {} end,
    update = function(_, hw, hh)
      if built then return end
      game.set_text("")
      T.text(0, hh - 96, 46, 1, 1, 1, 1, "MINI GAMES")
      T.text(0, hh - 148, 22, 0.7, 0.8, 1.0, 1, "Select a game")
      local n = #order
      local tw = math.min(2 * hw - 80, 440)
      local th, gap = 96, 26
      local y = (n * th + (n - 1) * gap) * 0.5 - th * 0.5
      tiles = {}
      for _, item in ipairs(order) do
        local c = item.color
        T.spawn(0, y, tw, th, c[1], c[2], c[3], 1)
        T.text(0, y, 32, 1, 1, 1, 1, item.label)
        tiles[#tiles + 1] = { x = 0, y = y, w = tw, h = th, key = item.key }
        y = y - (th + gap)
      end
      built = true
    end,
    tap = function(x, y)
      for _, t in ipairs(tiles) do
        if in_rect(t, x, y) then
          game.play_sound("hit"); game.haptic("light"); switch(t.key); return
        end
      end
    end,
  }
end

-- ===================================================================
-- Router lifecycle
-- ===================================================================
function on_start()
  game.log("Mini-game collection — started")
  game.play_music("music")
  scenes.menu = make_menu()
  scenes.grow = make_grow()
  scenes.breakout = make_breakout()
  scenes.snake = make_snake()
  order = {
    { key = "grow", label = "1. Grow Paddle", color = { 0.30, 0.62, 1.0 } },
    { key = "breakout", label = "2. Breakout", color = { 1.0, 0.55, 0.25 } },
    { key = "snake", label = "3. Snake", color = { 0.35, 0.82, 0.45 } },
  }
  booted = false
end

function on_update(dt)
  local hw, hh = game.bounds()
  if hw <= 0 then return end
  if not booted then switch("menu"); booted = true end
  if current and current.update then current.update(dt, hw, hh) end
end

function on_tap(x, y)
  if current and current.tap then current.tap(x, y) end
end
