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
  local ANT_SPEED = 110      -- world units / sec (slow, calm)
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
  local function load_tray(ti)
    local i = free_slot(); if not i or not tray[ti] then return false end
    slots[i] = table.remove(tray, ti); return true
  end
  -- Lowest colour index still present on the board (the current OUTERMOST layer).
  local function board_low_color()
    local low
    for r = 1, H do for c = 1, W do
      local v = grid[r][c]; if v ~= 0 and (low == nil or v < low) then low = v end
    end end
    return low
  end
  -- Auto play (autoplay / tests): commit free slots to the current outermost
  -- colour only. Never race an inner colour ahead of the outer ring — for a real
  -- picture that would orphan outer cells into an enclosed pocket (a stuck).
  local function fill_slots()
    if mode ~= "auto" then return end
    while free_slot() do
      local low = board_low_color()
      if not low or reachable_count(low) == 0 then break end
      local ti
      for i, b in ipairs(tray) do if b.color == low then ti = i; break end end
      if not ti then break end
      load_tray(ti)
    end
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
    table.insert(tray, 1, s); slots[i] = nil; return true
  end
  local function rewarded_ad(reward) game.track("rewarded_ad"); if reward then reward() end end
  local function cancel_slot_ad(i)
    if slots[i] then rewarded_ad(function() cancel_slot(i) end); return true end
    return false
  end
  local function check_stuck()
    if painted <= 0 then return false end
    for _, a in ipairs(ants) do if a.state ~= "idle" then return false end end
    for i = 1, SLOTS do local s = slots[i]; if s and reachable_count(s.color) > 0 then return false end end
    local free = false
    for i = 1, SLOTS do if slots[i] == nil then free = true end end
    if free then for _, b in ipairs(tray) do if reachable_count(b.color) > 0 then return false end end end
    return true
  end

  -- ---- textured tiles (candy) ---------------------------------------------
  local function tint(id, ci, a)
    local col = palette[ci]; game.set_color(id, col[1], col[2], col[3], a or 1)
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
    local id = game.spawn_sheet(NESTX, NESTY, CELL * 1.6, CELL * 1.6, "ant_sheet", 8, 8)
    ants[#ants + 1] = { id = id, slot = slot_i, state = "idle", x = NESTX, y = NESTY,
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
    if a.carry then game.move_to(a.carry, rx, ry - CELL * 0.5) end
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
      a.tr, a.tc, a.path, a.pi, a.state = r, c, p, 1, "out"   -- never over-sends ants
    elseif a.state == "out" then
      if move_along(a, dt) then
        if grid[a.tr][a.tc] ~= 0 then
          a.cc = grid[a.tr][a.tc]
          clear_cell(a.tr, a.tc)
          a.carry = game.spawn(a.x, a.y - CELL * 0.5, CELL * 0.7, CELL * 0.7, 1, 1, 1, 1)
          tint(a.carry, a.cc)
          game.play_sound("hit"); game.shake(0.02); game.haptic("light")
        end
        reserved[(a.tr-1)*W+a.tc] = nil
        local rev = {}
        for i = #a.path, 1, -1 do rev[#rev + 1] = a.path[i] end
        a.path, a.pi, a.state = rev, 1, "back"
      end
    elseif a.state == "back" then
      if move_along(a, dt) then
        if a.carry then game.despawn(a.carry); a.carry = nil; game.play_sound("wall") end
        a.state = "idle"
      end
    end
  end

  -- ---- HUD tiles (slots + tray) -------------------------------------------
  local slot_bg, slot_txt, slot_bug, tray_bg, tray_txt, tray_bug = {}, {}, {}, {}, {}, {}
  local slot_shown, tray_shown = {}, {}
  local function slot_x(i) return (i - (SLOTS + 1) / 2) * (SLOT_W + 8) end
  local function tray_x(i) local col = (i - 1) % 4; return (col - 1.5) * (TRAY_W + 8) end
  local function tray_yy(i) local row = math.floor((i - 1) / 4); return TRAY_Y - row * (TRAY_W + 8) end

  local function draw_hud()
    for i = 1, SLOTS do
      slot_bg[i] = T.sprite(slot_x(i), SLOT_Y, SLOT_W, SLOT_W, "tile_sq")
      game.set_color(slot_bg[i], 0.80, 0.76, 0.70, 1)
      slot_shown[i] = nil
    end
    for i = 1, 8 do
      tray_bg[i] = T.sprite(tray_x(i), tray_yy(i), TRAY_W, TRAY_W, "tile_sq")
      game.set_color(tray_bg[i], 0.80, 0.76, 0.70, 1)
      tray_shown[i] = nil
    end
  end
  local function refresh_hud()
    for i = 1, SLOTS do
      local s = slots[i]
      if s then tint(slot_bg[i], s.color) else game.set_color(slot_bg[i], 0.80, 0.76, 0.70, 1) end
      local lbl = s and tostring(s.n) or ""
      if lbl ~= slot_shown[i] then
        if slot_txt[i] then game.despawn(slot_txt[i]); slot_txt[i] = nil end
        if slot_bug[i] then game.despawn(slot_bug[i]); slot_bug[i] = nil end
        if lbl ~= "" then
          slot_bug[i] = T.sprite(slot_x(i) - SLOT_W * 0.24, SLOT_Y + SLOT_W * 0.22, SLOT_W * 0.34, SLOT_W * 0.34, "ant_sheet")
          game.set_color(slot_bug[i], 0.20, 0.16, 0.14, 1)
          slot_txt[i] = T.text(slot_x(i) + SLOT_W * 0.1, SLOT_Y - SLOT_W * 0.05, 22, 1, 1, 1, 1, lbl)
        end
        slot_shown[i] = lbl
      end
    end
    for i = 1, 8 do
      local b = tray[i]
      if b then tint(tray_bg[i], b.color) else game.set_color(tray_bg[i], 0.80, 0.76, 0.70, 1) end
      local lbl = b and tostring(b.n) or ""
      if lbl ~= tray_shown[i] then
        if tray_txt[i] then game.despawn(tray_txt[i]); tray_txt[i] = nil end
        if tray_bug[i] then game.despawn(tray_bug[i]); tray_bug[i] = nil end
        if lbl ~= "" then
          tray_bug[i] = T.sprite(tray_x(i) - TRAY_W * 0.24, tray_yy(i) + TRAY_W * 0.22, TRAY_W * 0.3, TRAY_W * 0.3, "ant_sheet")
          game.set_color(tray_bug[i], 0.20, 0.16, 0.14, 1)
          tray_txt[i] = T.text(tray_x(i) + TRAY_W * 0.08, tray_yy(i) - TRAY_W * 0.05, 22, 1, 1, 1, 1, lbl)
        end
        tray_shown[i] = lbl
      end
    end
  end

  local function status()
    if not SETTINGS.hud then return end
    if stuck then game.set_text("卡住了 — 点一个满槽位取消(看广告)") return end
    game.set_text(mode == "manual" and free_slot() and #tray > 0 and "点一个颜色" or "")
  end

  -- ---- build ---------------------------------------------------------------
  local function build(hw, hh)
    HW, HH = hw, hh

    -- ---- deterministic layout, stacked BOTTOM-UP so nothing ever overlaps ----
    local M, BAR_H = 30, 46
    local BAR_CY = -hh + M + BAR_H / 2
    TRAY_W = math.min((2 * hw - 44) / 4 - 8, 60)
    SLOT_W = math.min((2 * hw - 60) / 5 - 8, 50)
    local q_bot = BAR_CY + BAR_H / 2 + 28 + TRAY_W / 2      -- queue bottom row centre
    TRAY_Y = q_bot + (TRAY_W + 8)                           -- queue top row (row 0)
    SLOT_Y = (TRAY_Y + TRAY_W / 2) + 24 + SLOT_W / 2        -- slots above the queue
    local HOLE_R = 30
    NESTY = SLOT_Y + SLOT_W / 2 + 30 + HOLE_R               -- hole above the slots
    local board_bottom = NESTY + HOLE_R + 46                -- roomy gap: ants exit here
    local board_h = (hh - 150) - board_bottom               -- rest goes to the picture
    CELL = math.min((2 * hw - 44) / W, board_h / H, 16)
    OX = -W * CELL / 2
    TOPY = board_bottom + H * CELL
    NESTX = cx(math.floor(W / 2) + 1)

    grid, painted = {}, 0
    for r = 1, H do grid[r] = {} for c = 1, W do grid[r][c] = LEVEL.grid[r][c] end end
    tray = {}
    for i, b in ipairs(LEVEL.tray) do tray[i] = { color = b[1], n = b[2] } end
    slots, reserved, ants, dirty = {}, {}, {}, true
    playing, won, stuck, speed2, was_stuck = true, false, false, false, false

    -- decor: mascot + level pill
    T.sprite(0, hh - 42, 300, 118, "cat_face")
    T.text(-hw + 66, hh - 100, 20, 0.29, 0.22, 0.18, 1, "关卡 " .. (LEVEL.id or 1))
    -- board panel (white picture frame) behind the cells
    local panel = T.sprite(0, TOPY - 0.5 * CELL * H, W * CELL + 20, H * CELL + 20, "tile_sq")
    game.set_color(panel, 0.99, 0.97, 0.93, 1)
    -- nest hole + the two rewarded-ad unlock buttons flanking it
    T.sprite(NESTX, NESTY, HOLE_R * 2.4, HOLE_R * 1.9, "hole")   -- slightly widened
    for _, sx in ipairs({ -1, 1 }) do
      local bx = sx * (hw - 44)
      local ub = T.sprite(bx, NESTY, 74, 50, "tile_sq"); game.set_color(ub, 0.88, 0.85, 0.80, 1)
      T.sprite(bx, NESTY + 7, 26, 20, "ad_play")
      T.text(bx, NESTY - 15, 17, 0.47, 0.41, 0.36, 1, "解锁")
    end
    -- bottom bar: 4 equal-width buttons, evenly spaced — no overlap at any width
    local BM, BG = 14, 8
    local bw = (2 * hw - 2 * BM - 3 * BG) / 4
    local btns = {
      { "速度升级", { 0.34, 0.62, 0.86 } }, { "速度x2", { 0.94, 0.59, 0.25 } },
      { "第11关\n解锁", { 0.95, 0.84, 0.47 } }, { "第20关\n解锁", { 0.95, 0.84, 0.47 } },
    }
    for i, b in ipairs(btns) do
      local bxc = -hw + BM + bw / 2 + (i - 1) * (bw + BG)
      local id = T.sprite(bxc, BAR_CY, bw, BAR_H, "tile_sq")
      game.set_color(id, b[2][1], b[2][2], b[2][3], 1)
      local dark = b[2][1] > 0.9
      T.text(bxc, BAR_CY, 15, dark and 0.30 or 1, dark and 0.24 or 1, dark and 0.10 or 1, 1, b[1])
    end

    draw_board()
    draw_hud()
    back = { x = -hw + 36, y = hh - 46, w = 50, h = 50 }
    T.sprite(back.x, back.y, back.w, back.h, "icon_find")
    fill_slots()
    for i = 1, SLOTS do for _ = 1, ANTS_PER_SLOT do spawn_ant(i) end end
    recompute_field(); status(); built = true

    DEBUG = {
      game = "ant_clear", back = back,
      painted = function() return painted end,
      tray_len = function() return #tray end,
      won = function() return won end,
      stuck = function() return stuck end,
      reachable = function(col) return reachable_count(col) end,
      ant_xy = function() local o = {} for _, a in ipairs(ants) do o[#o + 1] = { a.x, a.y } end return o end,
      grid = function() return grid end,
      toggle_speed = function() speed2 = not speed2 end,
      set_mode = function(m) mode = m; fill_slots() end,
      free_slots = function() local n = 0 for i = 1, SLOTS do if slots[i] == nil then n = n + 1 end end return n end,
      load = function(ti) return load_tray(ti) end,
      load_unreachable = function()
        if not free_slot() then return false end
        for ti, b in ipairs(tray) do if reachable_count(b.color) == 0 then return load_tray(ti) end end
        return false
      end,
      cancel = function(i) return cancel_slot_ad(i) end,
      tray_colors = function() local o = {} for _, b in ipairs(tray) do o[#o + 1] = b.color end return o end,
      slot_colors = function() local o = {} for i = 1, SLOTS do o[i] = slots[i] and slots[i].color or 0 end return o end,
    }
  end

  local function win()
    playing, won = false, true
    game.set_text("恭喜完成！\n点击再玩一次")
    game.play_sound("score"); game.haptic("success"); game.shake(0.5); game.log("ant_clear win")
  end

  return {
    enter = function() built = false end,
    leave = function() T.clear(); ants = {}; built = false end,
    tap = function(x, y)
      if back and K.in_rect(back, x, y) then K.switch("menu"); return end
      if not playing then T.clear(); build(HW, HH); return end
      if math.abs(x - NESTX) < CELL and math.abs(y - NESTY) < CELL then
        speed2 = not speed2; game.play_sound("wall"); game.haptic("light"); return
      end
      if mode == "manual" then
        for i = 1, SLOTS do
          if slots[i] and math.abs(x - slot_x(i)) <= SLOT_W * 0.6 and math.abs(y - SLOT_Y) <= SLOT_W * 0.6 then
            if cancel_slot_ad(i) then game.play_sound("wall"); game.haptic("medium") end
            return
          end
        end
        if free_slot() then
          for i = 1, 8 do
            if tray[i] and math.abs(x - tray_x(i)) <= TRAY_W * 0.55 and math.abs(y - tray_yy(i)) <= TRAY_W * 0.55 then
              if load_tray(i) then game.play_sound("hit"); game.haptic("light") end
              return
            end
          end
        end
      end
    end,
    update = function(dt, hw, hh)
      if not built then build(hw, hh) end
      if not playing then return end
      dt = math.min(dt, MAX_DT)
      if dirty then recompute_field() end
      fill_slots()
      for _, a in ipairs(ants) do update_ant(a, dt) end
      for i = 1, SLOTS do if slots[i] and slots[i].n <= 0 then slots[i] = nil end end
      stuck = check_stuck()
      if stuck and not was_stuck then game.play_sound("wall"); game.haptic("medium") end
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
