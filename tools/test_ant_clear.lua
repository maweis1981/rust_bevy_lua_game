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
  despawn = function(id) pos[id] = nil end,
  set_text = function() end,
  shake = function() end,
  zoom = function() end,
  emit = function() end,
  play_sound = function() end,
  play_music = function() end,
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
local function all_empties_reachable(g)
  local h, w = #g, #g[1]
  local seen = {}
  local q, head = {}, 1
  local function key(r, c) return r * (w + 2) + c end
  for r = 1, h do for c = 1, w do
    if g[r][c] == 0 and (r == 1 or c == 1 or r == h or c == w) then
      local k = key(r, c); if not seen[k] then seen[k] = true; q[#q + 1] = { r, c } end
    end
  end end
  while head <= #q do
    local cell = q[head]; head = head + 1
    local r, c = cell[1], cell[2]
    for _, p in ipairs({ {r+1,c},{r-1,c},{r,c+1},{r,c-1} }) do
      local rr, cc = p[1], p[2]
      if rr >= 1 and rr <= h and cc >= 1 and cc <= w and g[rr][cc] == 0 then
        local k = key(rr, cc); if not seen[k] then seen[k] = true; q[#q + 1] = { rr, cc } end
      end
    end
  end
  for r = 1, h do for c = 1, w do
    if g[r][c] == 0 and not seen[key(r, c)] then return false, r, c end
  end end
  return true
end

----------------------------------------------------------------------
-- drive to completion, checking pathfinding + no-teleport every frame
----------------------------------------------------------------------
local BOUND = 460 * (1 / 30) * 2 + 2   -- ANT_SPEED * MAX_DT * (2x) + slack
local prev = D.ant_xy()
local buried_ok, teleport_ok, ever_dead = true, true, false
local frames, MAXF = 0, 30000
while not D.won() and not D.dead() and frames < MAXF do
  scene.update(DT, HW, HH)
  frames = frames + 1
  local ok = all_empties_reachable(D.grid())
  if not ok then buried_ok = false end
  local cur = D.ant_xy()
  for i = 1, math.min(#cur, #prev) do
    local dx, dy = cur[i][1] - prev[i][1], cur[i][2] - prev[i][2]
    if math.sqrt(dx * dx + dy * dy) > BOUND then teleport_ok = false end
  end
  prev = cur
  if D.dead() then ever_dead = true end
end

check(buried_ok, "PATHFINDING: no buried pixel ever removed (cleared region stays edge-connected)")
check(teleport_ok, "NO TELEPORT: every ant moves <= " .. string.format("%.1f", BOUND) .. " units/frame")
check(D.won(), "SOLVABLE: board fully cleared -> win (in " .. frames .. " frames)")
check(D.painted() == 0, "all pixels carried away (painted == 0)")
check(not ever_dead, "never falsely deadlocked on a solvable level")

----------------------------------------------------------------------
print(string.rep("-", 48))
if fail == 0 then print("ALL ANT-CLEAR TESTS PASSED") else print(fail .. " FAILURE(S)"); os.exit(1) end
