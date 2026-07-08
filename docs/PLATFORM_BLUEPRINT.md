# Rapid Game-Dev Platform — Architecture Blueprint & Roadmap

*Synthesis of a 5-track architecture review (engine/rapid-dev, Android build, ad-director,
analytics, Floniks pipeline). Targets: **iOS + Android (native Bevy) + TikTok Mini Games**.
Singapore studio, overseas/English only, hypercasual/arcade. This is the document we execute from.*

---

## 1. The one-paragraph thesis

The Rust `game.*` bridge is already a **retained-mode scene protocol** (return an id, push a
`LuaCommand`, mutate-by-id), not an engine coupling — which makes it re-hostable. So the platform
is: **author every game once in Lua over that bridge**, run it on three runtimes (mlua on
iOS/Android, ottavino on web, **fengari on TikTok** with the JS renderer as the presentation
backend), and layer four cross-cutting services the bridge owns centrally — a **KIT** (inherited
juice+meta), an **Ad Director** (Lua declares moments, Rust decides), a **Telemetry queue**
(one event schema, many sinks), and a **Floniks content pipeline** (art/audio/icon/ads from a
prompt). One Lua source, one policy layer, one analytics schema, three stores.

---

## 2. Layered architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│  GAME LAYER  — authored ONCE, byte-for-byte identical everywhere      │
│  assets/scripts/packs/*.lua   (games: closures {enter,update,tap,leave})│
│  assets/scripts/kit/*.lua     (KIT: juice · ui · scene · meta · rng · tween) │
│  assets/scripts/telemetry.lua (track helpers)                          │
└───────────────▲───────────────────────────────────────────────────────┘
                │  the `game.*` bridge  (command queue + snapshot reads)
┌───────────────┴───────────────────────────────────────────────────────┐
│  CROSS-CUTTING SERVICES  (live in the bridge — one impl, all games)     │
│   • Ad Director   game.ad_moment/ad_reward/ad_ready → policy → adapter   │
│   • Telemetry     game.track(name,props) → envelope → batch queue → sinks│
│   • Remote config (ad caps, A/B) fetched at boot, cached to save-KV      │
│   • Save/KV · Juice(shake/zoom/emit) · Audio · Haptics                   │
└───────┬───────────────────┬───────────────────────┬───────────────────┘
        │ mlua (C Lua 5.4)   │ ottavino (Rust 5.4)    │ fengari (JS 5.3, HYBRID)
┌───────┴──────┐   ┌─────────┴────────┐    ┌──────────┴─────────────────┐
│ iOS  (Xcode) │   │ Web preview      │    │ TikTok Mini Game            │
│ Android      │   │ (marketing/QA)   │    │ Lua logic in fengari,       │
│ (cargo-ndk + │   │                  │    │ pixels in JS render.js/     │
│  Gradle,     │   │                  │    │ particles.js/sound.js       │
│  GameActivity)│  │                  │    │                             │
└──────┬───────┘   └──────────────────┘    └──────────┬──────────────────┘
       │ native SDK shims (C/JNI, cfg-gated like hl_haptic)               │ JS adapters
   ┌───┴─────────────────────────────┐              ┌───────────────────┴──┐
   │ Ads: AppLovin MAX (primary)      │              │ Ads: TTMinis rewarded │
   │      + AdMob/Pangle/Meta/Unity   │              │      + interstitial   │
   │ Analytics: GameAnalytics + MMP   │              │ Analytics: TikTok     │
   │ (Adjust/AppsFlyer for UA/ROAS)   │              │   events + GA REST    │
   └──────────────────────────────────┘              └───────────────────────┘

  CONTENT PIPELINE (offline, feeds the repo):  Floniks MCP →
     icons/textures/backgrounds → assets/textures ; BGM/SFX/voice → assets/audio ;
     UGC video ads + app icon → marketing.  Driven by `make new-game` + a recipe.
```

---

## 3. Locked decisions (conflicts resolved)

| Area | Decision | One-line why |
|---|---|---|
| **TikTok single-source** | **Adopt fengari as a hybrid** (Lua logic + native-JS pixels), **gated on a one-game perf spike** on a low-end Android webview. | ~50 KB gz VM under a 4 MB cap deletes the hand-ported JS logic and the two-codebase drift; only risk is interpreter perf → measure first. |
| **Ad mediation (native)** | **AppLovin MAX** primary; AdMob + **Pangle** + Meta + Unity as bidders inside MAX. | >50% mediation share, full in-auction bidding, and Pangle = TikTok's own demand (synergy since we're on TikTok). |
| **Ad policy location** | **Rust Director** in the bridge, remote-tunable JSON config. | Policy must be central + identical across games/platforms; Lua stays byte-identical. |
| **Analytics primary** | **GameAnalytics** (REST, free, game-native) + **MMP (Adjust/AppsFlyer)** only if running paid UA + TikTok event sink. | GA gives HC KPIs/benchmarks with no vendor SDK (fits a Rust/wasm engine); attribution is a separate layer. |
| **Android toolchain** | **cargo-ndk + Gradle**, GameActivity backend, `cdylib`, NDK r27+ (16 KB pages). | cargo-apk is deprecated + NativeActivity-only; cargo-ndk hands the NDK env to `cc-rs` so vendored C-Lua cross-compiles cleanly. |
| **KIT layer** | Pure Lua modules in `assets/scripts/kit/`, loaded as EXTRA_SCRIPTS. | No Rust recompile; ships to all runtimes identically; one place tunes feel for every game. |
| **Determinism** | Daily/seeded runs use `KIT.rng.lcg`, never raw `math.random`. | fengari (5.3) and mlua (5.4) have different RNG algorithms → sequences would diverge. |
| **5.3/5.4 safety** | CI lint parses every `.lua` under `lua5.3 -p`. | Catches a 5.4-ism before it ships broken only on TikTok. |

---

## 4. Phased roadmap — all four pillars advance together

### Phase 0 — Foundation (parallel tracks, unblocks everything)

| Track | Workstream | Effort | Unblocks |
|---|---|---|---|
| **Engine** | KIT layer (`kit/juice·ui·scene·meta·rng·tween.lua`) + refactor 1 existing game onto it | M | every game inherits shell; scaffolding |
| **Engine** | `make new-game` scaffold (`tools/new_game.sh` + templates + test stub) | S | "new game in an afternoon" |
| **Engine** | **fengari SPIKE** — run `timedodge.lua` unmodified on TikTok via fengari, profile low-end Android → **go/no-go** | M | the entire single-source decision |
| **Ads** | Lua API (`game.ad_moment/ad_reward/ad_ready`) + Rust Director + remote-config schema + **Null backend** (desktop) | M | real ad SDKs; all ad instrumentation |
| **Analytics** | Widen `game.track` → `(name, props)`; envelope + `SessionTracker` + batch/offline queue; **LocalFile + GameAnalytics REST** sinks; `telemetry.lua` helpers | M | every KPI; ad/retention dashboards |
| **Build** | Android pipeline: cargo-ndk + Gradle + GameActivity + `#[bevy_main]` + `make android-run` boots on device; **fix `file_watcher` cfg** | M | Android as a target at all |

Phase 0 is mostly independent tracks → can run in parallel. The **fengari spike is the pivotal gate**: it decides whether TikTok becomes single-source (Phase 1) or stays hand-ported.

### Phase 1 — Make it real per platform

- **Ads:** AppLovin MAX native shims (iOS Obj-C / Android JNI, cfg-gated like `hl_haptic`); TTMinis rewarded+interstitial JS backend; remote-config fetch; policy tuning (grace/caps).
- **Analytics:** GameAnalytics live (HMAC/gzip REST); consent/ATT gate + anon `user_id`; retention/ad-ARPDAU/tutorial+level funnels; TikTok event sink; MMP native SDK shim **iff** paid UA.
- **TikTok:** if spike passed → migrate to fengari single-source: generic z-sorted `render.js` over the scene map, `bridge.js` shim, delete `miniprogram/shared/game.js` logic; `open_url`→rewarded via `KIT.sponsor`; `save`→localStorage with the shared `s:/n:/b:` codec.
- **Floniks pipeline:** `make new-game` emits placeholder art/BGM/icon; the repeatable ad-creative recipe (presenter→talking clip→gameplay capture→ffmpeg composite) parameterized per game.
- **Build:** signed AAB, Play internal-testing track; iOS TestFlight.

### Phase 2 — Scale & optimize

- Meta depth (daily challenge, cosmetic skins, progression ladder) via `KIT.meta`.
- A/B on remote ad config (grace/caps) read back through GA.
- Backfill the catalogue through the scaffold; each new game ships to all 3 targets for free.
- LiveOps: remote-config-driven events; per-game ad/econ tuning without a store update.

---

## 5. First concrete tasks (start each track now)

- **KIT:** create `assets/scripts/kit/juice.lua` (semantic verbs `hit/soft/pickup/success/fail/wall/near`) + register in `EXTRA_SCRIPTS` (`src/script.rs`); refactor `assets/scripts/packs/timedodge.lua` juice calls onto it.
- **Scaffold:** `tools/new_game.sh` + `tools/templates/pack.lua.tmpl` + `make new-game` target.
- **fengari spike:** new `miniprogram/tiktok-lua/` — vendor `fengari-web`, `bridge.js` (scene map + input snapshot), generic `render.js`, load `timedodge.lua`; measure fps on a real low-end Android.
- **Ads:** add `LuaCommand::AdMoment` + `AdReward{kind,token}` + an `AdEventQueue` + `apply_ad_events` system to `src/script.rs`; `game.ad_moment/ad_reward/ad_ready` in both `register_api` closures; `NullAdBackend`; the remote-config JSON struct.
- **Analytics:** widen `LuaCommand::Track` to `{event, props:Vec<(String,TrackVal)>}`; new `src/telemetry.rs` (envelope + queue + spill file + `AnalyticsSink` trait + `LocalFileSink` + `GameAnalyticsSink`); `assets/scripts/telemetry.lua`; migrate the 15 existing `game.track` call sites.
- **Android:** add the `android/` dir (build_rust.sh, gradle, MainActivity.kt, manifest), `crate-type += cdylib`, Android `bevy` feature, **tighten the `file_watcher` cfg to exclude `target_os="android"`**, `#[cfg(target_os="android")] #[bevy_main]` in `src/lib.rs`, `make android-*` block.

---

## 6. Biggest risks

1. **fengari perf on low-end Android** — the whole single-source thesis rides on the spike. Mitigation: measure `timedodge.lua` on a real cheap device *before* migrating; fall back to hybrid (fengari for logic-light games, hand-port only iteration-heavy ones) if it fails.
2. **Native ad/MMP SDK shims** are the heaviest engineering (Obj-C/JNI over MAX + optional MMP) and gate real revenue on iOS/Android. Sequence them after the Null-backend API is proven.
3. **Lua 5.3↔5.4 drift** (RNG, byte-strings, `<close>`) breaking only on TikTok — mitigated by the CI `lua5.3 -p` lint + `KIT.rng` determinism rule.
4. **Android 16 KB page size / NDK pinning** — Play-blocking if wrong; solved by NDK r27+ and the link-arg belt-and-suspenders.
5. **Store compliance** (ATT/consent, privacy policy, TikTok publisher qualification) — schedule the paperwork in parallel; it's lead-time, not code.

---

## 7. Definition of "Platform v1 done"

- One Lua game (Time Dodge) runs on **iOS + Android + TikTok** from a **single Lua source** (fengari on TikTok) — or, if the spike failed, iOS+Android single-source with TikTok hand-port isolated behind the same bridge shim.
- `make new-game NAME=x` produces a playable, menu-registered stub with juice + settings + pause + records **inherited**, running on all targets.
- `game.ad_moment/ad_reward` live with the Director + one real network (MAX on native, TTMinis on TikTok); no ad in the first session; reward callback exactly-once.
- `game.track` flows a versioned event schema to GameAnalytics; D1/D7 retention, session length, ad-ARPDAU, and the level+tutorial funnels render.
- Floniks `make new-game` fills placeholder icon/art/BGM, and the per-game UGC-ad recipe runs on demand.

---

*Full specialist designs (engine, Android, ads, analytics) are archived in the session transcript;
the Floniks-pipeline pillar is captured in §2 + §4/§5 above (that track's agent returned an
unusable result and was rewritten from the icon/UGC-ad/BGM flow already run in this project).*
