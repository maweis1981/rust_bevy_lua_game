-- ant_clear.lua — "Ant Art" strategy-elimination puzzle (vertical slice).
--
-- A cute picture is painted out of coloured pixels. Colour-matched ants march out
-- of the nest, crawl AROUND the open space (never through still-painted pixels),
-- pick up a pixel of their colour on the frontier, and carry it away — the board
-- is eaten from the edges inward until it is empty. Because a pixel can only be
-- taken once it sits on the frontier (touching cleared/open space), a colour
-- buried in the middle is unreachable until the colours around it are gone. That
-- spatial coupling is the puzzle.
--
-- What this slice proves out (the hard parts of the pitch):
--   * flow-field pathfinding on a DYNAMIC grid, shared by the whole swarm and
--     recomputed only when a pixel is removed (BFS from the nest through the open
--     ring + cleared channels) — so ants weave around walls, cheaply, in Lua;
--   * a tray (ordered colour-batch queue) whose colours + counts MATCH the
--     picture's colour distribution and is GUARANTEED solvable (tools/gen_level.py
--     emits it by peeling the frontier; see that file);
--   * slot scheduling with a real deadlock/lose state for the strategy layer.
--
-- The embedded LEVEL is produced by:  python3 tools/gen_level.py --pattern heart
-- Regenerate + paste to change the picture. The Rust flow-field port (src/ants.rs)
-- is the scale follow-up; at slice size the Lua BFS is trivially cheap.

local function make_ant_clear()
  local K = GAME_KIT
  local T = K.tracker()

  -- ---- level data (generated; keep in sync with tools/gen_level.py) --------
  local LEVEL = {
    w = 15, h = 14,
    palette = { {0.920,0.240,0.340}, {0.720,0.140,0.260}, {1.000,0.720,0.780} },
    grid = {
      {0,0,0,0,0,0,0,0,0,0,0,0,0,0,0},
      {0,0,0,0,0,0,0,0,0,0,0,0,0,0,0},
      {0,0,1,3,3,3,1,0,1,1,1,1,1,0,0},
      {0,1,3,3,3,3,3,1,1,1,1,1,1,1,0},
      {0,3,3,3,3,3,3,1,1,1,1,1,1,1,0},
      {1,3,3,3,3,3,3,1,1,1,1,1,1,1,1},
      {1,1,3,3,3,3,3,1,1,1,1,1,1,1,1},
      {0,1,1,1,1,1,1,1,1,1,1,1,1,1,0},
      {0,1,1,1,1,1,1,1,1,1,1,1,1,1,0},
      {0,1,1,1,1,1,1,1,1,1,1,1,1,1,0},
      {0,0,1,1,1,1,1,1,1,1,1,1,1,0,0},
      {0,0,0,2,2,2,2,2,2,2,2,2,0,0,0},
      {0,0,0,0,2,2,2,2,2,2,2,0,0,0,0},
      {0,0,0,0,0,0,2,2,2,0,0,0,0,0,0},
    },
    tray = { {1,6},{1,6},{1,6},{1,6},{1,6},{1,6},{1,6},{1,6},{1,6},{1,6},{1,6},{1,6},
             {3,6},{3,6},{1,6},{1,6},{3,6},{2,6},{2,6},{1,6},{2,6},{3,6},{1,1},{2,1},{3,1} },
  }

  -- ---- tunables ------------------------------------------------------------
  -- SLOTS < number of palette colours is what makes this a STRATEGY game: you
  -- cannot keep every colour active, so you must choose which colour to commit a
  -- scarce slot to — and loading a buried colour can strand you (a lose).
  local SLOTS = 2            -- active colour slots (< 3 palette colours on purpose)
  local ANTS_PER_SLOT = 4
  local ANT_SPEED = 460      -- world units / sec
  local MAX_DT = 1 / 30      -- clamp hitches (no teleport — the feel contract)
  local CELL_CAP = 28
  -- "manual": player taps a tray tile to load a colour into a free slot (the
  -- strategy layer). "auto": free slots pull the tray front (autoplay / tests).
  local mode = "manual"

  local W, H = LEVEL.w, LEVEL.h
  local grid = {}            -- grid[r][c], 1-based rows/cols, 0 = cleared
  local painted = 0
  local cell_id = {}         -- sprite id per painted cell

  -- geometry
  local CELL, OX, TOPY, NESTX, NESTY = 0, 0, 0, 0, 0
  local function cx(c) return OX + (c - 0.5) * CELL end          -- c in 0..W+1 ok
  local function cy(r) return TOPY - (r - 0.5) * CELL end        -- r=1 top row

  -- flow field over an open ring (rows 0..H+1, cols 0..W+1); core cell passable
  -- iff cleared. Node index n = r*(W+2)+c with r in 0..H+1, c in 0..W+1.
  local NW = W + 2
  local function node(r, c) return r * NW + c end
  local NEST = node(H + 1, math.floor(W / 2) + 1)
  local dist, par, dirty = {}, {}, true
  local function passable(r, c)
    if r < 1 or r > H or c < 1 or c > W then return true end      -- outside ring
    return grid[r][c] == 0
  end
  local function recompute_field()
    dist, par = {}, {}
    local q, head = { NEST }, 1
    dist[NEST] = 0; par[NEST] = -1
    while head <= #q do
      local n = q[head]; head = head + 1
      local r, c = math.floor(n / NW), n % NW
      local nb = { {r+1,c},{r-1,c},{r,c+1},{r,c-1} }
      for _, p in ipairs(nb) do
        local rr, cc = p[1], p[2]
        if rr >= 0 and rr <= H + 1 and cc >= 0 and cc <= W + 1 and passable(rr, cc) then
          local m = node(rr, cc)
          if dist[m] == nil then dist[m] = dist[n] + 1; par[m] = n; q[#q + 1] = m end
        end
      end
    end
    dirty = false
  end

  -- Build a world-space path nest -> ... -> target painted cell, or nil if the
  -- cell is not currently reachable (buried). `tr,tc` are 1-based core coords.
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
    -- chain is entry..nest; reverse to nest..entry, then append the target cell
    local pts = {}
    for i = #chain, 1, -1 do
      local r, c = math.floor(chain[i] / NW), chain[i] % NW
      pts[#pts + 1] = { cx(c), cy(r) }
    end
    pts[#pts + 1] = { cx(tc), cy(tr) }
    return pts
  end

  -- ---- slots / tray --------------------------------------------------------
  local tray = {}                 -- queue of {color, n}
  local slots = {}                -- [i] = {color, n} or nil
  local reserved = {}             -- reserved[r*W+c] = true (ant en route)
  local ants = {}
  local playing, won, dead = true, false, false
  local HW, HH, built = 0, 0, false
  local back, nest_id, speed2 = nil, nil, false

  local slot_bg, slot_txt, tray_bg, tray_txt = {}, {}, {}, {}
  local slot_shown, tray_shown = {}, {}   -- last-rendered label, to avoid churn

  local function reachable_count(color)
    if dirty then recompute_field() end
    local n = 0
    for r = 1, H do for c = 1, W do
      if grid[r][c] == color and not reserved[(r - 1) * W + c] then
        -- reachable iff a passable neighbour has a finite dist
        for _, p in ipairs({ {r+1,c},{r-1,c},{r,c+1},{r,c-1} }) do
          local rr, cc = p[1], p[2]
          if passable(rr, cc) and dist[node(rr, cc)] ~= nil then n = n + 1; break end
        end
      end
    end end
    return n
  end

  local function free_slot()
    for i = 1, SLOTS do if slots[i] == nil then return i end end
    return nil
  end

  -- Load tray batch `ti` into the leftmost free slot (the player's move, and the
  -- auto-player's too). Returns true on success.
  local function load_tray(ti)
    local i = free_slot()
    if not i or not tray[ti] then return false end
    slots[i] = table.remove(tray, ti)
    return true
  end

  -- Auto mode only: keep free slots topped up from the tray front.
  local function fill_slots()
    if mode ~= "auto" then return end
    while free_slot() and #tray > 0 do load_tray(1) end
  end

  -- Deadlock: nothing is being carried, no active slot colour has a reachable
  -- frontier cell, and no free slot can pull a workable colour from the tray,
  -- yet pixels remain. (Auto-fill front never hits this with a gen_level tray;
  -- bad manual reordering can — that's the strategy layer's lose state.)
  local function check_dead()
    if painted <= 0 then return false end
    for _, a in ipairs(ants) do if a.state ~= "idle" then return false end end
    for i = 1, SLOTS do
      local s = slots[i]
      if s and reachable_count(s.color) > 0 then return false end
    end
    local free = false
    for i = 1, SLOTS do if slots[i] == nil then free = true end end
    if free then
      for _, b in ipairs(tray) do if reachable_count(b.color) > 0 then return false end end
    end
    return true
  end

  -- ---- rendering -----------------------------------------------------------
  local function palette(ci) return LEVEL.palette[ci] end
  local function draw_board()
    cell_id, painted = {}, 0
    for r = 1, H do
      cell_id[r] = {}
      for c = 1, W do
        local ci = grid[r][c]
        if ci ~= 0 then
          local col = palette(ci)
          cell_id[r][c] = T.spawn(cx(c), cy(r), CELL - 1, CELL - 1, col[1], col[2], col[3], 1)
          painted = painted + 1
        end
      end
    end
  end

  local function clear_cell(r, c)
    local id = cell_id[r][c]
    if id then game.despawn(id); cell_id[r][c] = nil end
    grid[r][c] = 0
    painted = painted - 1
    dirty = true
    game.emit("spark", cx(c), cy(r), 4)
  end

  local function status()
    if not SETTINGS.hud then return end
    local hint = (mode == "manual" and free_slot() and #tray > 0) and "  — TAP A COLOUR" or ""
    game.set_text(string.format("PIXELS %d   TRAY %d%s", painted, #tray, hint))
  end

  local SLOT_Y, TRAY_Y = 0, 0
  local function slot_x(i) return (i - (SLOTS + 1) / 2) * (CELL * 2.4) end
  local function tray_x(i) return (i - 3.5) * (CELL * 1.5) end
  local function draw_hud()
    SLOT_Y = NESTY - CELL * 1.6
    TRAY_Y = SLOT_Y - CELL * 1.7
    for i = 1, SLOTS do
      slot_bg[i] = T.spawn(slot_x(i), SLOT_Y, CELL * 2.0, CELL * 1.4, 0.3, 0.3, 0.34, 1)
      slot_shown[i] = nil
    end
    for i = 1, 6 do
      tray_bg[i] = T.spawn(tray_x(i), TRAY_Y, CELL * 1.25, CELL * 1.1, 0.22, 0.22, 0.26, 1)
      tray_shown[i] = nil
    end
  end

  -- Update slot/tray tiles; only respawn a number label when it actually changes
  -- (no Text2d update API — a changed label = despawn + respawn, so bound churn).
  local function refresh_hud()
    for i = 1, SLOTS do
      local s = slots[i]
      if s then local c = palette(s.color); game.set_color(slot_bg[i], c[1], c[2], c[3], 1)
      else game.set_color(slot_bg[i], 0.3, 0.3, 0.34, 1) end
      local lbl = s and tostring(s.n) or ""
      if lbl ~= slot_shown[i] then
        if slot_txt[i] then game.despawn(slot_txt[i]) end
        slot_txt[i] = (lbl ~= "") and T.text(slot_x(i), SLOT_Y, 22, 1, 1, 1, 1, lbl) or nil
        slot_shown[i] = lbl
      end
    end
    for i = 1, 6 do
      local b = tray[i]
      if b then local c = palette(b.color); game.set_color(tray_bg[i], c[1], c[2], c[3], 1)
      else game.set_color(tray_bg[i], 0.22, 0.22, 0.26, 1) end
      local lbl = b and tostring(b.n) or ""
      if lbl ~= tray_shown[i] then
        if tray_txt[i] then game.despawn(tray_txt[i]) end
        tray_txt[i] = (lbl ~= "") and T.text(tray_x(i), TRAY_Y, 18, 1, 1, 1, 1, lbl) or nil
        tray_shown[i] = lbl
      end
    end
  end

  -- ---- ants ----------------------------------------------------------------
  local function spawn_ant(slot_i)
    local col = { 0.15, 0.12, 0.12 }
    local id = T.sprite(NESTX, NESTY, CELL * 0.5, CELL * 0.5, "villager")
    game.set_color(id, col[1], col[2], col[3], 1)
    ants[#ants + 1] = { id = id, slot = slot_i, state = "idle", x = NESTX, y = NESTY, pi = 1, path = nil, tr = 0, tc = 0 }
  end

  local function pick_target(color)
    if dirty then recompute_field() end
    -- nearest reachable frontier cell of this colour (min field dist to a neighbour)
    local bestr, bestc, bestd
    for r = 1, H do for c = 1, W do
      if grid[r][c] == color and not reserved[(r - 1) * W + c] then
        for _, p in ipairs({ {r+1,c},{r-1,c},{r,c+1},{r,c-1} }) do
          local rr, cc = p[1], p[2]
          if passable(rr, cc) then
            local d = dist[node(rr, cc)]
            if d ~= nil and (bestd == nil or d < bestd) then bestd = d; bestr, bestc = r, c end
          end
        end
      end
    end end
    return bestr, bestc
  end

  local function move_along(a, dt)
    local step = ANT_SPEED * dt * (speed2 and 2 or 1)
    local pts = a.path
    while step > 0 and a.pi < #pts do
      local nx, ny = pts[a.pi + 1][1], pts[a.pi + 1][2]
      local dx, dy = nx - a.x, ny - a.y
      local d = math.sqrt(dx * dx + dy * dy)
      if d <= step then a.x, a.y, a.pi, step = nx, ny, a.pi + 1, step - d
      else a.x, a.y, step = a.x + dx / d * step, a.y + dy / d * step, 0 end
    end
    game.move_to(a.id, a.x, a.y)
    return a.pi >= #pts
  end

  local function update_ant(a, dt)
    local s = slots[a.slot]
    if a.state == "idle" then
      if not s or s.n <= 0 then return end
      local r, c = pick_target(s.color)
      if not r then return end
      local p = path_to(r, c)
      if not p then return end
      reserved[(r - 1) * W + c] = true
      a.tr, a.tc, a.path, a.pi, a.state = r, c, p, 1, "out"
    elseif a.state == "out" then
      if move_along(a, dt) then
        -- arrived: carry the pixel away
        if grid[a.tr][a.tc] ~= 0 then
          clear_cell(a.tr, a.tc)
          if s then s.n = s.n - 1 end
          game.play_sound("hit"); game.shake(0.03)
        end
        reserved[(a.tr - 1) * W + a.tc] = nil
        -- return path = reverse of the outbound path
        local rev = {}
        for i = #a.path, 1, -1 do rev[#rev + 1] = a.path[i] end
        a.path, a.pi, a.state = rev, 1, "back"
      end
    elseif a.state == "back" then
      if move_along(a, dt) then a.state = "idle" end
    end
  end

  -- ---- lifecycle -----------------------------------------------------------
  local function build(hw, hh)
    HW, HH = hw, hh
    CELL = math.min((2 * hw - 44) / W, (1.15 * hh) / H, CELL_CAP)
    OX = -W * CELL / 2
    TOPY = hh - 150
    NESTX, NESTY = cx(math.floor(W / 2) + 1), cy(H + 1)

    -- deep-copy grid
    grid, painted = {}, 0
    for r = 1, H do grid[r] = {} for c = 1, W do grid[r][c] = LEVEL.grid[r][c] end end
    tray = {}
    for i, b in ipairs(LEVEL.tray) do tray[i] = { color = b[1], n = b[2] } end
    slots, reserved, ants, dirty = {}, {}, {}, true
    playing, won, dead, speed2 = true, false, false, false

    draw_board()
    nest_id = T.sprite(NESTX, NESTY, CELL * 0.9, CELL * 0.9, "rock")
    game.set_color(nest_id, 0.18, 0.12, 0.09, 1)
    draw_hud()
    back = K.make_back(T, hw, hh)
    fill_slots()
    for i = 1, SLOTS do for _ = 1, ANTS_PER_SLOT do spawn_ant(i) end end
    recompute_field(); status(); built = true

    DEBUG = {
      game = "ant_clear", back = back,
      painted = function() return painted end,
      tray_len = function() return #tray end,
      won = function() return won end,
      dead = function() return dead end,
      reachable = function(col) return reachable_count(col) end,
      ant_xy = function() local o = {} for _, a in ipairs(ants) do o[#o + 1] = { a.x, a.y } end return o end,
      grid = function() return grid end,
      toggle_speed = function() speed2 = not speed2 end,
      -- strategy-layer hooks for the headless harness / autoplay
      set_mode = function(m) mode = m; fill_slots() end,
      free_slots = function() local n = 0 for i = 1, SLOTS do if slots[i] == nil then n = n + 1 end end return n end,
      load = function(ti) return load_tray(ti) end,
      tray_colors = function() local o = {} for _, b in ipairs(tray) do o[#o + 1] = b.color end return o end,
      slot_colors = function() local o = {} for i = 1, SLOTS do o[i] = slots[i] and slots[i].color or 0 end return o end,
    }
  end

  local function win()
    playing, won = false, true
    game.set_text("CLEARED!\nTap to replay")
    game.play_sound("score"); game.haptic("success"); game.shake(0.6); game.log("ant_clear win")
  end
  local function lose()
    playing, dead = false, true
    game.set_text("STUCK!\nTap to retry")
    game.play_sound("hit"); game.haptic("heavy"); game.shake(0.4); game.log("ant_clear stuck")
  end

  return {
    enter = function() built = false end,
    leave = function() T.clear(); ants = {}; built = false end,
    tap = function(x, y)
      if back and K.in_rect(back, x, y) then K.switch("menu"); return end
      if not playing then T.clear(); build(HW, HH); return end
      -- tap the nest to toggle 2x speed (the "speed x2" affordance)
      if math.abs(x - NESTX) < CELL and math.abs(y - NESTY) < CELL then
        speed2 = not speed2; game.play_sound("wall"); game.haptic("light"); return
      end
      -- manual: tap a tray tile to commit that colour to a free slot
      if mode == "manual" and free_slot() then
        for i = 1, 6 do
          if tray[i] and math.abs(x - tray_x(i)) <= CELL * 0.63
             and math.abs(y - TRAY_Y) <= CELL * 0.55 then
            if load_tray(i) then game.play_sound("hit"); game.haptic("light") end
            return
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
      -- clear empty slots so they can refill next frame
      for i = 1, SLOTS do if slots[i] and slots[i].n <= 0 then slots[i] = nil end end
      refresh_hud()
      status()
      if painted <= 0 then win()
      elseif check_dead() then lose() end
    end,
  }
end

PACKS = PACKS or {}
PACKS.ant_clear = {
  slot = 10, key = "ant_clear", label = "Ant Art", short = "Ant Art",
  icon = "villager", color = { 0.85, 0.35, 0.42 }, tier = "curated", make = make_ant_clear,
}
