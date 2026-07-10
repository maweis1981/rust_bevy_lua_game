// test.js — invariant harness for the Water Sort logic, in the same spirit as
// miniprogram/test/run.js: drive the pure state machine headless and assert the
// rules hold. Exits non-zero on any failure. Run: node games/watersort/test.js
'use strict';
var L = require('./logic.js');

var pass = 0, fail = 0;
function ok(cond, msg) { if (cond) { pass++; console.log('  ok  ', msg); } else { fail++; console.log('  FAIL', msg); } }
function section(s) { console.log('[' + s + ']'); }

// [1] generation is seeded, reproducible, well-formed, and solvable
section('gen: seeded, well-formed, solvable');
var g1 = L.genLevel(12345, { cap: 4, colors: 5, empty: 2 });
var g1b = L.genLevel(12345, { cap: 4, colors: 5, empty: 2 });
ok(L.key(g1.tubes) === L.key(g1b.tubes), 'same seed -> identical level');
var counts = {};
g1.tubes.forEach(function (t) { t.forEach(function (c) { counts[c] = (counts[c] || 0) + 1; }); });
var everyColorFull = true;
for (var c = 0; c < 5; c++) if (counts[c] !== 4) everyColorFull = false;
ok(everyColorFull, 'each color appears exactly CAP times');
ok(g1.tubes.length === 5 + 2, 'tube count = colors + empty');
ok(!L.isWin(g1.tubes, 4), 'generated level is not already solved');
ok(L.isSolvable(g1.tubes, 4), 'generated level is solvable');

var diffSeeds = 0;
for (var s = 1; s <= 30; s++) {
  var g = L.genLevel(s * 7 + 1, { cap: 4, colors: 4, empty: 2 });
  if (L.isSolvable(g.tubes, 4) && !L.isWin(g.tubes, 4)) diffSeeds++;
}
ok(diffSeeds === 30, 'all 30 sampled seeds produce solvable, non-trivial levels (got ' + diffSeeds + ')');

// [2] pour legality
section('pour: legality rules');
var t = [[0, 0, 1], [1], [], [0]];  // cap 4
ok(L.canPour(t, 1, 3, 4) === false, 'cannot pour color 1 onto color 0');
ok(L.canPour(t, 0, 1, 4) === true, 'can pour top color 1 onto tube topped by 1');
ok(L.canPour(t, 0, 2, 4) === true, 'can pour onto an empty tube');
ok(L.canPour(t, 3, 0, 4) === false, 'cannot pour when colors differ at the seam (0 onto 1-top)');
var full = [[2, 2, 2, 2], [2]];
ok(L.canPour(full, 1, 0, 4) === false, 'cannot pour into a full tube');
ok(L.canPour(full, 0, 1, 4) === false, 'a solved/uniform-full tube is not a source');

// [3] pour moves the whole contiguous top run, capped by destination room
section('pour: run size & capacity');
var t2 = [[3, 1, 1, 1], [1]];   // top run of three 1s, dest has room for 3
ok(L.pourCount(t2, 0, 1, 4) === 3, 'pours the full run of 3 when room allows');
var t3 = [[3, 1, 1, 1], [1, 1, 1]]; // dest room for only 1
ok(L.pourCount(t3, 0, 1, 4) === 1, 'pour is clamped to destination capacity');

// [4] the controller: select -> pour, win detection, undo restores exactly
section('controller: select/pour/win/undo');
var lv = L.createLevel(999, { cap: 4, colors: 4, empty: 2 });
// replay the full shortest solution through the tap controller, asserting a win
var plan = lv.solve();               // [[from,to],...]
ok(Array.isArray(plan) && plan.length > 0, 'solver returns a non-empty plan');
var reachedWin = false;
for (var i = 0; i < plan.length; i++) {
  lv.select(plan[i][0]);
  lv.select(plan[i][1]);
  if (lv.state.won) { reachedWin = true; break; }
}
ok(reachedWin, 'replaying the solver plan through the tap controller reaches a win');
ok(L.isWin(lv.state.tubes, lv.state.cap), 'final state satisfies the win predicate');

// undo round-trip on a fresh level
var lv2 = L.createLevel(1000, { cap: 4, colors: 4, empty: 2 });
var snap = L.key(lv2.state.tubes);
var mvA = lv2.hint();
lv2.select(mvA[0]); lv2.select(mvA[1]);
ok(L.key(lv2.state.tubes) !== snap, 'a pour changed the board');
lv2.undo();
ok(L.key(lv2.state.tubes) === snap, 'undo restores the exact prior board');
ok(lv2.state.moves === 0, 'undo decrements the move counter');

// [5] reward hooks: +1 tube adds an empty; hint returns a legal move
section('rewards: +tube, hint legality');
var lv3 = L.createLevel(2024, { cap: 4, colors: 6, empty: 1 });
var n0 = lv3.state.tubes.length;
lv3.addTube();
ok(lv3.state.tubes.length === n0 + 1, '+1 tube adds an empty tube');
ok(lv3.state.tubes[n0].length === 0, 'the added tube is empty');
var h = lv3.hint();
ok(h === null || (h && L.canPour(lv3.state.tubes, h[0], h[1], lv3.state.cap)),
   'hint is either null or a legal move');

// [6] a won board reports no legal-move stuck state confusion
section('stuck / win exclusivity');
ok(lv.isStuck() === false, 'a won level is not reported as stuck');

console.log('\n' + pass + ' passed, ' + fail + ' failed');
process.exit(fail ? 1 : 0);
