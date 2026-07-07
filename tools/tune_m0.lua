-- tune_m0.lua — headless bot playtest for the M0 prototypes (NOT part of make
-- test). Plays each prototype with scripted "hands" and prints session-length
-- and score distributions, so difficulty tuning is data-driven before any
-- human playtest. Target band (plan §4 M1): median session 60–180 s.
--
-- Run: lua5.4 tools/tune_m0.lua [runs_per_strategy]

local RUNS = tonumber(arg and arg[1] or "") or 20
local HW, HH = 215, 466
local DT = 1 / 60
local CAP_S = 300                      -- stop a run after 5 minutes

-- deterministic LCG, reseeded per run
local rng = 1
local function lcg() rng = (1103515245 * rng + 12345) % 2147483648; return rng / 2147483648 end
math.random = function(a, b)
  local r = lcg()
  if a == nil then return r end
  if b == nil then return math.floor(r * a) + 1 end
  return math.floor(r * (b - a + 1)) + a
end

-- minimal mock host (no event recording — speed matters here)
local pos, max_id = {}, 0
local noop = function() end
game = {
  log = noop, bounds = function() return HW, HH end,
  spawn = function(x, y) max_id = max_id + 1; pos[max_id] = true; return max_id end,
  spawn_sprite = function(x, y) max_id = max_id + 1; pos[max_id] = true; return max_id end,
  spawn_text = function() max_id = max_id + 1; return max_id end,
  move_to = noop, set_color = noop, set_size = noop, set_rotation = noop,
  set_sprite_image = noop, set_frame = noop, set_tile = noop, set_bone = noop,
  spawn_sheet = function() max_id = max_id + 1; return max_id end,
  tilemap = function() max_id = max_id + 1; return max_id end,
  spawn_rig = function() max_id = max_id + 1; return max_id end,
  play_anim = noop, despawn = noop, set_text = noop, shake = noop, zoom = noop,
  cam = noop, set_bg_theme = noop, emit = noop, set_native_bg = noop,
  play_sound = noop, play_music = noop, play_voice = noop, stop_voice = noop,
  stop_music = noop, set_volume = noop, track = noop, haptic = noop,
  _store = {}, save = function(k, v) game._store[k] = v; return true end,
  load = function(k) return game._store[k] end,
  touches = function() return {} end,
  pointer = function() return game._px, game._py, game._down end,
  key = function() return false end,
  _px = nil, _py = nil, _down = false,
}

dofile("assets/scripts/packs/forge.lua")
dofile("assets/scripts/packs/fireflies.lua")
dofile("assets/scripts/main.lua")

local function enter(key)
  on_start(); on_update(DT)
  for _, t in ipairs(DEBUG.tiles) do
    if t.key == key then on_tap(t.x, t.y); break end
  end
  on_update(DT)
  return DEBUG
end

local function stats(xs)
  table.sort(xs)
  local n = #xs
  local sum = 0
  for _, v in ipairs(xs) do sum = sum + v end
  return xs[1], xs[math.max(1, math.floor(n / 2))], xs[n], sum / n
end

local function report(name, secs, scores)
  local mn, md, mx, avg = stats(secs)
  local smn, smd, smx = stats(scores)
  print(string.format("%-22s sessions: min %5.1fs  median %5.1fs  max %5.1fs  mean %5.1fs", name, mn, md, mx, avg))
  print(string.format("%-22s scores:   min %5d   median %5d   max %5d", "", smn, smd, smx))
end

-- one forge run; hand(frame, d) may tap. returns seconds, score
local function forge_run(seed, hand)
  rng = seed
  local d = enter("forge")
  local f = 0
  while d.alive() and f < CAP_S * 60 do
    f = f + 1
    hand(f, d)
    on_update(DT)
  end
  local s = d.score()
  on_tap(d.back.x, d.back.y); on_update(DT)   -- leave cleanly
  return f / 60, s
end

-- one fireflies run; returns seconds, rings
local function fireflies_run(seed)
  rng = seed
  local d = enter("fireflies")
  local f = 0
  while d.alive() and f < CAP_S * 60 do
    f = f + 1
    -- chaser hand: always herd toward the ring (greedy but plausible player)
    local rx, ry = d.ring_pos()
    game._px, game._py, game._down = rx, ry, true
    on_update(DT)
  end
  local s = d.rings()
  game._down = false
  on_tap(d.back.x, d.back.y); on_update(DT)
  return f / 60, s
end

-- forge hand 1: random tapper (taps a random annulus point every 0.5 s)
local function random_hand(f, d)
  if f % 30 == 0 then
    local ang, rad = lcg() * 6.28, 90 + lcg() * 260
    on_tap(math.cos(ang) * rad, math.sin(ang) * rad)
  end
end

-- forge hand 2: aimer (drops next to an existing star to court fusions)
local function aimer_hand(f, d)
  if f % 24 == 0 then
    local bs = d.bodies()
    if #bs > 0 then
      local b = bs[math.floor(lcg() * #bs) + 1]
      local dd = math.sqrt(b.x * b.x + b.y * b.y)
      if dd > 90 then
        -- drop slightly behind it on the same orbit band
        local ang = math.atan(b.y, b.x) - 0.25
        on_tap(math.cos(ang) * dd, math.sin(ang) * dd)
        return
      end
    end
    local ang, rad = lcg() * 6.28, 120 + lcg() * 180
    on_tap(math.cos(ang) * rad, math.sin(ang) * rad)
  end
end

print(string.format("== M0 bot playtest (%d runs per strategy, cap %ds) ==", RUNS, CAP_S))
for _, strat in ipairs({
  { name = "forge/random", run = function(s) return forge_run(s, random_hand) end },
  { name = "forge/aimer", run = function(s) return forge_run(s, aimer_hand) end },
  { name = "fireflies/chaser", run = fireflies_run },
}) do
  local secs, scores = {}, {}
  for i = 1, RUNS do
    local s, sc = strat.run(1000 + i * 7919)
    secs[#secs + 1] = s
    scores[#scores + 1] = sc
  end
  report(strat.name, secs, scores)
end
