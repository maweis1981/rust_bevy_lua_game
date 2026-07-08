// engine.js — the fengari SPIKE. Proves the platform thesis: run the SAME native
// Lua (assets/scripts/main.lua, unmodified) on the TikTok/web target via fengari
// (a JS Lua VM), with a JS `game.*` bridge over a scene map + a generic Canvas 2D
// renderer as the "native presentation" backend. If this holds 60fps on a real
// low-end Android webview, TikTok becomes single-source (see docs/PLATFORM_BLUEPRINT.md).
'use strict';

(function () {
  var F = fengari;
  var lua = F.lua, lauxlib = F.lauxlib, lualib = F.lualib;
  var LS = F.to_luastring, JS = F.to_jsstring;

  var canvas = document.getElementById('game');
  var ctx = canvas.getContext('2d');
  var W = canvas.width, H = canvas.height;
  var SW = W / 2, SH = H / 2;                 // world half-extents = pixels, origin centre
  function toX(x) { return SW + x; }
  function toY(y) { return SH - y; }

  // ---- scene model (what the bridge builds, what the renderer draws) --------
  var scene = new Map(), nextId = 0, hudText = '';
  var input = { x: null, y: null, down: false };
  var juice = { trauma: 0 };
  var tex = {};                               // name -> Image
  function texture(name) {
    if (!tex[name]) { var im = new Image(); im.src = 'textures/' + name + '.png'; tex[name] = im; }
    return tex[name];
  }

  // ---- localStorage typed KV (matches the Rust Bridge s:/n:/b: codec) --------
  function save(k, v) {
    var p = typeof v === 'number' ? 'n:' + v : typeof v === 'boolean' ? 'b:' + (v ? 1 : 0) : 's:' + v;
    try { localStorage.setItem('td.' + k, p); } catch (e) {}
  }
  function load(k) {
    var p; try { p = localStorage.getItem('td.' + k); } catch (e) { p = null; }
    if (p == null) return null;
    if (p.slice(0, 2) === 'n:') return Number(p.slice(2));
    if (p.slice(0, 2) === 'b:') return p.slice(2) === '1';
    return p.slice(2);
  }

  // ---- the `game.*` bridge — each is a fengari lua_CFunction (L)->nresults ---
  function num(L, i) { return lua.lua_tonumber(L, i); }
  function str(L, i) { return JS(lua.lua_tostring(L, i)); }

  var API = {
    log: function (L) { if (lua.lua_gettop(L) >= 1) console.log('[lua]', str(L, 1)); return 0; },
    bounds: function (L) { lua.lua_pushnumber(L, SW); lua.lua_pushnumber(L, SH); return 2; },
    pointer: function (L) {
      if (input.x === null) lua.lua_pushnil(L); else lua.lua_pushnumber(L, input.x);
      if (input.y === null) lua.lua_pushnil(L); else lua.lua_pushnumber(L, input.y);
      lua.lua_pushboolean(L, input.down ? 1 : 0); return 3;
    },
    key: function (L) { lua.lua_pushboolean(L, 0); return 1; },
    spawn: function (L) {
      var id = ++nextId;
      scene.set(id, { id: id, kind: 'rect', x: num(L, 1), y: num(L, 2), w: num(L, 3), h: num(L, 4),
        r: num(L, 5), g: num(L, 6), b: num(L, 7), a: lua.lua_gettop(L) >= 8 ? num(L, 8) : 1, rot: 0, z: id });
      lua.lua_pushnumber(L, id); return 1;
    },
    spawn_sprite: function (L) {
      var id = ++nextId;
      scene.set(id, { id: id, kind: 'sprite', x: num(L, 1), y: num(L, 2), w: num(L, 3), h: num(L, 4),
        tex: str(L, 5), r: 1, g: 1, b: 1, a: 1, rot: 0, z: id });
      lua.lua_pushnumber(L, id); return 1;
    },
    spawn_text: function (L) {
      var id = ++nextId;
      scene.set(id, { id: id, kind: 'text', x: num(L, 1), y: num(L, 2), size: num(L, 3),
        r: num(L, 4), g: num(L, 5), b: num(L, 6), a: num(L, 7), str: str(L, 8), rot: 0, z: id });
      lua.lua_pushnumber(L, id); return 1;
    },
    move_to: function (L) { var r = scene.get(num(L, 1)); if (r) { r.x = num(L, 2); r.y = num(L, 3); } return 0; },
    set_color: function (L) { var r = scene.get(num(L, 1)); if (r) { r.r = num(L, 2); r.g = num(L, 3); r.b = num(L, 4); if (lua.lua_gettop(L) >= 5) r.a = num(L, 5); } return 0; },
    set_size: function (L) { var r = scene.get(num(L, 1)); if (r) { r.w = num(L, 2); r.h = num(L, 3); } return 0; },
    set_rotation: function (L) { var r = scene.get(num(L, 1)); if (r) r.rot = num(L, 2); return 0; },
    set_sprite_image: function (L) { var r = scene.get(num(L, 1)); if (r) r.tex = str(L, 2); return 0; },
    despawn: function (L) { scene.delete(num(L, 1)); return 0; },
    set_text: function (L) { hudText = lua.lua_gettop(L) >= 1 ? str(L, 1) : ''; return 0; },
    // juice — minimal for the spike (renderer reads trauma; rest are no-ops/log)
    shake: function (L) { juice.trauma = Math.min(1, juice.trauma + num(L, 1)); return 0; },
    zoom: function (L) { return 0; },
    emit: function (L) { return 0; },
    play_sound: function (L) { return 0; },
    play_music: function (L) { return 0; },
    haptic: function (L) { return 0; },
    set_bg_theme: function (L) { return 0; },
    track: function (L) { return 0; },
    save: function (L) {
      var k = str(L, 1);
      if (lua.lua_isboolean(L, 2)) save(k, !!lua.lua_toboolean(L, 2));
      else if (lua.lua_isnumber(L, 2)) save(k, num(L, 2));
      else save(k, str(L, 2));
      lua.lua_pushboolean(L, 1); return 1;
    },
    load: function (L) {
      var v = load(str(L, 1));
      if (v === null) lua.lua_pushnil(L);
      else if (typeof v === 'number') lua.lua_pushnumber(L, v);
      else if (typeof v === 'boolean') lua.lua_pushboolean(L, v ? 1 : 0);
      else lua.lua_pushstring(L, LS(v));
      return 1;
    },
  };

  // ---- boot fengari, install `game`, load main.lua --------------------------
  var L = lauxlib.luaL_newstate();
  lualib.luaL_openlibs(L);
  lua.lua_newtable(L);
  Object.keys(API).forEach(function (name) {
    lua.lua_pushcfunction(L, API[name]);
    lua.lua_setfield(L, -2, LS(name));
  });
  lua.lua_setglobal(L, LS('game'));

  function callGlobal(name, args) {
    lua.lua_getglobal(L, LS(name));
    if (!lua.lua_isfunction(L, -1)) { lua.lua_pop(L, 1); return; }
    (args || []).forEach(function (a) { lua.lua_pushnumber(L, a); });
    if (lua.lua_pcall(L, (args || []).length, 0, 0) !== lua.LUA_OK) {
      console.error('[lua error in ' + name + ']', JS(lua.lua_tostring(L, -1)));
      lua.lua_pop(L, 1);
    }
  }

  window.__spikeBoot = function (luaSource) {
    if (lauxlib.luaL_loadstring(L, LS(luaSource)) !== lua.LUA_OK ||
        lua.lua_pcall(L, 0, 0, 0) !== lua.LUA_OK) {
      console.error('[lua load error]', JS(lua.lua_tostring(L, -1))); lua.lua_pop(L, 1); return;
    }
    callGlobal('on_start');

    // input
    function toWorld(cx, cy) { var r = canvas.getBoundingClientRect(); return { x: (cx - r.left) - SW, y: SH - (cy - r.top) }; }
    function setPtr(e, down) { var t = (e.touches && e.touches[0]) || e; var w = toWorld(t.clientX, t.clientY); input.x = w.x; input.y = w.y; if (down !== undefined) input.down = down; }
    canvas.addEventListener('mousedown', function (e) { setPtr(e, true); callGlobal('on_tap', [input.x, input.y]); });
    canvas.addEventListener('mousemove', function (e) { if (input.down) setPtr(e); });
    canvas.addEventListener('mouseup', function () { input.down = false; });
    canvas.addEventListener('touchstart', function (e) { e.preventDefault(); setPtr(e, true); callGlobal('on_tap', [input.x, input.y]); }, { passive: false });
    canvas.addEventListener('touchmove', function (e) { e.preventDefault(); setPtr(e); }, { passive: false });
    canvas.addEventListener('touchend', function () { input.down = false; });

    // frame loop
    var last = performance.now(), fpsN = 0, fpsT = 0, fps = 0;
    function frame(now) {
      var dt = (now - last) / 1000; last = now; if (dt > 0.1) dt = 0.1;
      fpsT += dt; fpsN++; if (fpsT >= 0.5) { fps = Math.round(fpsN / fpsT); fpsN = 0; fpsT = 0; window.__spikeFps = fps; }
      callGlobal('on_update', [dt]);
      draw(now / 1000);
      requestAnimationFrame(frame);
    }
    requestAnimationFrame(frame);
  };

  // ---- generic renderer over the scene map ----------------------------------
  function col(r, g, b, a) { return 'rgba(' + (r * 255 | 0) + ',' + (g * 255 | 0) + ',' + (b * 255 | 0) + ',' + (a === undefined ? 1 : a) + ')'; }
  function draw() {
    juice.trauma = Math.max(0, juice.trauma - 0.03);
    var amp = 16 * juice.trauma * juice.trauma;
    ctx.save();
    if (amp > 0.1) ctx.translate((Math.random() * 2 - 1) * amp, (Math.random() * 2 - 1) * amp);
    var g = ctx.createLinearGradient(0, 0, 0, H); g.addColorStop(0, '#0a0c18'); g.addColorStop(1, '#12102a');
    ctx.fillStyle = g; ctx.fillRect(-20, -20, W + 40, H + 40);
    var items = Array.from(scene.values()).sort(function (a, b) { return a.z - b.z; });
    for (var i = 0; i < items.length; i++) {
      var r = items[i], cx = toX(r.x), cy = toY(r.y);
      ctx.save(); ctx.translate(cx, cy); if (r.rot) ctx.rotate(-r.rot);
      if (r.kind === 'text') {
        ctx.fillStyle = col(r.r, r.g, r.b, r.a); ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
        ctx.font = '700 ' + r.size + 'px system-ui, sans-serif'; ctx.fillText(r.str, 0, 0);
      } else if (r.kind === 'sprite') {
        var im = texture(r.tex);
        if (im && im.complete && im.naturalWidth) { ctx.drawImage(im, -r.w / 2, -r.h / 2, r.w, r.h); }
        else { ctx.fillStyle = col(0.5, 0.6, 0.8, 0.9); ctx.fillRect(-r.w / 2, -r.h / 2, r.w, r.h); }
      } else {
        ctx.fillStyle = col(r.r, r.g, r.b, r.a); ctx.fillRect(-r.w / 2, -r.h / 2, r.w, r.h);
      }
      ctx.restore();
    }
    ctx.restore();
    if (hudText) { ctx.fillStyle = 'rgba(230,240,255,0.9)'; ctx.textAlign = 'left'; ctx.textBaseline = 'top'; ctx.font = '700 18px system-ui'; ctx.fillText(hudText, 12, 10); }
  }
})();
