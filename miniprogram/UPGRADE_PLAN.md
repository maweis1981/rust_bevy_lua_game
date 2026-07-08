# Time Dodge — Release-Readiness Upgrade Plan
*Product/design lead synthesis of five specialist audits. Everything below is buildable in Canvas 2D on the existing `miniprogram/shared/*.js` stack — no wasm, no 3D, no bundled art beyond optional tiny PNG glyphs.*

The core loop (hold=flow / release=freeze, relative drag) and the faceted rock/crystal material are genuinely strong and should not be touched. The gap to "release-ready" is entirely the **shell**: the game does not *teach, celebrate, persist, or present* its own best ideas, and it is missing the **compliance + system-screen contract** the three platforms require. Two things the design specialists under-weighted but that gate the actual shipped market: **China qualification paperwork** and **Chinese localization**. As product lead I'm elevating both.

---

## DO THESE FIRST — the 5 highest-leverage changes

1. **Start China qualification paperwork today (软著 + 小游戏备案/ICP + 实名/防沉迷).** Weeks of external lead time, gates *everything* on WeChat/Douyin, zero code. If this doesn't start now it's the long pole that slips the whole release. (Completeness / RELEASE §A)
2. **10-second interactive "learn-by-doing" onboarding.** The single biggest retention and completeness gap — all five specialists independently flagged it. Relative-drag + freeze-on-release is non-obvious and taught today only by two lines of menu prose. (A+C)
3. **Wire the dead particle system + make the FREEZE a full-screen event.** `emit()` is called on every eat/gate/death but nothing renders — this is the biggest "feels cheap" gap, and the game's namesake mechanic is currently invisible. One fix lands all the existing shake/zoom/sfx juice *and* gives the game its identity. (B)
4. **Pause + Settings (sound/haptics toggle) + safe-area insets, persisted.** Correctness/expectation gaps, not polish: no way to pause or quit a run, no mute, HUD sits under the notch. Reviewers reject on these. (A+C)
5. **Localize the entire UI to 中文 and fix the silent ad-waive fallback.** English-only is a hard gate on the CN-first market; the no-fill ad path currently grants the reward for free, which reviewers treat as fraud. (A+C)

## QUICK WINS (hours each, disproportionate perceived-quality jump)
- **Screen-space vignette + color grade** as the final draw pass in `draw()` — the single biggest cinematic-per-line upgrade. (S, `render.js`)
- **Show stored bests on the menu** (`timedodge_best`, `td_absorb_best`, total stars already persisted, never displayed). (S, `render.js drawSelect`)
- **Real star/lock/back glyphs** replacing `*`, `?`, and bare "BACK" text. (S, `render.js`)
- **Button press feedback** (scale-down + tap SFX) on every button — menus are currently inert. (S, `render.js button` + `sound.js`)
- **NEW BEST! stamp** on the end card (record is already detected in `die()`/`finishTrial()`). (S)
- **Additive blending** (`globalCompositeOperation='lighter'`) on player glow, trail, stars, gate — makes cyan-on-black read as premium for near-zero cost. (S, `render.js`)

---

# P0 — Blocking for release

### Compliance & platform contract (C)
**P0-1. China qualification & runtime compliance.** *What:* obtain 软著 (software copyright cert; ~10–15 days, one cert = one game, name must match), complete 小游戏备案 + ICP (weeks; Douyin filing 40–50 working days), and wire 实名认证 + 防沉迷 (real-name / anti-addiction) — currently not wired at all. *Why:* hard upload gate on WeChat & Douyin; nothing ships without it. *How:* paperwork (start immediately) + adapter wiring in `miniprogram/{wechat,douyin}/adapter.js`. *Effort:* L (mostly lead-time, not code).

**P0-2. Privacy consent + ToS/PP.** *What:* WeChat/Douyin privacy-authorization popup before first `storage`/ad call (`wx.getPrivacySetting`/`requirePrivacyAuthorize`); TikTok ToS + Privacy Policy URLs shown on the loading page. *Why:* legal gate under PIPL; TikTok review requires the URLs. *How:* `{wechat,douyin,tiktok}/adapter.js` + a consent overlay reusing `render.js panel()`. *Effort:* M.

**P0-3. Real ad units + fix silent-waive.** *What:* replace all `TODO(ship)` placeholder ad IDs; when no ad fills, apply the 25% chip and show "no ad available" — do **not** grant the reward. Verify TikTok's `res.isEnded` completion field. *Why:* current `if(!a){cb(true)}` free-grants the reward = fraud signal to reviewers; wrong TikTok field = reward never/always grants. *How:* three adapters + `game.js` hit-dialog resolve path. *Effort:* S (code) once IDs exist.

### Game UI / system screens (A)
**P0-4. Pause + quit + auto-pause on blur.** *What:* pause affordance in `run` mode, overlay with Resume/Restart/Home, and auto-pause on `wx.onHide`/`visibilitychange`. *Why:* a hold-to-move action game with no pause and no mid-run exit (`G.btn.back=null`, `game.js:144`) is a UX/review red flag. *How:* new `S.paused` short-circuit in `updateRun`; hit-rect `G.btn.pause` drawn in `hud()`, routed in `tap()`. *Effort:* M. *Placement rule (resolves specialist conflict):* read-only info stays top; the pause button may be top-right **only if oversized (≥44px)**; all actionable exits (Home/Restart) live in the overlay in the bottom thumb arc — never the top-left corner.

**P0-5. Settings with persisted sound/haptics toggles.** *What:* Sound on/off, Haptics/vibration on/off, links to Privacy/ToS; reachable one tap from menu and from pause. *Why:* baseline expectation + review requirement; `snd/hap` currently fire unconditionally. *How:* gate the single-choke-point `snd()`/`hap()` in `game.js` on flags persisted via existing `save/loadNum`; draw with `render.js panel/button`. *Effort:* S.

**P0-6. Safe-area / notch insets.** *What:* inset the HUD (drawn at raw `y:0..100`) and all top controls by the device safe-area. *Why:* score and controls are occluded by the status bar / Dynamic Island on real portrait handsets. *How:* read platform safe-area insets into `SW/SH` layout in `main.js`; offset HUD in `render.js hud()`. *Effort:* S–M.

### Onboarding & localization (C)
**P0-7. Interactive first-run tutorial.** *What:* a ~10s scripted coach on the first ENDLESS run — one frozen foe, pulsing ghost-touch + "HOLD to let time flow" → "RELEASE — now only YOU move" → "drag to weave" → a guaranteed first dodge that pays off with "STOLEN 3s!". Language-independent (icons/arrows/glow, not paragraphs). *Why:* #1 completeness/retention gap; the counter-intuitive control bounces first-timers. *How:* `td_seen_tut` flag + a `coach` sub-state in `game.js`; ghost-hand + prompts in `render.js`, leaning on the existing freeze tint. *Effort:* M.

**P0-8. Chinese localization.** *What:* extract every literal string from `render.js`/`game.js` into a locale table; author native `zh-CN` (keep the poetic tone, don't machine-translate); select locale from the adapter. Verify Android/WeChat CJK font fallback renders (no tofu). Prefer icons over words to reduce locale surface. *Why:* WeChat/Douyin are Chinese-first; English-only will be rejected or won't retain. *How:* `config.js` strings table + `render.js`/`game.js` call sites; per-platform font QA. *Effort:* M.

### Art completeness (B)
**P0-9. Wire & build the particle system.** *What:* pooled particle system (cap ~200, `{x,y,vx,vy,life,size,color,mode}`) updated in `main.js`, drawn additively in `render.js` before the vignette. Four presets: `spark` (near-miss/gate/small-eat), `absorb` (imploding ring + flash), `shatter` (glass shards on death, reusing `rockShape` triangles), `confetti` (trial clear). *Why:* `emit()` is dead code — every existing shake/zoom currently has nothing to look at; biggest "feels cheap" fix. *How:* new particle module + `main.js` frame loop + `render.js` additive pass. Requires exposing `platform.offscreen()` (`wx/tt.createCanvas`) if bloom is used. *Effort:* M.

**P0-10. Freeze/flow visual language.** *What:* drive `S.ts` (0=frozen…1=flowing) into a whole-screen state — frozen: pale-cyan wash + tightened frost vignette + ice-white rims + frost-ring pulse on the HUD timer, foe trails to zero; flowing: warmer grade + 2–3-sample motion-ghost on each moving rock + faster nebula drift. Add a low-pass "whoomp" on release. *Why:* the game's namesake mechanic has almost no visual identity today (tiny label + faint tint). *How:* keyed off already-smoothed `S.ts` in `render.js` + one SFX in `sound.js`; no new game state. *Effort:* M.

**P0-11. Depth background + final vignette/grade.** *What:* replace flat gradient + 90 static stars with 4 baked depth layers (void gradient → nebula radials → 3-sublayer parallax starfield → vignette/grade), baked once to an offscreen canvas and blitted per frame. *Why:* current bg reads as programmer placeholder; instantly lifts every screen. *How:* rewrite `render.js bg()`; bake to `platform.offscreen()`. Vignette is the quick win above. *Effort:* M.

---

# P1 — Strongly recommended (prototype → premium)

**P1-1. Design-system pass (UI, A/B).** Palette + type scale as tokens in `config.js` (define `C.PAL`; per-mode accent: ENDLESS cyan / TRIALS gold / ABSORB violet — kill the muddy per-call-site RGBs). Tabular-monospace HUD numerals (the timer jitters today), display face for titles with manual letter-spacing. One glass panel/button language across menu, cards, dialog, level-select. Move BACK out of the top-left dead zone. Add `measureText` fit so end-card subtitles (e.g. `STOLEN 12.3s   BEST 456.7s`) don't clip on narrow devices. *Effort:* M.

**P1-2. Menu as a premium hub (UI, A).** Hero crystal with full bloom as the logo lockup, animated "TIME DODGE" title, live starfield + drifting rocks behind the menu, three glass mode-cards with drawn mode glyphs (∞ / concentric gate / circle-eats-circle) and best-score badges. Screen-transition animation (scale 0.9→1 + fade ~180ms) replacing today's hard cuts. *Effort:* M.

**P1-3. Reward-moment polish (UI, C).** End card: count-up tally (~0.6s with a soft tick SFX), staggered `easeOutBack` star pops in `finishTrial` (one `snd('score')` each), gold NEW BEST! burst + heavier haptic. Near-zero-friction one-tap retry. *Effort:* S–M.

**P1-4. HUD frame + ABSORB mass meter (UI, B).** Replace the flat band with bracketed corner-tick container + mode-accent hairline; the "new hunter wakes" announcement slides in as a lower-third banner instead of swapping the subtitle. ABSORB gets a thin arc filling toward `MAX_MASS` (data already in `S.mass`/`S.peak`). *Effort:* S–M.

**P1-5. Thin meta layer (C, retention).** Persistent best + "best today", a daily seeded run (reuse `rng.js` + Trials seeding), and 3–4 cosmetic orb skins (pure palette/facet swaps of `drawPlayer`, bought with "stolen seconds"). Cosmetic-IAP model, never pay-to-win. *Why:* 2025 data — no-meta hypercasual churns to ~0% D30; thin progression holds ~10% D30. *Effort:* M.

**P1-6. Revive + share (C, monetization).** Opt-in "watch ad to continue" once per ENDLESS/ABSORB run (reuse the `rewardAd` + dialog pattern), and a share-for-reward button on the results card via the platform share API. *Resolution:* keep it strictly user-initiated, one rewarded prompt per run — no interstitials. *Effort:* M.

**P1-7. Music + audio state (B/C).** One looping ambient pad that fades a tension layer in as difficulty ramps; distinct UI/tap/reward/game-over cues (procedural in `sound.js`). Route all through the P0-5 sound toggle. Handle WebAudio suspend/resume on `onHide`/`onShow`. *Why:* Osmos/Super Hexagon's premium feel is inseparable from audio. *Effort:* M.

**P1-8. Deeper feel (B).** Hitstop (60–80ms freeze-frame on death and big-absorb), squash-&-stretch on the orb along its velocity, near-miss white-flash + tick. Progressive foe introduction (spawn a new kind alone + slow before normal). *Effort:* S–M.

---

# P2 — Polish

- **Color-blind safety in ABSORB (B/A):** redundant shape cue (ring on edible, outline/skull on deadly) — green/red alone is the top accessibility failure. *S.*
- **Foe cohesion (B):** normalize kind saturation/value, add per-kind additive rim light, enforce "red = danger only," add depth desaturation + contact shadow. *M.*
- **Gate & trail upgrade (B):** portal-style layered rotating rings + inward particle pull; additive tapered light-streak trail. *S–M.*
- **Friends leaderboard (C):** WeChat/Douyin open-data ranking on the results card (platform-API work). *M.*
- **Branded loading screen (B):** logo + crystal + "tap to begin" (also satisfies the audio-unlock gesture). *S.*
- **Adaptive layout QA (A):** clamp `buildSelect`/`buildLevels`/`card` world-unit math across aspect ratios so nothing clips or drifts out of the thumb arc. *S.*
- **Perf guardrails (C):** cache rock gradients, drop the per-frame `bullets.slice().sort()` in `render.js`, bake static layers — sustain 60fps with 40 foes on a mid-tier phone. *S–M.*

---

## Conflicts resolved
- **Pause placement:** top-right *only if* oversized; all destructive/exit actions live in the bottom-reachable overlay, not the top-left corner (fixes the audit's thumb-zone objection while honoring UI/UX's "pause is low-frequency" point).
- **Revive ad:** competitive/UI wanted it broadly; release wanted restraint — ship it **opt-in, once per run, no interstitials**.
- **Bloom:** use the quarter-res offscreen-upscale trick, never `ctx.filter` (unreliable in mini-game runtimes) — requires exposing `platform.offscreen()`.
- **Sequencing:** compliance paperwork (P0-1/2) runs in parallel from day one; code work proceeds independently and does not wait on it.

---

## Definition of "release-ready" — acceptance checklist
A build is release-ready when all of the following pass on a **real mid-tier device** per platform:

**Compliance**
- [ ] 软著 obtained; 小游戏备案 + ICP filed/approved (WeChat/Douyin); 实名/防沉迷 active and enforcing minor limits.
- [ ] Privacy consent popup fires before first storage/ad call (WeChat/Douyin); ToS + PP URLs on the loading page (TikTok).
- [ ] Real ad-unit IDs in all three adapters; no-fill applies the chip (never free-grants); reward gates only on verified completion.

**System screens & UX**
- [ ] Pause works and auto-pauses on background; Home/Restart reachable mid-run.
- [ ] Settings sound + haptics toggles take effect immediately and persist across restart; reachable one tap from menu.
- [ ] First-run tutorial teaches hold/release/drag by doing, shows once, is remembered.
- [ ] No UI occluded by notch/Dynamic Island/home indicator; touch maps 1:1; no clipped or overflowing text.

**Localization**
- [ ] Full 中文 UI on WeChat/Douyin, EN on TikTok; no tofu glyphs; store metadata localized.

**Presentation (the "quality bar")**
- [ ] Particles render on eat/gate/death; the freeze is a full-screen audiovisual event, not a label.
- [ ] Menu shows bests, has a hero title + live background + press feedback; end card counts up and stamps NEW BEST.
- [ ] One consistent palette/type/panel system across every screen; real star/lock/back glyphs; background has depth + vignette.
- [ ] At least one music track routed through the sound toggle.

**Stability**
- [ ] Sustained 60fps with a full 40-foe field (120 on ProMotion); audio suspends/resumes cleanly on background; persistence survives restart; weak-network load shows a retry path.

**Bottom line:** P0-1 (paperwork) and P0-8 (localization) gate the market; P0-4/5/6/7 are the completeness gaps that read as "unfinished"; P0-9/10/11 are the art/juice fixes that make the existing engine finally *land*. Do the five "first" items and the quick wins, and Time Dodge crosses from polished toy to shippable product.