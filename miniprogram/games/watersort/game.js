// game.js — Water Sort game core: owns the level (logic.js), the pixel LAYOUT
// (tube rects + button rects), tap hit-testing, the reward-driven actions, and
// a light pour animation. Platform-agnostic; the renderer reads `.view()`.
//
// Contract (mirrors the shell's game core so it can later drop into the
// collection router): createGame(platform) -> { setSize, setPointer, tap,
// update, view, DEBUG }. NOTE: unlike the Time Dodge shell (world coords,
// centre origin), this tap game works in raw CANVAS PIXELS — its standalone
// main.js passes pixels straight through.
'use strict';

var C = require('./config.js');
var LOGIC = require('./logic.js');
var RENDER = require('./render.js');

function createGame(platform) {
  var store = platform && platform.storage
    ? platform.storage
    : { get: function () { return null; }, set: function () {} };
  var rewardAd = (platform && platform.rewardAd) || function (cb) { cb(true); };
  if (platform && platform.getImage && RENDER.setImageGetter) RENDER.setImageGetter(platform.getImage);

  var G = {
    W: 0, H: 0, level: 1, lv: null,
    layout: { tubes: [], buttons: {} },
    selected: -1,
    anim: null,              // { from, to, col, units, t0, ms }
    toast: null,             // { text, until }
    banner: null,            // 'win'
    stats: { wins: 0 },
  };

  function loadProgress() {
    var lvl = store.get('ws_level');
    G.level = lvl ? Math.max(1, Number(lvl)) : 1;
    var w = store.get('ws_wins');
    G.stats.wins = w ? Number(w) : 0;
  }
  function saveProgress() {
    store.set('ws_level', String(G.level));
    store.set('ws_wins', String(G.stats.wins));
  }

  function newLevel(level) {
    var opts = C.levelOpts(level);
    // deterministic per level: seed folds the level index so it reproduces.
    var seed = (level * 2654435761) >>> 0;
    G.lv = LOGIC.createLevel(seed, opts);
    G.selected = -1; G.anim = null; G.banner = null;
    relayout();
  }

  // --- layout: tube grid + a bottom button row --------------------------------
  function relayout() {
    if (!G.lv) return;
    var tubes = G.lv.state.tubes, n = tubes.length, cap = G.lv.state.cap;
    var W = G.W, H = G.H;
    var topPad = H * 0.16, botBar = H * 0.13;
    var areaH = H - topPad - botBar;
    // choose rows so tubes fit; up to 5 per row
    var perRow = Math.min(5, Math.max(3, Math.ceil(n / 2)));
    var rows = Math.ceil(n / perRow);
    var cellW = W / perRow, cellH = areaH / rows;
    var tubeW = Math.min(cellW * 0.6, cellH * 0.42);
    var tubeH = Math.min(cellH * 0.82, tubeW * cap * 0.9 + tubeW * 0.4);
    var rects = [];
    for (var i = 0; i < n; i++) {
      var r = Math.floor(i / perRow), c = i % perRow;
      var countThisRow = (r === rows - 1) ? (n - perRow * (rows - 1)) : perRow;
      var rowW = countThisRow * cellW;
      var x0 = (W - rowW) / 2 + c * cellW + (cellW - tubeW) / 2;
      var y0 = topPad + r * cellH + (cellH - tubeH) / 2;
      rects.push({ x: x0, y: y0, w: tubeW, h: tubeH });
    }
    G.layout.tubes = rects;
    // buttons: UNDO | HINT | +TUBE across the bottom bar
    var by = H - botBar + botBar * 0.15, bh = botBar * 0.6;
    var bw = W * 0.27, gap = (W - bw * 3) / 4;
    G.layout.buttons = {
      undo: { x: gap, y: by, w: bw, h: bh, label: 'UNDO' },
      hint: { x: gap * 2 + bw, y: by, w: bw, h: bh, label: 'HINT ▶' },
      tube: { x: gap * 3 + bw * 2, y: by, w: bw, h: bh, label: '+TUBE ▶' },
    };
  }

  function toast(text) { G.toast = { text: text, until: (platform.now ? platform.now() : Date.now()) + 1400 }; }

  // --- input ------------------------------------------------------------------
  function hitTube(px, py) {
    var rs = G.layout.tubes;
    for (var i = 0; i < rs.length; i++) {
      var r = rs[i];
      // generous hit box
      if (px >= r.x - r.w * 0.2 && px <= r.x + r.w * 1.2 &&
          py >= r.y - r.h * 0.1 && py <= r.y + r.h * 1.1) return i;
    }
    return -1;
  }
  function inRect(px, py, r) { return px >= r.x && px <= r.x + r.w && py >= r.y && py <= r.y + r.h; }

  function beginPourAnim(from, to) {
    var st = G.lv.state;
    var units = LOGIC.pourCount(st.tubes, from, to, st.cap);
    var col = LOGIC.topColor(st.tubes[from]);
    G.anim = { from: from, to: to, col: col, units: units, t0: (platform.now ? platform.now() : Date.now()), ms: C.POUR_MS };
  }

  function tap(px, py) {
    if (G.banner === 'win') { // tap anywhere advances to next level
      G.level++; G.stats.wins++; saveProgress(); newLevel(G.level); return;
    }
    var B = G.layout.buttons;
    if (inRect(px, py, B.undo)) { doUndo(); return; }
    if (inRect(px, py, B.hint)) { doHint(); return; }
    if (inRect(px, py, B.tube)) { doAddTube(); return; }
    if (G.anim) return; // ignore taps mid-pour

    var i = hitTube(px, py);
    if (i < 0) { G.lv.state.selected = -1; return; }
    var st = G.lv.state;
    var wasSel = st.selected;
    // committing pour? animate first, commit the state when the pour lands.
    if (wasSel !== -1 && wasSel !== i && LOGIC.canPour(st.tubes, wasSel, i, st.cap)) {
      beginPourAnim(wasSel, i);
      G.pending = { from: wasSel, to: i };
      st.selected = -1;          // source is "pouring", no longer selected
      return;
    }
    G.lv.select(i);
  }

  // --- reward-driven actions --------------------------------------------------
  function doUndo() {                       // free undo (limited feel, no ad)
    if (G.lv.undo()) toast('undo'); else toast('nothing to undo');
  }
  function doHint() {                       // rewarded: show next best move
    rewardAd(function (rewarded) {
      if (!rewarded) { toast('ad skipped'); return; }
      var mv = G.lv.hint();
      if (!mv) { toast('no move'); return; }
      G.hintMove = mv; G.hintUntil = (platform.now ? platform.now() : Date.now()) + 2200;
      toast('hint: ' + (mv[0] + 1) + ' → ' + (mv[1] + 1));
    });
  }
  function doAddTube() {                    // rewarded: +1 empty spare tube
    rewardAd(function (rewarded) {
      if (!rewarded) { toast('ad skipped'); return; }
      G.lv.addTube(); relayout(); toast('+1 tube');
    });
  }

  // --- splash particles when a pour lands (algorithmic-art juice) ------------
  function spawnSplash(tubeIdx, colorId) {
    if (!G.parts) G.parts = [];
    var r = G.layout.tubes[tubeIdx]; if (!r) return;
    var col = C.PALETTE[colorId % C.PALETTE.length];
    var cx = r.x + r.w / 2, cy = r.y + r.h * 0.14, spread = r.w * 0.5;
    for (var i = 0; i < 12; i++) {
      var a = -Math.PI / 2 + (Math.random() - 0.5) * 2.2;
      var sp = r.w * (1.6 + Math.random() * 2.2);
      G.parts.push({ x: cx + (Math.random() - 0.5) * spread, y: cy,
                     vx: Math.cos(a) * sp, vy: Math.sin(a) * sp,
                     life: 0, max: 0.32 + Math.random() * 0.3, r0: r.w * (0.06 + Math.random() * 0.06), col: col });
    }
  }
  function stepParts(dt) {
    if (!G.parts || !G.parts.length) return;
    var grav = G.H * 1.6;
    for (var i = G.parts.length - 1; i >= 0; i--) {
      var p = G.parts[i]; p.life += dt;
      if (p.life >= p.max) { G.parts.splice(i, 1); continue; }
      p.vy += grav * dt; p.x += p.vx * dt; p.y += p.vy * dt;
    }
  }

  // --- lifecycle --------------------------------------------------------------
  function setSize(w, h) { G.W = w; G.H = h; relayout(); }
  function setPointer() {}                  // tap game: no drag state needed
  function update() {
    var t = (platform.now ? platform.now() : Date.now());
    var dt = G._lastT ? Math.min(0.05, Math.max(0, (t - G._lastT) / 1000)) : 0;
    G._lastT = t;
    if (G.anim && t - G.anim.t0 >= G.anim.ms) {
      var acol = G.anim.col, ato = G.anim.to;
      G.anim = null;
      if (G.pending) {                      // commit the animated pour now
        var p = G.pending; G.pending = null;
        G.lv.select(p.from);                // pick source (still legal — input was blocked)
        var ev = G.lv.select(p.to);         // pour
        if (ev === 'win') G.banner = 'win';
        spawnSplash(ato, acol);
        if (platform.playSound) platform.playSound('pour.wav', 0.55);
      }
    }
    stepParts(dt);
    if (G.toast && t > G.toast.until) G.toast = null;
    if (G.hintMove && t > G.hintUntil) { G.hintMove = null; }
  }

  function view() {
    var t = (platform.now ? platform.now() : Date.now());
    var anim = null;
    if (G.anim) {
      anim = { from: G.anim.from, to: G.anim.to, col: G.anim.col, units: G.anim.units,
               p: Math.max(0, Math.min(1, (t - G.anim.t0) / G.anim.ms)) };
    }
    return {
      W: G.W, H: G.H, level: G.level, wins: G.stats.wins, parts: G.parts || [],
      lv: G.lv, layout: G.layout, anim: anim, toast: G.toast,
      banner: G.banner, hintMove: G.hintMove || null,
      palette: C.PALETTE,
    };
  }

  loadProgress();
  newLevel(G.level);

  return {
    setSize: setSize, setPointer: setPointer, tap: tap, update: update, view: view,
    // DEBUG surface for headless tests / autoplay
    DEBUG: {
      state: function () { return G.lv.state; },
      solve: function () { return G.lv.solve(); },
      select: function (i) { return G.lv.select(i); },
      level: function () { return G.level; },
      forceLayout: relayout,
    },
  };
}

module.exports = { createGame: createGame };
