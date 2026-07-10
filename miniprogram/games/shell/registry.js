// registry.js — adapts each game's native module shape to the router's uniform
// instance contract { setSize(W,H), tap(px,py), pointer(px,py,down),
// update(dt,tSec), draw(ctx) }. Games are loaded as isolated modules on
// window.__games[<id>] by the shell bundle (build.sh), each exposing whatever
// its own files export. Missing games are skipped, so the collection grows by
// just adding a game to the bundle + an entry here.
'use strict';

function games() { return (typeof window !== 'undefined' && window.__games) || {}; }

// --- Water Sort: pixel coords + tap; draws via its createRenderer(ctx,W,H) ---
function wsEntry(mod) {
  return {
    id: 'watersort', title: 'WATER SORT', subtitle: 'sort the colors', color: '#2ea3f2',
    create: function (platform) {
      var g = mod.game.createGame(platform), r = null, W = 0, H = 0;
      return {
        setSize: function (w, h) { W = w; H = h; g.setSize(w, h); r = null; },
        tap: function (px, py) { g.tap(px, py); },
        pointer: function () {},
        update: function () { g.update(); },
        draw: function (ctx) { if (!r) r = mod.render.createRenderer(ctx, W, H); r.draw(g); },
      };
    },
  };
}

// --- Time Dodge: the shared/ engine. World coords (centre origin, +y up),
//     hold-to-flow pointer, its own sub-menu; renderer takes a time arg. -------
function tdEntry(mod) {
  return {
    id: 'timedodge', title: 'TIME DODGE', subtitle: 'hold time · dodge', color: '#e6394a',
    create: function (platform) {
      var g = mod.game.createGame(platform), r = null, W = 0, H = 0, SW = 0, SH = 0, tSec = 0;
      function toWorld(px, py) { return { x: px - SW, y: SH - py }; }
      return {
        setSize: function (w, h) { W = w; H = h; SW = w / 2; SH = h / 2; g.setSize(SW, SH); r = null; },
        tap: function (px, py) { var wld = toWorld(px, py); g.setPointer(wld.x, wld.y, true); g.tap(wld.x, wld.y); },
        pointer: function (px, py, down) {
          if (down) { var wld = toWorld(px, py); g.setPointer(wld.x, wld.y, true); }
          else g.setPointer(null, null, false);
        },
        update: function (dt, t) { tSec = t; g.update(dt); },
        draw: function (ctx) { if (!r) r = mod.render.createRenderer(ctx, W, H); r.draw(g, tSec); },
      };
    },
  };
}

// --- Suika: exposes its own createGame with draw(ctx). Optional (may not be
//     bundled yet). setSize(W,H,topInset) — router already reserves the bar. ---
function suikaEntry(mod) {
  return {
    id: 'suika', title: 'SUIKA', subtitle: 'drop & merge', color: '#37c871',
    create: function (platform) {
      var g = mod.game.createGame(platform);
      return {
        setSize: function (w, h) { g.setSize(w, h, 0); },
        tap: function (px, py) { if (g.tap) g.tap(px, py); },
        pointer: function (px, py, down) { if (g.pointer) g.pointer(px, py, down); },
        update: function (dt, t) { g.update(dt, t); },
        draw: function (ctx) { g.draw(ctx); },
      };
    },
  };
}

function buildRegistry() {
  var G = games(), reg = [];
  if (G.suika && G.suika.game) reg.push(suikaEntry(G.suika));
  if (G.watersort && G.watersort.game) reg.push(wsEntry(G.watersort));
  if (G.timedodge && G.timedodge.game) reg.push(tdEntry(G.timedodge));
  return reg;
}

module.exports = { buildRegistry: buildRegistry };
