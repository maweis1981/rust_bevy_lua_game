// game.js — TIME DODGE core state machine, ported from
// assets/scripts/packs/timedodge.lua. Platform-agnostic and render-agnostic:
// it owns ALL game state and mechanics, mutates on update(dt)/tap(x,y), and
// exposes read accessors the renderer and the Node test harness both read.
//
// Coordinates: origin at screen centre, +y UP, SW/SH are HALF-extents. The
// renderer converts to canvas pixels; the logic stays in world space so it is
// byte-for-byte the same maths as the Bevy/Lua source.
//
// `platform` is injected (see wechat/adapter.js, douyin/adapter.js, test/run.js)
// and provides:
//   storage.get(key) -> string|null,  storage.set(key, string)
//   rewardAd(cb)   -> show a rewarded video ad; cb(rewarded:boolean). This is the
//                     mini-game replacement for the Lua game.open_url sponsor link
//                     (mini-games CANNOT open arbitrary external URLs — see
//                     RESEARCH.md). rewarded===true  => sponsor absorbed the hit.
//   sound/haptic/shake/zoom/emit/track  -> optional juice hooks, no-op if absent.
'use strict';

var C = require('./config.js');
var newLcg = require('./rng.js').newLcg;
var clamp = C.clamp;

function dist(ax, ay, bx, by) {
  var dx = ax - bx, dy = ay - by;
  return Math.sqrt(dx * dx + dy * dy);
}
function inRect(r, x, y) {
  return r && Math.abs(x - r.x) <= r.w * 0.5 && Math.abs(y - r.y) <= r.h * 0.5;
}

function createGame(platform) {
  platform = platform || {};
  var store = platform.storage || { get: function () { return null; }, set: function () {} };

  // optional juice — routed to the platform if present, else no-ops.
  function snd(n) { if (platform.sound) platform.sound(n); }
  function hap(s) { if (platform.haptic) platform.haptic(s); }
  function shake(a) { if (platform.shake) platform.shake(a); }
  function zoom(a) { if (platform.zoom) platform.zoom(a); }
  function emit(p, x, y) { if (platform.emit) platform.emit(p, x, y); }
  function track(e, v) { if (platform.track) platform.track(e, v); }

  // ---- persistence (maps game.save/load -> platform storage) --------------
  function save(key, val) { store.set(key, String(val)); }
  function loadNum(key) { var v = store.get(key); return (v === null || v === undefined) ? null : Number(v); }

  var G = {
    mode: 'select',      // 'select' | 'levels' | 'run'
    SW: 200, SH: 356,
    S: null,             // the live run
    // menu hit-rects (also consumed by the renderer)
    btn: { endless: null, trials: null, absorb: null, back: null, levels: [] },
    input: { x: null, y: null, down: false },
    keys: {},
  };

  function rnd() { return (G.S && G.S.rng) ? G.S.rng() : Math.random(); }

  function starsOf(i) { return loadNum('td_lv' + i + '_stars') || 0; }
  function unlocked(i) { return i === 1 || starsOf(i - 1) > 0; }
  // aggregate persisted records for the menu (never shown before).
  function bests() {
    var total = 0;
    for (var i = 1; i <= C.LEVELS.length; i++) total += starsOf(i);
    return {
      endless: loadNum('timedodge_best') || 0,
      absorb: loadNum('td_absorb_best') || 0,
      stars: total,
      maxStars: C.LEVELS.length * 3,
    };
  }

  // ---- screens -------------------------------------------------------------
  function buildSelect() {
    G.mode = 'select';
    G.S = null;
    G.btn.endless = { x: 0, y: 10, w: 300, h: 86 };
    G.btn.trials = { x: 0, y: -110, w: 300, h: 86 };
    G.btn.absorb = { x: 0, y: -230, w: 300, h: 86 };
    G.btn.back = null;  // select IS the root of the standalone port
    G.btn.levels = [];
  }

  function buildLevels() {
    G.mode = 'levels';
    G.S = null;
    G.btn.endless = G.btn.trials = G.btn.absorb = null;
    G.btn.levels = [];
    var cols = 5, tw = 64, th = 76, gap = 12;
    for (var i = 1; i <= C.LEVELS.length; i++) {
      var col = (i - 1) % cols, row = Math.floor((i - 1) / cols);
      var x = -(cols - 1) * (tw + gap) * 0.5 + col * (tw + gap);
      var y = 140 - row * (th + gap + 14);
      G.btn.levels[i - 1] = { x: x, y: y, w: tw, h: th, i: i };
    }
    G.btn.back = { x: -G.SW + 46, y: G.SH - 34, w: 78, h: 48 };
  }

  function toSelect() { buildSelect(); }
  function toLevels() { buildLevels(); }

  // ---- the run -------------------------------------------------------------
  function placeGate() {
    // Farthest-point sampling of 24 candidates: keep the one farthest from both
    // the player and the previous gate — every gate is a cross-screen run.
    var S = G.S, best = null, bestscore = -1;
    for (var k = 0; k < 24; k++) {
      var x = (rnd() * 2 - 1) * (G.SW - 70);
      var y = -G.SH + 130 + rnd() * (2 * G.SH - 300);
      var dp = dist(x, y, S.px, S.py);
      var dg = S.gate ? dist(x, y, S.gate.x, S.gate.y) : dp;
      var score = Math.min(dp, dg);
      if (score > bestscore) { bestscore = score; best = { x: x, y: y }; }
    }
    S.gate = best;
  }

  function clearFoes() { if (G.S) G.S.bullets = []; }

  function closeHitDialog() {
    var S = G.S;
    if (!(S && S.hit_dialog)) return;
    S.hit_dialog = null;
    S.drag = null; // re-anchor: the finger may have moved while paused
  }
  function openHitDialog(rockSize) {
    var S = G.S;
    S.hit_dialog = {
      rock_size: rockSize,
      yes: { x: -85, y: -35, w: 140, h: 66 },
      no: { x: 85, y: -35, w: 140, h: 66 },
    };
    snd('wall'); hap('heavy'); shake(0.3);
  }

  function playerSize() { /* renderer reads S.mass directly */ }

  function startRun(lv, absorb) {
    closeHitDialog();
    var S = {
      trial: lv || null, absorb: !!absorb, px: 0, py: 0, prot: 0, ts: C.TS_MIN,
      score: 0, elapsed: 0, playing: true, done: false, bullets: [],
      gate: null, gate_i: 0, spawn_t: lv ? -1.0 : -0.5, mark: 10,
      next_unlock: 1, ann: '', ann_t: 0,
      volley_due: lv ? C.LEVELS[lv - 1].volley : 0,
      mass: C.PLAYER, peak: C.PLAYER, eaten: 0,
      hit_dialog: null, dialog_used: false,
      drag: null, trail: [], card: null, cardTitle: '', cardSub: '',
    };
    if (lv) S.rng = newLcg(C.LEVELS[lv - 1].seed);
    for (var i = 0; i < C.TRAIL_N; i++) S.trail.push({ x: 0, y: 0, a: 0 });
    G.S = S;
    G.mode = 'run';
    G.btn.back = null; // no Home button during a run; the end-card owns nav
    if (lv) placeGate();
  }

  function die() {
    var S = G.S;
    S.playing = false;
    clearFoes();
    snd('hit'); hap('heavy'); shake(0.7); zoom(0.8); emit('shatter', S.px, S.py);
    var retry = { label: 'RETRY', act: 'retry', primary: true };
    var modes = { label: 'MODES', act: 'modes' };
    if (S.absorb) {
      var best = loadNum('td_absorb_best') || 0;
      if (S.peak > best) { best = S.peak; save('td_absorb_best', best); S.newBest = true; }
      card('YOU FADED AWAY',
        'PEAK ' + Math.floor(S.peak) + '   EATEN ' + S.eaten + '   BEST ' + Math.floor(best),
        [retry, modes]);
    } else if (S.trial) {
      card('CAUGHT BY THE FREEZE',
        'MOMENT ' + S.trial + '   GATE ' + S.gate_i + '/' + C.LEVELS[S.trial - 1].gates,
        [retry, { label: 'LEVELS', act: 'levels' }]);
    } else {
      var b2 = loadNum('timedodge_best') || 0;
      if (S.score > b2) { b2 = S.score; save('timedodge_best', b2); S.newBest = true; }
      card('TIME RECLAIMED YOU',
        'STOLEN ' + S.score.toFixed(1) + 's   BEST ' + b2.toFixed(1) + 's', [retry, modes]);
    }
    track('lose');
  }

  // The normal big-rock penalty (ABSORB): chip 25% off; below MIN_MASS the run
  // ends. Shared by the in-loop hit path and the dialog's NO button.
  function applyChip() {
    var S = G.S;
    S.mass = S.mass * C.CHIP;
    snd('wall'); hap('heavy'); shake(0.5); zoom(0.5);
    if (S.mass < C.MIN_MASS) { die(); return; }
    playerSize();
  }

  function finishTrial() {
    var S = G.S;
    S.playing = false; S.done = true;
    clearFoes();
    var lv = C.LEVELS[S.trial - 1], i = S.trial;
    var stars = (S.elapsed <= lv.s3) ? 3 : (S.elapsed <= lv.s2 ? 2 : 1);
    if (stars > starsOf(i)) save('td_lv' + i + '_stars', stars);
    var best = loadNum('td_lv' + i + '_best');
    if (best === null || S.elapsed < best) { save('td_lv' + i + '_best', S.elapsed); S.newBest = true; }
    card('MOMENT SEALED',
      'TIME ' + S.elapsed.toFixed(1) + 's      ' + (stars >= 1 ? '*'.repeat(stars) : '-'),
      [{ label: 'LEVELS', act: 'levels', primary: true }, { label: 'REPLAY', act: 'retry' }]);
    snd('score'); hap('success'); shake(0.5); emit('confetti', S.px, S.py);
    track('clear');
  }

  function card(title, sub, btns) {
    var S = G.S;
    S.cardTitle = title; S.cardSub = sub;
    var n = btns.length, bw = 150, gap = 14;
    var x0 = -(n - 1) * (bw + gap) * 0.5;
    S.card = [];
    for (var i = 0; i < n; i++) {
      var x = x0 + i * (bw + gap);
      S.card.push({ rect: { x: x, y: -52, w: bw, h: 54 }, act: btns[i].act,
        label: btns[i].label, primary: !!btns[i].primary });
    }
  }

  function foeSpeed() {
    var S = G.S;
    if (S.trial) return C.LEVELS[S.trial - 1].speed;
    return Math.min(C.SPEED0 + S.score * C.SPEED_PER_S, C.SPEED_MAX);
  }
  function spawnGap() {
    var S = G.S;
    if (S.absorb) return 0.5;
    if (S.trial) return C.LEVELS[S.trial - 1].every;
    return Math.max(C.SPAWN_MIN, C.SPAWN0 - S.score * C.SPAWN_PER_S);
  }
  function pickKind() {
    var S = G.S;
    if (S.trial) {
      var ks = C.LEVELS[S.trial - 1].kinds;
      return ks[Math.floor(rnd() * ks.length)];
    }
    var kinds = [], w = [];
    for (var j = 0; j < C.UNLOCKS.length; j++) {
      var u = C.UNLOCKS[j];
      if (S.score >= u.t) { kinds.push(u.k); w.push(u.k === 'dart' ? 3 : 1); }
    }
    var total = 0; for (var m = 0; m < w.length; m++) total += w[m];
    var r = rnd() * total;
    for (var n = 0; n < w.length; n++) { r -= w[n]; if (r <= 0) return kinds[n]; }
    return 'dart';
  }

  function spawnFoe(kind, x, y, vx, vy, z, size) {
    var S = G.S;
    if (S.bullets.length >= C.MAX_FOES) return;
    size = size || C.FOE;
    S.bullets.push({ kind: kind, x: x, y: y, vx: vx, vy: vy, age: 0, near: false,
      z: (z === undefined ? 1 : z), rot: rnd() * 6.28, spin: (rnd() * 2 - 1) * 3.5,
      size: size, gone: false });
  }
  function spawnEdge() {
    var S = G.S;
    var kind = pickKind();
    var side = Math.floor(rnd() * 4) + 1, x = 0, y = 0;
    if (side === 1) { x = -G.SW - C.FOE; y = (rnd() * 2 - 1) * G.SH; }
    else if (side === 2) { x = G.SW + C.FOE; y = (rnd() * 2 - 1) * G.SH; }
    else if (side === 3) { x = (rnd() * 2 - 1) * G.SW; y = G.SH + C.FOE; }
    else { x = (rnd() * 2 - 1) * G.SW; y = -G.SH - C.FOE; }
    if (S.absorb) {
      var lo = clamp(S.mass * 0.40, 10, 80);
      var hi = clamp(S.mass * Math.min(1.1 + 0.06 * S.eaten, 1.7), 24, 160);
      var size = lo + rnd() * (hi - lo);
      var a = Math.atan2(S.py - y, S.px - x) + (rnd() * 1.2 - 0.6);
      var sp = 140 + rnd() * 120;
      spawnFoe('dart', x, y, sp * Math.cos(a), sp * Math.sin(a), 1, size);
      return;
    }
    var a2 = Math.atan2(S.py - y, S.px - x) + (rnd() * 0.5 - 0.25);
    var s = kind === 'drifter' ? C.DRIFT_SPEED : foeSpeed();
    spawnFoe(kind, x, y, s * Math.cos(a2), s * Math.sin(a2));
  }

  function updateRun(dt) {
    var S = G.S;
    if (S.hit_dialog) return;   // sponsor dialog up: the world is halted solid
    if (!S.playing) return;
    S.elapsed += dt;            // trials: REAL clock, freeze included

    var ox = S.px, oy = S.py;
    var p = G.input;
    if (p.down && p.x !== null) {
      if (S.drag) {
        S.px += (p.x - S.drag.x) * C.DRAG_SENS;
        S.py += (p.y - S.drag.y) * C.DRAG_SENS;
      }
      S.drag = { x: p.x, y: p.y };
    } else {
      S.drag = null;
    }
    var dx = 0, dy = 0;
    if (G.keys.left || G.keys.a) dx -= 1;
    if (G.keys.right || G.keys.d) dx += 1;
    if (G.keys.up || G.keys.w) dy += 1;
    if (G.keys.down || G.keys.s) dy -= 1;
    if (dx !== 0 || dy !== 0) { S.px += dx * C.KEY_SPEED * dt; S.py += dy * C.KEY_SPEED * dt; }
    var mvx = S.px - ox, mvy = S.py - oy;
    var mv = Math.sqrt(mvx * mvx + mvy * mvy);
    if (mv > C.PLAYER_MAX * dt) {
      S.px = ox + mvx / mv * C.PLAYER_MAX * dt;
      S.py = oy + mvy / mv * C.PLAYER_MAX * dt;
    }
    S.px = clamp(S.px, -G.SW + C.PLAYER * 0.5, G.SW - C.PLAYER * 0.5);
    S.py = clamp(S.py, -G.SH + C.PLAYER * 0.5, G.SH - C.PLAYER * 0.5);

    // THE mechanic: time flows while you TOUCH; release freezes the world.
    var pspeed = dist(S.px, S.py, ox, oy) / dt;
    var touching = p.down || dx !== 0 || dy !== 0;
    var target = touching ? 1 : C.TS_MIN;
    S.ts = S.ts + (target - S.ts) * Math.min(1, dt * C.TS_SMOOTH);
    var wdt = dt * S.ts;

    if (!S.trial && !S.absorb) {
      S.score += wdt;
      if (S.score >= S.mark) {
        S.mark += 10;
        snd('score'); hap('success'); shake(0.35);
      }
      var u = C.UNLOCKS[S.next_unlock];
      if (u && S.score >= u.t) {
        S.next_unlock += 1;
        S.ann = 'A NEW HUNTER WAKES: ' + u.k.toUpperCase(); S.ann_t = 2.5;
        snd('wall'); shake(0.2);
      }
      if (S.ann_t > 0) S.ann_t -= dt;
    }

    if (S.volley_due > 0) {
      for (var v = 0; v < S.volley_due; v++) spawnEdge();
      S.volley_due = 0;
    }
    S.spawn_t += wdt;
    if (S.spawn_t >= spawnGap()) { S.spawn_t = 0; spawnEdge(); }

    if (S.trial && S.gate) {
      if (dist(S.gate.x, S.gate.y, S.px, S.py) < (C.GATE + C.PLAYER) * 0.5) {
        S.gate_i += 1;
        snd('score'); hap('light'); shake(0.25); emit('spark', S.gate.x, S.gate.y);
        if (S.gate_i >= C.LEVELS[S.trial - 1].gates) { finishTrial(); return; }
        placeGate();
      }
    }

    // Advance foes. Each kind = one motion signature; drifter ignores the freeze.
    var spawned = [], kept = [];
    for (var bi = 0; bi < S.bullets.length; bi++) {
      var b = S.bullets[bi];
      var kd = C.KINDS[b.kind];
      var bdt = kd.real ? dt : wdt;
      if (kd.accel) {
        var cur0 = Math.max(1, Math.sqrt(b.vx * b.vx + b.vy * b.vy));
        var mm = Math.min(1 + kd.accel * bdt, C.SPEED_MAX / cur0);
        b.vx *= mm; b.vy *= mm;
      }
      if (kd.turn || kd.real) {
        var want = Math.atan2(S.py - b.y, S.px - b.x);
        var cur = Math.atan2(b.vy, b.vx);
        var diff = ((want - cur + Math.PI) % (2 * Math.PI)) - Math.PI;
        var rate = kd.real ? 3.0 : kd.turn;
        cur = cur + clamp(diff, -rate * bdt, rate * bdt);
        var sp = Math.sqrt(b.vx * b.vx + b.vy * b.vy);
        b.vx = sp * Math.cos(cur); b.vy = sp * Math.sin(cur);
      }
      b.age += bdt;
      var split = kd.split_at && b.age >= kd.split_at;
      b.z = Math.max(0, b.z - C.Z_RATE * bdt);
      var depth = 1 - b.z;
      var drift = 0.5 + 0.5 * depth;
      b.x += b.vx * bdt * drift; b.y += b.vy * bdt * drift;
      b.rot += b.spin * bdt;
      var sc = b.size * (0.30 + 0.70 * depth * depth);
      b.sc = sc; // cache apparent size for the renderer

      var d = dist(b.x, b.y, S.px, S.py);
      var consumed = false;
      if (S.absorb) {
        if (b.z <= C.PLANE_Z && d < (S.mass + sc) * 0.45 && !S.hit_dialog) {
          consumed = true;
          emit('spark', b.x, b.y);
          if (b.size <= S.mass) {
            S.mass = Math.min(C.MAX_MASS, Math.sqrt(S.mass * S.mass + C.EAT_GAIN * b.size * b.size));
            S.eaten += 1;
            if (S.mass > S.peak) S.peak = S.mass;
            snd('hit'); hap('light'); shake(0.10);
          } else if (!S.dialog_used) {
            S.dialog_used = true;
            openHitDialog(b.size); // FIRST big hit: sponsor cancel offer
          } else {
            applyChip();
            if (!S.playing) return; // chipped below MIN_MASS: dead
          }
          playerSize();
        }
      } else if (b.z <= C.PLANE_Z) {
        if (d < C.HIT_R) { die(); return; }
        if (d < C.NEAR && !b.near) {
          b.near = true;
          snd('wall'); hap('light'); shake(0.06); zoom(0.25);
        }
      }
      if (consumed) b.gone = true;

      if (b.gone) {
        // dropped (eaten / shattered)
      } else if (split) {
        var sp2 = Math.sqrt(b.vx * b.vx + b.vy * b.vy);
        var base = Math.atan2(b.vy, b.vx);
        var offs = [-0.55, 0, 0.55];
        for (var oi = 0; oi < offs.length; oi++) {
          spawned.push(['dart', b.x, b.y, sp2 * Math.cos(base + offs[oi]), sp2 * Math.sin(base + offs[oi]), b.z]);
        }
      } else if (Math.abs(b.x) > G.SW + C.OFF || Math.abs(b.y) > G.SH + C.OFF) {
        // off-screen: drop
      } else {
        kept.push(b);
      }
    }
    S.bullets = kept;
    for (var si = 0; si < spawned.length; si++) {
      var s2 = spawned[si];
      spawnFoe(s2[0], s2[1], s2[2], s2[3], s2[4], s2[5]);
    }

    // Player trail (only while dashing).
    if (pspeed > C.REF_SPEED * 0.5) {
      S.tcur = ((S.tcur || 0) % C.TRAIL_N) + 1;
      var t = S.trail[S.tcur - 1];
      t.a = 0.4; t.x = S.px; t.y = S.py;
    }
    for (var ti = 0; ti < C.TRAIL_N; ti++) {
      var tt = S.trail[ti];
      if (tt.a > 0.004) tt.a *= 0.85;
    }
    S.pspeed = pspeed;
  }

  // ---- input from the platform / harness -----------------------------------
  function setSize(hw, hh) { G.SW = hw; G.SH = hh; }
  function setPointer(x, y, down) { G.input.x = x; G.input.y = y; G.input.down = down; }
  function setKey(name, down) { G.keys[name] = down; }

  function update(dt) {
    if (dt > C.MAX_DT) dt = C.MAX_DT; // a hitch never teleports anything
    if (G.mode === 'run' && G.S) updateRun(dt);
  }

  // ---- tap routing (world coords) ------------------------------------------
  function tap(x, y) {
    var S = G.S;
    if (S && S.hit_dialog) {
      var hd = S.hit_dialog;
      if (inRect(hd.yes, x, y)) {
        // Sponsor absorbs the hit. Mini-games CANNOT open external URLs, so the
        // Lua game.open_url sponsor link becomes a REWARDED VIDEO AD: finishing
        // the ad waives the 25% chip; bailing on it takes the chip.
        closeHitDialog();
        var reward = platform.rewardAd || function (cb) { cb(true); }; // TODO: real ad unit
        reward(function (rewarded) {
          if (!rewarded) { applyChip(); }
        });
        snd('score'); hap('success');
      } else if (inRect(hd.no, x, y)) {
        closeHitDialog();
        applyChip();
      }
      return;
    }
    if (G.btn.back && inRect(G.btn.back, x, y)) {
      if (G.mode === 'levels') { toSelect(); }
      else if (S && S.trial) { toLevels(); }
      else { toSelect(); }
      return;
    }
    if (G.mode === 'select') {
      if (inRect(G.btn.endless, x, y)) startRun(null, false);
      else if (inRect(G.btn.trials, x, y)) toLevels();
      else if (inRect(G.btn.absorb, x, y)) startRun(null, true);
    } else if (G.mode === 'levels') {
      for (var i = 0; i < G.btn.levels.length; i++) {
        var r = G.btn.levels[i];
        if (inRect(r, x, y) && unlocked(r.i)) { startRun(r.i, false); return; }
      }
    } else if (S && !S.playing && S.card) {
      for (var c = 0; c < S.card.length; c++) {
        var bc = S.card[c];
        if (inRect(bc.rect, x, y)) {
          if (bc.act === 'retry') startRun(S.trial, S.absorb);
          else if (bc.act === 'levels') toLevels();
          else toSelect();
          return;
        }
      }
    }
  }

  buildSelect();

  // Public surface (renderer + tests read G directly for state).
  return {
    state: G,
    setSize: setSize,
    setPointer: setPointer,
    setKey: setKey,
    update: update,
    tap: tap,
    // helpers exposed for the renderer / harness
    starsOf: starsOf,
    unlocked: unlocked,
    bests: bests,
    startRun: startRun,
    toSelect: toSelect,
    toLevels: toLevels,
    inRect: inRect,
  };
}

module.exports = { createGame: createGame, inRect: inRect };
