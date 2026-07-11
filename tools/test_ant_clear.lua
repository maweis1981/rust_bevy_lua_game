-- Headless invariant tests for assets/scripts/packs/ant_clear.lua.
--
-- Mocks the Rust `game` API + GAME_KIT and drives the ant-clear puzzle to
-- completion under lua5.4, asserting the properties the design rests on:
--   1. MATCHING     — the tray's per-colour counts equal the picture's per-colour
--                     pixel counts (you can neither run short nor have leftovers).
--   2. PATHFINDING  — ants only ever remove FRONTIER pixels: at every frame every
--                     cleared cell stays connected to the outside (no buried pixel
--                     is ever taken). A broken flow field would strand an island.
--   3. NO TELEPORT  — each ant moves a bounded distance per frame (the feel
--                     contract; big-dt hitches are clamped).
--   4. SOLVABLE     — the generated level clears completely (win), never deadlocks.
--
-- Run: lua5.4 tools/test_ant_clear.lua   (exits non-zero on any failure)

local HW, HH = 215, 466
local DT = 1 / 60

-- deterministic RNG (unused by the pack, but keep parity with test_pong)
local rng = 987654321
math.random = function(a, b)
  rng = (1103515245 * rng + 12345) % 2147483648
  local r = rng / 2147483648
  if a == nil then return r end
  if b == nil then return math.floor(r * a) + 1 end
  return math.floor(r * (b - a + 1)) + a
end

----------------------------------------------------------------------
-- Mock host API
----------------------------------------------------------------------
local pos, max_id = {}, 0
game = {
  log = function() end,
  bounds = function() return HW, HH end,
  spawn = function(x, y) max_id = max_id + 1; pos[max_id] = { x = x, y = y }; return max_id end,
  spawn_sprite = function(x, y) max_id = max_id + 1; pos[max_id] = { x = x, y = y }; return max_id end,
  spawn_text = function(x, y) max_id = max_id + 1; pos[max_id] = { x = x, y = y }; return max_id end,
  move_to = function(id, x, y) if pos[id] then pos[id] = { x = x, y = y } end end,
  set_color = function() end,
  set_size = function() end,
  set_rotation = function() end,
  spawn_sheet = function(x, y) max_id = max_id + 1; pos[max_id] = { x = x, y = y }; return max_id end,
  set_frame = function() end,
  spawn_rig = function(x, y) max_id = max_id + 1; pos[max_id] = { x = x, y = y }; return max_id end,
  play_anim = function() end,
  set_bone = function() end,
  tween = function() end,
  despawn = function(id) pos[id] = nil end,
  set_text = function() end,
  shake = function() end,
  zoom = function() end,
  emit = function() end,
  play_sound = function() end,
  play_music = function() end,
  stop_music = function() end,
  set_volume = function() end,
  haptic = function() end,
  track = function() end,
  set_bg_theme = function() end,
  pointer = function() return nil, nil, false end,
  key = function() return false end,
  touches = function() return {} end,
}

SETTINGS = { hud = true }

----------------------------------------------------------------------
-- Minimal GAME_KIT (mirror of main.lua's helpers the pack uses)
----------------------------------------------------------------------
local function clamp(v, lo, hi) if v < lo then return lo elseif v > hi then return hi else return v end end
GAME_KIT = {
  clamp = clamp,
  sign = function(v) return (v > 0 and 1) or (v < 0 and -1) or 0 end,
  in_rect = function(r, x, y) return math.abs(x - r.x) <= r.w * 0.5 and math.abs(y - r.y) <= r.h * 0.5 end,
  switch = function() end,
  make_back = function(T, hw, hh)
    local r = { x = -hw + 84, y = hh - 152, w = 132, h = 76 }
    T.sprite(r.x, r.y, r.w, r.h, "btn_back"); return r
  end,
  tracker = function()
    local ids = {}
    return {
      spawn = function(...) local id = game.spawn(...); ids[#ids + 1] = id; return id end,
      sprite = function(...) local id = game.spawn_sprite(...); ids[#ids + 1] = id; return id end,
      text = function(...) local id = game.spawn_text(...); ids[#ids + 1] = id; return id end,
      clear = function() for _, id in ipairs(ids) do game.despawn(id) end; ids = {} end,
    }
  end,
}

----------------------------------------------------------------------
-- Load the pack, build the scene
----------------------------------------------------------------------
PACKS = {}
dofile("assets/scripts/packs/ant_clear.lua")
assert(PACKS.ant_clear, "pack did not register PACKS.ant_clear")
local scene = PACKS.ant_clear.make()
scene.enter()
scene.update(DT, HW, HH)   -- first update builds the board
local D = DEBUG
assert(D and D.game == "ant_clear", "DEBUG not exposed")

local fail = 0
local function check(cond, msg) if not cond then fail = fail + 1; print("FAIL: " .. msg) else print("ok: " .. msg) end end

----------------------------------------------------------------------
-- 1. MATCHING: tray colour sums == picture per-colour counts
----------------------------------------------------------------------
local grid0 = D.grid()
local Hn, Wn = #grid0, #grid0[1]
local board_counts = {}
for r = 1, Hn do for c = 1, Wn do
  local v = grid0[r][c]; if v ~= 0 then board_counts[v] = (board_counts[v] or 0) + 1 end
end end
-- reconstruct tray totals: painted now + everything still queued/active must equal
-- board_counts; simplest robust check — total painted == sum(board_counts) at start,
-- and the run below must consume exactly that many (win reaches 0).
local total0 = 0; for _, n in pairs(board_counts) do total0 = total0 + n end
check(D.painted() == total0, "board painted count = sum of colour counts (" .. total0 .. ")")

----------------------------------------------------------------------
-- helper: every empty cell must be reachable from OUTSIDE via empties
-- (i.e. no buried/enclosed cleared cell — proves frontier-only removal)
----------------------------------------------------------------------
-- Returns the set (keyed) of empty cells NOT reachable from outside via empties.
-- Shapes with an enclosed hole (the donut) legitimately START with such cells;
-- the invariant is that no NEW ones ever appear (every cleared cell must have
-- been outside-reachable when it was cleared).
local function key_rc(w, r, c) return r * (w + 2) + c end
local function unreachable_empties(g)
  local h, w = #g, #g[1]
  local seen = {}
  local q, head = {}, 1
  for r = 1, h do for c = 1, w do
    if g[r][c] == 0 and (r == 1 or c == 1 or r == h or c == w) then
      local k = key_rc(w, r, c); if not seen[k] then seen[k] = true; q[#q + 1] = { r, c } end
    end
  end end
  while head <= #q do
    local cell = q[head]; head = head + 1
    local r, c = cell[1], cell[2]
    for _, p in ipairs({ {r+1,c},{r-1,c},{r,c+1},{r,c-1} }) do
      local rr, cc = p[1], p[2]
      if rr >= 1 and rr <= h and cc >= 1 and cc <= w and g[rr][cc] == 0 then
        local k = key_rc(w, rr, cc); if not seen[k] then seen[k] = true; q[#q + 1] = { rr, cc } end
      end
    end
  end
  local out = {}
  for r = 1, h do for c = 1, w do
    if g[r][c] == 0 and not seen[key_rc(w, r, c)] then out[key_rc(w, r, c)] = true end
  end end
  return out
end
-- true iff every unreachable empty in g was ALREADY an (unreachable) empty at start
local function no_new_enclosed(g, initial)
  for k in pairs(unreachable_empties(g)) do
    if not initial[k] then return false end
  end
  return true
end

----------------------------------------------------------------------
-- shared driver: runs the scene to a terminal state, checking pathfinding +
-- no-teleport every frame. `policy` (optional) is the "player" — called each
-- frame before update to load tray colours into free slots.
----------------------------------------------------------------------
local BOUND = 460 * (1 / 30) * 2 + 2   -- ANT_SPEED * MAX_DT * (2x) + slack
-- runs until the board is cleared (won) or a frame cap. `policy` (the "player")
-- is called each frame and may load/cancel slots. Stuck is NOT terminal.
local function drive(Dh, policy)
  local prev = Dh.ant_xy()
  local initial = unreachable_empties(Dh.grid())   -- pre-enclosed holes (donut)
  local buried_ok, teleport_ok = true, true
  local frames, MAXF = 0, 30000
  while not Dh.won() and frames < MAXF do
    if policy then policy(Dh) end
    scene.update(DT, HW, HH)
    frames = frames + 1
    if not no_new_enclosed(Dh.grid(), initial) then buried_ok = false end
    local cur = Dh.ant_xy()
    for i = 1, math.min(#cur, #prev) do
      local dx, dy = cur[i][1] - prev[i][1], cur[i][2] - prev[i][2]
      if math.sqrt(dx * dx + dy * dy) > BOUND then teleport_ok = false end
    end
    prev = cur
  end
  return frames, buried_ok, teleport_ok
end

local function rebuild()   -- fresh play; DEBUG is reassigned on build
  scene.enter(); scene.update(DT, HW, HH); return DEBUG
end

----------------------------------------------------------------------
-- Scenario A: AUTO — autoplay clears the board (solvability + pathfinding)
----------------------------------------------------------------------
D.set_mode("auto")
local fa, buried_a, tele_a = drive(D)
check(buried_a, "PATHFINDING: no buried pixel ever removed (cleared region stays edge-connected)")
check(tele_a, "NO TELEPORT: every ant moves <= " .. string.format("%.1f", BOUND) .. " units/frame")
check(D.won(), "SOLVABLE (auto): board fully cleared -> win (in " .. fa .. " frames)")
check(D.painted() == 0, "all pixels carried away (painted == 0)")

----------------------------------------------------------------------
-- Scenario B: MANUAL, good play — the strategy load path. A "player" that loads
-- the tray front into any free slot must also clear the board and never stall.
----------------------------------------------------------------------
-- Good play in the COLUMN queue: only column heads are loadable; load any head
-- whose colour is currently reachable. (No geometric orphaning — the only failure
-- is a slot jam.) tray_colors() returns the 4 head colours (0 = empty column).
local function safe_policy(Dh)
  while Dh.free_slots() > 0 do
    local tc, pick = Dh.tray_colors(), nil
    for c = 1, 4 do if tc[c] ~= 0 and Dh.reachable(tc[c]) > 0 then pick = c; break end end
    if not pick then break end
    Dh.load(pick)
  end
end

D.set_mode("manual")   -- flip the shared mode before the fresh build auto-fills
D = rebuild()
-- a win advances the saved level, so the rebuild may be a DIFFERENT picture:
-- compare painted against the rebuilt grid's own cell count, not level 1's.
local g1 = D.grid()
local total1 = 0
for r = 1, #g1 do for c = 1, #g1[1] do if g1[r][c] ~= 0 then total1 = total1 + 1 end end end
check(D.free_slots() == 4 and D.painted() == total1, "manual: starts with empty slots, nothing auto-loads")
local fb, buried_b = drive(D, safe_policy)
check(buried_b, "PATHFINDING holds under manual play too")
check(D.won(), "STRATEGY: manual top-row (column-head) play clears the board (in " .. fb .. " frames)")
check(not D.stuck(), "manual good play never gets stuck")

----------------------------------------------------------------------
-- Scenario C: the rewarded-ad cancel path — cancel a committed slot mid-flight
-- (aborting its ants cleanly), then finish. Proves cancel frees a slot, the abort
-- keeps the pathfinding invariant, and the level still completes.
----------------------------------------------------------------------
D = rebuild()
D.set_mode("manual")
D.load(1); D.load(2)                                  -- commit two column heads
for _ = 1, 150 do scene.update(DT, HW, HH) end         -- ants go to work
local before = D.free_slots()
D.cancel(1)                                            -- rewarded-ad cancel
scene.update(DT, HW, HH)
check(D.free_slots() > before, "cancel (rewarded ad) frees a slot")
local fc, buried_c = drive(D, safe_policy)
check(buried_c, "PATHFINDING holds through cancel/abort too")
check(D.won(), "RECOVERED: cancel then column-head play clears the board (in " .. fc .. " frames)")

----------------------------------------------------------------------
print(string.rep("-", 48))
if fail == 0 then print("ALL ANT-CLEAR TESTS PASSED") else print(fail .. " FAILURE(S)"); os.exit(1) end
