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
-- Art (M3): Floniks-generated forge_star (tinted per level), forge_ring
-- (accretion ring), forge_ghost (aim ring), forge_up_* + forge_dust icons,
-- and the forge_theme/forge_hi BGM pair (switches on field pressure).

function make_forge()
  local K = GAME_KIT
  local clamp, inr = K.clamp, K.in_rect
  local T = K.tracker()

  -- tuning ------------------------------------------------------------
  local MAX_LEVEL   = 10
  local GM0         = 1.6e6   -- base gravity parameter (px^3/s^2-ish)
  local MASS_SCALE  = 1400    -- total mass that doubles GM (bot-tuned twice: 220→20s, 700→30s medians)
  local CORE_R      = 30      -- event-horizon radius
  local VMAX        = 620     -- hard speed cap (invariant-tested)
  local MAX_BODIES  = 48
  local SPAWN_CD    = 0.22    -- seconds between injections
  local COMBO_WIN   = 1.4     -- chain window (s)
  local DT_CAP      = 1 / 30
  local MIN_SPAWN_R = CORE_R + 90 -- bot-tuned: closer allowed suicide drops
  local LIVES0      = 4
  local RESTITUTION = 0.7     -- unequal-level bounce (bot-tuned: 0.86 scattered orbits)
  local SOFT_WALL_K = 3.2     -- nebula wall: spring back toward play space
  local SHOCK_K     = 26000   -- supernova shockwave impulse (px^2/s at d=1)
  local TWIN_EVERY  = 7       -- every 7th deal lands as a twin pair (deterministic)
  local COMET_EVERY = 20      -- seconds between comets
  local COMET_TTL   = 4.5     -- comet lifetime (s)
  local COMET_SPEED = 340     -- px/s, straight line, gravity-immune
  local COMET_R     = 14

  local function radius_of(level) return 9 + level * 6 end
  local function mass_of(level) return 2 ^ (level - 1) end
  -- 10-step cold->hot colour ramp (tints the grayscale orb texture)
  local RAMP = {
    { 0.55, 0.75, 1.00 }, { 0.45, 0.95, 0.85 }, { 0.45, 1.00, 0.55 },
    { 0.85, 1.00, 0.40 }, { 1.00, 0.90, 0.30 }, { 1.00, 0.70, 0.25 },
    { 1.00, 0.50, 0.30 }, { 1.00, 0.35, 0.45 }, { 0.95, 0.35, 0.80 },
    { 1.00, 1.00, 1.00 },
  }

  -- Implicit teaching (M1): the first three runs deal a fixed opening hand so
  -- a brand-new player is guaranteed to see a fusion inside 30 seconds.
  local TEACH_SEQ = { 1, 1, 1, 2, 2, 3 }
  local TEACH_RUNS = 3

  -- state ---------------------------------------------------------------
  local back, built, playing = nil, false, true
  local bodies = {}          -- { id, x, y, vx, vy, level, r, m, vis, flash_t }
  local score, lives, best_level = 0, LIVES0, 1
  local total_mass = 0
  local combo_n, combo_t = 0, 0
  local next_level = 1
  local teach_i = 0          -- >0 while dealing from TEACH_SEQ
  local spawn_cd = 0
  local core_id, preview_id = nil, nil
  local ghost_id, aim_dots = nil, {}
  local aiming, aim_x, aim_y, was_down = false, 0, 0, false
  local over_ids, again_rect, up_rect = {}, nil, nil
  local hw0, hh0 = 0, 0
  local rmax = 900
  local trail_k = 0          -- frame counter for the speed trail
  local deal_n = 0           -- deals this run; every TWIN_EVERY-th is a twin
  -- Comet event: a skill target that crosses the field on a straight line.
  -- Catching it with an orbiting star levels that star up for free.
  local comet, comet_t = nil, 0
  local comet_rng = 0        -- independent LCG in daily mode (same sky for all)
  local wall_mult = 1        -- STABLE NEBULA upgrade factor (normal mode only)

  -- Daily challenge (M2): everyone in the world gets the same deal sequence
  -- for the same UTC date — an independent LCG seeded by the date, so the
  -- global math.random stream (and the teaching hand) stays untouched.
  local daily, daily_rng = false, 0
  local daily_chip = nil     -- tap target that toggles the mode

  local function date_key()
    local y, m, d = game.date_utc()
    return string.format("%04d%02d%02d", y, m, d)
  end

  local function daily_seed()
    local y, m, d = game.date_utc()
    return (y * 10000 + m * 100 + d) % 2147483648
  end

  local function next_daily()
    daily_rng = (1103515245 * daily_rng + 12345) % 2147483648
    return math.floor((daily_rng / 2147483648) * 3) + 1
  end

  -- Permanent upgrade tree (M2): stardust = floor(score/50) per run. Upgrades
  -- apply to NORMAL runs only — the daily board stays pure so the same date is
  -- the same contest for everyone.
  local UPGRADES = {
    { key = "core", label = "EXTRA CORE",    costs = { 30, 90, 270 } }, -- +1 core / rank
    { key = "wall", label = "STABLE NEBULA", costs = { 20, 60, 180 } }, -- wall +40% / rank
    { key = "head", label = "HEAD START",    costs = { 25, 75, 225 } }, -- pre-placed L3 / rank
  }
  local shop_ids, shop_rects = {}, nil   -- shop card entities / hit rects

  -- Achievements (M2): permanent flags + a small toast on first unlock.
  local ACHIEVEMENTS = {
    { key = "first_fusion", label = "FIRST LIGHT" },
    { key = "chain3",       label = "CHAIN x3" },
    { key = "l5",           label = "STAR L5" },
    { key = "l8",           label = "STAR L8" },
    { key = "nova",         label = "SUPERNOVA" },
    { key = "daily",        label = "DAILY FORGED" },
  }
  local toast = nil          -- { id, t } one at a time; newest wins

  local function ach_count()
    local n = 0
    for _, a in ipairs(ACHIEVEMENTS) do
      if game.load("forge_ach_" .. a.key) then n = n + 1 end
    end
    return n
  end

  local function dust() return game.load("forge_dust") or 0 end
  local function rank_of(key) return game.load("forge_up_" .. key) or 0 end

  local function try_buy(key)
    for _, u in ipairs(UPGRADES) do
      if u.key == key then
        local r = rank_of(key)
        if r >= #u.costs then return false, "maxed" end
        local cost = u.costs[r + 1]
        if dust() < cost then return false, "poor" end
        game.save("forge_dust", dust() - cost)
        game.save("forge_up_" .. key, r + 1)
        game.track("forge_buy_" .. key, r + 1)
        return true
      end
    end
    return false, "unknown"
  end

  local function clear_shop()
    for _, id in ipairs(shop_ids) do game.despawn(id) end
    shop_ids, shop_rects = {}, nil
  end

  -- NOTE: caller clears the settlement card first (clear_over_card is
  -- declared later in the file, so it can't be referenced from here)
  local function open_shop()
    local P = shop_ids
    P[#P + 1] = game.spawn(0, 10, 340, 330, 0.05, 0.06, 0.14, 0.95)
    P[#P + 1] = game.spawn_sprite(-118, 140, 36, 36, "forge_dust")
    P[#P + 1] = game.spawn_text(10, 140, 28, 1.0, 0.85, 0.4, 1, string.format("STARDUST  %d", dust()))
    shop_rects = {}
    for i, u in ipairs(UPGRADES) do
      local y = 88 - (i - 1) * 62
      local r = rank_of(u.key)
      local label = string.format("%s  %d/3", u.label, r)
      local cost = r < #u.costs and ("COST " .. u.costs[r + 1]) or "MAX"
      P[#P + 1] = game.spawn(0, y, 300, 50, 0.16, 0.14, 0.3, 1)
      P[#P + 1] = game.spawn_sprite(-125, y, 42, 42, "forge_up_" .. u.key)
      P[#P + 1] = game.spawn_text(-24, y, 18, 1, 1, 1, 1, label)
      P[#P + 1] = game.spawn_text(110, y, 16, 0.7, 0.9, 1.0, 1, cost)
      shop_rects[u.key] = { x = 0, y = y, w = 300, h = 50 }
    end
    P[#P + 1] = game.spawn(0, -110, 190, 54, 1.0, 0.62, 0.2, 1)
    P[#P + 1] = game.spawn_text(0, -110, 24, 0.1, 0.06, 0.12, 1, "FORGE AGAIN")
    shop_rects.again = { x = 0, y = -110, w = 190, h = 54 }
  end

  local function gm() return GM0 * (1 + total_mass / MASS_SCALE) end

  local function hud()
    local combo = combo_n >= 2 and string.format("   x%d", combo_n) or ""
    local tag = daily and "DAILY   " or ""
    local twin = ((deal_n + 1) % TWIN_EVERY == 0) and " TWIN!" or ""
    game.set_text(string.format("%sSCORE %d   NEXT L%d%s   CORES %d%s", tag, score, next_level, twin, lives, combo))
  end

  local function tint(id, level)
    local c = RAMP[clamp(level, 1, MAX_LEVEL)]
    game.set_color(id, c[1], c[2], c[3], 1)
  end

  local function despawn_body(i)
    game.despawn(bodies[i].id)
    table.remove(bodies, i)
  end

  local function clear_toast()
    if toast then game.despawn(toast.id); toast = nil end
  end

  local function clear_comet()
    if comet then game.despawn(comet.id); comet = nil end
  end

  local function comet_rand()
    if daily then
      comet_rng = (1103515245 * comet_rng + 12345) % 2147483648
      return comet_rng / 2147483648
    end
    return math.random()
  end

  local function spawn_comet()
    local ang = comet_rand() * 6.28318
    local sx, sy = math.cos(ang) * rmax * 0.95, math.sin(ang) * rmax * 0.95
    -- aim at a point offset sideways from the core: it crosses, never hits
    local off = (100 + comet_rand() * 80) * (comet_rand() < 0.5 and -1 or 1)
    local dx, dy = -math.sin(ang) * off - sx, math.cos(ang) * off - sy
    local dd = math.sqrt(dx * dx + dy * dy)
    local id = game.spawn_sprite(sx, sy, COMET_R * 2, COMET_R * 2, "forge_star")
    game.set_color(id, 0.8, 1.0, 1.0, 1)
    comet = { id = id, x = sx, y = sy, vx = dx / dd * COMET_SPEED, vy = dy / dd * COMET_SPEED, ttl = COMET_TTL }
    game.play_sound("wall")
  end

  local function award(key)
    local k = "forge_ach_" .. key
    if game.load(k) then return end             -- each unlocks exactly once
    game.save(k, true)
    game.track(k)
    local label = key
    for _, a in ipairs(ACHIEVEMENTS) do
      if a.key == key then label = a.label end
    end
    clear_toast()
    toast = { id = game.spawn_text(0, hh0 - 140, 22, 1.0, 0.9, 0.4, 1, "* " .. label .. " *"), t = 2.2 }
    game.play_sound("score"); game.haptic("success")
  end

  local function draw_next()
    -- daily deals from the date-seeded LCG; otherwise the teaching sequence
    -- on early runs, then true random
    if daily then
      next_level = next_daily()
    elseif teach_i > 0 and teach_i <= #TEACH_SEQ then
      next_level = TEACH_SEQ[teach_i]
      teach_i = teach_i + 1
    else
      next_level = math.random(1, 3)
    end
    tint(preview_id, next_level)
  end

  local function hide_aim()
    aiming = false
    if ghost_id then game.set_color(ghost_id, 1, 1, 1, 0) end
    for _, id in ipairs(aim_dots) do game.set_color(id, 1, 1, 1, 0) end
  end

  local function show_aim(x, y)
    local d = math.sqrt(x * x + y * y)
    local ok = d >= MIN_SPAWN_R and spawn_cd <= 0
    local c = RAMP[clamp(next_level, 1, MAX_LEVEL)]
    game.move_to(ghost_id, x, y)
    game.set_color(ghost_id, c[1], c[2], c[3], ok and 0.55 or 0.15)
    if d > 1 then
      local tx, ty = -y / d, x / d   -- the tangential launch direction
      for k, id in ipairs(aim_dots) do
        game.move_to(id, x + tx * (18 + 16 * k), y + ty * (18 + 16 * k))
        game.set_color(id, c[1], c[2], c[3], ok and (0.5 - 0.1 * k) or 0)
      end
    end
  end

  local function clear_over_card()
    for _, id in ipairs(over_ids) do game.despawn(id) end
    over_ids, again_rect, up_rect = {}, nil, nil
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
    local id = game.spawn_sprite(x, y, r * 2, r * 2, "forge_star")
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
    hide_aim()
    local best_key = daily and ("forge_daily_" .. date_key()) or "forge_best"
    local best = game.load(best_key) or 0
    local is_best = score > best
    if is_best then best = score; game.save(best_key, score) end
    -- stardust payout (the upgrade currency)
    local earned = math.floor(score / 50)
    if earned > 0 then game.save("forge_dust", dust() + earned) end
    -- settlement card (E2: a dignified failure screen, one tap to retry)
    local P = over_ids
    P[#P + 1] = game.spawn(0, 10, 330, 300, 0.06, 0.05, 0.13, 0.92)
    P[#P + 1] = game.spawn_text(0, 120, 30, 1.0, 0.75, 0.35, 1,
      daily and ("DAILY " .. date_key()) or "THE FORGE COOLED")
    P[#P + 1] = game.spawn_text(0, 66, 26, 1, 1, 1, 1, string.format("SCORE  %d", score))
    if daily then award("daily") end
    P[#P + 1] = game.spawn_text(0, 26, 20, 0.8, 0.85, 1.0, 1,
      (is_best and "NEW BEST!" or string.format("BEST  %d", best))
        .. string.format("    ACH %d/%d", ach_count(), #ACHIEVEMENTS))
    P[#P + 1] = game.spawn_text(0, -12, 20, 0.9, 0.8, 1.0, 1,
      string.format("TOP STAR L%d    DUST +%d (%d)", best_level, earned, dust()))
    -- codex row: the fusion chain you have lit up so far (L1 is free — it is dealt)
    for k = 1, MAX_LEVEL do
      local id = game.spawn_sprite(-135 + (k - 1) * 30, -44, 22, 22, "forge_star")
      P[#P + 1] = id
      if k == 1 or (game.load("forge_codex_l" .. k) or 0) > 0 then
        local c = RAMP[k]
        game.set_color(id, c[1], c[2], c[3], 1)
      else
        game.set_color(id, 0.22, 0.22, 0.3, 0.8)
      end
    end
    P[#P + 1] = game.spawn(-78, -94, 158, 54, 1.0, 0.62, 0.2, 1)
    P[#P + 1] = game.spawn_text(-78, -94, 20, 0.1, 0.06, 0.12, 1, "FORGE AGAIN")
    again_rect = { x = -78, y = -94, w = 158, h = 54 }
    P[#P + 1] = game.spawn(88, -94, 140, 54, 0.35, 0.3, 0.65, 1)
    P[#P + 1] = game.spawn_text(88, -94, 20, 1, 1, 1, 1, "UPGRADES")
    up_rect = { x = 88, y = -94, w = 140, h = 54 }
    game.set_text(string.format("SCORE %d   BEST %d", score, best))
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
    -- codex: every fusion level reached is a permanent collection entry
    local ck = lvl > MAX_LEVEL and "forge_codex_nova" or ("forge_codex_l" .. lvl)
    game.save(ck, (game.load(ck) or 0) + 1)
    award("first_fusion")
    if combo_n >= 3 then award("chain3") end
    if lvl == 5 then award("l5") elseif lvl == 8 then award("l8")
    elseif lvl > MAX_LEVEL then award("nova") end
    game.track("forge_merge", lvl)
    if combo_n >= 2 then game.track("forge_combo", combo_n) end
    if lvl > best_level then best_level = lvl end
    game.emit("spark", x, y)
    game.play_sound("score")
    game.haptic(combo_n >= 3 and "heavy" or "success")
    game.shake(math.min(0.12 + 0.05 * lvl, 0.5))
    if lvl >= 5 then game.zoom(math.min(0.15 + 0.06 * (lvl - 5), 0.5)) end
    if lvl > MAX_LEVEL then
      -- L10 + L10: supernova — both stars burn out, big payout, field relaxes
      total_mass = total_mass - m
      game.despawn(a.id); game.despawn(b.id)
      table.remove(bodies, j); table.remove(bodies, i)
      score = score + 2048
      -- shockwave: every survivor is shoved radially away from the blast.
      -- Falloff K/max(d,80); clamp right here so the speed invariant holds
      -- even when sampled before the next integration pass.
      for _, o in ipairs(bodies) do
        local dx, dy = o.x - x, o.y - y
        local dd = math.sqrt(dx * dx + dy * dy)
        if dd > 1 then
          local imp = SHOCK_K / math.max(dd, 80)
          o.vx = o.vx + dx / dd * imp
          o.vy = o.vy + dy / dd * imp
          local sp2 = o.vx * o.vx + o.vy * o.vy
          if sp2 > VMAX * VMAX then
            local s = VMAX / math.sqrt(sp2)
            o.vx, o.vy = o.vx * s, o.vy * s
          end
        end
      end
      game.zoom(1.0); game.shake(0.8); game.emit("confetti", x, y)
      game.log("supernova")
      return
    end
    -- reuse a's sprite as the fused star (mass conserved: m = a.m + b.m)
    a.x, a.y, a.vx, a.vy = x, y, vx, vy
    a.level, a.m, a.r = lvl, m, radius_of(lvl)
    game.set_size(a.id, a.r * 2, a.r * 2)
    game.move_to(a.id, x, y)
    -- fusion white-flash: pop to white for a beat, then settle into the tint
    game.set_color(a.id, 1, 1, 1, 1)
    a.flash_t, a.vis = 0.09, "flash"
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
      local e = RESTITUTION
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
    -- accretion ring (Floniks art) drawn around the dark core, native colours
    local ring_id = T.sprite(0, 0, CORE_R * 3.4, CORE_R * 3.4, "forge_ring")
    game.set_color(ring_id, 1, 1, 1, 0.9)
    preview_id = T.sprite(hw - 36, hh - 36, 26, 26, "forge_star")
    ghost_id = T.sprite(9999, 9999, 26, 26, "forge_star")
    game.set_color(ghost_id, 1, 1, 1, 0)
    aim_dots = {}
    for k = 1, 4 do
      aim_dots[k] = T.sprite(9999, 9999, 8, 8, "forge_star")
      game.set_color(aim_dots[k], 1, 1, 1, 0)
    end
    back = K.make_back(T, hw, hh)
    -- DAILY chip: everyone plays the same deal today; tap toggles the mode
    local chip_x, chip_y = hw - 62, hh - 84
    local chip_id = T.spawn(chip_x, chip_y, 96, 34, 0.25, 0.2, 0.45, daily and 1 or 0.55)
    T.text(chip_x, chip_y, 16, 1, 1, 1, 1, daily and "DAILY ON" or "DAILY")
    daily_chip = { x = chip_x, y = chip_y, w = 96, h = 34, id = chip_id }
    clear_bodies()
    clear_over_card()
    score, lives, best_level = 0, LIVES0, 1
    total_mass, combo_n, combo_t = 0, 0, 0
    if daily then
      -- the daily board is pure: no upgrades, same contest for everyone
      daily_rng = daily_seed()
      comet_rng = daily_seed() + 99991   -- same sky for everyone, apart from deals
      teach_i = 0
      wall_mult = 1
      game.track("forge_daily_start", daily_seed())
    else
      local runs = (game.load("forge_runs") or 0) + 1
      game.save("forge_runs", runs)
      teach_i = (runs <= TEACH_RUNS) and 1 or 0
      -- permanent upgrades
      lives = LIVES0 + rank_of("core")
      wall_mult = 1 + 0.4 * rank_of("wall")
      for k = 1, rank_of("head") do
        inject(0, 180 + 45 * k, 3)               -- pre-placed L3s on stable orbits
      end
    end
    draw_next()
    spawn_cd, playing = 0, true
    aiming, was_down = false, false
    deal_n = 0
    clear_comet()
    comet_t = 0
    game.play_music("forge_theme")
    game.track("forge_start")
    hud()
    game.set_bg_theme(0, 1)   -- cool palette, full deep-space darkening: the void near a black hole
    built = true
    DEBUG = {
      game = "forge", back = back,
      score = function() return score end,
      lives = function() return lives end,
      alive = function() return playing end,
      next_level = function() return next_level end,
      again = function() return again_rect end,
      mode = function() return daily and "daily" or "normal" end,
      daily_chip = function() return daily_chip end,
      codex = function()
        local out = { nova = game.load("forge_codex_nova") or 0 }
        for k = 2, MAX_LEVEL do out[k] = game.load("forge_codex_l" .. k) or 0 end
        return out
      end,
      dust = function() return dust() end,
      upgrades = function()
        return { core = rank_of("core"), wall = rank_of("wall"), head = rank_of("head") }
      end,
      try_buy = function(k) return try_buy(k) end,
      up_button = function() return up_rect end,
      shop = function() return shop_rects end,
      comet = function()
        if not comet then return nil end
        return { x = comet.x, y = comet.y, vx = comet.vx, vy = comet.vy, ttl = comet.ttl }
      end,
      achievements = function()
        local out = {}
        for _, a in ipairs(ACHIEVEMENTS) do
          out[a.key] = game.load("forge_ach_" .. a.key) == true
        end
        return out
      end,
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
    clear_bodies(); clear_over_card(); clear_shop(); clear_toast(); clear_comet(); T.clear(); built = false
    build(game.bounds())
  end

  return {
    enter = function() built = false end,
    leave = function()
      clear_bodies(); clear_over_card(); clear_shop(); clear_toast(); clear_comet(); T.clear()
      game.stop_music()
      built = false
    end,

    -- Taps only drive UI now; injection is hold-to-aim + release (see update).
    tap = function(x, y)
      if back and inr(back, x, y) then K.switch("menu"); return end
      if daily_chip and inr(daily_chip, x, y) then
        daily = not daily
        game.play_sound("hit"); game.haptic("light")
        clear_shop(); restart()
        return
      end
      if not playing then
        if shop_rects then                       -- the upgrade shop is open
          for key, r in pairs(shop_rects) do
            if inr(r, x, y) then
              if key == "again" then
                clear_shop(); restart()
              else
                if try_buy(key) then game.play_sound("score"); game.haptic("success")
                else game.play_sound("wall") end
                clear_shop(); open_shop()        -- re-render ranks/costs/dust
              end
              return
            end
          end
          return                                  -- taps outside shop rows are inert
        end
        if up_rect and inr(up_rect, x, y) then
          clear_over_card(); open_shop()
          game.play_sound("hit")
          return
        end
        restart()
        return
      end
    end,

    update = function(dt, hw, hh)
      if not built then build(hw, hh) end
      if dt > DT_CAP then dt = DT_CAP end -- a hitch must never teleport an orbit
      if not playing then return end

      spawn_cd = math.max(0, spawn_cd - dt)
      if combo_t > 0 then combo_t = combo_t - dt; if combo_t <= 0 then combo_n = 0 end end

      -- hold to aim, release to launch (the ghost + tangent dots preview)
      local px, py, down = game.pointer()
      if down and px and not (back and inr(back, px, py))
          and not (daily_chip and inr(daily_chip, px, py)) then
        aiming, aim_x, aim_y = true, px, py
        show_aim(px, py)
      elseif aiming and not down then
        hide_aim()
        if spawn_cd <= 0 and inject(aim_x, aim_y, next_level) then
          deal_n = deal_n + 1
          if deal_n % TWIN_EVERY == 0 then
            -- twin star: a sibling lands trailing on the same orbit band.
            -- Deterministic counter (not RNG): players can plan for it, and
            -- the daily board stays identical for everyone.
            local dd = math.sqrt(aim_x * aim_x + aim_y * aim_y)
            local tx, ty = -aim_y / dd, aim_x / dd
            inject(aim_x - tx * 34, aim_y - ty * 34, next_level)
            game.emit("spark", aim_x, aim_y)
            game.play_sound("score"); game.haptic("success")
          end
          spawn_cd = SPAWN_CD
          draw_next()
          game.play_sound("hit"); game.haptic("light")
          hud()
        end
      end
      was_down = down

      -- gravity + integration (semi-implicit Euler) + speed cap
      local GM = gm()
      local rsoft = rmax * 0.72          -- the nebula wall starts here
      for _, b in ipairs(bodies) do
        local d2 = b.x * b.x + b.y * b.y
        local d = math.sqrt(d2)
        if d > 1 then
          local acc = GM / d2
          -- nebula wall: past rsoft a spring shoves the star back into play,
          -- so most "escapes" become long elliptical returns instead of losses
          if d > rsoft then acc = acc + (d - rsoft) * SOFT_WALL_K * wall_mult end
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
          -- the well eats it: it digests half the mass (failure still feeds
          -- the beast, but no runaway death spiral — bot-tuned)
          lives = lives - 1
          total_mass = total_mass - b.m * 0.5
          game.track("forge_eaten", b.level)
          game.emit("dust", b.x, b.y)
          game.play_sound("hit"); game.haptic("heavy"); game.shake(0.4); game.zoom(0.5)
          despawn_body(i)
          hud()
          if lives <= 0 then game_over(); return end
        elseif d > rmax then
          total_mass = total_mass - b.m   -- escaped: mass leaves the system
          game.track("forge_escape", b.level)
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

      -- pressure-reactive BGM: the heavy variant kicks in when the field is
      -- loaded, the calm theme returns when it clears (CurrentMusic dedups)
      if total_mass > 300 then game.play_music("forge_hi")
      elseif total_mass < 200 then game.play_music("forge_theme") end

      -- comet event: straight-line skill target; catch it with a star to
      -- level that star up for free (max level pays score instead)
      comet_t = comet_t + dt
      if not comet and comet_t >= COMET_EVERY then
        comet_t = 0
        spawn_comet()
      end
      if comet then
        comet.x = comet.x + comet.vx * dt
        comet.y = comet.y + comet.vy * dt
        comet.ttl = comet.ttl - dt
        game.move_to(comet.id, comet.x, comet.y)
        if trail_k % 3 == 0 then game.emit("dust", comet.x, comet.y) end
        local caught = false
        for _, b in ipairs(bodies) do
          local dx, dy = b.x - comet.x, b.y - comet.y
          if dx * dx + dy * dy < (b.r + COMET_R) ^ 2 then
            if b.level < MAX_LEVEL then
              total_mass = total_mass + b.m      -- doubling adds the old mass
              b.level = b.level + 1
              b.m = mass_of(b.level)
              b.r = radius_of(b.level)
              game.set_size(b.id, b.r * 2, b.r * 2)
              game.set_color(b.id, 1, 1, 1, 1)
              b.flash_t, b.vis = 0.12, "flash"
              if b.level > best_level then best_level = b.level end
            else
              score = score + 500
            end
            score = score + 100
            game.track("forge_comet_catch", b.level)
            game.emit("confetti", comet.x, comet.y)
            game.play_sound("score"); game.haptic("success")
            game.shake(0.3); game.zoom(0.3)
            hud()
            caught = true
            break
          end
        end
        if caught or comet.ttl <= 0 then clear_comet() end
      end

      -- achievement toast fade-out
      if toast then
        toast.t = toast.t - dt
        if toast.t <= 0 then clear_toast() end
      end

      -- speed trail: only slingshotting stars shed dust — speed IS the story
      trail_k = trail_k + 1
      if trail_k % 5 == 0 then
        for _, b in ipairs(bodies) do
          if b.vx * b.vx + b.vy * b.vy > 220 * 220 then game.emit("dust", b.x, b.y) end
        end
      end

      -- present: flash beats danger telegraph beats normal tint
      for _, b in ipairs(bodies) do
        game.move_to(b.id, b.x, b.y)
        local vis
        if b.flash_t then
          b.flash_t = b.flash_t - dt
          if b.flash_t <= 0 then b.flash_t = nil end
        end
        if b.flash_t then
          vis = "flash"
        else
          local d = math.sqrt(b.x * b.x + b.y * b.y)
          vis = (d < CORE_R + b.r * 0.35 + 44) and "hot" or "cool"
        end
        if vis ~= b.vis then
          b.vis = vis
          if vis == "hot" then game.set_color(b.id, 1.0, 0.22, 0.18, 1)
          elseif vis == "cool" then tint(b.id, b.level) end
          -- "flash" was painted white at fuse time
        end
      end
    end,
  }
end

PACKS = PACKS or {}
PACKS["forge"] = { slot = 23, key = "forge", label = "Starforge", short = "Forge",
  icon = "forge_star", color = { 1.0, 0.70, 0.25 }, tier = "ai", make = make_forge }
