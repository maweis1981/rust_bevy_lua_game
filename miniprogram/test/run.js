// test/run.js — headless invariant suite for the shared TIME DODGE engine.
// No deps, no canvas: it drives the game state machine directly through a
// stub platform (in-memory storage + a stub rewarded ad) and asserts the same
// contract the Lua suite (tools/test_pong.lua) checks for the Rust build.
//
//   node miniprogram/test/run.js      (exits non-zero on any failure)
'use strict';

var path = require('path');
var createGame = require(path.join(__dirname, '..', 'shared', 'game.js')).createGame;
var C = require(path.join(__dirname, '..', 'shared', 'config.js'));

var pass = 0, fail = 0;
function ok(cond, msg) {
  if (cond) { pass++; console.log('  ok   ' + msg); }
  else { fail++; console.log('  FAIL ' + msg); }
}
function near(a, b, eps) { return Math.abs(a - b) <= (eps === undefined ? 1e-6 : eps); }

function makePlatform() {
  var store = {};
  return {
    _store: store,
    storage: {
      get: function (k) { return Object.prototype.hasOwnProperty.call(store, k) ? store[k] : null; },
      set: function (k, v) { store[k] = String(v); },
    },
    rewardAd: function (cb) { cb(true); }, // stub: sponsor grants the reward
  };
}

function newGame() {
  var g = createGame(makePlatform());
  g.setSize(200, 356);
  return g;
}

function hold(g, frames, x, y) {
  for (var i = 0; i < frames; i++) {
    g.setPointer(x || 0, y || 0, true);
    g.update(1 / 30);
  }
}
function release(g, frames) {
  for (var i = 0; i < frames; i++) {
    g.setPointer(null, null, false);
    g.update(1 / 30);
  }
}
// inject a foe directly onto the player, in-plane, of a given size.
function injectFoe(g, size) {
  var S = g.state.S;
  S.bullets.push({ kind: 'dart', x: S.px, y: S.py, vx: 0, vy: 0, age: 0,
    near: false, z: 0.10, rot: 0, spin: 0, size: size, gone: false });
}

console.log('TIME DODGE — shared engine invariants\n');

// ---- 1. hold = time flows, release = world freezes (the core rule) ---------
(function () {
  console.log('[1] timescale: hold flows, release freezes');
  var g = newGame();
  g.tap(0, 10); // ENDLESS button
  ok(g.state.mode === 'run' && g.state.S && !g.state.S.trial && !g.state.S.absorb, 'ENDLESS run started');
  for (var i = 0; i < 20; i++) { g.setPointer(0, 0, true); g.update(1 / 30); g.state.S.bullets = []; }
  var tsHeld = g.state.S.ts;
  ok(tsHeld > 0.9, 'held: timescale drives toward 1 (got ' + tsHeld.toFixed(3) + ')');
  var scoreA = g.state.S.score;
  for (var j = 0; j < 20; j++) { g.setPointer(null, null, false); g.update(1 / 30); g.state.S.bullets = []; }
  var tsRel = g.state.S.ts;
  ok(tsRel < 0.15, 'released: timescale collapses toward TS_MIN (got ' + tsRel.toFixed(3) + ')');
  ok(near(tsRel, C.TS_MIN, 0.05), 'released timescale approaches TS_MIN=' + C.TS_MIN);
  // world time (stolen score) accrues fast while held, barely while frozen
  var g2 = newGame(); g2.tap(0, 10);
  hold(g2, 30); g2.state.S.bullets = [];
  var gained = g2.state.S.score;
  var before = g2.state.S.score;
  release(g2, 30);
  var frozenGain = g2.state.S.score - before;
  ok(gained > frozenGain * 3, 'stolen score accrues far faster held than frozen (' +
    gained.toFixed(2) + ' vs ' + frozenGain.toFixed(3) + ')');
})();

// ---- 2. ABSORB: eating a smaller rock grows mass by area -------------------
(function () {
  console.log('[2] absorb: small-eat grows mass');
  var g = newGame();
  g.tap(0, -230); // ABSORB button
  ok(g.state.S && g.state.S.absorb, 'ABSORB run started');
  var m0 = g.state.S.mass, e0 = g.state.S.eaten;
  injectFoe(g, 10); // smaller than PLAYER(26)
  g.setPointer(0, 0, true);
  g.update(1 / 30);
  ok(g.state.S.mass > m0, 'mass grew after eating (from ' + m0.toFixed(1) + ' to ' + g.state.S.mass.toFixed(1) + ')');
  ok(g.state.S.eaten === e0 + 1, 'eaten counter incremented');
  var expect = Math.sqrt(m0 * m0 + C.EAT_GAIN * 10 * 10);
  ok(near(g.state.S.mass, expect, 1e-6), 'mass = sqrt(m^2 + size^2) area growth');
})();

// ---- 3 & 4. First big hit opens the dialog once; NO chips x0.75 ------------
(function () {
  console.log('[3] absorb: first big hit opens the cancel dialog exactly once');
  var g = newGame();
  g.tap(0, -230);
  injectFoe(g, 90); // bigger than mass
  g.setPointer(0, 0, true);
  g.update(1 / 30);
  ok(g.state.S.hit_dialog !== null, 'big hit opened the CANCEL dialog');
  ok(g.state.S.dialog_used === true, 'dialog armed flag set (once per run)');
  var massBefore = g.state.S.mass;

  console.log('[4] NO on the dialog chips mass x0.75');
  var no = g.state.S.hit_dialog.no;
  g.tap(no.x, no.y); // press NO
  ok(g.state.S.hit_dialog === null, 'dialog closed after NO');
  ok(near(g.state.S.mass, massBefore * C.CHIP, 1e-6),
    'mass chipped to x' + C.CHIP + ' (from ' + massBefore.toFixed(1) + ' to ' + g.state.S.mass.toFixed(1) + ')');

  // a SECOND big hit must NOT reopen the dialog (it's once-per-run) -> chips.
  var massBefore2 = g.state.S.mass;
  injectFoe(g, 200);
  g.setPointer(0, 0, true);
  g.update(1 / 30);
  ok(g.state.S.hit_dialog === null, 'second big hit does NOT reopen the dialog');
  ok(g.state.S.playing ? near(g.state.S.mass, massBefore2 * C.CHIP, 1e-6) : true,
    'second big hit takes the normal chip');
})();

// ---- 4b. YES on the dialog + completed reward ad waives the chip -----------
(function () {
  console.log('[4b] YES + finished rewarded ad waives the chip (external URL -> ad)');
  var g = newGame();
  g.tap(0, -230);
  injectFoe(g, 90);
  g.setPointer(0, 0, true);
  g.update(1 / 30);
  var massBefore = g.state.S.mass;
  var yes = g.state.S.hit_dialog.yes;
  g.tap(yes.x, yes.y); // stub rewardAd grants reward -> no chip
  ok(g.state.S.hit_dialog === null, 'dialog closed after YES');
  ok(near(g.state.S.mass, massBefore, 1e-6), 'mass unchanged when sponsor absorbs the hit');
})();

// ---- 5. Below MIN_MASS the player fades away (run ends) ---------------------
(function () {
  console.log('[5] absorb: chipped below MIN_MASS fades away');
  var g = newGame();
  g.tap(0, -230);
  var S = g.state.S;
  S.dialog_used = true;      // past the one-time offer
  S.mass = 16;               // 16 * 0.75 = 12 < MIN_MASS(13)
  injectFoe(g, 200);
  g.setPointer(0, 0, true);
  g.update(1 / 30);
  ok(!g.state.S.playing, 'run ended (player faded)');
  ok(g.state.S.card && g.state.S.cardTitle === 'YOU FADED AWAY', 'fade-out end card shown');
})();

// ---- 6. Trial clear awards stars and unlocks the next level ----------------
(function () {
  console.log('[6] trials: clearing level 1 awards stars and unlocks level 2');
  var g = newGame();
  ok(g.unlocked(1) === true && g.unlocked(2) === false, 'level 1 open, level 2 locked at start');
  g.startRun(1, false);
  var S = g.state.S;
  var gates = C.LEVELS[0].gates;
  var guard = 0;
  while (g.state.S && g.state.S.playing && guard < 200) {
    // teleport onto the current gate, then step so it is captured
    S = g.state.S;
    if (S.gate) { S.px = S.gate.x; S.py = S.gate.y; }
    g.setPointer(null, null, false);
    g.update(1 / 30);
    if (g.state.S) g.state.S.bullets = []; // keep foes from ending the run in-test
    guard++;
  }
  ok(g.state.S && g.state.S.done, 'level 1 finished (' + gates + ' gates reached)');
  ok(g.starsOf(1) >= 1, 'stars awarded for level 1 (got ' + g.starsOf(1) + ')');
  ok(g.unlocked(2) === true, 'level 2 unlocked after >=1 star');
})();

// ---- 7. dt hitch never teleports the player (feel contract) ----------------
(function () {
  console.log('[7] a big dt hitch never teleports the orb (dt clamp)');
  var g = newGame();
  g.tap(0, 10);
  g.setPointer(0, 0, true); g.update(1 / 30);       // anchor the drag
  var px0 = g.state.S.px;
  g.setPointer(300, 300, true); g.update(5.0);       // huge dt + big finger jump
  var moved = Math.hypot(g.state.S.px - px0, g.state.S.py - px0);
  ok(moved <= C.PLAYER_MAX * C.MAX_DT + 1e-6, 'player move bounded by PLAYER_MAX*MAX_DT (moved ' + moved.toFixed(2) + ')');
})();

// ---- 8. Subpackage (分包) launcher: loads the engine, then boots ------------
(function () {
  console.log('[8] boot/launch: subpackage loads with progress, then boots once');
  var launch = require(path.join(__dirname, '..', 'boot', 'launch.js')).launch;

  // A no-op 2D context so boot/loading.js can draw without a real canvas.
  function stubCtx() {
    var noop = function () {};
    return {
      createLinearGradient: function () { return { addColorStop: noop }; },
      fillRect: noop, strokeRect: noop, beginPath: noop, arc: noop, fill: noop,
      fillText: noop, save: noop, restore: noop,
      set fillStyle(v) {}, set strokeStyle(v) {}, set lineWidth(v) {},
      set globalAlpha(v) {}, set font(v) {}, set textAlign(v) {}, set textBaseline(v) {},
    };
  }
  var canvas = { width: 400, height: 700, getContext: function () { return stubCtx(); } };

  // Drive raf a bounded number of times so the loading loop can't spin forever.
  var rafBudget = 8;
  function raf(cb) { if (rafBudget-- > 0) cb(); }

  // Fake loadSubpackage: reports progress 0→100 then calls success, like wx/tt.
  var progressSeen = [];
  function loadSubpackage(opts) {
    ok(opts && opts.name === 'engine', 'launcher requests the "engine" subpackage');
    var handlers = { onProgress: function (fn) { handlers._p = fn; return handlers; } };
    // Simulate async progress + completion synchronously for the test.
    setTimeout(function () {
      if (handlers._p) { handlers._p({ progress: 40 }); handlers._p({ progress: 100 }); }
      opts.success();
    }, 0);
    return handlers;
  }

  var booted = 0;
  var platform = { canvas: canvas, raf: raf, loadSubpackage: loadSubpackage,
    onProgress: function (p) { progressSeen.push(p); } };
  launch(platform, function (p) { booted++; ok(p === platform, 'boot receives the platform'); });

  // Let the setTimeout(0) fire.
  setTimeout(function () {
    ok(booted === 1, 'engine booted exactly once after subpackage success');

    // Fallback path: no loadSubpackage (e.g. preview/DevTools inlining) -> boot now.
    var booted2 = 0;
    launch({ canvas: canvas, raf: raf }, function () { booted2++; });
    ok(booted2 === 1, 'without loadSubpackage, launcher boots directly (fallback)');

    // ---- 9. TikTok bundle: the browser CommonJS bundle boots the engine ------
    (function () {
      console.log('[9] tiktok: engine.bundle.js require()s and starts the shared engine');
      var fs = require('fs');
      var bundlePath = path.join(__dirname, '..', 'tiktok', 'engine.bundle.js');
      if (!fs.existsSync(bundlePath)) {
        console.log('  skip (run prepare.sh first to generate tiktok/engine.bundle.js)');
      } else {
        // Fake just enough browser: a `window` for the bundle's registry, and a
        // no-op 2D canvas so shared/main.js can draw one frame.
        var win = {};
        var code = fs.readFileSync(bundlePath, 'utf8').replace(/\bwindow\b/g, '__win');
        // eslint-disable-next-line no-new-func
        (new Function('__win', code))(win);
        ok(typeof win.require === 'function', 'bundle exposes require()');
        var startGame = win.require('main.js').startGame;
        ok(typeof startGame === 'function', 'require("main.js").startGame is a function');

        var noop = function () {};
        var ctx = {
          createLinearGradient: function () { return { addColorStop: noop }; },
          createRadialGradient: function () { return { addColorStop: noop }; },
          fillRect: noop, strokeRect: noop, clearRect: noop, beginPath: noop,
          arc: noop, arcTo: noop, ellipse: noop, rect: noop, roundRect: noop,
          moveTo: noop, lineTo: noop, quadraticCurveTo: noop, bezierCurveTo: noop,
          closePath: noop, fill: noop, clip: noop,
          stroke: noop, fillText: noop, strokeText: noop, save: noop, restore: noop,
          translate: noop, rotate: noop, scale: noop, setTransform: noop, setLineDash: noop,
          measureText: function () { return { width: 10 }; },
          set fillStyle(v) {}, set strokeStyle(v) {}, set lineWidth(v) {},
          set globalAlpha(v) {}, set font(v) {}, set textAlign(v) {},
          set textBaseline(v) {}, set lineCap(v) {}, set lineJoin(v) {}, set shadowBlur(v) {}, set shadowColor(v) {},
        };
        var canvas = { width: 390, height: 690, getContext: function () { return ctx; } };
        var frames = 0;
        var platform = {
          canvas: canvas,
          onTouchStart: noop, onTouchMove: noop, onTouchEnd: noop,
          storage: { get: function () { return null; }, set: noop },
          rewardAd: function (cb) { cb(true); },
          raf: function (cb) { if (frames++ < 3) cb(); },
          now: function () { return frames * 16; },
        };
        var g = startGame(platform);
        ok(g && typeof g.update === 'function', 'startGame returned a live game (ran frames without throwing)');
      }
    })();

    console.log('\n' + pass + ' passed, ' + fail + ' failed');
    process.exit(fail === 0 ? 0 : 1);
  }, 5);
})();
