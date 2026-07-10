// menu.js — the collection menu screen. Lists games as tappable cards (title +
// subtitle + accent color) and offers a rewarded DAILY SPIN. Pure Canvas 2D;
// pixel coords. The router owns the loop and calls draw()/tap().
'use strict';

function createMenu(games, opts) {
  opts = opts || {};
  var ad = opts.ad;
  var onPick = opts.onPick || function () {};
  var W = 0, H = 0, cards = [], spinRect = null, toast = null, now = opts.now || function () { return Date.now(); };
  var getImage = opts.getImage || function () { return null; };
  function bgImg() { var im = getImage('bg.jpg'); return (im && im.complete && im.naturalWidth) ? im : null; }

  function setSize(w, h) {
    W = w; H = h;
    cards = [];
    var top = H * 0.26, bot = H * 0.86;
    var n = games.length;
    var gap = H * 0.03;
    var ch = Math.min(H * 0.14, (bot - top - gap * (n - 1)) / n);
    var cw = W * 0.86, cx = (W - cw) / 2;
    for (var i = 0; i < n; i++) {
      cards.push({ x: cx, y: top + i * (ch + gap), w: cw, h: ch, game: games[i] });
    }
    spinRect = { x: cx, y: bot + H * 0.01, w: cw, h: H * 0.075 };
  }

  function inRect(px, py, r) { return r && px >= r.x && px <= r.x + r.w && py >= r.y && py <= r.y + r.h; }

  function tap(px, py) {
    for (var i = 0; i < cards.length; i++) {
      if (inRect(px, py, cards[i])) { onPick(cards[i].game.id); return; }
    }
    if (inRect(px, py, spinRect) && ad) {
      if (!ad.dailyReady()) { toast = { t: 'come back tomorrow', until: now() + 1400 }; return; }
      ad.claimDaily(Math.random ? null : null, function (prize) {
        toast = { t: prize > 0 ? ('+' + prize + ' coins!') : 'ad skipped', until: now() + 1600 };
      });
    }
  }

  function roundRect(ctx, x, y, w, h, r) {
    ctx.beginPath(); ctx.moveTo(x + r, y);
    ctx.arcTo(x + w, y, x + w, y + h, r); ctx.arcTo(x + w, y + h, x, y + h, r);
    ctx.arcTo(x, y + h, x, y, r); ctx.arcTo(x, y, x + w, y, r); ctx.closePath();
  }
  function shade(hex, f) {  // f<0 darken, f>0 lighten
    var h = hex.replace('#', '');
    var r = parseInt(h.substr(0, 2), 16), g = parseInt(h.substr(2, 2), 16), b = parseInt(h.substr(4, 2), 16);
    var m = f < 0 ? 0 : 255, t = Math.abs(f);
    r = Math.round(r + (m - r) * t); g = Math.round(g + (m - g) * t); b = Math.round(b + (m - b) * t);
    return 'rgb(' + r + ',' + g + ',' + b + ')';
  }

  function draw(ctx) {
    var bg = bgImg();
    if (bg) { ctx.drawImage(bg, 0, 0, W, H); }
    else {
      ctx.fillStyle = '#0b1020'; ctx.fillRect(0, 0, W, H);
      ctx.fillStyle = 'rgba(255,255,255,0.10)';
      for (var s = 0; s < 40; s++) {
        var sx = (s * 9301 + 49297) % W, sy = (s * 233280 + 12345) % H;
        ctx.fillRect(sx, sy, 2, 2);
      }
    }
    // coins (own line, top-right, above the title so they never collide)
    if (ad) {
      ctx.fillStyle = '#f5b301'; ctx.textAlign = 'right'; ctx.textBaseline = 'alphabetic';
      ctx.font = '600 ' + Math.floor(H * 0.026) + 'px "Baloo2", system-ui, sans-serif';
      ctx.fillText('◎ ' + ad.coins(), W * 0.94, H * 0.075);
    }
    // title + subtitle (centered)
    ctx.fillStyle = '#eaf0ff'; ctx.textAlign = 'center'; ctx.textBaseline = 'alphabetic';
    ctx.font = '700 ' + Math.floor(H * 0.046) + 'px "Baloo2", system-ui, sans-serif';
    ctx.fillText('MINI ARCADE', W / 2, H * 0.155);
    ctx.fillStyle = '#9fb0d0';
    ctx.font = Math.floor(H * 0.024) + 'px "Baloo2", system-ui, sans-serif';
    ctx.fillText('tap a game', W / 2, H * 0.195);

    // game cards
    for (var i = 0; i < cards.length; i++) {
      var c = cards[i], g = c.game, base = g.color || '#2ea3f2';
      // drop shadow + vertical gradient body for depth
      ctx.save();
      ctx.shadowColor = 'rgba(0,0,0,0.38)'; ctx.shadowBlur = c.h * 0.14; ctx.shadowOffsetY = c.h * 0.06;
      roundRect(ctx, c.x, c.y, c.w, c.h, c.h * 0.22);
      var grad = ctx.createLinearGradient(0, c.y, 0, c.y + c.h);
      grad.addColorStop(0, shade(base, 0.12)); grad.addColorStop(1, shade(base, -0.28));
      ctx.fillStyle = grad; ctx.fill();
      ctx.restore();
      // top gloss sweep
      ctx.save();
      roundRect(ctx, c.x, c.y, c.w, c.h, c.h * 0.22); ctx.clip();
      var gl = ctx.createLinearGradient(0, c.y, 0, c.y + c.h * 0.55);
      gl.addColorStop(0, 'rgba(255,255,255,0.22)'); gl.addColorStop(1, 'rgba(255,255,255,0)');
      ctx.fillStyle = gl; ctx.fillRect(c.x, c.y, c.w, c.h * 0.55);
      ctx.restore();
      // clip text to the card so long titles/subtitles never bleed past the edge
      ctx.save();
      roundRect(ctx, c.x, c.y, c.w * 0.86, c.h, c.h * 0.22); ctx.clip();
      ctx.fillStyle = '#ffffff'; ctx.textAlign = 'left'; ctx.textBaseline = 'middle';
      ctx.font = '700 ' + Math.floor(c.h * 0.30) + 'px "Baloo2", system-ui, sans-serif';
      ctx.fillText(g.title, c.x + c.w * 0.07, c.y + c.h * 0.38);
      ctx.globalAlpha = 0.9;
      ctx.font = Math.floor(c.h * 0.16) + 'px "Baloo2", system-ui, sans-serif';
      ctx.fillText(g.subtitle || '', c.x + c.w * 0.07, c.y + c.h * 0.70);
      ctx.globalAlpha = 1;
      ctx.restore();
      ctx.fillStyle = '#ffffff'; ctx.globalAlpha = 0.95; ctx.textAlign = 'right'; ctx.textBaseline = 'middle';
      ctx.font = '700 ' + Math.floor(c.h * 0.36) + 'px "Baloo2", system-ui, sans-serif';
      ctx.fillText('▶', c.x + c.w * 0.94, c.y + c.h * 0.5);
      ctx.globalAlpha = 1;
    }

    // daily spin
    if (spinRect) {
      var ready = ad && ad.dailyReady();
      roundRect(ctx, spinRect.x, spinRect.y, spinRect.w, spinRect.h, spinRect.h * 0.3);
      ctx.fillStyle = ready ? 'rgba(245,179,1,0.22)' : 'rgba(255,255,255,0.06)';
      ctx.fill();
      ctx.lineWidth = 2; ctx.strokeStyle = ready ? 'rgba(245,179,1,0.8)' : 'rgba(255,255,255,0.16)'; ctx.stroke();
      ctx.fillStyle = ready ? '#f5b301' : '#9fb0d0'; ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
      ctx.font = '600 ' + Math.floor(spinRect.h * 0.4) + 'px "Baloo2", system-ui, sans-serif';
      ctx.fillText(ready ? '🎁 DAILY SPIN ▶' : 'DAILY SPIN — claimed', spinRect.x + spinRect.w / 2, spinRect.y + spinRect.h / 2);
    }

    if (toast && now() < toast.until) {
      ctx.fillStyle = 'rgba(0,0,0,0.6)';
      var tw = W * 0.6, tx = (W - tw) / 2, ty = H * 0.9;
      roundRect(ctx, tx, ty, tw, H * 0.05, H * 0.018); ctx.fill();
      ctx.fillStyle = '#eaf0ff'; ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
      ctx.font = Math.floor(H * 0.028) + 'px "Baloo2", system-ui, sans-serif';
      ctx.fillText(toast.t, W / 2, ty + H * 0.025);
    }
  }

  return { setSize: setSize, tap: tap, draw: draw };
}

module.exports = { createMenu: createMenu };
