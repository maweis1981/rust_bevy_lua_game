-- block_blast.lua — "Block Blast": an 8x8 drag-and-place block puzzle.
--
-- Three random polyomino pieces sit in a tray; DRAG a piece onto the 8x8 board.
-- Completely filling a row or column clears it (10 pts/line, with a combo bonus
-- for multi-line clears and consecutive-turn streaks). Use all three pieces, then
-- get three more. If none of your pieces can fit anywhere, it's game over. No
-- rotation, no timer — pure spatial planning.
--
-- Standalone game. Real drag-and-drop via game.pointer() (x, y, down); all art is
-- the existing pixel kit (pixel_tile blocks + tile_sq grid), tinted per colour.

local function make_block_blast()
  local K = GAME_KIT
  local T = K.tracker()
  local N = 8

  -- ---- pieces: lists of {dr,dc} offsets (top-left normalized). No rotation in
  --      play; variety comes from including rotated variants as distinct shapes.
  local function rect(h, w)
    local c = {}
    for r = 0, h - 1 do for k = 0, w - 1 do c[#c + 1] = { r, k } end end
    return c
  end
  local SHAPES = {
    { { 0, 0 } },                                          -- dot
    rect(1, 2), rect(2, 1),                                -- 2-lines
    rect(1, 3), rect(3, 1),                                -- 3-lines
    rect(1, 4), rect(4, 1),                                -- 4-lines
    rect(1, 5), rect(5, 1),                                -- 5-lines
    rect(2, 2),                                            -- 2x2 square
    rect(3, 3),                                            -- 3x3 square
    rect(2, 3), rect(3, 2),                                -- rectangles
    { { 0, 0 }, { 1, 0 }, { 1, 1 } }, { { 0, 1 }, { 1, 0 }, { 1, 1 } },  -- L corners
    { { 0, 0 }, { 0, 1 }, { 1, 0 } }, { { 0, 0 }, { 0, 1 }, { 1, 1 } },
    { { 0, 0 }, { 1, 0 }, { 2, 0 }, { 2, 1 } },            -- L
    { { 0, 1 }, { 1, 1 }, { 2, 1 }, { 2, 0 } },            -- J
    { { 0, 0 }, { 0, 1 }, { 0, 2 }, { 1, 0 } },            -- L lying
    { { 0, 0 }, { 0, 1 }, { 0, 2 }, { 1, 2 } },            -- J lying
    { { 0, 0 }, { 0, 1 }, { 0, 2 }, { 1, 1 } },            -- T
    { { 0, 1 }, { 1, 0 }, { 1, 1 }, { 1, 2 } },            -- T up
    { { 0, 1 }, { 0, 2 }, { 1, 0 }, { 1, 1 } },            -- S
    { { 0, 0 }, { 0, 1 }, { 1, 1 }, { 1, 2 } },            -- Z
  }
  -- weighted bag: smaller pieces appear a bit more so boards stay playable
  local BAG = {}
  for i = 1, #SHAPES do
    local n = #SHAPES[i]
    local w = (n <= 2 and 3) or (n <= 4 and 3) or (n <= 6 and 2) or 1
    for _ = 1, w do BAG[#BAG + 1] = i end
  end
  local COLORS = {
    { 0.98, 0.55, 0.22 }, { 0.96, 0.30, 0.44 }, { 0.36, 0.80, 0.54 }, { 0.28, 0.62, 1.00 },
    { 0.66, 0.44, 0.96 }, { 1.00, 0.80, 0.26 }, { 0.24, 0.82, 0.86 },
  }

  -- ---- state --------------------------------------------------------------
  local board, bg, fg = {}, {}, {}       -- board[r][c] + cell sprite grids
  local tray, tp = {}, {}                -- tray[1..3] piece + its sprite pool
  local dpool = {}                       -- drag sprite pool (follows the finger)
  local prevprev = {}                    -- board cells tinted for the drop preview
  local score, best, combo, placed = 0, 0, 0, 0
  local playing, built, was_down = true, false, false
  local drag = nil                       -- { i = tray slot being dragged }
  local score_txt, msg = nil, nil
  local CELL, BX0, BY0 = 0, 0, 0
  local HW, HH, TRAY_Y = 0, 0, 0
  local tray_cx = {}
  local back = nil

  local function gx(c) return BX0 + (c - 0.5) * CELL end
  local function gy(r) return BY0 - (r - 0.5) * CELL end
  local function bounds(sh)
    local mr, mc = 0, 0
    for _, o in ipairs(sh) do mr = math.max(mr, o[1]); mc = math.max(mc, o[2]) end
    return mr + 1, mc + 1     -- height, width in cells
  end

  local function new_piece() return { shape = BAG[math.random(#BAG)], color = math.random(#COLORS) } end
  local function fits(sh, ar, ac)
    for _, o in ipairs(sh) do
      local r, c = ar + o[1], ac + o[2]
      if r < 1 or r > N or c < 1 or c > N or board[r][c] ~= 0 then return false end
    end
    return true
  end
  local function can_place_any(sh)
    for ar = 1, N do for ac = 1, N do if fits(sh, ar, ac) then return true end end end
    return false
  end

  -- ---- score text (respawn on change; set_text is global so per-widget needs it) --
  local function set_score()
    if score_txt then game.despawn(score_txt) end
    score_txt = game.spawn_text(0, HH - 40, 40, 1, 0.96, 0.86, 1, tostring(score))
  end

  -- ---- board fg render -----------------------------------------------------
  local function refresh_board()
    for r = 1, N do for c = 1, N do
      local v = board[r][c]
      if v ~= 0 then
        local col = COLORS[v]
        game.set_color(fg[r][c], col[1], col[2], col[3], 1)
      else
        game.set_color(fg[r][c], 1, 1, 1, 0)
      end
    end end
  end

  -- ---- tray render ---------------------------------------------------------
  local function draw_tray()
    for i = 1, 3 do
      local p = tray[i]
      local ids = tp[i]
      local k = 0
      if p and not (drag and drag.i == i) then
        local sh = SHAPES[p.shape]; local col = COLORS[p.color]
        local bh, bw = bounds(sh)
        local ts = math.min(TRAY_W / math.max(bw, 3.2), CELL * 0.62)   -- fit in the slot
        for _, o in ipairs(sh) do
          k = k + 1
          local id = ids[k]
          local x = tray_cx[i] + (o[2] - (bw - 1) / 2) * ts
          local y = TRAY_Y + ((bh - 1) / 2 - o[1]) * ts
          game.move_to(id, x, y); game.set_size(id, ts * 0.92, ts * 0.92)
          game.set_color(id, col[1], col[2], col[3], 1)
        end
      end
      for j = k + 1, #ids do game.set_color(ids[j], 1, 1, 1, 0) end
    end
  end

  local function refill()
    for i = 1, 3 do tray[i] = new_piece() end
    draw_tray()
  end

  -- ---- line clears ---------------------------------------------------------
  local function clear_lines()
    local full_r, full_c = {}, {}
    for r = 1, N do
      local f = true
      for c = 1, N do if board[r][c] == 0 then f = false; break end end
      if f then full_r[#full_r + 1] = r end
    end
    for c = 1, N do
      local f = true
      for r = 1, N do if board[r][c] == 0 then f = false; break end end
      if f then full_c[#full_c + 1] = c end
    end
    local lines = #full_r + #full_c
    if lines == 0 then combo = 0; return end
    for _, r in ipairs(full_r) do for c = 1, N do board[r][c] = 0 end end
    for _, c in ipairs(full_c) do for r = 1, N do board[r][c] = 0 end end
    combo = combo + 1
    -- 10 per line, quadratic multi-line bonus, plus a combo-streak multiplier
    local gain = (10 * lines + 10 * lines * (lines - 1)) * combo
    score = score + gain
    game.play_sound("ac_deposit"); game.haptic("success"); game.shake(0.12 + 0.06 * lines)
    for _ = 1, lines * 4 do
      game.emit("confetti", (math.random() * 2 - 1) * CELL * N * 0.45,
                BY0 - math.random() * CELL * N, 8)
    end
    refresh_board()
  end

  local function check_gameover()
    for i = 1, 3 do local p = tray[i]; if p and can_place_any(SHAPES[p.shape]) then return end end
    playing = false
    game.play_sound("ac_stuck"); game.haptic("heavy"); game.shake(0.4)
    if score > best then best = score; if game.save then game.save("bb_best", best) end end
    msg = game.spawn_text(0, CELL * 1.2, 42, 1.0, 0.42, 0.36, 1, "GAME OVER")
    game.spawn_text(0, -CELL * 1.2, 22, 1, 0.96, 0.86, 1, "BEST " .. best .. " - TAP TO RETRY")
  end

  local function place(i, ar, ac)
    local p = tray[i]; local sh = SHAPES[p.shape]
    for _, o in ipairs(sh) do board[ar + o[1]][ac + o[2]] = p.color end
    placed = placed + #sh; score = score + #sh
    tray[i] = false
    game.play_sound("ac_place"); game.haptic("light")
    refresh_board()
    clear_lines()
    if not (tray[1] or tray[2] or tray[3]) then refill() end
    set_score(); draw_tray()
    check_gameover()
  end

  -- ---- drag preview: tint the target board cells green (valid) / red (blocked) --
  local function clear_preview()
    for _, rc in ipairs(prevprev) do
      local r, c = rc[1], rc[2]
      game.set_color(bg[r][c], 0.16, 0.15, 0.20, 1)
    end
    prevprev = {}
  end

  local function build(hw, hh)
    HW, HH = hw, hh; built = true
    T.clear()
    if best == 0 and game.load then best = tonumber(game.load("bb_best")) or 0 end
    board = {}
    for r = 1, N do board[r] = {} for c = 1, N do board[r][c] = 0 end end
    score, combo, placed, playing = 0, 0, 0, true
    if msg then msg = nil end
    game.set_text("")

    -- background
    local bgspr = T.sprite(0, 0, 2 * hw + 8, 2 * hh + 8, "bp_bg")
    game.set_color(bgspr, 0.5, 0.52, 0.62, 1)

    -- geometry: board fills most of the width, sits in the upper-middle
    CELL = (2 * hw - 40) / N
    BX0 = -N * CELL / 2
    BY0 = hh - 120                                  -- top edge of the board
    local bcy = BY0 - N * CELL / 2
    -- board frame
    local fr = T.sprite(0, bcy, N * CELL + 22, N * CELL + 22, "bp_panel")
    game.set_color(fr, 0.24, 0.24, 0.32, 1)
    -- cells
    bg, fg = {}, {}
    for r = 1, N do bg[r] = {}; fg[r] = {}
      for c = 1, N do
        bg[r][c] = T.sprite(gx(c), gy(r), CELL * 0.96, CELL * 0.96, "tile_sq")
        game.set_color(bg[r][c], 0.16, 0.15, 0.20, 1)
        fg[r][c] = T.sprite(gx(c), gy(r), CELL * 0.92, CELL * 0.92, "pixel_tile")
        game.set_color(fg[r][c], 1, 1, 1, 0)
      end
    end

    -- tray: 3 slots below the board
    TRAY_W = (2 * hw - 40) / 3
    TRAY_Y = -hh + 150
    tray_cx = { -TRAY_W, 0, TRAY_W }
    tp = {}
    for i = 1, 3 do
      local sl = T.sprite(tray_cx[i], TRAY_Y, TRAY_W * 0.92, TRAY_W * 0.78, "bp_panel")
      game.set_color(sl, 0.22, 0.22, 0.30, 1)
      tp[i] = {}
      for _ = 1, 9 do
        local id = T.sprite(0, TRAY_Y, CELL * 0.5, CELL * 0.5, "pixel_tile")
        game.set_color(id, 1, 1, 1, 0); tp[i][#tp[i] + 1] = id
      end
    end
    -- drag pool
    dpool = {}
    for _ = 1, 9 do
      local id = T.sprite(0, 0, CELL, CELL, "pixel_tile")
      game.set_color(id, 1, 1, 1, 0); dpool[#dpool + 1] = id
    end

    -- back button + score
    back = { x = -hw + 34, y = hh - 40, w = 44, h = 44 }
    local b = T.sprite(back.x, back.y, 44, 44, "badge_wood")
    T.sprite(back.x, back.y, 26, 26, "icon_back")
    score_txt = nil; set_score()

    refill()
  end

  return {
    enter = function() built = false; game.play_music("ac_bgm") end,
    leave = function() T.clear(); built = false; game.stop_music()
      if score_txt then score_txt = nil end end,
    tap = function(x, y)
      if back and K.in_rect(back, x, y) then K.switch("menu"); return end
      if not playing then T.clear(); build(HW, HH); return end
    end,
    update = function(dt, hw, hh)
      if not built then build(hw, hh) end
      if not playing then return end
      local px, py, down = game.pointer()
      if px == nil then px, py = 0, 0 end

      if down and not was_down and not drag then
        -- pick up a tray piece if the press is on one
        for i = 1, 3 do
          if tray[i] and math.abs(px - tray_cx[i]) < TRAY_W * 0.5 and math.abs(py - TRAY_Y) < TRAY_W * 0.5 then
            drag = { i = i }; draw_tray(); game.haptic("light"); break
          end
        end
      end

      if drag and down then
        local p = tray[drag.i]; local sh = SHAPES[p.shape]; local col = COLORS[p.color]
        local bh, bw = bounds(sh)
        local lift = CELL * 2.2
        -- drag sprites follow the finger (piece centred, lifted above the touch)
        local k = 0
        for _, o in ipairs(sh) do
          k = k + 1
          game.move_to(dpool[k], px + (o[2] - (bw - 1) / 2) * CELL, py + lift - (o[1] - (bh - 1) / 2) * CELL)
          game.set_size(dpool[k], CELL * 0.92, CELL * 0.92)
          game.set_color(dpool[k], col[1], col[2], col[3], 0.92)
        end
        for j = k + 1, #dpool do game.set_color(dpool[j], 1, 1, 1, 0) end
        -- snapped anchor from the piece centre, and preview
        clear_preview()
        local ccol = (px - BX0) / CELL + 0.5
        local crow = (BY0 - (py + lift)) / CELL + 0.5
        local ac = math.floor(ccol - (bw - 1) / 2 + 0.5)
        local ar = math.floor(crow - (bh - 1) / 2 + 0.5)
        drag.ar, drag.ac = ar, ac
        local ok = fits(sh, ar, ac)
        for _, o in ipairs(sh) do
          local r, c = ar + o[1], ac + o[2]
          if r >= 1 and r <= N and c >= 1 and c <= N then
            if ok then game.set_color(bg[r][c], 0.30, 0.62, 0.36, 1)
            else game.set_color(bg[r][c], 0.52, 0.24, 0.26, 1) end
            prevprev[#prevprev + 1] = { r, c }
          end
        end
      elseif drag and not down then
        -- release: place if valid, else return the piece to the tray
        local p = tray[drag.i]; local sh = SHAPES[p.shape]
        clear_preview()
        for j = 1, #dpool do game.set_color(dpool[j], 1, 1, 1, 0) end
        if drag.ar and fits(sh, drag.ar, drag.ac) then
          local i, ar, ac = drag.i, drag.ar, drag.ac; drag = nil; place(i, ar, ac)
        else
          drag = nil; draw_tray()
        end
      end
      was_down = down
    end,
  }
end

PACKS = PACKS or {}
PACKS.block_blast = {
  slot = 12, key = "block_blast", label = "Block Blast", short = "Blocks",
  icon = "brick", color = { 0.30, 0.62, 1.0 }, tier = "curated", make = make_block_blast,
}
