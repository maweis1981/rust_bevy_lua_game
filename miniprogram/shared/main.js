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

function startGame(platform) {
  var canvas = platform.canvas;
  var ctx = canvas.getContext('2d');
  var W = canvas.width, H = canvas.height;
  var SW = W / 2, SH = H / 2;

  var game = createGame(platform);
  game.setSize(SW, SH);
  var renderer = createRenderer(ctx, W, H);

  function toWorld(px, py) { return { x: px - SW, y: SH - py }; }

  platform.onTouchStart(function (px, py) {
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
    renderer.draw(game, t / 1000);
    platform.raf(frame);
  }
  platform.raf(frame);
  return game;
}

module.exports = { startGame: startGame };
