// logic.js — Ball / Water Sort pure state machine. NO rendering, NO platform,
// NO DOM — so it runs identically in the mini-game runtimes, in the TikTok
// webview, and headless in Node (test.js). All randomness comes from the same
// exact LCG as shared/rng.js, seeded, so a given (seed, difficulty) reproduces
// the same solvable level every time.
//
// Model: an array of `tubes`, each a stack (index 0 = bottom) of color ids
// 0..K-1, capacity CAP. A "pour" moves the contiguous run of equal colors on
// TOP of tube `from` onto tube `to`, legal iff `to` is empty or its top color
// equals the run's color and it has room. Win = every tube empty or a single
// full color.
'use strict';

// --- exact LCG (mirrors shared/rng.js) -------------------------------------
var A = 1103515245n, Cc = 12345n, M = 2147483648n;
function newLcg(seed) {
  var s = BigInt(seed >>> 0) % M;
  return function () { s = (A * s + Cc) % M; return Number(s) / 2147483648; };
}

// --- tube helpers ----------------------------------------------------------
function topColor(t) { return t.length ? t[t.length - 1] : -1; }
function runLen(t) { // length of the equal-color run on top
  if (!t.length) return 0;
  var c = t[t.length - 1], n = 1;
  for (var i = t.length - 2; i >= 0; i--) { if (t[i] === c) n++; else break; }
  return n;
}
function isUniformFull(t, cap) {
  if (t.length !== cap) return false;
  for (var i = 1; i < t.length; i++) if (t[i] !== t[0]) return false;
  return true;
}
function canPour(tubes, from, to, cap) {
  if (from === to) return false;
  var a = tubes[from], b = tubes[to];
  if (!a.length) return false;
  if (isUniformFull(a, cap)) return false;         // no point moving a solved tube
  if (b.length >= cap) return false;
  if (!b.length) return true;
  return topColor(a) === topColor(b);
}
function pourCount(tubes, from, to, cap) {         // how many units actually move
  var a = tubes[from], b = tubes[to];
  return Math.min(runLen(a), cap - b.length);
}
function isWin(tubes, cap) {
  for (var i = 0; i < tubes.length; i++) {
    var t = tubes[i];
    if (t.length === 0) continue;
    if (!isUniformFull(t, cap)) return false;
  }
  return true;
}
function cloneTubes(tubes) { return tubes.map(function (t) { return t.slice(); }); }
function key(tubes) {
  // canonical key: sort tube strings so permutations of identical tubes collapse
  return tubes.map(function (t) { return t.join(','); }).sort().join('|');
}

// --- solver (BFS + parent backpointers) — returns the FULL shortest solution
// as a list of [from,to] moves, or null (unsolvable), or undefined (gave up at
// nodeCap). Used to guarantee gen-solvability AND to power the hint reward.
// BFS (shortest) makes greedy hint-following converge instead of oscillating.
function solve(tubes, cap, nodeCap) {
  nodeCap = nodeCap || 300000;
  var startKey = key(tubes);
  if (isWin(tubes, cap)) return [];
  var visited = {};                 // key -> { pkey, move }
  visited[startKey] = { pkey: null, move: null };
  var queue = [{ t: cloneTubes(tubes), k: startKey }];
  var head = 0, nodes = 0;
  while (head < queue.length) {
    if (++nodes > nodeCap) return undefined;
    var cur = queue[head++];
    var n = cur.t.length;
    for (var f = 0; f < n; f++) {
      for (var to = 0; to < n; to++) {
        if (!canPour(cur.t, f, to, cap)) continue;
        var nt = cloneTubes(cur.t);
        var cnt = pourCount(cur.t, f, to, cap);
        var col = topColor(nt[f]);
        for (var m = 0; m < cnt; m++) { nt[f].pop(); nt[to].push(col); }
        var nk = key(nt);
        if (visited[nk]) continue;
        visited[nk] = { pkey: cur.k, move: [f, to] };
        if (isWin(nt, cap)) {                      // reconstruct path
          var moves = [], k = nk;
          while (visited[k] && visited[k].move) { moves.push(visited[k].move); k = visited[k].pkey; }
          moves.reverse();
          return moves;
        }
        queue.push({ t: nt, k: nk });
      }
    }
  }
  return null;
}
// First move of a shortest solution, or null/undefined. (hint reward)
function solveFirstMove(tubes, cap, nodeCap) {
  var s = solve(tubes, cap, nodeCap);
  if (s === null || s === undefined) return s;
  return s.length ? s[0] : null;
}
function isSolvable(tubes, cap) {
  var s = solve(tubes, cap);
  return s !== null && s !== undefined;   // solvable if a path (possibly empty) exists
}

// --- level generation ------------------------------------------------------
// K colors, CAP units each, plus EMPTY spare tubes. Distribute all color units
// randomly across the (K+EMPTY) tubes respecting capacity, then require the
// solver to confirm solvability; reshuffle (bounded) until solvable.
function genLevel(seed, opts) {
  opts = opts || {};
  var cap = opts.cap || 4;
  var colors = opts.colors || 4;
  var empty = opts.empty || 2;
  var rnd = newLcg(seed);
  var attempt = 0;
  while (true) {
    attempt++;
    // multiset of color units
    var bag = [];
    for (var c = 0; c < colors; c++) for (var i = 0; i < cap; i++) bag.push(c);
    // Fisher-Yates with the seeded rng
    for (var j = bag.length - 1; j > 0; j--) {
      var r = Math.floor(rnd() * (j + 1));
      var tmp = bag[j]; bag[j] = bag[r]; bag[r] = tmp;
    }
    var tubes = [];
    for (var t = 0; t < colors; t++) tubes.push(bag.slice(t * cap, t * cap + cap));
    for (var e = 0; e < empty; e++) tubes.push([]);
    // reject trivially-solved layouts and unsolvable ones
    if (!isWin(tubes, cap) && isSolvable(tubes, cap)) {
      return { tubes: tubes, cap: cap, colors: colors, empty: empty, seed: seed };
    }
    if (attempt > 200) { // extremely unlikely; return last (solver-checked) anyway
      return { tubes: tubes, cap: cap, colors: colors, empty: empty, seed: seed };
    }
  }
}

// --- the playable game object ----------------------------------------------
// createLevel returns a stateful controller with legal-move enforcement, undo,
// hint, and reward-driven extras (+1 tube). Selection model for tap input:
//   select(i): first tap picks a source tube (with a movable top run);
//              second tap on a legal dest pours; tapping the source again or an
//              illegal dest deselects.
function createLevel(seed, opts) {
  var L = genLevel(seed, opts);
  var S = {
    tubes: L.tubes, cap: L.cap, colors: L.colors, seed: seed,
    selected: -1, moves: 0, history: [], won: false,
    extraTubes: 0, hintsUsed: 0, undosUsed: 0,
  };

  function doPour(from, to) {
    var cnt = pourCount(S.tubes, from, to, S.cap);
    var col = topColor(S.tubes[from]);
    S.history.push({ from: from, to: to, cnt: cnt });
    for (var m = 0; m < cnt; m++) { S.tubes[from].pop(); S.tubes[to].push(col); }
    S.moves++;
    S.won = isWin(S.tubes, S.cap);
    return cnt;
  }

  return {
    state: S,
    // input: tap tube index i. Returns an event string for juice hooks.
    select: function (i) {
      if (S.won || i < 0 || i >= S.tubes.length) return 'none';
      if (S.selected === -1) {
        if (!S.tubes[i].length || isUniformFull(S.tubes[i], S.cap)) return 'empty-pick';
        S.selected = i; return 'pick';
      }
      if (i === S.selected) { S.selected = -1; return 'deselect'; }
      if (canPour(S.tubes, S.selected, i, S.cap)) {
        doPour(S.selected, i); S.selected = -1;
        return S.won ? 'win' : 'pour';
      }
      // illegal dest: if the tapped tube is itself pickable, switch selection
      if (S.tubes[i].length && !isUniformFull(S.tubes[i], S.cap)) { S.selected = i; return 'reselect'; }
      S.selected = -1; return 'illegal';
    },
    undo: function () {
      if (!S.history.length) return false;
      var mv = S.history.pop();
      var col = topColor(S.tubes[mv.to]);
      for (var m = 0; m < mv.cnt; m++) { S.tubes[mv.to].pop(); S.tubes[mv.from].push(col); }
      S.moves = Math.max(0, S.moves - 1); S.won = false; S.selected = -1;
      S.undosUsed++; return true;
    },
    // reward: add one empty spare tube (makes stuck boards solvable/easier).
    addTube: function () { S.tubes.push([]); S.extraTubes++; S.selected = -1; return true; },
    // reward: return the solver's next move [from,to], or null if none/unknown.
    hint: function () { S.hintsUsed++; return solveFirstMove(S.tubes, S.cap); },
    // full shortest solution from the current board (used by tests / autoplay).
    solve: function () { return solve(S.tubes, S.cap); },
    isStuck: function () {
      // any legal move available?
      for (var f = 0; f < S.tubes.length; f++)
        for (var t = 0; t < S.tubes.length; t++)
          if (canPour(S.tubes, f, t, S.cap)) return false;
      return !S.won;
    },
  };
}

module.exports = {
  newLcg: newLcg, topColor: topColor, runLen: runLen, isUniformFull: isUniformFull,
  canPour: canPour, pourCount: pourCount, isWin: isWin, solve: solve,
  solveFirstMove: solveFirstMove, isSolvable: isSolvable, genLevel: genLevel,
  createLevel: createLevel, key: key,
};
