// render.js — Canvas 2D rendering for TIME DODGE. Stateless: it draws purely
// from the game state each frame (starfield background, sci-fi HUD, rocks with
// 2.5D depth shading, the player orb + trail, menus, end cards, the cancel
// dialog). Nothing here mutates game state.
//
// World coords (origin centre, +y up) -> canvas pixels (origin top-left, +y
// down):  cx = SW + wx ,  cy = SH - wy   (SW/SH are half the canvas size).
'use strict';

var C = require('./config.js');

function rgba(c, a) {
  return 'rgba(' + Math.round(c[0] * 255) + ',' + Math.round(c[1] * 255) + ',' +
    Math.round(c[2] * 255) + ',' + (a === undefined ? 1 : a) + ')';
}

function createRenderer(ctx, W, H, juice, particles) {
  juice = juice || { trauma: 0, zoom: 0 };
  particles = particles || { draw: function () {} };
  // starfield: three parallax sub-layers (far dim/small -> near bright), fixed
  // field, twinkles with time. Plus a couple of static nebula blobs for depth.
  var stars = [];
  for (var i = 0; i < 130; i++) {
    var layer = i < 70 ? 0 : (i < 110 ? 1 : 2);
    stars.push({
      x: Math.random() * W, y: Math.random() * H,
      r: (layer === 0 ? 0.4 : layer === 1 ? 0.9 : 1.5) + Math.random() * 0.5,
      p: Math.random() * 6.28, l: layer,
    });
  }
  var nebula = [];
  for (var i = 0; i < 4; i++) {
    var cols = [[60, 40, 120], [30, 70, 120], [90, 40, 110], [24, 66, 96]];
    nebula.push({ x: Math.random() * W, y: Math.random() * H, r: 140 + Math.random() * 180, c: cols[i] });
  }
  var t0 = 0;
  var lastT = 0;

  // ---- little glyphs (replace ASCII '*' / '?' / 'BACK') --------------------
  function starGlyph(cx, cy, rad, color, alpha) {
    ctx.save();
    ctx.beginPath();
    for (var k = 0; k < 10; k++) {
      var a = -Math.PI / 2 + k * Math.PI / 5;
      var rr = (k % 2 === 0) ? rad : rad * 0.45;
      var px = cx + Math.cos(a) * rr, py = cy + Math.sin(a) * rr;
      if (k === 0) ctx.moveTo(px, py); else ctx.lineTo(px, py);
    }
    ctx.closePath();
    ctx.fillStyle = rgba(color, alpha === undefined ? 1 : alpha);
    ctx.fill();
    ctx.restore();
  }
  function lockGlyph(cx, cy, s, alpha) {
    ctx.save();
    ctx.strokeStyle = 'rgba(200,210,230,' + (alpha || 0.5) + ')';
    ctx.fillStyle = 'rgba(200,210,230,' + (alpha || 0.5) + ')';
    ctx.lineWidth = Math.max(1.5, s * 0.16);
    ctx.beginPath(); ctx.arc(cx, cy - s * 0.15, s * 0.5, Math.PI, 0); ctx.stroke(); // shackle
    var bw = s * 1.2, bh = s * 0.85;
    ctx.beginPath();
    ctx.rect(cx - bw / 2, cy - s * 0.15, bw, bh);
    ctx.fill();
    ctx.restore();
  }
  function gearGlyph(cx, cy, r, alpha) {
    ctx.save();
    var col = 'rgba(205,218,245,' + (alpha === undefined ? 0.85 : alpha) + ')';
    ctx.strokeStyle = col; ctx.lineWidth = Math.max(2, r * 0.22);
    for (var i = 0; i < 8; i++) {
      var a = i * Math.PI / 4;
      ctx.beginPath();
      ctx.moveTo(cx + Math.cos(a) * r * 0.8, cy + Math.sin(a) * r * 0.8);
      ctx.lineTo(cx + Math.cos(a) * r * 1.25, cy + Math.sin(a) * r * 1.25);
      ctx.stroke();
    }
    ctx.beginPath(); ctx.arc(cx, cy, r * 0.8, 0, 6.2832); ctx.stroke();
    ctx.beginPath(); ctx.arc(cx, cy, r * 0.32, 0, 6.2832); ctx.stroke();
    ctx.restore();
  }
  function pauseGlyph(cx, cy, s, alpha) {
    ctx.save();
    ctx.fillStyle = 'rgba(10,16,30,0.5)';
    ctx.beginPath(); ctx.arc(cx, cy, s * 1.35, 0, 6.2832); ctx.fill();
    ctx.fillStyle = 'rgba(225,238,255,' + (alpha === undefined ? 0.92 : alpha) + ')';
    ctx.fillRect(cx - s * 0.55, cy - s, s * 0.42, s * 2);
    ctx.fillRect(cx + s * 0.13, cy - s, s * 0.42, s * 2);
    ctx.restore();
  }
  // one settings toggle row: label left, ON/OFF pill = the tappable rect r.
  function toggleRow(SW, SH, r, label, on) {
    text(toX(SW, -68), toY(SH, r.y), 17, [0.82, 0.9, 1.0], label);
    var base = on ? [0.18, 0.60, 0.42] : [0.30, 0.32, 0.40];
    panel(SW, SH, r, rgba(base, 1), 'rgba(255,255,255,0.18)');
    text(toX(SW, r.x), toY(SH, r.y), 16, [1, 1, 1], on ? 'ON' : 'OFF');
  }
  function settingsOverlay(game) {
    var G = game.state, SW = G.SW, SH = G.SH, o = G.opt, U = G.ui;
    ctx.fillStyle = 'rgba(0,0,0,0.72)'; ctx.fillRect(0, 0, W, H);
    panel(SW, SH, { x: 0, y: -8, w: 320, h: 300 }, 'rgba(20,26,42,0.98)', 'rgba(120,170,255,0.4)');
    text(SW, toY(SH, 108), 26, [1, 1, 1], 'SETTINGS');
    toggleRow(SW, SH, U.setSound, 'SOUND', o.sound);
    toggleRow(SW, SH, U.setHaptic, 'VIBRATION', o.haptic);
    button(SW, SH, U.setClose, 'CLOSE', [0.24, 0.30, 0.42]);
  }
  function pauseOverlay(game) {
    var G = game.state, SW = G.SW, SH = G.SH, U = G.ui;
    ctx.fillStyle = 'rgba(0,0,0,0.72)'; ctx.fillRect(0, 0, W, H);
    text(SW, toY(SH, 150), 30, [1, 1, 1], 'PAUSED');
    button(SW, SH, U.pResume, 'RESUME', [0.18, 0.60, 0.40]);
    button(SW, SH, U.pRestart, 'RESTART', [0.24, 0.34, 0.50]);
    button(SW, SH, U.pHome, 'HOME', [0.30, 0.32, 0.42]);
  }

  function toX(SW, wx) { return SW + wx; }
  function toY(SH, wy) { return SH - wy; }

  function bg(SW, SH, time) {
    t0 = time;
    // deep void gradient (over-filled so screen-shake never exposes black edges)
    var g = ctx.createLinearGradient(0, 0, 0, H);
    g.addColorStop(0, '#04050d');
    g.addColorStop(0.55, '#080a18');
    g.addColorStop(1, '#0c0a1e');
    ctx.fillStyle = g;
    ctx.fillRect(-24, -24, W + 48, H + 48);
    // soft nebula clouds, drifting slowly (additive so they glow, not muddy)
    ctx.save();
    ctx.globalCompositeOperation = 'lighter';
    for (var m = 0; m < nebula.length; m++) {
      var nb = nebula[m];
      var dx = Math.sin(time * 0.05 + m) * 14, dy = Math.cos(time * 0.04 + m) * 12;
      var ng = ctx.createRadialGradient(nb.x + dx, nb.y + dy, 0, nb.x + dx, nb.y + dy, nb.r);
      ng.addColorStop(0, 'rgba(' + nb.c[0] + ',' + nb.c[1] + ',' + nb.c[2] + ',0.16)');
      ng.addColorStop(1, 'rgba(' + nb.c[0] + ',' + nb.c[1] + ',' + nb.c[2] + ',0)');
      ctx.fillStyle = ng;
      ctx.beginPath(); ctx.arc(nb.x + dx, nb.y + dy, nb.r, 0, 6.2832); ctx.fill();
    }
    // parallax twinkling stars (additive)
    for (var i = 0; i < stars.length; i++) {
      var s = stars[i];
      var tw = (s.l === 0 ? 0.3 : 0.5) + 0.5 * (0.5 + 0.5 * Math.sin(time * (1.4 + s.l) + s.p));
      var drift = time * (2 + s.l * 4);
      var yy = (s.y + drift) % (H + 8);
      ctx.fillStyle = 'rgba(200,220,255,' + tw.toFixed(3) + ')';
      ctx.beginPath(); ctx.arc(s.x, yy, s.r, 0, 6.2832); ctx.fill();
    }
    ctx.restore();
  }

  // Final full-screen pass: freeze wash (keyed off timescale) + vignette + grade.
  function postFx(G) {
    var ts = (G.mode === 'run' && G.S) ? G.S.ts : 1;
    // freeze wash: as time freezes (ts->0), a pale cyan frost creeps in
    var frost = (1 - ts);
    if (frost > 0.02) {
      ctx.save();
      ctx.globalCompositeOperation = 'lighter';
      ctx.fillStyle = 'rgba(90,150,190,' + (0.10 * frost).toFixed(3) + ')';
      ctx.fillRect(0, 0, W, H);
      ctx.restore();
    }
    // vignette (multiply-ish darken at edges) — the single biggest cinematic win
    var vg = ctx.createRadialGradient(W / 2, H / 2, H * 0.32, W / 2, H / 2, H * 0.75);
    vg.addColorStop(0, 'rgba(0,0,0,0)');
    vg.addColorStop(1, 'rgba(0,0,0,0.55)');
    ctx.fillStyle = vg;
    ctx.fillRect(0, 0, W, H);
    // frozen edge tint (cool the corners a touch when frozen)
    if (frost > 0.3) {
      var fv = ctx.createRadialGradient(W / 2, H / 2, H * 0.30, W / 2, H / 2, H * 0.78);
      fv.addColorStop(0, 'rgba(120,180,220,0)');
      fv.addColorStop(1, 'rgba(120,180,220,' + (0.14 * frost).toFixed(3) + ')');
      ctx.fillStyle = fv; ctx.fillRect(0, 0, W, H);
    }
  }

  function text(x, y, size, color, str, alpha) {
    ctx.fillStyle = rgba(color, alpha === undefined ? 1 : alpha);
    ctx.font = '700 ' + size + 'px -apple-system, "PingFang SC", system-ui, sans-serif';
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    ctx.fillText(str, x, y);
  }

  function panel(SW, SH, r, fill, stroke) {
    var x = toX(SW, r.x) - r.w / 2, y = toY(SH, r.y) - r.h / 2;
    var rad = Math.min(14, r.h / 2);
    ctx.beginPath();
    ctx.moveTo(x + rad, y);
    ctx.arcTo(x + r.w, y, x + r.w, y + r.h, rad);
    ctx.arcTo(x + r.w, y + r.h, x, y + r.h, rad);
    ctx.arcTo(x, y + r.h, x, y, rad);
    ctx.arcTo(x, y, x + r.w, y, rad);
    ctx.closePath();
    ctx.fillStyle = fill;
    ctx.fill();
    if (stroke) { ctx.strokeStyle = stroke; ctx.lineWidth = 1.5; ctx.stroke(); }
  }

  var curGame = null;  // set each frame in draw(), for button press feedback
  function isPressed(r) {
    if (!curGame) return false;
    var inp = curGame.state.input;
    return inp && inp.down && inp.x !== null && curGame.inRect(r, inp.x, inp.y);
  }
  function button(SW, SH, r, label, base) {
    var pressed = isPressed(r);
    var k = pressed ? 0.94 : 1;                 // scale-down on press
    var rr = { x: r.x, y: r.y, w: r.w * k, h: r.h * k };
    var cx = toX(SW, r.x), cy = toY(SH, r.y);
    var fill = pressed ? [Math.min(1, base[0] * 1.25 + 0.05), Math.min(1, base[1] * 1.25 + 0.05), Math.min(1, base[2] * 1.25 + 0.05)] : base;
    panel(SW, SH, rr, rgba(fill, 1), pressed ? 'rgba(255,255,255,0.5)' : 'rgba(255,255,255,0.14)');
    text(cx, cy, Math.min(26, r.h * 0.42) * k, [1, 1, 1], label);
  }

  // A stable irregular low-poly outline per rock, generated once and cached on
  // the foe object (cosmetic only). Deterministic so the facets don't shimmer.
  function rockShape(b) {
    if (b._rock) return b._rock;
    var seed = ((Math.abs(b.spin || 0) * 1000 + (b.size || 10) * 97 + (b.kind ? b.kind.length : 3) * 31) | 0) % 233280;
    if (seed <= 0) seed = 45137;
    function rnd() { seed = (seed * 9301 + 49297) % 233280; return seed / 233280; }
    var n = 8 + Math.floor(rnd() * 4);         // 8..11 vertices -> chunky facets
    var r = [], tone = [];
    for (var k = 0; k < n; k++) {
      r.push(0.60 + rnd() * 0.55);             // irregular radius 0.60..1.15
      tone.push(0.82 + rnd() * 0.34);          // per-facet material variation
    }
    b._rock = { n: n, r: r, tone: tone };
    return b._rock;
  }

  // Faceted "3D" asteroid: an irregular polygon fanned into triangles, each
  // facet shaded by its outward normal vs a screen-fixed light (upper-left),
  // plus a lit rim + a soft specular pop. Reads as an angular rock, not a ball.
  function drawRock(SW, SH, b, color) {
    var cx = toX(SW, b.x), cy = toY(SH, b.y);
    var rad = (b.sc || b.size) * 0.5;
    var sh = rockShape(b), n = sh.n;
    var rot = b.rot || 0;
    // Screen-fixed light (upper-left) expressed in the rock's local frame.
    var LWx = -0.7071, LWy = -0.7071, cr = Math.cos(-rot), sr = Math.sin(-rot);
    var lx = LWx * cr - LWy * sr, ly = LWx * sr + LWy * cr;

    ctx.save();
    ctx.translate(cx, cy);
    ctx.rotate(rot);
    var vx = [], vy = [];
    for (var k = 0; k < n; k++) {
      var a = (k / n) * 6.2832, rr = rad * sh.r[k];
      vx.push(Math.cos(a) * rr); vy.push(Math.sin(a) * rr);
    }
    // Per-facet shaded triangles (fan from centroid).
    for (var k = 0; k < n; k++) {
      var k2 = (k + 1) % n;
      var mx = (vx[k] + vx[k2]) * 0.5, my = (vy[k] + vy[k2]) * 0.5;
      var ml = Math.hypot(mx, my) || 1;
      var ndot = (mx / ml) * lx + (my / ml) * ly;      // -1..1
      var lit = (0.30 + 0.75 * Math.max(0, ndot)) * sh.tone[k];
      ctx.beginPath();
      ctx.moveTo(0, 0);
      ctx.lineTo(vx[k], vy[k]);
      ctx.lineTo(vx[k2], vy[k2]);
      ctx.closePath();
      ctx.fillStyle = rgba([color[0] * lit, color[1] * lit, color[2] * lit], 1);
      ctx.fill();
      // faint facet seam for crystalline definition
      ctx.strokeStyle = 'rgba(0,0,0,0.28)';
      ctx.lineWidth = 0.6;
      ctx.stroke();
    }
    // Lit outer rim.
    ctx.beginPath();
    for (var k = 0; k < n; k++) { if (k === 0) ctx.moveTo(vx[k], vy[k]); else ctx.lineTo(vx[k], vy[k]); }
    ctx.closePath();
    ctx.strokeStyle = 'rgba(255,255,255,0.18)';
    ctx.lineWidth = 1.1;
    ctx.stroke();
    // Soft specular pop toward the light.
    if (rad > 6) {
      var sx = lx * rad * 0.45, sy = ly * rad * 0.45;
      var sg = ctx.createRadialGradient(sx, sy, 0, sx, sy, rad * 0.6);
      sg.addColorStop(0, 'rgba(255,255,255,0.22)');
      sg.addColorStop(1, 'rgba(255,255,255,0)');
      ctx.fillStyle = sg;
      ctx.beginPath(); ctx.arc(sx, sy, rad * 0.6, 0, 6.2832); ctx.fill();
    }
    ctx.restore();
  }

  // The player: same low-poly faceted style as the rocks (so the whole scene
  // reads as one material language across all three modes) — but emissive: a
  // bright cyan crystal with a glow halo + core, so it's unmistakably "you".
  function drawPlayer(SW, SH, S, time) {
    var pcx = toX(SW, S.px), pcy = toY(SH, S.py), pr = S.mass * 0.5;
    var tsf = S.ts;
    // glow halo
    var hg = ctx.createRadialGradient(pcx, pcy, pr * 0.3, pcx, pcy, pr * 2.1);
    hg.addColorStop(0, 'rgba(150,235,255,0.45)');
    hg.addColorStop(1, 'rgba(120,220,255,0)');
    ctx.fillStyle = hg;
    ctx.beginPath(); ctx.arc(pcx, pcy, pr * 2.1, 0, 6.2832); ctx.fill();
    // cached irregular crystal outline
    if (!S._prock) {
      var seed = 917;
      var rnd = function () { seed = (seed * 9301 + 49297) % 233280; return seed / 233280; };
      var nn = 9, rr = [], tn = [];
      for (var q = 0; q < nn; q++) { rr.push(0.72 + rnd() * 0.34); tn.push(0.9 + rnd() * 0.2); }
      S._prock = { n: nn, r: rr, tone: tn };
    }
    var sh = S._prock, n = sh.n, rot = time * 0.5;
    var LWx = -0.7071, LWy = -0.7071, cr = Math.cos(-rot), sr = Math.sin(-rot);
    var lx = LWx * cr - LWy * sr, ly = LWx * sr + LWy * cr;
    var base = [0.60 + 0.4 * tsf, 0.95, 1.0];   // cooler/bluer when frozen
    ctx.save();
    ctx.translate(pcx, pcy);
    ctx.rotate(rot);
    var vx = [], vy = [];
    for (var k = 0; k < n; k++) { var a = (k / n) * 6.2832, r2 = pr * sh.r[k]; vx.push(Math.cos(a) * r2); vy.push(Math.sin(a) * r2); }
    for (var k = 0; k < n; k++) {
      var k2 = (k + 1) % n, mx = (vx[k] + vx[k2]) * 0.5, my = (vy[k] + vy[k2]) * 0.5, ml = Math.hypot(mx, my) || 1;
      var ndot = (mx / ml) * lx + (my / ml) * ly;
      var lit = (0.66 + 0.34 * Math.max(0, ndot)) * sh.tone[k];  // high ambient -> emissive
      ctx.beginPath(); ctx.moveTo(0, 0); ctx.lineTo(vx[k], vy[k]); ctx.lineTo(vx[k2], vy[k2]); ctx.closePath();
      ctx.fillStyle = rgba([Math.min(1, base[0] * lit), Math.min(1, base[1] * lit), Math.min(1, base[2] * lit)], 1);
      ctx.fill();
      ctx.strokeStyle = 'rgba(255,255,255,0.32)'; ctx.lineWidth = 0.7; ctx.stroke();
    }
    var cg = ctx.createRadialGradient(0, 0, 0, 0, 0, pr * 0.72);
    cg.addColorStop(0, 'rgba(255,255,255,0.85)');
    cg.addColorStop(1, 'rgba(255,255,255,0)');
    ctx.fillStyle = cg; ctx.beginPath(); ctx.arc(0, 0, pr * 0.72, 0, 6.2832); ctx.fill();
    ctx.restore();
  }

  function frozenTint(c, ts) {
    var k = (1 - ts) * 0.55;
    return [c[0] + (C.FROZEN_C[0] - c[0]) * k,
            c[1] + (C.FROZEN_C[1] - c[1]) * k,
            c[2] + (C.FROZEN_C[2] - c[2]) * k];
  }

  function drawRun(game, time) {
    var G = game.state, S = G.S, SW = G.SW, SH = G.SH;
    // trail (additive light-streak)
    ctx.save();
    ctx.globalCompositeOperation = 'lighter';
    for (var i = 0; i < S.trail.length; i++) {
      var tr = S.trail[i];
      if (tr.a > 0.02) {
        ctx.fillStyle = 'rgba(120,210,255,' + (tr.a * 0.9).toFixed(3) + ')';
        ctx.beginPath();
        ctx.arc(toX(SW, tr.x), toY(SH, tr.y), C.PLAYER * 0.34, 0, 6.2832);
        ctx.fill();
      }
    }
    ctx.restore();
    // trial gate (portal: two additive rings + inner glow)
    if (S.trial && S.gate) {
      var pulse = 0.7 + 0.3 * Math.sin((S.elapsed || 0) * 6);
      var gx = toX(SW, S.gate.x), gy = toY(SH, S.gate.y);
      ctx.save();
      ctx.globalCompositeOperation = 'lighter';
      ctx.strokeStyle = 'rgba(128,242,255,' + pulse.toFixed(3) + ')';
      ctx.lineWidth = 3;
      ctx.beginPath(); ctx.arc(gx, gy, C.GATE * 0.55, 0, 6.2832); ctx.stroke();
      ctx.strokeStyle = 'rgba(200,250,255,' + (pulse * 0.5).toFixed(3) + ')';
      ctx.lineWidth = 1.4;
      ctx.beginPath(); ctx.arc(gx, gy, C.GATE * (0.42 + 0.05 * Math.sin(time * 4)), 0, 6.2832); ctx.stroke();
      var igg = ctx.createRadialGradient(gx, gy, 0, gx, gy, C.GATE * 0.4);
      igg.addColorStop(0, 'rgba(128,242,255,' + (pulse * 0.4).toFixed(3) + ')');
      igg.addColorStop(1, 'rgba(128,242,255,0)');
      ctx.fillStyle = igg; ctx.beginPath(); ctx.arc(gx, gy, C.GATE * 0.4, 0, 6.2832); ctx.fill();
      ctx.restore();
    }
    // foes (far/dim first)
    var ordered = S.bullets.slice().sort(function (a, b) { return b.z - a.z; });
    for (var f = 0; f < ordered.length; f++) {
      var b = ordered[f];
      var kd = C.KINDS[b.kind];
      var c = kd.c;
      if (S.absorb) c = (b.size <= S.mass) ? C.SAFE_C : C.DANGER_C;
      var depth = 1 - b.z;
      var br = 0.45 + 0.55 * depth;
      var ft = frozenTint(c, S.ts);
      drawRock(SW, SH, b, [ft[0] * br, ft[1] * br, ft[2] * br]);
    }
    // particles (additive) sit above rocks, below the player + HUD
    particles.draw(ctx, toX, toY, SW, SH);
    // player — faceted emissive crystal (same style language as the rocks)
    drawPlayer(SW, SH, S, time);

    hud(game);
    if (!S.playing && S.card) endCard(game);
    if (S.hit_dialog) dialog(game);
  }

  function hud(game) {
    var G = game.state, S = G.S, SW = G.SW, SH = G.SH;
    var frozen = S.ts < 0.15;
    var primary, secondary;
    if (S.absorb) { primary = 'MASS ' + Math.floor(S.mass); secondary = 'EATEN ' + S.eaten; }
    else if (S.trial) {
      var lv = C.LEVELS[S.trial - 1];
      primary = S.elapsed.toFixed(1) + 's';
      secondary = 'MOMENT ' + S.trial + '   GATE ' + S.gate_i + '/' + lv.gates;
    } else if (S.ann_t > 0) { primary = S.score.toFixed(1) + 's'; secondary = S.ann; }
    else { primary = S.score.toFixed(1) + 's'; secondary = 'STOLEN'; }
    // header band
    ctx.fillStyle = 'rgba(5,8,20,0.42)';
    ctx.fillRect(0, 0, W, 100);
    text(SW, 40, 28, [1, 1, 1], primary);
    text(SW, 70, 14, [0.72, 0.82, 1.0], secondary);
    if (frozen) text(SW, 90, 12, [0.55, 0.85, 1.0], '- FROZEN -');
    // pause button (oversized, top-right) while the run is live
    if (G.btn.pause && S.playing && !S.paused) {
      var pr = G.btn.pause;
      pauseGlyph(toX(SW, pr.x), toY(SH, pr.y), 8);
    }
  }

  function endCard(game) {
    var G = game.state, S = G.S, SW = G.SW, SH = G.SH;
    ctx.fillStyle = 'rgba(0,0,0,0.62)';
    ctx.fillRect(0, 0, W, H);
    panel(SW, SH, { x: 0, y: 10, w: 360, h: 214 }, 'rgba(23,28,43,0.97)', 'rgba(90,160,255,0.4)');
    ctx.fillStyle = 'rgba(90,178,255,1)';
    ctx.fillRect(toX(SW, -180), toY(SH, 106) - 3, 360, 6);
    text(SW, toY(SH, 68), 29, [1, 1, 1], S.cardTitle);
    if (S.cardSub) text(SW, toY(SH, 24), 16, [0.8, 0.88, 1.0], S.cardSub);
    // NEW BEST! stamp when this run set a record (rotated gold badge).
    if (S.newBest) {
      var bx = toX(SW, 120), by = toY(SH, 92);
      ctx.save();
      ctx.translate(bx, by); ctx.rotate(-0.18);
      ctx.globalCompositeOperation = 'lighter';
      starGlyph(0, 0, 26, [1, 0.8, 0.25], 0.9);
      ctx.restore();
      text(bx, by, 10, [0.15, 0.1, 0.0], 'NEW');
      text(bx, by + 11, 9, [0.15, 0.1, 0.0], 'BEST');
    }
    for (var i = 0; i < S.card.length; i++) {
      var b = S.card[i];
      button(SW, SH, b.rect, b.label, b.primary ? [0.20, 0.62, 0.35] : [0.24, 0.30, 0.42]);
    }
  }

  function dialog(game) {
    var G = game.state, S = G.S, SW = G.SW, SH = G.SH, hd = S.hit_dialog;
    ctx.fillStyle = 'rgba(0,0,0,0.8)';
    ctx.fillRect(0, 0, W, H);
    panel(SW, SH, { x: 0, y: 0, w: 360, h: 250 }, 'rgba(26,31,46,1)', 'rgba(120,160,255,0.4)');
    text(SW, toY(SH, 75), 26, [1, 1, 1], 'CANCEL THIS HIT?');
    text(SW, toY(SH, 40), 14, [0.75, 0.85, 1.0], 'watch a sponsor clip to absorb it');
    button(SW, SH, hd.yes, 'YES', [0.20, 0.62, 0.35]);
    button(SW, SH, hd.no, 'NO', [0.70, 0.25, 0.22]);
  }

  function drawSelect(game) {
    var G = game.state, SW = G.SW, SH = G.SH;
    text(SW, toY(SH, 210), 44, [1, 1, 1], 'TIME DODGE');
    text(SW, toY(SH, 150), 15, [0.75, 0.85, 1.0], 'Hold: time flows.  Release: the world freezes.');
    text(SW, toY(SH, 124), 14, [0.75, 0.85, 1.0], 'Every second you hold on is a second stolen back.');
    // player records (persisted but never shown before) — a reason to return.
    if (game.bests) {
      var bs = game.bests();
      var cyv = toY(SH, 96);
      text(SW - 96, cyv, 12, [0.55, 0.7, 0.95], 'BEST');
      text(SW - 96, cyv + 17, 15, [0.9, 0.96, 1.0], bs.endless.toFixed(1) + 's');
      starGlyph(SW - 2, cyv - 3, 7, [1, 0.85, 0.4], 1);
      text(SW + 14, cyv, 15, [1, 0.9, 0.5], bs.stars + '/' + bs.maxStars);
      text(SW + 96, cyv, 12, [0.55, 0.7, 0.95], 'MASS');
      text(SW + 96, cyv + 17, 15, [0.9, 0.96, 1.0], String(Math.floor(bs.absorb)));
    }
    var b = G.btn;
    button(SW, SH, b.endless, 'ENDLESS', [0.75, 0.22, 0.20]);
    text(SW, toY(SH, b.endless.y - 22), 13, [1, 0.85, 0.8], 'steal as long as you can');
    button(SW, SH, b.trials, 'TRIALS', [0.20, 0.55, 0.70]);
    text(SW, toY(SH, b.trials.y - 22), 13, [0.8, 0.95, 1.0], 'ten sealed moments to break');
    button(SW, SH, b.absorb, 'ABSORB', [0.45, 0.28, 0.70]);
    text(SW, toY(SH, b.absorb.y - 22), 13, [0.85, 0.8, 1.0], 'eat the small - fear the big');
    if (b.gear) gearGlyph(toX(SW, b.gear.x), toY(SH, b.gear.y), 13);
  }

  function drawLevels(game) {
    var G = game.state, SW = G.SW, SH = G.SH;
    text(SW, toY(SH, 270), 30, [1, 1, 1], 'SEALED MOMENTS');
    text(SW, toY(SH, 224), 13, [0.75, 0.85, 1.0], 'release to freeze - the clock only forgives the dead');
    for (var i = 0; i < G.btn.levels.length; i++) {
      var r = G.btn.levels[i], open = game.unlocked(r.i);
      var base = open ? [0.20, 0.55, 0.70] : [0.28, 0.30, 0.36];
      panel(SW, SH, r, rgba(base, 1), 'rgba(255,255,255,0.12)');
      var cx = toX(SW, r.x), cy = toY(SH, r.y);
      if (open) {
        text(cx, cy - 12, 26, [1, 1, 1], String(r.i), 1);
        var sc = game.starsOf(r.i);
        for (var s = 0; s < 3; s++) {
          var lit = s < sc;
          starGlyph(cx + (s - 1) * 15, cy + 20, 6, lit ? [1, 0.85, 0.4] : [0.4, 0.44, 0.55], lit ? 1 : 0.6);
        }
      } else {
        text(cx, cy - 12, 26, [1, 1, 1], String(r.i), 0.35);
        lockGlyph(cx, cy + 16, 8, 0.55);
      }
    }
    if (G.btn.back) button(SW, SH, G.btn.back, 'BACK', [0.30, 0.32, 0.40]);
  }

  function draw(game, time) {
    var G = game.state;
    curGame = game;
    // Decay the shared shake/zoom trauma (time-based so it's frame-rate stable).
    var dt = time - lastT; lastT = time;
    if (dt < 0 || dt > 0.1) dt = 0.016;
    juice.trauma = Math.max(0, juice.trauma - dt * 1.6);
    juice.zoom = Math.max(0, juice.zoom - dt * 2.4);
    var tr = juice.trauma * juice.trauma;      // trauma² feels right
    var amp = 18 * tr;
    var sx = (Math.random() * 2 - 1) * amp, sy = (Math.random() * 2 - 1) * amp;
    var zs = 1 + 0.06 * juice.zoom;            // slight punch-in on impacts

    ctx.save();
    if (zs !== 1) { ctx.translate(W / 2, H / 2); ctx.scale(zs, zs); ctx.translate(-W / 2, -H / 2); }
    if (amp > 0.1) ctx.translate(sx, sy);
    bg(G.SW, G.SH, time);
    if (G.mode === 'select') drawSelect(game);
    else if (G.mode === 'levels') drawLevels(game);
    else if (G.mode === 'run' && G.S) drawRun(game, time);
    ctx.restore();
    // full-screen grade sits OUTSIDE the shake transform so edges stay clean
    postFx(G);
    // overlays sit on top of everything (incl. the vignette)
    if (G.overlay === 'settings') settingsOverlay(game);
    else if (G.mode === 'run' && G.S && G.S.paused) pauseOverlay(game);
  }

  return { draw: draw };
}

module.exports = { createRenderer: createRenderer };
