// boot/loading.js — MAIN-PACKAGE loading screen. Draws a deep-space starfield +
// a progress bar on the platform canvas while the `engine` subpackage downloads.
//
// This file MUST live in the main package (it runs BEFORE the subpackage is
// available), so it is deliberately platform-free and depends on nothing under
// shared/ (which ships inside the subpackage). It only needs a 2D canvas and a
// requestAnimationFrame-like callback, both injected.
'use strict';

function createLoading(canvas, raf) {
  var ctx = canvas.getContext('2d');
  var W = canvas.width, H = canvas.height;
  var prog = 0, running = true, err = null;
  var frames = 0;

  // A tiny seeded starfield (no Math.random, so it's stable frame-to-frame).
  var seed = 20260707;
  function rnd() { seed = (seed * 1103515245 + 12345) & 0x7fffffff; return seed / 0x7fffffff; }
  var stars = [];
  for (var i = 0; i < 90; i++) {
    stars.push({ x: rnd() * W, y: rnd() * H, r: 0.5 + rnd() * 1.6, p: rnd() });
  }

  function draw() {
    if (!running) return;
    frames++;
    var t = frames / 60;

    var g = ctx.createLinearGradient(0, 0, 0, H);
    g.addColorStop(0, '#080b1a');
    g.addColorStop(0.55, '#0e1030');
    g.addColorStop(1, '#161042');
    ctx.fillStyle = g;
    ctx.fillRect(0, 0, W, H);

    for (var i = 0; i < stars.length; i++) {
      var s = stars[i];
      var a = 0.35 + 0.65 * Math.abs(Math.sin(t * 1.5 + s.p * 6.2832));
      ctx.globalAlpha = a;
      ctx.fillStyle = '#cfe4ff';
      ctx.beginPath();
      ctx.arc(s.x, s.y, s.r, 0, 6.2832);
      ctx.fill();
    }
    ctx.globalAlpha = 1;

    ctx.textAlign = 'center';
    ctx.textBaseline = 'alphabetic';
    ctx.fillStyle = '#eaf2ff';
    ctx.font = 'bold ' + Math.round(W * 0.095) + 'px sans-serif';
    ctx.fillText('TIME DODGE', W / 2, H * 0.42);

    ctx.fillStyle = err ? '#ff7a6b' : '#7fb0d8';
    ctx.font = Math.round(W * 0.036) + 'px sans-serif';
    ctx.fillText(err ? err : 'ENTERING ORBIT', W / 2, H * 0.42 + W * 0.085);

    // Progress bar.
    var bw = W * 0.62, bh = Math.max(6, W * 0.02);
    var bx = (W - bw) / 2, by = H * 0.56;
    ctx.strokeStyle = 'rgba(120,180,230,0.5)';
    ctx.lineWidth = 1.5;
    ctx.strokeRect(bx, by, bw, bh);
    var p = Math.max(0, Math.min(1, prog));
    ctx.fillStyle = err ? '#c0392b' : '#39d0ff';
    ctx.fillRect(bx + 1.5, by + 1.5, (bw - 3) * p, bh - 3);

    ctx.fillStyle = '#9fc4e8';
    ctx.font = Math.round(W * 0.032) + 'px sans-serif';
    ctx.fillText(Math.round(p * 100) + '%', W / 2, by + bh + W * 0.065);

    raf(draw);
  }
  raf(draw);

  return {
    setProgress: function (p) { prog = p; },
    setError: function (m) { err = m; },
    stop: function () { running = false; },
  };
}

module.exports = { createLoading: createLoading };
