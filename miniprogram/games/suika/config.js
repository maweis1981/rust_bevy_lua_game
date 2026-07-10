// config.js — Suika (watermelon merge-drop) tunables. Plain CommonJS (loads in
// Node + the browser bundle). Pure data + pure helpers only, so logic.js can
// require it headless in the test harness. Radii are expressed as a fraction of
// the bin width so the whole sim scales with any canvas size.
'use strict';

var C = {
  // --- fruit tiers 0..N (N = TIER_COUNT-1). Classic Suika has 11 tiers. -------
  TIER_COUNT: 11,
  // radius as a fraction of bin width, monotonically increasing. Tier 10 has a
  // diameter of ~0.58*binW so the biggest fruit still fits inside the bin.
  RADII_FRAC: [0.040, 0.052, 0.066, 0.082, 0.100, 0.120, 0.145, 0.172, 0.205, 0.245, 0.290],
  // merge value: fusing two tier-t fruit awards POINTS[t] (classic triangular).
  POINTS: [1, 3, 6, 10, 15, 21, 28, 36, 45, 55, 66],
  // popping a pair of MAX-tier fruit awards this bonus (see logic.mergePop).
  MAX_POP_BONUS: 100,
  // per-tier fill colors (0..10).
  COLORS: [
    '#e6394a', // 0 cherry (red)
    '#ff7b29', // 1 strawberry (orange)
    '#f5b301', // 2 grape-amber
    '#c3e330', // 3 dekopon (lime)
    '#ffa64d', // 4 orange
    '#ff5d73', // 5 apple (pink-red)
    '#b6e14b', // 6 pear
    '#f0a6c8', // 7 peach
    '#8f6df0', // 8 pineapple-purple
    '#69d07a', // 9 melon (green)
    '#37b24d', // 10 watermelon (deep green)
  ],

  // --- droppable tiers: only small fruit (0..4) spawn from the top; anything
  // bigger only ever arises from a merge (standard Suika). ---------------------
  DROP_MIN_TIER: 0,
  DROP_MAX_TIER: 4,

  // --- physics ---------------------------------------------------------------
  // All *_FRAC scale with binW so feel is size-independent.
  GRAVITY_FRAC: 4.0,        // gravity px/s^2 = GRAVITY_FRAC * binW
  MAX_SPEED_FRAC: 5.0,      // velocity clamp px/s = MAX_SPEED_FRAC * binW
  WALL_RESTITUTION: 0.18,   // energy kept on wall/floor bounce
  PAIR_RESTITUTION: 0.05,   // tiny bounce between fruit (keep small = stable)
  AIR_DAMP: 0.999,          // per fixed-step velocity damping
  REST_SPEED_FRAC: 0.6,     // "settled" if speed < REST_SPEED_FRAC * binW
  FIXED_DT: 1 / 120,        // physics fixed timestep (s)
  SUBSTEPS: 2,              // integration substeps per fixed step
  ITERS: 4,                 // position-relaxation iterations per substep
  MAX_STEPS_PER_FRAME: 6,   // clamp catch-up so a hitch can't explode the sim
  MAX_FRUIT: 120,           // hard cap on live fruit

  // --- game rules ------------------------------------------------------------
  DANGER_SECONDS: 2.0,      // rest above the line this long -> game over
  DANGER_LINE_FRAC: 0.12,   // danger line y = binTop + DANGER_LINE_FRAC*binH
  DROP_COOLDOWN: 0.35,      // min seconds between drops
  REVIVE_CLEAR: 5,          // fruit cleared from the top on a REVIVE reward

  // --- palette / chrome ------------------------------------------------------
  BG: '#0b1020',
  BIN_WALL: 'rgba(255,255,255,0.22)',
  BIN_FILL: 'rgba(255,255,255,0.04)',
  DANGER: '#e6394a',
  TEXT: '#eaf0ff',
  SUBTEXT: '#9fb0d0',

  // radius (px) of a fruit of `tier` in a bin `binW` px wide.
  radiusOf: function (tier, binW) {
    var f = C.RADII_FRAC[Math.min(tier, C.RADII_FRAC.length - 1)];
    return f * binW;
  },
  colorOf: function (tier) { return C.COLORS[Math.min(tier, C.COLORS.length - 1)]; },
};

module.exports = C;
