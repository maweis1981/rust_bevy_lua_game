// admeta.js — shared rewarded-ad meta layer for the collection. Thin, reusable
// helpers so every game monetizes the SAME opt-in way (see
// docs/tiktok-minigame-selection.md): reward is granted only when the ad
// completes. Also owns a light collection-level "coins" balance + daily spin so
// the menu itself has a non-annoying rewarded touchpoint.
'use strict';

function createAdMeta(platform) {
  var store = (platform && platform.storage) || { get: function () { return null; }, set: function () {} };
  var rewardAd = (platform && platform.rewardAd) || function (cb) { cb(true); };
  var now = (platform && platform.now) ? platform.now : function () { return Date.now(); };

  function getNum(k, d) { var v = store.get(k); return v === null || v === undefined ? d : Number(v); }
  function setNum(k, v) { store.set(k, String(v)); }

  var api = {
    // coins: a tiny shared currency so end-of-run x2 / daily spin mean something
    coins: function () { return getNum('coins', 0); },
    addCoins: function (n) { var c = api.coins() + n; setNum('coins', c); return c; },

    // Rewarded "double this reward": grant base immediately is the caller's job;
    // this shows the ad and calls onDouble(extra) with the EXTRA amount on success.
    rewardedDouble: function (base, cb) {
      rewardAd(function (ok) { cb(ok ? base : 0); });
    },
    // Rewarded revive / continue: cb(true) if the player watched to completion.
    rewardedContinue: function (cb) { rewardAd(function (ok) { cb(!!ok); }); },
    // Generic: cb(rewarded:boolean).
    rewarded: function (cb) { rewardAd(function (ok) { cb(!!ok); }); },

    // Daily spin: available once per calendar-ish day (24h since last claim).
    dailyReady: function () { return now() - getNum('spin_at', 0) >= 24 * 3600 * 1000; },
    claimDaily: function (rng, cb) {
      // rewarded spin -> random coin prize; caller passes a 0..1 rng.
      rewardAd(function (ok) {
        if (!ok) { cb(0); return; }
        var prizes = [10, 20, 20, 30, 50, 100];
        var prize = prizes[Math.floor((rng ? rng() : 0.5) * prizes.length)] || 20;
        api.addCoins(prize); setNum('spin_at', now()); cb(prize);
      });
    },
  };
  return api;
}

module.exports = { createAdMeta: createAdMeta };
