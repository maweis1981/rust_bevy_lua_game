-- ant_clear.lua — "Ant Art" (蚂蚁艺术) — a strategy pixel-clear puzzle modelled
-- 1:1 on the reference game (Ants Flow, com.ants.box).
--
-- A cute picture is painted out of coloured pixels. You tap a colour tile to
-- commit it to one of your scarce SQUARE slots; matching ants then march out of
-- the nest, weave around the still-painted pixels (never through them — a flow
-- field shared by the swarm, recomputed only when a pixel is removed), pick a
-- frontier pixel of their colour, and carry it back down into the nest hole. The
-- board is eaten from the edges inward until it's clear -> the picture is done.
--
-- STRATEGY / MONETISATION: fewer slots than colours + interior colours that are
-- BURIED behind outer ones (cat eyes/nose inside the face). Commit a slot to a
-- buried colour and it stalls; fill every slot wrong and you're STUCK (no fail
-- state — relaxing genre). The escape valve is to CANCEL a slot (a rewarded
-- video: game.track"rewarded_ad"; wire a real SDK later) and re-pick, or restart.
--
-- Art pipeline: picture  = tools/gen_level.py --pattern cat   (embedded below)
--               ants      = tools/gen_ant_sheet.py -> assets/textures/ant_sheet.png
--               UI tiles  = tools/gen_ant_ui.py    -> tile_sq / hole / cat_face / ad_play
-- CJK strings are registered in tools/subset_font.py.

local function make_ant_clear()
  local K = GAME_KIT
  local T = K.tracker()

  -- ---- level (generated: tools/gen_level.py --pattern cat) -----------------
  local LEVEL = {
    id = 1, slots = 4,       -- level number + active-slot count (level-driven)
    w = 20, h = 17,
    palette = { {0.220,0.150,0.110}, {0.930,0.550,0.220}, {0.990,0.870,0.660}, {0.980,0.660,0.700}, {0.340,0.740,0.460} },
    grid = {
      {0,0,0,0,1,1,0,0,0,0,0,0,0,0,1,1,0,0,0,0},
      {0,0,0,1,4,4,1,0,0,0,0,0,0,1,4,4,1,0,0,0},
      {0,0,0,1,4,2,1,0,0,0,0,0,0,1,2,4,1,0,0,0},
      {0,0,1,1,2,2,1,1,0,0,0,0,1,1,2,2,1,1,0,0},
      {0,0,1,2,2,2,2,2,1,1,1,1,2,2,2,2,2,1,0,0},
      {0,1,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,1,0,0},
      {0,1,2,2,3,3,3,3,3,3,3,3,3,3,3,2,2,1,0,0},
      {0,1,2,3,3,3,3,3,3,3,3,3,3,3,3,3,2,1,0,0},
      {1,2,3,3,5,5,3,3,3,3,3,3,5,5,3,3,3,2,1,0},
      {1,2,3,3,5,5,3,3,3,3,3,3,5,5,3,3,3,2,1,0},
      {1,2,3,3,3,3,3,3,3,4,4,3,3,3,3,3,3,2,1,0},
      {1,2,3,3,3,3,3,3,4,4,4,4,3,3,3,3,3,2,1,0},
      {1,2,2,3,3,3,3,3,3,3,3,3,3,3,3,3,2,2,1,0},
      {0,1,2,2,3,3,3,3,3,3,3,3,3,3,2,2,1,0,0,0},
      {0,1,1,2,2,2,3,3,3,3,3,2,2,2,1,1,0,0,0,0},
      {0,0,0,1,1,2,2,2,2,2,2,2,1,1,1,1,0,0,0,0},
      {0,0,0,0,0,1,1,1,1,1,1,1,1,0,0,0,0,0,0,0},
    },
    tray = { {1,8},{1,8},{1,8},{1,8},{1,8},{2,8},{2,8},{2,8},{2,8},{1,8},{2,8},{3,8},{3,8},{3,8},{1,8},{2,8},{3,8},{3,8},{3,8},{3,8},{3,8},{2,8},{3,8},{3,8},{3,8},{4,8},{3,8},{2,8},{5,8},{1,6},{4,4},{2,2},{3,2} },
  }

  -- ---- tunables ------------------------------------------------------------
  local SLOTS = LEVEL.slots or 4   -- active slots (< palette size on purpose)
  local ANTS_PER_SLOT = 4
  local ANT_SPEED = 75       -- world units / sec (slow, calm)
  local ANT_SIZE = 2.3       -- ant sprite size in cells (big + clear)
  local MAX_DT = 1 / 30
  local mode = "manual"      -- "manual" (tap to load) | "auto" (autoplay/tests)

  local W, H = LEVEL.w, LEVEL.h
  local grid, painted, cell_id = {}, 0, {}

  -- geometry (filled in build)
  local CELL, OX, TOPY, NESTX, NESTY = 0, 0, 0, 0, 0
  local SLOT_Y, TRAY_Y, SLOT_W, TRAY_W = 0, 0, 0, 0
  local function cx(c) return OX + (c - 0.5) * CELL end
  local function cy(r) return TOPY - (r - 0.5) * CELL end

  -- ---- flow field over an open ring (rows/cols 0..H+1, 0..W+1) -------------
  local NW = W + 2
  local function node(r, c) return r * NW + c end
  local NEST = node(H + 1, math.floor(W / 2) + 1)
  local dist, par, dirty = {}, {}, true
  local function passable(r, c)
    if r < 1 or r > H or c < 1 or c > W then return true end
    return grid[r][c] == 0
  end
  local function recompute_field()
    dist, par = {}, {}
    local q, head = { NEST }, 1
    dist[NEST] = 0; par[NEST] = -1
    while head <= #q do
      local n = q[head]; head = head + 1
      local r, c = math.floor(n / NW), n % NW
      for _, p in ipairs({ {r+1,c},{r-1,c},{r,c+1},{r,c-1} }) do
        local rr, cc = p[1], p[2]
        if rr >= 0 and rr <= H + 1 and cc >= 0 and cc <= W + 1 and passable(rr, cc) then
          local m = node(rr, cc)
          if dist[m] == nil then dist[m] = dist[n] + 1; par[m] = n; q[#q + 1] = m end
        end
      end
    end
    dirty = false
  end
  local function path_to(tr, tc)
    if dirty then recompute_field() end
    local best, bestd
    for _, p in ipairs({ {tr+1,tc},{tr-1,tc},{tr,tc+1},{tr,tc-1} }) do
      local rr, cc = p[1], p[2]
      if rr >= 0 and rr <= H + 1 and cc >= 0 and cc <= W + 1 and passable(rr, cc) then
        local d = dist[node(rr, cc)]
        if d ~= nil and (bestd == nil or d < bestd) then bestd = d; best = node(rr, cc) end
      end
    end
    if best == nil then return nil end
    local chain, cur = {}, best
    while cur ~= -1 do chain[#chain + 1] = cur; cur = par[cur] end
    local pts = {}
    for i = #chain, 1, -1 do
      -- The flow-field nest node lives at grid row H+1 (the board's bottom edge),
      -- but the VISIBLE hole sits lower (its own layout position). Map the nest
      -- node to the visible hole so ants actually enter/leave the hole and never
      -- idle stranded on the board bottom.
      if chain[i] == NEST then
        pts[#pts + 1] = { NESTX, NESTY }
      else
        local r, c = math.floor(chain[i] / NW), chain[i] % NW
        pts[#pts + 1] = { cx(c), cy(r) }
      end
    end
    pts[#pts + 1] = { cx(tc), cy(tr) }
    return pts
  end

  -- ---- slots / tray / ants -------------------------------------------------
  local tray, slots, reserved, ants = {}, {}, {}, {}
  local NCOL, QROWS = 4, 2              -- queue = 4 fixed columns, 2 rows visible
  local cols = { {}, {}, {}, {} }       -- each column is a stack; only the head loads
  local col_adv = {}                    -- per-column slide-up animation timer
  local slot_pulse = {}   -- brief scale bump when a slot's count ticks down
  local playing, won, stuck, speed2 = true, false, false, false
  local HW, HH, built = 0, 0, false
  local back, was_stuck = nil, false
  local palette = LEVEL.palette

  local function reachable_count(color)
    if dirty then recompute_field() end
    local n = 0
    for r = 1, H do for c = 1, W do
      if grid[r][c] == color and not reserved[(r-1)*W+c] then
        for _, p in ipairs({ {r+1,c},{r-1,c},{r,c+1},{r,c-1} }) do
          if passable(p[1], p[2]) and dist[node(p[1], p[2])] ~= nil then n = n + 1; break end
        end
      end
    end end
    return n
  end
  local function free_slot() for i = 1, SLOTS do if slots[i] == nil then return i end end end
  local function queue_total() local n = 0 for c = 1, NCOL do n = n + #cols[c] end return n end
  local function col_head(c) return cols[c][1] end
  -- Load a COLUMN HEAD into a free slot (the only legal move: top row only). The
  -- column then advances up (col_adv drives the slide animation).
  local function load_head(c)
    local i = free_slot(); local b = cols[c] and cols[c][1]
    if not i or not b then return false end
    slots[i] = b; table.remove(cols[c], 1); col_adv[c] = 1; return true
  end
  -- Auto play (autoplay / tests): load any head whose colour is currently
  -- reachable. There is no geometric orphaning (ants only take reachable frontier
  -- cells) — the only failure is a slot jam, which is exactly the lose/ad state.
  local function fill_slots()
    if mode ~= "auto" then return end
    while free_slot() do
      local pick
      for c = 1, NCOL do
        local b = col_head(c)
        if b and reachable_count(b.color) > 0 then pick = c; break end
      end
      if not pick then break end
      load_head(pick)
    end
  end
  local function shortest_col()
    local best, bn = 1, math.huge
    for c = 1, NCOL do if #cols[c] < bn then bn = #cols[c]; best = c end end
    return best
  end
  local function cancel_slot(i)
    local s = slots[i]; if not s then return false end
    for _, a in ipairs(ants) do
      if a.slot == i and a.state == "out" then
        reserved[(a.tr-1)*W+a.tc] = nil
        s.n = s.n + 1                 -- give back the count reserved at dispatch
        local rev = { { a.x, a.y } }
        for k = a.pi, 1, -1 do rev[#rev + 1] = a.path[k] end
        a.path, a.pi, a.state = rev, 1, "back"
      end
    end
    local c = shortest_col(); table.insert(cols[c], 1, s); col_adv[c] = 1
    slots[i] = nil; return true
  end
  local function rewarded_ad(reward) game.track("rewarded_ad"); if reward then reward() end end
  local function cancel_slot_ad(i)
    if slots[i] then rewarded_ad(function() cancel_slot(i) end); return true end
    return false
  end
  -- Jammed (the lose/ad prompt): nothing carrying, no active slot colour reachable,
  -- and no free slot can load a reachable HEAD. Recoverable only by cancelling.
  local function check_stuck()
    if painted <= 0 then return false end
    for _, a in ipairs(ants) do if a.state ~= "idle" then return false end end
    for i = 1, SLOTS do local s = slots[i]; if s and reachable_count(s.color) > 0 then return false end end
    if free_slot() then
      for c = 1, NCOL do local b = col_head(c); if b and reachable_count(b.color) > 0 then return false end end
    end
    return true
  end

  -- ---- textured tiles (candy) ---------------------------------------------
  local function tint(id, ci, a)
    local col = palette[ci]; game.set_color(id, col[1], col[2], col[3], a or 1)
  end

  -- ---- bitmap number font (num_font.png: 10 candy digits, 52x68) -----------
  local NUMA = 52 / 68
  local function num_make(str, h, alpha)
    local dw = h * NUMA; local step = dw * 0.82
    local ids, offs = {}, {}
    local x0 = -(#str - 1) * step / 2
    for i = 1, #str do
      local d = tonumber(str:sub(i, i)) or 0
      local id = game.spawn_sheet(0, 0, dw, h, "num_font", 52, 68, 10, 10)
      game.set_frame(id, d); game.set_color(id, 1, 1, 1, alpha or 1)
      ids[i] = id; offs[i] = x0 + (i - 1) * step
    end
    return { ids = ids, offs = offs }
  end
  local function num_place(num, cx, cy)
    if not num then return end
    for i, id in ipairs(num.ids) do game.move_to(id, cx + num.offs[i], cy) end
  end
  local function num_free(num)
    if num then for _, id in ipairs(num.ids) do game.despawn(id) end end
  end

  -- ---- rendering: board ----------------------------------------------------
  local function draw_board()
    cell_id, painted = {}, 0
    for r = 1, H do cell_id[r] = {}
      for c = 1, W do
        local ci = grid[r][c]
        if ci ~= 0 then
          local id = T.sprite(cx(c), cy(r), CELL - 1, CELL - 1, "tile_sq")
          tint(id, ci); cell_id[r][c] = id; painted = painted + 1
        end
      end
    end
  end
  local function clear_cell(r, c)
    local id = cell_id[r][c]
    if id then game.despawn(id); cell_id[r][c] = nil end
    grid[r][c] = 0; painted = painted - 1; dirty = true
    game.emit("spark", cx(c), cy(r), 4)
  end

  -- ---- ants (spritesheet walk + facing + carry) ---------------------------
  local function spawn_ant(slot_i)
    -- ant_sheet is 8 frames of 48x48 (see tools/gen_ant_sheet.py). spawn_sheet
    -- needs (x,y,w,h,name, frame_w, frame_h, cols, frames) — all nine, or the
    -- host binding errors (which stalled the web build).
    local sh = game.spawn_sprite(NESTX, NESTY, CELL * ANT_SIZE * 0.85, CELL * ANT_SIZE * 0.5, "ant_shadow")
    game.set_color(sh, 1, 1, 1, 0.55)
    local id = game.spawn_sheet(NESTX, NESTY, CELL * ANT_SIZE, CELL * ANT_SIZE, "ant_sheet", 48, 48, 8, 8)
    ants[#ants + 1] = { id = id, shadow = sh, slot = slot_i, state = "idle", x = NESTX, y = NESTY,
                        pi = 1, path = nil, tr = 0, tc = 0, anim = 0, carry = nil, cc = 0, tintc = -1,
                        phase = (#ants % 8) * 0.8, dust = 0 }
  end
  -- Colour each ant to its slot's colour (a red slot -> red ants), so the swarm
  -- reads as "these ants are carrying THIS colour". Only re-set on change.
  local function tint_ant(a)
    local s = slots[a.slot]
    local ci = s and s.color or 0
    if ci ~= a.tintc then
      if ci == 0 then game.set_color(a.id, 0.55, 0.48, 0.44, 1)
      else local c = palette[ci]; game.set_color(a.id, c[1], c[2], c[3], 1) end
      a.tintc = ci
    end
  end
  local function pick_target(color)
    if dirty then recompute_field() end
    local br, bc, bd
    for r = 1, H do for c = 1, W do
      if grid[r][c] == color and not reserved[(r-1)*W+c] then
        for _, p in ipairs({ {r+1,c},{r-1,c},{r,c+1},{r,c-1} }) do
          if passable(p[1], p[2]) then
            local d = dist[node(p[1], p[2])]
            if d ~= nil and (bd == nil or d < bd) then bd = d; br, bc = r, c end
          end
        end
      end
    end end
    return br, bc
  end
  local function face(a, nx, ny)
    local dx, dy = nx - a.x, ny - a.y
    if dx * dx + dy * dy > 0.01 then game.set_rotation(a.id, math.atan(-dx, dy)) end
  end
  local function move_along(a, dt)
    local step = ANT_SPEED * dt * (speed2 and 2 or 1)
    local sx0, sy0, moved = a.x, a.y, 0
    while step > 0 and a.pi < #a.path do
      local nx, ny = a.path[a.pi + 1][1], a.path[a.pi + 1][2]
      local dx, dy = nx - a.x, ny - a.y
      local d = math.sqrt(dx * dx + dy * dy)
      face(a, nx, ny)
      if d <= step then a.x, a.y, a.pi, step, moved = nx, ny, a.pi + 1, step - d, moved + d
      else a.x, a.y, step, moved = a.x + dx / d * step, a.y + dy / d * step, 0, moved + step end
    end
    a.anim = (a.anim + moved * 0.16) % 8
    game.set_frame(a.id, math.floor(a.anim))
    -- gentle side-to-side meander perpendicular to travel (visual only — logical
    -- position stays on the path), plus little dust puffs while walking.
    local tdx, tdy = a.x - sx0, a.y - sy0
    local tl = math.sqrt(tdx * tdx + tdy * tdy)
    local rx, ry = a.x, a.y
    if tl > 0.01 then
      local px, py = -tdy / tl, tdx / tl
      local sway = math.sin(a.anim * 0.85 + a.phase) * CELL * 0.18
      rx, ry = a.x + px * sway, a.y + py * sway
      a.dust = a.dust + moved
      if a.dust > CELL * 0.85 then a.dust = 0; game.emit("dust", rx, ry - CELL * 0.15, 3) end
    end
    game.move_to(a.id, rx, ry)
    if a.shadow then game.move_to(a.shadow, rx, ry - CELL * 0.55) end
    -- emerge scale-in as the ant leaves the nest
    if a.emerge and a.emerge < 1 then
      a.emerge = math.min(1, a.emerge + dt * 5)
      local sz = CELL * ANT_SIZE * (0.35 + 0.65 * a.emerge)
      game.set_size(a.id, sz, sz)
    end
    -- carried pixel pops up from nothing, then rides the ant
    if a.carry then
      a.carry_t = math.min(1, (a.carry_t or 1) + dt * 8)
      local cs = CELL * 0.72 * (0.2 + 0.8 * a.carry_t)
      game.set_size(a.carry, cs, cs)
      game.move_to(a.carry, rx, ry - CELL * 0.5)
    end
    return a.pi >= #a.path
  end
  local function update_ant(a, dt)
    local s = slots[a.slot]
    tint_ant(a)
    if a.state == "idle" then
      if not s or s.n <= 0 then return end
      local r, c = pick_target(s.color); if not r then return end
      local p = path_to(r, c); if not p then return end
      reserved[(r-1)*W+c] = true
      s.n = s.n - 1                     -- reserve the count at DISPATCH so a slot
      slot_pulse[a.slot] = 1            -- animate the count tick-down
      a.emerge = 0                      -- scale-in as it leaves the nest
      a.tr, a.tc, a.path, a.pi, a.state = r, c, p, 1, "out"   -- never over-sends ants
    elseif a.state == "out" then
      if move_along(a, dt) then
        if grid[a.tr][a.tc] ~= 0 then
          a.cc = grid[a.tr][a.tc]
          clear_cell(a.tr, a.tc)
          a.carry = game.spawn(a.x, a.y - CELL * 0.5, 1, 1, 1, 1, 1, 1)
          a.carry_t = 0                 -- pop the picked pixel up from nothing
          tint(a.carry, a.cc)
          game.shake(0.02); game.haptic("light")   -- grab: subtle (deposit is the sound)
        end
        reserved[(a.tr-1)*W+a.tc] = nil
        local rev = {}
        for i = #a.path, 1, -1 do rev[#rev + 1] = a.path[i] end
        a.path, a.pi, a.state = rev, 1, "back"
      end
    elseif a.state == "back" then
      if move_along(a, dt) then
        if a.carry then game.despawn(a.carry); a.carry = nil; game.play_sound("ac_deposit") end
        a.state = "idle"
      end
    end
  end

  -- ---- HUD tiles (slots + tray) -------------------------------------------
  local slot_bg, slot_txt, slot_bug, tray_bg, tray_txt, tray_bug = {}, {}, {}, {}, {}, {}
  local slot_shown, tray_shown = {}, {}
  local coin_num                       -- bitmap-digit coin counter
  local drifters = {}                  -- ambient floating leaves/motes (bg motion)

  -- Ambient background motion: a handful of soft leaves + light motes that drift
  -- slowly upward-diagonally and wrap, so the scene never feels static. Spawned
  -- behind the board; cheap (just move_to + set_rotation per frame).
  local function spawn_drifters()
    drifters = {}
    for i = 1, 11 do
      local leaf = (i % 3 ~= 0)                       -- 2/3 leaves, 1/3 glowing motes
      local sz = leaf and (16 + math.random() * 14) or (7 + math.random() * 7)
      local id = game.spawn_sprite(0, 0, sz, sz, leaf and "leaf" or "petal")
      if leaf then
        local g = 0.35 + math.random() * 0.3
        game.set_color(id, 0.55 * g + 0.3, 0.62 * g + 0.28, 0.30 * g + 0.18, 0.5)
      else
        game.set_color(id, 1, 0.98, 0.9, 0.5)
      end
      drifters[i] = {
        id = id, leaf = leaf,
        x = (math.random() * 2 - 1) * HW, y = (math.random() * 2 - 1) * HH,
        vx = (math.random() * 2 - 1) * 10, vy = 6 + math.random() * 12,
        rot = math.random() * 6.28, spin = (math.random() * 2 - 1) * 0.6,
      }
    end
  end
  local function update_drifters(dt)
    for _, d in ipairs(drifters) do
      d.x = d.x + d.vx * dt; d.y = d.y + d.vy * dt; d.rot = d.rot + d.spin * dt
      if d.y > HH + 30 then d.y = -HH - 30; d.x = (math.random() * 2 - 1) * HW end
      if d.x > HW + 30 then d.x = -HW - 30 elseif d.x < -HW - 30 then d.x = HW + 30 end
      game.move_to(d.id, d.x, d.y)
      if d.leaf then game.set_rotation(d.id, d.rot) end
    end
  end

  -- Despawn every dynamically-spawned (untracked) sprite: ants + their shadows/
  -- carried pixels, and all bitmap-number digits. Called on rebuild and leave so
  -- nothing leaks (T.clear only covers tracker-owned sprites).
  local function despawn_dynamic()
    for _, a in ipairs(ants) do
      game.despawn(a.id)
      if a.shadow then game.despawn(a.shadow) end
      if a.carry then game.despawn(a.carry) end
    end
    for i = 1, SLOTS do num_free(slot_txt[i]); slot_txt[i] = nil end
    for c = 1, NCOL do for row = 0, QROWS - 1 do num_free(tray_txt[qi and qi(c, row) or ((c-1)*QROWS+row+1)]); end end
    tray_txt = {}
    num_free(coin_num); coin_num = nil
    for _, d in ipairs(drifters) do game.despawn(d.id) end; drifters = {}
  end
  local QYGAP = 6
  local function slot_x(i) return (i - (SLOTS + 1) / 2) * (SLOT_W + 8) end
  local function col_x(c) return (c - (NCOL + 1) / 2) * (TRAY_W + 8) end
  local function row_y(row) return TRAY_Y - row * (TRAY_W + QYGAP) end   -- row 0 = head (top)
  local function qi(c, row) return (c - 1) * QROWS + row + 1 end          -- 0-based row

  local function draw_hud()
    for i = 1, SLOTS do
      slot_bg[i] = T.sprite(slot_x(i), SLOT_Y, SLOT_W, SLOT_W, "tile_sq")
      game.set_color(slot_bg[i], 0.80, 0.76, 0.70, 1)
      slot_shown[i] = nil
    end
    for c = 1, NCOL do for row = 0, QROWS - 1 do
      local i = qi(c, row)
      tray_bg[i] = T.sprite(col_x(c), row_y(row), TRAY_W, TRAY_W, "tile_sq")
      game.set_color(tray_bg[i], 0.80, 0.76, 0.70, 0)
      tray_shown[i] = nil
    end end
  end
  local function refresh_hud()
    for i = 1, SLOTS do
      local s = slots[i]
      if s then tint(slot_bg[i], s.color) else game.set_color(slot_bg[i], 0.80, 0.76, 0.70, 1) end
      -- count-tick pulse: scale the slot tile up briefly, then ease back
      local p = slot_pulse[i] or 0
      if p > 0.01 then
        local sc = SLOT_W * (1 + 0.18 * p); game.set_size(slot_bg[i], sc, sc)
        slot_pulse[i] = p * 0.82
      elseif slot_pulse[i] then
        game.set_size(slot_bg[i], SLOT_W, SLOT_W); slot_pulse[i] = nil
      end
      local lbl = s and tostring(s.n) or ""
      if lbl ~= slot_shown[i] then
        num_free(slot_txt[i]); slot_txt[i] = nil
        if slot_bug[i] then game.despawn(slot_bug[i]); slot_bug[i] = nil end
        if lbl ~= "" then
          slot_bug[i] = T.sprite(slot_x(i) - SLOT_W * 0.26, SLOT_Y + SLOT_W * 0.26, SLOT_W * 0.3, SLOT_W * 0.3, "ant_icon")
          game.set_color(slot_bug[i], 0.20, 0.16, 0.14, 1)
          slot_txt[i] = num_make(lbl, SLOT_W * 0.52, 1)
        end
        slot_shown[i] = lbl
      end
      num_place(slot_txt[i], slot_x(i) + SLOT_W * 0.12, SLOT_Y - SLOT_W * 0.02)
    end
    for c = 1, NCOL do
      local slide = (col_adv[c] or 0)
      if slide > 0.01 then col_adv[c] = slide * 0.8 elseif col_adv[c] then col_adv[c] = nil end
      for row = 0, QROWS - 1 do
        local i = qi(c, row)
        local b = cols[c][row + 1]
        local head = (row == 0)
        local a = head and 1 or 0.5                 -- only the head row is "live"
        local yy = row_y(row) - slide * (TRAY_W + QYGAP)   -- slide up from one row below
        local xx = col_x(c)
        game.move_to(tray_bg[i], xx, yy)
        if b then tint(tray_bg[i], b.color, a) else game.set_color(tray_bg[i], 0.80, 0.76, 0.70, 0) end
        local lbl = b and tostring(b.n) or ""
        if lbl ~= tray_shown[i] then
          num_free(tray_txt[i]); tray_txt[i] = nil
          if tray_bug[i] then game.despawn(tray_bug[i]); tray_bug[i] = nil end
          if lbl ~= "" then
            tray_bug[i] = T.sprite(xx - TRAY_W * 0.26, yy + TRAY_W * 0.24, TRAY_W * 0.28, TRAY_W * 0.28, "ant_icon")
            game.set_color(tray_bug[i], 0.20, 0.16, 0.14, a)
            tray_txt[i] = num_make(lbl, TRAY_W * 0.5, a)
          end
          tray_shown[i] = lbl
        end
        if tray_bug[i] then game.move_to(tray_bug[i], xx - TRAY_W * 0.26, yy + TRAY_W * 0.24) end
        num_place(tray_txt[i], xx + TRAY_W * 0.06, yy - TRAY_W * 0.04)
      end
    end
  end

  local function status()
    if not SETTINGS.hud then return end
    if stuck then game.set_text("卡住了 — 点一个满槽位取消(看广告)") return end
    game.set_text(mode == "manual" and free_slot() and queue_total() > 0 and "点一个颜色" or "")
  end

  -- ---- build ---------------------------------------------------------------
  local function build(hw, hh)
    HW, HH = hw, hh
    despawn_dynamic()   -- clear any leftover ants / bitmap digits before a rebuild

    -- ---- deterministic layout, stacked BOTTOM-UP so nothing ever overlaps ----
    local M, BAR_H = 30, 46
    local BAR_CY = -hh + M + BAR_H / 2
    TRAY_W = math.min((2 * hw - 44) / 4 - 8, 54)
    SLOT_W = math.min((2 * hw - 60) / 5 - 8, 50)
    -- reserve QROWS visible queue rows above the bar (head row at the top)
    local q_bot = BAR_CY + BAR_H / 2 + 18 + TRAY_W / 2      -- bottom queue row centre
    TRAY_Y = q_bot + (QROWS - 1) * (TRAY_W + 6)             -- head row (row 0, top)
    SLOT_Y = (TRAY_Y + TRAY_W / 2) + 20 + SLOT_W / 2        -- slots above the queue
    local HOLE_R = 30
    NESTY = SLOT_Y + SLOT_W / 2 + 30 + HOLE_R               -- hole above the slots
    local board_bottom = NESTY + HOLE_R + 46                -- roomy gap: ants exit here
    -- RESPONSIVE: the picture fills the screen width (like the reference), then
    -- is capped by whatever vertical space is left — it scales with the device,
    -- never a fixed size.
    local board_h = (hh - 82) - board_bottom                -- rest goes to the picture
    CELL = math.min((2 * hw - 18) / W, board_h / H)
    OX = -W * CELL / 2
    TOPY = board_bottom + H * CELL
    NESTX = cx(math.floor(W / 2) + 1)

    grid, painted = {}, 0
    for r = 1, H do grid[r] = {} for c = 1, W do grid[r][c] = LEVEL.grid[r][c] end end
    -- Fixed queue: distribute the (peel-order, guaranteed-solvable) tray round-
    -- robin into NCOL columns. Only column HEADS load; the layout never shuffles.
    tray, cols, col_adv = {}, { {}, {}, {}, {} }, {}
    for i, b in ipairs(LEVEL.tray) do
      local bb = { color = b[1], n = b[2] }
      cols[(i - 1) % NCOL + 1][#cols[(i - 1) % NCOL + 1] + 1] = bb
    end
    slots, reserved, ants, dirty = {}, {}, {}, true
    playing, won, stuck, speed2, was_stuck = true, false, false, false, false

    -- full-screen cozy background (generated art), behind everything
    T.sprite(0, 0, math.max(2 * hw, 2 * hh * 512 / 768) + 4, 2 * hh + 4, "game_bg")
    spawn_drifters()   -- ambient floating leaves/motes over the background
    -- top status bar: settings (left) · 关卡 N (centre) · coins (right)
    local bar = T.sprite(0, hh - 34, 2 * hw - 20, 48, "tile_sq")
    game.set_color(bar, 0.99, 0.94, 0.84, 1)
    T.text(0, hh - 34, 22, 0.30, 0.22, 0.16, 1, "关卡 " .. (LEVEL.id or 1))
    T.sprite(hw - 96, hh - 34, 26, 26, "icon_coin")
    coin_num = num_make("1240", 22, 1); num_place(coin_num, hw - 54, hh - 34)
    -- board panel (white picture frame) behind the cells
    local panel = T.sprite(0, TOPY - 0.5 * CELL * H, W * CELL + 20, H * CELL + 20, "tile_sq")
    game.set_color(panel, 0.99, 0.97, 0.93, 1)
    -- nest hole (generated art) + the two rewarded-ad unlock buttons flanking it
    T.sprite(NESTX, NESTY, HOLE_R * 2.5, HOLE_R * 2.4, "hole")
    for _, sx in ipairs({ -1, 1 }) do
      local bx = sx * (hw - 44)
      local ub = T.sprite(bx, NESTY, 80, 54, "btn_pill"); game.set_color(ub, 0.93, 0.80, 0.55, 1)
      T.sprite(bx, NESTY + 8, 26, 20, "ad_play")
      T.text(bx, NESTY - 14, 17, 0.42, 0.32, 0.18, 1, "解锁")
    end
    -- bottom bar: 4 equal-width buttons, evenly spaced — no overlap at any width
    local BM, BG = 14, 8
    local bw = (2 * hw - 2 * BM - 3 * BG) / 4
    local btns = {
      { "速度升级", { 0.34, 0.62, 0.86 }, "icon_speed" },
      { "速度x2", { 0.94, 0.59, 0.25 }, "icon_x2" },
      { "第11关\n解锁", { 0.95, 0.84, 0.47 }, "icon_gift" },
      { "第20关\n解锁", { 0.95, 0.84, 0.47 }, "icon_gift" },
    }
    for i, b in ipairs(btns) do
      local bxc = -hw + BM + bw / 2 + (i - 1) * (bw + BG)
      local id = T.sprite(bxc, BAR_CY, bw, BAR_H + 6, "btn_pill")
      game.set_color(id, b[2][1], b[2][2], b[2][3], 1)
      local ic = T.sprite(bxc - bw * 0.32, BAR_CY, BAR_H * 0.62, BAR_H * 0.62, b[3])
      if b[3] == "icon_x2" then game.set_color(ic, 0.22, 0.15, 0.10, 1) end
      local dark = b[2][1] > 0.9
      T.text(bxc + bw * 0.12, BAR_CY, 14, dark and 0.30 or 1, dark and 0.24 or 1, dark and 0.10 or 1, 1, b[1])
    end

    draw_board()
    draw_hud()
    back = { x = -hw + 34, y = hh - 34, w = 44, h = 44 }
    T.sprite(back.x, back.y, back.w, back.h, "icon_find")
    fill_slots()
    for i = 1, SLOTS do for _ = 1, ANTS_PER_SLOT do spawn_ant(i) end end
    recompute_field(); status(); built = true

    DEBUG = {
      game = "ant_clear", back = back,
      painted = function() return painted end,
      tray_len = function() return queue_total() end,
      won = function() return won end,
      stuck = function() return stuck end,
      reachable = function(col) return reachable_count(col) end,
      ant_xy = function() local o = {} for _, a in ipairs(ants) do o[#o + 1] = { a.x, a.y } end return o end,
      grid = function() return grid end,
      toggle_speed = function() speed2 = not speed2 end,
      set_mode = function(m) mode = m; fill_slots() end,
      free_slots = function() local n = 0 for i = 1, SLOTS do if slots[i] == nil then n = n + 1 end end return n end,
      load = function(c) return load_head(c) end,   -- c = column index (1..NCOL)
      load_unreachable = function()                  -- load a buried-colour head (a wrong move)
        if not free_slot() then return false end
        for c = 1, NCOL do local b = col_head(c); if b and reachable_count(b.color) == 0 then return load_head(c) end end
        return false
      end,
      cancel = function(i) return cancel_slot_ad(i) end,
      tray_colors = function() local o = {} for c = 1, NCOL do local b = col_head(c); o[c] = b and b.color or 0 end return o end,
      slot_colors = function() local o = {} for i = 1, SLOTS do o[i] = slots[i] and slots[i].color or 0 end return o end,
    }
  end

  local function win()
    playing, won = false, true
    game.set_text("恭喜完成！\n点击再玩一次")
    game.play_sound("ac_win"); game.haptic("success"); game.shake(0.5); game.log("ant_clear win")
  end

  return {
    enter = function() built = false; game.play_music("ac_bgm") end,
    leave = function() T.clear(); despawn_dynamic(); ants = {}; built = false; game.stop_music() end,
    tap = function(x, y)
      if back and K.in_rect(back, x, y) then K.switch("menu"); return end
      if not playing then T.clear(); build(HW, HH); return end
      if math.abs(x - NESTX) < CELL and math.abs(y - NESTY) < CELL then
        speed2 = not speed2; game.play_sound("ac_load"); game.haptic("light"); return
      end
      if mode == "manual" then
        for i = 1, SLOTS do
          if slots[i] and math.abs(x - slot_x(i)) <= SLOT_W * 0.6 and math.abs(y - SLOT_Y) <= SLOT_W * 0.6 then
            if cancel_slot_ad(i) then game.play_sound("ac_load"); game.haptic("medium") end
            return
          end
        end
        if free_slot() then
          for c = 1, NCOL do   -- only the top row (column heads) can be loaded
            if col_head(c) and math.abs(x - col_x(c)) <= TRAY_W * 0.55 and math.abs(y - row_y(0)) <= TRAY_W * 0.6 then
              if load_head(c) then game.play_sound("ac_place"); game.haptic("light") end
              return
            end
          end
        end
      end
    end,
    update = function(dt, hw, hh)
      if not built then build(hw, hh) end
      update_drifters(math.min(dt, MAX_DT))   -- ambient motion, even on the win card
      if not playing then return end
      dt = math.min(dt, MAX_DT)
      if dirty then recompute_field() end
      fill_slots()
      for _, a in ipairs(ants) do update_ant(a, dt) end
      for i = 1, SLOTS do if slots[i] and slots[i].n <= 0 then slots[i] = nil end end
      stuck = check_stuck()
      if stuck and not was_stuck then game.play_sound("ac_stuck"); game.haptic("medium") end
      was_stuck = stuck
      refresh_hud(); status()
      if painted <= 0 then win() end
    end,
  }
end

PACKS = PACKS or {}
PACKS.ant_clear = {
  slot = 10, key = "ant_clear", label = "Ant Art", short = "Ant Art",
  icon = "villager", color = { 0.93, 0.55, 0.22 }, tier = "curated", make = make_ant_clear,
}
