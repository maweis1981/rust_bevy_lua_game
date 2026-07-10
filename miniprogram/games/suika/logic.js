// logic.js — Suika pure simulation. NO rendering, NO platform, NO DOM — so it
// runs identically in the mini-game runtimes, in the TikTok webview, and
// headless in Node (test.js). The next-fruit sequence is driven by the same
// exact seeded LCG as watersort/logic.js, so a given seed reproduces the same
// run. Physics is deterministic (no rng), so a long random-drop simulation is
// reproducible and testable for stability (no NaN, bounded positions).
//
// Coordinate space: pixel-like, y DOWN. The bin is an axis-aligned rectangle
// {x,y,w,h} (top-left origin). Fruit are circles {x,y,vx,vy,r,tier,id}. The
// caller (game.js) supplies the bin rect; the sim owns everything inside it.
'use strict';

var C = require('./config.js');

// --- exact LCG (mirrors watersort/logic.js & shared/rng.js) ------------------
var A = 1103515245n, Cc = 12345n, M = 2147483648n;
function newLcg(seed) {
  var s = BigInt(seed >>> 0) % M;
  return function () { s = (A * s + Cc) % M; return Number(s) / 2147483648; };
}

function finite(n) { return typeof n === 'number' && isFinite(n); }

// --- the simulation ----------------------------------------------------------
// createSim(seed, bin) -> stateful headless controller.
//   bin = { x, y, w, h } in pixels.
function createSim(seed, bin) {
  var rnd = newLcg(seed);
  var S = {
    bin: { x: bin.x, y: bin.y, w: bin.w, h: bin.h },
    fruit: [],
    nextId: 1,
    score: 0,
    over: false,
    dangerTimer: 0,          // seconds a fruit has rested above the danger line
    current: pickDropTier(), // tier queued to drop next
    next: pickDropTier(),    // tier after that (preview)
    lastMerges: 0,           // merges applied in the most recent step (juice)
    lastPops: 0,             // max-tier pops in the most recent step (juice)
    mergeEvents: [],         // {x,y,tier,pop} per merge — drained by the renderer for particle FX
    dropped: 0,              // total fruit dropped
  };

  function pickDropTier() {
    var span = C.DROP_MAX_TIER - C.DROP_MIN_TIER + 1;
    return C.DROP_MIN_TIER + Math.floor(rnd() * span);
  }

  function dangerY() { return S.bin.y + C.DANGER_LINE_FRAC * S.bin.h; }

  // spawn the queued `current` fruit at column x (clamped inside the bin), just
  // above the danger line. Advances the current/next queue. Returns the fruit
  // or null (over / at cap).
  function drop(x) {
    if (S.over) return null;
    if (S.fruit.length >= C.MAX_FRUIT) return null;
    var tier = S.current;
    var r = C.radiusOf(tier, S.bin.w);
    var minX = S.bin.x + r, maxX = S.bin.x + S.bin.w - r;
    if (!finite(x)) x = S.bin.x + S.bin.w / 2;
    x = Math.max(minX, Math.min(maxX, x));
    var f = {
      id: S.nextId++, tier: tier, r: r,
      x: x, y: S.bin.y + r + 1, vx: 0, vy: 0,
      merged: false, sleep: 0,
    };
    S.fruit.push(f);
    S.current = S.next;
    S.next = pickDropTier();
    S.dropped++;
    return f;
  }

  var invMassCache = {}; // tier -> inverse mass (mass ~ r^2 ~ area)
  function invMass(f) {
    var m = f.r * f.r;
    return m > 0 ? 1 / m : 0;
  }

  // integrate one FIXED step (config FIXED_DT), split into SUBSTEPS, each with
  // ITERS position-relaxation passes. Deterministic.
  function fixedStep() {
    if (S.over) return;
    var b = S.bin;
    var g = C.GRAVITY_FRAC * b.w;
    var maxV = C.MAX_SPEED_FRAC * b.w;
    var subs = C.SUBSTEPS;
    var sdt = C.FIXED_DT / subs;
    var fs = S.fruit;
    var i, j;

    for (var sub = 0; sub < subs; sub++) {
      // integrate
      for (i = 0; i < fs.length; i++) {
        var f = fs[i];
        f.vy += g * sdt;
        // clamp speed
        var sp = Math.hypot(f.vx, f.vy);
        if (sp > maxV) { var k = maxV / sp; f.vx *= k; f.vy *= k; }
        f.vx *= C.AIR_DAMP; f.vy *= C.AIR_DAMP;
        f.x += f.vx * sdt; f.y += f.vy * sdt;
        // NaN guard
        if (!finite(f.x) || !finite(f.y) || !finite(f.vx) || !finite(f.vy)) {
          f.x = b.x + b.w / 2; f.y = b.y + b.h / 2; f.vx = 0; f.vy = 0;
        }
      }
      // relaxation: walls + pairwise separation
      for (var it = 0; it < C.ITERS; it++) {
        for (i = 0; i < fs.length; i++) confineWall(fs[i]);
        for (i = 0; i < fs.length; i++) {
          for (j = i + 1; j < fs.length; j++) separate(fs[i], fs[j]);
        }
      }
    }
  }

  function confineWall(f) {
    var b = S.bin;
    var left = b.x + f.r, right = b.x + b.w - f.r;
    var floor = b.y + b.h - f.r;
    if (f.x < left) { f.x = left; if (f.vx < 0) f.vx = -f.vx * C.WALL_RESTITUTION; }
    else if (f.x > right) { f.x = right; if (f.vx > 0) f.vx = -f.vx * C.WALL_RESTITUTION; }
    if (f.y > floor) { f.y = floor; if (f.vy > 0) f.vy = -f.vy * C.WALL_RESTITUTION; }
    // soft ceiling well above the bin top so nothing escapes upward
    var ceil = b.y - f.r * 2;
    if (f.y < ceil) { f.y = ceil; if (f.vy < 0) f.vy = 0; }
  }

  // position-based separation + light normal impulse for a pair. Same-tier
  // overlaps are only marked for merge (resolved after the step) — we still
  // separate them lightly so they don't sink through each other before merging.
  function separate(a, bb) {
    var dx = bb.x - a.x, dy = bb.y - a.y;
    var dist = Math.hypot(dx, dy);
    var minDist = a.r + bb.r;
    if (dist >= minDist) return;
    var nx, ny;
    if (dist < 1e-6) {
      // coincident centers: deterministic normal by id parity so we never NaN
      nx = ((a.id + bb.id) & 1) ? 1 : 0;
      ny = 1 - nx;
      dist = 1e-6;
    } else { nx = dx / dist; ny = dy / dist; }
    var overlap = minDist - dist;
    var ia = invMass(a), ib = invMass(bb), sum = ia + ib;
    if (sum <= 0) return;
    var pushA = overlap * (ia / sum) * 0.8;   // 0.8 relaxation to avoid overshoot
    var pushB = overlap * (ib / sum) * 0.8;
    a.x -= nx * pushA; a.y -= ny * pushA;
    bb.x += nx * pushB; bb.y += ny * pushB;
    // light restitution on the approaching normal component only
    var rvx = bb.vx - a.vx, rvy = bb.vy - a.vy;
    var rel = rvx * nx + rvy * ny;
    if (rel < 0) {
      var jimp = -(1 + C.PAIR_RESTITUTION) * rel / sum;
      var ix = jimp * nx, iy = jimp * ny;
      a.vx -= ix * ia; a.vy -= iy * ia;
      bb.vx += ix * ib; bb.vy += iy * ib;
    }
  }

  // resolve merges: any two overlapping fruit of the SAME tier fuse into one
  // tier+1 fruit at their midpoint (each fruit merges at most once per step).
  // A pair at MAX tier pops (both removed) for a bonus instead.
  function resolveMerges() {
    var fs = S.fruit;
    var i, j;
    for (i = 0; i < fs.length; i++) fs[i].merged = false;
    var newFruit = [];
    var merges = 0, pops = 0;
    for (i = 0; i < fs.length; i++) {
      var a = fs[i];
      if (a.merged) continue;
      for (j = i + 1; j < fs.length; j++) {
        var bb = fs[j];
        if (bb.merged || bb.tier !== a.tier) continue;
        var dx = bb.x - a.x, dy = bb.y - a.y;
        var dist = Math.hypot(dx, dy);
        if (dist > a.r + bb.r) continue;         // must actually be touching
        a.merged = true; bb.merged = true;
        var mx = (a.x + bb.x) / 2, my = (a.y + bb.y) / 2;
        if (a.tier >= C.TIER_COUNT - 1) {
          S.score += C.MAX_POP_BONUS; pops++;
          S.mergeEvents.push({ x: mx, y: my, tier: a.tier, pop: true });
        } else {
          var nt = a.tier + 1;
          S.score += C.POINTS[Math.min(a.tier, C.POINTS.length - 1)];
          S.mergeEvents.push({ x: mx, y: my, tier: nt, pop: false });
          newFruit.push({
            id: S.nextId++, tier: nt, r: C.radiusOf(nt, S.bin.w),
            x: (a.x + bb.x) / 2, y: (a.y + bb.y) / 2,
            vx: (a.vx + bb.vx) / 2, vy: (a.vy + bb.vy) / 2,
            merged: false, sleep: 0,
          });
          merges++;
        }
        break; // a is consumed; move to next i
      }
    }
    if (merges || pops) {
      S.fruit = fs.filter(function (f) { return !f.merged; }).concat(newFruit);
    }
    if (S.mergeEvents.length > 120) S.mergeEvents.splice(0, S.mergeEvents.length - 120);
    S.lastMerges = merges; S.lastPops = pops;
  }

  // danger check: is any fruit RESTING with its top above the danger line?
  function anyRestingOverLine() {
    var dy = dangerY();
    var rest = C.REST_SPEED_FRAC * S.bin.w;
    for (var i = 0; i < S.fruit.length; i++) {
      var f = S.fruit[i];
      if (f.y - f.r < dy && Math.hypot(f.vx, f.vy) < rest) return true;
    }
    return false;
  }

  // step the whole sim forward `dt` real seconds. Runs fixed steps + merges,
  // updates the danger timer / game-over predicate. Returns an events summary.
  function step(dt) {
    if (S.over || !finite(dt) || dt <= 0) { S.lastMerges = 0; S.lastPops = 0; return { merges: 0, pops: 0, over: S.over }; }
    var n = Math.min(C.MAX_STEPS_PER_FRAME, Math.max(1, Math.round(dt / C.FIXED_DT)));
    var totMerges = 0, totPops = 0;
    for (var s = 0; s < n; s++) {
      fixedStep();
      resolveMerges();
      totMerges += S.lastMerges; totPops += S.lastPops;
      // danger accrual is charged per fixed step so it's framerate-independent
      if (anyRestingOverLine()) {
        S.dangerTimer += C.FIXED_DT;
        if (S.dangerTimer >= C.DANGER_SECONDS) { S.over = true; break; }
      } else {
        S.dangerTimer = 0;
      }
    }
    S.lastMerges = totMerges; S.lastPops = totPops;
    return { merges: totMerges, pops: totPops, over: S.over };
  }

  // REVIVE reward: remove the top-most fruit (those above / nearest the danger
  // line) to rescue a lost run, then clear the danger timer and resume.
  function revive(nClear) {
    nClear = nClear || C.REVIVE_CLEAR;
    // sort by y ascending (top of bin first) and drop the first nClear
    var sorted = S.fruit.slice().sort(function (p, q) { return (p.y - p.r) - (q.y - q.r); });
    var kill = {};
    for (var i = 0; i < Math.min(nClear, sorted.length); i++) kill[sorted[i].id] = true;
    S.fruit = S.fruit.filter(function (f) { return !kill[f.id]; });
    S.dangerTimer = 0;
    S.over = false;
    return true;
  }

  function reset() {
    S.fruit = []; S.score = 0; S.over = false; S.dangerTimer = 0;
    S.nextId = 1; S.dropped = 0; S.lastMerges = 0; S.lastPops = 0;
    S.mergeEvents = [];
    S.current = pickDropTier(); S.next = pickDropTier();
  }

  function setBin(nb) {
    // rescale existing fruit proportionally so a resize doesn't teleport them
    var ob = S.bin;
    if (ob.w > 0 && ob.h > 0 && nb.w > 0 && nb.h > 0) {
      var sx = nb.w / ob.w, sy = nb.h / ob.h;
      for (var i = 0; i < S.fruit.length; i++) {
        var f = S.fruit[i];
        f.x = nb.x + (f.x - ob.x) * sx;
        f.y = nb.y + (f.y - ob.y) * sy;
        f.r = C.radiusOf(f.tier, nb.w);
      }
    }
    S.bin = { x: nb.x, y: nb.y, w: nb.w, h: nb.h };
  }

  return {
    state: S,
    drop: drop,
    step: step,
    revive: revive,
    reset: reset,
    setBin: setBin,
    dangerY: dangerY,
    // introspection for tests / juice
    isOver: function () { return S.over; },
    count: function () { return S.fruit.length; },
  };
}

module.exports = {
  newLcg: newLcg,
  createSim: createSim,
};
