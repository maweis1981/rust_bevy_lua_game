// particles.js — a tiny pooled particle system. The game core already calls
// emit('spark'|'shatter'|'confetti', x, y) on eats / gates / deaths / clears,
// but nothing rendered it. main.js wires platform.emit -> burst(); the renderer
// draws them additively (globalCompositeOperation='lighter') so sparks glow.
// World coords (origin centre, +y UP); the renderer converts to canvas px.
'use strict';

function createParticles(cap) {
  cap = cap || 240;
  var pool = [];
  for (var i = 0; i < cap; i++) pool.push({ x: 0, y: 0, vx: 0, vy: 0, life: 0, max: 1, size: 1, r: 255, g: 255, b: 255, mode: 0 });
  var live = 0;

  function spawn(x, y, vx, vy, life, size, col, mode) {
    if (live >= cap) return;
    var p = pool[live++];
    p.x = x; p.y = y; p.vx = vx; p.vy = vy; p.life = life; p.max = life;
    p.size = size; p.r = col[0]; p.g = col[1]; p.b = col[2]; p.mode = mode || 0;
  }
  function rnd() { return Math.random(); }

  // preset bursts. mode: 0=drag, 1=implode(no drag), 2=shards+drag, 3=confetti(gravity)
  function burst(preset, x, y, opts) {
    opts = opts || {};
    var n, i, a, sp, col;
    if (preset === 'spark') {
      col = opts.col || [150, 230, 255];
      n = 10; for (i = 0; i < n; i++) { a = rnd() * 6.2832; sp = 70 + rnd() * 150; spawn(x, y, Math.cos(a) * sp, Math.sin(a) * sp, 0.35 + rnd() * 0.3, 2 + rnd() * 2, col, 0); }
    } else if (preset === 'absorb') {
      col = opts.col || [150, 255, 210];
      n = 16; for (i = 0; i < n; i++) { a = (i / n) * 6.2832; sp = 90 + rnd() * 70; spawn(x + Math.cos(a) * 22, y + Math.sin(a) * 22, -Math.cos(a) * sp, -Math.sin(a) * sp, 0.45, 3, col, 1); }
    } else if (preset === 'shatter') {
      col = opts.col || [255, 190, 160];
      n = 20; for (i = 0; i < n; i++) { a = rnd() * 6.2832; sp = 90 + rnd() * 200; spawn(x, y, Math.cos(a) * sp, Math.sin(a) * sp, 0.6 + rnd() * 0.5, 3 + rnd() * 3, col, 2); }
    } else if (preset === 'confetti') {
      n = 30; var cols = [[255, 210, 90], [130, 240, 255], [255, 130, 170], [160, 255, 160]];
      for (i = 0; i < n; i++) { col = cols[Math.floor(rnd() * 4)]; spawn(x, y, (rnd() * 2 - 1) * 130, 120 + rnd() * 170, 0.9 + rnd() * 0.6, 3 + rnd() * 3, col, 3); }
    }
  }

  function update(dt) {
    for (var i = 0; i < live; i++) {
      var p = pool[i];
      p.life -= dt;
      if (p.life <= 0) { var t = pool[i]; pool[i] = pool[live - 1]; pool[live - 1] = t; live--; i--; continue; }
      p.x += p.vx * dt; p.y += p.vy * dt;
      if (p.mode !== 1) { p.vx *= 0.90; p.vy *= 0.90; }  // drag
      if (p.mode === 3) p.vy -= 300 * dt;                // gravity (world +y up)
    }
  }

  function draw(ctx, toX, toY, SW, SH) {
    if (live === 0) return;
    ctx.save();
    ctx.globalCompositeOperation = 'lighter';
    for (var i = 0; i < live; i++) {
      var p = pool[i], k = p.life / p.max; if (k < 0) k = 0;
      ctx.globalAlpha = k;
      ctx.fillStyle = 'rgb(' + p.r + ',' + p.g + ',' + p.b + ')';
      var s = p.size * (0.4 + 0.6 * k);
      ctx.beginPath(); ctx.arc(toX(SW, p.x), toY(SH, p.y), s, 0, 6.2832); ctx.fill();
    }
    ctx.restore();
    ctx.globalAlpha = 1;
  }

  return { burst: burst, update: update, draw: draw, count: function () { return live; } };
}

module.exports = { createParticles: createParticles };
