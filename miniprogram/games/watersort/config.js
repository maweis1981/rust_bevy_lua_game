// config.js — Water Sort tunables. Plain CommonJS (loads in Node + the browser
// bundle). Difficulty ramps colors/empties with the level index; caps keep it
// inside the "cozy hyper-casual" band the TikTok selection analysis calls for.
'use strict';

var C = {
  CAP: 4,                 // units per tube
  BASE_COLORS: 3,         // colors at level 1
  MAX_COLORS: 8,          // hard cap (palette length)
  BASE_EMPTY: 2,          // spare empty tubes
  // level index -> generation opts
  levelOpts: function (level) {
    var colors = Math.min(C.MAX_COLORS, C.BASE_COLORS + Math.floor((level - 1) / 2));
    var empty = C.BASE_EMPTY;                 // keep 2 spares; harder as colors grow
    return { cap: C.CAP, colors: colors, empty: empty };
  },
  // distinct, high-contrast fills for color ids 0..7 (TikTok-friendly warm-ish set)
  PALETTE: [
    '#e6394a', // red
    '#2ea3f2', // blue
    '#37c871', // green
    '#f5b301', // amber
    '#9b5de5', // purple
    '#ff7b29', // orange
    '#00c2b8', // teal
    '#e85d9c', // pink
  ],
  BG: '#0b1020',
  TUBE_GLASS: 'rgba(255,255,255,0.10)',
  TUBE_EDGE: 'rgba(255,255,255,0.28)',
  TEXT: '#eaf0ff',
  SUBTEXT: '#9fb0d0',
  POUR_MS: 260,           // pour animation duration
};

module.exports = C;
