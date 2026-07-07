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

function createRenderer(ctx, W, H) {
  // starfield: fixed field, twinkles with time.
  var stars = [];
  for (var i = 0; i < 90; i++) {
    stars.push({ x: Math.random() * W, y: Math.random() * H, r: Math.random() * 1.4 + 0.3, p: Math.random() * 6.28 });
  }
  var t0 = 0;

  function toX(SW, wx) { return SW + wx; }
  function toY(SH, wy) { return SH - wy; }

  function bg(SW, SH, time) {
    t0 = time;
    var g = ctx.createLinearGradient(0, 0, 0, H);
    g.addColorStop(0, '#05060f');
    g.addColorStop(1, '#0a0a18');
    ctx.fillStyle = g;
    ctx.fillRect(0, 0, W, H);
    for (var i = 0; i < stars.length; i++) {
      var s = stars[i];
      var tw = 0.4 + 0.6 * (0.5 + 0.5 * Math.sin(time * 2 + s.p));
      ctx.fillStyle = 'rgba(180,205,255,' + tw.toFixed(3) + ')';
      ctx.beginPath();
      ctx.arc(s.x, s.y, s.r, 0, 6.2832);
      ctx.fill();
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

  function button(SW, SH, r, label, base) {
    var cx = toX(SW, r.x), cy = toY(SH, r.y);
    panel(SW, SH, r, rgba(base, 1), 'rgba(255,255,255,0.14)');
    text(cx, cy, Math.min(26, r.h * 0.42), [1, 1, 1], label);
  }

  function drawRock(SW, SH, b, color) {
    var cx = toX(SW, b.x), cy = toY(SH, b.y);
    var rad = (b.sc || b.size) * 0.5;
    // angular 2.5D look: a rotated polygon with a lit rim.
    var n = 7;
    ctx.save();
    ctx.translate(cx, cy);
    ctx.rotate(b.rot || 0);
    ctx.beginPath();
    for (var k = 0; k < n; k++) {
      var a = (k / n) * 6.2832;
      var rr = rad * (0.82 + 0.18 * Math.sin(k * 2.3 + (b.spin || 0)));
      var px = Math.cos(a) * rr, py = Math.sin(a) * rr;
      if (k === 0) ctx.moveTo(px, py); else ctx.lineTo(px, py);
    }
    ctx.closePath();
    ctx.fillStyle = rgba(color, 1);
    ctx.fill();
    ctx.strokeStyle = 'rgba(255,255,255,0.25)';
    ctx.lineWidth = 1;
    ctx.stroke();
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
    // trail
    for (var i = 0; i < S.trail.length; i++) {
      var tr = S.trail[i];
      if (tr.a > 0.02) {
        ctx.fillStyle = 'rgba(180,230,255,' + (tr.a).toFixed(3) + ')';
        ctx.beginPath();
        ctx.arc(toX(SW, tr.x), toY(SH, tr.y), C.PLAYER * 0.32, 0, 6.2832);
        ctx.fill();
      }
    }
    // trial gate
    if (S.trial && S.gate) {
      var pulse = 0.7 + 0.3 * Math.sin((S.elapsed || 0) * 6);
      var gx = toX(SW, S.gate.x), gy = toY(SH, S.gate.y);
      ctx.strokeStyle = 'rgba(128,242,255,' + pulse.toFixed(3) + ')';
      ctx.lineWidth = 3;
      ctx.beginPath(); ctx.arc(gx, gy, C.GATE * 0.55, 0, 6.2832); ctx.stroke();
      ctx.fillStyle = 'rgba(128,242,255,' + (pulse * 0.35).toFixed(3) + ')';
      ctx.beginPath(); ctx.arc(gx, gy, C.GATE * 0.32, 0, 6.2832); ctx.fill();
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
    // player orb
    var pc = [1 - (1 - S.ts) * 0.3, 1, 1];
    var pcx = toX(SW, S.px), pcy = toY(SH, S.py), pr = S.mass * 0.5;
    var grad = ctx.createRadialGradient(pcx, pcy, 1, pcx, pcy, pr);
    grad.addColorStop(0, 'rgba(255,255,255,0.95)');
    grad.addColorStop(1, rgba(pc, 0.85));
    ctx.fillStyle = grad;
    ctx.beginPath(); ctx.arc(pcx, pcy, pr, 0, 6.2832); ctx.fill();
    ctx.strokeStyle = 'rgba(200,240,255,0.9)'; ctx.lineWidth = 2; ctx.stroke();

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
    var b = G.btn;
    button(SW, SH, b.endless, 'ENDLESS', [0.75, 0.22, 0.20]);
    text(SW, toY(SH, b.endless.y - 22), 13, [1, 0.85, 0.8], 'steal as long as you can');
    button(SW, SH, b.trials, 'TRIALS', [0.20, 0.55, 0.70]);
    text(SW, toY(SH, b.trials.y - 22), 13, [0.8, 0.95, 1.0], 'ten sealed moments to break');
    button(SW, SH, b.absorb, 'ABSORB', [0.45, 0.28, 0.70]);
    text(SW, toY(SH, b.absorb.y - 22), 13, [0.85, 0.8, 1.0], 'eat the small - fear the big');
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
      text(cx, cy - 10, 26, [1, 1, 1], String(r.i), open ? 1 : 0.45);
      var st = open ? (game.starsOf(r.i) >= 1 ? '*'.repeat(game.starsOf(r.i)) : '-') : '?';
      text(cx, cy + 20, 15, [1, 0.9, 0.4], st, open ? 1 : 0.4);
    }
    if (G.btn.back) button(SW, SH, G.btn.back, 'BACK', [0.30, 0.32, 0.40]);
  }

  function draw(game, time) {
    var G = game.state;
    bg(G.SW, G.SH, time);
    if (G.mode === 'select') drawSelect(game);
    else if (G.mode === 'levels') drawLevels(game);
    else if (G.mode === 'run' && G.S) drawRun(game, time);
  }

  return { draw: draw };
}

module.exports = { createRenderer: createRenderer };
