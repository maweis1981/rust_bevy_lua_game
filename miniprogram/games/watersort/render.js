// render.js — Canvas 2D drawing for Water Sort. Reads game.view() only; holds
// no game state. Pixel coordinates (top-left origin), matching game.js layout.
'use strict';
var C = require('./config.js');

function createRenderer(ctx, W, H) {

  function roundRect(x, y, w, h, r) {
    ctx.beginPath();
    ctx.moveTo(x + r, y);
    ctx.arcTo(x + w, y, x + w, y + h, r);
    ctx.arcTo(x + w, y + h, x, y + h, r);
    ctx.arcTo(x, y + h, x, y, r);
    ctx.arcTo(x, y, x + w, y, r);
    ctx.closePath();
  }

  function drawTube(rect, tube, cap, palette, selected, liftUnits) {
    var x = rect.x, y = rect.y, w = rect.w, h = rect.h;
    var r = w * 0.5;
    var segH = (h - r * 0.4) / cap;
    // glass body
    ctx.save();
    roundRect(x, y, w, h, r);
    ctx.fillStyle = C.TUBE_GLASS; ctx.fill();
    ctx.lineWidth = Math.max(2, w * 0.05); ctx.strokeStyle = C.TUBE_EDGE; ctx.stroke();
    // clip liquids to the tube shape
    roundRect(x + 2, y + 2, w - 4, h - 4, r); ctx.clip();
    for (var i = 0; i < tube.length; i++) {
      var col = palette[tube[i] % palette.length];
      var segY = y + h - (i + 1) * segH;
      var lift = (selected && i >= tube.length - liftUnits) ? -h * 0.10 : 0;
      ctx.fillStyle = col;
      ctx.fillRect(x + 3, segY + lift, w - 6, segH + 1);
      // subtle top gloss on the topmost unit of a run
      ctx.fillStyle = 'rgba(255,255,255,0.12)';
      ctx.fillRect(x + 3, segY + lift, w - 6, Math.max(2, segH * 0.16));
    }
    ctx.restore();
  }

  function drawButton(b, enabled) {
    ctx.save();
    roundRect(b.x, b.y, b.w, b.h, b.h * 0.28);
    ctx.fillStyle = enabled ? 'rgba(46,163,242,0.22)' : 'rgba(255,255,255,0.06)';
    ctx.fill();
    ctx.lineWidth = 2; ctx.strokeStyle = enabled ? 'rgba(46,163,242,0.7)' : 'rgba(255,255,255,0.18)';
    ctx.stroke();
    ctx.fillStyle = enabled ? C.TEXT : C.SUBTEXT;
    ctx.font = Math.floor(b.h * 0.34) + 'px system-ui, -apple-system, sans-serif';
    ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
    ctx.fillText(b.label, b.x + b.w / 2, b.y + b.h / 2);
    ctx.restore();
  }

  function draw(game) {
    var v = game.view();
    ctx.fillStyle = C.BG; ctx.fillRect(0, 0, W, H);
    if (!v.lv) return;
    var st = v.lv.state, palette = v.palette;

    // HUD — title on its own line, stats on a second line, so they never collide
    ctx.fillStyle = C.TEXT;
    ctx.font = '600 ' + Math.floor(H * 0.038) + 'px system-ui, -apple-system, sans-serif';
    ctx.textAlign = 'left'; ctx.textBaseline = 'alphabetic';
    ctx.fillText('WATER SORT', W * 0.06, H * 0.072);
    ctx.fillStyle = C.SUBTEXT;
    ctx.font = Math.floor(H * 0.026) + 'px system-ui, -apple-system, sans-serif';
    ctx.textAlign = 'left';
    ctx.fillText('LEVEL ' + v.level, W * 0.06, H * 0.115);
    ctx.textAlign = 'right';
    ctx.fillText('moves ' + st.moves, W * 0.94, H * 0.115);

    // tubes
    var liftUnits = st.selected >= 0 ? LOGIC_runLen(st.tubes[st.selected]) : 0;
    for (var i = 0; i < st.tubes.length; i++) {
      var isSel = (i === st.selected);
      drawTube(v.layout.tubes[i], st.tubes[i], st.cap, palette, isSel, liftUnits);
      // tube index label
      var r = v.layout.tubes[i];
      ctx.fillStyle = C.SUBTEXT; ctx.textAlign = 'center'; ctx.textBaseline = 'top';
      ctx.font = Math.floor(r.w * 0.34) + 'px system-ui, sans-serif';
      ctx.fillText(String(i + 1), r.x + r.w / 2, r.y + r.h + 4);
    }

    // hint arrow (rewarded)
    if (v.hintMove) {
      var a = v.layout.tubes[v.hintMove[0]], b = v.layout.tubes[v.hintMove[1]];
      ctx.strokeStyle = '#f5b301'; ctx.lineWidth = Math.max(3, W * 0.01);
      ctx.beginPath();
      ctx.moveTo(a.x + a.w / 2, a.y - 6);
      ctx.quadraticCurveTo((a.x + b.x) / 2 + a.w / 2, Math.min(a.y, b.y) - H * 0.06, b.x + b.w / 2, b.y - 6);
      ctx.stroke();
    }

    // buttons
    drawButton(v.layout.buttons.undo, st.history.length > 0);
    drawButton(v.layout.buttons.hint, !v.banner);
    drawButton(v.layout.buttons.tube, !v.banner);

    // toast
    if (v.toast) {
      ctx.fillStyle = 'rgba(0,0,0,0.55)';
      var tw = W * 0.5, tx = (W - tw) / 2, ty = H * 0.72;
      roundRect(tx, ty, tw, H * 0.06, H * 0.02); ctx.fill();
      ctx.fillStyle = C.TEXT; ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
      ctx.font = Math.floor(H * 0.03) + 'px system-ui, sans-serif';
      ctx.fillText(v.toast.text, W / 2, ty + H * 0.03);
    }

    // win banner
    if (v.banner === 'win') {
      ctx.fillStyle = 'rgba(6,10,26,0.78)'; ctx.fillRect(0, 0, W, H);
      ctx.fillStyle = '#37c871'; ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
      ctx.font = 'bold ' + Math.floor(H * 0.08) + 'px system-ui, sans-serif';
      ctx.fillText('SOLVED!', W / 2, H * 0.42);
      ctx.fillStyle = C.TEXT;
      ctx.font = Math.floor(H * 0.035) + 'px system-ui, sans-serif';
      ctx.fillText('tap to continue → LV ' + (v.level + 1), W / 2, H * 0.52);
    }
  }

  // tiny inline run-length (renderer-local; avoids importing logic here)
  function LOGIC_runLen(t) {
    if (!t.length) return 0;
    var c = t[t.length - 1], n = 1;
    for (var i = t.length - 2; i >= 0; i--) { if (t[i] === c) n++; else break; }
    return n;
  }

  return { draw: draw };
}

module.exports = { createRenderer: createRenderer };
