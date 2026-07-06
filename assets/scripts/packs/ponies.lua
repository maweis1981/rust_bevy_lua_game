-- ponies.lua — "PONY PARADE": a Queens / Star Battle logic puzzle.
-- Place one pony in every row, every column and every colour region; ponies
-- may never touch, not even diagonally. Tap cycles a cell empty -> X mark ->
-- pony -> empty. A pony that would break a rule is rejected and costs a heart.
-- Levels are generated on the fly: a valid non-touching permutation is laid
-- down first, regions are grown outward from each pony, and a counting solver
-- keeps only puzzles with a UNIQUE solution (with a capped fallback so the
-- generator terminates under any math.random, including the test LCG).
-- Registers the global factory make_ponies (main.lua builds the menu from PACKS).
-- Talks to the host ONLY through the `game` bridge + shared GAME_KIT helpers.

function make_ponies()
  local K = GAME_KIT
  local inr = K.in_rect
  local T = K.tracker()

  -- Region tints: pastel, high-contrast neighbours (index = region 1..8).
  local COLORS = {
    { 0.98, 0.75, 0.42 }, -- orange
    { 0.72, 0.62, 0.95 }, -- lilac
    { 0.55, 0.78, 0.98 }, -- sky
    { 0.98, 0.68, 0.80 }, -- pink
    { 0.85, 0.90, 0.50 }, -- lime
    { 0.98, 0.55, 0.48 }, -- coral
    { 0.60, 0.90, 0.75 }, -- mint
    { 0.90, 0.82, 0.66 }, -- sand
  }
  local START_N, MAX_N = 5, 8
  local HEARTS0 = 3
  local FLASH_T = 0.45

  local back, built = nil, false
  local level, N = 1, START_N
  local sol, reg = nil, nil        -- sol[r] = solution column; reg[r][c] = region id
  local state = nil                -- state[r][c]: 0 empty, 1 X mark, 2 pony
  local cells, marks, ponies = nil, nil, nil -- entity ids per cell
  local hearts, placed = HEARTS0, 0
  local won, dead = false, false
  local flash = {}                 -- { {r,c,t}, ... } cells flashing red
  local ox, oy, cell = 0, 0, 0     -- board top-left cell centre + cell size

  ----------------------------------------------------------------------------
  -- Puzzle generation (pure Lua, terminates under ANY math.random)
  ----------------------------------------------------------------------------

  -- A random permutation where consecutive rows differ by >= 2 columns —
  -- i.e. N non-touching "queens" placed one per row and column.
  local function gen_solution(n)
    local s, used = {}, {}
    local function bt(r)
      if r > n then return true end
      local cols = {}
      for c = 1, n do
        if not used[c] and (r == 1 or math.abs(c - s[r - 1]) >= 2) then cols[#cols + 1] = c end
      end
      for i = #cols, 2, -1 do local j = math.random(i); cols[i], cols[j] = cols[j], cols[i] end
      for _, c in ipairs(cols) do
        s[r], used[c] = c, true
        if bt(r + 1) then return true end
        s[r], used[c] = nil, nil
      end
      return false
    end
    bt(1)
    return s
  end

  -- Partition the grid into n contiguous regions, region k seeded at row k's
  -- pony. Round-robin growth (not "pick a random region") so a constant RNG
  -- can never spin forever on a landlocked region.
  local DIRS = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }
  local function gen_regions(n, s)
    local rg, mine = {}, {}
    for r = 1, n do rg[r] = {} end
    for k = 1, n do rg[k][s[k]] = k; mine[k] = { { k, s[k] } } end
    local remaining = n * n - n
    while remaining > 0 do
      local progressed = false
      for k = 1, n do
        if remaining == 0 then break end
        local opts = {}
        for _, cl in ipairs(mine[k]) do
          for _, d in ipairs(DIRS) do
            local rr, cc = cl[1] + d[1], cl[2] + d[2]
            if rr >= 1 and rr <= n and cc >= 1 and cc <= n and not rg[rr][cc] then
              opts[#opts + 1] = { rr, cc }
            end
          end
        end
        if #opts > 0 then
          local p = opts[math.random(#opts)]
          rg[p[1]][p[2]] = k
          mine[k][#mine[k] + 1] = p
          remaining = remaining - 1
          progressed = true
        end
      end
      if not progressed then break end -- unreachable, but never hang
    end
    return rg
  end

  -- Count solutions (early-out at `limit`) — the uniqueness gate.
  local function count_solutions(n, rg, limit)
    local usedc, usedreg, colof, count = {}, {}, {}, 0
    local function bt(r)
      if count >= limit then return end
      if r > n then count = count + 1; return end
      for c = 1, n do
        local k = rg[r][c]
        if not usedc[c] and not usedreg[k] and (r == 1 or math.abs(c - colof[r - 1]) >= 2) then
          usedc[c], usedreg[k], colof[r] = true, true, c
          bt(r + 1)
          usedc[c], usedreg[k], colof[r] = nil, nil, nil
        end
      end
    end
    bt(1)
    return count
  end

  local function gen_level(n)
    for _ = 1, 30 do
      local s = gen_solution(n)
      for _ = 1, 8 do
        local rg = gen_regions(n, s)
        if count_solutions(n, rg, 2) == 1 then return s, rg end
      end
    end
    -- Capped fallback: still a valid, winnable board (may have siblings).
    local s = gen_solution(n)
    return s, gen_regions(n, s)
  end

  ----------------------------------------------------------------------------
  -- Board state & rendering
  ----------------------------------------------------------------------------

  local function hud()
    if dead then
      game.set_text("OUT OF HEARTS - TAP TO RETRY")
    elseif won then
      game.set_text(string.format("LEVEL %d CLEAR! TAP FOR NEXT", level))
    else
      game.set_text(string.format("LV %d  HEARTS %d  LEFT %d", level, hearts, N - placed))
    end
  end

  local function cell_center(r, c)
    return ox + (c - 1) * cell, oy - (r - 1) * cell
  end

  local function tint(r, c)
    local col = COLORS[((reg[r][c] - 1) % #COLORS) + 1]
    game.set_color(cells[r][c], col[1], col[2], col[3], 1)
  end

  local function clear_overlay(r, c)
    if marks[r][c] then
      game.despawn(marks[r][c][1]); game.despawn(marks[r][c][2]); marks[r][c] = nil
    end
    if ponies[r][c] then game.despawn(ponies[r][c]); ponies[r][c] = nil end
  end

  local function draw_state(r, c)
    clear_overlay(r, c)
    local x, y = cell_center(r, c)
    if state[r][c] == 1 then
      local a = game.spawn(x, y, cell * 0.52, cell * 0.09, 0.25, 0.25, 0.30, 0.9)
      local b = game.spawn(x, y, cell * 0.52, cell * 0.09, 0.25, 0.25, 0.30, 0.9)
      game.set_rotation(a, 0.785); game.set_rotation(b, -0.785)
      marks[r][c] = { a, b }
    elseif state[r][c] == 2 then
      ponies[r][c] = game.spawn_sprite(x, y, cell * 0.82, cell * 0.82, "pony")
    end
  end

  -- Would a pony at (r,c) break a rule against the ponies on the board now?
  local function violation(r, c)
    for rr = 1, N do
      for cc = 1, N do
        if state[rr][cc] == 2 then
          if rr == r or cc == c then return true end
          if reg[rr][cc] == reg[r][c] then return true end
          if math.abs(rr - r) <= 1 and math.abs(cc - c) <= 1 then return true end
        end
      end
    end
    return false
  end

  local function clear_board_entities()
    if not cells then return end
    for r = 1, N do
      for c = 1, N do
        clear_overlay(r, c)
        if cells[r][c] then game.despawn(cells[r][c]) end
      end
    end
    cells = nil
  end

  local function build_level(hw, hh, fresh)
    clear_board_entities()
    if fresh then sol, reg = gen_level(N) end
    state, cells, marks, ponies = {}, {}, {}, {}
    hearts, placed, won, dead, flash = HEARTS0, 0, false, false, {}
    local board = math.min(2 * hw * 0.94, 2 * hh * 0.62)
    cell = board / N
    ox = -board / 2 + cell / 2
    oy = hh * 0.08 + board / 2 - cell / 2
    for r = 1, N do
      state[r], cells[r], marks[r], ponies[r] = {}, {}, {}, {}
      for c = 1, N do
        state[r][c] = 0
        local x, y = cell_center(r, c)
        -- Raw spawn (not via T): the board is rebuilt every level, so these are
        -- despawned by clear_board_entities; T only owns the back button + texts.
        -- Spawn with the region colour directly (tint() is only for restoring
        -- after a mistake flash) so the board never depends on same-frame recolor.
        local col = COLORS[((reg[r][c] - 1) % #COLORS) + 1]
        cells[r][c] = game.spawn(x, y, cell - 3, cell - 3, col[1], col[2], col[3], 1)
      end
    end
    hud()
  end

  local function build(hw, hh)
    T.clear()
    back = K.make_back(T, hw, hh)
    T.text(0, hh - 230, 20, 0.35, 0.3, 0.5, 1, "PONY PARADE")
    T.text(0, -hh + 150, 13, 0.45, 0.42, 0.55, 1, "ONE PONY PER ROW, COLUMN AND COLOR")
    T.text(0, -hh + 128, 13, 0.45, 0.42, 0.55, 1, "PONIES NEVER TOUCH - NOT EVEN DIAGONALLY")
    T.text(0, -hh + 106, 13, 0.45, 0.42, 0.55, 1, "TAP: MARK X   TAP AGAIN: PONY")
    build_level(hw, hh, true)
    built = true
    DEBUG = {
      game = "ponies", back = back,
      n = function() return N end,
      level = function() return level end,
      hearts = function() return hearts end,
      placed = function() return placed end,
      won = function() return won end,
      dead = function() return dead end,
      state = function(r, c) return state[r][c] end,
      region = function(r, c) return reg[r][c] end,
      solution = function(r) return sol[r] end,
      cell_center = cell_center,
    }
  end

  local function tap_cell(r, c)
    local s = state[r][c]
    if s == 0 then
      state[r][c] = 1
      game.play_sound("wall"); game.haptic("light")
    elseif s == 1 then
      if violation(r, c) then
        hearts = hearts - 1
        flash[#flash + 1] = { r = r, c = c, t = FLASH_T }
        game.set_color(cells[r][c], 0.95, 0.25, 0.22, 1)
        game.play_sound("hit"); game.haptic("heavy"); game.shake(0.3)
        if hearts <= 0 then dead = true end
      else
        state[r][c] = 2
        placed = placed + 1
        game.play_sound("hit"); game.haptic("medium"); game.shake(0.1)
        if placed == N then
          won = true
          game.play_sound("score"); game.haptic("success"); game.shake(0.5)
        end
      end
    else
      state[r][c] = 0
      placed = placed - 1
      game.play_sound("wall"); game.haptic("light")
    end
    draw_state(r, c)
    hud()
  end

  return {
    enter = function() built = false end,
    leave = function()
      clear_board_entities()
      T.clear()
      built = false
    end,
    tap = function(x, y)
      if back and inr(back, x, y) then K.switch("menu"); return end
      if not built then return end
      if dead then
        local hw, hh = game.bounds()
        build_level(hw, hh, true)
        return
      end
      if won then
        level = level + 1
        N = math.min(START_N + math.floor((level - 1) / 2), MAX_N)
        local hw, hh = game.bounds()
        build_level(hw, hh, true)
        return
      end
      -- Map world coords -> cell (row 1 at the top).
      local ccol = math.floor((x - (ox - cell / 2)) / cell) + 1
      local crow = math.floor(((oy + cell / 2) - y) / cell) + 1
      if crow >= 1 and crow <= N and ccol >= 1 and ccol <= N then
        tap_cell(crow, ccol)
      end
    end,
    update = function(dt, hw, hh)
      if not built then build(hw, hh) end
      if dt > 1 / 30 then dt = 1 / 30 end
      -- Bleed off red mistake flashes back to the region tint.
      if #flash > 0 then
        local keep = {}
        for _, f in ipairs(flash) do
          f.t = f.t - dt
          if f.t <= 0 then tint(f.r, f.c) else keep[#keep + 1] = f end
        end
        flash = keep
      end
    end,
  }
end

-- Self-register this game pack (see main.lua: the menu builds from PACKS).
PACKS = PACKS or {}
PACKS["ponies"] = { slot = 21, key = "ponies", label = "Pony Parade", short = "Ponies", icon = "pony", color = { 0.72, 0.55, 0.85 }, tier = "ai", make = make_ponies }
