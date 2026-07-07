# Time Dodge — WeChat + Douyin + TikTok mini-game port

A dependency-free **plain JS + Canvas 2D** port of *Time Dodge* (from the
Rust/Bevy/Lua game `assets/scripts/packs/timedodge.lua`), targeting **WeChat
mini-games (微信小游戏)**, **Douyin mini-games (抖音小游戏)**, and **TikTok Mini
Games (TTMinis, HTML runtime)** from ONE shared codebase. See `RESEARCH.md` for
the platform findings (esp. why the 25 MB Bevy wasm can't ship, why the sponsor
URL becomes a rewarded video ad, and how TikTok's HTML/webview runtime differs
from WeChat/Douyin's no-DOM one).

## The game

Time flows **only while you hold the screen**; release and the world freezes —
you are the only thing still moving. Relative drag (the orb moves by your
finger's delta × 1.5, so the finger never covers it). Three modes:

- **ENDLESS** — survive; score = "stolen" seconds. New foe kinds wake at 10/20/
  30/45 s (dart · surge · seeker · splitter · drifter).
- **TRIALS** — 10 seeded levels; reach the gates in sequence. Real-time clock
  (freezing is safe but the clock keeps counting); 1–3 stars by finish time;
  next unlocks at 1 star; stars/bests persist.
- **ABSORB** — osmos-style: eat rocks smaller than you (grow by area), bigger
  rocks chip 25%, below min mass you fade. The **first** big hit per run opens a
  *"CANCEL THIS HIT?"* dialog: **YES** plays a rewarded video ad (waives the chip
  if watched to the end), **NO** takes the chip.

## Layout

```
miniprogram/
  shared/            ← canonical ENGINE (ships INSIDE the subpackage)
    config.js          tunables (ported 1:1 from timedodge.lua)
    rng.js             seeded LCG (BigInt-exact) for TRIALS
    game.js            state machine + all three modes + mechanics
    render.js          Canvas 2D drawing (starfield, HUD, rocks, player, dialog)
    main.js            frame loop; wires an injected `platform` to game+renderer
  boot/              ← canonical MAIN-PACKAGE launcher (platform-free; wx/tt)
    loading.js         deep-space loading screen + progress bar
    launch.js          shows loading, loadSubpackage('engine'), then boots
  wechat/            ← thin WeChat wrapper (no-DOM, wx.*)
    game.js  game.json  project.config.json  adapter.js (binds wx.*)
    boot/  (generated)         ← copy of ../boot   (main package)
    engine/index.js            ← subpackage entry (checked in)
    engine/shared/ (generated) ← copy of ../shared (subpackage)
  douyin/            ← thin Douyin wrapper (no-DOM, tt.*), same engine/ + boot/
  tiktok/            ← thin TikTok wrapper (HTML runtime = real DOM/webview)
    index.html                 ← loads minis.js, inits TTMinis, starts engine
    adapter.js                 ← DOM adapter + TTMinis rewarded ad (checked in)
    engine.bundle.js (generated) ← ../shared bundled with a browser require()
  test/run.js        ← Node invariant harness (no deps)
  prepare.sh         ← assembles wechat/douyin roots + the tiktok/ bundle
  RESEARCH.md  README.md  SHIPPING.md
```

## TikTok (TTMinis) build — HTML runtime, not the no-DOM one

TikTok Mini Games' **HTML runtime is a real webview** (DOM, `<canvas>`,
`window`, `localStorage`, DOM touch events) — the opposite of WeChat/Douyin
mini-games, which have **no DOM** and hand you a canvas only via
`wx/tt.createCanvas`. So the TikTok build is the simplest of the three: the SAME
`shared/` engine runs in a normal HTML page with a normal `<canvas>`.

- `tiktok/index.html` loads the SDK (`https://developers.tiktok.com/js/minis.js`),
  calls `TTMinis.game.init({ clientKey })`, reports `TTMinis.game.setLoadingProgress`,
  then `startGame(platform)`.
- `tiktok/adapter.js` is plain web APIs (canvas, DOM touch/mouse, `localStorage`)
  with the rewarded ad routed through `TTMinis.game.createRewardedVideoAd`.
- The browser has no CommonJS `require()`, so `prepare.sh` bundles the canonical
  `shared/*.js` (**used verbatim, only wrapped**) into `tiktok/engine.bundle.js`
  with a tiny inline require() registry. No subpackage — HTML runtime loads the
  page up front.

Because it's just HTML5, you can preview it in any browser
(`python3 -m http.server` in `tiktok/`) — the SDK calls no-op gracefully outside
TikTok. Verified this way headless (Chromium) and by the bundle boot test `[9]`.

## Subpackage (分包) architecture

WeChat/Douyin mini-**games** hard-cap the **main package at 4 MB** (total 20 MB
via subpackages — RESEARCH §3). This port uses the platform **subpackage** system
so the main package stays tiny and, more importantly, so it scales as a
**collection shell**: each future game becomes its own subpackage loaded on
demand and the launcher never grows.

- **Main package** (`game.js` + `adapter.js` + `boot/`, ~32 KB): builds the
  platform adapter and runs `boot/launch.js`, which draws the loading screen and
  calls `wx.loadSubpackage`/`tt.loadSubpackage({ name: 'engine' })`, piping the
  task's `onProgress` (`{ progress: 0..100 }`) into the bar.
- **Subpackage `engine/`** (declared in `game.json` `"subpackages"`, ~56 KB):
  `engine/index.js` + the copied `shared/` engine. `require`d only inside
  `loadSubpackage`'s `success` — i.e. after the download completes.
- **Fallback**: if the runtime exposes no `loadSubpackage` (a plain preview, or a
  base that inlines everything), the launcher boots the engine directly — the
  `engine/` files exist under the root either way.

Both sizes are trivially under the 4 MB main-package cap today; the split is the
**architecture** for the collection, verified end-to-end headless by test `[8]`.

### How one codebase targets both platforms

`shared/main.js` takes an injected **`platform`** object and never references
`wx` or `tt` directly. Each wrapper's `adapter.js` builds that object from its
namespace:

```js
const plat = (typeof wx !== 'undefined') ? wx
           : (typeof tt !== 'undefined') ? tt : null;
```

`platform` provides: `canvas`, `onTouchStart/Move/End`, `storage.get/set`,
`rewardAd(cb)`, `raf`, `now`, and optional juice (`haptic`, …). Swapping
`wx.*` ↔ `tt.*` is the *only* difference between the two builds.

## Run the tests

```
node miniprogram/test/run.js
```

Drives the shared state machine headless (stub canvas + platform) and asserts
the same invariants as the Lua suite: hold=flow/release=freeze, absorb-eat grows
mass, the big-hit dialog opens exactly once per run, NO chips ×0.75, below-min
fades, trial clear awards stars & unlocks the next level, and a dt hitch never
teleports the orb. Exits non-zero on any failure.

## Open in DevTools / preview

Because DevTools packages only files under the opened root and `require()` can't
escape it, run the copy step first:

```
cd miniprogram && ./prepare.sh
```

Then:

- **WeChat**: WeChat DevTools (微信开发者工具) → *Import project* → select
  `miniprogram/wechat` → project type **小游戏 (Mini Game)**. Set your own
  `appid` in `wechat/project.config.json` (or use a test appid).
- **Douyin**: Douyin DevTools (抖音开发者工具) → *Import project* → select
  `miniprogram/douyin` → project type **小游戏**. Set your `appid` in
  `douyin/project.config.json`.

Re-run `./prepare.sh` after any edit to `shared/`.

## What remains before a real store submission

> **See [`SHIPPING.md`](SHIPPING.md) for the full step-by-step 上架 checklist**
> (account/版号 prerequisites, DevTools import, ad-unit setup, on-device
> verification, store assets, and submission). The summary:

- **appid** — replace the placeholder `appid` in each `project.config.json` with
  a registered mini-game appid (WeChat: mp.weixin.qq.com; Douyin: open-douyin).
- **Ad unit id** — replace the `adUnitId` placeholders in `wechat/adapter.js`
  and `douyin/adapter.js` with real rewarded-video ad units from each platform's
  流量主/变现 console (marked `TODO(ship)`). Rewarded ads require the account to
  be eligible for monetization.
- **Icons / cover art / store metadata** — each platform needs an app icon,
  cover images, category, description, and (China) ICP/实名 compliance info.
- **On-device verification** — this port was verified headless + via a stub
  canvas only; it has **not** been run in the proprietary DevTools or on a
  handset. Confirm touch-coordinate scaling, canvas sizing on notched devices,
  ProMotion/frame pacing, the ad lifecycle, and storage limits on real hardware.
- **Review** — submit for platform review (content + monetization compliance).
