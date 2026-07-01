-- roguelike.lua — a small arena survivors-like ("roguelike").
--
-- Loaded from its OWN file (see EXTRA_SCRIPTS in src/script.rs). It runs before
-- main.lua and registers the global factory `make_roguelike`, which main.lua's
-- on_start adds to the menu. It uses GAME_KIT (shared helpers exposed by
-- main.lua) plus the usual `game` bridge API.
--
-- Loop: move (drag / WASD) to dodge enemies that chase you; you auto-fire at the
-- nearest one. Kills drop XP gems; collect them to level up and pick 1 of 3
-- random upgrades (the roguelike build variety). Enemies get faster/tougher over
-- time. Lose all HP -> game over. Tap to restart; "< BACK" returns to the menu.

function make_roguelike()
  local K = GAME_KIT
  local clamp, inr = K.clamp, K.in_rect

  local PSIZE, ESIZE, BSIZE, GSIZE = 26, 24, 12, 16
  local BASE_MOVE, DRAG_SENS, BULLET_SPEED, BASE_ESPEED = 300, 2.6, 440, 62
  local MAX_ENEMIES, MAX_DT, CONTACT_CD = 60, 1 / 30, 0.7

  local T = K.tracker()
  local player, back
  local px, py, hp, max_hp = 0, 0, 5, 5
  local move_speed, damage, fire_int, nbullets = BASE_MOVE, 1, 0.6, 1
  local enemies, bullets, gems = {}, {}, {}
  local fire_t, spawn_t, elapsed, hurt_cd = 0, 0, 0, 0
  local xp, xp_need, level, kills = 0, 4, 1, 0
  local playing, leveling, built = true, false, false
  local choices, choice_ids, drag_prev = {}, {}, nil
  local HW, HH = 0, 0

  local UPGRADES = {
    { label = "+1 Damage", apply = function() damage = damage + 1 end },
    { label = "+Fire Rate", apply = function() fire_int = math.max(0.09, fire_int * 0.82) end },
    { label = "+Move Speed", apply = function() move_speed = move_speed + 55 end },
    { label = "Heal +2", apply = function() hp = math.min(max_hp, hp + 2) end },
    { label = "+2 Max HP", apply = function() max_hp = max_hp + 2; hp = hp + 2 end },
    { label = "+1 Bullet", apply = function() nbullets = nbullets + 1 end },
  }

  local function hud()
    game.set_text(string.format("HP %d/%d   LV %d   KILL %d", hp, max_hp, level, kills))
  end
  local function despawn_all(list) for _, e in ipairs(list) do game.despawn(e.id) end end
  local function clear_choices() for _, id in ipairs(choice_ids) do game.despawn(id) end; choice_ids = {} end
  local function cleanup()
    despawn_all(enemies); despawn_all(bullets); despawn_all(gems); clear_choices()
    enemies, bullets, gems = {}, {}, {}
    T.clear()
  end

  local function game_over()
    playing = false
    game.set_text(string.format("GAME OVER\nLV %d   KILL %d\nTap to restart", level, kills))
    game.play_sound("hit"); game.haptic("heavy"); game.shake(0.6); game.log("lose")
  end

  local function start_levelup()
    leveling = true
    local pool = {}
    for i = 1, #UPGRADES do pool[i] = UPGRADES[i] end
    choices = {}
    for i = 1, 3 do choices[i] = table.remove(pool, math.random(1, #pool)) end
    clear_choices()
    local tw, th = math.min(2 * HW - 80, 420), 84
    game.set_text(string.format("LEVEL UP  (LV %d) — choose:", level))
    for i, up in ipairs(choices) do
      local ty = (th + 20) - (i - 1) * (th + 18)
      choice_ids[#choice_ids + 1] = game.spawn(0, ty, tw, th, 0.28, 0.30, 0.42, 0.96)
      choice_ids[#choice_ids + 1] = game.spawn_text(0, ty, 30, 1, 1, 1, 1, up.label)
      up.rect = { x = 0, y = ty, w = tw, h = th }
    end
    game.play_sound("score"); game.haptic("success")
  end

  local function gain_xp()
    xp = xp + 1
    if xp >= xp_need then
      xp = 0; level = level + 1; xp_need = xp_need + 3; start_levelup()
    end
  end

  local function spawn_enemy()
    if #enemies >= MAX_ENEMIES then return end
    local ex, ey, edge = 0, 0, math.random(1, 4)
    if edge == 1 then ex, ey = -HW - 20, (math.random() * 2 - 1) * HH
    elseif edge == 2 then ex, ey = HW + 20, (math.random() * 2 - 1) * HH
    elseif edge == 3 then ex, ey = (math.random() * 2 - 1) * HW, HH + 20
    else ex, ey = (math.random() * 2 - 1) * HW, -HH - 20 end
    local id = game.spawn_sprite(ex, ey, ESIZE, ESIZE, "enemy")
    enemies[#enemies + 1] = { id = id, x = ex, y = ey, hp = 1 + math.floor(elapsed / 25) }
  end

  local function nearest_enemy()
    local best, bd
    for _, e in ipairs(enemies) do
      local d = (e.x - px) ^ 2 + (e.y - py) ^ 2
      if not bd or d < bd then bd, best = d, e end
    end
    return best
  end

  local function fire()
    local tgt = nearest_enemy()
    if not tgt then return end
    local ang = math.atan(tgt.y - py, tgt.x - px)
    for i = 1, nbullets do
      local a = ang + (i - (nbullets + 1) / 2) * 0.18
      local id = game.spawn_sprite(px, py, BSIZE, BSIZE, "orb")
      game.set_color(id, 1.0, 0.9, 0.3, 1)
      bullets[#bullets + 1] = {
        id = id, x = px, y = py,
        vx = math.cos(a) * BULLET_SPEED, vy = math.sin(a) * BULLET_SPEED, life = 1.6,
      }
    end
    game.play_sound("wall")
  end

  local function build(hw, hh)
    HW, HH = hw, hh
    enemies, bullets, gems = {}, {}, {}
    px, py, hp, max_hp = 0, 0, 5, 5
    move_speed, damage, fire_int, nbullets = BASE_MOVE, 1, 0.6, 1
    fire_t, spawn_t, elapsed, hurt_cd = 0, 0, 0, 0
    xp, xp_need, level, kills = 0, 4, 1, 0
    playing, leveling = true, false
    player = T.sprite(0, 0, PSIZE, PSIZE, "hero")
    back = K.make_back(T, hw, hh)
    hud(); built = true
    DEBUG = {
      game = "roguelike", back = back, player = player,
      hp = function() return hp end, level = function() return level end,
      kills = function() return kills end, enemies = function() return #enemies end,
      alive = function() return playing end, leveling = function() return leveling end,
      choices = function() return choices end,
    }
  end

  local function move_player(dt)
    local dpx, dpy, down = game.pointer()
    local mx = move_speed * dt
    local lx, ly = HW - PSIZE * 0.5, HH - PSIZE * 0.5
    if down and dpx ~= nil and dpy ~= nil then
      if drag_prev then
        px = clamp(px + clamp((dpx - drag_prev.x) * DRAG_SENS, -mx, mx), -lx, lx)
        py = clamp(py + clamp((dpy - drag_prev.y) * DRAG_SENS, -mx, mx), -ly, ly)
      end
      drag_prev = { x = dpx, y = dpy }
    else
      drag_prev = nil
      local vx, vy = 0, 0
      if game.key("left") or game.key("a") then vx = vx - move_speed end
      if game.key("right") or game.key("d") then vx = vx + move_speed end
      if game.key("up") or game.key("w") then vy = vy + move_speed end
      if game.key("down") or game.key("s") then vy = vy - move_speed end
      px = clamp(px + vx * dt, -lx, lx); py = clamp(py + vy * dt, -ly, ly)
    end
  end

  return {
    enter = function() built = false end,
    leave = function() cleanup(); built = false end,
    tap = function(x, y)
      if back and inr(back, x, y) then K.switch("menu"); return end
      if leveling then
        for _, up in ipairs(choices) do
          if up.rect and inr(up.rect, x, y) then
            up.apply(); clear_choices(); leveling = false; hud(); return
          end
        end
        return
      end
      if not playing then cleanup(); build(HW, HH) end
    end,
    update = function(dt, hw, hh)
      HW, HH = hw, hh
      if not built then build(hw, hh) end
      if not playing or leveling then return end
      dt = math.min(dt, MAX_DT)
      elapsed = elapsed + dt
      hurt_cd = math.max(0, hurt_cd - dt)
      move_player(dt)

      local spawn_int = math.max(0.35, 1.3 - elapsed * 0.02)
      spawn_t = spawn_t + dt
      while spawn_t >= spawn_int do spawn_t = spawn_t - spawn_int; spawn_enemy() end

      local espeed = BASE_ESPEED + elapsed * 1.4
      for _, e in ipairs(enemies) do
        local dx, dy = px - e.x, py - e.y
        local d = math.sqrt(dx * dx + dy * dy) + 1e-6
        e.x = e.x + dx / d * espeed * dt; e.y = e.y + dy / d * espeed * dt
        game.move_to(e.id, e.x, e.y)
        if hurt_cd <= 0 and d < (PSIZE + ESIZE) * 0.5 then
          hp = hp - 1; hurt_cd = CONTACT_CD
          game.play_sound("hit"); game.haptic("heavy"); game.shake(0.2)
          if hp <= 0 then game_over(); return end
          hud()
        end
      end

      fire_t = fire_t + dt
      while fire_t >= fire_int do fire_t = fire_t - fire_int; fire() end

      for bi = #bullets, 1, -1 do
        local b = bullets[bi]
        b.x = b.x + b.vx * dt; b.y = b.y + b.vy * dt; b.life = b.life - dt
        local hit = false
        for ei = #enemies, 1, -1 do
          local e = enemies[ei]
          if math.abs(b.x - e.x) < (ESIZE + BSIZE) * 0.5 and math.abs(b.y - e.y) < (ESIZE + BSIZE) * 0.5 then
            e.hp = e.hp - damage; hit = true
            if e.hp <= 0 then
              gems[#gems + 1] = { id = game.spawn_sprite(e.x, e.y, GSIZE, GSIZE, "gem"), x = e.x, y = e.y }
              game.despawn(e.id); table.remove(enemies, ei)
              kills = kills + 1; game.shake(0.05); hud()
            end
            break
          end
        end
        if hit or b.life <= 0 or b.x < -HW - 30 or b.x > HW + 30 or b.y < -HH - 30 or b.y > HH + 30 then
          game.despawn(b.id); table.remove(bullets, bi)
        else
          game.move_to(b.id, b.x, b.y)
        end
      end

      for gi = #gems, 1, -1 do
        local g = gems[gi]
        local dx, dy = px - g.x, py - g.y
        local d = math.sqrt(dx * dx + dy * dy) + 1e-6
        if d < 90 then g.x = g.x + dx / d * 220 * dt; g.y = g.y + dy / d * 220 * dt end
        if d < (PSIZE + GSIZE) * 0.5 then
          game.despawn(g.id); table.remove(gems, gi); gain_xp()
          if leveling then game.move_to(player, px, py); return end
        else
          game.move_to(g.id, g.x, g.y)
        end
      end

      local flash = hurt_cd > 0 and (0.5 + 0.5 * math.cos(hurt_cd * 30)) or 0
      game.set_color(player, 1, 1 - flash * 0.6, 1 - flash * 0.6, 1)
      game.move_to(player, px, py)
    end,
  }
end
