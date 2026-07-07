-- Headless invariant tests for the M0 graybox prototypes:
--   packs/forge.lua      (Starforge  — central gravity  + fusion merging)
--   packs/fireflies.lua  (Fireflies  — boids three rules + light herding)
--
-- Mirrors tools/test_pong.lua: mocks the Rust `game` API, drives the router
-- and each pack for thousands of frames, and asserts the math-core contracts
-- from docs/hybrid-casual-math-game-plan.md §2.3 / issues #60 #61.
--
-- Run: lua5.4 tools/test_m0_packs.lua   (exits non-zero on any failure)

local HW, HH = 215, 466
local DT = 1 / 60

----------------------------------------------------------------------
-- RNG override (deterministic LCG; rand_mode "good" pins r = 0.1)
----------------------------------------------------------------------
local rand_mode = "mixed"
local rng = 987654321
local function lcg() rng = (1103515245 * rng + 12345) % 2147483648; return rng / 2147483648 end
math.random = function(a, b)
  local r
  if rand_mode == "good" then r = 0.1 else r = lcg() end
  if a == nil then return r end
  if b == nil then return math.floor(r * a) + 1 end
  return math.floor(r * (b - a + 1)) + a
end

----------------------------------------------------------------------
-- Mock host API (same shape as test_pong.lua)
----------------------------------------------------------------------
local dims, pos, max_id = {}, {}, 0
local frame_events
local function record(n, a) if frame_events then frame_events[#frame_events + 1] = { n, a } end end

game = {
  log = function(m) record("log", m) end,
  bounds = function() return HW, HH end,
  spawn = function(x, y, w, h) max_id = max_id + 1; dims[max_id] = { w = w, h = h }; pos[max_id] = { x = x, y = y }; return max_id end,
  spawn_sprite = function(x, y, w, h) max_id = max_id + 1; dims[max_id] = { w = w, h = h }; pos[max_id] = { x = x, y = y }; return max_id end,
  spawn_text = function(x, y) max_id = max_id + 1; dims[max_id] = { w = 0, h = 0 }; pos[max_id] = { x = x, y = y }; return max_id end,
  move_to = function(id, x, y) pos[id] = { x = x, y = y } end,
  set_color = function() end,
  set_size = function(id, w, h) dims[id] = { w = w, h = h } end,
  set_rotation = function() end,
  set_sprite_image = function() end,
  spawn_sheet = function(x, y, w, h) max_id = max_id + 1; dims[max_id] = { w = w, h = h }; pos[max_id] = { x = x, y = y }; return max_id end,
  set_frame = function() end,
  tilemap = function(x, y) max_id = max_id + 1; dims[max_id] = { w = 0, h = 0 }; pos[max_id] = { x = x, y = y }; return max_id end,
  set_tile = function() end,
  spawn_rig = function(x, y) max_id = max_id + 1; dims[max_id] = { w = 0, h = 0 }; pos[max_id] = { x = x, y = y }; return max_id end,
  play_anim = function(id, c) record("anim", c) end,
  set_bone = function() end,
  despawn = function(id) pos[id] = nil; dims[id] = nil end,
  set_text = function() end,
  shake = function(v) record("shake", v) end,
  zoom = function(v) record("zoom", v) end,
  cam = function(x, y, z) record("cam", z) end,
  set_bg_theme = function(v) record("bg_theme", v) end,
  emit = function(p) record("emit", p) end,
  set_native_bg = function(n) record("native_bg", n) end,
  play_sound = function(n) record("sound", n) end,
  play_music = function(n) record("music", n) end,
  play_voice = function(n) record("voice", n) end,
  stop_voice = function() record("stopvoice") end,
  stop_music = function() record("stopmusic") end,
  set_volume = function(c, v) record("volume", c) end,
  track = function(e) record("track", e) end,
  _store = {},
  save = function(k, v)
    local t = type(v)
    if t ~= "string" and t ~= "number" and t ~= "boolean" then return false end
    game._store[k] = v; record("save", k); return true
  end,
  load = function(k) return game._store[k] end,
  _touches = {},
  touches = function() return game._touches end,
  haptic = function(k) record("haptic", k) end,
  pointer = function() return game._px, game._py, game._down end,
  key = function(n) return game._keys[n] == true end,
  _px = nil, _py = nil, _down = false, _keys = {},
}
local function events_have(n, a)
  for _, e in ipairs(frame_events) do if e[1] == n and (a == nil or e[2] == a) then return true end end
  return false
end
local function clear_input() game._px, game._py, game._down, game._keys = nil, nil, false, {} end

----------------------------------------------------------------------
-- Assertions
----------------------------------------------------------------------
local failures, checks, seen = {}, 0, {}
local function check(c, m) checks = checks + 1; if not c then failures[#failures + 1] = m end end
local function check_once(k, c, m)
  checks = checks + 1
  if not c and not seen[k] then seen[k] = true; failures[#failures + 1] = m end
end

-- Load only what these tests need: the two M0 packs, then the router.
dofile("assets/scripts/packs/forge.lua")
dofile("assets/scripts/packs/fireflies.lua")
dofile("assets/scripts/main.lua")

local function boot() rng = 987654321; frame_events = {}; on_start(); frame_events = {}; on_update(DT) end
local function enter(key)
  clear_input()
  for _, t in ipairs(DEBUG.tiles) do
    if t.key == key then on_tap(t.x, t.y); break end
  end
  frame_events = {}; on_update(DT)
  return DEBUG
end
local function step(dt) frame_events = {}; on_update(dt or DT) end
local function finite(v) return v == v and v > -1e9 and v < 1e9 end

-- forge input model (M1): hold to aim, release to launch
local function inject_at(x, y)
  game._px, game._py, game._down = x, y, true
  step()                       -- aiming frame (ghost + tangent dots)
  game._down = false
  step()                       -- release frame -> injection
end

----------------------------------------------------------------------
-- Starforge — math-core contracts
----------------------------------------------------------------------
local F_VMAX, F_RMAX = 620, math.sqrt(HW * HW + HH * HH) + 80

local function forge_body_invariants(d, tag)
  local sum = 0
  for _, b in ipairs(d.bodies()) do
    check_once(tag .. "_fin", finite(b.x) and finite(b.y) and finite(b.vx) and finite(b.vy),
      "forge: non-finite body state (" .. tag .. ")")
    check_once(tag .. "_lvl", b.level >= 1 and b.level <= 10, "forge: level out of range (" .. tag .. ")")
    check_once(tag .. "_mass", b.m == 2 ^ (b.level - 1), "forge: mass != 2^(level-1) (" .. tag .. ")")
    local sp = math.sqrt(b.vx ^ 2 + b.vy ^ 2)
    check_once(tag .. "_vcap", sp <= F_VMAX + 1.0, string.format("forge: speed %.0f over cap (%s)", sp, tag))
    local dist = math.sqrt(b.x ^ 2 + b.y ^ 2)
    check_once(tag .. "_rmax", dist <= F_RMAX + F_VMAX * DT + 1,
      string.format("forge: body at r=%.0f beyond escape cull (%s)", dist, tag))
    sum = sum + b.m
  end
  check_once(tag .. "_tm", d.total_mass() >= sum - 1e-6,
    "forge: total_mass fell below the sum of live bodies (" .. tag .. ")")
  check_once(tag .. "_cnt", d.body_count() <= 48, "forge: body cap exceeded (" .. tag .. ")")
end

local function forge_orbit_stability()
  boot(); rand_mode = "good"                    -- next_level pinned to 1
  local d = enter("forge")
  check(d and d.game == "forge", "menu tile should enter forge")
  check(d.back ~= nil, "forge should expose a back button")
  inject_at(150, 0)
  check(d.body_count() == 1, "one hold-release injection should orbit exactly one star")
  for _ = 1, 1200 do
    step()
    forge_body_invariants(d, "orbit")
  end
  check(d.body_count() == 1, "a lone star on a circular orbit must neither fall in nor escape")
  local b = d.bodies()[1]
  local dist = math.sqrt(b.x ^ 2 + b.y ^ 2)
  check(math.abs(dist - 150) < 30, string.format("circular orbit drifted: r=%.0f (want ~150)", dist))
  on_tap(d.back.x, d.back.y); step()
end

local function forge_fusion()
  boot(); rand_mode = "good"
  local d = enter("forge")
  inject_at(150, 0)
  for _ = 1, 20 do step() end                   -- clear the injection cooldown
  local s0 = d.score()                          -- before the pair can touch
  -- drop the second star 12px radially outside the first one's CURRENT spot:
  -- overlap is structural, not a phase coincidence
  local b1 = d.bodies()[1]
  local dd = math.sqrt(b1.x * b1.x + b1.y * b1.y)
  inject_at(b1.x * (1 + 12 / dd), b1.y * (1 + 12 / dd))
  local fused = false
  for _ = 1, 1800 do
    step()
    forge_body_invariants(d, "fuse")
    local bs = d.bodies()
    if #bs == 1 and bs[1].level == 2 then fused = true; break end
  end
  check(fused, "two L1 stars on the same orbit band should fuse into one L2")
  check(d.score() > s0, "fusion must raise the score")
  on_tap(d.back.x, d.back.y); step()
end

local function forge_long_run()
  boot(); rand_mode = "mixed"
  local d = enter("forge")
  local saw_over, restarted = false, false
  local taps = 0
  for f = 1, 6000 do
    if d.alive() then
      if f % 30 == 0 and taps < 60 then
        local ang, rad = lcg() * 6.28, 90 + lcg() * 250
        inject_at(math.cos(ang) * rad, math.sin(ang) * rad)
        taps = taps + 1
      end
      step()
      forge_body_invariants(d, "long")
    else
      saw_over = true
      check(d.again() ~= nil, "settlement card must expose the FORGE AGAIN button")
      on_tap(0, 0); step()                      -- tap anywhere restarts
      check(d.alive(), "tap after game over must restart the run")
      check(d.score() == 0, "restart must reset the score")
      check(d.again() == nil, "restart must clear the settlement card")
      restarted = true
    end
  end
  check(taps > 0, "long run should have injected stars")
  if saw_over then check(restarted, "game over must be recoverable") end
  -- big-dt hitch: capped dt means no star may teleport
  local before = {}
  for k, b in ipairs(d.bodies()) do before[k] = { x = b.x, y = b.y } end
  step(0.25)
  for k, b in ipairs(d.bodies()) do
    if before[k] then
      local jump = math.sqrt((b.x - before[k].x) ^ 2 + (b.y - before[k].y) ^ 2)
      check_once("f_dt", jump <= F_VMAX * (1 / 30) + 1.0,
        string.format("forge: big-dt hitch teleported a star %.0fpx", jump))
    end
  end
  on_tap(d.back.x, d.back.y); step()
end

local function forge_teaching()
  boot(); rand_mode = "mixed"
  game._store.forge_runs = nil                  -- brand-new player
  local d = enter("forge")
  -- the first run must deal the fixed teaching hand so a fusion is guaranteed
  local want = { 1, 1, 1, 2, 2, 3 }
  for k, lvl in ipairs(want) do
    check(d.next_level() == lvl, string.format("teach deal %d should be L%d (got L%d)", k, lvl, d.next_level()))
    inject_at(150 + k * 9, k * 7)
    for _ = 1, 14 do step() end                 -- clear the injection cooldown
  end
  -- holding must never inject; only the release does. (The released star may
  -- fuse on arrival, so assert via the mass ledger, not the body count.)
  local n0, tm0 = d.body_count(), d.total_mass()
  local lvl = d.next_level()
  game._px, game._py, game._down = 60, 160, true
  for _ = 1, 30 do step() end
  check(d.body_count() == n0 and d.total_mass() == tm0, "holding (aiming) must not inject a star")
  game._down = false; step()
  check(d.total_mass() >= tm0 + 2 ^ (lvl - 1) - 1e-6,
    "release after aiming must inject exactly one star (mass ledger)")
  clear_input()
  on_tap(d.back.x, d.back.y); step()
end

----------------------------------------------------------------------
-- Fireflies — boids contracts
----------------------------------------------------------------------
local B_VMAX = 250

local function boid_invariants(d, tag)
  for _, b in ipairs(d.boids()) do
    check_once(tag .. "_fin", finite(b.x) and finite(b.y) and finite(b.vx) and finite(b.vy),
      "boids: non-finite state (" .. tag .. ")")
    local sp = math.sqrt(b.vx ^ 2 + b.vy ^ 2)
    check_once(tag .. "_vcap", sp <= B_VMAX + 1.0, string.format("boids: speed %.0f over cap (%s)", sp, tag))
    check_once(tag .. "_in", math.abs(b.x) <= HW + 0.5 and math.abs(b.y) <= HH + 0.5,
      "boids: firefly left the screen (" .. tag .. ")")
  end
end

local function fireflies_cohesion()
  boot(); rand_mode = "good"
  local d = enter("fireflies")
  check(d and d.game == "fireflies", "menu tile should enter fireflies")
  check(d.back ~= nil, "fireflies should expose a back button")
  check(d.flock() == 40, "swarm should start at 40")
  game._px, game._py, game._down = 0, 0, true   -- hold the light at the centre
  for _ = 1, 900 do
    step()
    boid_invariants(d, "coh")
  end
  local bs, cx, cy = d.boids(), 0, 0
  for _, b in ipairs(bs) do cx = cx + b.x; cy = cy + b.y end
  cx, cy = cx / #bs, cy / #bs
  local mean = 0
  for _, b in ipairs(bs) do mean = mean + math.sqrt((b.x - cx) ^ 2 + (b.y - cy) ^ 2) end
  mean = mean / #bs
  check(mean <= 150, string.format("swarm did not cohere around the light (mean spread %.0f)", mean))
  check(d.flock() == 40, "no firefly may die while no web exists")
  -- big-dt hitch
  local before = {}
  for k, b in ipairs(bs) do before[k] = { x = b.x, y = b.y } end
  step(0.25)
  for k, b in ipairs(d.boids()) do
    if before[k] then
      local jump = math.sqrt((b.x - before[k].x) ^ 2 + (b.y - before[k].y) ^ 2)
      check_once("b_dt", jump <= B_VMAX * (1 / 30) + 1.0,
        string.format("boids: big-dt hitch teleported a firefly %.0fpx", jump))
    end
  end
  clear_input()
  on_tap(d.back.x, d.back.y); step()
end

local function fireflies_scoring_and_loss()
  boot(); rand_mode = "mixed"
  local d = enter("fireflies")
  -- herd the swarm into the ring and hold until it scores
  local scored = false
  for _ = 1, 4000 do
    local rx, ry = d.ring_pos()
    game._px, game._py, game._down = rx, ry, true
    step()
    boid_invariants(d, "score")
    if d.rings() >= 1 then scored = true; break end
  end
  check(scored, "holding the swarm inside the ring should score within ~66s")
  check(d.web_count() >= 1, "every scored ring must spawn a web")
  -- now park the light on the web: the swarm must take losses
  local flock0 = d.flock()
  local lost = false
  for _ = 1, 2400 do
    local ws = d.webs()
    if #ws == 0 then break end
    game._px, game._py, game._down = ws[1].x, ws[1].y, true
    step()
    boid_invariants(d, "loss")
    if d.flock() < flock0 then lost = true; break end
  end
  check(lost, "parking the swarm on a web must cost fireflies")
  -- drive it to game over, then restart
  local over = false
  for _ = 1, 20000 do
    if not d.alive() then over = true; break end
    local ws = d.webs()
    if #ws > 0 then game._px, game._py, game._down = ws[1].x, ws[1].y, true end
    step()
  end
  check(over, "attrition should eventually end the run")
  check(d.again() ~= nil, "fireflies settlement card must expose the GLOW AGAIN button")
  clear_input()
  on_tap(0, 0); step()
  check(d.alive() and d.flock() == 40, "tap after game over must restart with a full swarm")
  check(d.again() == nil, "restart must clear the fireflies settlement card")
  on_tap(d.back.x, d.back.y); step()
end

----------------------------------------------------------------------
forge_orbit_stability()
forge_fusion()
forge_long_run()
forge_teaching()
fireflies_cohesion()
fireflies_scoring_and_loss()

print(string.format("checks=%d", checks))
if #failures == 0 then
  print("PASS — M0 graybox math-core invariants held")
  os.exit(0)
else
  print(string.format("FAIL — %d violated:", #failures))
  for _, f in ipairs(failures) do print("  - " .. f) end
  os.exit(1)
end
