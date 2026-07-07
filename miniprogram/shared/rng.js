// rng.js — the exact LCG from timedodge.lua (new_lcg), so seeded TRIALS levels
// reproduce the same "sealed moment" every attempt.
//
//   Lua:  s = (1103515245 * s + 12345) % 2147483648; return s / 2147483648
//
// Lua 5.4 does this in 64-bit integers. JS Numbers are IEEE doubles that lose
// precision above 2^53, and 1103515245 * (up to 2^31) ~ 2.4e18 overflows that.
// BigInt gives us the exact integer result (V8-based mini-game engines support
// it); we only leave BigInt at the final [0,1) division.
'use strict';

var A = 1103515245n, Cc = 12345n, M = 2147483648n; // 2^31

function newLcg(seed) {
  var s = BigInt(seed) % M;
  return function () {
    s = (A * s + Cc) % M;
    return Number(s) / 2147483648;
  };
}

module.exports = { newLcg: newLcg };
