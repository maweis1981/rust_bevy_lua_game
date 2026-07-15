-- bead_pop.lua — "Bead Pop": a premium bead-art pixel-painter.
--
-- A cute picture is shown as a ghost template of coloured bead-sockets. A tray of
-- faceted GEMS sits below; tap a gem and a glossy bead of that colour arcs up and
-- snaps into the next empty pixel of that colour — filling the picture bead by
-- bead. Tap useful colours in a row to build a COMBO; tap a finished colour and
-- the combo breaks. Complete the picture for a confetti payoff, then the next one.
--
-- Standalone game (its own /play/?game=bead_pop page). All art is the unified
-- glossy kit from tools/gen_beadpop_assets.py (bp_bead / bp_gem / bp_socket /
-- bp_bg / bp_panel), tinted per colour so one style covers everything.

local function make_bead_pop()
  local K = GAME_KIT
  local T = K.tracker()

  -- ---- pictures (shape-only pixel art; 0 = empty) + a premium palette each ----
  local PICS = {
    { name = "heart", w = 11, h = 10,
      pal = { {0.98,0.24,0.42}, {1.00,0.62,0.72}, {1.00,0.95,0.98} },  -- red / pink / shine
      grid = {
        {0,0,0,0,0,0,0,0,0,0,0},
        {0,1,1,0,0,0,0,1,1,0,0},
        {1,2,2,1,0,0,1,1,1,1,0},
        {1,2,3,1,1,1,1,1,1,1,1},
        {1,1,1,1,1,1,1,1,1,1,1},
        {1,1,1,1,1,1,1,1,1,1,1},
        {0,1,1,1,1,1,1,1,1,1,0},
        {0,0,1,1,1,1,1,1,1,0,0},
        {0,0,0,1,1,1,1,1,0,0,0},
        {0,0,0,0,1,1,1,0,0,0,0},
      } },
    { name = "cat", w = 13, h = 12,
      pal = { {0.24,0.24,0.30}, {1.00,0.97,0.94}, {1.00,0.55,0.68}, {0.35,0.86,0.92} }, -- ink/white/pink/cyan
      grid = {
        {1,1,0,0,0,0,0,0,0,0,0,1,1},
        {1,3,1,0,0,0,0,0,0,0,1,3,1},
        {1,1,1,1,1,1,1,1,1,1,1,1,1},
        {1,1,1,1,1,1,1,1,1,1,1,1,1},
        {1,2,2,1,1,1,1,1,1,1,2,2,1},
        {1,2,4,2,1,1,1,1,1,2,4,2,1},
        {1,2,2,1,1,1,1,1,1,1,2,2,1},
        {1,1,1,1,1,3,3,1,1,1,1,1,1},
        {1,1,1,1,1,1,1,1,1,1,1,1,1},
        {0,1,1,1,1,1,1,1,1,1,1,1,0},
        {0,0,1,1,1,1,1,1,1,1,1,0,0},
        {0,0,0,1,1,0,0,0,1,1,0,0,0},
      } },
    { name = "star", w = 11, h = 11,
      pal = { {1.00,0.82,0.18}, {1.00,0.62,0.10}, {1.00,0.96,0.72} },  -- gold / amber / light
      grid = {
        {0,0,0,0,0,3,0,0,0,0,0},
        {0,0,0,0,1,1,1,0,0,0,0},
        {0,0,0,0,1,3,1,0,0,0,0},
        {1,1,1,1,1,1,1,1,1,1,1},
        {0,1,1,1,1,1,1,1,1,1,0},
        {0,0,1,1,1,1,1,1,1,0,0},
        {0,0,1,1,1,1,1,1,1,0,0},
        {0,1,1,1,0,1,0,1,1,1,0},
        {0,1,1,0,0,1,0,0,1,1,0},
        {1,1,0,0,0,0,0,0,0,1,1},
        {2,0,0,0,0,0,0,0,0,0,2},
      } },
  }

  local HW, HH = 0, 0
  local cur = 1
  local W, H, PAL, GRID
  local CELL, OX, TOPY = 0, 0, 0
  local filled, cell_id = {}, {}       -- per cell: filled? and its bead sprite id
  local need = {}                       -- need[color] = remaining empty cells
  local total, done = 0, 0
  local flying = {}                     -- in-flight beads {id,x0,y0,x1,y1,t,dur,color,r,c}
  local GEM_COLS, GEM_ROWS = 5, 3
  local gems, gem_id, gem_x, gem_y, GEMW = {}, {}, {}, {}, 0
  local combo, best_combo = 0, 0
  local score = 0
  local prog_fill, prog_x0, prog_w, prog_y, prog_h
  local lvl_txt, score_txt, pct_txt, hint_txt, combo_txt, combo_t = nil, nil, nil, nil, nil, 0
  local tapped_once = false
  local playing, win_t = false, 0
  local built = false

  local function cx(c) return OX + (c - 0.5) * CELL end
  local function cy(r) return TOPY - (r - 0.5) * CELL end

  local function col(ci) return PAL[ci] or {1,1,1} end

  -- set_text is a single global; for independent labels we despawn + respawn
  local function retext(id, x, y, size, r, g, b, a, s)
    if id then game.despawn(id) end
    return T.text(x, y, size, r, g, b, a, s)
  end

  -- pick a gem colour: bias toward colours the picture still needs (keeps the
  -- tray useful) but sometimes drop a finished colour to reward attention.
  -- pick a gem colour, STRONGLY biased to colours the picture still needs so the
  -- tray never soft-locks (a tray with no needed colour would be un-tappable).
  local function roll_gem()
    local needed = {}
    for c = 1, #PAL do if (need[c] or 0) > 0 then needed[#needed + 1] = c end end
    if #needed == 0 then return math.random(1, #PAL) end
    if math.random() < 0.82 then return needed[math.random(1, #needed)] end
    return math.random(1, #PAL)
  end

  local function set_gem(i, c)
    gems[i] = c
    local cc = col(c)
    game.set_color(gem_id[i], cc[1], cc[2], cc[3], 1)
  end

  local function build(hw, hh)
    HW, HH = hw, hh
    T.clear(); flying = {}; combo = 0; win_t = 0; playing = true
    local P = PICS[(cur - 1) % #PICS + 1]
    W, H, PAL, GRID = P.w, P.h, P.pal, P.grid

    -- premium gradient stage
    local bg = T.sprite(0, 0, math.max(2*hw, 2*hh*768/1152) + 4, 2*hh + 4, "bp_bg")

    -- geometry: board fills the width, capped by the space above the gem tray
    local tray_top = -hh + 40 + GEM_ROWS * 0
    GEMW = math.min((2*hw - 40) / GEM_COLS - 8, 78)
    local tray_h = GEM_ROWS * (GEMW + 10)
    local tray_cy = -hh + 46 + tray_h/2
    local board_bottom = tray_cy + tray_h/2 + 40
    local board_top = hh - 118
    CELL = math.min((2*hw - 40) / W, (board_top - board_bottom) / H)
    OX = -W * CELL / 2
    TOPY = board_bottom + H * CELL

    -- HUD: level + score, then a clear progress capsule with a % readout
    lvl_txt = T.text(-hw + 42, hh - 34, 15, 1, 1, 1, 1, "LEVEL " .. cur)
    score_txt = T.text(hw - 40, hh - 34, 15, 1.0, 0.86, 0.35, 1, tostring(score))
    prog_w = 2*hw - 72; prog_x0 = -prog_w/2; prog_y = hh - 66; prog_h = 15
    local cap = T.sprite(0, prog_y, prog_w + 14, prog_h + 12, "bp_panel")
    game.set_color(cap, 0.14, 0.11, 0.26, 1)
    prog_fill = T.sprite(prog_x0, prog_y, 2, prog_h, "bp_panel")
    game.set_color(prog_fill, 0.42, 0.92, 0.62, 1)
    pct_txt = T.text(0, prog_y, 13, 0.10, 0.10, 0.22, 1, "0%")
    -- first-time hint (only level 1; fades on the first tap)
    hint_txt = nil
    if cur == 1 then hint_txt = T.text(0, tray_cy + tray_h/2 + 20, 15, 1, 1, 1, 0.9, "Tap gems to paint!") end

    -- board: sockets + ghost template beads
    _pct_shown, _idle, tapped_once = nil, 0, false
    filled, cell_id, need, total, done = {}, {}, {}, 0, 0
    for c = 1, #PAL do need[c] = 0 end
    for r = 1, H do filled[r], cell_id[r] = {}, {}
      for c = 1, W do
        local ci = GRID[r][c]
        if ci ~= 0 then
          T.sprite(cx(c), cy(r), CELL*0.96, CELL*0.96, "bp_socket")
          local ghost = T.sprite(cx(c), cy(r), CELL*0.78, CELL*0.78, "bp_bead")
          local cc = col(ci)
          game.set_color(ghost, cc[1], cc[2], cc[3], 0.22)   -- faint paint-by-number hint
          cell_id[r][c] = ghost
          filled[r][c] = false
          need[ci] = need[ci] + 1
          total = total + 1
        end
      end
    end

    -- gem tray
    gems, gem_id, gem_x, gem_y = {}, {}, {}, {}
    for row = 0, GEM_ROWS - 1 do
      for cc = 0, GEM_COLS - 1 do
        local i = row * GEM_COLS + cc + 1
        local gx = -(GEM_COLS-1)/2 * (GEMW + 8) + cc * (GEMW + 8)
        local gy = tray_cy + tray_h/2 - GEMW/2 - row * (GEMW + 10)
        gem_x[i], gem_y[i] = gx, gy
        gem_id[i] = T.sprite(gx, gy, GEMW, GEMW, "bp_gem")
        set_gem(i, roll_gem())
      end
    end
    built = true
  end

  -- find the next empty cell of colour `ci` (scan top->bottom for a tidy fill)
  local function next_cell(ci)
    for r = 1, H do for c = 1, W do
      if GRID[r][c] == ci and not filled[r][c] then return r, c end
    end end
    return nil
  end

  local function land(b)
    done = done + 1            -- cell was already RESERVED at launch (filled/need)
    score = score + 10 * math.max(1, b.combo)           -- combo multiplies the payoff
    score_txt = retext(score_txt, HW - 40, HH - 34, 15, 1.0, 0.86, 0.35, 1, tostring(score))
    -- the flying bead IS the filled bead: settle it, full colour, pop
    local cc = col(b.color)
    game.set_color(b.id, cc[1], cc[2], cc[3], 1)
    game.move_to(b.id, b.x1, b.y1)
    game.set_size(b.id, CELL*0.92, CELL*0.92)
    game.tween(b.id, nil, nil, 1.0, 0.18, "back", 0, 1.35)   -- squash-pop settle
    cell_id[b.r][b.c] = b.id
    game.emit("spark", b.x1, b.y1, 6)
    game.play_sound("score")
    game.haptic("light")
  end

  local function launch(color, sx, sy)
    local r, c = next_cell(color)
    if not r then                       -- colour already complete: break combo
      combo = 0
      game.play_sound("hit"); game.haptic("medium")
      return false
    end
    filled[r][c] = true                 -- RESERVE the cell now so the next launch
    need[color] = (need[color] or 1) - 1 -- picks a different cell (no bead stacking)
    combo = combo + 1; best_combo = math.max(best_combo, combo)
    if combo >= 3 then                  -- visible combo popup (grows with the streak)
      combo_txt = retext(combo_txt, 0, HH * 0.52, 15 + math.min(combo, 9), 1.0, 0.85, 0.3, 1, "COMBO x" .. combo)
      combo_t = 0.9
    end
    if combo % 5 == 0 then game.shake(0.24); game.emit("spark", 0, HH * 0.5, 10) end  -- burst by the combo text, not on the picture
    -- a fresh glossy bead flies from the tapped gem up to the target cell (TRACKED
    -- via T so it's despawned on the next build — no leftover beads across levels)
    local id = T.sprite(sx, sy, CELL*0.6, CELL*0.6, "bp_bead")
    local cc = col(color)
    game.set_color(id, cc[1], cc[2], cc[3], 1)
    game.set_layer(id, 40)              -- above the board while it flies
    flying[#flying + 1] = {
      id = id, x0 = sx, y0 = sy, x1 = cx(c), y1 = cy(r),
      t = 0, dur = 0.34, color = color, r = r, c = c, combo = combo,
    }
    return true
  end

  return {
    enter = function()
      cur = 1; score = 0; built = false
      if game.play_music then game.play_music("ac_bgm") end
    end,
    leave = function()
      T.clear(); flying = {}; built = false
      if game.stop_music then game.stop_music() end
    end,
    tap = function(x, y)
      if not playing then return end
      _idle = 0
      if not tapped_once then tapped_once = true
        if hint_txt then game.despawn(hint_txt); hint_txt = nil end
      end
      for i = 1, #gem_id do
        if math.abs(x - gem_x[i]) <= GEMW*0.6 and math.abs(y - gem_y[i]) <= GEMW*0.6 then
          if launch(gems[i], gem_x[i], gem_y[i]) then game.play_sound("ac_place") end
          -- ALWAYS consume + refill the tapped gem (even a wasted tap), so the
          -- tray can never fill up with un-tappable finished colours.
          game.tween(gem_id[i], nil, nil, 0.0, 0.12, "quad", 0, 1.0)
          set_gem(i, roll_gem())
          game.tween(gem_id[i], nil, nil, 1.0, 0.18, "back", 0.12, 0.2)
          return
        end
      end
    end,
    update = function(dt, hw, hh)
      if not built then build(hw, hh) end
      dt = math.min(dt, 1/30)



      -- advance in-flight beads along a parabolic arc, land on arrival
      for k = #flying, 1, -1 do
        local b = flying[k]
        b.t = b.t + dt
        local p = math.min(1, b.t / b.dur)
        local ease = 1 - (1 - p) * (1 - p)              -- ease-out along the path
        local x = b.x0 + (b.x1 - b.x0) * ease
        local hop = -math.abs(b.x1 - b.x0) * 0.35 - CELL * 2
        local y = b.y0 + (b.y1 - b.y0) * ease + hop * math.sin(math.pi * p)
        game.move_to(b.id, x, y)
        game.set_size(b.id, CELL * (0.6 + 0.34 * p), CELL * (0.6 + 0.34 * p))
        if p >= 1 then land(b); table.remove(flying, k) end
      end

      -- progress bar + % readout
      if prog_fill and total > 0 then
        local frac = done / total
        game.set_size(prog_fill, math.max(2, prog_w * frac), prog_h)
        game.move_to(prog_fill, prog_x0 + math.max(2, prog_w*frac)/2, prog_y)
        local pct = math.floor(frac * 100 + 0.5)
        if pct ~= _pct_shown then _pct_shown = pct
          pct_txt = retext(pct_txt, 0, prog_y, 24, 1, 1, 1, 1, pct .. "%") end
      end

      -- combo popup: hold briefly, then fade + drift up and clear
      if combo_txt then
        combo_t = combo_t - dt
        if combo_t <= 0 then game.despawn(combo_txt); combo_txt = nil end
      end
      -- combo resets if you pause too long between useful taps (keeps rhythm)
      _idle = (_idle or 0) + dt
      if playing and #flying == 0 and _idle > 2.5 and combo > 0 then combo = 0 end

      if playing and done >= total and #flying == 0 then
        playing = false; win_t = 0
        -- bonus for a clean run, and a star rating from the best combo
        local stars = best_combo >= total and 3 or (best_combo >= total * 0.4 and 2 or 1)
        score = score + 100 * stars
        score_txt = retext(score_txt, HW - 40, HH - 34, 15, 1.0, 0.86, 0.35, 1, tostring(score))
        local grade = stars == 3 and "PERFECT!" or (stars == 2 and "GREAT!" or "NICE!")
        retext(nil, 0, HH * 0.30, 34, 1.0, 0.92, 0.4, 1, "COMPLETE!")
        retext(nil, 0, HH * 0.30 - 34, 22, 0.6, 1.0, 0.7, 1, grade)
        game.play_sound("ac_win"); game.haptic("success"); game.shake(0.6); game.zoom(0.7)
        -- celebratory pop: every placed bead does a little bounce
        for r = 1, H do for c = 1, W do
          if cell_id[r][c] then game.tween(cell_id[r][c], nil, nil, 1.0, 0.4, "back", (r+c)*0.02, 1.4) end
        end end
      end

      if not playing then
        win_t = win_t + dt
        if math.floor((win_t) / 0.28) ~= math.floor((win_t - dt) / 0.28) and win_t < 1.8 then
          game.emit("confetti", (math.random()*2-1)*hw*0.7, (math.random()*2-1)*hh*0.4, 14)
          game.play_sound("ac_deposit")
        end
        if win_t >= 2.6 then cur = cur + 1; built = false end
      end
    end,
  }
end

PACKS = PACKS or {}
PACKS.bead_pop = {
  slot = 11, key = "bead_pop", label = "Bead Pop", short = "Bead Pop",
  icon = "orb", color = { 0.62, 0.42, 0.95 }, tier = "curated", make = make_bead_pop,
}
