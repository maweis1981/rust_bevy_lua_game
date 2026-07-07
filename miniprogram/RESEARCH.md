# RESEARCH — WeChat (微信小游戏) & Douyin (抖音小游戏) port of *Time Dodge*

This document records the platform findings that shaped this port, with the
official sources they came from. The headline constraints:

1. **The 25 MB Bevy/wgpu/winit wasm build is NOT viable** in either mini-game
   runtime — for two independent reasons (size *and* missing DOM). We therefore
   reimplemented the mechanics in **plain JS + Canvas 2D**.
2. **Mini-games cannot open an arbitrary external URL.** The ABSORB mode's
   "open sponsor link" (`game.open_url` in the Lua source) is mapped to a
   **rewarded video ad** (`wx.createRewardedVideoAd` / `tt.createRewardedVideoAd`).

---

## 1. The runtime: JS + Canvas/WebGL, no DOM/BOM

WeChat mini-games run JavaScript (JavaScriptCore on iOS, V8 on Android; NW.js in
DevTools) that exposes the global `wx` API but has **no BOM and no DOM** — there
is no global `window` or `document`, and `document.createElement('canvas')` (or
any DOM element creation) throws.

- Rendering surface comes from **`wx.createCanvas()`** (first call → on-screen
  canvas; later calls → off-screen). You get a 2D or WebGL context off *that*
  object, not off a DOM `<canvas>`.
- Input: **`wx.onTouchStart` / `wx.onTouchMove` / `wx.onTouchEnd`** (and
  `onTouchCancel`), each delivering `e.touches[]` with `clientX/clientY`.
- Persistence: **`wx.getStorageSync` / `wx.setStorageSync`** (synchronous KV).
- A **"weapp-adapter"** is the community pattern of *simulating* `document`/
  `window`/`Image` on top of `wx.*` so DOM-oriented engines (Cocos, Three.js,
  etc.) can run. It is a real, documented concept but **not part of the base
  library and no longer officially maintained** — each engine is expected to
  ship its own adapter. Our port needs **no** adapter because it never touches
  the DOM: it draws directly to the `wx.createCanvas()` 2D context.

Sources (fetched):
- https://developers.weixin.qq.com/minigame/en/dev/tutorial/base/adapter.html — "There are no running environments for BOM and DOM, and there are no global `document` and `window` objects"; DOM canvas creation "will incur an error"; defines "Adapter".
- https://developers.weixin.qq.com/minigame/dev/guide/runtime/adapter.html
- https://developers.weixin.qq.com/minigame/dev/api/render/canvas/wx.createCanvas.html

### Douyin (抖音小游戏) — the `tt.*` twin

ByteDance's Douyin mini-game deliberately mirrors the WeChat surface under the
`tt.*` namespace: `tt.createCanvas`, `tt.onTouchStart/Move/End`,
`tt.getStorageSync/setStorageSync`, `tt.createRewardedVideoAd`. Same runtime
model (JS, no DOM, per-engine adapters), same config filenames (`game.json`,
`project.config.json`). Docs now live at `developer.open-douyin.com`
(`microapp.bytedance.com` 301-redirects there).

Source:
- https://developer.open-douyin.com/docs/resource/zh-CN/mini-game/develop/api/mini-game/bytedance-mini-game
- https://developer.open-douyin.com/docs/resource/zh-CN/mini-game/develop/api/ads/tt-create-rewarded-video-ad

## 2. Required project files

Each platform's project **root** must contain, at minimum:

| File | Purpose |
| --- | --- |
| `game.js` | Entry script (the runtime executes it on launch). |
| `game.json` | Mini-game config: `deviceOrientation`, `showStatusBar`, `networkTimeout`, `subpackages`, `workers`, `navigateToMiniProgramAppIdList`, `permission`, … |
| `project.config.json` | DevTools/project config: `appid`, `projectname`, `compileType:"game"`, `setting` (`es6`, `minified`, `urlCheck`, …). |

The runtime packages **only files under the opened project root**, and
`require()` paths may not escape that root. Because both platforms use the same
two config filenames, they cannot share one root — hence this repo keeps the one
**canonical `shared/`** engine and `prepare.sh` copies it into `wechat/shared/`
and `douyin/shared/` so each root is self-contained (see README).

`game.json` keys per the official config reference:
- https://developers.weixin.qq.com/minigame/en/dev/reference/configuration/app.html

## 3. Package-size limits — why 25 MB wasm is dead on arrival

| Platform | Main package | Total (with subpackages) |
| --- | --- | --- |
| WeChat | **4 MB** | **20 MB** (raised to **30 MB** for games with 内购/virtual payment) |
| Douyin | **4 MB** | **20 MB** (subpackaged; main stays ≤ 4 MB) |

A single 25 MB wasm blob exceeds the **4 MB main-package** limit by ~6× and sits
at/over the 20 MB total ceiling *before any assets or glue*. Subpackaging cannot
save it: the wasm must load to start the game, so it belongs in the main package,
which is hard-capped at 4 MB.

**The JS port DOES subpackage** (see README "Subpackage 分包 architecture"): the
main package is a thin launcher (`boot/` + `adapter.js`, ~32 KB) and the engine
ships in an `engine/` subpackage (~56 KB) fetched via
`wx.loadSubpackage`/`tt.loadSubpackage` with a progress bar. Both are far under
4 MB today; the split is the **collection architecture** (each added game = its
own subpackage loaded on demand), and the correct answer to the 4 MB cap for JS
content — it is only the *wasm* that subpackaging can't rescue, because the
engine itself *is* the wasm.

Source:
- https://developers.weixin.qq.com/community/minigame/doc/00088e009103508f3270aaf9c61001 — "主包/单个独立分包限制仍保持 4M … 整包大小限制从 20M 提升至 30M".

## 4. **Why the Bevy/Rust wasm port is NOT viable** (definitive)

Two independent blockers, either one fatal:

1. **Size.** 25 MB wasm ≫ 4 MB main-package cap (§3), and can't be deferred to a
   subpackage because it's the engine itself.
2. **No DOM → winit/wgpu can't initialize.** Rust's browser wasm stack targets
   `wasm32-unknown-unknown` against a **browser DOM**:
   - **winit**'s web backend creates and drives a real `<canvas>` element and
     attaches listeners via `web-sys`/`document`/`window`. The mini-game runtime
     has *no* `document`/`window` and throws on DOM canvas creation — winit has
     nowhere to create or mount its window/event target.
   - **wgpu**'s WebGL2/WebGPU backend obtains its context from an
     `HtmlCanvasElement` the standard browser way
     (`document.createElement('canvas').getContext(...)`). The mini-game only
     offers a GL context off a `wx.createCanvas()` object — a *different*,
     non-DOM surface wgpu is not written against.
   - **wasm-bindgen / web-sys / js-sys** glue reaches for `window`, `document`,
     `performance`, `requestAnimationFrame`, WebGL globals — browser globals the
     host does not provide.

   Making Bevy run would require a bespoke adapter faking a DOM canvas *and* a
   winit/wgpu backend retargeted to `wx.*`/`tt.*` — i.e. a different windowing/
   rendering path than the stock Rust web stack ships. Out of scope, and still
   blocked by §3 regardless.

**Conclusion:** ship a native-JS reimplementation of the *mechanics* (this port),
not the wasm.

Sources: the adapter/DOM page (§1) and the size announcement (§3).

## 5. **External URL → rewarded video ad** (the key API mapping)

**A mini-game cannot open an arbitrary web URL.** There is no browser-style
navigation and no `location`. The only in-ecosystem options are:

- **`wx.navigateToMiniProgram({ appId })`** — jump to *another mini-program*
  (target appId must be whitelisted in `game.json`'s
  `navigateToMiniProgramAppIdList`). Douyin: `tt.navigateToMiniProgram`.
- **Rewarded video ad** — `wx.createRewardedVideoAd` / `tt.createRewardedVideoAd`.
- `web-view` is a **mini-PROGRAM (小程序) component only** — it does **not**
  exist in mini-GAMES (小游戏), and even in mini-programs it only loads
  developer-owned verified business domains.

The Lua `timedodge.lua` ABSORB "CANCEL THIS HIT?" dialog answered **YES** by
calling `game.open_url("https://google.com")` (a sponsor link) and waiving the
25% chip. Since that URL open is impossible here, we map it to a **rewarded
video ad**:

> **YES** → `platform.rewardAd(cb)` shows a rewarded video. If the user watches
> to completion (`onClose` → `res.isEnded === true`), the sponsor "absorbs" the
> hit and the chip is **waived**. If they bail early (`isEnded === false`) or the
> ad errors, the normal **25% chip** is applied. **NO** → immediate 25% chip.

This is *stricter* than the Lua original (which always waived on YES); it is the
correct, review-safe mini-game behavior (reward gated on ad completion). See the
`rewardAd` wiring in `shared/game.js` (`tap` → dialog) and the adapters.

Rewarded ad API shape (both platforms):
```js
const ad = wx.createRewardedVideoAd({ adUnitId: 'adunit-xxxxxxxx' }); // singleton
ad.load();
ad.show().catch(() => ad.load().then(() => ad.show())); // canonical retry
ad.onClose(res => { if (res && res.isEnded) grantReward(); });
```
Sources (fetched):
- https://developers.weixin.qq.com/minigame/dev/api/navigate/wx.navigateToMiniProgram.html
- https://developers.weixin.qq.com/minigame/dev/api/ad/wx.createRewardedVideoAd.html
- https://developers.weixin.qq.com/minigame/en/dev/guide/open-ability/ad/rewarded-video-ad.html — grant reward only when `res.isEnded` is true.
- https://developer.open-douyin.com/docs/resource/zh-CN/mini-game/develop/api/ads/tt-create-rewarded-video-ad

## 6. Persistence mapping

`game.save(key, value)` / `game.load(key)` in the Lua source → the platform's
synchronous storage: `wx.setStorageSync` / `wx.getStorageSync` (WeChat) and
`tt.setStorageSync` / `tt.getStorageSync` (Douyin). Values are stored as strings
and parsed back with `Number(...)` where numeric (mirroring Lua's `tonumber`).
Keys carried over verbatim: `timedodge_best`, `td_absorb_best`,
`td_lv<i>_stars`, `td_lv<i>_best`.

## 7. Verification notes / what is unverified here

- WeChat facts (§1–§6) are from **direct reads** of `developers.weixin.qq.com`.
- Douyin's `developer.open-douyin.com` pages are JS-rendered SPAs; some were
  corroborated via search snippets + engine-vendor porting guides rather than a
  clean full-text fetch. The `tt.*` mirroring of `wx.*` and the `isEnded`
  rewarded-ad contract are consistent across all sources, but treat the exact
  Douyin size numbers as **well-corroborated, not first-party-full-text-fetched**.
- **We could not run either proprietary DevTools** in this environment. The
  runtime behaviour of `wx.createCanvas`, touch coordinate scaling, and the ad
  lifecycle is implemented to spec but **not verified on-device**. The shared
  engine *is* verified headless (`test/run.js`) and via a stub-canvas boot.
