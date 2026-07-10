// render.js — Canvas 2D drawing for Suika. Reads game.view() only; holds no
// game state. Pixel coordinates (top-left origin), matching game.js layout.
// createRenderer(ctx) — reads W/H from the view each frame, so a resize between
// frames is handled without rebuilding the renderer.
'use strict';
var C = require('./config.js');

// Optional art assets: set by game.js from platform.getImage. Returns an
// HTMLImageElement (maybe not yet loaded) or null; rendering falls back to
// procedural drawing when an image is absent (headless/tests).
var _imgGetter = null;
function setImageGetter(fn) { _imgGetter = fn; }
function img(name) {
  if (!_imgGetter) return null;
  var im = _imgGetter(name);
  return (im && im.complete && im.naturalWidth) ? im : null;
}

function createRenderer(ctx) {

  // ambient stardust: a seeded flow-field drift behind play (algorithmic-art).
  var _motes = null, _mt = 0;
  function ambient(W, H) {
    if (!_motes) {
      _motes = [];
      for (var i = 0; i < 36; i++) _motes.push({ x: Math.random() * W, y: Math.random() * H, s: 0.3 + Math.random() * 0.8, ph: Math.random() * 6.28 });
    }
    _mt += 0.016;
    ctx.save(); ctx.globalCompositeOperation = 'lighter';
    for (var j = 0; j < _motes.length; j++) {
      var m = _motes[j];
      var ang = Math.sin(m.x * 0.004 + _mt * 0.2) + Math.cos(m.y * 0.005 - _mt * 0.15);
      m.x += Math.cos(ang) * 0.28 * m.s; m.y += Math.sin(ang) * 0.22 * m.s - 0.05;
      if (m.y < 0) m.y = H; if (m.y > H) m.y = 0; if (m.x < 0) m.x = W; if (m.x > W) m.x = 0;
      var tw = 0.4 + 0.6 * Math.abs(Math.sin(_mt * 1.4 + m.ph));
      ctx.globalAlpha = 0.14 * tw * m.s;
      ctx.beginPath(); ctx.arc(m.x, m.y, 1.3 * m.s, 0, 6.283); ctx.fillStyle = '#bfe0ff'; ctx.fill();
    }
    ctx.restore();
  }

  function drawParticles(parts) {
    if (!parts || !parts.length) return;
    ctx.save(); ctx.globalCompositeOperation = 'lighter';
    for (var i = 0; i < parts.length; i++) {
      var p = parts[i], t = 1 - p.life / p.max;
      ctx.globalAlpha = Math.max(0, t);
      ctx.beginPath(); ctx.arc(p.x, p.y, p.r0 * (0.45 + 0.55 * t), 0, 6.283);
      ctx.fillStyle = p.col; ctx.fill();
    }
    ctx.restore();
  }

  function roundRect(x, y, w, h, r) {
    ctx.beginPath();
    ctx.moveTo(x + r, y);
    ctx.arcTo(x + w, y, x + w, y + h, r);
    ctx.arcTo(x + w, y + h, x, y + h, r);
    ctx.arcTo(x, y + h, x, y, r);
    ctx.arcTo(x, y, x + w, y, r);
    ctx.closePath();
  }

  // draw a fruit of `tier` centred at (x,y) with radius r; uses the sprite sheet
  // when available (cells are square, side = sheet height), else procedural.
  function sprite(tier, x, y, r, alpha) {
    var sheet = img('fruits.png');
    if (sheet) {
      var cell = sheet.naturalHeight;
      var sx = Math.min(tier, C.TIER_COUNT - 1) * cell;
      var d = r * 2.14;
      if (alpha != null) { ctx.save(); ctx.globalAlpha = alpha; }
      ctx.drawImage(sheet, sx, 0, cell, cell, x - d / 2, y - d / 2, d, d);
      if (alpha != null) ctx.restore();
      return true;
    }
    return false;
  }

  function drawFruit(f) {
    if (sprite(f.tier, f.x, f.y, f.r, null)) return;
    var col = C.colorOf(f.tier);
    ctx.beginPath(); ctx.arc(f.x, f.y, f.r, 0, Math.PI * 2);
    ctx.fillStyle = col; ctx.fill();
    ctx.lineWidth = Math.max(1, f.r * 0.08); ctx.strokeStyle = 'rgba(0,0,0,0.18)'; ctx.stroke();
    ctx.beginPath(); ctx.arc(f.x - f.r * 0.32, f.y - f.r * 0.32, f.r * 0.30, 0, Math.PI * 2);
    ctx.fillStyle = 'rgba(255,255,255,0.28)'; ctx.fill();
    if (f.r > 10) {
      ctx.fillStyle = 'rgba(0,0,0,0.45)'; ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
      ctx.font = Math.floor(f.r * 0.8) + 'px "Baloo2", system-ui, sans-serif';
      ctx.fillText(String(f.tier + 1), f.x, f.y + f.r * 0.04);
    }
  }

  function drawButton(b, accent) {
    roundRect(b.x, b.y, b.w, b.h, b.h * 0.3);
    ctx.fillStyle = accent ? 'rgba(46,163,242,0.24)' : 'rgba(255,255,255,0.08)';
    ctx.fill();
    ctx.lineWidth = 2;
    ctx.strokeStyle = accent ? 'rgba(46,163,242,0.8)' : 'rgba(255,255,255,0.28)';
    ctx.stroke();
    ctx.fillStyle = C.TEXT;
    ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
    ctx.font = '600 ' + Math.floor(b.h * 0.4) + 'px "Baloo2", system-ui, sans-serif';
    ctx.fillText(b.label, b.x + b.w / 2, b.y + b.h / 2);
  }

  function draw(game) {
    var v = game.view();
    var W = v.W, H = v.H;
    var bg = img('bg.png');
    if (bg) ctx.drawImage(bg, 0, 0, W, H);
    else { ctx.fillStyle = C.BG; ctx.fillRect(0, 0, W, H); }
    ambient(W, H);
    if (!v.sim) return;
    var S = v.sim.state, b = v.bin;

    // --- HUD (kept below the reserved top inset) ------------------------------
    var hudY = v.topInset + H * 0.045;
    ctx.fillStyle = C.TEXT;
    ctx.textAlign = 'left'; ctx.textBaseline = 'alphabetic';
    ctx.font = '700 ' + Math.floor(H * 0.034) + 'px "Baloo2", system-ui, sans-serif';
    ctx.fillText('SUIKA', W * 0.06, hudY);
    ctx.font = '700 ' + Math.floor(H * 0.03) + 'px "Baloo2", system-ui, sans-serif';
    ctx.textAlign = 'right';
    ctx.fillText(String(S.score), W * 0.94, hudY);
    ctx.fillStyle = C.SUBTEXT;
    ctx.font = Math.floor(H * 0.02) + 'px "Baloo2", system-ui, sans-serif';
    ctx.fillText('best ' + Math.max(v.best, S.score), W * 0.94, hudY + H * 0.026);

    // next fruit preview (top-left, under the title)
    if (!S.over) {
      var nr = Math.min(H * 0.02, C.radiusOf(S.current, b.w));
      ctx.fillStyle = C.SUBTEXT; ctx.textAlign = 'left'; ctx.textBaseline = 'middle';
      ctx.font = Math.floor(H * 0.02) + 'px "Baloo2", system-ui, sans-serif';
      ctx.fillText('next', W * 0.06, hudY + H * 0.028);
      var npr = Math.max(nr, H * 0.022);
      if (!sprite(S.next, W * 0.20, hudY + H * 0.028, npr, null)) {
        ctx.beginPath(); ctx.arc(W * 0.20, hudY + H * 0.028, npr, 0, Math.PI * 2);
        ctx.fillStyle = C.colorOf(S.next); ctx.fill();
      }
    }

    // --- bin ------------------------------------------------------------------
    ctx.save();
    roundRect(b.x, b.y, b.w, b.h, Math.min(18, b.w * 0.05));
    ctx.fillStyle = C.BIN_FILL; ctx.fill();
    ctx.lineWidth = Math.max(2, b.w * 0.012);
    ctx.strokeStyle = C.BIN_WALL; ctx.stroke();
    // clip fruit to the bin
    ctx.clip();

    // danger line
    var dy = v.dangerY;
    ctx.setLineDash([b.w * 0.03, b.w * 0.03]);
    ctx.lineWidth = 2;
    var danger = S.dangerTimer > 0.4;
    ctx.strokeStyle = danger ? C.DANGER : 'rgba(230,57,74,0.45)';
    ctx.beginPath(); ctx.moveTo(b.x, dy); ctx.lineTo(b.x + b.w, dy); ctx.stroke();
    ctx.setLineDash([]);

    // fruit
    for (var i = 0; i < S.fruit.length; i++) drawFruit(S.fruit[i]);
    ctx.restore();

    // --- aim guide + ghost of the current fruit -------------------------------
    if (!S.over) {
      var gx = Math.max(b.x, Math.min(b.x + b.w, v.aimX));
      ctx.save();
      ctx.strokeStyle = 'rgba(255,255,255,0.18)';
      ctx.lineWidth = 2; ctx.setLineDash([6, 8]);
      ctx.beginPath(); ctx.moveTo(gx, b.y); ctx.lineTo(gx, b.y + b.h); ctx.stroke();
      ctx.setLineDash([]);
      var cr = C.radiusOf(S.current, b.w);
      var cgx = Math.max(b.x + cr, Math.min(b.x + b.w - cr, gx));
      if (!sprite(S.current, cgx, b.y + cr + 1, cr, 0.65)) {
        ctx.globalAlpha = 0.55;
        ctx.beginPath(); ctx.arc(cgx, b.y + cr + 1, cr, 0, Math.PI * 2);
        ctx.fillStyle = C.colorOf(S.current); ctx.fill();
      }
      ctx.restore();
    }

    // merge burst particles (over the field)
    drawParticles(v.parts);

    // merge flash bloom
    if (v.flash > 0.02) {
      ctx.fillStyle = 'rgba(255,255,255,' + (v.flash * 0.12).toFixed(3) + ')';
      ctx.fillRect(0, 0, W, H);
    }

    // --- toast ----------------------------------------------------------------
    if (v.toast) {
      var tw = W * 0.6, tx = (W - tw) / 2, ty = H * 0.8;
      ctx.fillStyle = 'rgba(0,0,0,0.6)';
      roundRect(tx, ty, tw, H * 0.06, H * 0.02); ctx.fill();
      ctx.fillStyle = C.TEXT; ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
      ctx.font = Math.floor(H * 0.028) + 'px "Baloo2", system-ui, sans-serif';
      ctx.fillText(v.toast.text, W / 2, ty + H * 0.03);
    }

    // --- game over overlay ----------------------------------------------------
    if (S.over) {
      ctx.fillStyle = 'rgba(6,10,26,0.82)'; ctx.fillRect(0, 0, W, H);
      ctx.fillStyle = C.DANGER; ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
      ctx.font = 'bold ' + Math.floor(H * 0.06) + 'px "Baloo2", system-ui, sans-serif';
      ctx.fillText('GAME OVER', W / 2, H * 0.32);
      ctx.fillStyle = C.TEXT;
      ctx.font = '700 ' + Math.floor(H * 0.04) + 'px "Baloo2", system-ui, sans-serif';
      ctx.fillText('score ' + S.score, W / 2, H * 0.4);
      ctx.fillStyle = C.SUBTEXT;
      ctx.font = Math.floor(H * 0.024) + 'px "Baloo2", system-ui, sans-serif';
      ctx.fillText('best ' + Math.max(v.best, S.score), W / 2, H * 0.45);
      // buttons (revive/×2 disable once used)
      drawButton(v.buttons.revive, !v.reviveUsed);
      drawButton(v.buttons.dbl, !v.doubled);
      drawButton(v.buttons.restart, false);
    }
  }

  return { draw: draw };
}

module.exports = { createRenderer: createRenderer, setImageGetter: setImageGetter };
