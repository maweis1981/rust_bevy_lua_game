// main.js — standalone frame loop for Water Sort. Wires an injected `platform`
// (same shape as the shell's) to the game core + renderer. This is a TAP game,
// so it passes raw canvas pixels straight to game.tap(px,py) (no world-coord
// conversion). Kept platform-free.
'use strict';
var createGame = require('./game.js').createGame;
var createRenderer = require('./render.js').createRenderer;

function startGame(platform) {
  var canvas = platform.canvas;
  var ctx = canvas.getContext('2d');
  var W = canvas.width, H = canvas.height;

  var game = createGame(platform);
  game.setSize(W, H);
  var renderer = createRenderer(ctx, W, H);

  // tap on touch start (pour game — no drag). Pixels pass through unchanged.
  platform.onTouchStart(function (px, py) { game.tap(px, py); });
  if (platform.onTouchMove) platform.onTouchMove(function () {});
  if (platform.onTouchEnd) platform.onTouchEnd(function () {});

  function frame() {
    game.update();
    renderer.draw(game);
    platform.raf(frame);
  }
  platform.raf(frame);
  return game;
}

module.exports = { startGame: startGame };
