// tiktok/adapter.js — the ONLY TikTok-specific glue. TikTok Minis' HTML runtime
// is a real webview (DOM, <canvas>, localStorage, DOM touch events), so this
// adapter is plain web APIs — with the rewarded video ad routed through the
// TikTok SDK (TTMinis.game.createRewardedVideoAd). It exposes the same
// `platform` shape the shared engine expects (see shared/main.js), published as
// window.createTikTokPlatform() so index.html can hand it to startGame().
//
// Loaded as a classic <script> (not a module), after engine.bundle.js.
'use strict';

(function () {
  function createTikTokPlatform() {
    var canvas = document.getElementById('game');
    if (!canvas) { canvas = document.createElement('canvas'); document.body.appendChild(canvas); }

    // Size in LOGICAL (CSS) pixels so world units + touch clientX/Y map 1:1,
    // matching the original game's tuning and the wx/tt adapters.
    function resize() {
      canvas.width = Math.floor(window.innerWidth);
      canvas.height = Math.floor(window.innerHeight);
    }
    resize();
    window.addEventListener('resize', resize);

    function localXY(clientX, clientY) {
      var r = canvas.getBoundingClientRect();
      return { x: clientX - r.left, y: clientY - r.top };
    }

    // Touch (primary) + mouse (desktop preview) unified into (px, py).
    function onStart(cb) {
      canvas.addEventListener('touchstart', function (e) {
        e.preventDefault();
        var t = e.touches[0]; if (t) { var p = localXY(t.clientX, t.clientY); cb(p.x, p.y); }
      }, { passive: false });
      canvas.addEventListener('mousedown', function (e) { var p = localXY(e.clientX, e.clientY); cb(p.x, p.y); });
    }
    function onMove(cb) {
      canvas.addEventListener('touchmove', function (e) {
        e.preventDefault();
        var t = e.touches[0]; if (t) { var p = localXY(t.clientX, t.clientY); cb(p.x, p.y); }
      }, { passive: false });
      canvas.addEventListener('mousemove', function (e) {
        if (e.buttons) { var p = localXY(e.clientX, e.clientY); cb(p.x, p.y); }
      });
    }
    function onEnd(cb) {
      canvas.addEventListener('touchend', function (e) { e.preventDefault(); cb(); }, { passive: false });
      canvas.addEventListener('touchcancel', function () { cb(); });
      canvas.addEventListener('mouseup', function () { cb(); });
    }

    // Rewarded video ad via the TikTok SDK. TTMinis.game.createRewardedVideoAd
    // mirrors the wx/tt shape (singleton .show()/.load() + a close callback that
    // reports completion). NOTE(ship): confirm the exact close/reward event
    // field against the portal's rewarded-ad doc — modeled on isEnded here.
    function makeRewardAd() {
      var ad = null, pending = null;
      function ensure() {
        if (ad) return ad;
        if (typeof TTMinis === 'undefined' || !TTMinis.game || !TTMinis.game.createRewardedVideoAd) return null;
        // TODO(ship): replace with your real TikTok ad unit id (Developer
        // Portal → Monetization / Ads).
        ad = TTMinis.game.createRewardedVideoAd({ adUnitId: 'YOUR_TIKTOK_AD_UNIT_ID' });
        if (ad.onClose) ad.onClose(function (res) {
          var cb = pending; pending = null;
          if (cb) cb(!!(res && res.isEnded)); // reward only if watched to the end
        });
        if (ad.onError) ad.onError(function () { var cb = pending; pending = null; if (cb) cb(false); });
        return ad;
      }
      return function rewardAd(cb) {
        var a = ensure();
        if (!a) { cb(true); return; }  // no ad component (plain preview) -> waive
        pending = cb;
        var showP = a.show && a.show();
        if (showP && showP.catch) {
          showP.catch(function () {
            if (a.load) { a.load().then(function () { return a.show(); }).catch(function () {
              var c = pending; pending = null; if (c) c(false);
            }); } else { var c = pending; pending = null; if (c) c(false); }
          });
        }
      };
    }

    var storage = {
      get: function (key) {
        try { var v = window.localStorage.getItem(key); return (v === null || v === '') ? null : v; }
        catch (e) { return null; }
      },
      set: function (key, val) {
        try { window.localStorage.setItem(key, String(val)); } catch (e) {}
      },
    };

    var raf = (typeof requestAnimationFrame !== 'undefined')
      ? function (cb) { requestAnimationFrame(cb); }
      : function (cb) { setTimeout(cb, 16); };

    // Web Audio context for the procedural SFX synth (shared/sound.js). Created
    // lazily and cached; starts suspended and is resumed on the first touch.
    var _actx = null;
    function audioContext() {
      if (_actx) return _actx;
      try {
        var AC = (typeof window !== 'undefined') && (window.AudioContext || window.webkitAudioContext);
        if (AC) _actx = new AC();
      } catch (e) { _actx = null; }
      return _actx;
    }

    return {
      canvas: canvas,
      onTouchStart: onStart,
      onTouchMove: onMove,
      onTouchEnd: onEnd,
      storage: storage,
      rewardAd: makeRewardAd(),
      audio: audioContext,
      raf: raf,
      now: function () {
        return (typeof performance !== 'undefined' && performance.now) ? performance.now() : Date.now();
      },
      haptic: function (style) {
        if (typeof navigator !== 'undefined' && navigator.vibrate) {
          navigator.vibrate(style === 'heavy' ? 20 : style === 'medium' ? 12 : 6);
        }
      },
    };
  }

  window.createTikTokPlatform = createTikTokPlatform;
})();
