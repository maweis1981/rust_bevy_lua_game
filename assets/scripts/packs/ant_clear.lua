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

  -- ---- levels (generated: tools/gen_level.py, all validated solvable@4) -----
  -- Shared FOOD palette: 1 chocolate, 2 bread, 3 sugar, 4 berry, 5 mint. Every
  -- picture is a food mosaic the colony hauls off crumb by crumb. Progression
  -- is saved (game.save "ant_clear_lvl") and wraps around.
  local LEVELS = {
    { -- 1: the approved-mockup FOX on a mint backdrop (full-rectangle mosaic)
      slots = 4, w = 16, h = 13,
      grid = {
        {5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5},
        {5,2,5,5,5,5,5,5,5,5,5,5,5,5,2,5},
        {5,2,2,5,5,5,5,5,5,5,5,5,5,2,2,5},
        {5,2,2,2,5,5,5,5,5,5,5,5,2,2,2,5},
        {5,2,2,2,2,5,5,5,5,5,5,2,2,2,2,5},
        {5,2,2,2,2,2,2,2,2,2,2,2,2,2,2,5},
        {5,2,2,2,1,2,2,2,2,2,2,1,2,2,2,5},
        {5,2,3,3,2,2,2,2,2,2,2,2,3,3,2,5},
        {5,2,4,3,3,2,2,1,1,2,2,3,3,4,2,5},
        {5,2,3,3,3,3,3,1,1,3,3,3,3,3,2,5},
        {5,2,2,3,3,3,3,4,4,3,3,3,3,2,2,5},
        {5,5,2,2,3,3,3,3,3,3,3,3,2,2,5,5},
        {5,5,5,5,2,2,2,2,2,2,2,2,5,5,5,5},
      },
      tray = { {5,8},{5,8},{5,8},{5,8},{5,8},{5,8},{5,8},{5,8},{2,8},{2,8},{2,8},{2,8},{2,8},{2,8},{5,8},{2,8},{2,8},{3,8},{2,8},{3,8},{3,8},{5,8},{2,8},{3,8},{1,6},{4,4},{5,4},{3,2} },
    },
    { -- 2: strawberry-iced DONUT with sprinkles (enclosed hole = extra strategy)
      slots = 4, w = 20, h = 17,
      grid = {
        {0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0},
        {0,0,0,0,0,0,4,4,4,4,4,4,4,4,0,0,0,0,0,0},
        {0,0,0,0,4,4,4,4,4,4,4,3,4,4,4,4,0,0,0,0},
        {0,0,0,4,4,4,4,4,5,4,4,4,4,4,4,4,4,0,0,0},
        {0,0,4,4,3,4,4,4,4,4,4,4,4,4,4,4,5,4,0,0},
        {0,5,4,4,4,4,4,4,4,4,4,4,3,4,4,4,4,4,4,0},
        {0,4,4,4,4,4,4,4,4,0,0,4,4,4,4,4,4,4,4,0},
        {0,4,4,2,4,3,2,0,0,0,0,0,0,2,4,4,4,5,4,0},
        {0,4,2,2,4,2,2,0,0,0,0,0,0,2,4,2,2,4,4,0},
        {0,4,2,2,2,2,2,0,0,0,0,0,0,2,2,2,2,4,2,0},
        {0,2,2,2,2,2,2,2,2,0,0,2,2,2,2,2,2,2,2,0},
        {0,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,0},
        {0,0,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,0,0},
        {0,0,0,1,1,1,1,1,1,1,1,1,1,1,1,1,1,0,0,0},
        {0,0,0,0,1,1,1,1,1,1,1,1,1,1,1,1,0,0,0,0},
        {0,0,0,0,0,0,1,1,1,1,1,1,1,1,0,0,0,0,0,0},
        {0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0},
      },
      tray = { {4,8},{4,8},{4,8},{4,8},{4,8},{4,8},{4,8},{4,8},{4,8},{2,8},{2,8},{2,8},{2,8},{2,8},{4,8},{2,8},{2,8},{1,8},{1,8},{1,8},{2,8},{4,8},{1,8},{2,6},{3,4},{4,4},{5,4},{1,2} },
    },
    { -- 3: the CAT (hand-authored pixel art; interior colours buried)
      slots = 4, w = 20, h = 17,
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
    },
    { -- 4: a cookie HEART (3 colours: chocolate body, bread point, sugar shine)
      slots = 4, w = 16, h = 14,
      grid = {
        {0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0},
        {0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0},
        {0,0,1,3,3,3,1,0,0,1,1,1,1,1,0,0},
        {0,1,3,3,3,3,3,1,1,1,1,1,1,1,1,0},
        {0,1,3,3,3,3,3,1,1,1,1,1,1,1,1,0},
        {1,1,3,3,3,3,3,1,1,1,1,1,1,1,1,1},
        {1,1,3,3,3,3,3,1,1,1,1,1,1,1,1,1},
        {0,1,1,1,1,1,1,1,1,1,1,1,1,1,1,0},
        {0,1,1,1,1,1,1,1,1,1,1,1,1,1,1,0},
        {0,0,1,1,1,1,1,1,1,1,1,1,1,1,0,0},
        {0,0,1,1,1,1,1,1,1,1,1,1,1,1,0,0},
        {0,0,0,2,2,2,2,2,2,2,2,2,2,0,0,0},
        {0,0,0,0,2,2,2,2,2,2,2,2,0,0,0,0},
        {0,0,0,0,0,0,2,2,2,2,0,0,0,0,0,0},
      },
      tray = { {1,8},{1,8},{1,8},{1,8},{1,8},{1,8},{1,8},{1,8},{1,8},{1,8},{3,8},{1,8},{3,8},{1,8},{2,8},{2,8},{3,7},{2,6},{1,3} },
    },
    { -- 5: a SMILEY cookie (chocolate face details on a bread base)
      slots = 4, w = 15, h = 14,
      grid = {
        {0,0,0,0,0,0,0,0,0,0,0,0,0,0,0},
        {0,0,0,0,1,1,1,1,1,1,1,0,0,0,0},
        {0,0,0,1,1,1,1,1,1,1,1,1,0,0,0},
        {0,0,1,1,1,1,1,1,1,1,1,1,1,0,0},
        {0,0,1,1,1,1,1,1,1,1,1,1,1,0,0},
        {0,1,1,1,2,2,1,1,1,2,2,1,1,1,0},
        {0,1,1,1,1,1,1,1,1,1,1,1,1,1,0},
        {0,1,1,1,1,1,1,1,1,1,1,1,1,1,0},
        {0,1,1,3,2,1,1,1,1,1,2,3,1,1,0},
        {0,0,1,1,2,1,1,1,1,1,2,1,1,0,0},
        {0,0,1,1,2,2,2,1,2,2,2,1,1,0,0},
        {0,0,0,1,1,1,2,2,2,1,1,1,0,0,0},
        {0,0,0,0,1,1,1,1,1,1,1,0,0,0,0},
        {0,0,0,0,0,0,0,0,0,0,0,0,0,0,0},
      },
      tray = { {1,8},{1,8},{1,8},{1,8},{1,8},{1,8},{1,8},{1,8},{1,8},{1,8},{1,8},{1,8},{2,8},{1,8},{2,8},{1,5},{3,2},{2,1} },
    },
  }
  local cur_lvl = 1
  local LEVEL = LEVELS[1]
  local PALETTE5 = { {0.290,0.180,0.125}, {1.000,0.624,0.110}, {1.000,0.953,0.863}, {1.000,0.353,0.416}, {0.224,0.788,0.722} }

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
  -- FAKE PERSPECTIVE (the mockup's 3D tabletop look): rows shrink and converge
  -- toward a vanishing point as they recede. PS[r] = scale of row r, ROWY[r] =
  -- its centre-line. Filled in build(); identity until then. Ant paths go
  -- through cx/cy too, so the swarm walks the same tilted table.
  local PS, ROWY = {}, {}
  local PERSP = 0.30            -- how much the far (top) row shrinks
  local function rs(r) return PS[r] or 1 end
  local function cx(c, r) return (OX + (c - 0.5) * CELL) * rs(r or H) end
  local function cy(r) return ROWY[r] or (TOPY - (r - 0.5) * CELL) end

  -- ---- flow field over an open ring (rows/cols 0..H+1, 0..W+1) -------------
  -- NW/NEST are level-sized; re-derived in build() when the level changes.
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
        pts[#pts + 1] = { cx(c, r), cy(r) }
      end
    end
    pts[#pts + 1] = { cx(tc, tr), cy(tr) }
    return pts
  end

  -- ---- slots / tray / ants -------------------------------------------------
  local tray, slots, reserved, ants = {}, {}, {}, {}
  local NCOL, QROWS = 4, 3              -- queue = 4 fixed columns, 3 rows visible
                                        -- (denser tray, like the approved mockup)
  local cols = { {}, {}, {}, {} }       -- each column is a stack; only the head loads
  local col_adv = {}                    -- per-column slide-up animation timer
  local slot_pulse = {}   -- brief scale bump when a slot's count ticks down
  local playing, won, stuck, speed2 = true, false, false, false
  local dispatch_cd = 0        -- ants leave the nest ONE AT A TIME (single file)
  local DISPATCH_GAP = 0.45    -- seconds between departures
  local muted = false          -- sound toggle (music + sfx)
  local win_t = 0              -- celebration timer -> auto-advance to next level
  local HW, HH, built = 0, 0, false
  local back, was_stuck = nil, false
  local palette = PALETTE5

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
  -- Each colour is a REAL food object (rendered sprites, not tinted cubes):
  -- the picture/queue/carried blocks read as actual chocolate/bread/sugar/candy.
  local FOOD = { "food_choc", "food_bread", "food_sugar", "food_berry", "food_mint" }
  -- BOARD cells use flat matte tiles (cell_<food>_<1..4>, tools/board_cells.py):
  -- no per-cell shadow, four texture variants so same-colour runs don't repeat —
  -- the mosaic reads as ONE continuous picture, like the reference.
  local CFOOD = { "choc", "bread", "sugar", "berry", "mint" }

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
          -- flat matte cell, one of four texture variants (deterministic pick) so
          -- same-colour runs never repeat; sized to the pitch for thin even seams
          local v = (r * 7 + c * 13) % 4 + 1
          local id = T.sprite(cx(c, r), cy(r), CELL * rs(r) * 1.02, CELL * rs(r) * 1.02,
                              "cell_" .. CFOOD[ci] .. "_" .. v)
          -- level intro: each block POPS in (0 -> overshoot -> 1), staggered in a
          -- diagonal wave across the picture — the board builds itself in ~1s
          game.tween(id, nil, nil, 1.0, 0.30, "back", (r + c) * 0.028, 0)
          -- depth lighting (receding rows darker) + tiny per-cell tone jitter so
          -- the surface reads organic, not printed
          local k = (1 - 0.30 * (1 - rs(r))) * (0.94 + 0.06 * (((r * 31 + c * 17) % 7) / 6))
          game.set_color(id, k, k, k, 1)
          cell_id[r][c] = id; painted = painted + 1
        end
      end
    end
  end
  local function clear_cell(r, c)
    local id = cell_id[r][c]
    if id then game.despawn(id); cell_id[r][c] = nil end
    grid[r][c] = 0; painted = painted - 1; dirty = true
    game.emit("spark", cx(c, r), cy(r), 4)
  end

  -- ---- ants (spritesheet walk + facing + carry) ---------------------------
  local function spawn_ant(slot_i)
    local sh = game.spawn_sprite(NESTX, NESTY, CELL * ANT_SIZE * 0.9, CELL * ANT_SIZE * 0.6, "ant_shadow")
    game.set_color(sh, 1, 1, 1, 0.5)
    -- SKELETAL ant (assets/rigs/ant.rig): a body part + six legs driven by a
    -- looping tripod-gait clip, so the legs genuinely walk. The rig root scales
    -- the authored 156px body down to the game's ant size; set_color on the
    -- root tints every bone (species colour) — the engine propagates it.
    local id = game.spawn_rig(NESTX, NESTY, "ant", CELL * ANT_SIZE / 110)
    game.play_anim(id, "walk")
    ants[#ants + 1] = { id = id, shadow = sh, slot = slot_i, state = "idle", x = NESTX, y = NESTY,
                        pi = 1, path = nil, tr = 0, tc = 0, anim = 0, carry = nil, cc = 0, tintc = -1,
                        phase = (#ants % 8) * 0.8, dust = 0 }
  end
  -- Colour each ant to its slot's colour (a red slot -> red ants), so the swarm
  -- reads as "these ants are carrying THIS colour". Only re-set on change.
  -- ANT SPECIES BY COLOUR: ant_hero.png is a light luminance master, so tinting
  -- it turns the whole ant into a different-coloured species (chocolate ants haul
  -- chocolate, sugar-white ants haul sugar, ...). Idle ants with no slot rest as
  -- a natural warm brown. Only re-set on change.
  local IDLE_ANT = { 0.62, 0.42, 0.28 }
  local function tint_ant(a)
    local s = slots[a.slot]
    local ci = s and s.color or 0
    if ci ~= a.tintc then
      if ci == 0 then game.set_color(a.id, IDLE_ANT[1], IDLE_ANT[2], IDLE_ANT[3], 1)
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
    a.anim = (a.anim + moved * 0.16) % 8   -- drives the sway timing (single sprite, no frames)
    -- gentle side-to-side meander perpendicular to travel (visual only — logical
    -- position stays on the path), plus little dust puffs while walking.
    local tdx, tdy = a.x - sx0, a.y - sy0
    local tl = math.sqrt(tdx * tdx + tdy * tdy)
    local rx, ry = a.x, a.y
    if tl > 0.01 then
      local px, py = -tdy / tl, tdx / tl
      -- TWO-WAY ANT ROAD: everyone shares one trail; outbound ants keep to one
      -- side, returning ants to the other, so opposite streams pass cleanly.
      local lane = (a.state == "out" and 1 or -1) * CELL * 0.24
      local sway = math.sin(a.anim * 0.85 + a.phase) * CELL * 0.12
      rx, ry = a.x + px * (sway + lane), a.y + py * (sway + lane)
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
      if dispatch_cd > 0 then return end   -- single file: one ant leaves at a time
      local r, c = pick_target(s.color); if not r then return end
      local p = path_to(r, c); if not p then return end
      reserved[(r-1)*W+c] = true
      s.n = s.n - 1                     -- reserve the count at DISPATCH so a slot
      slot_pulse[a.slot] = 1            -- animate the count tick-down
      a.emerge = 0                      -- scale-in as it leaves the nest
      dispatch_cd = DISPATCH_GAP        -- next ant waits its turn at the nest
      a.tr, a.tc, a.path, a.pi, a.state = r, c, p, 1, "out"   -- never over-sends ants
    elseif a.state == "out" then
      if move_along(a, dt) then
        if grid[a.tr][a.tc] ~= 0 then
          a.cc = grid[a.tr][a.tc]
          clear_cell(a.tr, a.tc)
          a.carry = game.spawn_sprite(a.x, a.y - CELL * 0.5, CELL * 0.72, CELL * 0.72, FOOD[a.cc])
          a.carry_t = 0                 -- pop the picked morsel up from nothing
          game.shake(0.02); game.haptic("light")   -- grab: subtle (deposit is the sound)
        end
        reserved[(a.tr-1)*W+a.tc] = nil
        local rev = {}
        for i = #a.path, 1, -1 do rev[#rev + 1] = a.path[i] end
        a.path, a.pi, a.state = rev, 1, "back"
      end
    elseif a.state == "back" then
      if move_along(a, dt) then
        if a.carry then
          game.despawn(a.carry); a.carry = nil
          game.play_sound("ac_deposit")
          game.emit("spark", NESTX, NESTY - CELL * 0.4, 5)   -- deposit sparkle at the hole
          game.zoom(0.12)                                     -- tiny satisfying punch
        end
        a.state = "idle"
      end
    end
  end

  -- ---- HUD tiles (slots + tray) -------------------------------------------
  local slot_bg, slot_txt, slot_bug, tray_bg, tray_txt, tray_bug = {}, {}, {}, {}, {}, {}
  local slot_food = {}                 -- mini food sprite sitting in each spice box
  local slot_shown, tray_shown = {}, {}
  local coin_num, coin_shown           -- bitmap-digit LIVE score (cleared blocks)
  local coin_x, coin_y = 0, 0          -- where the score digits sit (set in build)
  local lvl_num                        -- bitmap-digit level number (in the badge)
  local prog_x0, prog_w, prog_fill, prog_stars = 0, 1, nil, {}   -- star progress bar
  local prog_y, prog_h = 0, 8          -- fill centre-line + thickness (set in build)
  local prog_star_pos = {}             -- bar-star coordinates (win-show flight targets)
  local drifters = {}                  -- ambient floating leaves/motes (bg motion)
  local buttons = {}                   -- tappable UI buttons with press-state feedback

  -- Register a pill button for press feedback + hit-testing. `sel` (optional) is
  -- a predicate → the button shows a lit "selected" state while it returns true
  -- (e.g. speed x2 while active); `on_tap` runs when it's pressed.
  local function add_button(id, rect, base, on_tap, sel)
    buttons[#buttons + 1] = { id = id, rect = rect, base = base, pulse = 0, on_tap = on_tap, sel = sel }
  end
  -- Ease each button back from its last press; pressed = darker (pushed in),
  -- selected = brighter (lit). Runs every frame so it animates on the win card too.
  local function update_buttons(dt)
    for _, b in ipairs(buttons) do
      b.pulse = math.max(0, b.pulse - dt * 6)
      local k = 1 - 0.28 * b.pulse                       -- press darkens
      local lift = (b.sel and b.sel()) and 0.16 or 0     -- selected brightens toward white
      game.set_color(b.id, b.base[1] * k + lift, b.base[2] * k + lift, b.base[3] * k + lift, 1)
    end
  end
  -- Hit-test the buttons; on a press, pulse + fire on_tap. Returns true if consumed.
  local function press_button(x, y)
    for _, b in ipairs(buttons) do
      if K.in_rect(b.rect, x, y) then
        b.pulse = 1; game.play_sound("ac_load"); game.haptic("light")
        if b.on_tap then b.on_tap() end
        return true
      end
    end
    return false
  end

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
    num_free(lvl_num); lvl_num = nil
    prog_fill, prog_stars = nil, {}   -- tracker-owned sprites; drop stale refs
    for _, d in ipairs(drifters) do game.despawn(d.id) end; drifters = {}
    buttons = {}   -- pill sprites are tracker-owned (T.clear despawns them); drop stale refs
  end
  local QYGAP = 6
  local function slot_x(i) return (i - (SLOTS + 1) / 2) * (SLOT_W + 8) end
  local function col_x(c) return (c - (NCOL + 1) / 2) * (TRAY_W + 8) end
  local function row_y(row) return TRAY_Y - row * (TRAY_W + QYGAP) end   -- row 0 = head (top)
  local function qi(c, row) return (c - 1) * QROWS + row + 1 end          -- 0-based row

  local function draw_hud()
    -- CLEAN trays (empty Floniks wooden trays), drawn as 9-SLICE panels so the
    -- rounded rim stays native-crisp at any stretch (a plain scaled sprite blurs)
    local strip_w = SLOTS * (SLOT_W + 8) + 44
    T.panel(0, SLOT_Y, strip_w, SLOT_W + 26, "tray_wood", 60)
    local q_cy = (row_y(0) + row_y(QROWS - 1)) / 2
    local q_w = NCOL * (TRAY_W + 8) + 44
    local q_h = QROWS * (TRAY_W + QYGAP) + 26
    T.panel(0, q_cy, q_w, q_h, "tray_wood", 60)
    for i = 1, SLOTS do
      -- slot sockets are BAKED into the sliced strip; slot_bg is a dark cover
      -- that hides the baked colour block while the slot is empty
      slot_bg[i] = T.sprite(slot_x(i), SLOT_Y, SLOT_W * 0.92, SLOT_W * 0.80, "tile_sq")
      game.set_color(slot_bg[i], 0.26, 0.16, 0.10, 1)
      slot_shown[i] = nil
    end
    for c = 1, NCOL do for row = 0, QROWS - 1 do
      local i = qi(c, row)
      tray_bg[i] = nil            -- queue tiles are per-food sprites, spawned on demand
      tray_shown[i] = nil
    end end
  end
  local total_cells = 0   -- set in build; drives the star progress bar
  local function refresh_hud()
    -- star progress: fill tracks the cleared fraction; lit stars fade IN over
    -- the baked dark stars of the mockup strip at 1/3 2/3 3/3
    if prog_fill and total_cells > 0 then
      local frac = 1 - painted / total_cells
      local fw = math.max(1, prog_w * frac)
      game.set_size(prog_fill, fw, prog_h or 8)
      game.move_to(prog_fill, prog_x0 + fw / 2, prog_y or (HH - 34))
      for k = 1, 3 do
        if prog_stars[k] then
          if frac >= k / 3 - 0.001 then game.set_color(prog_stars[k], 1, 1, 1, 1)
          else game.set_color(prog_stars[k], 0.42, 0.32, 0.24, 1) end
        end
      end
      -- LIVE score: cleared blocks, as bitmap digits next to the coin
      local score = tostring(total_cells - painted)
      if score ~= coin_shown then
        num_free(coin_num)
        coin_num = num_make(score, 18, 1)
        coin_shown = score
      end
      num_place(coin_num, coin_x, coin_y)
    end
    for i = 1, SLOTS do
      local s = slots[i]
      -- count-tick pulse: bump the committed food briefly, then ease back
      local p = slot_pulse[i] or 0
      if slot_food[i] then
        if p > 0.01 then
          local sc = SLOT_W * 0.72 * (1 + 0.20 * p); game.set_size(slot_food[i], sc, sc)
          slot_pulse[i] = p * 0.82
        elseif slot_pulse[i] then
          game.set_size(slot_food[i], SLOT_W * 0.72, SLOT_W * 0.72); slot_pulse[i] = nil
        end
      end
      -- key includes the colour: respawn the food + markers when it changes
      local lbl = s and (tostring(s.n) .. ":" .. s.color) or ""
      if lbl ~= slot_shown[i] then
        num_free(slot_txt[i]); slot_txt[i] = nil
        if slot_food[i] then game.despawn(slot_food[i]); slot_food[i] = nil end
        if slot_bug[i] then game.despawn(slot_bug[i]); slot_bug[i] = nil end
        if s then
          -- the dark socket stays visible; the committed food sits IN it
          slot_food[i] = T.sprite(slot_x(i), SLOT_Y, SLOT_W * 0.72, SLOT_W * 0.72, FOOD[s.color])
          game.tween(slot_food[i], nil, nil, 1.0, 0.26, "back", 0, 0.3)   -- pop into the box
          slot_bug[i] = T.sprite(slot_x(i) - SLOT_W * 0.30, SLOT_Y + SLOT_W * 0.26, SLOT_W * 0.36, SLOT_W * 0.36, "ant_hero")
          tint(slot_bug[i], s.color)                 -- marker ant = the species colour
          slot_txt[i] = num_make(tostring(s.n), SLOT_W * 0.50, 1)
        end
        slot_shown[i] = lbl
      end
      num_place(slot_txt[i], slot_x(i) + SLOT_W * 0.16, SLOT_Y - SLOT_W * 0.16)
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
        -- key includes the colour: queue tiles are REAL food sprites, so a colour
        -- change (column advancing) respawns the tile with the right texture
        local lbl = b and (tostring(b.n) .. ":" .. b.color) or ""
        if lbl ~= tray_shown[i] then
          num_free(tray_txt[i]); tray_txt[i] = nil
          if tray_bg[i] then game.despawn(tray_bg[i]); tray_bg[i] = nil end
          if tray_bug[i] then game.despawn(tray_bug[i]); tray_bug[i] = nil end
          if b then
            tray_bg[i] = T.sprite(xx, yy, TRAY_W, TRAY_W, FOOD[b.color])
            game.set_color(tray_bg[i], 1, 1, 1, a)
            game.tween(tray_bg[i], nil, nil, 1.0, 0.24, "back", 0, 0.4)   -- pop on arrival
            tray_bug[i] = T.sprite(xx - TRAY_W * 0.26, yy + TRAY_W * 0.24, TRAY_W * 0.34, TRAY_W * 0.34, "ant_hero")
            tint(tray_bug[i], b.color, a)            -- marker ant = species colour
            tray_txt[i] = num_make(tostring(b.n), TRAY_W * 0.5, a)
          end
          tray_shown[i] = lbl
        end
        if tray_bg[i] then game.move_to(tray_bg[i], xx, yy) end
        if tray_bug[i] then game.move_to(tray_bug[i], xx - TRAY_W * 0.26, yy + TRAY_W * 0.24) end
        num_place(tray_txt[i], xx + TRAY_W * 0.06, yy - TRAY_W * 0.04)
      end
    end
  end

  local function status()
    if not SETTINGS.hud then return end
    -- only the stuck rescue prompt is ever shown; no idle hint text
    game.set_text(stuck and "卡住了 — 点一个满槽位取消(看广告)" or "")
  end

  -- ---- build ---------------------------------------------------------------
  local function build(hw, hh)
    HW, HH = hw, hh
    despawn_dynamic()   -- clear any leftover ants / bitmap digits before a rebuild
    -- pick the current level and re-derive the level-sized geometry
    LEVEL = LEVELS[((cur_lvl - 1) % #LEVELS) + 1]
    W, H = LEVEL.w, LEVEL.h
    NW = W + 2
    NEST = node(H + 1, math.floor(W / 2) + 1)

    -- ---- deterministic layout, stacked BOTTOM-UP so nothing ever overlaps ----
    local M = 26                       -- bottom margin (power-up bar removed)
    TRAY_W = math.min((2 * hw - 44) / 4 - 8, 54)
    SLOT_W = math.min((2 * hw - 60) / 5 - 8, 50)
    -- reserve QROWS visible queue rows above the bar (head row at the top)
    local q_bot = -hh + M + 14 + TRAY_W / 2                 -- bottom queue row centre
    TRAY_Y = q_bot + (QROWS - 1) * (TRAY_W + 6)             -- head row (row 0, top)
    SLOT_Y = (TRAY_Y + TRAY_W / 2) + 38 + SLOT_W / 2        -- slots above the queue
                                                            -- (extra air so the two
                                                            -- wooden trays read apart)
    local HOLE_R = 30
    NESTY = SLOT_Y + SLOT_W / 2 + 30 + HOLE_R               -- hole above the slots
    local board_bottom = NESTY + HOLE_R + 46                -- roomy gap: ants exit here
    -- RESPONSIVE: the picture fills the screen width (like the reference), then
    -- is capped by whatever vertical space is left — it scales with the device,
    -- never a fixed size.
    local board_h = (hh - 82) - board_bottom                -- rest goes to the picture
    -- perspective rows total H*(1 - PERSP/2) cells of height, so CELL can grow
    -- to refill the reclaimed space (width cap is the near, full-size row)
    CELL = math.min((2 * hw - 18) / W, board_h / (H * (1 - PERSP / 2)))
    OX = -W * CELL / 2
    -- per-row scale (top row most shrunken) + stacked centre-lines, bottom-up
    PS, ROWY = {}, {}
    for r = 1, H do PS[r] = 1 - PERSP * (H - r) / math.max(1, H - 1) end
    local yy = board_bottom
    for r = H, 1, -1 do
      ROWY[r] = yy + CELL * PS[r] / 2
      yy = yy + CELL * PS[r]
    end
    TOPY = yy                                              -- top edge of the picture
    NESTX = cx(math.floor(W / 2) + 1, H)

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
    dispatch_cd = 0

    -- full-screen cozy background (generated art), behind everything
    T.sprite(0, 0, math.max(2 * hw, 2 * hh * 512 / 768) + 4, 2 * hh + 4, "game_bg")
    spawn_drifters()   -- ambient floating leaves/motes over the background
    -- full-screen vignette + warm grade, topmost among sprites (layer 90) but
    -- below the text tier — focuses the eye centre-screen, HUD text stays crisp
    local vig = T.sprite(0, 0, 2 * hw + 4, 2 * hh + 4, "vignette")
    game.set_layer(vig, 90)
    -- top status bar: SEPARATE live sprites (no baked values) — wooden plank,
    -- level badge + live digits, star progress groove, coin + live score
    local by = hh - 34
    local bar_w = 2 * hw - 16
    local bar_h = 46
    T.panel(0, by, bar_w, bar_h, "bar_wood", 34)
    local function bfx(f) return -bar_w / 2 + f * bar_w end -- fraction -> x
    T.sprite(bfx(0.09), by, bar_h * 1.25, bar_h * 1.25, "badge_wood")
    lvl_num = num_make(tostring(cur_lvl), bar_h * 0.46, 1)
    num_place(lvl_num, bfx(0.09), by)
    -- progress groove + live fill, then the three stars (dark until earned)
    prog_x0, prog_w = bfx(0.21), bar_w * (0.72 - 0.21)
    prog_y, prog_h = by, bar_h * 0.22
    local groove = T.sprite(prog_x0 + prog_w / 2, prog_y, prog_w, prog_h + 6, "tile_sq")
    game.set_color(groove, 0.22, 0.13, 0.08, 0.9)
    prog_fill = T.sprite(prog_x0, prog_y, 1, prog_h, "tile_sq")
    game.set_color(prog_fill, 1.0, 0.78, 0.20, 1)
    prog_stars, prog_star_pos = {}, {}
    for k, f in ipairs({ 0.38, 0.505, 0.63 }) do
      prog_stars[k] = T.sprite(bfx(f), by + 1, bar_h * 0.52, bar_h * 0.52, "icon_star")
      game.set_color(prog_stars[k], 0.42, 0.32, 0.24, 1)    -- unlit until earned
      prog_star_pos[k] = { bfx(f), by + 1 }                 -- flight targets (win show)
    end
    T.sprite(bfx(0.80), by, 28, 28, "icon_coin")
    coin_num, coin_shown = nil, nil                         -- live score (set in refresh)
    coin_x, coin_y = bfx(0.895), by
    -- ONE soft shadow under the whole picture (cells carry no per-cell shadow
    -- any more): a grounded contact shade, slightly deeper at the bottom edge
    local b_bot = ROWY[H] and (ROWY[H] - CELL * PS[H] / 2) or (TOPY - H * CELL)
    local panel = T.sprite(0, (TOPY + b_bot) / 2 - 3, W * CELL + 18, (TOPY - b_bot) + 20, "tile_sq")
    game.set_color(panel, 0.20, 0.12, 0.07, 0.22)
    local lip = T.sprite(0, b_bot - 4, W * CELL * PS[H] + 10, 10, "tile_sq")
    game.set_color(lip, 0.16, 0.10, 0.06, 0.28)
    -- nest hole (generated art). The unlock buttons and the shovel/bomb power-up
    -- buttons are removed for now (no function behind them yet).
    T.sprite(NESTX, NESTY, HOLE_R * 2.6, HOLE_R * 2.6, "hole")
    -- crumb debris: a few fallen morsels scattered under the picture (mockup decor)
    for k = 1, 6 do
      local fx = (math.random() * 2 - 1) * CELL * W * 0.42
      local fy = board_bottom - 10 - math.random() * 26
      local cr = T.sprite(fx, fy, CELL * (0.28 + math.random() * 0.22), CELL * (0.28 + math.random() * 0.22),
                          FOOD[math.random(1, #FOOD)])
      game.set_color(cr, 1, 1, 1, 0.9)
      game.set_rotation(cr, math.random() * 6.28)
    end

    draw_board()
    total_cells = painted            -- progress bar denominator (set once per build)
    draw_hud()
    -- back + sound: two small wooden medallions tucked under the bar's left end
    -- (the bar itself is badge · star progress · coin, exactly like the mockup)
    back = { x = -hw + 30, y = hh - 76, w = 38, h = 38 }
    T.sprite(back.x, back.y, back.w, back.h, "badge_wood")
    T.text(back.x, back.y, 17, 1.00, 0.96, 0.88, 1, "<")
    local snd_b = T.sprite(back.x + 44, back.y, 36, 36, "badge_wood")
    local snd_i = T.sprite(back.x + 44, back.y, 23, 23, "icon_sound")
    add_button(snd_b, { x = back.x + 44, y = back.y, w = 36, h = 36 }, { 1, 1, 1 }, function()
      muted = not muted
      local v = muted and 0 or 1
      game.set_volume("music", v); game.set_volume("sfx", v)
      game.set_color(snd_i, 1, 1, 1, muted and 0.25 or 1)
    end)
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
    playing, won, win_t = false, true, 0
    game.set_text("")                    -- no caption; the star show says it
    -- advance the saved progression; the celebration auto-advances into it
    cur_lvl = (cur_lvl % #LEVELS) + 1
    if game.save then game.save("ant_clear_lvl", cur_lvl) end
    game.play_sound("ac_win"); game.haptic("success"); game.shake(0.5); game.log("ant_clear win")
    game.zoom(0.6)
    -- WIN SHOW: three big stars rise from where the picture was and fly one by
    -- one into their bar sockets (overshoot ease), each launch with confetti
    local py = TOPY - 0.5 * CELL * H
    for k = 1, 3 do
      local sp = prog_star_pos[k]
      if sp then
        local st = T.sprite(0, py, 46, 46, "icon_star")
        game.tween(st, sp[1], sp[2], 0.55, 0.62, "back", 0.18 + (k - 1) * 0.34, 2.0)
      end
    end
    for i = 1, 6 do
      game.emit("confetti", (math.random() * 2 - 1) * CELL * W * 0.4,
                py + (math.random() * 2 - 1) * CELL * H * 0.3, 14)
    end
  end

  return {
    enter = function()
      built = false
      -- (assign first: a host whose `load` returns no values must read as nil)
      local saved = game.load and game.load("ant_clear_lvl")
      cur_lvl = tonumber(saved) or cur_lvl
      game.play_music("ac_bgm")
    end,
    leave = function() T.clear(); despawn_dynamic(); ants = {}; built = false; game.stop_music() end,
    tap = function(x, y)
      if back and K.in_rect(back, x, y) then K.switch("menu"); return end
      if not playing then T.clear(); build(HW, HH); return end
      if press_button(x, y) then return end   -- bottom bar + unlock buttons (press feedback)
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
      update_buttons(math.min(dt, MAX_DT))    -- ease button press/selected states
      if not playing then
        -- won: hold the celebration briefly, then AUTO-ADVANCE to the next level
        -- (no caption, no tap needed; a tap during the hold skips ahead)
        if won then
          local step = math.min(dt, MAX_DT)
          -- confetti keeps popping every ~0.35s while the star show plays
          if math.floor((win_t + step) / 0.35) ~= math.floor(win_t / 0.35) and win_t < 1.6 then
            game.emit("confetti", (math.random() * 2 - 1) * HW * 0.6,
                      (math.random() * 2 - 1) * HH * 0.3, 12)
            game.play_sound("ac_deposit")
          end
          win_t = win_t + step
          if win_t >= 2.8 then win_t = 0; T.clear(); build(HW, HH) end
        end
        return
      end
      dt = math.min(dt, MAX_DT)
      dispatch_cd = math.max(0, dispatch_cd - dt * (speed2 and 2 or 1))
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
