// boot/launch.js — MAIN-PACKAGE launcher. Shows the loading screen, downloads
// the `engine` subpackage via the platform's loadSubpackage (wx/tt), tracks
// progress, and once it's in, hands control to the engine's boot callback.
//
// Why a subpackage? WeChat/Douyin mini-GAMES hard-cap the MAIN package at 4 MB
// (total 20 MB via subpackages). Keeping the engine in a subpackage keeps the
// main package tiny and — the real point — makes this a COLLECTION shell: each
// additional game becomes its own subpackage loaded on demand, so the launcher
// never grows. See RESEARCH.md §3 and README "Subpackage (分包) architecture".
//
// Platform-free (no wx/tt reference) so test/run.js can drive it headless.
'use strict';

var createLoading = require('./loading.js').createLoading;

// platform: the adapter object (needs .canvas, .raf, and optionally
//           .loadSubpackage(opts) -> task-with-.onProgress).
// boot:     function(platform) invoked once the engine subpackage is loaded.
function launch(platform, boot) {
  var screen = createLoading(platform.canvas, platform.raf);

  function go() {
    screen.setProgress(1);
    screen.stop();
    boot(platform);
  }

  var loadSub = platform.loadSubpackage;
  // Fallback: environments without subpackage loading (e.g. a plain preview, or
  // a DevTools base that inlines everything) — the engine files still exist
  // under engine/, so boot directly.
  if (typeof loadSub !== 'function') {
    go();
    return;
  }

  var task = loadSub({
    name: 'engine',
    success: go,
    fail: function () { screen.setError('LOAD FAILED — RETRY'); },
  });
  if (task && typeof task.onProgress === 'function') {
    task.onProgress(function (res) {
      screen.setProgress(((res && res.progress) || 0) / 100);
    });
  }
}

module.exports = { launch: launch };
