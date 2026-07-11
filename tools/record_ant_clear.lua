-- record_ant_clear.lua — headless gameplay recorder for the Ant Art pack.
--
-- Mocks the Rust `game` API (like tools/test_pong.lua), builds the ant_clear
-- scene, and plays a scripted run that tells the whole story in one clip:
--   1. good play — clear the outer colour bands, ants eating the heart inward;
--   2. a MISTAKE — commit the scarce slots to buried inner colours;
--   3. STUCK — the non-terminal prompt fires;
--   4. CANCEL (rewarded ad) — free the slots;
--   5. RECOVER — clear the rest -> CLEARED.
-- Every sim frame is dumped as a JSON line for tools/render_ant_clear_gif.py.
--
-- Run: lua5.4 tools/record_ant_clear.lua   (writes build/ant_clear_frames.jsonl)

local HW, HH = 200, 430
local DT = 1 / 60
local OUT = "build/ant_clear_frames.jsonl"

local rng = 20260710
math.random = function(a, b)
  rng = (1103515245 * rng + 12345) % 2147483648
  local r = rng / 2147483648
  if a == nil then return r end
  if b == nil then return math.floor(r * a) + 1 end
  return math.floor(r * (b - a + 1)) + a
end

----------------------------------------------------------------------
-- Mock host API — records entity state instead of drawing
----------------------------------------------------------------------
local ents, max_id = {}, 0
local hud_text, frame_fx = "", {}
local function add(x, y, w, h, r, g, b, a, tex, str)
  max_id = max_id + 1
  ents[max_id] = { x = x, y = y, w = w or 0, h = h or 0, r = r or 1, g = g or 1,
                   b = b or 1, a = a or 1, tex = tex, str = str, rot = 0, frame = 0 }
  return max_id
end
local function noop() end
game = setmetatable({
  bounds = function() return HW, HH end,
  spawn = function(x, y, w, h, r, g, b, a) return add(x, y, w, h, r, g, b, a, "rect") end,
  spawn_sprite = function(x, y, w, h, name) return add(x, y, w, h, 1, 1, 1, 1, name) end,
  spawn_sheet = function(x, y, w, h, name) return add(x, y, w, h, 1, 1, 1, 1, name or "ant_sheet") end,
  -- rigs record as a single ant_hero entity (the offline renderer approximates
  -- the skeletal ant with the hero sprite; scale 110 mirrors spawn_ant's maths)
  spawn_rig = function(x, y, _, scale) return add(x, y, (scale or 1) * 110, (scale or 1) * 110, 1, 1, 1, 1, "ant_hero") end,
  play_anim = function() end,
  set_bone = function() end,
  spawn_text = function(x, y, size, r, g, b, a, str) return add(x, y, 0, size, r, g, b, a, "text", str) end,
  move_to = function(id, x, y) local e = ents[id]; if e then e.x, e.y = x, y end end,
  set_color = function(id, r, g, b, a) local e = ents[id]; if e then e.r, e.g, e.b, e.a = r, g, b, a end end,
  set_size = function(id, w, h) local e = ents[id]; if e then e.w, e.h = w, h end end,
  set_rotation = function(id, a) local e = ents[id]; if e then e.rot = a end end,
  set_frame = function(id, f) local e = ents[id]; if e then e.frame = f end end,
  despawn = function(id) ents[id] = nil end,
  set_text = function(s) hud_text = s or "" end,
  shake = function(v) frame_fx[#frame_fx + 1] = { "shake", v } end,
  emit = function(p, x, y, n) frame_fx[#frame_fx + 1] = { "emit", x or 0, y or 0 } end,
  play_sound = function() end,
  pointer = function() return nil, nil, false end,
  key = function() return false end,
  touches = function() return {} end,
}, { __index = function() return noop end })

SETTINGS = { hud = true }
local function clamp(v, lo, hi) if v < lo then return lo elseif v > hi then return hi else return v end end
GAME_KIT = {
  clamp = clamp, sign = function(v) return (v > 0 and 1) or (v < 0 and -1) or 0 end,
  in_rect = function(r, x, y) return math.abs(x - r.x) <= r.w * 0.5 and math.abs(y - r.y) <= r.h * 0.5 end,
  switch = noop,
  make_back = function(T, hw, hh)
    local r = { x = -hw + 84, y = hh - 152, w = 132, h = 76 }
    T.sprite(r.x, r.y, r.w, r.h, "btn_back"); return r
  end,
  tracker = function()
    local ids = {}
    return {
      spawn = function(...) local id = game.spawn(...); ids[#ids + 1] = id; return id end,
      sprite = function(...) local id = game.spawn_sprite(...); ids[#ids + 1] = id; return id end,
      panel = function(x, y, w, h, name) local id = game.spawn_sprite(x, y, w, h, name); ids[#ids + 1] = id; return id end,
      text = function(...) local id = game.spawn_text(...); ids[#ids + 1] = id; return id end,
      clear = function() for _, id in ipairs(ids) do game.despawn(id) end; ids = {} end,
    }
  end,
}

PACKS = {}
dofile("assets/scripts/packs/ant_clear.lua")
local scene = PACKS.ant_clear.make()
scene.enter(); scene.update(DT, HW, HH)
local D = DEBUG
D.set_mode("manual")
D.toggle_speed()   -- 2x for a watchable-length demo clip (game default is calm)

----------------------------------------------------------------------
-- JSON dump
----------------------------------------------------------------------
local function jstr(s) return '"' .. tostring(s):gsub('[\\"]', '\\%0'):gsub("\n", "\\n") .. '"' end
local out = assert(io.open(OUT, "w"))
local function dump(n, phase)
  local parts = {}
  for id, e in pairs(ents) do
    parts[#parts + 1] = string.format('[%.1f,%.1f,%.1f,%.1f,%.3f,%.3f,%.3f,%.3f,%s,%s,%.4f,%d]',
      e.x, e.y, e.w, e.h, e.r, e.g, e.b, e.a, jstr(e.tex or "rect"), jstr(e.str or ""),
      e.rot or 0, math.floor(e.frame or 0))
  end
  local fx = {}
  for _, f in ipairs(frame_fx) do
    fx[#fx + 1] = string.format('[%.1f,%.1f]', f[2] or 0, f[3] or 0)
  end
  out:write(string.format('{"n":%d,"phase":%s,"hud":%s,"emits":[%s],"ents":[%s]}\n',
    n, jstr(phase), jstr(hud_text), table.concat(fx, ","), table.concat(parts, ",")))
end

----------------------------------------------------------------------
-- Scripted player
----------------------------------------------------------------------
-- Good play in the COLUMN queue: load any column HEAD whose colour is reachable
-- (only the top row is loadable; the column advances up after).
local function safe_play()
  while D.free_slots() > 0 do
    local tc, pick = D.tray_colors(), nil
    for c = 1, 4 do if tc[c] ~= 0 and D.reachable(tc[c]) > 0 then pick = c; break end end
    if not pick then break end
    D.load(pick)
  end
end

local frames = 0
local function step(phase, nframes, act)
  for _ = 1, nframes do
    if act then act() end
    frame_fx = {}
    scene.update(DT, HW, HH)
    frames = frames + 1
    dump(frames, phase)
    if D.won() then return true end
  end
  return false
end

-- play the level to completion, loading column heads (the queue advances as columns empty)
while not D.won() and frames < 12000 do
  if step("play", 1, safe_play) then break end
end
-- hold on the CLEARED card (freeze-frame; the sim has stopped)
for _ = 1, 80 do frame_fx = {}; frames = frames + 1; dump(frames, "done") end

out:close()
print(string.format("recorded %d frames -> %s (final painted=%d won=%s)",
  frames, OUT, D.painted(), tostring(D.won())))
