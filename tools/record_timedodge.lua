-- record_timedodge.lua — headless gameplay recorder for the Time Dodge pack.
--
-- Mocks the Rust `game` API (like tools/test_pong.lua), boots the router, enters
-- Time Dodge, and plays it with a small autopilot that alternates FREEZE (hold
-- still, world stops) and DODGE (dash perpendicular to incoming bullets) — the
-- signature "time moves when you move" rhythm — then deliberately ends the run
-- so the clip closes on the death freeze-frame. Every sim frame is dumped as a
-- JSON line for tools/render_timedodge_gif.py to render into shareable GIFs.
--
-- Run: lua5.4 tools/record_timedodge.lua   (writes build/timedodge_frames.jsonl)

local HW, HH = 195, 422        -- world half-extents == half the render canvas
local DT = 1 / 60
local OUT = "build/timedodge_frames.jsonl"

-- Deterministic RNG so the clip is reproducible.
local rng = 424242
local function lcg() rng = (1103515245 * rng + 12345) % 2147483648; return rng / 2147483648 end
math.random = function(a, b)
  local r = lcg()
  if a == nil then return r end
  if b == nil then return math.floor(r * a) + 1 end
  return math.floor(r * (b - a + 1)) + a
end

----------------------------------------------------------------------
-- Mock host API (records entity state instead of drawing)
----------------------------------------------------------------------
local ents, max_id = {}, 0          -- id -> {x,y,w,h,r,g,b,a,tex}
local hud_text, frame_fx = "", {}
local function add(x, y, w, h, r, g, b, a, tex)
  max_id = max_id + 1
  ents[max_id] = { x = x, y = y, w = w or 0, h = h or 0,
                   r = r or 1, g = g or 1, b = b or 1, a = a or 1, tex = tex }
  return max_id
end

game = {
  log = function() end,
  bounds = function() return HW, HH end,
  spawn = function(x, y, w, h, r, g, b, a) return add(x, y, w, h, r, g, b, a, "rect") end,
  spawn_sprite = function(x, y, w, h, name) return add(x, y, w, h, 1, 1, 1, 1, name) end,
  spawn_text = function(x, y, size, r, g, b, a, str)
    local id = add(x, y, 0, size, r, g, b, a, "text"); ents[id].str = str; return id
  end,
  move_to = function(id, x, y) local e = ents[id]; if e then e.x, e.y = x, y end end,
  set_color = function(id, r, g, b, a)
    local e = ents[id]; if e then e.r, e.g, e.b, e.a = r, g, b, a end
  end,
  set_size = function(id, w, h) local e = ents[id]; if e then e.w, e.h = w, h end end,
  set_rotation = function() end,
  set_sprite_image = function() end,
  spawn_sheet = function(x, y, w, h) return add(x, y, w, h, 1, 1, 1, 1, "sheet") end,
  set_frame = function() end,
  tilemap = function(x, y) return add(x, y, 0, 0, 1, 1, 1, 1, "tilemap") end,
  set_tile = function() end,
  spawn_rig = function(x, y) return add(x, y, 0, 0, 1, 1, 1, 1, "rig") end,
  play_anim = function() end,
  set_bone = function() end,
  despawn = function(id) ents[id] = nil end,
  set_text = function(s) hud_text = s or "" end,
  shake = function(v) frame_fx[#frame_fx + 1] = { "shake", v } end,
  zoom = function(v) frame_fx[#frame_fx + 1] = { "zoom", v } end,
  cam = function() end,
  set_bg_theme = function() end,
  emit = function() end,
  set_native_bg = function() end,
  play_sound = function(n) frame_fx[#frame_fx + 1] = { "sound", n } end,
  play_music = function() end,
  play_voice = function() end,
  stop_voice = function() end,
  stop_music = function() end,
  set_volume = function() end,
  track = function() end,
  _store = {},
  save = function(k, v) game._store[k] = v; return true end,
  load = function(k) return game._store[k] end,
  touches = function() return {} end,
  haptic = function() end,
  pointer = function() return game._px, game._py, game._down end,
  key = function() return false end,
  _px = nil, _py = nil, _down = false,
}

-- Only the pack under test + the router are needed (menu also shows the three
-- built-in games; their factories live in main.lua itself).
dofile("assets/scripts/packs/timedodge.lua")
dofile("assets/scripts/main.lua")

on_start(); on_update(DT)
for _, t in ipairs(DEBUG.tiles) do
  if t.key == "timedodge" then on_tap(t.x, t.y); break end
end
on_update(DT)
assert(DEBUG.game == "timedodge", "failed to enter timedodge")

----------------------------------------------------------------------
-- JSON dump (tiny hand-rolled serializer — numbers + strings only)
----------------------------------------------------------------------
local function jstr(s) return '"' .. s:gsub('[\\"]', '\\%0'):gsub("\n", "\\n") .. '"' end
local out = assert(io.open(OUT, "w"))
local function dump_frame(n)
  local parts = {}
  for id, e in pairs(ents) do
    parts[#parts + 1] = string.format(
      '[%d,%.1f,%.1f,%.1f,%.1f,%.3f,%.3f,%.3f,%.3f,%s]',
      id, e.x, e.y, e.w, e.h, e.r, e.g, e.b, e.a, jstr(e.tex or "rect"))
  end
  local fx = {}
  for _, f in ipairs(frame_fx) do
    fx[#fx + 1] = string.format('[%s,%s]', jstr(f[1]),
      type(f[2]) == "number" and string.format("%.3f", f[2]) or jstr(tostring(f[2])))
  end
  out:write(string.format(
    '{"n":%d,"ts":%.3f,"alive":%s,"hud":%s,"fx":[%s],"ents":[%s]}\n',
    n, DEBUG.timescale and DEBUG.timescale() or 1,
    tostring(DEBUG.alive and DEBUG.alive() or false),
    jstr(hud_text), table.concat(fx, ","), table.concat(parts, ",")))
end

----------------------------------------------------------------------
-- Autopilot: opening dash -> freeze/dodge cycles -> a deliberate final hit
----------------------------------------------------------------------
local prev_b = {}                -- bullet id -> previous position (for velocity)
local freeze_left, dash_left = 0, 0.9
local t = 0

local function player_pos()
  local p = ents[DEBUG.player]
  return p and p.x or 0, p and p.y or 0
end

local function think(px, py)
  -- Estimate bullet velocities from the recorded positions.
  local threats, nearest, nd = {}, nil, 1e9
  local cur = {}
  for _, id in ipairs(DEBUG.bullet_ids()) do
    local e = ents[id]
    if e then
      cur[id] = { x = e.x, y = e.y }
      local pb = prev_b[id]
      local vx, vy = 0, 0
      if pb then vx, vy = (e.x - pb.x) / DT, (e.y - pb.y) / DT end
      local dx, dy = px - e.x, py - e.y
      local d = math.sqrt(dx * dx + dy * dy)
      if d < nd then nd, nearest = d, { x = e.x, y = e.y, vx = vx, vy = vy, d = d } end
      -- threatening = close and (frozen counts too: it WILL close when we move)
      if d < 200 then threats[#threats + 1] = { x = e.x, y = e.y, vx = vx, vy = vy, d = d } end
    end
  end
  prev_b = cur
  return threats, nearest, nd
end

local function dodge_vector(px, py, threats)
  local ax, ay = -px * 0.004, -py * 0.004          -- gentle pull to centre
  for _, b in ipairs(threats) do
    local sp = math.sqrt(b.vx * b.vx + b.vy * b.vy)
    local nx, ny
    if sp > 1 then nx, ny = b.vx / sp, b.vy / sp     -- bullet heading
    else local d = math.max(b.d, 1); nx, ny = (px - b.x) / d, (py - b.y) / d end
    -- steer perpendicular to the bullet's path, away from our side of it
    local pxn, pyn = -ny, nx
    local side = (px - b.x) * pxn + (py - b.y) * pyn
    if side < 0 then pxn, pyn = -pxn, -pyn end
    local w = 1 / math.max(b.d, 20)
    ax, ay = ax + pxn * w * 60, ay + pyn * w * 60
  end
  local m = math.sqrt(ax * ax + ay * ay)
  if m < 0.001 then return 0, 0 end
  return ax / m, ay / m
end

local frames = 0
local died_at = nil
for step = 1, math.floor(16 / DT) do
  t = t + DT
  local px, py = player_pos()

  if not DEBUG.alive() then
    if not died_at then died_at = frames end
    game._down = false
    if frames - died_at > 45 then dump_frame(frames); break end   -- 0.75s of game-over card
  elseif t < 0.9 then
    -- opening dash: wake the world up
    game._down, game._px, game._py = true, 130 * math.cos(t * 7), 240 * math.sin(t * 7)
  elseif t > 11.5 then
    -- finale: dash straight into the nearest bullet for the freeze-frame ending
    local _, nearest = think(px, py)
    if nearest then
      game._down, game._px, game._py = true, nearest.x + nearest.vx * 0.15, nearest.y + nearest.vy * 0.15
    else
      game._down, game._px, game._py = true, -px * 3, -py * 3   -- stir until one spawns
    end
  else
    local threats, _, nd = think(px, py)
    if freeze_left > 0 then
      freeze_left = freeze_left - DT
      game._down, game._px, game._py = true, px, py              -- hold: world freezes
      if nd < 120 then freeze_left = 0 end                       -- too close — move!
    elseif #threats > 0 or dash_left > 0 then
      dash_left = dash_left - DT
      local dxn, dyn = dodge_vector(px, py, threats)
      game._down, game._px, game._py = true, px + dxn * 240, py + dyn * 240
      if #threats == 0 and dash_left <= 0 then freeze_left = 0.55 + lcg() * 0.5 end
    else
      dash_left = 0.35                                           -- reposition burst
    end
    if freeze_left <= 0 and #threats == 0 and dash_left <= 0 then
      freeze_left = 0.6
    end
  end

  frame_fx = {}
  on_update(DT)
  frames = frames + 1
  dump_frame(frames)
end

out:close()
print(string.format("recorded %d frames -> %s (died at frame %s)",
  frames, OUT, tostring(died_at)))
