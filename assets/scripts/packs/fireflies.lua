-- fireflies.lua — "FIREFLIES" (M0 graybox): the boids control-group candidate.
--
-- Math core (docs/hybrid-casual-math-game-plan.md §2.3): Craig Reynolds' three
-- rules — separation / alignment / cohesion — plus one light-attraction term:
-- while the finger is down it is the only light source and the swarm steers
-- toward it. No other control exists; the game is *indirect* herding.
--
-- Loop: guide enough of the swarm into the glow ring and hold it there to
-- score; every scored ring relocates and spawns a spider web. A firefly that
-- brushes a web is stuck and lost. The run ends when the swarm starves
-- (fewer than MIN_FLOCK left).
--
-- Graybox: existing textures only (orb / sparkle tints). No new assets.

function make_fireflies()
  local K = GAME_KIT
  local clamp, inr = K.clamp, K.in_rect
  local T = K.tracker()

  -- tuning ------------------------------------------------------------
  local N0         = 40      -- starting swarm
  local MIN_FLOCK  = 8       -- lose below this
  local NEIGH_R    = 64      -- neighbourhood radius
  local SEP_R      = 22      -- separation radius
  local W_SEP, W_ALI, W_COH = 60, 4.5, 3.0
  local W_LIGHT    = 240     -- pull toward the finger (accel)
  local W_WALL     = 420     -- soft wall push
  local WALL_M     = 40      -- wall margin
  local VMIN, VMAX = 36, 250
  local BOID_SZ    = 16
  local RING_R     = 78      -- goal ring radius
  local RING_NEED  = 0.6     -- fraction of living swarm required inside
  local RING_HOLD  = 1.0     -- seconds to hold
  local WEB_R      = 34
  local DT_CAP     = 1 / 30

  -- state ---------------------------------------------------------------
  local back, built, playing = nil, false, true
  local boids = {}           -- { id, x, y, vx, vy, ph }
  local webs = {}            -- { id, x, y }
  local ring = nil           -- { id, x, y }
  local rings_scored, hold_t = 0, 0
  local hw0, hh0 = 0, 0

  local function hud()
    game.set_text(string.format("RINGS %d   FLOCK %d", rings_scored, #boids))
  end

  local function clear_dynamic()
    for _, b in ipairs(boids) do game.despawn(b.id) end
    for _, w in ipairs(webs) do game.despawn(w.id) end
    if ring then game.despawn(ring.id) end
    boids, webs, ring = {}, {}, nil
  end

  local function spawn_boid(x, y)
    local id = game.spawn_sprite(x, y, BOID_SZ, BOID_SZ, "sparkle")
    game.set_color(id, 0.75, 1.0, 0.45, 1)
    local ph = #boids * 0.618
    boids[#boids + 1] = {
      id = id, x = x, y = y,
      vx = math.cos(ph * 6.28) * 60, vy = math.sin(ph * 6.28) * 60, ph = ph,
    }
  end

  local function place_ring()
    local hw, hh = hw0, hh0
    local x = (math.random() * 2 - 1) * (hw - RING_R - WALL_M)
    local y = (math.random() * 2 - 1) * (hh - RING_R - WALL_M - 60)
    if ring then game.despawn(ring.id) end
    local id = game.spawn_sprite(x, y, RING_R * 2, RING_R * 2, "orb")
    game.set_color(id, 1.0, 0.85, 0.3, 0.22)   -- translucent glow disc
    ring = { id = id, x = x, y = y }
    hold_t = 0
  end

  local function spawn_web()
    -- keep webs away from the current ring so a ring is never a death trap
    local hw, hh = hw0, hh0
    for _ = 1, 8 do
      local x = (math.random() * 2 - 1) * (hw - WEB_R - WALL_M)
      local y = (math.random() * 2 - 1) * (hh - WEB_R - WALL_M - 60)
      local dx, dy = x - ring.x, y - ring.y
      if dx * dx + dy * dy > (RING_R + WEB_R + 60) ^ 2 then
        local id = game.spawn_sprite(x, y, WEB_R * 2, WEB_R * 2, "orb")
        game.set_color(id, 0.45, 0.45, 0.52, 0.85)
        webs[#webs + 1] = { id = id, x = x, y = y }
        return
      end
    end
  end

  local function game_over()
    playing = false
    game.set_text(string.format("THE SWARM FADED\nRINGS %d\nTap to glow again", rings_scored))
    game.log("fireflies_over")
    game.play_sound("hit"); game.haptic("heavy"); game.shake(0.5)
    game.track("fireflies_over", rings_scored)
  end

  local function build(hw, hh)
    hw0, hh0 = hw, hh
    back = K.make_back(T, hw, hh)
    clear_dynamic()
    rings_scored, hold_t, playing = 0, 0, true
    for i = 1, N0 do
      local a = (i / N0) * 6.28
      spawn_boid(math.cos(a) * 90, math.sin(a) * 90)
    end
    place_ring()
    hud()
    game.set_bg_theme(1)
    built = true
    DEBUG = {
      game = "fireflies", back = back,
      rings = function() return rings_scored end,
      flock = function() return #boids end,
      alive = function() return playing end,
      web_count = function() return #webs end,
      webs = function()
        local out = {}
        for k, w in ipairs(webs) do out[k] = { x = w.x, y = w.y } end
        return out
      end,
      ring_pos = function() return ring.x, ring.y end,
      boids = function()
        local out = {}
        for k, b in ipairs(boids) do out[k] = { x = b.x, y = b.y, vx = b.vx, vy = b.vy } end
        return out
      end,
    }
  end

  local function restart()
    clear_dynamic(); T.clear(); built = false
    build(game.bounds())
  end

  return {
    enter = function() built = false end,
    leave = function() clear_dynamic(); T.clear(); built = false end,

    tap = function(x, y)
      if back and inr(back, x, y) then K.switch("menu"); return end
      if not playing then restart(); return end
    end,

    update = function(dt, hw, hh)
      if not built then build(hw, hh) end
      if dt > DT_CAP then dt = DT_CAP end
      if not playing then return end
      hw0, hh0 = hw, hh

      local px, py, down = game.pointer()

      -- boids: O(n^2) neighbour scan — n<=40 is well inside budget
      for i = 1, #boids do
        local b = boids[i]
        local sx, sy = 0, 0          -- separation
        local ax, ay, an = 0, 0, 0   -- alignment
        local cx, cy, cn = 0, 0, 0   -- cohesion
        for j = 1, #boids do
          if j ~= i then
            local o = boids[j]
            local dx, dy = o.x - b.x, o.y - b.y
            local d2 = dx * dx + dy * dy
            if d2 < NEIGH_R * NEIGH_R and d2 > 0.0001 then
              local d = math.sqrt(d2)
              if d < SEP_R then
                sx = sx - dx / d * (SEP_R - d) / SEP_R
                sy = sy - dy / d * (SEP_R - d) / SEP_R
              end
              ax = ax + o.vx; ay = ay + o.vy; an = an + 1
              cx = cx + o.x;  cy = cy + o.y;  cn = cn + 1
            end
          end
        end
        local fx = sx * W_SEP
        local fy = sy * W_SEP
        if an > 0 then
          fx = fx + (ax / an - b.vx) / VMAX * W_ALI * VMAX / 60
          fy = fy + (ay / an - b.vy) / VMAX * W_ALI * VMAX / 60
        end
        if cn > 0 then
          fx = fx + (cx / cn - b.x) * W_COH / 60
          fy = fy + (cy / cn - b.y) * W_COH / 60
        end
        -- the light: while held, the finger is the sun
        if down and px then
          local dx, dy = px - b.x, py - b.y
          local d = math.sqrt(dx * dx + dy * dy)
          if d > 1 then
            fx = fx + dx / d * W_LIGHT
            fy = fy + dy / d * W_LIGHT
          end
        else
          -- gentle deterministic wander so an idle swarm still breathes
          b.ph = b.ph + dt * 0.8
          fx = fx + math.cos(b.ph * 3.1) * 30
          fy = fy + math.sin(b.ph * 2.3) * 30
        end
        -- soft walls
        if b.x < -hw + WALL_M then fx = fx + W_WALL * (-hw + WALL_M - b.x) / WALL_M end
        if b.x >  hw - WALL_M then fx = fx - W_WALL * (b.x - hw + WALL_M) / WALL_M end
        if b.y < -hh + WALL_M then fy = fy + W_WALL * (-hh + WALL_M - b.y) / WALL_M end
        if b.y >  hh - WALL_M then fy = fy - W_WALL * (b.y - hh + WALL_M) / WALL_M end

        b.vx = b.vx + fx * dt
        b.vy = b.vy + fy * dt
        local sp = math.sqrt(b.vx * b.vx + b.vy * b.vy)
        if sp > VMAX then b.vx, b.vy = b.vx / sp * VMAX, b.vy / sp * VMAX
        elseif sp < VMIN and sp > 0.001 then b.vx, b.vy = b.vx / sp * VMIN, b.vy / sp * VMIN end
        b.x = clamp(b.x + b.vx * dt, -hw, hw)
        b.y = clamp(b.y + b.vy * dt, -hh, hh)
      end

      -- webs catch fireflies (walk backwards; despawn on contact)
      for i = #boids, 1, -1 do
        local b = boids[i]
        for _, w in ipairs(webs) do
          local dx, dy = b.x - w.x, b.y - w.y
          if dx * dx + dy * dy < (WEB_R + BOID_SZ * 0.4) ^ 2 then
            game.despawn(b.id)
            table.remove(boids, i)
            game.emit("dust", b.x, b.y)
            game.play_sound("wall"); game.haptic("medium"); game.shake(0.15)
            hud()
            break
          end
        end
      end
      if #boids < MIN_FLOCK then game_over(); return end

      -- goal ring: hold RING_NEED of the swarm inside for RING_HOLD seconds
      local inside = 0
      for _, b in ipairs(boids) do
        local dx, dy = b.x - ring.x, b.y - ring.y
        if dx * dx + dy * dy < RING_R * RING_R then inside = inside + 1 end
      end
      if inside >= math.max(1, math.floor(#boids * RING_NEED)) then
        hold_t = hold_t + dt
        if hold_t >= RING_HOLD then
          rings_scored = rings_scored + 1
          game.emit("confetti", ring.x, ring.y)
          game.play_sound("score"); game.haptic("success")
          game.shake(0.2); game.zoom(0.3)
          place_ring()
          spawn_web()
          hud()
        end
      else
        hold_t = 0
      end

      -- present
      for _, b in ipairs(boids) do game.move_to(b.id, b.x, b.y) end
    end,
  }
end

PACKS = PACKS or {}
PACKS["fireflies"] = { slot = 24, key = "fireflies", label = "Fireflies", short = "Glow",
  icon = "sparkle", color = { 0.75, 1.0, 0.45 }, tier = "ai", make = make_fireflies }
