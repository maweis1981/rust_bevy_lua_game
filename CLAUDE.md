# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A 2D **mini-game collection**: **Rust + Bevy 0.19** engine, **Lua 5.4** (via `mlua`,
vendored) for game logic, shipping to **macOS** (dev) and **iOS**. The Rust crate is the
single source of truth, compiled as an `rlib` for the desktop binary and as a `staticlib`
linked into an iOS UIKit app.

`assets/scripts/main.lua` is a small **scene router**: a menu lists games and switches
between them; each game is a closure returning `{ enter, update, tap, leave }` that tracks
its own entities (despawned on leave) and exposes a `DEBUG` table for the tests. Games so
far: **Grow the Paddle** (Pong variant), **Breakout** (the Bevy example, ported), and
**Snake**. Add a game by writing a `make_*` closure and adding it to `order`/`scenes`.

**On-screen text is Latin-only.** Bevy's bundled `default_font` (Fira) has no CJK/emoji
glyphs, so all `set_text` / `spawn_text` strings must be ASCII or they render as blank
boxes (and spam `ICU4X ... segmentation model` errors). Keep UI copy in English.

## Commands

```bash
make run          # desktop build + run (cargo run). Lua hot-reloads while running.
make check        # cargo check — fast compile validation
make clippy       # lints (cargo clippy --all-targets)
make fmt          # cargo fmt
make test         # Rust unit tests + the Lua gameplay invariant suite

make ios-lib      # cross-compile the static lib for the simulator only
make ios-project  # regenerate hollowlullaby.xcodeproj from project.yml
make ios-build    # build the iOS app for the simulator (implies ios-project)
make ios-run      # build + install + launch on simulator (SIM="iPhone 16" by default)

make device-build # build + sign the app for a physical device (aarch64-apple-ios)
make device-run   # build + install + launch on the connected device (DEVICE=<udid>)
```

## Tests

`make test` runs two layers:

- **Rust unit tests** (`src/script.rs`, `#[cfg(test)] mod tests`) cover pure helpers
  like `haptic_style` and the `shake_offset` camera-shake math. Run one: `cargo test <name>`.
- **Lua gameplay invariants** (`tools/test_pong.lua`, needs `lua5.4`) mock the Rust `game`
  API (forcing ball colours by overriding `math.random`) and drive `assets/scripts/main.lua`
  headless for thousands of frames. It asserts both the physics "feel" contract — no
  paddle/ball teleport, no tunneling (vs the paddle's *current* height), total ball speed
  capped, ball on-screen, and nothing leaping on a big-`dt` hitch — and the size mechanic:
  green hits grow the paddle (+ success haptic), red hits / missed-green shrink it, full
  screen = win, floor = lose. This suite caught the unbounded-speed and un-clamped-`dt`
  bugs — extend it when you change gameplay in `main.lua`.

## Toolchain (important, non-obvious)

The machine's **global default rustc is an old 1.71.1**, which cannot build Bevy.
`rust-toolchain.toml` pins this project to `stable` (≥ 1.95, Bevy 0.19's MSRV) and
declares the iOS targets, so plain `cargo` commands here automatically use the right
toolchain. Don't `rustup default` anything — the pin handles it. Do not downgrade
the Bevy/mlua versions to suit an older compiler.

## Architecture

Three files carry the design; read them together before changing the Rust↔Lua boundary:

- `src/lib.rs` — `run()` builds the `App` (DefaultPlugins + `ScriptPlugin`), spawns the
  camera and the `Player` sprite. Also defines the iOS `main_rs` C entrypoint
  (`#[cfg(target_os = "ios")]`). Both desktop and iOS funnel through `run()`.
- `src/main.rs` — desktop binary; just calls `hollowlullaby::run()`.
- `src/script.rs` — the entire Lua integration (`ScriptPlugin`).

### The Rust ↔ Lua boundary (the key invariant)

**Lua never touches the Bevy `World` directly.** Doing so would require holding a
`&mut World` across an FFI call (borrow-checker hostile) and would force the VM to be
`Send + Sync`. Instead:

1. The VM (`LuaVm`) is a **`NonSend` resource** — `mlua::Lua` is single-threaded, so
   its systems run on the main thread via `NonSendMut<LuaVm>`.
2. Host functions exposed to Lua (the global `game` table) only **push `LuaCommand`s**
   onto a `CommandQueue` stored in `mlua` app-data.
3. Rust systems run the Lua callbacks, then **drain the queue and apply** each command
   to the ECS.

Frame flow (`Update`, chained in this order):
`reload_changed_scripts` (re-exec the chunk + call `on_start` when the asset loads or
changes) → `run_lua` (call `on_update(dt)`, then drain & apply commands).

### Adding to the Lua API — do all three steps

To expose a new capability to scripts:
1. Add a variant to `enum LuaCommand` in `src/script.rs`.
2. Register a function on the `game` table in `register_api` that pushes that variant
   (use `lua.app_data_mut::<CommandQueue>()` inside the closure).
3. Handle the variant in `run_lua`'s match (this is where you have `Commands` and ECS
   queries to actually mutate the world).

The **write path** (Lua → ECS) follows the three steps above. A **read path** also
exists for input: `tick_lua` snapshots the pointer (mouse/touch in world coords) and
held keys into the `Bridge` app-data each frame *before* calling `on_update`, and the
`game.pointer()` / `game.key(name)` functions just read that snapshot. Add more reads
(e.g. entity positions) the same way — stash a snapshot in app-data (or the Lua
registry) before `on_update`, never hand Lua a `&World`.

### Presentation: audio, haptics, screen shake

The bridge also exposes juice primitives that scripts drive:

- **Audio.** `game.play_sound(name)` / `game.play_music(name)` map `name` to
  `assets/audio/<name>.wav` and spawn a Bevy `AudioPlayer` (`DESPAWN` for one-shots,
  `LOOP` for music; `MusicTrack` tracks the current loop so a new one replaces it). WAV
  decoding is **not** in Bevy's defaults — the `wav` feature is enabled in `Cargo.toml`.
  The clips are synthesized (no external assets) by `tools/gen_audio.py`; re-run it to
  regenerate them.
- **Haptics.** `game.haptic("light"/"medium"/"heavy"/"success")` calls the C shim
  `hl_haptic` in `ios/Sources/haptics.m` (UIKit feedback generators). It's `#[cfg(target_os
  = "ios")]`-gated in Rust and a no-op on desktop, so desktop builds don't link it.
- **Screen shake.** `game.shake(0..1)` adds "trauma" to the `ScreenShake` resource; the
  `camera_shake` system offsets the tagged `GameCamera` by a trauma² · sine jitter and
  bleeds trauma back to zero, so effects decay smoothly (no manual per-frame camera math
  in Lua).
- **Recolor / resize.** `game.set_color(id, r,g,b,a)` mutates a sprite's color (ball-trail
  fade, paddle flash, green/red ball telegraph) and `game.set_size(id, w, h)` its
  `custom_size` (the player paddle grows/shrinks); `game.spawn` takes an optional 8th alpha
  arg.

### Lua scripts as Bevy assets

Scripts are loaded through a custom `LuaScript` asset + `AssetLoader` (not `include_str!`
or raw `fs`). This is deliberate: it gives **hot-reload on desktop** (the `file_watcher`
Bevy feature is enabled only for non-iOS in `Cargo.toml`) and **bundle loading on iOS**
for free, since Bevy's iOS asset reader resolves `assets/` inside the app bundle. The
entry script path is `MAIN_SCRIPT_PATH` (`scripts/main.lua`).

## iOS build pipeline

`make ios-run` chains: cross-compile static lib → generate Xcode project → xcodebuild →
install/launch on simulator.

- `project.yml` (XcodeGen) is the source of truth for the Xcode project, which is
  git-ignored and regenerated. It declares a **pre-build script** that runs
  `ios/build_rust.sh`, links `-lhollowlullaby` from `build/ios`, and lists the system
  frameworks wgpu/winit/audio need (Metal, UIKit, AudioToolbox, …).
- `ios/build_rust.sh` picks the Rust target from Xcode's `PLATFORM_NAME`
  (`iphonesimulator` → `aarch64-apple-ios-sim`, `iphoneos` → `aarch64-apple-ios`) and
  copies the `.a` to `build/ios/`. It re-exports `PATH` to reach `~/.cargo/bin` because
  Xcode sanitizes `PATH`.
- `ios/Sources/main.m` is the C `main` that calls the Rust `main_rs`; winit takes over
  the UIKit event loop from there.
- `assets/` is added as a **folder reference** (not a group) so its subdirectory
  structure is preserved in the bundle — required for Bevy to find `scripts/main.lua`.

### Physical device

`project.yml` is configured for automatic signing: `DEVELOPMENT_TEAM: N37MF9W73E`
(the only locally-valid Apple Development identity, "wei ma (5R5933K932)"),
`CODE_SIGN_STYLE: Automatic`, bundle id `com.ngmob.hollowlullaby`. `make device-run`
builds for `aarch64-apple-ios`, signs (Xcode auto-creates the provisioning profile via
`-allowProvisioningUpdates`), installs and launches via `devicectl`.

Gotchas: the device must be **connected and unlocked** to launch (a locked device fails
with `FBSOpenApplicationErrorDomain error 7`); a never-trusted developer cert needs a
one-time trust in Settings → General → VPN & Device Management. The test device runs iOS
27.0 while Xcode 26.5's SDK is 26.5 — plain install/launch via `devicectl` works, but
on-device debugging may not until Xcode matches the OS. Default `DEVICE` udid is in the
Makefile; override with `make device-run DEVICE=<udid>` (list via `xcrun devicectl list devices`).

**Ship Release on device.** Debug runs Bevy/wgpu with debug assertions and the game crate
at `opt-level = 1` — noticeably laggy on device even for a trivial scene. Use
`make device-run CONFIG=Release` (Makefile is parametrized by `CONFIG`, default Debug). An
FPS overlay (top-right, `src/lib.rs`, `FrameTimeDiagnosticsPlugin`) helps confirm; device
console logs are not CLI-readable here, so read FPS off the on-screen overlay.

### Info.plist / ProMotion

The Info.plist is generated by XcodeGen via `info.properties` in `project.yml` (not
`GENERATE_INFOPLIST_FILE`), because arbitrary keys are needed:
`CADisableMinimumFrameDurationOnPhone: true` unlocks ProMotion (up to 120 Hz; iOS
otherwise caps rendering at 60), and `UILaunchScreen: {}` gives a full-resolution surface.
The generated `ios/Info.plist` is derived — rerun `xcodegen generate` after edits.

## Conventions

- New rendering/gameplay belongs in Rust systems; new *behavior/tuning* belongs in Lua.
  If you find yourself recompiling Rust to tweak gameplay numbers, move that into Lua.
- Sprites use `Sprite::from_color(...)` (no texture assets required for the demo).
- Keep Lua errors non-fatal: the bridge logs `on_update` errors and continues rather
  than panicking the app.
