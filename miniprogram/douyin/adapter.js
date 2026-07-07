// douyin/adapter.js — the ONLY Douyin-specific code. The twin of
// wechat/adapter.js with the tt.* namespace. Douyin mirrors the WeChat
// mini-game API almost 1:1, so this is a near-identical file.
'use strict';

/* global tt */

function makeCanvas() {
  var canvas = tt.createCanvas();
  var info = tt.getSystemInfoSync();
  canvas.width = info.windowWidth;
  canvas.height = info.windowHeight;
  return canvas;
}

function makeRewardAd() {
  var ad = null, pending = null;
  function ensure() {
    if (ad) return ad;
    if (!tt.createRewardedVideoAd) return null;
    // TODO(ship): replace with your real Douyin ad unit id from the
    // 抖音开放平台 (developer.open-douyin.com) 变现/广告 console.
    ad = tt.createRewardedVideoAd({ adUnitId: 'YOUR_DOUYIN_AD_UNIT_ID' });
    ad.onClose(function (res) {
      var cb = pending; pending = null;
      if (cb) cb(!!(res && res.isEnded)); // reward only if watched to the end
    });
    ad.onError(function () { var cb = pending; pending = null; if (cb) cb(false); });
    return ad;
  }
  return function rewardAd(cb) {
    var a = ensure();
    if (!a) { cb(true); return; } // no ad component (e.g. DevTools) -> waive
    pending = cb;
    a.show().catch(function () {
      a.load().then(function () { return a.show(); }).catch(function () {
        var c = pending; pending = null; if (c) c(false);
      });
    });
  };
}

function haptic(style) {
  if (!tt.vibrateShort) return;
  try { tt.vibrateShort({ type: style === 'heavy' ? 'heavy' : 'light' }); }
  catch (e) { try { tt.vibrateShort(); } catch (e2) {} }
}

module.exports = {
  canvas: makeCanvas(),
  onTouchStart: function (cb) { tt.onTouchStart(function (e) { var t = e.touches[0]; if (t) cb(t.clientX, t.clientY); }); },
  onTouchMove: function (cb) { tt.onTouchMove(function (e) { var t = e.touches[0]; if (t) cb(t.clientX, t.clientY); }); },
  onTouchEnd: function (cb) { tt.onTouchEnd(function () { cb(); }); tt.onTouchCancel(function () { cb(); }); },
  storage: {
    get: function (key) { var v = tt.getStorageSync(key); return (v === '' || v === undefined || v === null) ? null : v; },
    set: function (key, val) { tt.setStorageSync(key, val); },
  },
  rewardAd: makeRewardAd(),
  // Subpackage loader for boot/launch.js. tt.loadSubpackage mirrors wx's; it
  // returns a task whose .onProgress reports { progress: 0..100 }.
  loadSubpackage: (typeof tt !== 'undefined' && typeof tt.loadSubpackage === 'function')
    ? function (opts) { return tt.loadSubpackage(opts); }
    : null,
  raf: function (cb) { (typeof requestAnimationFrame !== 'undefined' ? requestAnimationFrame : function (f) { setTimeout(f, 16); })(cb); },
  now: function () { return Date.now(); },
  haptic: haptic,
};
