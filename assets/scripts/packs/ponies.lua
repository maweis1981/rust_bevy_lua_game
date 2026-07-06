-- ponies.lua — "小马拼图" (Pony Parade): a Queens / Star Battle logic puzzle,
-- UI and interaction modeled 1:1 on the reference gameplay video:
--   · tap an open cell to place a pony DIRECTLY (no manual X cycling)
--   · every placed pony AUTO-MARKS an X on each cell it excludes
--     (same row / column / colour region / any of the 8 neighbours)
--   · a wrong pony (not the unique solution) flashes red and costs a heart
--     (2 hearts per board); running out of hearts or time fails the level
--   · top bar: coins · energy · level title · hearts · streak; below it the
--     "remaining ponies" + countdown pills and the three-rule banner
--   · bottom bar: clear · find-pony tool · lightbulb hint · colourblind
--     mode toggle · coordinates toggle
-- Chinese labels render through assets/fonts/game.ttf, a Noto Sans subset
-- built by tools/subset_font.py — any NEW CJK string must be added there.
-- Puzzles are generated on the fly with a uniqueness-counting solver (capped
-- fallback so generation terminates under ANY math.random, incl. test LCG).
-- Registers make_ponies; talks to the host ONLY via `game` + GAME_KIT.

function make_ponies()
  local K = GAME_KIT
  local inr = K.in_rect
  local T = K.tracker()

  -- Region tints matched to the video's pastel look (index = region 1..10).
  local COLORS = {
    { 0.80, 0.85, 0.45 }, -- olive-lime
    { 0.95, 0.60, 0.70 }, -- pink
    { 0.45, 0.72, 0.95 }, -- blue
    { 0.62, 0.55, 0.90 }, -- violet
    { 0.72, 0.85, 0.95 }, -- pale sky
    { 0.95, 0.55, 0.45 }, -- coral red
    { 0.97, 0.72, 0.35 }, -- orange
    { 0.55, 0.85, 0.70 }, -- mint
    { 0.90, 0.80, 0.55 }, -- sand
    { 0.80, 0.65, 0.85 }, -- mauve
  }
  local START_N, MAX_N = 5, 10
  local HEARTS0 = 2
  local FLASH_T = 0.45

  -- session meta (persists across enter/leave; the closure lives for the run)
  local level, streak, coins, energy = 1, 0, 48, 98

  local back, built = nil, false
  local N = START_N
  local sol, reg = nil, nil       -- sol[r] = solution column; reg[r][c] = region id
  local state = nil               -- state[r][c]: 0 open, 1 auto-X, 2 pony
  local cells, xmarks, ponies = nil, nil, nil
  local hearts, placed = HEARTS0, 0
  local won, dead = false, false
  local time_left, time_shown = 0, -1
  local flash = {}                -- red mistake flashes / yellow hint flashes
  local ox, oy, cell = 0, 0, 0
  local scr_hw, scr_hh = 215, 466

  -- HUD entity ids (text redrawn in place via despawn+respawn)
  local ui = {}                   -- static pills/icons (in T)
  local dyn = {}                  -- dynamic texts: level, hearts, streak, left, time, badges
  local overlay = {}              -- win/fail overlay entities
  local find_charges, bulb_charges = 1, 1
  local cb_on, coord_on = false, false
  local cb_ids, coord_ids = {}, {}

  ----------------------------------------------------------------------------
  -- Puzzle generation (unchanged core: terminates under ANY math.random)
  ----------------------------------------------------------------------------
  local function gen_solution(n)
    local s, used = {}, {}
    local function bt(r)
      if r > n then return true end
      local colsl = {}
      for c = 1, n do
        if not used[c] and (r == 1 or math.abs(c - s[r - 1]) >= 2) then colsl[#colsl + 1] = c end
      end
      for i = #colsl, 2, -1 do local j = math.random(i); colsl[i], colsl[j] = colsl[j], colsl[i] end
      for _, c in ipairs(colsl) do
        s[r], used[c] = c, true
        if bt(r + 1) then return true end
        s[r], used[c] = nil, nil
      end
      return false
    end
    bt(1)
    return s
  end

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
      if not progressed then break end
    end
    return rg
  end

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
    local s = gen_solution(n)
    return s, gen_regions(n, s)
  end

  ----------------------------------------------------------------------------
  -- Board rendering
  ----------------------------------------------------------------------------
  local function cell_center(r, c)
    return ox + (c - 1) * cell, oy - (r - 1) * cell
  end

  local function tint(r, c)
    local col = COLORS[((reg[r][c] - 1) % #COLORS) + 1]
    game.set_color(cells[r][c], col[1], col[2], col[3], 1)
  end

  local function clear_overlay_at(r, c)
    if xmarks[r][c] then
      game.despawn(xmarks[r][c][1]); game.despawn(xmarks[r][c][2]); xmarks[r][c] = nil
    end
    if ponies[r][c] then game.despawn(ponies[r][c]); ponies[r][c] = nil end
  end

  local function draw_cell_state(r, c)
    clear_overlay_at(r, c)
    local x, y = cell_center(r, c)
    if state[r][c] == 1 then
      local a = game.spawn(x, y, cell * 0.58, cell * 0.15, 1, 1, 1, 0.95)
      local b = game.spawn(x, y, cell * 0.58, cell * 0.15, 1, 1, 1, 0.95)
      game.set_rotation(a, 0.785); game.set_rotation(b, -0.785)
      xmarks[r][c] = { a, b }
    elseif state[r][c] == 2 then
      ponies[r][c] = game.spawn_sprite(x, y, cell * 0.88, cell * 0.88, "pony")
    end
  end

  -- Recompute every auto-X from the ponies on the board (video behaviour:
  -- placing marks exclusions immediately; removing un-marks what only that
  -- pony excluded). Full recompute keeps removal trivially correct.
  local function recompute_marks()
    for r = 1, N do
      for c = 1, N do
        if state[r][c] ~= 2 then
          local excluded = false
          for rr = 1, N do
            for cc = 1, N do
              if state[rr][cc] == 2 then
                if rr == r or cc == c or reg[rr][cc] == reg[r][c]
                  or (math.abs(rr - r) <= 1 and math.abs(cc - c) <= 1) then
                  excluded = true
                end
              end
            end
          end
          local want = excluded and 1 or 0
          if state[r][c] ~= want then
            state[r][c] = want
            draw_cell_state(r, c)
          end
        end
      end
    end
  end

  ----------------------------------------------------------------------------
  -- HUD (top bar, pills, rule banner, toolbar) — cloned from the video layout
  ----------------------------------------------------------------------------
  local function retext(key, x, y, size, r, g, b, a, s)
    if dyn[key] then game.despawn(dyn[key]) end
    dyn[key] = game.spawn_text(x, y, size, r, g, b, a, s)
  end

  local function hud_level() retext("level", 0, scr_hh - 118, 30, 0.16, 0.18, 0.30, 1, "第" .. level .. "关") end
  local function hud_streak() retext("streak", scr_hw - 78, scr_hh - 160, 17, 0.85, 0.15, 0.15, 1, "连胜：" .. streak) end
  local function hud_left() retext("left", -scr_hw + 118, scr_hh - 212, 16, 0.85, 0.15, 0.15, 1, "剩余：" .. (N - placed)) end
  local function hud_coins() retext("coins", -scr_hw + 96, scr_hh - 118, 16, 0.35, 0.30, 0.20, 1, tostring(coins)) end
  local function hud_time()
    local t = math.max(0, math.ceil(time_left))
    if t == time_shown then return end
    time_shown = t
    retext("time", scr_hw - 80, scr_hh - 212, 16, 0.85, 0.15, 0.15, 1, "剩余时间：" .. t)
  end
  local function hud_hearts()
    for i = 1, HEARTS0 do
      local id = dyn["heart" .. i]
      if id then
        if i <= hearts then game.set_color(id, 1, 1, 1, 1)
        else game.set_color(id, 0.25, 0.25, 0.28, 0.65) end
      end
    end
  end
  local function hud_badges()
    retext("findn", -70, -scr_hh + 64, 15, 1, 1, 1, 1, find_charges > 0 and tostring(find_charges) or "+")
    retext("bulbn", 70, -scr_hh + 64, 15, 1, 1, 1, 1, bulb_charges > 0 and tostring(bulb_charges) or "+")
  end

  local BTN = {}  -- tap rects for toolbar buttons

  local function build_hud()
    -- pale board-room backdrop, spawned first so everything draws over it
    T.spawn(0, 0, scr_hw * 2 + 4, scr_hh * 2 + 4, 0.80, 0.85, 0.91, 1)
    back = K.make_back(T, scr_hw, scr_hh)

    -- coins + energy pills (top-left, under the back button)
    T.spawn(-scr_hw + 78, scr_hh - 118, 120, 30, 0.62, 0.66, 0.74, 0.9)
    T.sprite(-scr_hw + 32, scr_hh - 118, 26, 26, "icon_coin")
    T.spawn(-scr_hw + 78, scr_hh - 156, 120, 30, 0.62, 0.66, 0.74, 0.9)
    T.sprite(-scr_hw + 32, scr_hh - 156, 26, 26, "icon_bolt")
    T.text(-scr_hw + 96, scr_hh - 156, 16, 0.35, 0.30, 0.20, 1, tostring(energy))

    -- hearts pill (centered) + streak pill (right)
    T.spawn(0, scr_hh - 160, 128, 36, 1, 1, 1, 0.95)
    dyn["heart1"] = game.spawn_sprite(-24, scr_hh - 160, 26, 26, "icon_heart")
    dyn["heart2"] = game.spawn_sprite(24, scr_hh - 160, 26, 26, "icon_heart")
    T.spawn(scr_hw - 92, scr_hh - 160, 150, 34, 1, 1, 1, 0.95)
    T.sprite(scr_hw - 152, scr_hh - 160, 28, 28, "icon_trophy")

    -- remaining + countdown pills
    T.spawn(-scr_hw + 108, scr_hh - 212, 190, 32, 1, 1, 1, 0.85)
    T.sprite(-scr_hw + 34, scr_hh - 212, 26, 26, "pony")
    T.spawn(scr_hw - 104, scr_hh - 212, 198, 32, 1, 1, 1, 0.85)
    T.sprite(scr_hw - 190, scr_hh - 212, 24, 24, "icon_clock")

    -- three-rule banner
    T.spawn(0, scr_hh - 272, scr_hw * 2 - 24, 62, 1, 1, 1, 0.95)
    T.text(-scr_hw * 0.62, scr_hh - 272, 13, 0.20, 0.22, 0.32, 1, "每种颜色1匹\n小马")
    T.spawn(-scr_hw * 0.30, scr_hh - 272, 2, 46, 0.85, 0.87, 0.90, 1)
    T.text(0, scr_hh - 272, 13, 0.20, 0.22, 0.32, 1, "每行每列均有且\n仅有1匹小马")
    T.spawn(scr_hw * 0.30, scr_hh - 272, 2, 46, 0.85, 0.87, 0.90, 1)
    T.text(scr_hw * 0.62, scr_hh - 272, 13, 0.20, 0.22, 0.32, 1, "小马不能相邻")

    -- bottom toolbar: clear · find tool · bulb tool · colourblind · coords
    local by = -scr_hh + 96
    BTN.clear = { x = -scr_hw + 44, y = by, w = 84, h = 74 }
    T.spawn(BTN.clear.x, BTN.clear.y, BTN.clear.w, BTN.clear.h, 0.62, 0.72, 0.84, 0.95)
    T.sprite(BTN.clear.x, BTN.clear.y + 12, 30, 30, "icon_trash")
    T.text(BTN.clear.x, BTN.clear.y - 22, 14, 1, 1, 1, 1, "清除")

    BTN.find = { x = -70, y = by, w = 96, h = 96 }
    T.spawn(BTN.find.x, BTN.find.y, BTN.find.w, BTN.find.h, 1, 1, 1, 0.95)
    T.sprite(BTN.find.x, BTN.find.y + 8, 62, 62, "icon_find")
    T.spawn(BTN.find.x, -scr_hh + 64, 84, 22, 0.15, 0.35, 0.80, 1)

    BTN.bulb = { x = 70, y = by, w = 96, h = 96 }
    T.spawn(BTN.bulb.x, BTN.bulb.y, BTN.bulb.w, BTN.bulb.h, 1, 1, 1, 0.95)
    T.sprite(BTN.bulb.x, BTN.bulb.y + 8, 58, 58, "icon_bulb")
    T.spawn(BTN.bulb.x, -scr_hh + 64, 84, 22, 0.15, 0.35, 0.80, 1)

    BTN.coord = { x = scr_hw - 42, y = by, w = 80, h = 74 }
    T.spawn(BTN.coord.x, BTN.coord.y, BTN.coord.w, BTN.coord.h, 0.62, 0.72, 0.84, 0.95)
    T.sprite(BTN.coord.x, BTN.coord.y + 12, 28, 28, "icon_pin")
    T.text(BTN.coord.x, BTN.coord.y - 22, 14, 1, 1, 1, 1, "坐标")

    BTN.cb = { x = scr_hw - 48, y = by + 108, w = 86, h = 76 }
    T.spawn(BTN.cb.x, BTN.cb.y, BTN.cb.w, BTN.cb.h, 0.92, 0.94, 0.97, 0.95)
    T.sprite(BTN.cb.x, BTN.cb.y + 14, 34, 34, "icon_eye")
    T.text(BTN.cb.x, BTN.cb.y - 22, 12, 0.85, 0.15, 0.15, 1, "色盲模式")

    hud_level(); hud_streak(); hud_coins(); hud_hearts(); hud_badges()
  end

  ----------------------------------------------------------------------------
  -- Overlays (win / fail), toggles
  ----------------------------------------------------------------------------
  local function clear_overlay()
    for _, id in ipairs(overlay) do game.despawn(id) end
    overlay = {}
  end

  local function show_overlay(title, subtitle, r, g, b)
    clear_overlay()
    overlay[#overlay + 1] = game.spawn(0, 0, scr_hw * 1.7, 150, 1, 1, 1, 0.97)
    overlay[#overlay + 1] = game.spawn_text(0, 26, 30, r, g, b, 1, title)
    overlay[#overlay + 1] = game.spawn_text(0, -30, 17, 0.35, 0.38, 0.48, 1, subtitle)
  end

  local function clear_toggles()
    for _, id in ipairs(cb_ids) do game.despawn(id) end
    for _, id in ipairs(coord_ids) do game.despawn(id) end
    cb_ids, coord_ids = {}, {}
  end

  local function redraw_cb()
    for _, id in ipairs(cb_ids) do game.despawn(id) end
    cb_ids = {}
    if not cb_on then return end
    for r = 1, N do
      for c = 1, N do
        local x, y = cell_center(r, c)
        cb_ids[#cb_ids + 1] = game.spawn_text(
          x + cell * 0.28, y + cell * 0.26, math.max(9, cell * 0.22),
          0.15, 0.17, 0.25, 0.85, tostring(reg[r][c]))
      end
    end
  end

  local function redraw_coords()
    for _, id in ipairs(coord_ids) do game.despawn(id) end
    coord_ids = {}
    if not coord_on then return end
    for r = 1, N do
      local _, y = cell_center(r, 1)
      coord_ids[#coord_ids + 1] = game.spawn_text(
        ox - cell * 0.85, y, math.max(10, cell * 0.26), 0.35, 0.38, 0.48, 1, tostring(r))
    end
    for c = 1, N do
      local x, _ = cell_center(1, c)
      coord_ids[#coord_ids + 1] = game.spawn_text(
        x, oy + cell * 0.85, math.max(10, cell * 0.26), 0.35, 0.38, 0.48, 1,
        string.char(64 + c))
    end
  end

  ----------------------------------------------------------------------------
  -- Level lifecycle
  ----------------------------------------------------------------------------
  local function clear_board_entities()
    if not cells then return end
    for r = 1, N do
      for c = 1, N do
        clear_overlay_at(r, c)
        if cells[r][c] then game.despawn(cells[r][c]) end
      end
    end
    cells = nil
  end

  local function build_level(fresh)
    clear_board_entities(); clear_overlay(); clear_toggles()
    if fresh then sol, reg = gen_level(N) end
    state, cells, xmarks, ponies = {}, {}, {}, {}
    hearts, placed, won, dead, flash = HEARTS0, 0, false, false, {}
    time_left, time_shown = N * 10, -1
    local board = math.min(2 * scr_hw * 0.875, 2 * scr_hh * 0.44)
    cell = board / N
    ox = -board / 2 + cell / 2
    oy = -scr_hh * 0.02 + board / 2 - cell / 2
    for r = 1, N do
      state[r], cells[r], xmarks[r], ponies[r] = {}, {}, {}, {}
      for c = 1, N do
        state[r][c] = 0
        local x, y = cell_center(r, c)
        local col = COLORS[((reg[r][c] - 1) % #COLORS) + 1]
        cells[r][c] = game.spawn(x, y, cell - 3, cell - 3, col[1], col[2], col[3], 1)
      end
    end
    hud_level(); hud_hearts(); hud_left(); hud_time()
    redraw_cb(); redraw_coords()
  end

  local function win_level()
    won = true
    streak = streak + 1
    coins = coins + 20
    hud_streak(); hud_coins()
    show_overlay("恭喜过关！", "点击继续", 0.20, 0.65, 0.30)
    game.play_sound("score"); game.haptic("success"); game.shake(0.5)
  end

  local function fail_level(reason)
    dead = true
    streak = 0
    hud_streak()
    show_overlay("挑战失败", reason .. "·再试一次", 0.85, 0.20, 0.18)
    game.play_sound("hit"); game.haptic("heavy"); game.shake(0.4)
  end

  local function place_correct(r)
    local c = sol[r]
    state[r][c] = 2
    placed = placed + 1
    draw_cell_state(r, c)
    recompute_marks()
    hud_left()
    game.play_sound("hit"); game.haptic("medium"); game.shake(0.08)
    if placed == N then win_level() end
  end

  local function tap_cell(r, c)
    local s = state[r][c]
    if s == 2 then
      state[r][c] = 0
      placed = placed - 1
      draw_cell_state(r, c)
      recompute_marks()
      hud_left()
      game.play_sound("wall"); game.haptic("light")
    elseif s == 1 then
      game.shake(0.04)  -- excluded cell: nudge only, matches the video
    else
      if sol[r] == c then
        place_correct(r)
      else
        hearts = hearts - 1
        hud_hearts()
        flash[#flash + 1] = { r = r, c = c, t = FLASH_T, red = true }
        game.set_color(cells[r][c], 0.92, 0.20, 0.18, 1)
        game.play_sound("hit"); game.haptic("heavy"); game.shake(0.3)
        if hearts <= 0 then fail_level("爱心用完了") end
      end
    end
  end

  local function first_unsolved_row()
    for r = 1, N do if state[r][sol[r]] ~= 2 then return r end end
    return nil
  end

  ----------------------------------------------------------------------------
  -- Scene
  ----------------------------------------------------------------------------
  local function build(hw, hh)
    T.clear(); dyn = {}
    scr_hw, scr_hh = hw, hh
    build_hud()
    build_level(true)
    built = true
    DEBUG = {
      game = "ponies", back = back,
      n = function() return N end,
      level = function() return level end,
      hearts = function() return hearts end,
      placed = function() return placed end,
      won = function() return won end,
      dead = function() return dead end,
      streak = function() return streak end,
      coins = function() return coins end,
      time_left = function() return time_left end,
      find_charges = function() return find_charges end,
      bulb_charges = function() return bulb_charges end,
      cb_on = function() return cb_on end,
      coord_on = function() return coord_on end,
      state = function(r, c) return state[r][c] end,
      region = function(r, c) return reg[r][c] end,
      solution = function(r) return sol[r] end,
      cell_center = cell_center,
      btn = function(name) return BTN[name] end,
    }
  end

  return {
    enter = function() built = false end,
    leave = function()
      clear_board_entities(); clear_overlay(); clear_toggles()
      for _, id in pairs(dyn) do game.despawn(id) end
      dyn = {}
      T.clear()
      built = false
    end,
    tap = function(x, y)
      if back and inr(back, x, y) then K.switch("menu"); return end
      if not built then return end
      if dead then build_level(true); return end
      if won then
        level = level + 1
        N = math.min(START_N + math.floor((level - 1) / 2), MAX_N)
        build_level(true)
        return
      end
      if inr(BTN.clear, x, y) then
        if placed > 0 then
          for r = 1, N do
            for c = 1, N do
              if state[r][c] == 2 then state[r][c] = 0; draw_cell_state(r, c) end
            end
          end
          placed = 0
          recompute_marks(); hud_left()
          game.play_sound("wall"); game.haptic("light")
        end
        return
      end
      if inr(BTN.find, x, y) then
        if find_charges > 0 then
          local r = first_unsolved_row()
          if r then find_charges = find_charges - 1; hud_badges(); place_correct(r) end
        end
        return
      end
      if inr(BTN.bulb, x, y) then
        if bulb_charges > 0 then
          local r = first_unsolved_row()
          if r then
            bulb_charges = bulb_charges - 1; hud_badges()
            flash[#flash + 1] = { r = r, c = sol[r], t = 1.0 }
            game.set_color(cells[r][sol[r]], 1.0, 0.95, 0.35, 1)
            game.play_sound("wall"); game.haptic("light")
          end
        end
        return
      end
      if inr(BTN.cb, x, y) then cb_on = not cb_on; redraw_cb(); return end
      if inr(BTN.coord, x, y) then coord_on = not coord_on; redraw_coords(); return end
      local ccol = math.floor((x - (ox - cell / 2)) / cell) + 1
      local crow = math.floor(((oy + cell / 2) - y) / cell) + 1
      if crow >= 1 and crow <= N and ccol >= 1 and ccol <= N then
        tap_cell(crow, ccol)
      end
    end,
    update = function(dt, hw, hh)
      if not built then build(hw, hh) end
      if dt > 1 / 30 then dt = 1 / 30 end
      if not won and not dead then
        time_left = time_left - dt
        hud_time()
        if time_left <= 0 then fail_level("时间到了") end
      end
      if #flash > 0 then
        local keep = {}
        for _, f in ipairs(flash) do
          f.t = f.t - dt
          if f.t <= 0 then
            if state[f.r] and state[f.r][f.c] ~= nil then tint(f.r, f.c) end
          else
            keep[#keep + 1] = f
          end
        end
        flash = keep
      end
    end,
  }
end

-- Self-register this game pack (see main.lua: the menu builds from PACKS).
PACKS = PACKS or {}
PACKS["ponies"] = { slot = 21, key = "ponies", label = "Pony Parade", short = "Ponies", icon = "pony", color = { 0.72, 0.55, 0.85 }, tier = "ai", make = make_ponies }
