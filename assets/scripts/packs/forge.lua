-- forge.lua — "STARFORGE" (M0 graybox): the math-driven hybrid-casual candidate.
--
-- Math core, two coupled formulas (docs/hybrid-casual-math-game-plan.md §2.3):
--   gravity   a = GM / r^2         (every star falls toward the central well)
--   fusion    a + a -> 2a          (equal-level stars merge, mass doubles)
-- Coupling: GM grows with the total mass on the field, so every fusion
-- *tightens* every orbit — the difficulty curve IS the formula.
--
-- One finger: tap to inject a star at the tap point; it enters a circular
-- orbit automatically (v = sqrt(GM/r), tangential). Equal levels fuse on
-- contact (momentum conserved, 2^n score, chain combo). A star that falls
-- into the event horizon feeds the well (GM up, one core lost); a star
-- flung off-screen is gone. Lose 3 cores and the run ends.
--
-- Graybox: existing "orb" texture tinted per level. No new assets.

function make_forge()
  local K = GAME_KIT
  local clamp, inr = K.clamp, K.in_rect
  local T = K.tracker()

  -- tuning ------------------------------------------------------------
  local MAX_LEVEL   = 10
  local GM0         = 1.6e6   -- base gravity parameter (px^3/s^2-ish)
  local MASS_SCALE  = 220     -- total mass that doubles GM
  local CORE_R      = 30      -- event-horizon radius
  local VMAX        = 620     -- hard speed cap (invariant-tested)
  local MAX_BODIES  = 48
  local SPAWN_CD    = 0.22    -- seconds between injections
  local COMBO_WIN   = 1.4     -- chain window (s)
  local DT_CAP      = 1 / 30
  local MIN_SPAWN_R = CORE_R + 46
  local LIVES0      = 3

  local function radius_of(level) return 9 + level * 6 end
  local function mass_of(level) return 2 ^ (level - 1) end
  -- 10-step cold->hot colour ramp (tints the grayscale orb texture)
  local RAMP = {
    { 0.55, 0.75, 1.00 }, { 0.45, 0.95, 0.85 }, { 0.45, 1.00, 0.55 },
    { 0.85, 1.00, 0.40 }, { 1.00, 0.90, 0.30 }, { 1.00, 0.70, 0.25 },
    { 1.00, 0.50, 0.30 }, { 1.00, 0.35, 0.45 }, { 0.95, 0.35, 0.80 },
    { 1.00, 1.00, 1.00 },
  }

  -- state ---------------------------------------------------------------
  local back, built, playing = nil, false, true
  local bodies = {}          -- { id, x, y, vx, vy, level, r, m }
  local score, lives, best_level = 0, LIVES0, 1
  local total_mass = 0
  local combo_n, combo_t = 0, 0
  local next_level = 1
  local spawn_cd = 0
  local core_id = nil
  local hw0, hh0 = 0, 0
  local rmax = 900

  local function gm() return GM0 * (1 + total_mass / MASS_SCALE) end

  local function hud()
    game.set_text(string.format("SCORE %d   NEXT L%d   CORES %d", score, next_level, lives))
  end

  local function tint(id, level)
    local c = RAMP[clamp(level, 1, MAX_LEVEL)]
    game.set_color(id, c[1], c[2], c[3], 1)
  end

  local function despawn_body(i)
    game.despawn(bodies[i].id)
    table.remove(bodies, i)
  end

  local function clear_bodies()
    for _, b in ipairs(bodies) do game.despawn(b.id) end
    bodies = {}
  end

  -- Inject a star at (x,y) on a circular orbit: v = sqrt(GM/r) tangential.
  local function inject(x, y, level)
    if #bodies >= MAX_BODIES then return false end
    local d = math.sqrt(x * x + y * y)
    if d < MIN_SPAWN_R then return false end
    local r = radius_of(level)
    local v = math.sqrt(gm() / d)
    if v > VMAX then v = VMAX end
    -- counter-clockwise tangent
    local tx, ty = -y / d, x / d
    local id = game.spawn_sprite(x, y, r * 2, r * 2, "orb")
    tint(id, level)
    bodies[#bodies + 1] = {
      id = id, x = x, y = y, vx = tx * v, vy = ty * v,
      level = level, r = r, m = mass_of(level),
    }
    total_mass = total_mass + mass_of(level)
    return true
  end

  local function game_over()
    playing = false
    game.set_text(string.format("SUPERNOVA COLLAPSE\nSCORE %d   BEST STAR L%d\nTap to forge again", score, best_level))
    game.log("forge_over")
    game.play_sound("hit"); game.haptic("heavy"); game.shake(0.6); game.zoom(0.8)
    game.track("forge_over", score)
  end

  local function fuse(i, j)
    local a, b = bodies[i], bodies[j]
    local lvl = a.level + 1
    local m = a.m + b.m
    -- momentum-conserving merge at the centre of mass
    local x = (a.x * a.m + b.x * b.m) / m
    local y = (a.y * a.m + b.y * b.m) / m
    local vx = (a.vx * a.m + b.vx * b.m) / m
    local vy = (a.vy * a.m + b.vy * b.m) / m
    -- combo chain
    combo_n = (combo_t > 0) and (combo_n + 1) or 1
    combo_t = COMBO_WIN
    score = score + (2 ^ lvl) * combo_n
    if lvl > best_level then best_level = lvl end
    game.emit("spark", x, y)
    game.play_sound("score")
    game.haptic(combo_n >= 3 and "heavy" or "success")
    game.shake(math.min(0.12 + 0.05 * lvl, 0.5))
    if lvl > MAX_LEVEL then
      -- L10 + L10: supernova — both stars burn out, big payout, field relaxes
      total_mass = total_mass - m
      game.despawn(a.id); game.despawn(b.id)
      table.remove(bodies, j); table.remove(bodies, i)
      score = score + 2048
      game.zoom(1.0); game.shake(0.8); game.emit("confetti", x, y)
      game.log("supernova")
      return
    end
    -- reuse a's sprite as the fused star (mass conserved: m = a.m + b.m)
    a.x, a.y, a.vx, a.vy = x, y, vx, vy
    a.level, a.m, a.r = lvl, m, radius_of(lvl)
    game.set_size(a.id, a.r * 2, a.r * 2)
    game.move_to(a.id, x, y)
    tint(a.id, lvl)
    game.despawn(b.id)
    table.remove(bodies, j)
  end

  -- elastic-ish bounce for unequal levels (impulse along the contact normal)
  local function bounce(a, b, nx, ny, overlap)
    local tm = a.m + b.m
    a.x = a.x - nx * overlap * (b.m / tm)
    a.y = a.y - ny * overlap * (b.m / tm)
    b.x = b.x + nx * overlap * (a.m / tm)
    b.y = b.y + ny * overlap * (a.m / tm)
    local rvx, rvy = b.vx - a.vx, b.vy - a.vy
    local rel = rvx * nx + rvy * ny
    if rel < 0 then
      local e = 0.86
      local imp = -(1 + e) * rel / (1 / a.m + 1 / b.m)
      a.vx = a.vx - imp * nx / a.m
      a.vy = a.vy - imp * ny / a.m
      b.vx = b.vx + imp * nx / b.m
      b.vy = b.vy + imp * ny / b.m
      game.play_sound("wall")
    end
  end

  local function build(hw, hh)
    hw0, hh0 = hw, hh
    rmax = math.sqrt(hw * hw + hh * hh) + 80
    core_id = T.sprite(0, 0, CORE_R * 2, CORE_R * 2, "orb")
    game.set_color(core_id, 0.08, 0.05, 0.16, 1)
    back = K.make_back(T, hw, hh)
    clear_bodies()
    score, lives, best_level = 0, LIVES0, 1
    total_mass, combo_n, combo_t = 0, 0, 0
    next_level = math.random(1, 3)
    spawn_cd, playing = 0, true
    hud()
    game.set_bg_theme(2)
    built = true
    DEBUG = {
      game = "forge", back = back,
      score = function() return score end,
      lives = function() return lives end,
      alive = function() return playing end,
      body_count = function() return #bodies end,
      total_mass = function() return total_mass end,
      gm = function() return gm() end,
      bodies = function()
        local out = {}
        for k, b in ipairs(bodies) do
          out[k] = { x = b.x, y = b.y, vx = b.vx, vy = b.vy, level = b.level, r = b.r, m = b.m }
        end
        return out
      end,
    }
  end

  local function restart()
    clear_bodies(); T.clear(); built = false
    build(game.bounds())
  end

  return {
    enter = function() built = false end,
    leave = function() clear_bodies(); T.clear(); built = false end,

    tap = function(x, y)
      if back and inr(back, x, y) then K.switch("menu"); return end
      if not playing then restart(); return end
      if spawn_cd > 0 then return end
      if inject(x, y, next_level) then
        spawn_cd = SPAWN_CD
        next_level = math.random(1, 3)
        game.play_sound("hit"); game.haptic("light")
        hud()
      end
    end,

    update = function(dt, hw, hh)
      if not built then build(hw, hh) end
      if dt > DT_CAP then dt = DT_CAP end -- a hitch must never teleport an orbit
      if not playing then return end

      spawn_cd = math.max(0, spawn_cd - dt)
      if combo_t > 0 then combo_t = combo_t - dt; if combo_t <= 0 then combo_n = 0 end end

      -- gravity + integration (semi-implicit Euler) + speed cap
      local GM = gm()
      for _, b in ipairs(bodies) do
        local d2 = b.x * b.x + b.y * b.y
        local d = math.sqrt(d2)
        if d > 1 then
          local acc = GM / d2
          b.vx = b.vx - (b.x / d) * acc * dt
          b.vy = b.vy - (b.y / d) * acc * dt
        end
        local sp2 = b.vx * b.vx + b.vy * b.vy
        if sp2 > VMAX * VMAX then
          local s = VMAX / math.sqrt(sp2)
          b.vx, b.vy = b.vx * s, b.vy * s
        end
        b.x = b.x + b.vx * dt
        b.y = b.y + b.vy * dt
      end

      -- horizon + escape (iterate backwards: we remove while walking)
      for i = #bodies, 1, -1 do
        local b = bodies[i]
        local d = math.sqrt(b.x * b.x + b.y * b.y)
        if d < CORE_R + b.r * 0.35 then
          -- the well eats it: field gets HEAVIER (failure feeds the beast)
          lives = lives - 1
          total_mass = total_mass + b.m   -- mass moves into the well, GM keeps it
          game.emit("dust", b.x, b.y)
          game.play_sound("hit"); game.haptic("heavy"); game.shake(0.4); game.zoom(0.5)
          despawn_body(i)
          hud()
          if lives <= 0 then game_over(); return end
        elseif d > rmax then
          total_mass = total_mass - b.m   -- escaped: mass leaves the system
          despawn_body(i)
          game.play_sound("wall"); game.haptic("medium")
        end
      end

      -- pairwise contact: equal levels fuse, unequal bounce
      local i = 1
      while i <= #bodies do
        local a = bodies[i]
        local j = i + 1
        local fused = false
        while j <= #bodies do
          local c = bodies[j]
          local dx, dy = c.x - a.x, c.y - a.y
          local rr = a.r + c.r
          local d2 = dx * dx + dy * dy
          if d2 < rr * rr then
            local d = math.sqrt(d2)
            local nx, ny
            if d > 0.001 then nx, ny = dx / d, dy / d else nx, ny = 1, 0; d = 0.001 end
            if a.level == c.level then
              fuse(i, j)
              hud()
              fused = true
              break -- a changed (or is gone); restart its pair scan
            else
              bounce(a, c, nx, ny, rr - d)
            end
          end
          j = j + 1
        end
        if not fused then i = i + 1 end
      end

      -- present
      for _, b in ipairs(bodies) do game.move_to(b.id, b.x, b.y) end
    end,
  }
end

PACKS = PACKS or {}
PACKS["forge"] = { slot = 23, key = "forge", label = "Starforge", short = "Forge",
  icon = "orb", color = { 1.0, 0.70, 0.25 }, tier = "ai", make = make_forge }
