// config.js — all tunables, ported 1:1 from assets/scripts/packs/timedodge.lua.
// Plain CommonJS so it loads in WeChat/Douyin mini-game runtimes AND in Node.
'use strict';

// World coordinate convention (matches the Bevy/Lua source): origin at screen
// centre, +y is UP. SW/SH are HALF-extents (hw, hh). The renderer converts to
// canvas pixels (y-down) at draw time; the game logic never sees pixels.

var C = {
  PLAYER: 26, FOE: 18, GATE: 34,
  // RELATIVE drag: the orb moves by the finger DELTA * sens, never to the
  // finger position, so the finger never covers the orb / incoming foes.
  DRAG_SENS: 1.5, KEY_SPEED: 460,
  PLAYER_MAX: 820,   // hard speed cap: a pointer jump never teleports the orb
  REF_SPEED: 300,    // px/s that reads as "dashing" (trail fx)
  TS_MIN: 0.06,      // near-frozen world rate while released
  TS_SMOOTH: 12,     // timescale attack/release rate
  SPEED0: 320, SPEED_PER_S: 8, SPEED_MAX: 500,
  SPAWN0: 0.55, SPAWN_MIN: 0.26, SPAWN_PER_S: 0.016,
  MAX_FOES: 40, OFF: 70,
  NEAR: 44, HIT_R: 19,
  MAX_DT: 1 / 30, TRAIL_N: 10,
  DRIFT_SPEED: 70,   // drifter real-time crawl px/s (immune to freeze)
  // 2.5D depth: meteors surface from the deep (z=1 far, z=0 in-plane). Only
  // rocks near the plane (z <= PLANE_Z) can touch you.
  Z_RATE: 1.2, PLANE_Z: 0.35,
  // ABSORB: eat rocks smaller than you (grow by area), bigger rocks chip you.
  MIN_MASS: 13, MAX_MASS: 120,
  EAT_GAIN: 1.0, CHIP: 0.75,   // area fraction kept / size kept on hit
  SAFE_C: [0.35, 0.90, 0.50], DANGER_C: [1.0, 0.25, 0.20],
  FROZEN_C: [0.55, 0.85, 1.0],
};

// Foe kinds — one colour + one motion signature each.
C.KINDS = {
  dart:     { c: [1.00, 0.30, 0.25] },
  surge:    { c: [1.00, 0.80, 0.25], accel: 1.0 },
  seeker:   { c: [0.75, 0.40, 1.00], turn: 1.6 },
  splitter: { c: [1.00, 0.55, 0.20], split_at: 1.1 },
  drifter:  { c: [0.92, 0.95, 1.00], real: true },
};

// Endless: foes wake at stolen-time milestones.
C.UNLOCKS = [
  { t: 0, k: 'dart' }, { t: 10, k: 'surge' }, { t: 20, k: 'seeker' },
  { t: 30, k: 'splitter' }, { t: 45, k: 'drifter' },
];

// Trials: seed fixes gate layout + spawn pattern so a level is the same moment
// every attempt. s3/s2 = real-second star thresholds.
C.LEVELS = [
  { seed: 101,  gates: 3, volley: 2, kinds: ['dart'],                                             speed: 240, every: 0.70, s3: 6,  s2: 10 },
  { seed: 202,  gates: 3, volley: 2, kinds: ['dart'],                                             speed: 255, every: 0.62, s3: 4,  s2: 7 },
  { seed: 303,  gates: 4, volley: 3, kinds: ['dart', 'surge'],                                    speed: 265, every: 0.58, s3: 7,  s2: 11 },
  { seed: 404,  gates: 4, volley: 3, kinds: ['dart', 'surge'],                                    speed: 275, every: 0.52, s3: 7,  s2: 11 },
  { seed: 505,  gates: 5, volley: 4, kinds: ['dart', 'surge', 'seeker'],                          speed: 285, every: 0.48, s3: 9,  s2: 14 },
  { seed: 606,  gates: 5, volley: 4, kinds: ['dart', 'surge', 'seeker'],                          speed: 295, every: 0.44, s3: 9,  s2: 14 },
  { seed: 707,  gates: 6, volley: 5, kinds: ['dart', 'seeker', 'splitter'],                       speed: 305, every: 0.40, s3: 16, s2: 25 },
  { seed: 808,  gates: 6, volley: 5, kinds: ['dart', 'surge', 'splitter'],                        speed: 315, every: 0.36, s3: 19, s2: 30 },
  { seed: 909,  gates: 7, volley: 4, kinds: ['dart', 'dart', 'seeker', 'splitter', 'drifter'],    speed: 320, every: 0.33, s3: 20, s2: 32 },
  { seed: 1010, gates: 8, volley: 6, kinds: ['dart', 'surge', 'seeker', 'splitter', 'drifter'],   speed: 335, every: 0.30, s3: 39, s2: 63 },
];

C.SPONSOR_URL = 'https://google.com'; // parity with the Lua game.open_url target

function clamp(v, lo, hi) { return v < lo ? lo : (v > hi ? hi : v); }
C.clamp = clamp;

module.exports = C;
