// sound.js — tiny procedural SFX synth (no audio files to bundle). Given a Web
// Audio context (standard AudioContext on TikTok's HTML webview; the same shape
// from wx.createWebAudioContext / tt.createWebAudioContext on WeChat/Douyin), it
// synthesizes the game's three cues — 'score', 'hit', 'wall' — from oscillators
// and a noise burst. All calls are guarded so a missing method or a suspended
// context never throws into the game loop.
'use strict';

function createSound(ctx) {
  var noiseBuf = null;
  function noise() {
    if (!ctx || !ctx.createBuffer) return null;
    if (noiseBuf) return noiseBuf;
    var n = Math.floor((ctx.sampleRate || 44100) * 0.3);
    noiseBuf = ctx.createBuffer(1, n, ctx.sampleRate || 44100);
    var d = noiseBuf.getChannelData(0);
    for (var i = 0; i < n; i++) d[i] = Math.random() * 2 - 1;
    return noiseBuf;
  }
  function env(g, t0, dur, peak) {
    g.gain.setValueAtTime(0.0001, t0);
    g.gain.exponentialRampToValueAtTime(peak, t0 + 0.008);
    g.gain.exponentialRampToValueAtTime(0.0001, t0 + dur);
  }
  function tone(freq, t0, dur, type, peak) {
    var o = ctx.createOscillator(), g = ctx.createGain();
    o.type = type || 'sine';
    o.frequency.setValueAtTime(freq, t0);
    o.connect(g); g.connect(ctx.destination);
    env(g, t0, dur, peak || 0.2);
    o.start(t0); o.stop(t0 + dur + 0.03);
  }
  function thud(t0, dur, peak, cut) {
    var buf = noise(); if (!buf) return;
    var s = ctx.createBufferSource(); s.buffer = buf;
    var g = ctx.createGain();
    var chain = g;
    if (ctx.createBiquadFilter) {
      var f = ctx.createBiquadFilter();
      f.type = 'lowpass'; f.frequency.value = cut || 1000;
      s.connect(f); f.connect(g);
    } else { s.connect(g); }
    g.connect(ctx.destination);
    env(g, t0, dur, peak || 0.3);
    s.start(t0); s.stop(t0 + dur + 0.03);
  }

  function play(name) {
    if (!ctx || !ctx.createOscillator) return;
    try {
      var t = (ctx.currentTime || 0) + 0.001;
      if (name === 'score') {            // bright rising two-tone (reward)
        tone(660, t, 0.12, 'triangle', 0.16);
        tone(990, t + 0.06, 0.16, 'triangle', 0.14);
      } else if (name === 'hit') {       // punchy impact (eat / death)
        thud(t, 0.16, 0.32, 900);
        tone(150, t, 0.14, 'sine', 0.20);
      } else if (name === 'wall') {      // low thunk (near-miss / chip / dialog)
        tone(210, t, 0.10, 'square', 0.11);
        thud(t, 0.07, 0.14, 550);
      } else {
        tone(440, t, 0.10, 'sine', 0.13);
      }
    } catch (e) { /* audio is non-critical */ }
  }
  function resume() { try { if (ctx && ctx.resume) ctx.resume(); } catch (e) {} }

  return { play: play, resume: resume };
}

module.exports = { createSound: createSound };
