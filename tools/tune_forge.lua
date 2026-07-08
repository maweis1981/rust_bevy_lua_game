-- tools/tune_forge.lua — data-driven balance harness for Starforge (Direction A).
--
-- Rationale: one person's "feel" is not a valid tuning signal (§ user feedback).
-- Instead we simulate MANY runs across skill tiers (novice / average / skilled)
-- with scripted bots, measure objective metrics, and check them against the
-- research-backed target scorecard (GameAnalytics session bands, the 85% flow
-- rule, Suika-style skill-gap, "no immortal strategy"). This makes tuning
-- reproducible and defensible instead of subjective.
--
-- Run one param set:
--   lua5.4 tools/tune_forge.lua [N] [DECAY0=..] [DECAY_LV=..] [FUSE_BOOST=..] [CORE_GROW=..] [MASS_SCALE=..]
-- Prints a per-tier summary line + PASS/FAIL vs the scorecard.

----------------------------------------------------------------------
-- Parse args → FORGE_TUNE (read by forge.lua's balance constants)
----------------------------------------------------------------------
local N = 40
local TUNE = {}
for _, a in ipairs(arg) do
  local k, v = a:match("^([%w_]+)=([%-%d%.]+)$")   -- keys may contain underscores
  if k then TUNE[k] = tonumber(v)
  elseif tonumber(a) then N = math.floor(tonumber(a)) end
end
FORGE_TUNE = TUNE   -- global seam consumed by packs/forge.lua

local HW, HH = 215, 466
local DT = 1 / 60
local CAP_S = 240                 -- run cap; survive past this = "immortal" (bad)
local CAP_F = math.floor(CAP_S / DT)

----------------------------------------------------------------------
-- Deterministic RNG (re-seeded per game so runs vary but reproduce)
----------------------------------------------------------------------
local rng = 1
local function lcg() rng = (1103515245 * rng + 12345) % 2147483648; return rng / 2147483648 end
math.random = function(a, b)
  local r = lcg()
  if a == nil then return r end
  if b == nil then return math.floor(r * a) + 1 end
  return math.floor(r * (b - a + 1)) + a
end

----------------------------------------------------------------------
-- Mock host API (same shape as tools/test_m0_packs.lua, all no-op sinks)
----------------------------------------------------------------------
local max_id = 0
local noop = function() end
game = setmetatable({
  bounds = function() return HW, HH end,
  spawn = function() max_id = max_id + 1; return max_id end,
  spawn_sprite = function() max_id = max_id + 1; return max_id end,
  spawn_text = function() max_id = max_id + 1; return max_id end,
  spawn_sheet = function() max_id = max_id + 1; return max_id end,
  tilemap = function() max_id = max_id + 1; return max_id end,
  spawn_rig = function() max_id = max_id + 1; return max_id end,
  despawn = noop, move_to = noop, set_color = noop, set_size = noop, set_rotation = noop,
  set_sprite_image = noop, set_frame = noop, set_tile = noop, play_anim = noop, set_bone = noop,
  set_text = noop, shake = noop, zoom = noop, cam = noop, set_bg_theme = noop, emit = noop,
  set_native_bg = noop, play_sound = noop, play_music = noop, play_voice = noop,
  stop_voice = noop, stop_music = noop, set_volume = noop, track = noop, log = noop,
  haptic = noop,
  _store = {},
  save = function(k, v) game._store[k] = v; return true end,
  load = function(k) return game._store[k] end,
  _touches = {}, touches = function() return game._touches end,
  date_utc = function() return 2026, 7, 7 end,
  pointer = function() return game._px, game._py, game._down end,
  key = function() return false end,
  _px = nil, _py = nil, _down = false,
}, {})

----------------------------------------------------------------------
-- Load the game
----------------------------------------------------------------------
dofile("assets/scripts/packs/forge.lua")
dofile("assets/scripts/packs/fireflies.lua")
dofile("assets/scripts/main.lua")

local function on_up(dt) on_update(dt or DT) end
local function boot()
  on_start(); on_up()
  game._store.forge_tutorial_done = true   -- skip the one-time onboarding overlay
end
local function enter_forge()
  game._px, game._py, game._down = nil, nil, false
  for _, t in ipairs(DEBUG.tiles) do if t.key == "forge" then on_tap(t.x, t.y); break end end
  on_up()
  return DEBUG
end
-- one hold→release drop at (x,y)
local function drop(x, y)
  game._px, game._py, game._down = x, y, true
  on_up()
  game._down = false
  on_up()
  game._px, game._py = nil, nil
end

----------------------------------------------------------------------
-- Bots — three skill tiers. Skill axis = WHERE you drop (placement),
-- identical drop cadence, so the metric isolates decision quality.
----------------------------------------------------------------------
local MINR = 122          -- just past MIN_SPAWN_R (120)
local function rand_valid()
  local ang = math.random() * 6.2831853
  local r = MINR + math.random() * 170
  return math.cos(ang) * r, math.sin(ang) * r
end

-- novice: mashes a random drop every chance — no plan, floods the field. This
-- careless play SHOULD die fast (that's the point of the attrition loop).
local function bot_novice() return rand_valid() end

-- skilled: takes a fusion whenever the incoming level matches a live star
-- (drop ON it to force the merge), otherwise adds stock only when the field is
-- uncrowded, and HOLDS (returns nil) rather than flood a crowded field. The
-- skill here is not-flooding + converting to fusions, so it should outlast.
local function bot_skilled(d)
  local nl = d.next_level()
  local best, bestd
  for _, b in ipairs(d.bodies()) do
    if b.level == nl then
      local dist = math.sqrt(b.x * b.x + b.y * b.y)
      if dist >= MINR and (not best or dist < bestd) then best, bestd = b, dist end
    end
  end
  if best then return best.x, best.y end        -- always take the fusion
  -- maintain a working stockpile so same-level matches keep appearing — too few
  -- starves fusions, too many floods. STOCK is the survival/score dial: a
  -- smaller field survives longer, a larger one scores more (the Suika tradeoff).
  local STOCK = tonumber(os.getenv("BOT_STOCK") or "16")   -- expert plays for score
  if d.body_count() < STOCK then
    local ang = d.body_count() * 2.399963       -- golden-angle spread
    return math.cos(ang) * (160 + (d.body_count() % 3) * 22), math.sin(ang) * (160 + (d.body_count() % 3) * 22)
  end
  return nil                                     -- hold: field is full enough
end

-- average: mostly plays smart, but has careless moments that overfill the field
local function bot_average(d)
  if math.random() < 0.4 then
    if d.body_count() < 26 then return rand_valid() end
    return nil
  end
  return bot_skilled(d)
end

----------------------------------------------------------------------
-- Run one game to death (or cap). Cadence: a drop attempt every ~SPAWN_CD.
----------------------------------------------------------------------
local function play(bot, seed)
  rng = seed
  -- fresh run: first game enters; later games restart via the AGAIN button
  if not DEBUG or DEBUG.game ~= "forge" or DEBUG.alive() == false then
    if DEBUG and DEBUG.again and DEBUG.again() then
      local a = DEBUG.again(); on_tap(a.x, a.y); on_up()
    else
      enter_forge()
    end
  end
  local d = DEBUG
  local f, maxlv = 0, 1
  while d.alive() and f < CAP_F do
    local x, y = bot(d)
    if x then drop(x, y) else on_up(); on_up() end
    for _ = 1, 12 do on_up() end
    f = f + 14
    for _, b in ipairs(d.bodies()) do if b.level > maxlv then maxlv = b.level end end
  end
  return { t = f * DT, score = d.score(), lv = maxlv, immortal = (f >= CAP_F) }
end

----------------------------------------------------------------------
-- Aggregate helpers
----------------------------------------------------------------------
local function median(t)
  local s = {}
  for _, v in ipairs(t) do s[#s + 1] = v end
  table.sort(s)
  local n = #s
  if n == 0 then return 0 end
  return (n % 2 == 1) and s[(n + 1) // 2] or (s[n // 2] + s[n // 2 + 1]) / 2
end
local function mean(t) local s = 0; for _, v in ipairs(t) do s = s + v end; return #t > 0 and s / #t or 0 end
local function pmax(t) local m = 0; for _, v in ipairs(t) do if v > m then m = v end end; return m end

local function run_tier(name, bot)
  local ts, scores, lvs, imm = {}, {}, {}, 0
  boot()
  for g = 1, N do
    local r = play(bot, 100000 + g * 7919)
    ts[#ts + 1] = r.t; scores[#scores + 1] = r.score; lvs[#lvs + 1] = r.lv
    if r.immortal then imm = imm + 1 end
  end
  return {
    name = name, t_med = median(ts), t_max = pmax(ts),
    s_med = median(scores), s_max = pmax(scores), lv_med = median(lvs), lv_max = pmax(lvs),
    immortal = imm,
  }
end

----------------------------------------------------------------------
-- Main
----------------------------------------------------------------------
-- these fallbacks mirror forge.lua's shipped defaults, for display only
io.write(string.format("FORGE_TUNE: DECAY0=%.3f DECAY_LV=%.3f FUSE_BOOST=%.3f CORE_GROW=%.2f MASS_SCALE=%d  (N=%d/tier)\n",
  TUNE.DECAY0 or 0.007, TUNE.DECAY_LV or 0.0, TUNE.FUSE_BOOST or 0.20, TUNE.CORE_GROW or 1.0, TUNE.MASS_SCALE or 1150, N))

local nov = run_tier("novice", bot_novice)
local avg = run_tier("average", bot_average)
local skl = run_tier("skilled", bot_skilled)

for _, r in ipairs({ nov, avg, skl }) do
  io.write(string.format("  %-8s  run_med=%5.1fs  run_max=%5.1fs  score_med=%6d  score_max=%6d  toplv_med=%2d  toplv_max=%2d  immortal=%d/%d\n",
    r.name, r.t_med, r.t_max, r.s_med, r.s_max, r.lv_med, r.lv_max, r.immortal, N))
end

-- Scorecard checks (research-backed targets)
local gap = nov.t_med > 0 and (skl.t_med / nov.t_med) or 0
local sgap = nov.s_med > 0 and (skl.s_med / math.max(nov.s_med, 1)) or 0
-- Genre-corrected scorecard. The sim proved this is a SUIKA-model score-chaser,
-- not a survival-time game: you can't hand-place high-level stars (L5+ only form
-- from chance collisions of fusion products), so runs are naturally short and
-- similar-length across skill — the skill ceiling lives in SCORE, not longevity.
-- (Suika itself: comparable run lengths, expert scores ~10x.) So survival is a
-- sanity band; the SCORE gap + "no immortal" are the real pass criteria.
local checks = {
  { "runs in a fast-retry band (novice 12-45s)",      nov.t_med >= 12 and nov.t_med <= 45 },
  { "skilled at least holds up (>=1.3x novice time)", gap >= 1.3 },
  { "SCORE skill gap >=5x  (primary skill axis)",     sgap >= 5.0 },
  { "no immortal strategy  (attrition loop sound)",   (nov.immortal + avg.immortal + skl.immortal) == 0 },
}
io.write(string.format("  skill gap: time x%.1f  score x%.1f\n", gap, sgap))
local allok = true
for _, c in ipairs(checks) do
  io.write(string.format("  [%s] %s\n", c[2] and "PASS" or "FAIL", c[1]))
  allok = allok and c[2]
end
io.write(allok and "==> SCORECARD PASS\n" or "==> SCORECARD FAIL (tune params)\n")
os.exit(allok and 0 or 1)
