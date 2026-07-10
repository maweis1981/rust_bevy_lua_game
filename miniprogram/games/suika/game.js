// game.js — Suika game core: owns the sim (logic.js), the pixel LAYOUT (bin rect
// + danger line + on-screen buttons), tap hit-testing, the drop/aim input, the
// reward-driven actions, best-score persistence, and its OWN full-frame draw.
//
// TWO integration surfaces, one object:
//   * Standalone: main.js calls createGame(platform), setSize, tap, update, draw.
//   * Collection router: createGame(platform) -> { setSize(W,H,topInset), tap,
//     pointer, update(dt,tSec), draw(ctx), view, DEBUG }. draw(ctx) renders the
//     ENTIRE frame itself (delegating to render.js). topInset reserves the top
//     slice of the canvas empty for a router-drawn back button (default 0).
//
// Works in raw CANVAS PIXELS (top-left origin) — no world-coord conversion.
'use strict';

var C = require('./config.js');
var LOGIC = require('./logic.js');
var RENDER = require('./render.js');
var createRenderer = RENDER.createRenderer;

function createGame(platform) {
  var store = platform && platform.storage
    ? platform.storage
    : { get: function () { return null; }, set: function () {} };
  var rewardAd = (platform && platform.rewardAd) || function (cb) { cb(true); };
  function now() { return platform && platform.now ? platform.now() : Date.now(); }
  // wire optional art assets (fruit sheet + background) into the renderer
  if (platform && platform.getImage && RENDER.setImageGetter) RENDER.setImageGetter(platform.getImage);

  var G = {
    W: 0, H: 0, topInset: 0,
    sim: null,
    bin: { x: 0, y: 0, w: 0, h: 0 },
    aimX: 0,
    best: 0,
    lastDrop: -999,          // seconds (sim clock) of the last drop
    clock: 0,                // accumulated seconds
    toast: null,             // { text, until }
    reviveUsed: false,       // once-per-run revive spent?
    doubled: false,          // ×2 already applied on this game-over screen?
    buttons: {},             // game-over overlay buttons (built in relayout)
    flash: 0,                // merge flash 0..1 (decays), for juice
  };

  function loadBest() { var b = store.get('suika_best'); G.best = b ? Number(b) || 0 : 0; }
  function saveBest() {
    if (G.sim && G.sim.state.score > G.best) {
      G.best = G.sim.state.score; store.set('suika_best', String(G.best));
    }
  }

  // --- layout ----------------------------------------------------------------
  function relayout() {
    var W = G.W, H = G.H, inset = G.topInset;
    // usable area sits below the reserved top inset (router back button).
    var top = inset + H * 0.11;                 // HUD band under the inset
    var bottomPad = H * 0.04;
    var binW = Math.min(W * 0.9, (H - top - bottomPad) * 0.62);
    var binH = H - top - bottomPad;
    var binX = (W - binW) / 2;
    var binY = top;
    G.bin = { x: binX, y: binY, w: binW, h: binH };
    if (G.sim) G.sim.setBin(G.bin);
    if (!G.aimX) G.aimX = binX + binW / 2;
    G.aimX = Math.max(binX, Math.min(binX + binW, G.aimX));

    // game-over overlay buttons (three stacked, centered)
    var bw = W * 0.62, bh = H * 0.07, bx = (W - bw) / 2, cy = H * 0.5;
    G.buttons = {
      revive: { x: bx, y: cy, w: bw, h: bh, label: 'REVIVE ▶' },
      dbl: { x: bx, y: cy + bh * 1.25, w: bw, h: bh, label: '×2 SCORE ▶' },
      restart: { x: bx, y: cy + bh * 2.5, w: bw, h: bh, label: 'RESTART' },
    };
  }

  function newRun() {
    var seed = ((now() >>> 0) ^ 0x9e3779b9) >>> 0;
    G.sim = LOGIC.createSim(seed, G.bin);
    G.reviveUsed = false; G.doubled = false; G.flash = 0;
    G.lastDrop = -999;
  }

  function toast(text) { G.toast = { text: text, until: now() + 1300 }; }

  // --- input -----------------------------------------------------------------
  function inRect(px, py, r) { return r && px >= r.x && px <= r.x + r.w && py >= r.y && py <= r.y + r.h; }

  // drag / hover: move the aim column (only meaningful while playing).
  function pointer(px, py, down) {
    if (!G.sim || G.sim.state.over) return;
    G.aimX = Math.max(G.bin.x, Math.min(G.bin.x + G.bin.w, px));
  }

  function tap(px, py) {
    if (!G.sim) return;
    if (G.sim.state.over) {
      if (inRect(px, py, G.buttons.revive)) { doRevive(); return; }
      if (inRect(px, py, G.buttons.dbl)) { doDouble(); return; }
      if (inRect(px, py, G.buttons.restart)) { saveBest(); newRun(); return; }
      return;
    }
    // playing: aim to the tapped column and drop (respecting cooldown)
    G.aimX = Math.max(G.bin.x, Math.min(G.bin.x + G.bin.w, px));
    tryDrop();
  }

  function tryDrop() {
    if (!G.sim || G.sim.state.over) return;
    if (G.clock - G.lastDrop < C.DROP_COOLDOWN) return;
    var f = G.sim.drop(G.aimX);
    if (f) { G.lastDrop = G.clock; }
  }

  // --- reward-driven actions -------------------------------------------------
  function doRevive() {
    if (G.reviveUsed) { toast('revive already used'); return; }
    rewardAd(function (rewarded) {
      if (!rewarded) { toast('ad skipped'); return; }
      G.reviveUsed = true;
      G.sim.revive(C.REVIVE_CLEAR);
      toast('revived! keep going');
    });
  }
  function doDouble() {
    if (G.doubled) { toast('already doubled'); return; }
    rewardAd(function (rewarded) {
      if (!rewarded) { toast('ad skipped'); return; }
      G.doubled = true;
      G.sim.state.score *= 2;
      saveBest();
      toast('score doubled!');
    });
  }

  // --- lifecycle -------------------------------------------------------------
  // setSize(W,H,topInset) — topInset (pixels) reserves the top of the canvas
  // empty for a router-drawn back button. Default 0 for standalone.
  function setSize(W, H, topInset) {
    G.W = W; G.H = H; G.topInset = topInset || 0;
    relayout();
    if (!G.sim) newRun();
  }

  // --- generative particle layer (merge bursts) — the algorithmic-art juice ---
  function spawnBurst(x, y, tier, pop) {
    var binW = G.sim.state.bin.w, r = C.radiusOf(tier, binW), col = C.colorOf(tier);
    var n = pop ? 22 : 14;
    for (var i = 0; i < n; i++) {
      var a = (i / n) * Math.PI * 2 + Math.random() * 0.6;
      var sp = r * (2.2 + Math.random() * 2.8);
      G.parts.push({ x: x, y: y, vx: Math.cos(a) * sp, vy: Math.sin(a) * sp - r * 1.1,
                     life: 0, max: 0.40 + Math.random() * 0.4, r0: r * (0.15 + Math.random() * 0.12), col: col });
    }
  }

  // per-fruit "juice" state (squash/stretch + face) keyed by fruit id, advanced
  // each frame and annotated onto the fruit objects for the renderer.
  function updateJuice(dt) {
    if (!G.juice) G.juice = {};
    var binW = G.sim.state.bin.w, fs = G.sim.state.fruit, seen = {};
    for (var i = 0; i < fs.length; i++) {
      var f = fs[i];
      var st = G.juice[f.id];
      if (!st) st = G.juice[f.id] = { s: 0, v: 0, psp: 0, nextBlink: G.clock + 1 + Math.random() * 4, react: 0 };
      var sp = Math.hypot(f.vx, f.vy);
      var dec = st.psp - sp;                                  // deceleration = impact
      if (dec > binW * 0.8) st.v += Math.min(0.38, dec / (binW * 4));   // squash pop on impact
      var target = -Math.min(0.16, Math.max(0, f.vy) / (binW * 4) * 0.35); // stretch while falling
      st.v += (target - st.s) * 55 * dt;                     // spring
      st.v *= Math.pow(0.02, dt);                            // damping
      st.s = Math.max(-0.22, Math.min(0.40, st.s + st.v * dt));
      st.psp = sp;
      // blink schedule
      var blinking = (G.clock >= st.nextBlink && G.clock < st.nextBlink + 0.12);
      if (G.clock >= st.nextBlink + 0.12) st.nextBlink = G.clock + 2 + Math.random() * 4;
      st.react = Math.max(0, st.react - dt * 2.2);
      // annotate for the renderer
      f.sq = st.s;
      f.blink = blinking ? 1 : 0;
      f.lookx = Math.max(-1, Math.min(1, f.vx / (binW * 1.6)));
      f.looky = Math.max(-1, Math.min(1, f.vy / (binW * 1.6)));
      f.react = st.react;
      seen[f.id] = 1;
    }
    for (var key in G.juice) if (!seen[key]) delete G.juice[key];
  }
  function pokeReact(x, y, tier) {                            // merged fruit reacts (happy pop)
    var fs = G.sim.state.fruit, best = null, bd = 1e18;
    for (var i = 0; i < fs.length; i++) {
      var f = fs[i]; if (f.tier !== tier) continue;
      var d = (f.x - x) * (f.x - x) + (f.y - y) * (f.y - y);
      if (d < bd) { bd = d; best = f; }
    }
    if (best) { var st = G.juice[best.id]; if (st) { st.react = 1; st.v += 0.45; } }
  }

  function update(dt, tSec) {
    if (!G.sim) return;
    if (!(dt > 0) || dt > 0.1) dt = dt > 0 ? 0.1 : 0; // clamp big hitches
    G.clock += dt;
    var ev = G.sim.step(dt);
    if (ev.merges || ev.pops) G.flash = Math.min(1, G.flash + 0.5 * (ev.merges + ev.pops));
    G.flash *= 0.9;
    if (!G.parts) G.parts = [];
    updateJuice(dt);
    var evs = G.sim.state.mergeEvents;
    if (evs && evs.length) { for (var k = 0; k < evs.length; k++) { spawnBurst(evs[k].x, evs[k].y, evs[k].tier, evs[k].pop); pokeReact(evs[k].x, evs[k].y, evs[k].tier); } evs.length = 0; }
    var grav = G.sim.state.bin.w * 2.2;
    for (var pi = G.parts.length - 1; pi >= 0; pi--) {
      var p = G.parts[pi]; p.life += dt;
      if (p.life >= p.max) { G.parts.splice(pi, 1); continue; }
      p.vy += grav * dt; p.vx *= 0.985; p.x += p.vx * dt; p.y += p.vy * dt;
    }
    var wasOver = G._over;
    if (G.sim.state.over && !wasOver) { saveBest(); }
    G._over = G.sim.state.over;
    if (G.toast && now() > G.toast.until) G.toast = null;
  }

  function view() {
    return {
      W: G.W, H: G.H, topInset: G.topInset,
      bin: G.bin, sim: G.sim, aimX: G.aimX,
      best: G.best, buttons: G.buttons, toast: G.toast,
      flash: G.flash, dangerY: G.sim ? G.sim.dangerY() : 0, parts: G.parts || [],
      reviveUsed: G.reviveUsed, doubled: G.doubled,
      config: C,
    };
  }

  // draw(ctx) — renders the ENTIRE frame. Renderer is cached & rebound if the
  // ctx changes (router may hand us a different context).
  var _renderer = null, _ctx = null;
  function draw(ctx) {
    if (!ctx) return;
    if (_ctx !== ctx) { _ctx = ctx; _renderer = createRenderer(ctx); }
    _renderer.draw(this);
  }

  loadBest();

  return {
    setSize: setSize,
    tap: tap,
    pointer: pointer,
    setPointer: pointer,     // alias to match the watersort/shell surface
    update: update,
    draw: draw,
    view: view,
    // DEBUG surface for headless tests / autoplay
    DEBUG: {
      sim: function () { return G.sim; },
      state: function () { return G.sim.state; },
      drop: function (x) { G.aimX = x; return G.sim.drop(x); },
      forceDrop: function (x) { return G.sim.drop(x); },
      bin: function () { return G.bin; },
      newRun: newRun,
    },
  };
}

module.exports = { createGame: createGame };
