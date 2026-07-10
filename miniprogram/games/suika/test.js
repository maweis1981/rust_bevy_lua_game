// test.js — invariant harness for the Suika simulation, in watersort/test.js
// style: drive the pure headless sim and assert the rules + physics stability
// hold. Exits non-zero on any failure. Run: node games/suika/test.js
'use strict';
var C = require('./config.js');
var L = require('./logic.js');

var pass = 0, fail = 0;
function ok(cond, msg) { if (cond) { pass++; console.log('  ok  ', msg); } else { fail++; console.log('  FAIL', msg); } }
function section(s) { console.log('[' + s + ']'); }

var BIN = { x: 40, y: 120, w: 700, h: 1000 };

// [1] seeded reproducibility — same seed => identical next-fruit sequence ------
section('rng: seeded, reproducible next-fruit sequence');
function dropSequence(seed, n) {
  var sim = L.createSim(seed, BIN);
  var seq = [];
  for (var i = 0; i < n; i++) { seq.push(sim.state.current); sim.drop(BIN.x + BIN.w / 2); }
  return seq;
}
var seqA = dropSequence(12345, 30);
var seqB = dropSequence(12345, 30);
var seqC = dropSequence(999, 30);
ok(JSON.stringify(seqA) === JSON.stringify(seqB), 'same seed -> identical drop-tier sequence');
ok(JSON.stringify(seqA) !== JSON.stringify(seqC), 'different seed -> different sequence');
var inRange = seqA.every(function (t) { return t >= C.DROP_MIN_TIER && t <= C.DROP_MAX_TIER; });
ok(inRange, 'all dropped tiers are within the droppable range 0..' + C.DROP_MAX_TIER);

// [2] merge produces tier+1 and adds the tier's score -------------------------
section('merge: two same-tier fruit fuse into tier+1 and score');
(function () {
  var sim = L.createSim(7, BIN);
  var S = sim.state;
  var tier = 2, r = C.radiusOf(tier, BIN.w);
  var cx = BIN.x + BIN.w / 2, cy = BIN.y + BIN.h - r - 1;
  // two overlapping tier-2 fruit resting on the floor
  S.fruit.push({ id: S.nextId++, tier: tier, r: r, x: cx - r * 0.5, y: cy, vx: 0, vy: 0, merged: false, sleep: 0 });
  S.fruit.push({ id: S.nextId++, tier: tier, r: r, x: cx + r * 0.5, y: cy, vx: 0, vy: 0, merged: false, sleep: 0 });
  var before = S.score, n0 = S.fruit.length;
  sim.step(1 / 60);
  var hasTier3 = S.fruit.some(function (f) { return f.tier === tier + 1; });
  ok(hasTier3, 'a tier-' + (tier + 1) + ' fruit was produced by the merge');
  ok(S.fruit.length === n0 - 1, 'two fruit merged into one (count -1)');
  ok(S.score === before + C.POINTS[tier], 'score increased by POINTS[' + tier + '] = ' + C.POINTS[tier]);
})();

// merge value chain — a stacked column of same-tier fruit cascades
(function () {
  var sim = L.createSim(8, BIN);
  var S = sim.state;
  var r = C.radiusOf(0, BIN.w);
  var cx = BIN.x + BIN.w / 2, cy = BIN.y + BIN.h - r - 1;
  S.fruit.push({ id: S.nextId++, tier: 0, r: r, x: cx - r * 0.4, y: cy, vx: 0, vy: 0, merged: false, sleep: 0 });
  S.fruit.push({ id: S.nextId++, tier: 0, r: r, x: cx + r * 0.4, y: cy, vx: 0, vy: 0, merged: false, sleep: 0 });
  sim.step(1 / 60);
  ok(sim.state.score > 0, 'cherry+cherry merge awards score');
})();

// [3] game-over predicate fires when a fruit rests above the danger line ------
section('game-over: resting above the danger line for ~DANGER_SECONDS');
(function () {
  // wide, short bin so a large fruit resting on the floor pokes above the line.
  var bin = { x: 0, y: 0, w: 400, h: 200 };
  var sim = L.createSim(3, bin);
  var S = sim.state;
  var tier = 9, r = C.radiusOf(tier, bin.w);           // r ~ 98 in a 400px bin
  var floorY = bin.y + bin.h - r;
  S.fruit.push({ id: S.nextId++, tier: tier, r: r, x: bin.x + bin.w / 2, y: floorY, vx: 0, vy: 0, merged: false, sleep: 0 });
  var dy = sim.dangerY();
  ok(floorY - r < dy, 'the resting fruit top is above the danger line (setup sanity)');
  var overAt1s = false, overAt = -1;
  for (var i = 0; i < 240; i++) {
    sim.step(1 / 60);                                   // 1/60 real s per call
    if (i === 60 && S.over) overAt1s = true;            // ~1s elapsed
    if (S.over) { overAt = i; break; }
  }
  ok(!overAt1s, 'not game-over yet at ~1s (< DANGER_SECONDS)');
  ok(S.over === true, 'game-over fired');
  // ~120 calls ≈ 2s; allow slack for the accrual granularity
  ok(overAt >= 110 && overAt <= 140, 'game-over fired near DANGER_SECONDS (call ' + overAt + ')');
})();

// game-over blocks further drops
(function () {
  var sim = L.createSim(3, BIN);
  sim.state.over = true;
  var f = sim.drop(BIN.x + BIN.w / 2);
  ok(f === null, 'no drop is accepted once the run is over');
})();

// revive clears top fruit and resumes
(function () {
  var sim = L.createSim(5, BIN);
  var S = sim.state;
  for (var i = 0; i < 8; i++) {
    var r = C.radiusOf(0, BIN.w);
    S.fruit.push({ id: S.nextId++, tier: 0, r: r, x: BIN.x + 100 + i * 20, y: BIN.y + 50 + i * 5, vx: 0, vy: 0, merged: false, sleep: 0 });
  }
  S.over = true;
  var n0 = S.fruit.length;
  sim.revive(C.REVIVE_CLEAR);
  ok(S.over === false, 'revive resumes the run');
  ok(S.fruit.length === n0 - C.REVIVE_CLEAR, 'revive removed REVIVE_CLEAR top fruit');
  ok(S.dangerTimer === 0, 'revive resets the danger timer');
})();

// [4] STABILITY — thousands of steps of random drops stay finite & bounded ----
section('stability: 5000 steps of random drops (no NaN, bounded)');
(function () {
  var bin = { x: 40, y: 120, w: 700, h: 1050 };
  var sim = L.createSim(4242, bin);
  var rx = L.newLcg(0xC0FFEE);                          // deterministic drop columns
  var maxR = C.RADII_FRAC[C.RADII_FRAC.length - 1] * bin.w;
  var bad = 0, oob = 0, steps = 5000, maxSeen = 0;
  for (var i = 0; i < steps; i++) {
    if (i % 6 === 0) {
      if (sim.state.over) { sim.revive(20); }           // keep the churn going
      sim.drop(bin.x + rx() * bin.w);
    }
    sim.step(1 / 60);
    var fs = sim.state.fruit;
    for (var j = 0; j < fs.length; j++) {
      var f = fs[j];
      if (!isFinite(f.x) || !isFinite(f.y) || !isFinite(f.vx) || !isFinite(f.vy)) bad++;
      if (f.x < bin.x - 1 || f.x > bin.x + bin.w + 1 ||
          f.y > bin.y + bin.h + 1 || f.y < bin.y - 3 * maxR) oob++;
      var sp = Math.hypot(f.vx, f.vy);
      if (sp > maxSeen) maxSeen = sp;
    }
    if (fs.length > C.MAX_FRUIT) { oob = -1; break; }    // cap breached
  }
  ok(bad === 0, 'no NaN / non-finite fruit over ' + steps + ' steps (found ' + bad + ')');
  ok(oob === 0, 'every fruit stayed inside the bin bounds (violations ' + oob + ')');
  ok(sim.state.fruit.length <= C.MAX_FRUIT, 'fruit count never exceeded MAX_FRUIT (' + C.MAX_FRUIT + ')');
  ok(maxSeen <= C.MAX_SPEED_FRAC * bin.w + 1, 'peak speed stayed under the clamp (' + Math.round(maxSeen) + ' px/s)');
  // sanity: the sim actually did work (merges happened -> some higher tiers)
  var maxTier = 0;
  sim.state.fruit.forEach(function (f) { if (f.tier > maxTier) maxTier = f.tier; });
  ok(sim.state.dropped > 100, 'many fruit were dropped over the run (' + sim.state.dropped + ')');
})();

// [5] a second independent long run from a different seed is also stable ------
section('stability: second seed, larger bin');
(function () {
  var bin = { x: 0, y: 0, w: 900, h: 1400 };
  var sim = L.createSim(77, bin);
  var rx = L.newLcg(12321);
  var bad = 0;
  for (var i = 0; i < 3000; i++) {
    if (i % 5 === 0) { if (sim.state.over) sim.revive(20); sim.drop(bin.x + rx() * bin.w); }
    sim.step(1 / 60);
    var fs = sim.state.fruit;
    for (var j = 0; j < fs.length; j++) {
      var f = fs[j];
      if (!isFinite(f.x) || !isFinite(f.y) || !isFinite(f.vx) || !isFinite(f.vy)) bad++;
    }
  }
  ok(bad === 0, 'no non-finite fruit in the second long run');
})();

console.log('\n' + pass + ' passed, ' + fail + ' failed');
process.exit(fail ? 1 : 0);
