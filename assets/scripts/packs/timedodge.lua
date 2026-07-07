-- timedodge.lua — "TIME DODGE": a SUPERHOT-style hyper-casual dodger.
-- Time moves when YOU move: the world (red bullets converging on you) advances
-- at a timescale driven by your own movement speed, while your orb always moves
-- in real time. Hold still to freeze the world and plan; dash to slip between
-- shots — but only flowing time scores. Survive as long as you can.
-- Registers the global factory make_timedodge (main.lua builds the menu from PACKS).
-- Talks to the host ONLY through the `game` bridge + shared GAME_KIT helpers.

function make_timedodge()
  local K = GAME_KIT
  local clamp = K.clamp
  local T = K.tracker()

  local PLAYER, BULLET = 26, 18
  local EASE, KEY_SPEED = 14, 460        -- pointer-follow gain / keyboard px/s
  local REF_SPEED, TS_MIN = 300, 0.06    -- player px/s that means "full time flow"
  local TS_SMOOTH = 12                   -- timescale attack/release rate
  local SPEED0, SPEED_PER_S, SPEED_MAX = 240, 6, 500
  local SPAWN0, SPAWN_MIN, SPAWN_PER_S = 0.55, 0.28, 0.012
  local MAX_BULLETS, OFF = 40, 70        -- live cap / off-screen despawn margin
  local NEAR, HIT_R = 44, 19             -- near-miss ring / kill distance
  local MAX_DT, TRAIL_N = 1 / 30, 10
  local FROZEN_C, FLOW_C = { 0.55, 0.85, 1.0 }, { 1.0, 0.30, 0.25 }

  local back, player, built, playing = nil, nil, false, true
  local px, py, ts, score, best = 0, 0, TS_MIN, 0, 0
  local bullets, spawn_timer, next_mark = {}, 0, 10
  local trail, tcur = {}, 0
  local HW, HH = 0, 0

  local function hud()
    game.set_text(string.format("TIME %.1fs%s", score, ts < 0.15 and "  FROZEN" or ""))
  end
  local function clear_bullets()
    for _, b in ipairs(bullets) do game.despawn(b.id) end
    bullets = {}
  end
  local function bullet_speed() return math.min(SPEED0 + score * SPEED_PER_S, SPEED_MAX) end
  local function spawn_every() return math.max(SPAWN_MIN, SPAWN0 - score * SPAWN_PER_S) end

  -- Spawn a bullet on a random edge, aimed at the player (with a little jitter),
  -- so standing frozen forever is safe but scores nothing — you must move.
  local function spawn_bullet()
    if #bullets >= MAX_BULLETS then return end
    local side, x, y = math.random(4), 0, 0
    if side == 1 then x, y = -HW - BULLET, (math.random() * 2 - 1) * HH
    elseif side == 2 then x, y = HW + BULLET, (math.random() * 2 - 1) * HH
    elseif side == 3 then x, y = (math.random() * 2 - 1) * HW, HH + BULLET
    else x, y = (math.random() * 2 - 1) * HW, -HH - BULLET end
    local a = math.atan(py - y, px - x) + (math.random() * 0.5 - 0.25)
    local s = bullet_speed()
    local id = game.spawn_sprite(x, y, BULLET, BULLET, "orb")
    bullets[#bullets + 1] = { id = id, x = x, y = y, vx = s * math.cos(a), vy = s * math.sin(a), near = false }
  end

  local function die()
    playing = false
    if score > best then best = score; game.save("timedodge_best", best) end
    game.set_text(string.format("GAME OVER\nTIME %.1fs   BEST %.1fs\nTap to restart", score, best))
    game.play_sound("hit"); game.haptic("heavy"); game.shake(0.7); game.zoom(0.8)
    game.log("lose")
  end

  local function build(hw, hh)
    HW, HH = hw, hh
    best = tonumber(game.load("timedodge_best")) or 0
    px, py, ts, score = 0, 0, TS_MIN, 0
    spawn_timer, next_mark, playing = 0, 10, true
    for i = 1, TRAIL_N do
      trail[i] = { id = T.spawn(0, 0, PLAYER * 0.6, PLAYER * 0.6, 0.7, 0.9, 1.0, 0), a = 0 }
    end
    player = T.sprite(px, py, PLAYER, PLAYER, "orb")
    back = K.make_back(T, hw, hh)
    hud()
    built = true
    DEBUG = {
      game = "timedodge", back = back, player = player,
      timescale = function() return ts end,
      score = function() return score end,
      alive = function() return playing end,
      bullet_count = function() return #bullets end,
      bullet_ids = function() local ids = {}; for i, b in ipairs(bullets) do ids[i] = b.id end; return ids end,
    }
  end

  local function restart()
    clear_bullets(); T.clear(); built = false
    build(game.bounds())
  end

  return {
    enter = function() built = false end,
    leave = function() clear_bullets(); T.clear(); built = false end,
    tap = function(x, y)
      if back and K.in_rect(back, x, y) then K.switch("menu"); return end
      if not playing then restart(); return end
    end,
    update = function(dt, hw, hh)
      if not built then build(hw, hh) end
      HW, HH = hw, hh
      if dt > MAX_DT then dt = MAX_DT end   -- a hitch never teleports anything
      if not playing then return end

      -- Player moves in REAL time: ease toward the held pointer, or WASD/arrows.
      local ox, oy = px, py
      local ptx, pty, down = game.pointer()
      if down and ptx ~= nil then
        local k = math.min(1, dt * EASE)
        px, py = px + (ptx - px) * k, py + (pty - py) * k
      end
      local dx, dy = 0, 0
      if game.key("left") or game.key("a") then dx = dx - 1 end
      if game.key("right") or game.key("d") then dx = dx + 1 end
      if game.key("up") or game.key("w") then dy = dy + 1 end
      if game.key("down") or game.key("s") then dy = dy - 1 end
      if dx ~= 0 or dy ~= 0 then px, py = px + dx * KEY_SPEED * dt, py + dy * KEY_SPEED * dt end
      local lim_x, lim_y = hw - PLAYER * 0.5, hh - PLAYER * 0.5
      px, py = clamp(px, -lim_x, lim_x), clamp(py, -lim_y, lim_y)

      -- THE mechanic: timescale follows the player's own speed.
      local pspeed = math.sqrt((px - ox) ^ 2 + (py - oy) ^ 2) / dt
      local target = clamp(pspeed / REF_SPEED, TS_MIN, 1)
      ts = ts + (target - ts) * math.min(1, dt * TS_SMOOTH)
      local wdt = dt * ts                    -- world time: bullets, spawns, score

      score = score + wdt
      if score >= next_mark then             -- 10s survival milestones
        next_mark = next_mark + 10
        game.play_sound("score"); game.haptic("success"); game.shake(0.35)
      end

      spawn_timer = spawn_timer + wdt
      if spawn_timer >= spawn_every() then spawn_timer = 0; spawn_bullet() end

      -- Advance bullets in WORLD time; telegraph the flow with their colour.
      local cr = FROZEN_C[1] + (FLOW_C[1] - FROZEN_C[1]) * ts
      local cg = FROZEN_C[2] + (FLOW_C[2] - FROZEN_C[2]) * ts
      local cb = FROZEN_C[3] + (FLOW_C[3] - FROZEN_C[3]) * ts
      local kept = {}
      for _, b in ipairs(bullets) do
        b.x, b.y = b.x + b.vx * wdt, b.y + b.vy * wdt
        local d = math.sqrt((b.x - px) ^ 2 + (b.y - py) ^ 2)
        if d < HIT_R then
          game.despawn(b.id)
          for _, g in ipairs(kept) do game.despawn(g.id) end
          bullets = {}
          die()
          return
        end
        if d < NEAR and not b.near then      -- near miss: a graze of juice
          b.near = true
          game.play_sound("wall"); game.haptic("light"); game.shake(0.06); game.zoom(0.25)
        end
        if math.abs(b.x) > hw + OFF or math.abs(b.y) > hh + OFF then
          game.despawn(b.id)
        else
          game.move_to(b.id, b.x, b.y)
          game.set_color(b.id, cr, cg, cb, 1)
          kept[#kept + 1] = b
        end
      end
      bullets = kept

      -- Player trail (only while dashing) + frozen/flow tint on the orb itself.
      if pspeed > REF_SPEED * 0.5 then
        tcur = (tcur % TRAIL_N) + 1
        trail[tcur].a = 0.4
        game.move_to(trail[tcur].id, px, py)
      end
      for i = 1, TRAIL_N do
        local t = trail[i]
        if t.a > 0.004 then t.a = t.a * 0.85; game.set_color(t.id, 0.7, 0.9, 1.0, t.a) end
      end
      local pc = 1 - ts
      game.set_color(player, 1 - pc * 0.3, 1, 1, 1)  -- white -> icy when frozen
      game.move_to(player, px, py)
      hud()
    end,
  }
end

-- Self-register this game pack (see main.lua: the menu builds from PACKS).
PACKS = PACKS or {}
PACKS["timedodge"] = { slot = 10, key = "timedodge", label = "Time Dodge", short = "Dodge",
  icon = "icon_clock", color = { 0.30, 0.70, 0.85 }, tier = "curated", make = make_timedodge }
