// main.js — wires an injected `platform` to the game core + renderer and runs
// the frame loop. Called by wechat/game.js and douyin/game.js with their
// respective adapters. Kept tiny and platform-free.
//
// The `platform` object must provide:
//   canvas            a wx/tt canvas (getContext('2d'), .width, .height)
//   onTouchStart/Move/End(cb)   cb(xPx, yPx) in canvas pixels
//   storage.get/set   persistence (wx/tt.getStorageSync/setStorageSync)
//   rewardAd(cb)       show a rewarded video ad; cb(rewarded:boolean)
//   raf(cb)            request-animation-frame
//   now()             high-res millis (optional; falls back to Date.now)
//   sound/haptic/shake/zoom/emit/track   optional juice
'use strict';

var createGame = require('./game.js').createGame;
var createRenderer = require('./render.js').createRenderer;
var createSound = require('./sound.js').createSound;
var createParticles = require('./particles.js').createParticles;

function startGame(platform) {
  var canvas = platform.canvas;
  var ctx = canvas.getContext('2d');
  var W = canvas.width, H = canvas.height;
  var SW = W / 2, SH = H / 2;

  // --- Juice wiring: the game core already emits sound/shake/zoom cues in ALL
  // three modes; here we give those hooks a real implementation. -------------
  // Sound: synth on the platform's Web Audio context (if the adapter exposes
  // one). Attach as platform.sound so game.js's snd() routes to it.
  var sfx = createSound(platform.audio ? platform.audio() : null);
  if (!platform.sound) platform.sound = function (n) { sfx.play(n); };
  // Screen shake + zoom punch: a shared "trauma" the renderer reads and decays.
  var juice = { trauma: 0, zoom: 0 };
  platform.shake = function (a) { juice.trauma = Math.min(1, juice.trauma + (a || 0)); };
  platform.zoom = function (a) { juice.zoom = Math.min(1, juice.zoom + (a || 0)); };
  // Particles: the game core emits presets on eats/gates/deaths/clears.
  var particles = createParticles(240);
  platform.emit = function (preset, x, y, opts) { particles.burst(preset, x, y, opts); };

  var game = createGame(platform);
  game.setSize(SW, SH);
  var renderer = createRenderer(ctx, W, H, juice, particles);

  function toWorld(px, py) { return { x: px - SW, y: SH - py }; }

  var audioReady = false;
  platform.onTouchStart(function (px, py) {
    if (!audioReady) { sfx.resume(); audioReady = true; } // un-suspend on 1st gesture
    var w = toWorld(px, py);
    game.setPointer(w.x, w.y, true);
    game.tap(w.x, w.y);
  });
  platform.onTouchMove(function (px, py) {
    var w = toWorld(px, py);
    game.setPointer(w.x, w.y, true);
  });
  platform.onTouchEnd(function () {
    game.setPointer(null, null, false);
  });

  var now = platform.now || function () { return Date.now(); };
  var last = now();
  function frame() {
    var t = now();
    var dt = (t - last) / 1000;
    last = t;
    if (dt > 0.1) dt = 0.1;    // tab-away / stall guard
    if (dt < 0) dt = 0;
    game.update(dt);
    particles.update(dt);
    renderer.draw(game, t / 1000);
    platform.raf(frame);
  }
  platform.raf(frame);
  return game;
}

module.exports = { startGame: startGame };
