// render.js — Canvas 2D drawing for Water Sort. Reads game.view() only; holds
// no game state. Pixel coordinates (top-left origin), matching game.js layout.
//
// The pour is the showcase moment: the source tube LIFTS out of its slot, MOVES
// over the destination and TILTS its mouth down, and an arcing liquid STREAM
// pours out — the stream is drawn by a real WebGL2 fragment shader (an SDF
// bezier ribbon with animated internal flow + a rounded liquid tip), rendered
// to an offscreen canvas and composited over the 2D scene. A pure-2D ribbon is
// kept as a fallback for contexts without WebGL2 (and for headless safety).
'use strict';
var C = require('./config.js');

var _imgGetter = null;
function setImageGetter(fn) { _imgGetter = fn; }
function img(name) {
  if (!_imgGetter) return null;
  var im = _imgGetter(name);
  return (im && im.complete && im.naturalWidth) ? im : null;
}

function sstep(a, b, x) { x = Math.max(0, Math.min(1, (x - a) / (b - a))); return x * x * (3 - 2 * x); }
function lerp(a, b, t) { return a + (b - a) * t; }
function hexToRgb(h) {
  h = h.replace('#', '');
  return [parseInt(h.substr(0, 2), 16) / 255, parseInt(h.substr(2, 2), 16) / 255, parseInt(h.substr(4, 2), 16) / 255];
}

// --- WebGL2 liquid-stream shader (lazy singleton) ---------------------------
// One offscreen canvas + program, reused every frame. Draws a fluid ribbon that
// follows a quadratic bezier P0->P1->P2 (mouth -> arc -> landing surface). The
// fragment shader finds the nearest point on the curve (sampled SDF), shades a
// rounded body with a bright core, scrolls internal flow bands, and rounds the
// leading tip into a droplet. Uniforms carry the geometry each frame so no
// buffers are re-uploaded. Returns null if WebGL2 is unavailable.
var _gl = (function () {
  var st = null, tried = false;
  var VS = '#version 300 es\nin vec2 a; void main(){ gl_Position = vec4(a,0.0,1.0); }';
  var FS = [
    '#version 300 es',
    'precision highp float;',
    'uniform vec2 uRes; uniform vec2 uP0; uniform vec2 uP1; uniform vec2 uP2;',
    'uniform float uThick; uniform vec3 uCol; uniform float uTime; uniform float uHead; uniform float uTail;',
    'out vec4 frag;',
    'vec2 bez(float t){ float m=1.0-t; return m*m*uP0 + 2.0*m*t*uP1 + t*t*uP2; }',
    'void main(){',
    '  vec2 P = vec2(gl_FragCoord.x, uRes.y - gl_FragCoord.y);', // gl bottom-left -> canvas top-left
    '  float best = 1e9; float bt = 0.0;',
    '  const int N = 48;',
    '  for(int i=0;i<=N;i++){ float t=float(i)/float(N); float d=distance(P,bez(t)); if(d<best){best=d;bt=t;} }',
    '  if(bt < uTail || bt > uHead){ frag=vec4(0.0); return; }',
    '  float taper = 0.72 + 0.28*sin(bt*3.14159);',              // thinner at both ends
    '  float th = uThick * taper * (0.9 + 0.1*sin(bt*22.0 - uTime*9.0));',
    '  float edge = smoothstep(th, th*0.5, best);',
    '  if(edge<=0.002){ frag=vec4(0.0); return; }',
    '  float flow = 0.5 + 0.5*sin(bt*40.0 - uTime*13.0);',       // scrolling interior bands
    '  vec3 col = uCol * (0.80 + 0.34*flow);',
    '  float core = smoothstep(th*0.55, 0.0, best);',            // bright glassy core
    '  col += vec3(0.30,0.34,0.40) * core;',
    '  float tip = smoothstep(0.05,0.0,abs(bt-uHead)) * smoothstep(th*1.9,0.0,best);',
    '  col += uCol * 0.5 * tip;',                                // rounded leading droplet
    '  frag = vec4(col, edge*0.96);',
    '}',
  ].join('\n');

  function compile(gl, type, src) {
    var s = gl.createShader(type); gl.shaderSource(s, src); gl.compileShader(s);
    if (!gl.getShaderParameter(s, gl.COMPILE_STATUS)) { return null; }
    return s;
  }
  function init() {
    tried = true;
    if (typeof document === 'undefined' || !document.createElement) return null;
    var cv = document.createElement('canvas');
    var gl = cv.getContext('webgl2', { premultipliedAlpha: false, alpha: true, antialias: true });
    if (!gl) return null;
    var vs = compile(gl, gl.VERTEX_SHADER, VS), fs = compile(gl, gl.FRAGMENT_SHADER, FS);
    if (!vs || !fs) return null;
    var prog = gl.createProgram(); gl.attachShader(prog, vs); gl.attachShader(prog, fs); gl.linkProgram(prog);
    if (!gl.getProgramParameter(prog, gl.LINK_STATUS)) return null;
    var buf = gl.createBuffer(); gl.bindBuffer(gl.ARRAY_BUFFER, buf);
    gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([-1, -1, 3, -1, -1, 3]), gl.STATIC_DRAW); // fullscreen tri
    var loc = gl.getAttribLocation(prog, 'a');
    gl.enableVertexAttribArray(loc); gl.vertexAttribPointer(loc, 2, gl.FLOAT, false, 0, 0);
    gl.useProgram(prog);
    var U = {};
    ['uRes', 'uP0', 'uP1', 'uP2', 'uThick', 'uCol', 'uTime', 'uHead', 'uTail'].forEach(function (n) {
      U[n] = gl.getUniformLocation(prog, n);
    });
    gl.enable(gl.BLEND); gl.blendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA);
    return { cv: cv, gl: gl, U: U };
  }
  return {
    get: function () { if (!tried) { try { st = init(); } catch (e) { st = null; } } return st; },
  };
})();

// Draw the shader stream onto `ctx`. p0/p1/p2 are {x,y} in canvas user space.
// Returns true if it rendered via WebGL (caller skips the 2D fallback).
function drawStreamGL(ctx, W, H, p0, p1, p2, rgb, thick, time, head, tail) {
  var s = _gl.get();
  if (!s) return false;
  var gl = s.gl;
  if (s.cv.width !== W || s.cv.height !== H) { s.cv.width = W; s.cv.height = H; }
  gl.viewport(0, 0, W, H);
  gl.clearColor(0, 0, 0, 0); gl.clear(gl.COLOR_BUFFER_BIT);
  gl.uniform2f(s.U.uRes, W, H);
  gl.uniform2f(s.U.uP0, p0.x, p0.y);
  gl.uniform2f(s.U.uP1, p1.x, p1.y);
  gl.uniform2f(s.U.uP2, p2.x, p2.y);
  gl.uniform1f(s.U.uThick, thick);
  gl.uniform3f(s.U.uCol, rgb[0], rgb[1], rgb[2]);
  gl.uniform1f(s.U.uTime, time);
  gl.uniform1f(s.U.uHead, head);
  gl.uniform1f(s.U.uTail, tail);
  gl.drawArrays(gl.TRIANGLES, 0, 3);
  try { ctx.drawImage(s.cv, 0, 0, W, H); } catch (e) { return false; }
  return true;
}

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

  // Draw a tube (glass + liquid) at `rect`. When `selected` and not tilting, the
  // top run lifts a touch. `mouthY` (optional) reports the inner liquid geometry.
  function drawTube(rect, tube, cap, palette, selected, liftUnits) {
    var x = rect.x, y = rect.y, w = rect.w, h = rect.h, r = w * 0.5;
    var n = tube.length;

    // --- glass body: cross gradient for a rounded, translucent look ----------
    ctx.save();
    roundRect(x, y, w, h, r);
    var bodyG = ctx.createLinearGradient(x, 0, x + w, 0);
    bodyG.addColorStop(0, 'rgba(255,255,255,0.16)');
    bodyG.addColorStop(0.45, 'rgba(255,255,255,0.05)');
    bodyG.addColorStop(1, 'rgba(255,255,255,0.13)');
    ctx.fillStyle = bodyG; ctx.fill();
    ctx.restore();

    // --- liquid: contiguous same-colour runs, no seams/gaps ------------------
    var ix = x + 2.5, iy = y + 2.5, iw = w - 5, ih = h - 5, ir = iw * 0.5;
    var unitH = ih / cap, lift = -h * 0.09;
    ctx.save();
    roundRect(ix, iy, iw, ih, ir); ctx.clip();
    var i = 0;
    while (i < n) {
      var c = tube[i], j = i;
      while (j < n && tube[j] === c) j++;                 // extend same-colour run
      var isTop = (j === n);
      var off = (selected && isTop && (n - i) <= (liftUnits || n)) ? lift : 0;
      var yTop = iy + ih - j * unitH + off, yBot = iy + ih - i * unitH + off;
      ctx.fillStyle = palette[c % palette.length];
      ctx.fillRect(ix, yTop, iw, (yBot - yTop) + 0.75);   // overlap => zero gaps
      if (i === 0) {                                       // floor shade for depth
        var fl = ctx.createLinearGradient(0, yBot - unitH * 0.5, 0, yBot);
        fl.addColorStop(0, 'rgba(0,0,0,0)'); fl.addColorStop(1, 'rgba(0,0,0,0.18)');
        ctx.fillStyle = fl; ctx.fillRect(ix, yBot - unitH * 0.5, iw, unitH * 0.5);
      }
      i = j;
    }
    if (n > 0) {                                           // meniscus surface band
      var topY = iy + ih - n * unitH + (selected ? lift : 0);
      var men = ctx.createLinearGradient(0, topY, 0, topY + unitH * 0.55);
      men.addColorStop(0, 'rgba(255,255,255,0.30)'); men.addColorStop(1, 'rgba(255,255,255,0)');
      ctx.fillStyle = men; ctx.fillRect(ix, topY, iw, unitH * 0.55);
    }
    ctx.restore();

    // --- glass sheen: a vertical gloss streak + bright rim -------------------
    ctx.save();
    roundRect(x, y, w, h, r); ctx.clip();
    var streak = ctx.createLinearGradient(x, 0, x + w * 0.55, 0);
    streak.addColorStop(0, 'rgba(255,255,255,0)');
    streak.addColorStop(0.5, 'rgba(255,255,255,0.26)');
    streak.addColorStop(1, 'rgba(255,255,255,0)');
    ctx.fillStyle = streak; ctx.fillRect(x + w * 0.13, y + r * 0.5, w * 0.16, h - r);
    ctx.restore();
    roundRect(x, y, w, h, r);
    ctx.lineWidth = Math.max(2, w * 0.055); ctx.strokeStyle = 'rgba(255,255,255,0.34)'; ctx.stroke();
  }

  // 2D fallback ribbon (used only when WebGL2 is unavailable).
  function drawStream2D(p0, p1, p2, color, thick, head, tail) {
    ctx.save();
    ctx.strokeStyle = color; ctx.globalAlpha = 0.85; ctx.lineCap = 'round';
    ctx.lineWidth = thick;
    ctx.beginPath();
    var started = false;
    for (var k = 0; k <= 24; k++) {
      var t = tail + (head - tail) * (k / 24);
      if (t < 0 || t > 1) continue;
      var m = 1 - t;
      var px = m * m * p0.x + 2 * m * t * p1.x + t * t * p2.x;
      var py = m * m * p0.y + 2 * m * t * p1.y + t * t * p2.y;
      if (!started) { ctx.moveTo(px, py); started = true; } else ctx.lineTo(px, py);
    }
    ctx.stroke();
    // rounded tip droplet
    var ht = head, hm = 1 - ht;
    var hx = hm * hm * p0.x + 2 * hm * ht * p1.x + ht * ht * p2.x;
    var hy = hm * hm * p0.y + 2 * hm * ht * p1.y + ht * ht * p2.y;
    ctx.globalAlpha = 1; ctx.fillStyle = color;
    ctx.beginPath(); ctx.arc(hx, hy, thick * 0.6, 0, 6.283); ctx.fill();
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
    ctx.font = Math.floor(b.h * 0.34) + 'px "Baloo2", system-ui, sans-serif';
    ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
    ctx.fillText(b.label, b.x + b.w / 2, b.y + b.h / 2);
    ctx.restore();
  }

  function draw(game) {
    var v = game.view();
    var bg = img('bg.jpg');
    if (bg) ctx.drawImage(bg, 0, 0, W, H);
    else { ctx.fillStyle = C.BG; ctx.fillRect(0, 0, W, H); }
    if (!v.lv) return;
    var st = v.lv.state, palette = v.palette;

    // HUD — title on its own line, stats on a second line, so they never collide
    ctx.fillStyle = C.TEXT;
    ctx.font = '600 ' + Math.floor(H * 0.038) + 'px "Baloo2", system-ui, sans-serif';
    ctx.textAlign = 'left'; ctx.textBaseline = 'alphabetic';
    ctx.fillText('WATER SORT', W * 0.06, H * 0.072);
    ctx.fillStyle = C.SUBTEXT;
    ctx.font = Math.floor(H * 0.026) + 'px "Baloo2", system-ui, sans-serif';
    ctx.textAlign = 'left';
    ctx.fillText('LEVEL ' + v.level, W * 0.06, H * 0.115);
    ctx.textAlign = 'right';
    ctx.fillText('moves ' + st.moves, W * 0.94, H * 0.115);

    var an = v.anim;
    var liftUnits = st.selected >= 0 ? LOGIC_runLen(st.tubes[st.selected]) : 0;

    // Pre-compute the pour choreography so both the tilted tube and the stream
    // share one set of phase envelopes.
    var pour = null;
    if (an) {
      var p = an.p;
      var lift = sstep(0.00, 0.16, p);          // rise out of the slot
      var move = sstep(0.10, 0.34, p);          // travel + tilt into pour pose
      var flow = sstep(0.34, 0.84, p);          // liquid actually transferring
      var back = sstep(0.84, 1.00, p);          // settle back to the slot
      var place = Math.max(lift * 0.35, move) * (1 - back);   // 0..1 in pour pose
      var sr = v.layout.tubes[an.from], dr = v.layout.tubes[an.to];
      var destCx = dr.x + dr.w / 2;
      // Tilt the mouth down toward the dest; lean the (long) body into the LARGER
      // screen half so it never runs off an edge. Foreshorten a touch when lifted.
      var sign = (destCx < W * 0.5) ? -1 : 1;
      var restMouth = { x: sr.x + sr.w / 2, y: sr.y };
      var poseMouth = { x: destCx, y: dr.y - dr.h * 0.05 };
      var mouth = { x: lerp(restMouth.x, poseMouth.x, place),
                    y: lerp(restMouth.y, poseMouth.y, place) - lift * (1 - move) * sr.h * 0.12 };
      var angle = sign * 1.9 * place;           // ~109° at full pose: mouth points down
      var scale = lerp(1, 0.82, place);
      pour = { p: p, flow: flow, place: place, sign: sign, sr: sr, dr: dr, mouth: mouth, angle: angle, scale: scale };
    }

    // tubes (skip the pouring source — it is drawn tilted, on top, afterwards)
    for (var i = 0; i < st.tubes.length; i++) {
      var isSel = (i === st.selected);
      var arr = st.tubes[i];
      if (an && i === an.from) {
        // source rendered separately below (tilted); keep only its slot label
        var slr = v.layout.tubes[i];
        ctx.fillStyle = C.SUBTEXT; ctx.textAlign = 'center'; ctx.textBaseline = 'top';
        ctx.font = Math.floor(slr.w * 0.34) + 'px "Baloo2", system-ui, sans-serif';
        ctx.fillText(String(i + 1), slr.x + slr.w / 2, slr.y + slr.h + 4);
        continue;
      } else if (an && i === an.to) {
        var revealed = Math.round(an.units * pour.flow);
        arr = arr.slice();
        for (var u = 0; u < revealed; u++) arr.push(an.col);
      }
      drawTube(v.layout.tubes[i], arr, st.cap, palette, isSel, liftUnits);
      var r = v.layout.tubes[i];
      ctx.fillStyle = C.SUBTEXT; ctx.textAlign = 'center'; ctx.textBaseline = 'top';
      ctx.font = Math.floor(r.w * 0.34) + 'px "Baloo2", system-ui, sans-serif';
      ctx.fillText(String(i + 1), r.x + r.w / 2, r.y + r.h + 4);
    }

    // the tilted, pouring source tube + the shader liquid stream
    if (an) {
      var sr2 = pour.sr, dr2 = pour.dr;
      var fullSrc = st.tubes[an.from];
      var drained2 = Math.round(an.units * pour.flow);
      var srcArr = fullSrc.slice(0, fullSrc.length - drained2);

      // draw the source tube in a rotated frame, pivoting about its mouth
      ctx.save();
      ctx.translate(pour.mouth.x, pour.mouth.y);
      ctx.rotate(pour.angle);
      ctx.scale(pour.scale, pour.scale);
      drawTube({ x: -sr2.w / 2, y: 0, w: sr2.w, h: sr2.h }, srcArr, st.cap, palette, false, 0);
      ctx.restore();

      // stream geometry: from the tilted mouth, arc down to the dest liquid top
      var revealed2 = Math.round(an.units * pour.flow);
      var dix = dr2.x + 2.5, diy = dr2.y + 2.5, dih = dr2.h - 5;
      var destTopY = diy + dih - (st.tubes[an.to].length + revealed2) * (dih / st.cap);
      var p0 = { x: pour.mouth.x, y: pour.mouth.y };
      var p2 = { x: dr2.x + dr2.w / 2, y: Math.max(destTopY, dr2.y + 4) };
      var p1 = { x: lerp(p0.x, p2.x, 0.25), y: p2.y - dr2.h * 0.10 };
      var rgb = hexToRgb(palette[an.col % palette.length]);
      var thick = Math.max(4, sr2.w * 0.24);
      // active window: tip leads slightly, tail retracts as the pour finishes
      var head = Math.max(0, Math.min(1, pour.flow * 1.18));
      var tail = sstep(0.86, 1.0, pour.p);
      var time = an.p * (pour.p != null ? 6.0 : 0) + an.from + an.to;  // deterministic-ish scroll
      if (head > tail + 0.01 && pour.place > 0.35) {
        var okGL = drawStreamGL(ctx, W, H, p0, p1, p2, rgb, thick, time, head, tail);
        if (!okGL) drawStream2D(p0, p1, p2, palette[an.col % palette.length], thick, head, tail);
      }
    }

    // splash particles from a landed pour
    if (v.parts && v.parts.length) {
      ctx.save();
      for (var pk = 0; pk < v.parts.length; pk++) {
        var pp = v.parts[pk], tt = 1 - pp.life / pp.max;
        ctx.globalAlpha = Math.max(0, tt);
        ctx.beginPath(); ctx.arc(pp.x, pp.y, pp.r0 * (0.5 + 0.5 * tt), 0, 6.283);
        ctx.fillStyle = pp.col; ctx.fill();
      }
      ctx.restore();
    }

    // hint arrow (rewarded)
    if (v.hintMove) {
      var ha = v.layout.tubes[v.hintMove[0]], hb = v.layout.tubes[v.hintMove[1]];
      ctx.strokeStyle = '#f5b301'; ctx.lineWidth = Math.max(3, W * 0.01);
      ctx.beginPath();
      ctx.moveTo(ha.x + ha.w / 2, ha.y - 6);
      ctx.quadraticCurveTo((ha.x + hb.x) / 2 + ha.w / 2, Math.min(ha.y, hb.y) - H * 0.06, hb.x + hb.w / 2, hb.y - 6);
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
      ctx.font = Math.floor(H * 0.03) + 'px "Baloo2", system-ui, sans-serif';
      ctx.fillText(v.toast.text, W / 2, ty + H * 0.03);
    }

    // win banner
    if (v.banner === 'win') {
      ctx.fillStyle = 'rgba(6,10,26,0.78)'; ctx.fillRect(0, 0, W, H);
      ctx.fillStyle = '#37c871'; ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
      ctx.font = 'bold ' + Math.floor(H * 0.08) + 'px "Baloo2", system-ui, sans-serif';
      ctx.fillText('SOLVED!', W / 2, H * 0.42);
      ctx.fillStyle = C.TEXT;
      ctx.font = Math.floor(H * 0.035) + 'px "Baloo2", system-ui, sans-serif';
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

module.exports = { createRenderer: createRenderer, setImageGetter: setImageGetter };
