// router.js — the collection shell. Owns the canvas, the RAF loop, and input
// dispatch; swaps between the menu and a running game. Reserves a top BAR for a
// "‹ back" chip and runs each game in the space BELOW it: the game is sized to
// (W, H-BAR), the router translates its draw by (0,BAR) and offsets input y by
// -BAR, so games need zero awareness of the shell (they draw in their own
// 0-based space). This is what makes the collection composable.
'use strict';

var createMenu = require('./menu.js').createMenu;

function createRouter(platform, registry, ad) {
  var canvas = platform.canvas;
  var ctx = canvas.getContext('2d');
  var W = canvas.width, H = canvas.height;
  var BAR = Math.round(H * 0.07);
  var now = platform.now || function () { return Date.now(); };

  var games = registry.map(function (g) { return { id: g.id, title: g.title, subtitle: g.subtitle, color: g.color }; });
  var menu = createMenu(games, { ad: ad, now: now, onPick: launch, getImage: platform.getImage });
  menu.setSize(W, H);

  var screen = 'menu';   // 'menu' | 'game'
  var current = null;    // active game instance
  var currentId = null;

  function launch(id) {
    var entry = null;
    for (var i = 0; i < registry.length; i++) if (registry[i].id === id) entry = registry[i];
    if (!entry) return;
    current = entry.create(platform, { W: W, H: H - BAR, ad: ad, exit: backToMenu });
    if (current.setSize) current.setSize(W, H - BAR);
    currentId = id; screen = 'game';
  }
  function backToMenu() {
    if (current && current.destroy) current.destroy();
    current = null; currentId = null; screen = 'menu';
  }

  // --- input --------------------------------------------------------------
  platform.onTouchStart(function (px, py) {
    if (screen === 'menu') { menu.tap(px, py); return; }
    if (py < BAR) { backToMenu(); return; }         // back chip zone
    var y = py - BAR;
    if (current.tap) current.tap(px, y);
    if (current.pointer) current.pointer(px, y, true);
  });
  platform.onTouchMove(function (px, py) {
    if (screen !== 'game' || py < BAR) return;
    if (current.pointer) current.pointer(px, py - BAR, true);
  });
  platform.onTouchEnd(function (px, py) {
    if (screen !== 'game') return;
    if (current.pointer) current.pointer(px, (py || BAR) - BAR, false);
  });

  // --- top bar ------------------------------------------------------------
  function drawBar() {
    ctx.fillStyle = '#0b1020'; ctx.fillRect(0, 0, W, BAR);
    ctx.strokeStyle = 'rgba(255,255,255,0.10)'; ctx.lineWidth = 1;
    ctx.beginPath(); ctx.moveTo(0, BAR - 0.5); ctx.lineTo(W, BAR - 0.5); ctx.stroke();
    ctx.fillStyle = '#eaf0ff'; ctx.textAlign = 'left'; ctx.textBaseline = 'middle';
    ctx.font = '600 ' + Math.floor(BAR * 0.42) + 'px system-ui, sans-serif';
    ctx.fillText('‹ MENU', W * 0.05, BAR * 0.5);
    if (currentId) {
      ctx.textAlign = 'right'; ctx.fillStyle = '#9fb0d0';
      ctx.fillText(currentId.toUpperCase(), W * 0.95, BAR * 0.5);
    }
  }

  // --- loop ---------------------------------------------------------------
  var last = now();
  function frame() {
    var t = now(); var dt = (t - last) / 1000; last = t;
    if (dt > 0.1) dt = 0.1; if (dt < 0) dt = 0;
    if (screen === 'menu') {
      menu.draw(ctx);
    } else if (current) {
      if (current.update) current.update(dt, t / 1000);
      ctx.save(); ctx.translate(0, BAR);
      // clip to game area so a game can't overdraw the bar
      ctx.beginPath(); ctx.rect(0, 0, W, H - BAR); ctx.clip();
      if (current.draw) current.draw(ctx);
      ctx.restore();
      drawBar();
    }
    platform.raf(frame);
  }
  platform.raf(frame);

  return { launch: launch, backToMenu: backToMenu };
}

module.exports = { createRouter: createRouter };
