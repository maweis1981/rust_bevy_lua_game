// wechat/adapter.js — the ONLY WeChat-specific code. Binds the wx.* surface to
// the platform interface the shared code expects. Douyin's adapter is the twin
// of this with tt.* (see douyin/adapter.js).
'use strict';

/* global wx */

function makeCanvas() {
  var canvas = wx.createCanvas();
  var info = wx.getWindowInfo ? wx.getWindowInfo() : wx.getSystemInfoSync();
  // Size the canvas in LOGICAL pixels so world units match the original game's
  // tuning and touch coords (clientX/clientY are logical) map 1:1.
  canvas.width = info.windowWidth;
  canvas.height = info.windowHeight;
  return canvas;
}

function makeRewardAd() {
  var ad = null, pending = null;
  function ensure() {
    if (ad) return ad;
    if (!wx.createRewardedVideoAd) return null;
    // TODO(ship): replace 'adunit-XXXXXXXXXXXXXXXX' with your real WeChat ad
    // unit id from the mp.weixin.qq.com 流量主 (traffic master) console.
    ad = wx.createRewardedVideoAd({ adUnitId: 'adunit-XXXXXXXXXXXXXXXX' });
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
  if (!wx.vibrateShort) return;
  try {
    if (style === 'heavy') wx.vibrateShort({ type: 'heavy' });
    else if (style === 'medium') wx.vibrateShort({ type: 'medium' });
    else wx.vibrateShort({ type: 'light' });
  } catch (e) { /* some bases only accept no-arg */ try { wx.vibrateShort(); } catch (e2) {} }
}

module.exports = {
  canvas: makeCanvas(),
  onTouchStart: function (cb) { wx.onTouchStart(function (e) { var t = e.touches[0]; if (t) cb(t.clientX, t.clientY); }); },
  onTouchMove: function (cb) { wx.onTouchMove(function (e) { var t = e.touches[0]; if (t) cb(t.clientX, t.clientY); }); },
  onTouchEnd: function (cb) { wx.onTouchEnd(function () { cb(); }); wx.onTouchCancel(function () { cb(); }); },
  storage: {
    get: function (key) { var v = wx.getStorageSync(key); return (v === '' || v === undefined || v === null) ? null : v; },
    set: function (key, val) { wx.setStorageSync(key, val); },
  },
  rewardAd: makeRewardAd(),
  // Subpackage loader for boot/launch.js. wx.loadSubpackage downloads the
  // `engine` subpackage (game.json) and returns a task whose .onProgress
  // reports { progress: 0..100, totalBytesWritten, totalBytesExpectedToWrite }.
  loadSubpackage: (typeof wx !== 'undefined' && typeof wx.loadSubpackage === 'function')
    ? function (opts) { return wx.loadSubpackage(opts); }
    : null,
  raf: function (cb) { (typeof requestAnimationFrame !== 'undefined' ? requestAnimationFrame : function (f) { setTimeout(f, 16); })(cb); },
  now: function () { return Date.now(); },
  haptic: haptic,
};
