// engine.js — the fengari runtime. Runs the UNMODIFIED native game scripts
// (assets/scripts/main.lua + packs, byte-for-byte) on the TikTok / web target
// via fengari (a Lua 5.3 VM in JS), over a JS `game.*` bridge + a Canvas 2D
// renderer that IS the "native presentation" backend for this platform.
//
// This is the production runtime, not the spike: every `game.*` the shipped
// packs call is implemented for real — particles, Web Audio (sfx/music/voice),
// zoom + camera, a reactive cosmic/nebula background (space_mode / set_bg_theme),
// vignette + energy bloom postFx. The Lua stays identical across mlua (iOS),
// ottavino (wasm), and this fengari path — see docs/PLATFORM_BLUEPRINT.md.
'use strict';

(function () {
  var F = fengari;
  var lua = F.lua, lauxlib = F.lauxlib, lualib = F.lualib;
  var LS = F.to_luastring, JS = F.to_jsstring;

  // ---- canvas / world -------------------------------------------------------
  var canvas = document.getElementById('game');
  var ctx = canvas.getContext('2d', { alpha: false });
  var W = canvas.width, H = canvas.height;
  var SW = W / 2, SH = H / 2;          // world half-extents; origin centre, +y up
  function toX(x) { return SW + x; }
  function toY(y) { return SH - y; }

  // ---- scene model (Lua mutates this; the renderer draws it) ----------------
  var scene = new Map(), nextId = 0, hudText = '';

  // ---- input ----------------------------------------------------------------
  var input = { x: null, y: null, down: false, touches: [] };
  var keys = {};
  var today = currentUtcDate();

  // ---- camera + juice -------------------------------------------------------
  var cam = { x: 0, y: 0, zoom: 1 };   // game.cam(dx,dy,zoom)
  var shake = { trauma: 0 };           // game.shake -> trauma
  var punch = { zoom: 0 };             // game.zoom  -> punch-in trauma
  var energy = 0;                      // smoothed trauma; drives bg reactivity

  // ---- background -----------------------------------------------------------
  var bg = { space: false, theme: 0, t: 0 };
  var STARS = makeStars(140);
  var NEBULA = makeNebula(5);

  // ---- particles ------------------------------------------------------------
  // Two looks: soft additive GLOW discs (sparks/embers/splash — real light) and
  // solid spinning BITS (confetti/debris). Presets carry native's 4 names plus a
  // grey "debris" burst for impacts. drag slows them so they settle, not fly flat.
  var PCAP = 512, parts = [];
  var PRESETS = {
    spark:    { speed: [200, 360], grav: -260, drag: 2.2, ttl: 0.45, size: 6, up: false, count: 18, glow: true,
                cols: [[1, 0.85, 0.35], [1, 0.6, 0.2], [1, 0.95, 0.7]] },
    dust:     { speed: [30, 100],  grav: -40,  drag: 1.6, ttl: 0.80, size: 7, up: false, count: 14, glow: true,
                cols: [[0.62, 0.55, 0.45], [0.72, 0.66, 0.55]] },
    confetti: { speed: [140, 300], grav: -260, drag: 0.6, ttl: 1.30, size: 7, up: true,  count: 24, glow: false,
                cols: [[0.95, 0.35, 0.45], [0.35, 0.75, 0.95], [0.95, 0.85, 0.35], [0.55, 0.9, 0.5], [0.8, 0.5, 0.95]] },
    splash:   { speed: [150, 300], grav: -460, drag: 1.0, ttl: 0.55, size: 5, up: true,  count: 20, glow: true,
                cols: [[0.5, 0.75, 0.95], [0.7, 0.88, 1.0]] },
    debris:   { speed: [120, 320], grav: -360, drag: 1.2, ttl: 0.70, size: 5, up: false, count: 16, glow: false,
                cols: [[0.72, 0.74, 0.80], [0.55, 0.57, 0.62], [0.88, 0.88, 0.94]] },
  };
  function emit(preset, x, y, count) {
    var p = PRESETS[preset] || PRESETS.spark;
    var n = count || p.count;
    for (var i = 0; i < n && parts.length < PCAP; i++) {
      var ang = p.up ? Math.PI * Math.random() : Math.PI * 2 * Math.random();
      var sp = p.speed[0] + Math.random() * (p.speed[1] - p.speed[0]);
      var c = p.cols[(Math.random() * p.cols.length) | 0];
      parts.push({ x: x, y: y, vx: Math.cos(ang) * sp, vy: Math.sin(ang) * sp,
        life: p.ttl, ttl: p.ttl, size: p.size * (0.7 + 0.6 * Math.random()),
        r: c[0], g: c[1], b: c[2], grav: p.grav, drag: p.drag || 0, glow: p.glow,
        rot: Math.random() * 6.28, spin: (Math.random() * 2 - 1) * 8 });
    }
  }
  function stepParticles(dt) {
    for (var i = parts.length - 1; i >= 0; i--) {
      var p = parts[i];
      p.life -= dt;
      if (p.life <= 0) { parts.splice(i, 1); continue; }
      var d = 1 - Math.min(0.9, (p.drag || 0) * dt);
      p.vx *= d; p.vy = p.vy * d + p.grav * dt;
      p.x += p.vx * dt; p.y += p.vy * dt; p.rot += p.spin * dt;
    }
  }

  // Soft glow disc, pre-rendered once and tinted+cached per quantized colour so
  // particles read as real light rather than flat squares.
  var GLOW = document.createElement('canvas'); GLOW.width = GLOW.height = 64;
  (function () {
    var g = GLOW.getContext('2d');
    var rg = g.createRadialGradient(32, 32, 0, 32, 32, 32);
    rg.addColorStop(0, 'rgba(255,255,255,1)');
    rg.addColorStop(0.35, 'rgba(255,255,255,0.6)');
    rg.addColorStop(1, 'rgba(255,255,255,0)');
    g.fillStyle = rg; g.fillRect(0, 0, 64, 64);
  })();
  var glowCache = {};
  function glowFor(r, g, b) {
    var key = ((r * 5) | 0) + '_' + ((g * 5) | 0) + '_' + ((b * 5) | 0);
    if (glowCache[key]) return glowCache[key];
    var c = document.createElement('canvas'); c.width = c.height = 64;
    var cx = c.getContext('2d');
    cx.drawImage(GLOW, 0, 0);
    cx.globalCompositeOperation = 'source-in';
    cx.fillStyle = 'rgb(' + (r * 255 | 0) + ',' + (g * 255 | 0) + ',' + (b * 255 | 0) + ')';
    cx.fillRect(0, 0, 64, 64);
    glowCache[key] = c; return c;
  }

  // ---- audio (Web Audio; sfx overlap+dedup, one music loop, one voice) ------
  var AC = window.AudioContext || window.webkitAudioContext;
  var actx = null, buffers = {}, pending = {}, vol = { sfx: 1, music: 1, voice: 1 };
  var musicName = null, musicGain = null, musicSrc = null;
  var voiceSrc = null, sfxPlayedThisFrame = {};
  function audioBase() { return (window.__AUDIO_BASE || 'audio/'); }
  function ensureAudio() {
    if (!actx && AC) { try { actx = new AC(); } catch (e) { actx = null; } }
    if (actx && actx.state === 'suspended') actx.resume();
    return actx;
  }
  function getBuffer(name, cb) {
    if (buffers[name]) { cb(buffers[name]); return; }
    if (buffers[name] === null) { return; }               // known-missing: skip
    if (pending[name]) { pending[name].push(cb); return; }
    pending[name] = [cb];
    fetch(audioBase() + name + '.wav').then(function (r) {
      if (!r.ok) throw 0; return r.arrayBuffer();
    }).then(function (buf) {
      return actx.decodeAudioData(buf);
    }).then(function (dec) {
      buffers[name] = dec; (pending[name] || []).forEach(function (f) { f(dec); }); delete pending[name];
    }).catch(function () { buffers[name] = null; delete pending[name]; });   // silent no-op
  }
  function playSound(name) {
    if (!ensureAudio()) return;
    if (sfxPlayedThisFrame[name]) return;                 // dedup identical within a frame
    sfxPlayedThisFrame[name] = true;
    if (name.slice(0, 2) === 'ui') { synthUi(name); return; }   // synthesized console blip
    getBuffer(name, function (b) {
      var s = actx.createBufferSource(); s.buffer = b;
      var g = actx.createGain(); g.gain.value = vol.sfx;
      s.connect(g); g.connect(actx.destination); s.start();
    });
  }
  // Sci-fi UI sounds, synthesized (no asset) — a starship-console blip for taps,
  // a rising chime for confirm, a falling one for back. ui_tap/ui/ui_confirm/ui_back.
  function synthUi(name) {
    var t = actx.currentTime, dur, f0, f1;
    if (name === 'ui_back') { f0 = 540; f1 = 300; dur = 0.10; }
    else if (name === 'ui_confirm') { f0 = 480; f1 = 900; dur = 0.15; }
    else { f0 = 680; f1 = 940; dur = 0.07; }              // ui / ui_tap
    function tone(type, mul, gain) {
      var o = actx.createOscillator(), g = actx.createGain();
      o.type = type;
      o.frequency.setValueAtTime(f0 * mul, t);
      o.frequency.exponentialRampToValueAtTime(f1 * mul, t + dur);
      g.gain.setValueAtTime(0.0001, t);
      g.gain.exponentialRampToValueAtTime(gain * vol.sfx, t + 0.006);
      g.gain.exponentialRampToValueAtTime(0.0001, t + dur);
      o.connect(g); g.connect(actx.destination); o.start(t); o.stop(t + dur + 0.02);
    }
    tone('square', 1, 0.16);
    tone('triangle', 2, 0.05);                            // a harmonic for "console" timbre
  }
  function playMusic(name) {
    if (!ensureAudio()) return;
    if (musicName === name) return;                       // already looping this track
    if (musicSrc) { try { musicSrc.stop(); } catch (e) {} musicSrc = null; }
    musicName = name;
    getBuffer(name, function (b) {
      if (musicName !== name) return;                     // switched again while loading
      musicSrc = actx.createBufferSource(); musicSrc.buffer = b; musicSrc.loop = true;
      musicGain = actx.createGain(); musicGain.gain.value = vol.music;
      musicSrc.connect(musicGain); musicGain.connect(actx.destination); musicSrc.start();
    });
  }
  function stopMusic() { if (musicSrc) { try { musicSrc.stop(); } catch (e) {} } musicSrc = null; musicName = null; }
  function playVoice(name) {
    if (!ensureAudio()) return;
    if (voiceSrc) { try { voiceSrc.stop(); } catch (e) {} voiceSrc = null; }
    getBuffer(name, function (b) {
      voiceSrc = actx.createBufferSource(); voiceSrc.buffer = b;
      var g = actx.createGain(); g.gain.value = vol.voice;
      voiceSrc.connect(g); g.connect(actx.destination); voiceSrc.start();
      voiceSrc.onended = function () { voiceSrc = null; };
    });
  }
  function stopVoice() { if (voiceSrc) { try { voiceSrc.stop(); } catch (e) {} } voiceSrc = null; }
  function setVolume(ch, v) {
    if (vol[ch] === undefined) return;
    vol[ch] = Math.max(0, Math.min(1, v));
    if (ch === 'music' && musicGain) musicGain.gain.value = vol.music;
  }

  // ---- textures -------------------------------------------------------------
  var tex = {};
  function texBase() { return (window.__TEX_BASE || 'textures/'); }
  function texture(name) {
    if (!tex[name]) { var im = new Image(); im.src = texBase() + name + '.png'; tex[name] = im; }
    return tex[name];
  }

  // Texture TINTING — the native/wasm path multiplies each Sprite by its color
  // (foe kind-colours, ABSORB green/red danger, freeze blue, gate pulse, player
  // tint). Canvas drawImage can't tint, so multiply the texture on a scratch
  // canvas then clip to its alpha (destination-in). Only tinted when the colour
  // is meaningfully non-white, so white sprites stay a plain fast blit.
  var _tc = document.createElement('canvas'), _tcx = _tc.getContext('2d');
  function drawTinted(im, sx, sy, sw, sh, w, h, r, g, b) {
    var iw = Math.max(1, Math.ceil(w)), ih = Math.max(1, Math.ceil(h));
    if (_tc.width < iw) _tc.width = iw;
    if (_tc.height < ih) _tc.height = ih;
    _tcx.clearRect(0, 0, iw, ih);
    _tcx.globalCompositeOperation = 'source-over';
    _tcx.drawImage(im, sx, sy, sw, sh, 0, 0, iw, ih);
    _tcx.globalCompositeOperation = 'multiply';
    _tcx.fillStyle = 'rgb(' + (r * 255 | 0) + ',' + (g * 255 | 0) + ',' + (b * 255 | 0) + ')';
    _tcx.fillRect(0, 0, iw, ih);
    _tcx.globalCompositeOperation = 'destination-in';   // clip the fill to the sprite's alpha
    _tcx.drawImage(im, sx, sy, sw, sh, 0, 0, iw, ih);
    _tcx.globalCompositeOperation = 'source-over';
    ctx.drawImage(_tc, 0, 0, iw, ih, -w / 2, -h / 2, w, h);
  }

  // ---- typed KV over localStorage (matches native s:/n:/b: codec) -----------
  function save(k, v) {
    var p = typeof v === 'number' ? 'n:' + v : typeof v === 'boolean' ? 'b:' + (v ? 1 : 0) : 's:' + v;
    try { localStorage.setItem('hl.' + k, p); } catch (e) {}
  }
  function load(k) {
    var p; try { p = localStorage.getItem('hl.' + k); } catch (e) { p = null; }
    if (p == null) return null;
    if (p.slice(0, 2) === 'n:') return Number(p.slice(2));
    if (p.slice(0, 2) === 'b:') return p.slice(2) === '1';
    return p.slice(2);
  }

  // ---- TikTok rewarded video ads (TTMinis) ----------------------------------
  // game.ad_ready(kind) -> can we show an ad? game.ad_reward(kind, cb) shows a
  // rewarded video; cb(granted, reason) fires EXACTLY once. Per the TTMinis IAA
  // docs: createRewardedVideoAd({adUnitId}) -> show() (Promise; no load()) +
  // onClose(res => res.isEnded) for reward-earned. Instances are single-use.
  // Register each adUnitId in the TikTok Developer Portal and paste it here.
  var AD_UNITS = {
    revive: 'YOUR_REVIVE_AD_UNIT_ID',
    cancel_hit: 'YOUR_CANCEL_HIT_AD_UNIT_ID',
    default: 'YOUR_AD_UNIT_ID',
  };
  // Where ads have NO fill for a user's region (e.g. you hold rewarded-ad rights
  // in some countries but not the US), still grant the reward so REVIVE / cancel-
  // hit never become dead buttons. Only a genuine SKIP (the user opened an ad and
  // closed it early) is denied. Set false to withhold the reward on no-fill.
  var AD_GRANT_ON_NOFILL = true;
  function adsAvailable() {
    // Ads-off build (e.g. the US app, which ships without IAA — see the two-app
    // split in package-timedodge.sh). No ad object is ever created or shown.
    if (window.__ADS_ENABLED === false) return false;
    return !!(window.TTMinis && window.TTMinis.game && window.TTMinis.game.createRewardedVideoAd);
  }
  function requestRewarded(kind, done) {
    var fired = false;
    function finish(g, r) { if (fired) return; fired = true; done(g, r); }
    if (!adsAvailable()) return finish(false, 'unsupported');   // no SDK (native/web/preview)
    var adUnitId = AD_UNITS[kind] || AD_UNITS.default;
    var ad;
    try { ad = window.TTMinis.game.createRewardedVideoAd({ adUnitId: adUnitId }); }
    catch (e) { return finish(AD_GRANT_ON_NOFILL, 'create_failed'); }
    // Watched to completion -> reward. Closed early -> denied (a real skip).
    try { ad.onClose(function (res) { finish(!!(res && res.isEnded), (res && res.isEnded) ? 'earned' : 'closed_early'); }); } catch (e) {}
    // No inventory / network / not-ready (e.g. an unpermitted region) -> treat as
    // "no ad to watch" and grant, so the feature still works everywhere.
    try { ad.onError(function (err) { finish(AD_GRANT_ON_NOFILL, 'nofill:' + ((err && err.errCode) || 'unknown')); }); } catch (e) {}
    try { var pr = ad.show(); if (pr && pr.catch) pr.catch(function () { finish(AD_GRANT_ON_NOFILL, 'show_failed'); }); }
    catch (e) { finish(AD_GRANT_ON_NOFILL, 'show_failed'); }
  }

  // ---- the game.* bridge (each is a fengari lua_CFunction) -------------------
  function num(L, i) { return lua.lua_tonumber(L, i); }
  function opt(L, i, d) { return lua.lua_gettop(L) >= i && !lua.lua_isnoneornil(L, i) ? lua.lua_tonumber(L, i) : d; }
  function str(L, i) { return JS(lua.lua_tostring(L, i)); }

  var API = {
    // ---- reads ----
    bounds: function (L) { lua.lua_pushnumber(L, SW); lua.lua_pushnumber(L, SH); return 2; },
    pointer: function (L) {
      if (input.x === null) lua.lua_pushnil(L); else lua.lua_pushnumber(L, input.x);
      if (input.y === null) lua.lua_pushnil(L); else lua.lua_pushnumber(L, input.y);
      lua.lua_pushboolean(L, input.down ? 1 : 0); return 3;
    },
    touches: function (L) {
      lua.lua_newtable(L);
      for (var i = 0; i < input.touches.length; i++) {
        var t = input.touches[i];
        lua.lua_newtable(L);
        lua.lua_pushnumber(L, t.x); lua.lua_setfield(L, -2, LS('x'));
        lua.lua_pushnumber(L, t.y); lua.lua_setfield(L, -2, LS('y'));
        lua.lua_rawseti(L, -2, i + 1);
      }
      return 1;
    },
    key: function (L) { lua.lua_pushboolean(L, keys[str(L, 1)] ? 1 : 0); return 1; },
    date_utc: function (L) {
      lua.lua_pushnumber(L, today.y); lua.lua_pushnumber(L, today.m); lua.lua_pushnumber(L, today.d); return 3;
    },

    // ---- scene: spawn / mutate / despawn ----
    spawn: function (L) {
      var id = ++nextId;
      scene.set(id, { id: id, kind: 'rect', x: num(L, 1), y: num(L, 2), w: num(L, 3), h: num(L, 4),
        r: num(L, 5), g: num(L, 6), b: num(L, 7), a: opt(L, 8, 1), rot: 0, z: id });
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
    spawn_sheet: function (L) {   // (x,y,w,h,name,cols,rows) — a sprite with frame sub-rects
      var id = ++nextId;
      scene.set(id, { id: id, kind: 'sprite', x: num(L, 1), y: num(L, 2), w: num(L, 3), h: num(L, 4),
        tex: str(L, 5), cols: opt(L, 6, 1), rows: opt(L, 7, 1), frame: 0, r: 1, g: 1, b: 1, a: 1, rot: 0, z: id });
      lua.lua_pushnumber(L, id); return 1;
    },
    set_frame: function (L) { var r = scene.get(num(L, 1)); if (r) r.frame = num(L, 2) | 0; return 0; },
    move_to: function (L) { var r = scene.get(num(L, 1)); if (r) { r.x = num(L, 2); r.y = num(L, 3); } return 0; },
    set_color: function (L) { var r = scene.get(num(L, 1)); if (r) { r.r = num(L, 2); r.g = num(L, 3); r.b = num(L, 4); if (lua.lua_gettop(L) >= 5) r.a = num(L, 5); } return 0; },
    set_size: function (L) { var r = scene.get(num(L, 1)); if (r) { r.w = num(L, 2); r.h = num(L, 3); } return 0; },
    set_rotation: function (L) { var r = scene.get(num(L, 1)); if (r) r.rot = num(L, 2); return 0; },
    set_sprite_image: function (L) { var r = scene.get(num(L, 1)); if (r) r.tex = str(L, 2); return 0; },
    despawn: function (L) { scene.delete(num(L, 1)); return 0; },
    set_text: function (L) { hudText = lua.lua_gettop(L) >= 1 && !lua.lua_isnil(L, 1) ? str(L, 1) : ''; return 0; },

    // ---- camera + juice ----
    shake: function (L) { shake.trauma = Math.min(1, shake.trauma + num(L, 1)); return 0; },
    zoom: function (L) { punch.zoom = Math.min(1, punch.zoom + num(L, 1)); return 0; },
    cam: function (L) { cam.x = opt(L, 1, 0); cam.y = opt(L, 2, 0); cam.zoom = opt(L, 3, 1) || 1; return 0; },
    emit: function (L) { emit(str(L, 1), num(L, 2), num(L, 3), opt(L, 4, 0)); return 0; },
    set_bg_theme: function (L) { bg.theme = num(L, 1) | 0; return 0; },
    space_mode: function (L) { bg.space = lua.lua_toboolean(L, 1) ? true : false; return 0; },
    haptic: function (L) {
      if (navigator.vibrate) {
        var s = str(L, 1);
        // Punchier patterns so impacts read on the body, not just the eyes.
        var pat = s === 'heavy' ? [40, 25, 30] : s === 'medium' ? 22
          : s === 'success' ? [15, 30, 15, 30, 22] : 12;
        try { navigator.vibrate(pat); } catch (e) {}
      }
      return 0;
    },

    // ---- audio ----
    play_sound: function (L) { playSound(str(L, 1)); return 0; },
    play_music: function (L) { playMusic(str(L, 1)); return 0; },
    stop_music: function (L) { stopMusic(); return 0; },
    play_voice: function (L) { playVoice(str(L, 1)); return 0; },
    stop_voice: function (L) { stopVoice(); return 0; },
    set_volume: function (L) { setVolume(str(L, 1), num(L, 2)); return 0; },

    // ---- persistence + misc ----
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
    track: function (L) { return 0; },   // analytics sink lives in the native bridge; no-op here
    log: function (L) { if (lua.lua_gettop(L) >= 1) console.log('[lua]', str(L, 1)); return 0; },
    open_url: function (L) { try { window.open(str(L, 1), '_blank'); } catch (e) {} return 0; },

    // ---- ads: TikTok rewarded video (see requestRewarded above) ----
    ad_moment: function (L) { return 0; },              // opportunity hint; no-op on this runtime
    ad_ready: function (L) { lua.lua_pushboolean(L, adsAvailable() ? 1 : 0); return 1; },
    ad_reward: function (L) {
      var kind = str(L, 1);
      lua.lua_pushvalue(L, 2);                          // stash the Lua callback in the registry
      var ref = lauxlib.luaL_ref(L, lua.LUA_REGISTRYINDEX);
      requestRewarded(kind, function (granted, reason) {
        lua.lua_rawgeti(L, lua.LUA_REGISTRYINDEX, ref); // fetch + fire cb(granted, reason) exactly once
        if (lua.lua_isfunction(L, -1)) {
          lua.lua_pushboolean(L, granted ? 1 : 0);
          lua.lua_pushstring(L, LS(reason || ''));
          if (lua.lua_pcall(L, 2, 0, 0) !== lua.LUA_OK) { console.error('[ad_reward cb]', JS(lua.lua_tostring(L, -1))); lua.lua_pop(L, 1); }
        } else { lua.lua_pop(L, 1); }
        lauxlib.luaL_unref(L, lua.LUA_REGISTRYINDEX, ref);
      });
      return 0;
    },

    // ---- skeletal rigs / tilemap: showcase-only, not in the ship bundle. Kept
    //      as safe stubs so nothing errors if a pack references them. ----
    spawn_rig: function (L) { lua.lua_pushnumber(L, ++nextId); return 1; },
    play_anim: function (L) { return 0; },
    set_bone: function (L) { return 0; },
    tilemap: function (L) { lua.lua_pushnumber(L, ++nextId); return 1; },
    set_tile: function (L) { return 0; },
  };

  // ---- boot fengari, install `game` -----------------------------------------
  var L = lauxlib.luaL_newstate();
  lualib.luaL_openlibs(L);
  lua.lua_newtable(L);
  Object.keys(API).forEach(function (name) {
    lua.lua_pushcfunction(L, API[name]);
    lua.lua_setfield(L, -2, LS(name));
  });
  lua.lua_setglobal(L, LS('game'));

  function loadChunk(src, name) {
    if (lauxlib.luaL_loadbuffer(L, LS(src), src.length, LS('@' + name)) !== lua.LUA_OK ||
        lua.lua_pcall(L, 0, 0, 0) !== lua.LUA_OK) {
      console.error('[lua load error: ' + name + ']', JS(lua.lua_tostring(L, -1))); lua.lua_pop(L, 1);
      return false;
    }
    return true;
  }
  function callGlobal(name, args) {
    lua.lua_getglobal(L, LS(name));
    if (!lua.lua_isfunction(L, -1)) { lua.lua_pop(L, 1); return; }
    (args || []).forEach(function (a) { lua.lua_pushnumber(L, a); });
    if (lua.lua_pcall(L, (args || []).length, 0, 0) !== lua.LUA_OK) {
      console.error('[lua error in ' + name + ']', JS(lua.lua_tostring(L, -1))); lua.lua_pop(L, 1);
    }
  }

  // Public boot: `packs` = [{name, src}] loaded first (they self-register into
  // PACKS), then `mainSrc` (main.lua) which reads PACKS in on_start. `autoboot`
  // optionally sets the landing scene (e.g. "timedodge" for an ad-campaign build).
  window.__hlBoot = function (packs, mainSrc, autoboot, standalone) {
    (packs || []).forEach(function (p) { loadChunk(p.src, p.name); });
    if (autoboot) loadChunk('AUTOBOOT = "' + String(autoboot).replace(/"/g, '') + '"', 'autoboot');
    // Single-game build: the game's own screen is the home — no "return to the
    // collection" affordance (there is no collection). Scripts read STANDALONE.
    if (standalone) loadChunk('STANDALONE = true', 'standalone');
    if (!loadChunk(mainSrc, 'main.lua')) return;
    ensureAudio();
    callGlobal('on_start');
    wireInput();
    startLoop();
  };
  // Back-compat single-source boot (the original spike entry).
  window.__spikeBoot = function (mainSrc) { window.__hlBoot([], mainSrc, null); };

  // ---- input wiring ---------------------------------------------------------
  function wireInput() {
    function toWorld(cx, cy) { var r = canvas.getBoundingClientRect();
      var sx = W / r.width, sy = H / r.height;
      return { x: (cx - r.left) * sx - SW, y: SH - (cy - r.top) * sy }; }
    function refreshTouches(e) {
      input.touches = [];
      if (e.touches) for (var i = 0; i < e.touches.length; i++) {
        input.touches.push(toWorld(e.touches[i].clientX, e.touches[i].clientY));
      }
    }
    function setPtr(e, down) {
      var t = (e.touches && e.touches[0]) || e; var w = toWorld(t.clientX, t.clientY);
      input.x = w.x; input.y = w.y; if (down !== undefined) input.down = down;
    }
    canvas.addEventListener('mousedown', function (e) { ensureAudio(); setPtr(e, true); callGlobal('on_tap', [input.x, input.y]); });
    canvas.addEventListener('mousemove', function (e) { if (input.down) setPtr(e); });
    window.addEventListener('mouseup', function () { input.down = false; });
    canvas.addEventListener('touchstart', function (e) { e.preventDefault(); ensureAudio(); setPtr(e, true); refreshTouches(e); callGlobal('on_tap', [input.x, input.y]); }, { passive: false });
    canvas.addEventListener('touchmove', function (e) { e.preventDefault(); setPtr(e); refreshTouches(e); }, { passive: false });
    canvas.addEventListener('touchend', function (e) { input.down = false; refreshTouches(e); }, { passive: false });
    var KMAP = { ArrowUp: 'up', ArrowDown: 'down', ArrowLeft: 'left', ArrowRight: 'right', ' ': 'space',
      w: 'up', s: 'down', a: 'left', d: 'right', W: 'up', S: 'down', A: 'left', D: 'right' };
    window.addEventListener('keydown', function (e) { var k = KMAP[e.key]; if (k) keys[k] = true; });
    window.addEventListener('keyup', function (e) { var k = KMAP[e.key]; if (k) keys[k] = false; });
    document.addEventListener('visibilitychange', function () { if (document.hidden && actx) actx.suspend(); else ensureAudio(); });
  }

  // ---- frame loop -----------------------------------------------------------
  function startLoop() {
    var last = performance.now(), fpsN = 0, fpsT = 0;
    function frame(now) {
      var dt = (now - last) / 1000; last = now; if (dt > 0.1) dt = 0.1;
      fpsT += dt; fpsN++; if (fpsT >= 0.5) { window.__hlFps = window.__spikeFps = Math.round(fpsN / fpsT); fpsN = 0; fpsT = 0; }
      sfxPlayedThisFrame = {};
      callGlobal('on_update', [dt]);
      stepParticles(dt);
      // trauma bleed + energy smoothing (attack-fast / release-slow, like the shader)
      shake.trauma = Math.max(0, shake.trauma - dt * 1.2);
      punch.zoom = Math.max(0, punch.zoom - dt * 2.2);
      var target = shake.trauma;
      energy += (target - energy) * (target > energy ? 0.5 : 0.05);
      bg.t += dt;
      draw();
      requestAnimationFrame(frame);
    }
    requestAnimationFrame(frame);
  }

  // ---- renderer -------------------------------------------------------------
  function col(r, g, b, a) { return 'rgba(' + (r * 255 | 0) + ',' + (g * 255 | 0) + ',' + (b * 255 | 0) + ',' + (a === undefined ? 1 : a) + ')'; }

  function drawBackground() {
    var g = ctx.createLinearGradient(0, 0, 0, H);
    if (bg.space) { g.addColorStop(0, '#05060f'); g.addColorStop(1, '#0b0820'); }
    else if (bg.theme === 1) { g.addColorStop(0, '#0c1420'); g.addColorStop(1, '#161022'); }
    else { g.addColorStop(0, '#0a0c18'); g.addColorStop(1, '#12102a'); }
    ctx.fillStyle = g; ctx.fillRect(0, 0, W, H);

    if (bg.space) {
      // drifting nebula blobs (cheap radial gradients)
      ctx.globalCompositeOperation = 'lighter';
      for (var n = 0; n < NEBULA.length; n++) {
        var b2 = NEBULA[n];
        var cx = (b2.x + Math.sin(bg.t * b2.sp) * 40 + W) % W;
        var cy = (b2.y + bg.t * b2.drift) % (H + 200) - 100;
        var rg = ctx.createRadialGradient(cx, cy, 0, cx, cy, b2.r);
        var bloom = 0.06 + energy * 0.10;
        rg.addColorStop(0, 'rgba(' + b2.c + ',' + bloom + ')'); rg.addColorStop(1, 'rgba(' + b2.c + ',0)');
        ctx.fillStyle = rg; ctx.fillRect(cx - b2.r, cy - b2.r, b2.r * 2, b2.r * 2);
      }
      ctx.globalCompositeOperation = 'source-over';
    }
    // stars (twinkle; brighter in space)
    var base = bg.space ? 0.9 : 0.5;
    for (var i = 0; i < STARS.length; i++) {
      var s = STARS[i];
      var y = (s.y + bg.t * s.pz * 14) % H;
      var tw = base * (0.5 + 0.5 * Math.sin(bg.t * s.tw + s.ph));
      ctx.fillStyle = 'rgba(200,220,255,' + (tw * s.b).toFixed(3) + ')';
      ctx.fillRect(s.x, y, s.sz, s.sz);
    }
  }

  function draw() {
    ctx.setTransform(1, 0, 0, 1, 0, 0);
    drawBackground();

    // camera: cam zoom * zoom-punch, + shake jitter, around centre
    var pz = 1 - 0.06 * punch.zoom * punch.zoom;         // native zoom_scale punch-in
    var s = cam.zoom * pz;
    var amp = 16 * shake.trauma * shake.trauma;
    var jx = (Math.random() * 2 - 1) * amp, jy = (Math.random() * 2 - 1) * amp;
    ctx.save();
    ctx.translate(SW + jx, SH + jy);
    ctx.scale(s, s);
    ctx.translate(-SW, -SH);
    ctx.translate(-cam.x, cam.y);

    // scene, z-sorted
    var items = Array.from(scene.values()).sort(function (a, b) { return a.z - b.z; });
    for (var i = 0; i < items.length; i++) {
      var r = items[i], cx = toX(r.x), cy = toY(r.y);
      ctx.save(); ctx.translate(cx, cy); if (r.rot) ctx.rotate(-r.rot);
      if (r.kind === 'text') {
        ctx.fillStyle = col(r.r, r.g, r.b, r.a);
        ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
        var font = 'system-ui, -apple-system, "Segoe UI", sans-serif';
        ctx.font = '700 ' + r.size + 'px ' + font;
        // Auto-fit: the system font is wider than the native subset, so long
        // centred lines can overrun the canvas — shrink to fit with a margin.
        var maxW = W - 20;
        var mw = ctx.measureText(r.str).width;
        if (mw > maxW) ctx.font = '700 ' + (r.size * maxW / mw) + 'px ' + font;
        ctx.fillText(r.str, 0, 0);
      } else if (r.kind === 'sprite') {
        var im = texture(r.tex);
        var ready = im && im.complete && im.naturalWidth;
        if (r.a !== undefined && r.a < 1) ctx.globalAlpha = r.a;
        // Tint when the sprite colour is meaningfully non-white (foe kind-colours,
        // ABSORB danger, freeze, gate pulse, player). White sprites blit plainly.
        var tint = r.r < 0.96 || r.g < 0.96 || r.b < 0.96;
        if (ready) {
          var sw2 = im.naturalWidth, sh2 = im.naturalHeight, sx2 = 0, sy2 = 0;
          if (r.cols) {
            sw2 = im.naturalWidth / r.cols; sh2 = im.naturalHeight / r.rows;
            sx2 = (r.frame % r.cols) * sw2; sy2 = ((r.frame / r.cols) | 0) * sh2;
          }
          if (tint) {
            drawTinted(im, sx2, sy2, sw2, sh2, r.w, r.h, r.r, r.g, r.b);
          } else {
            ctx.drawImage(im, sx2, sy2, sw2, sh2, -r.w / 2, -r.h / 2, r.w, r.h);
          }
        } else {
          ctx.fillStyle = col(r.r * 0.6 + 0.2, r.g * 0.6 + 0.25, r.b * 0.6 + 0.35, r.a);
          ctx.fillRect(-r.w / 2, -r.h / 2, r.w, r.h);
        }
        ctx.globalAlpha = 1;
      } else {
        ctx.fillStyle = col(r.r, r.g, r.b, r.a);
        ctx.fillRect(-r.w / 2, -r.h / 2, r.w, r.h);
      }
      ctx.restore();
    }

    // particles — pass 1: additive glow discs; pass 2: solid spinning bits
    if (parts.length) {
      var k, p, a, px, py;
      ctx.globalCompositeOperation = 'lighter';
      for (k = 0; k < parts.length; k++) {
        p = parts[k]; if (!p.glow) continue;
        a = Math.max(0, p.life / p.ttl);
        px = toX(p.x); py = toY(p.y);
        var gz = p.size * (1.4 + 1.6 * (1 - a));      // bloom out as it fades
        ctx.globalAlpha = a;
        ctx.drawImage(glowFor(p.r, p.g, p.b), px - gz, py - gz, gz * 2, gz * 2);
      }
      ctx.globalCompositeOperation = 'source-over';
      for (k = 0; k < parts.length; k++) {
        p = parts[k]; if (p.glow) continue;
        a = Math.max(0, p.life / p.ttl);
        px = toX(p.x); py = toY(p.y);
        ctx.globalAlpha = Math.min(1, a * 1.6);
        ctx.fillStyle = col(p.r, p.g, p.b, 1);
        ctx.save(); ctx.translate(px, py); ctx.rotate(p.rot);
        ctx.fillRect(-p.size / 2, -p.size / 2, p.size, p.size * 0.62); ctx.restore();
      }
      ctx.globalAlpha = 1;
    }
    ctx.restore();

    // ---- postFx (screen space) ----
    // energy bloom: a cyan-white wash on impacts, like the shader's flash
    if (energy > 0.01) {
      ctx.fillStyle = 'rgba(120,200,255,' + (energy * 0.12).toFixed(3) + ')';
      ctx.fillRect(0, 0, W, H);
    }
    // vignette
    var vg = ctx.createRadialGradient(SW, SH, SH * 0.55, SW, SH, SH * 1.15);
    vg.addColorStop(0, 'rgba(0,0,0,0)'); vg.addColorStop(1, 'rgba(0,0,0,0.42)');
    ctx.fillStyle = vg; ctx.fillRect(0, 0, W, H);

    // HUD (top-left)
    if (hudText) {
      ctx.fillStyle = 'rgba(230,240,255,0.94)'; ctx.textAlign = 'left'; ctx.textBaseline = 'top';
      ctx.font = '700 18px system-ui, -apple-system, sans-serif';
      ctx.fillText(hudText, 14, 12);
    }
  }

  // ---- small helpers --------------------------------------------------------
  function makeStars(n) {
    var a = [];
    for (var i = 0; i < n; i++) a.push({ x: Math.random() * W, y: Math.random() * H,
      sz: Math.random() < 0.8 ? 1 : 2, b: 0.4 + Math.random() * 0.6, tw: 1 + Math.random() * 3,
      ph: Math.random() * 6.28, pz: 0.2 + Math.random() * 0.8 });
    return a;
  }
  function makeNebula(n) {
    var cols = ['80,120,255', '160,90,255', '60,180,220', '200,90,160', '90,140,255'];
    var a = [];
    for (var i = 0; i < n; i++) a.push({ x: Math.random() * W, y: Math.random() * H,
      r: 180 + Math.random() * 220, c: cols[i % cols.length], sp: 0.1 + Math.random() * 0.3, drift: 4 + Math.random() * 8 });
    return a;
  }
  function currentUtcDate() { var d = new Date(); return { y: d.getUTCFullYear(), m: d.getUTCMonth() + 1, d: d.getUTCDate() }; }
})();
