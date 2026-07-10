// main.js — standalone frame loop for Suika. Wires an injected `platform` (same
// shape as watersort's shell) to the game core. Computes real `dt` from
// platform.now and drives game.update(dt,tSec) + game.draw(ctx). topInset is 0
// in standalone (the router supplies a non-zero inset when embedding). Kept
// platform-free.
'use strict';
var createGame = require('./game.js').createGame;

function startGame(platform) {
  var canvas = platform.canvas;
  var ctx = canvas.getContext('2d');
  var W = canvas.width, H = canvas.height;

  var game = createGame(platform);
  game.setSize(W, H, 0);

  // touchstart drops at the tapped column; drag moves the aim guide.
  platform.onTouchStart(function (px, py) { game.tap(px, py); });
  if (platform.onTouchMove) platform.onTouchMove(function (px, py) { game.pointer(px, py, true); });
  if (platform.onTouchEnd) platform.onTouchEnd(function () {});

  var now = platform.now ? function () { return platform.now(); } : function () { return Date.now(); };
  var last = now();

  function frame() {
    var t = now();
    var dt = (t - last) / 1000;
    last = t;
    if (!(dt > 0)) dt = 0;
    if (dt > 0.1) dt = 0.1;                 // clamp hitches
    game.update(dt, t / 1000);
    game.draw(ctx);
    platform.raf(frame);
  }
  platform.raf(frame);
  return game;
}

module.exports = { startGame: startGame };
