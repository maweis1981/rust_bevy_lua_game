-- ant_clear.lua — "Ant Art" (蚂蚁艺术) — a strategy pixel-clear puzzle modelled
-- 1:1 on the reference game (Ants Flow, com.ants.box).
--
-- A cute picture is painted out of coloured pixels. You tap a colour tile to
-- commit it to one of your scarce SQUARE slots; matching ants then march out of
-- the nest, weave around the still-painted pixels (never through them — a flow
-- field shared by the swarm, recomputed only when a pixel is removed), pick a
-- frontier pixel of their colour, and carry it back down into the nest hole. The
-- board is eaten from the edges inward until it's clear -> the picture is done.
--
-- STRATEGY / MONETISATION: fewer slots than colours + interior colours that are
-- BURIED behind outer ones (cat eyes/nose inside the face). Commit a slot to a
-- buried colour and it stalls; fill every slot wrong and you're STUCK (no fail
-- state — relaxing genre). The escape valve is to CANCEL a slot (a rewarded
-- video: game.track"rewarded_ad"; wire a real SDK later) and re-pick, or restart.
--
-- Art pipeline: picture  = tools/gen_level.py --pattern cat   (embedded below)
--               ants      = tools/gen_ant_sheet.py -> assets/textures/ant_sheet.png
--               UI tiles  = tools/gen_ant_ui.py    -> tile_sq / hole / cat_face / ad_play
-- CJK strings are registered in tools/subset_font.py.

local function make_ant_clear()
  local K = GAME_KIT
  local T = K.tracker()

  -- ---- levels (generated: tools/gen_level.py, all validated solvable@4) -----
  -- Shared FOOD palette: 1 chocolate, 2 bread, 3 sugar, 4 berry, 5 mint. Every
  -- picture is a food mosaic the colony hauls off crumb by crumb. Progression
  -- is saved (game.save "ant_clear_lvl") and wraps around.
  local LEVELS = {
    { -- fox (14x12, 124 cells) — hi-res recognizable picture
      slots = 4, w = 14, h = 12,
      grid = {
        {2,0,0,0,0,0,0,0,0,0,0,0,0,2},
        {2,2,0,0,0,0,0,0,0,0,0,0,2,2},
        {2,2,2,0,0,0,0,0,0,0,0,2,2,2},
        {2,2,2,2,0,0,0,0,0,0,2,2,2,2},
        {2,2,2,2,2,2,2,2,2,2,2,2,2,2},
        {2,2,2,1,2,2,2,2,2,2,1,2,2,2},
        {2,3,3,2,2,2,2,2,2,2,2,3,3,2},
        {2,4,3,3,2,2,1,1,2,2,3,3,4,2},
        {2,3,3,3,3,3,1,1,3,3,3,3,3,2},
        {2,2,3,3,3,3,4,4,3,3,3,3,2,2},
        {0,2,2,3,3,3,3,3,3,3,3,2,2,0},
        {0,0,0,2,2,2,2,2,2,2,2,0,0,0},
      },
      tray = { {2,4}, {2,4}, {2,4}, {2,4}, {2,4}, {2,4}, {2,4}, {2,4}, {2,4}, {2,4}, {2,4}, {2,4}, {2,4}, {2,4}, {2,4}, {2,4}, {2,4}, {3,4}, {2,4}, {3,4}, {3,4}, {3,4}, {3,4}, {2,4}, {3,4}, {3,4}, {1,4}, {3,4}, {2,4}, {4,4}, {1,2}, {3,2} },
    },
    { -- heart (13x10, 99 cells) — hi-res recognizable picture
      slots = 4, w = 13, h = 10,
      grid = {
        {0,4,3,3,3,3,0,4,4,4,4,4,0},
        {0,3,3,3,3,3,4,4,4,4,4,4,0},
        {4,3,3,3,3,3,4,4,4,4,4,4,4},
        {4,4,3,3,3,3,4,4,4,4,4,4,4},
        {0,4,4,4,4,4,4,4,4,4,4,4,0},
        {0,4,4,4,4,4,4,4,4,4,4,4,0},
        {0,4,4,4,4,4,4,4,4,4,4,4,0},
        {0,0,4,4,4,4,4,4,4,4,4,0,0},
        {0,0,0,1,1,1,1,1,1,1,0,0,0},
        {0,0,0,0,0,1,1,1,0,0,0,0,0},
      },
      tray = { {4,4}, {4,4}, {4,4}, {4,4}, {4,4}, {4,4}, {4,4}, {4,4}, {4,4}, {4,4}, {4,4}, {4,4}, {4,4}, {3,4}, {4,4}, {3,4}, {4,4}, {4,4}, {3,4}, {1,4}, {4,4}, {1,4}, {3,4}, {4,3}, {1,2}, {3,2} },
    },
    { -- smiley (11x11, 109 cells) — hi-res recognizable picture
      slots = 4, w = 11, h = 11,
      grid = {
        {0,0,2,2,2,2,2,2,2,0,0},
        {0,2,2,2,2,2,2,2,2,2,0},
        {2,2,2,2,2,2,2,2,2,2,2},
        {2,2,1,1,2,2,2,1,1,2,2},
        {2,2,1,1,2,2,2,1,1,2,2},
        {2,2,2,2,2,2,2,2,2,2,2},
        {2,4,2,2,2,2,2,2,2,4,2},
        {2,2,1,2,2,2,2,2,1,2,2},
        {2,2,1,1,2,2,2,1,1,2,2},
        {0,2,2,1,1,1,1,1,2,2,0},
        {0,0,2,2,2,2,2,2,2,0,0},
      },
      tray = { {2,4}, {2,4}, {2,4}, {2,4}, {2,4}, {2,4}, {2,4}, {2,4}, {2,4}, {2,4}, {2,4}, {2,4}, {2,4}, {2,4}, {2,4}, {2,4}, {2,4}, {2,4}, {2,4}, {1,4}, {1,4}, {2,4}, {1,4}, {2,4}, {1,4}, {2,4}, {1,3}, {4,2} },
    },
    { -- donut (13x12, 96 cells) — hi-res recognizable picture
      slots = 4, w = 13, h = 12,
      grid = {
        {0,0,0,0,0,0,4,0,0,0,0,0,0},
        {0,0,0,3,4,4,4,4,4,4,0,0,0},
        {0,0,4,4,4,4,4,4,4,4,4,0,0},
        {0,4,4,4,4,4,4,4,5,4,4,4,0},
        {0,4,4,4,3,4,0,4,4,4,4,4,0},
        {4,5,2,2,4,0,0,0,4,4,4,4,2},
        {2,4,2,2,2,0,0,0,4,2,2,4,2},
        {0,2,2,2,2,2,0,2,2,2,2,2,0},
        {0,2,2,2,2,2,2,2,2,2,2,2,0},
        {0,0,1,1,1,1,1,1,1,1,1,0,0},
        {0,0,0,1,1,1,1,1,1,1,0,0,0},
        {0,0,0,0,0,0,1,0,0,0,0,0,0},
      },
      tray = { {4,4}, {4,4}, {4,4}, {4,4}, {4,4}, {4,4}, {4,4}, {2,4}, {4,4}, {2,4}, {2,4}, {4,4}, {1,4}, {2,4}, {2,4}, {2,4}, {1,4}, {1,4}, {4,4}, {2,4}, {1,4}, {4,4}, {2,3}, {3,2}, {5,2}, {1,1} },
    },
    { -- cat (19x17, 246 cells) — hi-res recognizable picture
      slots = 4, w = 19, h = 17,
      grid = {
        {0,0,0,0,1,1,0,0,0,0,0,0,0,0,1,1,0,0,0},
        {0,0,0,1,4,4,1,0,0,0,0,0,0,1,4,4,1,0,0},
        {0,0,0,1,4,2,1,0,0,0,0,0,0,1,2,4,1,0,0},
        {0,0,1,1,2,2,1,1,0,0,0,0,1,1,2,2,1,1,0},
        {0,0,1,2,2,2,2,2,1,1,1,1,2,2,2,2,2,1,0},
        {0,1,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,1,0},
        {0,1,2,2,3,3,3,3,3,3,3,3,3,3,3,2,2,1,0},
        {0,1,2,3,3,3,3,3,3,3,3,3,3,3,3,3,2,1,0},
        {1,2,3,3,5,5,3,3,3,3,3,3,5,5,3,3,3,2,1},
        {1,2,3,3,5,5,3,3,3,3,3,3,5,5,3,3,3,2,1},
        {1,2,3,3,3,3,3,3,3,4,4,3,3,3,3,3,3,2,1},
        {1,2,3,3,3,3,3,3,4,4,4,4,3,3,3,3,3,2,1},
        {1,2,2,3,3,3,3,3,3,3,3,3,3,3,3,3,2,2,1},
        {0,1,2,2,3,3,3,3,3,3,3,3,3,3,2,2,1,0,0},
        {0,1,1,2,2,2,3,3,3,3,3,2,2,2,1,1,0,0,0},
        {0,0,0,1,1,2,2,2,2,2,2,2,1,1,1,1,0,0,0},
        {0,0,0,0,0,1,1,1,1,1,1,1,1,0,0,0,0,0,0},
      },
      tray = { {1,4}, {1,4}, {1,4}, {1,4}, {1,4}, {1,4}, {1,4}, {1,4}, {1,4}, {2,4}, {2,4}, {2,4}, {2,4}, {1,4}, {2,4}, {2,4}, {2,4}, {1,4}, {2,4}, {2,4}, {1,4}, {2,4}, {3,4}, {3,4}, {3,4}, {3,4}, {3,4}, {3,4}, {1,4}, {2,4}, {3,4}, {3,4}, {3,4}, {2,4}, {3,4}, {3,4}, {3,4}, {3,4}, {3,4}, {3,4}, {3,4}, {3,4}, {3,4}, {2,4}, {1,4}, {4,4}, {3,4}, {3,4}, {3,4}, {3,4}, {2,4}, {3,4}, {4,4}, {5,4}, {1,4}, {2,4}, {2,4}, {3,4}, {4,4}, {5,4}, {1,2}, {2,2}, {3,2} },
    },
    { -- flower (11x12, 51 cells) — trays generated peel-order by tools/levelgen
      slots = 4, w = 11, h = 12,
      grid = {
        {0,0,0,0,4,0,4,0,0,0,0},
        {0,0,0,4,4,4,4,4,0,0,0},
        {0,0,4,4,2,2,2,4,4,0,0},
        {0,4,4,2,2,2,2,2,4,4,0},
        {0,0,4,4,2,2,2,4,4,0,0},
        {0,0,0,4,4,4,4,4,0,0,0},
        {0,0,0,0,4,5,4,0,0,0,0},
        {0,0,0,0,0,5,0,0,0,0,0},
        {0,0,0,5,0,5,0,5,0,0,0},
        {0,0,5,5,0,5,0,5,5,0,0},
        {0,0,0,0,0,5,0,0,0,0,0},
        {0,0,0,0,5,5,5,0,0,0,0},
      },
      tray = { {4,4}, {4,4}, {4,4}, {4,3}, {5,4}, {5,4}, {5,4}, {5,1}, {2,1}, {4,4}, {4,4}, {4,2}, {5,1}, {2,4}, {2,3}, {4,1}, {2,3} },
    },
    { -- mushroom (11x10, 72 cells)
      slots = 4, w = 11, h = 10,
      grid = {
        {0,0,0,1,1,1,1,1,0,0,0},
        {0,0,1,2,2,2,2,2,1,0,0},
        {0,1,2,3,2,2,2,3,2,1,0},
        {1,2,2,2,2,3,2,2,2,2,1},
        {1,2,3,2,2,2,2,2,3,2,1},
        {0,1,2,2,2,2,2,2,2,1,0},
        {0,0,1,1,1,1,1,1,1,0,0},
        {0,0,0,3,3,3,3,3,0,0,0},
        {0,0,0,3,0,3,0,3,0,0,0},
        {0,0,0,3,3,3,3,3,0,0,0},
      },
      tray = { {1,4}, {1,4}, {1,4}, {1,4}, {1,1}, {3,4}, {3,4}, {3,1}, {1,2}, {2,4}, {2,4}, {2,4}, {2,1}, {3,3}, {1,2}, {2,4}, {2,3}, {3,4}, {3,1}, {1,1}, {2,4}, {2,4}, {3,1}, {2,4} },
    },
    { -- ghost (11x10, 81 cells)
      slots = 4, w = 11, h = 10,
      grid = {
        {0,0,0,3,3,3,3,3,0,0,0},
        {0,0,3,3,3,3,3,3,3,0,0},
        {0,3,3,3,3,3,3,3,3,3,0},
        {0,3,3,1,1,3,1,1,3,3,0},
        {0,3,3,1,1,3,1,1,3,3,0},
        {0,3,3,3,3,3,3,3,3,3,0},
        {0,3,3,3,4,3,4,3,3,3,0},
        {0,3,3,3,3,3,3,3,3,3,0},
        {0,3,3,3,3,3,3,3,3,3,0},
        {0,3,0,3,3,0,3,3,0,3,0},
      },
      tray = { {3,4}, {3,4}, {3,4}, {3,4}, {3,4}, {3,4}, {3,4}, {3,2}, {3,4}, {3,4}, {3,4}, {3,4}, {3,4}, {3,2}, {1,4}, {3,4}, {3,4}, {3,4}, {3,2}, {1,4}, {3,4}, {4,2}, {3,1} },
    },
    { -- fish (13x7, 63 cells)
      slots = 4, w = 13, h = 7,
      grid = {
        {0,0,0,0,2,2,2,2,2,0,0,0,0},
        {0,0,2,2,2,2,2,2,2,2,2,0,0},
        {0,2,2,3,3,3,3,3,2,2,2,5,0},
        {2,2,1,3,3,3,3,3,2,2,5,5,5},
        {0,2,2,3,3,3,3,3,2,2,2,5,0},
        {0,0,2,2,2,2,2,2,2,2,2,0,0},
        {0,0,0,0,2,2,2,2,2,0,0,0,0},
      },
      tray = { {2,4}, {2,4}, {2,4}, {2,4}, {2,4}, {2,1}, {5,3}, {2,4}, {2,4}, {2,4}, {2,4}, {2,1}, {3,2}, {5,1}, {1,1}, {2,3}, {3,4}, {3,4}, {3,1}, {5,1}, {2,1}, {3,4} },
    },
    { -- star (11x10, 59 cells)
      slots = 4, w = 11, h = 10,
      grid = {
        {0,0,0,0,0,2,0,0,0,0,0},
        {0,0,0,0,2,2,2,0,0,0,0},
        {0,0,0,0,2,2,2,0,0,0,0},
        {2,2,2,2,2,2,2,2,2,2,2},
        {0,2,2,2,2,2,2,2,2,2,0},
        {0,0,2,2,2,2,2,2,2,0,0},
        {0,0,2,2,2,2,2,2,2,0,0},
        {0,2,2,2,2,0,2,2,2,2,0},
        {0,2,2,2,0,0,0,2,2,2,0},
        {0,2,2,0,0,0,0,0,2,2,0},
      },
      tray = { {2,4}, {2,4}, {2,4}, {2,4}, {2,4}, {2,4}, {2,4}, {2,4}, {2,4}, {2,4}, {2,4}, {2,4}, {2,4}, {2,1}, {2,4}, {2,2} },
    },
    { -- rocket (45x60, 1164 cells) — big showcase level
      slots = 4, w = 45, h = 60,
      grid = {
        {0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0},
        {0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0},
        {0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0},
        {0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,4,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0},
        {0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,4,4,4,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0},
        {0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,4,4,4,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0},
        {0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,4,4,4,4,4,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0},
        {0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,4,4,4,4,4,4,4,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0},
        {0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,4,4,4,4,4,4,4,4,4,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0},
        {0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,4,4,4,4,4,4,4,4,4,4,4,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0},
        {0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,4,4,4,4,4,4,4,4,4,4,4,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0},
        {0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,4,4,4,4,4,4,4,4,4,4,4,4,4,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0},
        {0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0},
        {0,0,0,0,0,0,0,0,0,0,0,0,0,1,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,1,0,0,0,0,0,0,0,0,0,0,0,0,0},
        {0,0,0,0,0,0,0,0,0,0,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,0,0,0,0,0,0,0,0,0,0},
        {0,0,0,0,0,0,0,0,0,1,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,1,0,0,0,0,0,0,0,0,0},
        {0,0,0,0,0,0,0,0,0,1,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,1,0,0,0,0,0,0,0,0,0},
        {0,0,0,0,0,0,0,0,0,1,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,1,0,0,0,0,0,0,0,0,0},
        {0,0,0,0,0,0,0,0,0,0,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,0,0,0,0,0,0,0,0,0,0},
        {0,0,0,0,0,0,0,0,0,0,0,1,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,1,0,0,0,0,0,0,0,0,0,0,0},
        {0,0,0,0,0,0,0,0,0,0,1,3,3,3,3,3,3,3,3,3,1,1,1,1,1,3,3,3,3,3,3,3,3,3,1,0,0,0,0,0,0,0,0,0,0},
        {0,0,0,0,0,0,0,0,0,0,1,3,3,3,3,3,3,3,1,1,5,5,5,5,5,1,1,3,3,3,3,3,3,3,1,0,0,0,0,0,0,0,0,0,0},
        {0,0,0,0,0,0,0,0,0,1,3,3,3,3,3,3,3,1,5,5,5,5,5,5,5,5,5,1,3,3,3,3,3,3,3,1,0,0,0,0,0,0,0,0,0},
        {0,0,0,0,0,0,0,0,0,1,3,3,3,3,3,3,1,5,5,5,5,1,1,1,5,5,5,5,1,3,3,3,3,3,3,1,0,0,0,0,0,0,0,0,0},
        {0,0,0,0,0,0,0,0,0,1,3,3,3,3,3,3,1,5,5,1,1,3,3,3,1,1,5,5,1,3,3,3,3,3,3,1,0,0,0,0,0,0,0,0,0},
        {0,0,0,0,0,0,0,0,0,1,3,3,3,3,3,1,5,5,5,1,3,3,3,3,3,1,5,5,5,1,3,3,3,3,3,1,0,0,0,0,0,0,0,0,0},
        {0,0,0,0,0,0,0,0,0,1,3,3,3,3,3,1,5,5,1,3,3,3,3,3,3,3,1,5,5,1,3,3,3,3,3,1,0,0,0,0,0,0,0,0,0},
        {0,0,0,0,0,0,0,0,0,1,3,3,3,3,3,1,5,5,1,3,3,3,3,3,3,3,1,5,5,1,3,3,3,3,3,1,0,0,0,0,0,0,0,0,0},
        {0,0,0,0,0,0,0,0,0,1,3,3,3,3,3,1,5,5,1,3,3,3,3,3,3,3,1,5,5,1,3,3,3,3,3,1,0,0,0,0,0,0,0,0,0},
        {0,0,0,0,0,0,0,0,0,1,3,3,3,3,3,1,5,5,5,1,3,3,3,3,3,1,5,5,5,1,3,3,3,3,3,1,0,0,0,0,0,0,0,0,0},
        {0,0,0,0,0,0,0,0,0,1,3,3,3,3,3,3,1,5,5,1,1,3,3,3,1,1,5,5,1,3,3,3,3,3,3,1,0,0,0,0,0,0,0,0,0},
        {0,0,0,0,0,0,0,0,0,1,3,3,3,3,3,3,1,5,5,5,5,1,1,1,5,5,5,5,1,3,3,3,3,3,3,1,0,0,0,0,0,0,0,0,0},
        {0,0,0,0,0,0,0,0,0,1,3,3,3,3,3,3,3,1,5,5,5,5,5,5,5,5,5,1,3,3,3,3,3,3,3,1,0,0,0,0,0,0,0,0,0},
        {0,0,0,0,0,0,0,0,0,1,3,3,3,3,3,3,3,3,1,1,5,5,5,5,5,1,1,3,3,3,3,3,3,3,3,1,0,0,0,0,0,0,0,0,0},
        {0,0,0,0,0,0,0,0,0,1,3,3,3,3,3,3,3,3,3,3,1,1,1,1,1,3,3,3,3,3,3,3,3,3,3,1,0,0,0,0,0,0,0,0,0},
        {0,0,0,0,0,0,0,0,0,1,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,1,0,0,0,0,0,0,0,0,0},
        {0,0,0,0,0,0,0,0,0,1,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,1,0,0,0,0,0,0,0,0,0},
        {0,0,0,0,0,0,0,0,0,1,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,1,0,0,0,0,0,0,0,0,0},
        {0,0,0,0,0,0,0,0,0,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,0,0,0,0,0,0,0,0,0},
        {0,0,0,0,0,0,0,0,0,1,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,1,0,0,0,0,0,0,0,0,0},
        {0,0,0,0,0,0,0,0,0,1,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,1,0,0,0,0,0,0,0,0,0},
        {0,0,0,0,0,0,0,0,1,1,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,1,1,0,0,0,0,0,0,0,0},
        {0,0,0,0,0,0,0,0,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,0,0,0,0,0,0,0,0},
        {0,0,0,0,0,0,0,1,2,1,0,0,1,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,1,0,0,1,2,1,0,0,0,0,0,0,0},
        {0,0,0,0,0,0,0,1,2,1,0,0,1,1,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,1,1,0,0,1,2,1,0,0,0,0,0,0,0},
        {0,0,0,0,0,0,1,2,2,1,0,0,0,0,1,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,1,0,0,0,0,1,2,2,1,0,0,0,0,0,0},
        {0,0,0,0,0,1,2,2,2,1,0,0,0,0,0,1,1,3,3,3,3,3,3,3,3,3,3,3,1,1,0,0,0,0,0,1,2,2,2,1,0,0,0,0,0},
        {0,0,0,0,0,1,2,2,2,1,0,0,0,0,0,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,0,0,0,0,0,1,2,2,2,1,0,0,0,0,0},
        {0,0,0,0,1,2,2,2,2,1,0,0,0,0,0,0,1,1,1,1,1,1,1,1,1,1,1,1,1,0,0,0,0,0,0,1,2,2,2,2,1,0,0,0,0},
        {0,0,0,0,1,2,2,1,1,0,0,0,0,0,0,0,1,1,1,1,1,1,1,1,1,1,1,1,1,0,0,0,0,0,0,0,1,1,2,2,1,0,0,0,0},
        {0,0,0,1,2,1,1,0,0,0,0,0,0,0,0,0,0,1,1,1,1,1,1,1,1,1,1,1,0,0,0,0,0,0,0,0,0,0,1,1,2,1,0,0,0},
        {0,0,0,1,1,0,0,0,0,0,0,0,0,0,0,0,0,1,1,1,1,1,1,1,1,1,1,1,0,0,0,0,0,0,0,0,0,0,0,0,1,1,0,0,0},
        {0,0,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,2,2,4,4,4,4,4,4,4,2,2,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,0,0},
        {0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,2,2,2,4,4,4,4,4,2,2,2,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0},
        {0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,2,2,4,4,4,4,4,2,2,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0},
        {0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,2,2,2,4,4,4,2,2,2,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0},
        {0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,2,2,4,4,4,2,2,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0},
        {0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,2,2,2,4,2,2,2,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0},
        {0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,2,0,0,0,2,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0},
        {0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,2,0,0,0,2,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0},
      },
      tray = { {1,4}, {1,4}, {1,4}, {1,4}, {1,4}, {1,4}, {1,4}, {1,4}, {1,4}, {1,4}, {1,4}, {1,4}, {1,4}, {1,4}, {1,4}, {1,4}, {1,4}, {1,4}, {1,4}, {1,4}, {1,4}, {1,4}, {1,4}, {1,4}, {1,4}, {1,4}, {1,4}, {1,4}, {1,4}, {1,4}, {1,4}, {1,4}, {1,4}, {1,4}, {1,4}, {1,4}, {1,4}, {1,3}, {2,4}, {2,4}, {2,4}, {2,4}, {2,2}, {4,1}, {1,4}, {1,4}, {1,4}, {1,4}, {1,4}, {1,4}, {2,4}, {2,4}, {2,4}, {2,4}, {2,4}, {2,4}, {2,4}, {2,4}, {2,4}, {2,4}, {2,4}, {2,4}, {3,4}, {3,4}, {3,4}, {3,4}, {3,4}, {3,4}, {3,4}, {3,4}, {3,4}, {3,4}, {3,4}, {4,4}, {4,4}, {4,4}, {4,4}, {4,4}, {4,4}, {4,4}, {4,4}, {4,2}, {1,4}, {1,4}, {1,4}, {1,4}, {1,2}, {2,4}, {2,4}, {2,4}, {2,4}, {3,4}, {3,4}, {3,4}, {3,4}, {3,4}, {3,4}, {3,4}, {3,4}, {3,4}, {3,4}, {3,4}, {3,2}, {4,4}, {4,4}, {4,4}, {4,4}, {4,4}, {4,4}, {4,4}, {4,4}, {4,1}, {1,4}, {1,4}, {1,4}, {1,4}, {1,2}, {2,4}, {2,2}, {3,4}, {3,4}, {3,4}, {3,4}, {3,4}, {3,4}, {3,4}, {3,4}, {3,4}, {3,4}, {3,4}, {3,2}, {4,4}, {4,4}, {4,4}, {4,4}, {4,4}, {4,4}, {4,4}, {1,4}, {1,4}, {1,4}, {1,4}, {1,2}, {2,4}, {2,2}, {3,4}, {3,4}, {3,4}, {3,4}, {3,4}, {3,4}, {3,4}, {3,4}, {3,4}, {3,4}, {3,4}, {3,2}, {4,4}, {4,4}, {4,4}, {4,4}, {4,4}, {4,4}, {1,4}, {1,4}, {1,4}, {1,4}, {2,4}, {2,2}, {3,4}, {3,4}, {3,4}, {3,4}, {3,4}, {3,4}, {3,4}, {3,4}, {3,4}, {3,4}, {3,4}, {3,2}, {4,4}, {4,4}, {4,4}, {4,4}, {4,2}, {1,4}, {1,4}, {1,4}, {1,4}, {1,4}, {1,2}, {2,4}, {2,2}, {3,4}, {3,4}, {3,4}, {3,4}, {3,4}, {3,4}, {3,4}, {3,4}, {3,4}, {4,4}, {4,4}, {4,4}, {4,2}, {1,4}, {1,4}, {1,4}, {1,4}, {1,1}, {2,4}, {2,2}, {3,4}, {3,4}, {3,4}, {3,4}, {3,4}, {3,4}, {3,3}, {4,4}, {4,4}, {4,3}, {5,4}, {5,4}, {5,2}, {1,4}, {1,4}, {1,4}, {1,2}, {2,4}, {2,2}, {3,4}, {3,4}, {3,4}, {3,4}, {3,3}, {4,4}, {4,4}, {4,1}, {5,4}, {5,4}, {5,4}, {5,4}, {5,2}, {1,4}, {1,4}, {1,4}, {1,4}, {1,2}, {2,4}, {2,2}, {3,4}, {3,4}, {3,4}, {3,3}, {4,4}, {4,3}, {5,4}, {5,4}, {5,4}, {5,4}, {1,4}, {1,4}, {1,4}, {1,4}, {1,3}, {2,4}, {2,2}, {3,4}, {3,4}, {3,4}, {3,4}, {3,1}, {4,4}, {4,2}, {5,4}, {5,4}, {5,2}, {1,4}, {1,4}, {1,4}, {1,1}, {2,4}, {2,2}, {3,4}, {3,4}, {3,4}, {3,4}, {3,1}, {4,4}, {4,1}, {5,4}, {5,4}, {5,4}, {1,4}, {1,4}, {1,2}, {2,4}, {2,1}, {3,4}, {3,4}, {3,4}, {3,4}, {3,4}, {4,3}, {5,4}, {5,3}, {1,4}, {2,2}, {3,4}, {3,4}, {3,2}, {4,1}, {5,3} },
    },
    { -- tiger (26x24, 410 cells) — colourful (all 5 colours)
      slots = 4, w = 26, h = 24,
      grid = {
        {0,0,1,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,1,0,0},
        {0,0,1,2,1,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,1,2,1,0,0},
        {0,0,1,2,2,2,1,1,0,0,0,0,0,0,0,0,0,0,1,1,2,2,2,1,0,0},
        {0,0,1,2,4,2,2,2,1,1,0,0,0,0,0,0,1,1,2,2,2,4,2,1,0,0},
        {0,0,1,2,4,4,4,4,1,1,1,1,1,1,1,1,1,1,4,4,4,4,2,1,0,0},
        {0,0,0,1,2,4,4,1,1,2,2,2,2,1,2,2,2,1,1,4,4,2,1,0,0,0},
        {0,0,0,1,2,1,1,2,2,2,1,2,2,1,2,2,1,2,2,1,1,2,1,0,0,0},
        {0,0,0,1,1,2,2,1,2,2,1,2,2,1,2,2,1,2,2,1,2,1,1,0,0,0},
        {0,0,0,1,1,2,2,1,2,2,2,1,2,1,2,1,2,2,2,1,2,1,1,0,0,0},
        {0,0,0,1,2,2,3,1,3,2,2,1,2,1,2,1,2,3,3,1,2,2,1,0,0,0},
        {0,0,0,1,2,1,1,1,1,3,2,2,2,2,2,2,3,1,1,1,1,2,1,0,0,0},
        {0,0,1,2,1,5,5,5,5,1,3,2,2,2,2,3,1,5,5,5,5,1,2,1,0,0},
        {0,0,1,2,1,5,1,1,5,1,3,2,2,2,2,3,1,5,1,1,5,1,2,1,0,0},
        {0,0,1,2,1,5,1,1,5,1,2,1,1,1,1,1,1,5,1,1,5,1,2,1,0,0},
        {0,0,1,2,2,1,1,1,1,2,2,2,1,4,1,2,2,1,1,1,1,2,2,1,0,0},
        {0,0,1,2,1,1,2,2,3,3,3,3,1,4,1,3,3,3,2,2,1,1,2,1,0,0},
        {0,0,1,1,2,2,2,3,3,3,3,3,3,1,3,3,3,3,3,2,2,2,1,1,0,0},
        {0,0,0,1,2,2,3,3,3,3,3,3,3,1,3,3,3,3,3,3,2,2,1,0,0,0},
        {0,0,0,0,1,1,3,3,3,3,3,3,3,1,3,3,3,3,3,3,1,1,0,0,0,0},
        {0,0,1,1,1,2,3,3,3,3,3,1,1,3,1,1,3,3,3,3,2,1,1,1,0,0},
        {0,0,0,0,0,1,1,3,3,3,1,3,3,3,3,3,1,3,3,1,1,0,0,0,0,0},
        {0,0,0,0,0,0,0,1,3,3,3,3,3,3,3,3,3,3,1,0,0,0,0,0,0,0},
        {0,0,0,0,0,0,0,0,0,1,1,1,1,1,1,1,1,0,0,0,0,0,0,0,0,0},
        {0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0},
      },
      tray = { {1,4}, {1,4}, {1,4}, {1,4}, {1,4}, {1,4}, {1,4}, {1,4}, {1,4}, {1,4}, {1,4}, {1,4}, {1,4}, {1,4}, {1,4}, {1,4}, {1,4}, {1,4}, {1,4}, {1,2}, {3,2}, {1,4}, {1,4}, {1,4}, {1,1}, {2,4}, {2,4}, {2,4}, {2,4}, {2,4}, {2,4}, {2,4}, {2,4}, {2,4}, {2,4}, {2,3}, {3,4}, {3,4}, {3,4}, {3,2}, {1,4}, {1,4}, {1,4}, {1,4}, {1,2}, {2,4}, {2,4}, {2,4}, {2,4}, {2,4}, {3,4}, {3,4}, {3,4}, {4,4}, {4,4}, {4,2}, {1,4}, {1,4}, {1,4}, {1,4}, {1,4}, {2,4}, {2,4}, {2,3}, {3,4}, {3,4}, {3,3}, {4,4}, {5,4}, {5,2}, {1,4}, {1,4}, {1,4}, {1,4}, {2,4}, {2,4}, {2,4}, {2,2}, {3,4}, {3,4}, {3,4}, {5,2}, {1,4}, {1,4}, {1,4}, {2,4}, {2,4}, {2,1}, {3,4}, {3,4}, {3,4}, {3,1}, {5,2}, {1,3}, {2,4}, {2,4}, {3,4}, {3,4}, {3,3}, {5,4}, {5,2}, {1,4}, {1,4}, {2,4}, {2,2}, {3,4}, {3,3}, {4,1}, {1,3}, {2,4}, {2,4}, {3,2}, {4,1}, {1,4} },
    },
  }
  local cur_lvl = 1
  local LEVEL = LEVELS[1]
  -- PURE-COLOUR palette for the pixel mosaic: clean, distinct, moderately vivid
  -- (concept-matched). Hue roles are kept so the pictures read: 1 dark cocoa
  -- (eyes/outline), 2 orange (fur/face), 3 warm cream (muzzle/light), 4 rose
  -- (nose/accents), 5 mint-teal (eyes/accents). Blocks are this colour, flat.
  -- NOTE colour 1 is a deep espresso, not a mid-cocoa: the old {0.40,0.245,0.15}
  -- was nearly the soil board's own shadow tone, so dark blocks camouflaged into
  -- the dirt and looked "unloaded". A near-black espresso reads as an intentional
  -- dark accent (eyes/outline) with strong contrast against the brown board.
  local PALETTE5 = { {0.220,0.130,0.110}, {1.000,0.600,0.135}, {1.000,0.930,0.780}, {0.975,0.410,0.505}, {0.300,0.800,0.640} }

  -- ---- tunables ------------------------------------------------------------
  local SLOTS = LEVEL.slots or 4   -- active slots (< palette size on purpose)
  local ANTS_PER_SLOT = 4
  local ANT_SPEED = 48       -- world units / sec (a leisurely, casual crawl —
                             -- premium casual games amble, they don't scurry)
  local ANT_SIZE = 1.05      -- ant BODY LENGTH in cells (small vs the blocks,
                             -- like the reference — was reading 3+ cells)
  local MAX_DT = 1 / 30
  local mode = "manual"      -- "manual" (tap to load) | "auto" (autoplay/tests)

  local W, H = LEVEL.w, LEVEL.h
  local grid, painted, cell_id = {}, 0, {}

  -- geometry (filled in build)
  local CELL, OX, TOPY, NESTX, NESTY = 0, 0, 0, 0, 0
  local SLOT_Y, TRAY_Y, SLOT_W, TRAY_W = 0, 0, 0, 0
  -- FLAT grid (pixel-art): all cells the SAME size, no perspective. PS[r] = row
  -- scale (all 1), ROWY[r] = centre-line. The `rs`/PS machinery is kept so cx/cy
  -- and the ant paths still route through one place — PERSP = 0 makes it uniform.
  local PS, ROWY = {}, {}
  local PERSP = 0.0            -- 0 = flat uniform grid (was a fake-3D taper)
  local function rs(r) return PS[r] or 1 end
  local function cx(c, r) return (OX + (c - 0.5) * CELL) * rs(r or H) end
  local function cy(r) return ROWY[r] or (TOPY - (r - 0.5) * CELL) end

  -- ---- flow field over an open ring (rows/cols 0..H+1, 0..W+1) -------------
  -- NW/NEST are level-sized; re-derived in build() when the level changes.
  local NW = W + 2
  local function node(r, c) return r * NW + c end
  local NEST = node(H + 1, math.floor(W / 2) + 1)
  local dist, par, dirty = {}, {}, true
  local function passable(r, c)
    if r < 1 or r > H or c < 1 or c > W then return true end
    return grid[r][c] == 0
  end
  local function recompute_field()
    dist, par = {}, {}
    local q, head = { NEST }, 1
    dist[NEST] = 0; par[NEST] = -1
    while head <= #q do
      local n = q[head]; head = head + 1
      local r, c = math.floor(n / NW), n % NW
      for _, p in ipairs({ {r+1,c},{r-1,c},{r,c+1},{r,c-1} }) do
        local rr, cc = p[1], p[2]
        if rr >= 0 and rr <= H + 1 and cc >= 0 and cc <= W + 1 and passable(rr, cc) then
          local m = node(rr, cc)
          if dist[m] == nil then dist[m] = dist[n] + 1; par[m] = n; q[#q + 1] = m end
        end
      end
    end
    dirty = false
  end
  local function path_to(tr, tc)
    if dirty then recompute_field() end
    local best, bestd
    for _, p in ipairs({ {tr+1,tc},{tr-1,tc},{tr,tc+1},{tr,tc-1} }) do
      local rr, cc = p[1], p[2]
      if rr >= 0 and rr <= H + 1 and cc >= 0 and cc <= W + 1 and passable(rr, cc) then
        local d = dist[node(rr, cc)]
        if d ~= nil and (bestd == nil or d < bestd) then bestd = d; best = node(rr, cc) end
      end
    end
    if best == nil then return nil end
    local chain, cur = {}, best
    while cur ~= -1 do chain[#chain + 1] = cur; cur = par[cur] end
    local pts = {}
    for i = #chain, 1, -1 do
      -- The flow-field nest node lives at grid row H+1 (the board's bottom edge),
      -- but the VISIBLE hole sits lower (its own layout position). Map the nest
      -- node to the visible hole so ants actually enter/leave the hole and never
      -- idle stranded on the board bottom.
      if chain[i] == NEST then
        pts[#pts + 1] = { NESTX, NESTY }
      else
        local r, c = math.floor(chain[i] / NW), chain[i] % NW
        pts[#pts + 1] = { cx(c, r), cy(r) }
      end
    end
    pts[#pts + 1] = { cx(tc, tr), cy(tr) }
    return pts
  end

  -- ---- slots / tray / ants -------------------------------------------------
  local tray, slots, reserved, ants = {}, {}, {}, {}
  local NCOL, QROWS = 4, 3              -- queue = 4 fixed columns, 3 rows visible
                                        -- (denser tray, like the approved mockup)
  local cols = { {}, {}, {}, {} }       -- each column is a stack; only the head loads
  local col_adv = {}                    -- per-column slide-up animation timer
  local slot_pulse = {}   -- brief scale bump when a slot's count ticks down
  local playing, won, stuck, speed2 = true, false, false, false
  local screen = "play"                 -- "play" | "select" (level-picker page)
  local max_lvl = 1                     -- highest UNLOCKED level (saved progress)
  local sel_cards, sel_back = {}, nil   -- level-select hit-rects + its back button
  -- TIME RACE: the top bar drains over the level's deadline; you keep more stars
  -- the faster you clear the picture (shorter time -> higher grade & score).
  local elapsed, star_grade = 0, 3      -- level timer + live time grade (3..1)
  local par3, par2, par1 = 0, 0, 0      -- 3-star / 2-star / deadline thresholds (s)
  local best_stars = {}                 -- best grade earned per level (select page)
  -- BOSS RACE: later levels (>= BOSS_FROM) pit you against a boss beetle that eats
  -- the time bar. If it empties before you clear the picture, the boss wins -> lose.
  local BOSS_FROM = 6
  local lost, boss_on, boss_id = false, false, nil
  local dispatch_cd = 0        -- ants leave the nest ONE AT A TIME (single file)
  local DISPATCH_GAP = 0.45    -- seconds between departures
  local muted = false          -- sound toggle (music + sfx)
  local win_t = 0              -- celebration timer -> auto-advance to next level
  local intro = { ids = {} }   -- level-intro title card ("LEVEL N") state
  local HW, HH, built = 0, 0, false
  local back, was_stuck = nil, false
  local palette = PALETTE5

  local function reachable_count(color)
    if dirty then recompute_field() end
    local n = 0
    for r = 1, H do for c = 1, W do
      if grid[r][c] == color and not reserved[(r-1)*W+c] then
        for _, p in ipairs({ {r+1,c},{r-1,c},{r,c+1},{r,c-1} }) do
          if passable(p[1], p[2]) and dist[node(p[1], p[2])] ~= nil then n = n + 1; break end
        end
      end
    end end
    return n
  end
  local function free_slot() for i = 1, SLOTS do if slots[i] == nil then return i end end end
  local function queue_total() local n = 0 for c = 1, NCOL do n = n + #cols[c] end return n end
  local function col_head(c) return cols[c][1] end
  -- Load a COLUMN HEAD into a free slot (the only legal move: top row only). The
  -- column then advances up (col_adv drives the slide animation).
  local function load_head(c)
    local i = free_slot(); local b = cols[c] and cols[c][1]
    if not i or not b then return false end
    slots[i] = b; table.remove(cols[c], 1); col_adv[c] = 1; return true
  end
  -- Auto play (autoplay / tests): load any head whose colour is currently
  -- reachable. There is no geometric orphaning (ants only take reachable frontier
  -- cells) — the only failure is a slot jam, which is exactly the lose/ad state.
  local function fill_slots()
    if mode ~= "auto" then return end
    while free_slot() do
      local pick
      for c = 1, NCOL do
        local b = col_head(c)
        if b and reachable_count(b.color) > 0 then pick = c; break end
      end
      if not pick then break end
      load_head(pick)
    end
  end
  local function shortest_col()
    local best, bn = 1, math.huge
    for c = 1, NCOL do if #cols[c] < bn then bn = #cols[c]; best = c end end
    return best
  end
  local function cancel_slot(i)
    local s = slots[i]; if not s then return false end
    for _, a in ipairs(ants) do
      if a.slot == i and a.state == "out" then
        reserved[(a.tr-1)*W+a.tc] = nil
        s.n = s.n + 1                 -- give back the count reserved at dispatch
        local rev = { { a.x, a.y } }
        for k = a.pi, 1, -1 do rev[#rev + 1] = a.path[k] end
        a.path, a.pi, a.state = rev, 1, "back"
      end
    end
    local c = shortest_col(); table.insert(cols[c], 1, s); col_adv[c] = 1
    slots[i] = nil; return true
  end
  local function rewarded_ad(reward) game.track("rewarded_ad"); if reward then reward() end end
  local function cancel_slot_ad(i)
    if slots[i] then rewarded_ad(function() cancel_slot(i) end); return true end
    return false
  end
  -- Jammed (the lose/ad prompt): nothing carrying, no active slot colour reachable,
  -- and no free slot can load a reachable HEAD. Recoverable only by cancelling.
  local function check_stuck()
    if painted <= 0 then return false end
    for _, a in ipairs(ants) do if a.state ~= "idle" then return false end end
    for i = 1, SLOTS do local s = slots[i]; if s and reachable_count(s.color) > 0 then return false end end
    if free_slot() then
      for c = 1, NCOL do local b = col_head(c); if b and reachable_count(b.color) > 0 then return false end end
    end
    return true
  end

  -- ---- textured tiles (candy) ---------------------------------------------
  local function tint(id, ci, a)
    local col = palette[ci]; game.set_color(id, col[1], col[2], col[3], a or 1)
  end
  -- Each colour is a REAL food object (rendered sprites, not tinted cubes):
  -- the picture/queue/carried blocks read as actual chocolate/bread/sugar/candy.
  local FOOD = { "food_choc", "food_bread", "food_sugar", "food_berry", "food_mint" }
  -- ANT SPECIES tokens: one cute Animal-Crossing-style ant per colour, each
  -- hugging its own food (chocolate/bread/sugar/strawberry/mint). The queue/slot
  -- token IS this illustrated bug — a real themed object, not a tinted chip.
  -- Colours are BAKED into the art, so these are placed untinted.
  local SPECIES = { "antkind_choc", "antkind_bread", "antkind_sugar", "antkind_berry", "antkind_mint" }
  -- BOARD cells use flat matte tiles (cell_<food>_<1..4>, tools/board_cells.py):
  -- no per-cell shadow, four texture variants so same-colour runs don't repeat —
  -- the mosaic reads as ONE continuous picture, like the reference.
  local CFOOD = { "choc", "bread", "sugar", "berry", "mint" }

  -- ---- bitmap number font (num_font.png: 10 candy digits, 52x68) -----------
  local NUMA = 52 / 68
  local function num_make(str, h, alpha)
    local dw = h * NUMA; local step = dw * 0.82
    local ids, offs = {}, {}
    local x0 = -(#str - 1) * step / 2
    for i = 1, #str do
      local d = tonumber(str:sub(i, i)) or 0
      local id = game.spawn_sheet(0, 0, dw, h, "num_font", 52, 68, 10, 10)
      game.set_frame(id, d); game.set_color(id, 1, 1, 1, alpha or 1)
      ids[i] = id; offs[i] = x0 + (i - 1) * step
    end
    return { ids = ids, offs = offs }
  end
  local function num_place(num, cx, cy)
    if not num then return end
    for i, id in ipairs(num.ids) do game.move_to(id, cx + num.offs[i], cy) end
  end
  local function num_free(num)
    if num then for _, id in ipairs(num.ids) do game.despawn(id) end end
  end
  -- recolour bitmap digits (e.g. dark numbers on a light count-badge pill)
  local function num_tint(num, r, g, b)
    if num then for _, id in ipairs(num.ids) do game.set_color(id, r, g, b, 1) end end
  end

  -- ---- rendering: board ----------------------------------------------------
  local function draw_board()
    cell_id, painted = {}, 0
    for r = 1, H do cell_id[r] = {}
      for c = 1, W do
        local ci = grid[r][c]
        if ci ~= 0 then
          -- PURE-COLOUR candy pixel: one solid palette colour on a soft rounded
          -- tintable tile (pixel_tile.png). No food texture, no depth muddying —
          -- the mosaic reads as a crisp, high-saturation pixel picture (the hero
          -- visual), while the tile's rounded corners + faint bottom shade keep it
          -- tactile, not a crude flat square. A slight gap shows soil as grout.
          local col = palette[ci]
          local id = T.sprite(cx(c, r), cy(r), CELL * rs(r) * 0.95, CELL * rs(r) * 0.95, "pixel_tile")
          -- level intro: each block POPS in (0 -> overshoot -> 1), staggered in a
          -- diagonal wave across the picture — the board builds itself in ~1s
          game.tween(id, nil, nil, 1.0, 0.30, "back", (r + c) * 0.028, 0)
          game.set_color(id, col[1], col[2], col[3], 1)
          if game.shadow then game.shadow(id) end
          cell_id[r][c] = id; painted = painted + 1
        end
      end
    end
  end
  local function clear_cell(r, c)
    local id = cell_id[r][c]
    if id then game.despawn(id); cell_id[r][c] = nil end
    grid[r][c] = 0; painted = painted - 1; dirty = true
    game.emit("spark", cx(c, r), cy(r), 4)
  end

  -- ---- ants (spritesheet walk + facing + carry) ---------------------------
  local function spawn_ant(slot_i)
    local sh = game.spawn_sprite(NESTX, NESTY, CELL * ANT_SIZE * 0.7, CELL * ANT_SIZE * 0.45, "ant_shadow")
    game.set_color(sh, 1, 1, 1, 0)
    -- PIXEL ant sprite (ant_walk.png, top-down, head-up so set_rotation to the
    -- heading faces it forward). Light body + dark outline, so set_color tints it
    -- to the species colour while the outline stays dark. Ants start HIDDEN
    -- (alpha 0) resting inside the nest, not piled on the hole.
    local aw = CELL * ANT_SIZE
    -- ant_walk is a 6-frame WALK sheet (128x128 frames); the frame is advanced by
    -- the ant's travelled distance in move_along so the legs actually step.
    local id = game.spawn_sheet(NESTX, NESTY, aw, aw, "ant_walk", 128, 128, 6, 1)
    ants[#ants + 1] = { id = id, shadow = sh, slot = slot_i, state = "idle", x = NESTX, y = NESTY,
                        pi = 1, path = nil, tr = 0, tc = 0, anim = 0, carry = nil, cc = 0,
                        rig_s = 1, hidden = true, tintk = nil,
                        phase = (#ants % 8) * 0.8, dust = 0 }
  end
  -- Colour each ant to its slot's colour (a red slot -> red ants), so the swarm
  -- reads as "these ants are carrying THIS colour". Only re-set on change.
  -- ANT SPECIES BY COLOUR: ant_hero.png is a light luminance master, so tinting
  -- it turns the whole ant into a different-coloured species (chocolate ants haul
  -- chocolate, sugar-white ants haul sugar, ...). Idle ants with no slot rest as
  -- a natural warm brown. Only re-set on change.
  local IDLE_ANT = { 0.62, 0.42, 0.28 }
  -- species colour + visibility in one place: hidden ants (resting INSIDE the
  -- nest) are fully transparent, so idle workers never pile up on the hole.
  local function tint_ant(a)
    local s = slots[a.slot]
    -- A DISPATCHED ant keeps the colour it left the nest with (a.color), even
    -- after its slot empties and is cleared to nil mid-journey — otherwise the
    -- traveling ant would repaint to the idle brown ("染色丢失变成纯色"). Idle
    -- ants (a.color == nil) follow their slot so the resting swarm previews it.
    local ci = a.color or (s and s.color) or 0
    local key = ci .. (a.hidden and "h" or "v")
    if key ~= a.tintk then
      local c = (ci == 0) and IDLE_ANT or palette[ci]
      game.set_color(a.id, c[1], c[2], c[3], a.hidden and 0 or 1)
      if a.shadow then game.set_color(a.shadow, 1, 1, 1, a.hidden and 0 or 0.5) end
      a.tintk = key
    end
  end
  local function pick_target(color)
    if dirty then recompute_field() end
    local br, bc, bd
    for r = 1, H do for c = 1, W do
      if grid[r][c] == color and not reserved[(r-1)*W+c] then
        for _, p in ipairs({ {r+1,c},{r-1,c},{r,c+1},{r,c-1} }) do
          if passable(p[1], p[2]) then
            local d = dist[node(p[1], p[2])]
            if d ~= nil and (bd == nil or d < bd) then bd = d; br, bc = r, c end
          end
        end
      end
    end end
    return br, bc
  end
  local function face(a, nx, ny)
    local dx, dy = nx - a.x, ny - a.y
    if dx * dx + dy * dy > 0.0001 then a.face_target = math.atan(-dx, dy) end
  end
  local function move_along(a, dt)
    local step = ANT_SPEED * dt * (speed2 and 2 or 1)
    local sx0, sy0, moved = a.x, a.y, 0
    while step > 0 and a.pi < #a.path do
      local nx, ny = a.path[a.pi + 1][1], a.path[a.pi + 1][2]
      local dx, dy = nx - a.x, ny - a.y
      local d = math.sqrt(dx * dx + dy * dy)
      face(a, nx, ny)
      if d <= step then a.x, a.y, a.pi, step, moved = nx, ny, a.pi + 1, step - d, moved + d
      else a.x, a.y, step, moved = a.x + dx / d * step, a.y + dy / d * step, 0, moved + step end
    end
    a.anim = (a.anim + moved) % 1000
    -- step the walk-cycle frame by distance travelled (~6 frames per 0.9 cell) so
    -- the legs move while the ant walks; a still ant holds its current frame
    if moved > 0 then game.set_frame(a.id, math.floor(a.anim / (CELL * 0.15)) % 6) end
    -- SOLID pixel motion: a small CONSTANT lane offset (two-way ant road) — NO
    -- floaty perpendicular sway, so the ant tracks the path instead of drifting.
    local tdx, tdy = a.x - sx0, a.y - sy0
    local tl = math.sqrt(tdx * tdx + tdy * tdy)
    local rx, ry = a.x, a.y
    if tl > 0.01 then
      -- TWO-WAY ANT ROAD: outbound ants keep to one side, returning to the other,
      -- so opposite streams pass cleanly. A fixed offset never wobbles.
      local px, py = -tdy / tl, tdx / tl
      local lane = (a.state == "out" and 1 or -1) * CELL * 0.14
      rx, ry = a.x + px * lane, a.y + py * lane
      a.dust = a.dust + moved
      if a.dust > CELL * 1.2 then a.dust = 0; game.emit("dust", rx, ry - CELL * 0.15, 2) end
    end
    -- EASE the heading toward the path direction (no 90-degree snaps at corners)
    if a.face_target then
      a.rot = a.rot or a.face_target
      local diff = a.face_target - a.rot
      while diff > math.pi do diff = diff - 2 * math.pi end
      while diff < -math.pi do diff = diff + 2 * math.pi end
      a.rot = a.rot + diff * math.min(1, dt * 12)
      game.set_rotation(a.id, a.rot)
    end
    game.move_to(a.id, rx, ry)
    if a.shadow then game.move_to(a.shadow, rx, ry - CELL * 0.40) end
    -- carried pixel pops up from nothing, then rides the ant
    if a.carry then
      a.carry_t = math.min(1, (a.carry_t or 1) + dt * 8)
      local cs = CELL * 0.72 * (0.2 + 0.8 * a.carry_t)
      game.set_size(a.carry, cs, cs)
      game.move_to(a.carry, rx, ry - CELL * 0.5)
    end
    return a.pi >= #a.path
  end
  local function update_ant(a, dt)
    local s = slots[a.slot]
    tint_ant(a)
    if a.state == "idle" then
      if not s or s.n <= 0 then return end
      if dispatch_cd > 0 then return end   -- single file: one ant leaves at a time
      local r, c = pick_target(s.color); if not r then return end
      local p = path_to(r, c); if not p then return end
      reserved[(r-1)*W+c] = true
      s.n = s.n - 1                     -- reserve the count at DISPATCH so a slot
      slot_pulse[a.slot] = 1            -- animate the count tick-down
      a.color = s.color                 -- LOCK the dispatch colour to this ant
      a.hidden = false; tint_ant(a)     -- step out of the nest, visible again
      -- emerge pop: rig scale grows from a quarter to full (tween is absolute
      -- Transform scale, so the target is the rig's own base scale)
      game.tween(a.id, nil, nil, a.rig_s, 0.35, "back", 0, a.rig_s * 0.25)
      dispatch_cd = DISPATCH_GAP        -- next ant waits its turn at the nest
      a.tr, a.tc, a.path, a.pi, a.state = r, c, p, 1, "out"   -- never over-sends ants
    elseif a.state == "out" then
      if move_along(a, dt) then
        if grid[a.tr][a.tc] ~= 0 then
          a.cc = grid[a.tr][a.tc]
          clear_cell(a.tr, a.tc)
          a.carry = game.spawn_sprite(a.x, a.y - CELL * 0.5, CELL * 0.62, CELL * 0.62, "pixel_tile")
          local pc = palette[a.cc] or {1,1,1}; game.set_color(a.carry, pc[1], pc[2], pc[3], 1)
          a.carry_t = 0                 -- pop the picked morsel up from nothing
          game.shake(0.02); game.haptic("light")   -- grab: subtle (deposit is the sound)
        end
        reserved[(a.tr-1)*W+a.tc] = nil
        local rev = {}
        for i = #a.path, 1, -1 do rev[#rev + 1] = a.path[i] end
        a.path, a.pi, a.state = rev, 1, "back"
      end
    elseif a.state == "back" then
      if move_along(a, dt) then
        if a.carry then
          game.despawn(a.carry); a.carry = nil
          game.play_sound("ac_deposit")
          game.emit("spark", NESTX, NESTY - CELL * 0.4, 5)   -- deposit sparkle at the hole
          game.zoom(0.12)                                     -- tiny satisfying punch
        end
        a.color = nil                    -- release the lock: idle ants re-follow slot
        a.hidden = true; tint_ant(a)     -- slip back INSIDE the nest (no pile-up)
        a.state = "idle"
      end
    end
  end

  -- ---- HUD tiles (slots + tray) -------------------------------------------
  local slot_bg, slot_txt, slot_bug, tray_bg, tray_txt, tray_bug = {}, {}, {}, {}, {}, {}
  local tray_badge = {}                 -- per-queue-cell dark count-badge disc
  local slot_food = {}                 -- mini food sprite sitting in each spice box
  local slot_shown, tray_shown = {}, {}
  local coin_num, coin_shown           -- bitmap-digit LIVE score (cleared blocks)
  local coin_x, coin_y = 0, 0          -- where the score digits sit (set in build)
  local lvl_num                        -- bitmap-digit level number (in the badge)
  local prog_x0, prog_w, prog_fill, prog_stars = 0, 1, nil, {}   -- star progress bar
  local prog_y, prog_h = 0, 8          -- fill centre-line + thickness (set in build)
  local prog_star_pos = {}             -- bar-star coordinates (win-show flight targets)
  local drifters = {}                  -- ambient floating leaves/motes (bg motion)
  local buttons = {}                   -- tappable UI buttons with press-state feedback

  -- Register a pill button for press feedback + hit-testing. `sel` (optional) is
  -- a predicate → the button shows a lit "selected" state while it returns true
  -- (e.g. speed x2 while active); `on_tap` runs when it's pressed.
  local function add_button(id, rect, base, on_tap, sel)
    buttons[#buttons + 1] = { id = id, rect = rect, base = base, pulse = 0, on_tap = on_tap, sel = sel }
  end
  -- Ease each button back from its last press; pressed = darker (pushed in),
  -- selected = brighter (lit). Runs every frame so it animates on the win card too.
  local function update_buttons(dt)
    for _, b in ipairs(buttons) do
      b.pulse = math.max(0, b.pulse - dt * 6)
      local k = 1 - 0.28 * b.pulse                       -- press darkens
      local lift = (b.sel and b.sel()) and 0.16 or 0     -- selected brightens toward white
      game.set_color(b.id, b.base[1] * k + lift, b.base[2] * k + lift, b.base[3] * k + lift, 1)
    end
  end
  -- Hit-test the buttons; on a press, pulse + fire on_tap. Returns true if consumed.
  local function press_button(x, y)
    for _, b in ipairs(buttons) do
      if K.in_rect(b.rect, x, y) then
        b.pulse = 1; game.play_sound("ac_load"); game.haptic("light")
        if b.on_tap then b.on_tap() end
        return true
      end
    end
    return false
  end

  -- Ambient background motion: a handful of soft leaves + light motes that drift
  -- slowly upward-diagonally and wrap, so the scene never feels static. Spawned
  -- behind the board; cheap (just move_to + set_rotation per frame).
  local function spawn_drifters()
    drifters = {}
    for i = 1, 11 do
      local leaf = (i % 3 ~= 0)                       -- 2/3 leaves, 1/3 glowing motes
      local sz = leaf and (16 + math.random() * 14) or (7 + math.random() * 7)
      local id = game.spawn_sprite(0, 0, sz, sz, leaf and "leaf" or "petal")
      if leaf then
        local g = 0.35 + math.random() * 0.3
        game.set_color(id, 0.55 * g + 0.3, 0.62 * g + 0.28, 0.30 * g + 0.18, 0.5)
      else
        game.set_color(id, 1, 0.98, 0.9, 0.5)
      end
      drifters[i] = {
        id = id, leaf = leaf,
        x = (math.random() * 2 - 1) * HW, y = (math.random() * 2 - 1) * HH,
        vx = (math.random() * 2 - 1) * 10, vy = 6 + math.random() * 12,
        rot = math.random() * 6.28, spin = (math.random() * 2 - 1) * 0.6,
      }
    end
  end
  local function update_drifters(dt)
    for _, d in ipairs(drifters) do
      d.x = d.x + d.vx * dt; d.y = d.y + d.vy * dt; d.rot = d.rot + d.spin * dt
      if d.y > HH + 30 then d.y = -HH - 30; d.x = (math.random() * 2 - 1) * HW end
      if d.x > HW + 30 then d.x = -HW - 30 elseif d.x < -HW - 30 then d.x = HW + 30 end
      game.move_to(d.id, d.x, d.y)
      if d.leaf then game.set_rotation(d.id, d.rot) end
    end
  end

  -- Despawn every dynamically-spawned (untracked) sprite: ants + their shadows/
  -- carried pixels, and all bitmap-number digits. Called on rebuild and leave so
  -- nothing leaks (T.clear only covers tracker-owned sprites).
  local function despawn_dynamic()
    for _, a in ipairs(ants) do
      game.despawn(a.id)
      if a.shadow then game.despawn(a.shadow) end
      if a.carry then game.despawn(a.carry) end
    end
    for i = 1, SLOTS do num_free(slot_txt[i]); slot_txt[i] = nil end
    for c = 1, NCOL do for row = 0, QROWS - 1 do num_free(tray_txt[qi and qi(c, row) or ((c-1)*QROWS+row+1)]); end end
    tray_txt = {}
    num_free(coin_num); coin_num = nil
    num_free(lvl_num); lvl_num = nil
    prog_fill, prog_stars = nil, {}   -- tracker-owned sprites; drop stale refs
    for _, id in ipairs(intro.ids) do game.despawn(id) end
    intro.ids, intro.t = {}, nil      -- kill any mid-flight level-intro card
    for _, d in ipairs(drifters) do game.despawn(d.id) end; drifters = {}
    buttons = {}   -- pill sprites are tracker-owned (T.clear despawns them); drop stale refs
  end
  local QYGAP = 6
  local function slot_x(i) return (i - (SLOTS + 1) / 2) * (SLOT_W + 8) end
  local function col_x(c) return (c - (NCOL + 1) / 2) * (TRAY_W + 8) end
  local function row_y(row) return TRAY_Y - row * (TRAY_W + QYGAP) end   -- row 0 = head (top)
  local function qi(c, row) return (c - 1) * QROWS + row + 1 end          -- 0-based row

  local function draw_hud()
    -- CLEAN trays (empty Floniks wooden trays), drawn as 9-SLICE panels so the
    -- rounded rim stays native-crisp at any stretch (a plain scaled sprite blurs)
    local strip_w = SLOTS * (SLOT_W + 8) + 44
    T.panel(0, SLOT_Y, strip_w, SLOT_W + 26, "tray_wood", 81)
    local q_cy = (row_y(0) + row_y(QROWS - 1)) / 2
    local q_w = NCOL * (TRAY_W + 8) + 44
    local q_h = QROWS * (TRAY_W + QYGAP) + 26
    T.panel(0, q_cy, q_w, q_h, "tray_wood", 81)
    -- bento partition WALLS between cells (raised honey-wood dividers, like the
    -- mockup's compartment trays)
    for i = 1, SLOTS - 1 do
      local w = T.sprite((slot_x(i) + slot_x(i + 1)) / 2, SLOT_Y, 6, SLOT_W * 0.88, "tile_sq")
      game.set_color(w, 0.88, 0.68, 0.44, 1)
    end
    for c = 1, NCOL - 1 do
      local w = T.sprite((col_x(c) + col_x(c + 1)) / 2, q_cy, 6, q_h * 0.86, "tile_sq")
      game.set_color(w, 0.88, 0.68, 0.44, 1)
    end
    for i = 1, SLOTS do
      -- a soft recessed CUP socket (covers the baked block); empty = bare cup,
      -- filled = the cute species-ant character sits in it. Neutral dark so the
      -- illustrated ant (its own colour + shading) reads on top.
      slot_bg[i] = T.sprite(slot_x(i), SLOT_Y, SLOT_W * 0.98, SLOT_W * 0.90, "tile_sq")
      game.set_color(slot_bg[i], 0.31, 0.23, 0.16, 1)
      slot_shown[i] = nil
    end
    for c = 1, NCOL do for row = 0, QROWS - 1 do
      local i = qi(c, row)
      tray_bg[i], tray_bug[i], tray_badge[i] = nil, nil, nil   -- queue cells spawn on demand
      tray_shown[i] = nil
    end end
  end
  local total_cells = 0   -- set in build; drives the star progress bar
  local function refresh_hud()
    -- TIME RACE bar: the fill drains from full to empty over the deadline (par1),
    -- shifting gold -> orange -> red as time runs out. The 3 stars are the live
    -- grade you'll earn (all lit, then drop right-to-left as you pass par3/par2)
    -- — race the clock to keep them. Completion shows in the emptying picture.
    if prog_fill and total_cells > 0 then
      local frac = math.max(0, math.min(1, 1 - elapsed / par1))   -- time remaining
      local fw = math.max(1, prog_w * frac)
      game.set_size(prog_fill, fw, prog_h or 8)
      game.move_to(prog_fill, prog_x0 + fw / 2, prog_y or (HH - 34))
      if frac > 0.5 then game.set_color(prog_fill, 1.0, 0.78, 0.20, 1)
      elseif frac > 0.25 then game.set_color(prog_fill, 1.0, 0.55, 0.15, 1)
      else game.set_color(prog_fill, 0.95, 0.28, 0.20, 1) end
      -- boss beetle rides the draining edge, marching toward the start (boss lvls)
      if boss_on and boss_id then game.move_to(boss_id, prog_x0 + fw, prog_y) end
      for k = 1, 3 do
        if prog_stars[k] then
          if k <= star_grade then game.set_color(prog_stars[k], 1, 1, 1, 1)
          else game.set_color(prog_stars[k], 0.42, 0.32, 0.24, 1) end
        end
      end
      -- LIVE score: cleared blocks, as bitmap digits next to the coin
      local score = tostring(total_cells - painted)
      if score ~= coin_shown then
        num_free(coin_num)
        coin_num = num_make(score, 18, 1)
        coin_shown = score
      end
      num_place(coin_num, coin_x, coin_y)
    end
    for i = 1, SLOTS do
      local s = slots[i]
      -- count-tick pulse: bump the committed food briefly, then ease back
      local p = slot_pulse[i] or 0
      if slot_food[i] then
        if p > 0.01 then
          local sc = SLOT_W * 0.98 * (1 + 0.18 * p); game.set_size(slot_food[i], sc, sc)
          slot_pulse[i] = p * 0.82
        elseif slot_pulse[i] then
          game.set_size(slot_food[i], SLOT_W * 0.98, SLOT_W * 0.98); slot_pulse[i] = nil
        end
      end
      -- key includes the colour: respawn the ant + count when it changes
      local lbl = s and (tostring(s.n) .. ":" .. s.color) or ""
      if lbl ~= slot_shown[i] then
        num_free(slot_txt[i]); slot_txt[i] = nil
        if slot_food[i] then game.despawn(slot_food[i]); slot_food[i] = nil end
        if slot_bug[i] then game.despawn(slot_bug[i]); slot_bug[i] = nil end
        if s then
          -- the cute SPECIES-ANT character (hugging its food) sits in the cup —
          -- an illustrated themed object, not a tinted chip. Colour is baked in.
          slot_food[i] = T.sprite(slot_x(i), SLOT_Y, SLOT_W * 0.98, SLOT_W * 0.98, SPECIES[s.color])
          game.tween(slot_food[i], nil, nil, 1.0, 0.26, "back", 0, 0.3)   -- pop into the cup
          -- count badge: a light cream pill + dark digits in the corner (concept
          -- style — a clear quantity read that pops off the ant)
          slot_bug[i] = T.sprite(slot_x(i) + SLOT_W * 0.30, SLOT_Y - SLOT_W * 0.30, SLOT_W * 0.46, SLOT_W * 0.46, "tile_sq")
          game.set_color(slot_bug[i], 0.98, 0.92, 0.78, 1)
          slot_txt[i] = num_make(tostring(s.n), SLOT_W * 0.34, 1)
          num_tint(slot_txt[i], 0.30, 0.21, 0.14)
        end
        slot_shown[i] = lbl
      end
      num_place(slot_txt[i], slot_x(i) + SLOT_W * 0.30, SLOT_Y - SLOT_W * 0.30)
    end
    for c = 1, NCOL do
      local slide = (col_adv[c] or 0)
      if slide > 0.01 then col_adv[c] = slide * 0.8 elseif col_adv[c] then col_adv[c] = nil end
      for row = 0, QROWS - 1 do
        local i = qi(c, row)
        local b = cols[c][row + 1]
        local head = (row == 0)
        local a = head and 1 or 0.75                -- head row live; deeper rows only
                                                    -- slightly dimmed (was muddy at 0.5)
        local yy = row_y(row) - slide * (TRAY_W + QYGAP)   -- slide up from one row below
        local xx = col_x(c)
        -- a wooden TOKEN + a colour-tinted ANT + count, so the queue reads
        -- "N ants of this colour" (was a food block, which read as candy).
        -- Head row is bright; deeper rows dim via alpha `a`.
        local lbl = b and (tostring(b.n) .. ":" .. b.color) or ""
        if lbl ~= tray_shown[i] then
          num_free(tray_txt[i]); tray_txt[i] = nil
          if tray_bg[i] then game.despawn(tray_bg[i]); tray_bg[i] = nil end
          if tray_bug[i] then game.despawn(tray_bug[i]); tray_bug[i] = nil end
          if tray_badge[i] then game.despawn(tray_badge[i]); tray_badge[i] = nil end
          if b then
            -- soft cup socket + the cute SPECIES-ANT character + a count badge
            tray_bg[i] = T.sprite(xx, yy, TRAY_W * 0.98, TRAY_W * 0.92, "tile_sq")
            game.set_color(tray_bg[i], 0.31, 0.23, 0.16, a)   -- neutral cup socket
            game.tween(tray_bg[i], nil, nil, 1.0, 0.24, "back", 0, 0.4)   -- pop on arrival
            tray_bug[i] = T.sprite(xx, yy, TRAY_W * 0.98, TRAY_W * 0.98, SPECIES[b.color])
            game.set_color(tray_bug[i], 1, 1, 1, a)  -- illustrated ant (baked colour), dim deep rows
            tray_badge[i] = T.sprite(xx + TRAY_W * 0.30, yy - TRAY_W * 0.30, TRAY_W * 0.44, TRAY_W * 0.44, "tile_sq")
            game.set_color(tray_badge[i], 0.98, 0.92, 0.78, a)     -- light cream pill
            tray_txt[i] = num_make(tostring(b.n), TRAY_W * 0.32, a)
            num_tint(tray_txt[i], 0.30, 0.21, 0.14)                -- dark digits
          end
          tray_shown[i] = lbl
        end
        if tray_bg[i] then game.move_to(tray_bg[i], xx, yy) end
        if tray_bug[i] then game.move_to(tray_bug[i], xx, yy) end
        if tray_badge[i] then game.move_to(tray_badge[i], xx + TRAY_W * 0.30, yy - TRAY_W * 0.30) end
        num_place(tray_txt[i], xx + TRAY_W * 0.30, yy - TRAY_W * 0.30)
      end
    end
  end

  local function status()
    if not SETTINGS.hud then return end
    -- only the stuck rescue prompt is ever shown; no idle hint text
    game.set_text(stuck and "Stuck? Tap a filled slot to cancel (watch ad)" or "")
  end

  -- ---- level-intro title card ("LEVEL N") ----------------------------------
  -- A clear "new level" beat (Supercell-style): a wooden plate + the level title
  -- sweeps down from above, holds, then lifts away and fades. Self-animated in
  -- update_intro (position + alpha), spawned untracked so despawn_dynamic reaps
  -- it if the level rebuilds mid-flight.
  local function clear_intro()
    for _, id in ipairs(intro.ids) do game.despawn(id) end
    intro.ids, intro.t = {}, nil
  end
  local function show_intro()
    clear_intro()
    local y = HH * 0.34
    local plate = game.spawn_sprite(0, y, 300, 96, "bar_wood")
    game.set_layer(plate, 95)               -- above the vignette (layer 90)
    local txt = game.spawn_text(0, y, 42, 1.00, 0.96, 0.86, 1, "LEVEL " .. cur_lvl)
    intro.ids, intro.plate, intro.txt, intro.y, intro.t = { plate, txt }, plate, txt, y, 0
  end
  local function update_intro(dt)
    if not intro.t then return end
    intro.t = intro.t + dt
    local t, IN, HOLD, OUT = intro.t, 0.34, 1.10, 0.42
    local total = IN + HOLD + OUT
    local yoff, alpha
    if t < IN then
      local p = t / IN; local e = 1 - (1 - p) * (1 - p)   -- ease-out drop-in
      yoff, alpha = (1 - e) * 130, math.min(1, p * 1.6)
    elseif t < IN + HOLD then
      yoff, alpha = 0, 1
    elseif t < total then
      local p = (t - IN - HOLD) / OUT                     -- lift up and fade out
      yoff, alpha = -p * 100, 1 - p
    else
      clear_intro(); return
    end
    local y = intro.y + yoff
    game.move_to(intro.plate, 0, y); game.set_color(intro.plate, 1, 1, 1, alpha)
    game.move_to(intro.txt, 0, y); game.set_color(intro.txt, 1.00, 0.96, 0.86, alpha)
  end

  -- ---- build ---------------------------------------------------------------
  local function build(hw, hh)
    HW, HH = hw, hh
    despawn_dynamic()   -- clear any leftover ants / bitmap digits before a rebuild
    -- pick the current level and re-derive the level-sized geometry
    LEVEL = LEVELS[((cur_lvl - 1) % #LEVELS) + 1]
    W, H = LEVEL.w, LEVEL.h
    NW = W + 2
    NEST = node(H + 1, math.floor(W / 2) + 1)

    -- ---- deterministic layout, stacked BOTTOM-UP so nothing ever overlaps ----
    -- The PICTURE is the hero and gets the lion's share of the height. A COMPACT
    -- control panel (queue + slots) sits at the bottom, a SMALL nest hole tucks
    -- just under the board, and the mosaic fills all the rest up to the HUD.
    -- Everything is inset by FRAME so nothing sits under the pixel bezel that
    -- encloses the play field. The status bar drops below the top bezel; a small
    -- toolbar band under it holds the back/mute medallions (off the play area).
    local FRAME = 20                   -- bezel inset (matches game_frame border)
    local BAR_CY = hh - 34 - FRAME     -- status bar centre (below top bezel)
    local BAR_H = 46
    local BTN_CY = (BAR_CY - BAR_H / 2) - 26   -- back/mute band, below the bar
    local M = FRAME + 14               -- bottom margin (clears the bottom bezel)
    TRAY_W = math.min((2 * hw - 44) / 4 - 8, 54)
    SLOT_W = math.min((2 * hw - 60) / 5 - 8, 50)
    -- control panel: QROWS queue rows (head row on top) + one slot row above them
    local q_bot = -hh + M + TRAY_W / 2                      -- bottom queue row centre
    TRAY_Y = q_bot + (QROWS - 1) * (TRAY_W + 5)             -- head row (row 0, top)
    SLOT_Y = (TRAY_Y + TRAY_W / 2) + 20 + SLOT_W / 2        -- slots just above the queue
    local panel_top = SLOT_Y + SLOT_W / 2                  -- top edge of the control panel
    -- a small band for the nest hole between the panel and the board's lower edge
    local HOLE_BAND = 52
    local board_bottom = panel_top + HOLE_BAND              -- ants exit into the hole here
    -- RESPONSIVE: the picture fills the screen WIDTH (like the reference), capped
    -- only by the (now generous) vertical space left up to the HUD — it scales
    -- with the device, never a fixed size. Leave ~2.6 blocks of width for the
    -- soil-plot rim + inner margin so the mosaic sits inside a generous plot.
    -- Board fills the width (inside the bezel) and grows up to a top budget that
    -- leaves the button band clear — the plot RIM (≈ 1.35 cells above the mosaic)
    -- must not reach the buttons, so it's subtracted from the budget.
    local widthCell = (2 * hw - 18 - 2 * FRAME) / (W + 2.6)
    local rim = widthCell * 1.35
    local board_h = ((BTN_CY - 22) - rim) - board_bottom
    CELL = math.min(widthCell, board_h / (H * (1 - PERSP / 2)))
    -- nest hole: sized to the CELLS (a modest ~2-cell entrance, not a crater) and
    -- centred in the hole band right under the board — a landmark, not the star.
    local HOLE_R = CELL * 1.05
    NESTY = panel_top + HOLE_BAND / 2                       -- hole centre in its band
    OX = -W * CELL / 2
    -- per-row scale (top row most shrunken) + stacked centre-lines, bottom-up
    PS, ROWY = {}, {}
    for r = 1, H do PS[r] = 1 - PERSP * (H - r) / math.max(1, H - 1) end
    local yy = board_bottom
    for r = H, 1, -1 do
      ROWY[r] = yy + CELL * PS[r] / 2
      yy = yy + CELL * PS[r]
    end
    TOPY = yy                                              -- top edge of the picture
    NESTX = cx(math.floor(W / 2) + 1, H)

    grid, painted = {}, 0
    for r = 1, H do grid[r] = {} for c = 1, W do grid[r][c] = LEVEL.grid[r][c] end end
    -- Fixed queue: distribute the (peel-order, guaranteed-solvable) tray round-
    -- robin into NCOL columns. Only column HEADS load; the layout never shuffles.
    tray, cols, col_adv = {}, { {}, {}, {}, {} }, {}
    for i, b in ipairs(LEVEL.tray) do
      local bb = { color = b[1], n = b[2] }
      cols[(i - 1) % NCOL + 1][#cols[(i - 1) % NCOL + 1] + 1] = bb
    end
    slots, reserved, ants, dirty = {}, {}, {}, true
    playing, won, stuck, speed2, was_stuck = true, false, false, false, false
    dispatch_cd = 0

    -- full-screen background (generated art), behind everything. Each level has
    -- its OWN biome so the run reads as a JOURNEY (meadow -> forest -> autumn ->
    -- desert -> snow) — a sense of level progression. Cycles with the levels.
    local BGS = { "game_bg", "bg_forest", "bg_autumn", "bg_desert", "bg_snow",
                  "bg_beach", "bg_candy", "bg_night", "bg_cave", "bg_lava" }
    local bgtex = BGS[((cur_lvl - 1) % #BGS) + 1] or "game_bg"
    local bgspr = T.sprite(0, 0, math.max(2 * hw, 2 * hh * 512 / 768) + 4, 2 * hh + 4, bgtex)
    game.set_color(bgspr, 1, 1, 1, 1)   -- biome colour baked into the texture
    spawn_drifters()   -- ambient floating leaves/motes over the background
    -- (No dark vignette — Animal Crossing is bright & high-key. Focus comes from
    -- the soil plot + soft drop-shadows, not from darkening the frame.)
    -- top status bar: SEPARATE live sprites (no baked values) — wooden plank,
    -- level badge + live digits, star progress groove, coin + live score
    local by = BAR_CY
    local bar_w = 2 * hw - 2 * (FRAME + 8)
    local bar_h = BAR_H
    T.panel(0, by, bar_w, bar_h, "bar_wood", 52)
    local function bfx(f) return -bar_w / 2 + f * bar_w end -- fraction -> x
    T.sprite(bfx(0.09), by, bar_h * 1.25, bar_h * 1.25, "badge_wood")
    lvl_num = num_make(tostring(cur_lvl), bar_h * 0.46, 1)
    num_place(lvl_num, bfx(0.09), by)
    -- progress groove + live fill, then the three stars (dark until earned)
    prog_x0, prog_w = bfx(0.21), bar_w * (0.72 - 0.21)
    prog_y, prog_h = by, bar_h * 0.22
    local groove = T.sprite(prog_x0 + prog_w / 2, prog_y, prog_w, prog_h + 6, "tile_sq")
    game.set_color(groove, 0.22, 0.13, 0.08, 0.9)
    prog_fill = T.sprite(prog_x0, prog_y, 1, prog_h, "tile_sq")
    game.set_color(prog_fill, 1.0, 0.78, 0.20, 1)
    prog_stars, prog_star_pos = {}, {}
    for k, f in ipairs({ 0.38, 0.505, 0.63 }) do
      prog_stars[k] = T.sprite(bfx(f), by + 1, bar_h * 0.52, bar_h * 0.52, "icon_star")
      game.set_color(prog_stars[k], 0.42, 0.32, 0.24, 1)    -- unlit until earned
      prog_star_pos[k] = { bfx(f), by + 1 }                 -- flight targets (win show)
    end
    T.sprite(bfx(0.80), by, 28, 28, "icon_coin")
    coin_num, coin_shown = nil, nil                         -- live score (set in refresh)
    coin_x, coin_y = bfx(0.895), by
    -- DUG SOIL PLOT (Animal Crossing look): the mosaic sits in a warm soil bed
    -- framed by a soft raised earth rim, on the bright grass — a LIGHT surface,
    -- not a dark mat. A soft drop shadow grounds it. 9-slice keeps the rim crisp.
    local b_bot = ROWY[H] and (ROWY[H] - CELL * PS[H] / 2) or (TOPY - H * CELL)
    local pcx = (TOPY + b_bot) / 2 - 2
    local plot_w = W * CELL + CELL * 2.6
    local plot_h = (TOPY - b_bot) + CELL * 2.7
    -- pixel dirt bed (no soft shadow — pixel-art style)
    local plot = T.panel(0, pcx, plot_w, plot_h, "soil_plot", 66)   -- pixel dirt frame
    game.set_color(plot, 1, 1, 1, 1)                           -- baked pixel dirt colour
    -- nest hole (generated art). The unlock buttons and the shovel/bomb power-up
    -- buttons are removed for now (no function behind them yet).
    T.sprite(NESTX, NESTY, HOLE_R * 2.0, HOLE_R * 2.0, "hole")
    -- crumb debris: a few fallen morsels scattered under the picture (mockup decor)
    for k = 1, 6 do
      local fx = (math.random() * 2 - 1) * CELL * W * 0.42
      local fy = board_bottom - 10 - math.random() * 26
      local sz = CELL * (0.22 + math.random() * 0.16)
      local cr = T.sprite(fx, fy, sz, sz, "pixel_tile")
      local pc = palette[math.random(1, #palette)]
      game.set_color(cr, pc[1], pc[2], pc[3], 0.9)
    end

    draw_board()
    total_cells = painted            -- progress bar denominator (set once per build)
    -- TIME RACE thresholds, scaled to the level's size (bigger picture = more
    -- time). Generous so casual play still earns stars; tune to taste. Boss levels
    -- get a TIGHTER deadline (par1) — the bar can actually run out and you lose.
    elapsed, star_grade, lost = 0, 3, false
    boss_on = ((cur_lvl - 1) % #LEVELS) + 1 >= BOSS_FROM
    par3 = math.max(8, total_cells * 0.60)    -- fast  -> keep all 3 stars
    par2 = math.max(16, total_cells * 1.00)   -- ok    -> 2 stars
    par1 = math.max(28, total_cells * (boss_on and 1.15 or 1.60))   -- deadline
    draw_hud()
    -- the boss marker rides the draining edge of the time bar (boss levels only)
    if boss_on then
      boss_id = T.sprite(prog_x0 + prog_w, prog_y, prog_h * 3.4, prog_h * 3.4, "boss")
    else
      boss_id = nil
    end
    -- pixel bezel enclosing the whole play field (drawn on top so it frames the
    -- board/HUD on every edge; the buttons below sit inside the window, on top).
    T.sprite(0, 0, 2 * hw, 2 * hh, "game_frame")
    -- back + sound: two small wooden medallions in the toolbar band under the bar,
    -- OFF the play area (the bar itself is badge · star progress · coin)
    back = { x = -hw + FRAME + 22, y = BTN_CY, w = 36, h = 36 }
    T.sprite(back.x, back.y, back.w, back.h, "badge_wood")
    T.sprite(back.x, back.y, 22, 22, "icon_back")   -- AC back arrow (was a "<" glyph)
    local snd_b = T.sprite(back.x + 44, back.y, 36, 36, "badge_wood")
    local snd_i = T.sprite(back.x + 44, back.y, 23, 23, "icon_sound")
    add_button(snd_b, { x = back.x + 44, y = back.y, w = 36, h = 36 }, { 1, 1, 1 }, function()
      muted = not muted
      local v = muted and 0 or 1
      game.set_volume("music", v); game.set_volume("sfx", v)
      game.set_color(snd_i, 1, 1, 1, muted and 0.25 or 1)
    end)
    fill_slots()
    for i = 1, SLOTS do for _ = 1, ANTS_PER_SLOT do spawn_ant(i) end end
    recompute_field(); status(); built = true
    show_intro()        -- announce the level (sweeps in over the fresh board)

    DEBUG = {
      game = "ant_clear", back = back,
      painted = function() return painted end,
      tray_len = function() return queue_total() end,
      won = function() return won end,
      stuck = function() return stuck end,
      reachable = function(col) return reachable_count(col) end,
      ant_xy = function() local o = {} for _, a in ipairs(ants) do o[#o + 1] = { a.x, a.y } end return o end,
      grid = function() return grid end,
      toggle_speed = function() speed2 = not speed2 end,
      set_mode = function(m) mode = m; fill_slots() end,
      free_slots = function() local n = 0 for i = 1, SLOTS do if slots[i] == nil then n = n + 1 end end return n end,
      load = function(c) return load_head(c) end,   -- c = column index (1..NCOL)
      load_unreachable = function()                  -- load a buried-colour head (a wrong move)
        if not free_slot() then return false end
        for c = 1, NCOL do local b = col_head(c); if b and reachable_count(b.color) == 0 then return load_head(c) end end
        return false
      end,
      cancel = function(i) return cancel_slot_ad(i) end,
      tray_colors = function() local o = {} for c = 1, NCOL do local b = col_head(c); o[c] = b and b.color or 0 end return o end,
      slot_colors = function() local o = {} for i = 1, SLOTS do o[i] = slots[i] and slots[i].color or 0 end return o end,
    }
  end

  local function win()
    playing, won, win_t = false, true, 0
    game.set_text("")                    -- no caption; the star show says it
    -- TIME GRADE: the stars still lit when you finished = the grade earned. Keep
    -- the best per level (for the select page) and add a speed bonus to the score.
    local g = star_grade
    local beaten = cur_lvl
    best_stars[beaten] = math.max(best_stars[beaten] or 0, g)
    local bonus = math.floor(math.max(0, par2 - elapsed) * 6)   -- faster = bigger
    local final = (total_cells or 0) + bonus
    num_free(coin_num); coin_num = num_make(tostring(final), 18, 1); coin_shown = tostring(final)
    num_place(coin_num, coin_x, coin_y)
    -- advance the saved progression; the celebration auto-advances into it. Beating
    -- level N unlocks N+1 in the level-select page (max_lvl never decreases).
    cur_lvl = (cur_lvl % #LEVELS) + 1
    max_lvl = math.max(max_lvl, math.min(#LEVELS, beaten + 1))
    if game.save then
      game.save("ant_clear_lvl", cur_lvl); game.save("ant_clear_max", max_lvl)
      game.save("ant_clear_stars_" .. beaten, best_stars[beaten])
    end
    game.play_sound("ac_win"); game.haptic("success"); game.shake(0.5); game.log("ant_clear win")
    game.zoom(0.6)
    -- WIN SHOW: the EARNED stars rise from where the picture was and fly one by
    -- one into their bar sockets (overshoot ease), each launch with confetti
    local py = TOPY - 0.5 * CELL * H
    for k = 1, g do
      local sp = prog_star_pos[k]
      if sp then
        local st = T.sprite(0, py, 46, 46, "icon_star")
        game.tween(st, sp[1], sp[2], 0.55, 0.62, "back", 0.18 + (k - 1) * 0.34, 2.0)
      end
    end
    for i = 1, 6 do
      game.emit("confetti", (math.random() * 2 - 1) * CELL * W * 0.4,
                py + (math.random() * 2 - 1) * CELL * H * 0.3, 14)
    end
  end

  -- The BOSS caught you: the time bar emptied before the picture was cleared.
  -- No progress lost — tap to retry the same level (cur_lvl is NOT advanced).
  local function lose()
    playing, won, lost, win_t = false, false, true, 0
    game.play_sound("ac_stuck"); game.haptic("heavy"); game.shake(0.7); game.log("ant_clear lose")
    local cyb = TOPY - 0.5 * CELL * H
    -- dim the whole field, then the boss looms in over the board with a caption
    local ov = T.sprite(0, 0, 2 * HW + 8, 2 * HH + 8, "tile_sq")
    game.set_color(ov, 0.06, 0.05, 0.08, 0.55)
    local bz = T.sprite(0, cyb + CELL * 1.0, CELL * 5.2, CELL * 5.2, "boss")
    game.tween(bz, nil, nil, 1.0, 0.42, "back", 0, 0.25)
    T.text(0, cyb + CELL * 4.4, 27, 1.0, 0.34, 0.30, 1, "BOSS WINS!")
    T.text(0, cyb - CELL * 1.6, 19, 1, 0.96, 0.86, 1, "TAP TO RETRY")
    game.emit("dust", 0, cyb, 14)
  end

  -- ---- LEVEL SELECT page ---------------------------------------------------
  -- A grid of picture-preview cards (rendered from each level's grid, see
  -- tools/gen_level_thumbs.py). Levels above max_lvl show a padlock and can't be
  -- entered; unlocked ones jump straight into that level on tap. Everything is
  -- tracked (T.*) so T.clear() tears the page down when a card / back is tapped.
  local function build_select(hw, hh)
    HW, HH = hw, hh
    T.clear(); despawn_dynamic(); ants = {}; sel_cards = {}
    local FRAME = 20
    local bgspr = T.sprite(0, 0, math.max(2 * hw, 2 * hh * 512 / 768) + 4, 2 * hh + 4, "game_bg")
    game.set_color(bgspr, 1, 1, 1, 1)
    spawn_drifters()
    -- title bar + back medallion (mirrors the play screen's toolbar)
    local ty = hh - 34 - FRAME
    T.panel(0, ty, 2 * hw - 2 * (FRAME + 8), 46, "bar_wood", 52)
    T.text(0, ty, 30, 1, 0.96, 0.86, 1, "LEVELS")
    sel_back = { x = -hw + FRAME + 22, y = ty - 58, w = 36, h = 36 }
    T.sprite(sel_back.x, sel_back.y, 36, 36, "badge_wood")
    T.sprite(sel_back.x, sel_back.y, 22, 22, "icon_back")
    -- 3-column card grid, centred, below the title/back band
    local COLS = 3
    local usable_w = 2 * hw - 2 * (FRAME + 12)
    local gap = 14
    local cw = (usable_w - (COLS - 1) * gap) / COLS
    local ch = cw
    local ROWS = math.ceil(#LEVELS / COLS)
    local grid_top = (ty - 96) - ch / 2                    -- first row centre
    for idx = 0, #LEVELS - 1 do
      local r, c = math.floor(idx / COLS), idx % COLS
      local cx = -usable_w / 2 + cw / 2 + c * (cw + gap)
      local cy = grid_top - r * (ch + gap)
      local lvl = idx + 1
      local locked = lvl > max_lvl
      local card = T.panel(cx, cy, cw, ch, "tray_wood", 66)
      local th = T.sprite(cx, cy + ch * 0.05, cw * 0.62, ch * 0.62, "lvl_thumb_" .. lvl)
      if locked then
        game.set_color(card, 0.52, 0.50, 0.54, 1)
        game.set_color(th, 0.30, 0.30, 0.34, 1)
        T.sprite(cx, cy, cw * 0.34, cw * 0.34, "icon_lock")
      else
        game.set_color(card, 1, 1, 1, 1)
        T.text(cx, cy + ch * 0.36, 20, 1, 0.96, 0.86, 1, tostring(lvl))
        -- earned time-grade stars along the card's bottom (dark = not yet earned)
        local bs = best_stars[lvl] or 0
        for s = 1, 3 do
          local st = T.sprite(cx + (s - 2) * cw * 0.20, cy - ch * 0.37, cw * 0.16, cw * 0.16, "icon_star")
          if s <= bs then game.set_color(st, 1.0, 0.82, 0.20, 1)
          else game.set_color(st, 0.40, 0.34, 0.28, 1) end
        end
      end
      sel_cards[#sel_cards + 1] = { x = cx, y = cy, w = cw, h = ch, lvl = lvl, locked = locked }
    end
    -- the pixel bezel on top, framing the page like the play screen
    T.sprite(0, 0, 2 * hw, 2 * hh, "game_frame")
  end

  return {
    enter = function()
      built = false; screen = "play"
      -- (assign first: a host whose `load` returns no values must read as nil)
      local saved = game.load and game.load("ant_clear_lvl")
      cur_lvl = tonumber(saved) or cur_lvl
      -- FREE PLAY: every level is unlocked so you can jump straight to any picture
      -- (including the big 45x60 rocket). The star rating on each card still tracks
      -- which levels you've completed and how fast, so progression is still visible.
      max_lvl = #LEVELS
      for i = 1, #LEVELS do   -- best time-grade per level (for the select cards)
        local s = game.load and game.load("ant_clear_stars_" .. i)
        best_stars[i] = tonumber(s) or best_stars[i] or 0
      end
      game.play_music("ac_bgm")
    end,
    leave = function() T.clear(); despawn_dynamic(); ants = {}; built = false; game.stop_music() end,
    tap = function(x, y)
      -- LEVEL SELECT page: back -> menu, tap an unlocked card -> jump to that level
      if screen == "select" then
        if sel_back and K.in_rect(sel_back, x, y) then K.switch("menu"); return end
        for _, cd in ipairs(sel_cards) do
          if math.abs(x - cd.x) <= cd.w / 2 and math.abs(y - cd.y) <= cd.h / 2 then
            if cd.locked then
              game.play_sound("ac_stuck"); game.haptic("medium")   -- locked buzz
            else
              cur_lvl = cd.lvl; screen = "play"
              game.play_sound("ac_place"); game.haptic("light")
              T.clear(); build(HW, HH)
            end
            return
          end
        end
        return
      end
      -- PLAY screen: the back button now opens the level-select page
      if back and K.in_rect(back, x, y) then screen = "select"; build_select(HW, HH); return end
      if not playing then game.set_text(""); T.clear(); build(HW, HH); return end
      if press_button(x, y) then return end   -- bottom bar + unlock buttons (press feedback)
      if mode == "manual" then
        for i = 1, SLOTS do
          if slots[i] and math.abs(x - slot_x(i)) <= SLOT_W * 0.6 and math.abs(y - SLOT_Y) <= SLOT_W * 0.6 then
            if cancel_slot_ad(i) then game.play_sound("ac_load"); game.haptic("medium") end
            return
          end
        end
        if free_slot() then
          for c = 1, NCOL do   -- only the top row (column heads) can be loaded
            if col_head(c) and math.abs(x - col_x(c)) <= TRAY_W * 0.55 and math.abs(y - row_y(0)) <= TRAY_W * 0.6 then
              if load_head(c) then game.play_sound("ac_place"); game.haptic("light") end
              return
            end
          end
        end
      end
    end,
    update = function(dt, hw, hh)
      if not built then build(hw, hh) end
      if screen == "select" then update_drifters(math.min(dt, MAX_DT)); return end
      update_drifters(math.min(dt, MAX_DT))   -- ambient motion, even on the win card
      update_buttons(math.min(dt, MAX_DT))    -- ease button press/selected states
      update_intro(math.min(dt, MAX_DT))      -- level-intro title card sweep
      if not playing then
        -- won: hold the celebration briefly, then AUTO-ADVANCE to the next level
        -- (no caption, no tap needed; a tap during the hold skips ahead)
        if won then
          local step = math.min(dt, MAX_DT)
          -- confetti keeps popping every ~0.35s while the star show plays
          if math.floor((win_t + step) / 0.35) ~= math.floor(win_t / 0.35) and win_t < 1.6 then
            game.emit("confetti", (math.random() * 2 - 1) * HW * 0.6,
                      (math.random() * 2 - 1) * HH * 0.3, 12)
            game.play_sound("ac_deposit")
          end
          win_t = win_t + step
          if win_t >= 2.8 then win_t = 0; T.clear(); build(HW, HH) end
        end
        return
      end
      dt = math.min(dt, MAX_DT)
      elapsed = elapsed + dt
      star_grade = (elapsed <= par3 and 3) or (elapsed <= par2 and 2) or 1
      if boss_on and elapsed >= par1 and painted > 0 then lose(); return end
      dispatch_cd = math.max(0, dispatch_cd - dt * (speed2 and 2 or 1))
      if dirty then recompute_field() end
      fill_slots()
      for _, a in ipairs(ants) do update_ant(a, dt) end
      for i = 1, SLOTS do if slots[i] and slots[i].n <= 0 then slots[i] = nil end end
      stuck = check_stuck()
      if stuck and not was_stuck then game.play_sound("ac_stuck"); game.haptic("medium") end
      was_stuck = stuck
      refresh_hud(); status()
      if painted <= 0 then win() end
    end,
  }
end

PACKS = PACKS or {}
PACKS.ant_clear = {
  slot = 10, key = "ant_clear", label = "Ant Art", short = "Ant Art",
  icon = "villager", color = { 0.93, 0.55, 0.22 }, tier = "curated", make = make_ant_clear,
}
