//! Lua scripting layer.
//!
//! Design: Lua never touches the Bevy `World` directly (that would fight the
//! borrow checker and require the VM to be `Send + Sync`). Instead, Lua-callable
//! functions push *intents* onto a command queue stored in the VM's app-data.
//! Rust systems run the Lua callbacks, then drain the queue and apply each
//! command to the ECS. The VM is a `NonSend` resource because `mlua::Lua` is
//! single-threaded.
//!
//! Entities created from Lua get a stable integer id (returned synchronously by
//! `game.spawn`), so scripts can move/despawn them later. Rust keeps the
//! id -> Entity mapping in `EntityRegistry`.
//!
//! Lua-facing API (global table `game`):
//!   game.log(message)
//!   game.bounds() -> half_width, half_height   (world units; origin at center)
//!   game.spawn(x, y, w, h, r, g, b [, a]) -> id (colored sprite; rgba in 0..1,
//!                                               alpha optional, default 1)
//!   game.spawn_sprite(x, y, w, h, name) -> id  (textured sprite from
//!                                               assets/textures/<name>.png;
//!                                               set_color tints it)
//!   game.spawn_sheet(x, y, w, h, name,
//!                    fw, fh, cols, frames) -> id (sprite-sheet sprite: frames
//!                                               are fw×fh px, `cols` per row,
//!                                               `frames` total; shows frame 0)
//!   game.set_frame(id, i)                      (switch a sheet sprite to frame
//!                                               i, clamped to [0, frames-1] —
//!                                               no texture rebind per frame)
//!   game.tilemap(x, y, cols, rows, tw, th,
//!                tileset, tcols, tframes) -> id (grid of tile cells centered
//!                                               at x,y; cells start hidden;
//!                                               move_to/despawn act on the
//!                                               whole map via the root)
//!   game.set_tile(id, tx, ty, index)           (show tileset frame at cell
//!                                               tx,ty; -1 hides the cell;
//!                                               out-of-range coords ignored)
//!   game.rock3d(x, y, z, size) -> id           (REAL-3D rock: shared procedural
//!                                               mesh, own StandardMaterial; the
//!                                               first call bootstraps a 3D
//!                                               camera + lights under the 2D
//!                                               layer — see src/rock3d.rs)
//!   game.move3d(id, x, y, z)                   (set a 3D entity's translation;
//!                                               x,y are the same world units as
//!                                               2D, z<0 is deeper into space)
//!   game.rot3d(id, rx, ry, rz)                 (absolute rotation in radians —
//!                                               Lua drives spin per frame, so
//!                                               a gameplay time-freeze freezes
//!                                               the tumble for free)
//!   game.color3d(id, r, g, b)                  (tint that rock's own material)
//!   game.scale3d(id, s)                        (uniform world size; the rock
//!                                               mesh is unit-diameter, so
//!                                               s == diameter in world units)
//!   game.spawn_rig(x, y, name [, scale]) -> id (cutout skeletal character
//!                                               from assets/rigs/<name>.rig;
//!                                               see src/rig.rs for the format)
//!   game.play_anim(id, clip)                   (play a rig clip; looping is
//!                                               declared in the rig data)
//!   game.set_bone(id, bone, angle, dx, dy)     (manual bone override, wins
//!                                               over the clip; omit angle to
//!                                               clear the override)
//!   game.move_to(id, x, y)
//!   game.set_color(id, r, g, b, a)             (recolor a sprite; enables
//!                                               flashes and fading trails)
//!   game.set_size(id, w, h)                    (resize a sprite; e.g. a paddle
//!                                               that grows/shrinks)
//!   game.set_rotation(id, radians)             (rotate a sprite about z; e.g. a
//!                                               rolling ball, a kick lunge)
//!   game.tween(id, x, y, scale, dur, ease, delay, from_scale)
//!                                              (Rust-driven eased motion: move
//!                                               to x,y and/or scale over dur
//!                                               seconds. ease = "linear"/"out"/
//!                                               "in"/"inout"/"back"; nil x/y =
//!                                               scale-only; from_scale sets the
//!                                               start scale, e.g. 0 for pop-in.
//!                                               A new tween replaces the old.)
//!   game.despawn(id)
//!   game.spawn_text(x, y, size, r, g, b, a, s) -> id (world-space Text2d label,
//!                                               centered at x,y; for menus/titles)
//!   game.set_text(string)                      (updates the on-screen HUD text)
//!   game.emit(preset, x, y [, count])          (CPU particle burst: "spark"/
//!                                               "dust"/"confetti"/"splash";
//!                                               default 16, global cap 512)
//!   game.shake(intensity)                      (0..1 impulse; Rust decays a
//!                                               camera screen-shake from it)
//!   game.cam(x, y [, zoom])                    (camera base pose: follow a
//!                                               hero, zoom 0.25..4 = magnify;
//!                                               shake/punch layer on top)
//!   game.play_sound(name)                      (one-shot SFX: assets/audio/<name>.wav)
//!   game.play_music(name)                      (looping bg music; replaces any
//!                                               currently-playing track)
//!   game.play_voice(name)                      (single dialogue-voice channel;
//!                                               stops any voice still playing)
//!   game.stop_voice()                          (stop the current dialogue voice)
//!   game.stop_music()                          (stop the looping music track)
//!   game.set_volume(channel, v)                ("sfx"/"music"/"voice", 0..1;
//!                                               music/voice adjust live, sfx
//!                                               applies from the next shot)
//!   game.haptic(kind)                          ("light"/"medium"/"heavy"/
//!                                               "success"; iOS only, else no-op)
//!   game.track(event [, value])                (analytics: append to the local
//!                                               ~/.hollowlullaby/analytics.log,
//!                                               console on web; remote sink
//!                                               can replace this later)
//!   game.open_url(url)                         (open an http(s):// URL in the
//!                                               system browser; web opens a new
//!                                               tab (same-tab fallback if the
//!                                               popup is blocked); iOS is a
//!                                               logged no-op for now; any other
//!                                               scheme is logged and ignored)
//!   game.pointer() -> x, y, down               (mouse/touch in world coords;
//!                                               x,y are nil when unavailable,
//!                                               down = button/finger held)
//!   game.key(name) -> bool                     (held keys: "up"/"down"/"left"/
//!                                               "right"/"w"/"a"/"s"/"d"/"space")
//!   game.touches() -> { {x,y,id}, ... }        (ALL active touches in world
//!                                               coords, for multi-touch play;
//!                                               desktop maps a held left click
//!                                               to a single touch, id 0)
//!   game.save(key, value) -> ok                (persist a string/number/boolean
//!                                               across sessions; desktop+iOS
//!                                               write ~/.hollowlullaby/save.txt,
//!                                               web keeps it for the session)
//!   game.load(key) -> value | nil              (read back a saved value with
//!                                               its original type)
//!   game.date_utc() -> year, month, day        (today's UTC civil date, same
//!                                               worldwide — daily-challenge
//!                                               seeds; snapshotted per frame)
//!
//! Reads (pointer/keys) flow the other way: each frame `tick_lua` snapshots
//! input into the `Bridge` app-data before calling `on_update`, so the Lua
//! query functions above just read that snapshot -- no `World` access from Lua.
//!
//! Script lifecycle callbacks (optional globals):
//!   function on_start()
//!   function on_update(dt)        -- dt = seconds since last frame
//!   function on_tap(x, y)         -- world coords of a touch / left click

use std::collections::HashMap;
#[cfg(not(target_arch = "wasm32"))]
use std::path::PathBuf;
#[cfg(target_arch = "wasm32")]
use std::{cell::RefCell, rc::Rc};

use crate::rig::{
    animate_rigs, build_rigs, BonePose, RigAsset, RigAssetLoader, RigRoot, RigState,
};
use crate::rock3d::{rock_mesh, spawn_3d_rig, Rock3dState};
use bevy::asset::{io::Reader, AssetLoader, LoadContext, LoadState};
use bevy::audio::{AudioSinkPlayback, Volume};
use bevy::prelude::*;
use bevy::sprite::Anchor;
// The Lua VM host differs per platform (see Cargo.toml): mlua (C Lua) on
// desktop/iOS, ottavino (pure-Rust Lua) on the web. Both expose an identical
// `LuaVm` surface, so every system below is backend-agnostic.
#[cfg(not(target_arch = "wasm32"))]
use mlua::{Function, Lua};
#[cfg(target_arch = "wasm32")]
use ottavino::{Callback, CallbackReturn, Closure, Executor, Function, Lua, Table, Value};

const MAIN_SCRIPT_PATH: &str = "scripts/main.lua";

pub struct ScriptPlugin;

impl Plugin for ScriptPlugin {
    fn build(&self, app: &mut App) {
        app.init_asset::<LuaScript>()
            .init_asset_loader::<LuaScriptLoader>()
            .init_asset::<RigAsset>()
            .init_asset_loader::<RigAssetLoader>()
            .init_resource::<EntityRegistry>()
            .init_resource::<ScreenShake>()
            .init_resource::<CameraRig>()
            .init_resource::<BackgroundTheme>()
            .init_resource::<CurrentMusic>()
            .init_resource::<AudioVolumes>()
            .init_resource::<TextureCache>()
            .init_resource::<SheetRegistry>()
            .init_resource::<TilemapRegistry>()
            .insert_non_send(LuaVm::new())
            .add_systems(Startup, (setup_scene, load_scripts))
            .add_systems(
                Update,
                (
                    reload_changed_scripts,
                    tick_lua,
                    apply_lua,
                    flush_save,
                    particle_update,
                    tween_update,
                    build_rigs,
                    animate_rigs,
                    camera_shake,
                )
                    .chain(),
            );
    }
}

// ---------------------------------------------------------------------------
// Scene infrastructure: camera + a HUD text element
// ---------------------------------------------------------------------------

/// Holds the HUD text entity so `game.set_text` can update it.
#[derive(Resource)]
struct Hud(Entity);

/// Maps Lua-visible ids to the ECS entities they created.
#[derive(Resource, Default)]
struct EntityRegistry(HashMap<u32, Entity>);

/// The 2D camera, tagged so `camera_shake` can offset it.
#[derive(Component)]
struct GameCamera;

/// Decaying "trauma" that drives the camera screen-shake. `game.shake` adds to
/// it; `camera_shake` bleeds it back to zero each frame.
#[derive(Resource, Default)]
pub(crate) struct ScreenShake {
    pub(crate) trauma: f32,
    /// Camera zoom "punch" 0..1: impacts push it up, `camera_shake` eases it
    /// back to zero; the camera scales by `zoom_scale(zoom)` (punch-IN).
    pub(crate) zoom: f32,
}

/// Camera base pose driven by `game.cam(x, y, zoom)`. The shake/zoom-punch
/// effects layer ON TOP of this rig (they are transient juice; the rig is the
/// scene's intent), so a game can follow its hero and still get impact punch.
/// `zoom` is magnification: 2.0 = twice as close. Clamped by `cam_zoom_clamp`.
#[derive(Resource)]
pub(crate) struct CameraRig {
    pub(crate) x: f32,
    pub(crate) y: f32,
    pub(crate) zoom: f32,
}

impl Default for CameraRig {
    fn default() -> Self {
        Self { x: 0.0, y: 0.0, zoom: 1.0 }
    }
}

/// Per-scene background palette selector, set from Lua via `game.set_bg_theme`.
/// `background.rs` eases the aurora shader toward this target so each mini-game
/// can tint the backdrop to match its mood (e.g. garden greens for Gem Match).
#[derive(Resource, Default)]
pub(crate) struct BackgroundTheme {
    pub(crate) target: f32,
    /// Deep-space darkening (0 = aurora, 1 = void); `game.set_bg_theme`'s 2nd arg.
    pub(crate) space_target: f32,
}

/// Audio is managed as three channels so tracks never pile up on top of each
/// other (see `apply_lua`):
///   • **Music** — one looping track, tagged `MusicSound`. `game.play_music`
///     no-ops if that same track is already playing (`CurrentMusic` remembers
///     the name), otherwise it stops the old track and starts the new one.
///   • **Voice** — one one-shot dialogue clip, tagged `VoiceSound`.
///     `game.play_voice` stops any voice still playing before starting the new
///     line, so witnesses never talk over themselves; `game.stop_voice` clears it.
///   • **SFX** — `game.play_sound` one-shots may overlap (impacts want that), but
///     the *same* sound is de-duplicated within a single frame so a burst of
///     identical hits plays once, not ten times.
/// Stopping a channel means despawning the entities carrying its marker, which is
/// robust against one-shots that already finished on their own (they leave the
/// query, so there is no stale entity to double-despawn).
#[derive(Resource, Default)]
struct CurrentMusic(Option<String>);

/// Per-channel volume (0..1) driven by `game.set_volume`. New one-shots start
/// at their channel volume; the looping music track and a playing voice line
/// are adjusted live through their `AudioSink`s.
#[derive(Resource)]
struct AudioVolumes {
    sfx: f32,
    music: f32,
    voice: f32,
}

impl Default for AudioVolumes {
    fn default() -> Self {
        Self { sfx: 1.0, music: 1.0, voice: 1.0 }
    }
}

/// Marks the single looping music entity.
#[derive(Component)]
struct MusicSound;

/// Marks a one-shot voice/dialogue entity (only one plays at a time).
#[derive(Component)]
struct VoiceSound;

// ---------------------------------------------------------------------------
// CPU particles (the roadmap's "fallback first" tier — the Lua API stays put
// if the implementation is ever swapped for a GPU backend like bevy_hanabi)
// ---------------------------------------------------------------------------

/// Hard cap on simultaneously-alive particles: an emit that would exceed it is
/// truncated, so no script can melt a phone with a confetti loop.
const PARTICLE_CAP: usize = 512;

/// One CPU particle: straight-line motion + gravity + linear alpha fade over
/// its lifetime, despawned when `ttl` runs out.
#[derive(Component)]
struct Particle {
    vel: Vec2,
    gravity: f32,
    ttl: f32,
    life: f32,
    rgb: (f32, f32, f32),
}

/// Tuning for one emit preset. Angles: `up_fan` sprays into the upper
/// half-plane (splash/confetti), otherwise the full circle (spark/dust).
struct PresetParams {
    speed: (f32, f32),
    gravity: f32,
    ttl: f32,
    size: f32,
    colors: &'static [(f32, f32, f32)],
    up_fan: bool,
}

/// Look up an emit preset; unknown names fall back to "spark" so a typo in a
/// script still shows *something* rather than silently nothing.
fn preset_params(name: &str) -> PresetParams {
    match name {
        "dust" => PresetParams {
            speed: (30.0, 90.0),
            gravity: -60.0,
            ttl: 0.7,
            size: 4.0,
            colors: &[(0.62, 0.55, 0.45), (0.72, 0.66, 0.55)],
            up_fan: false,
        },
        "confetti" => PresetParams {
            speed: (120.0, 260.0),
            gravity: -220.0,
            ttl: 1.2,
            size: 6.0,
            colors: &[
                (0.95, 0.35, 0.45),
                (0.35, 0.75, 0.95),
                (0.95, 0.85, 0.35),
                (0.55, 0.9, 0.5),
                (0.8, 0.5, 0.95),
            ],
            up_fan: true,
        },
        "splash" => PresetParams {
            speed: (140.0, 280.0),
            gravity: -500.0,
            ttl: 0.5,
            size: 4.0,
            colors: &[(0.5, 0.75, 0.95), (0.7, 0.88, 1.0)],
            up_fan: true,
        },
        _ => PresetParams {
            // "spark" and any unknown preset
            speed: (180.0, 320.0),
            gravity: -300.0,
            ttl: 0.4,
            size: 5.0,
            colors: &[(1.0, 0.8, 0.3), (1.0, 0.55, 0.2)],
            up_fan: false,
        },
    }
}

/// Deterministic LCG in [0, 1) — no OS entropy, so headless runs and replays
/// are reproducible and wasm needs no getrandom call here.
fn lcg(seed: &mut u64) -> f32 {
    *seed = seed
        .wrapping_mul(6364136223846793005)
        .wrapping_add(1442695040888963407);
    ((*seed >> 40) & 0xFF_FFFF) as f32 / 16_777_216.0
}

/// How many particles an emit may actually spawn under the global cap.
fn emit_count_allowed(alive: usize, requested: u32, cap: usize) -> u32 {
    (cap.saturating_sub(alive)).min(requested as usize) as u32
}

// ---------------------------------------------------------------------------
// Tweens: Rust-driven eased motion for Lua entities (`game.tween`). Scripts
// fire-and-forget; the engine animates every frame, so motion stays smooth
// regardless of the Lua tick. A new tween on the same entity replaces the old.
// ---------------------------------------------------------------------------

/// Easing kinds for [`TweenAnim`] (indices match `ease_from_name`).
#[derive(Clone, Copy, PartialEq)]
enum Ease {
    Linear,
    Out,
    In,
    InOut,
    Back,
}

fn ease_from_name(name: &str) -> Ease {
    match name {
        "linear" => Ease::Linear,
        "in" => Ease::In,
        "inout" => Ease::InOut,
        "back" | "pop" => Ease::Back,
        _ => Ease::Out,
    }
}

fn ease_apply(e: Ease, t: f32) -> f32 {
    let t = t.clamp(0.0, 1.0);
    match e {
        Ease::Linear => t,
        Ease::Out => 1.0 - (1.0 - t).powi(3),
        Ease::In => t.powi(3),
        Ease::InOut => {
            if t < 0.5 {
                4.0 * t * t * t
            } else {
                1.0 - (-2.0 * t + 2.0).powi(3) / 2.0
            }
        }
        // back-out: overshoots the target slightly, then settles (juicy pops)
        Ease::Back => {
            let c1 = 1.70158_f32;
            let c3 = c1 + 1.0;
            1.0 + c3 * (t - 1.0).powi(3) + c1 * (t - 1.0).powi(2)
        }
    }
}

/// An in-flight `game.tween`: eased translation and/or uniform scale.
#[derive(Component)]
struct TweenAnim {
    to_xy: Option<Vec2>,
    to_scale: Option<f32>,
    from_scale: Option<f32>,   // explicit start scale (e.g. 0 for a pop-in)
    from_xy: Option<Vec2>,     // captured on the first ticked frame
    from_scale_cur: f32,
    t: f32,
    dur: f32,
    delay: f32,
    ease: Ease,
    started: bool,
}

/// Advance tweens: wait out the delay, capture the start state, ease to the
/// target, snap + detach on completion.
fn tween_update(
    time: Res<Time>,
    mut commands: Commands,
    mut tweens: Query<(Entity, &mut TweenAnim, &mut Transform)>,
) {
    let dt = time.delta_secs();
    for (entity, mut tw, mut transform) in &mut tweens {
        if tw.delay > 0.0 {
            tw.delay -= dt;
            if tw.delay > 0.0 {
                continue;
            }
        }
        if !tw.started {
            tw.started = true;
            tw.from_xy = Some(transform.translation.truncate());
            tw.from_scale_cur = tw.from_scale.unwrap_or(transform.scale.x);
            if let Some(fs) = tw.from_scale {
                transform.scale = Vec3::splat(fs);
            }
        }
        tw.t += dt;
        let k = ease_apply(tw.ease, if tw.dur > 0.0 { tw.t / tw.dur } else { 1.0 });
        if let (Some(from), Some(to)) = (tw.from_xy, tw.to_xy) {
            let p = from.lerp(to, k);
            transform.translation.x = p.x;
            transform.translation.y = p.y;
        }
        if let Some(to_s) = tw.to_scale {
            let s = tw.from_scale_cur + (to_s - tw.from_scale_cur) * k;
            transform.scale = Vec3::splat(s);
        }
        if tw.t >= tw.dur {
            if let Some(to) = tw.to_xy {
                transform.translation.x = to.x;
                transform.translation.y = to.y;
            }
            if let Some(to_s) = tw.to_scale {
                transform.scale = Vec3::splat(to_s);
            }
            commands.entity(entity).remove::<TweenAnim>();
        }
    }
}

/// Linear fade: full alpha at birth, zero at death.
fn particle_alpha(life_frac: f32) -> f32 {
    life_frac.clamp(0.0, 1.0)
}

/// Advance every particle: integrate velocity + gravity, fade out, despawn on
/// expiry — "life reaches zero, entity is gone" is the roadmap invariant.
fn particle_update(
    time: Res<Time>,
    mut commands: Commands,
    mut particles: Query<(Entity, &mut Particle, &mut Transform, &mut Sprite)>,
) {
    let dt = time.delta_secs();
    for (entity, mut p, mut transform, mut sprite) in &mut particles {
        p.ttl -= dt;
        if p.ttl <= 0.0 {
            commands.entity(entity).despawn();
            continue;
        }
        let dv = p.gravity * dt;
        p.vel.y += dv;
        transform.translation.x += p.vel.x * dt;
        transform.translation.y += p.vel.y * dt;
        let (r, g, b) = p.rgb;
        sprite.color = Color::srgba(r, g, b, particle_alpha(p.ttl / p.life));
    }
}

/// Frame layout of a sprite-sheet entity spawned by `game.spawn_sheet`, keyed
/// by Lua id. Kept in a resource (not a component) so `game.set_frame` works
/// even in the same frame the sheet was spawned (the entity is not in the
/// World yet, but this map is updated synchronously during the drain).
#[derive(Resource, Default)]
struct SheetRegistry(HashMap<u32, SheetInfo>);

#[derive(Clone, Copy)]
struct SheetInfo {
    fw: f32,
    fh: f32,
    cols: u32,
    frames: u32,
}

/// Layout + per-cell entities of a `game.tilemap` grid, keyed by Lua id. Cells
/// are children of a root entity (which is what EntityRegistry maps the id to,
/// so `move_to`/`despawn` act on the whole map; despawn is recursive).
#[derive(Resource, Default)]
struct TilemapRegistry(HashMap<u32, TilemapInfo>);

struct TilemapInfo {
    cols: u32,
    rows: u32,
    /// Tileset frame layout (frames are tile-sized, `tcols` per row).
    tw: f32,
    th: f32,
    tcols: u32,
    tframes: u32,
    /// Row-major cell entities, `cols * rows` of them.
    cells: Vec<Entity>,
}

/// Row-major slot of cell (tx, ty) in a cols×rows grid; None when out of
/// bounds — a stray `set_tile` must be a no-op, never a panic or wraparound.
fn tile_slot(cols: u32, rows: u32, tx: i64, ty: i64) -> Option<usize> {
    if tx < 0 || ty < 0 || tx >= cols as i64 || ty >= rows as i64 {
        return None;
    }
    Some((ty as u32 * cols + tx as u32) as usize)
}

/// Retains a strong handle to every texture ever loaded, keyed by name, so a
/// sprite that swaps its image (frame animation via `set_sprite_image`) never
/// drops the only handle to a frame — which would let Bevy unload it and cause a
/// one-frame blank (flicker) when the animation cycles back to it.
#[derive(Resource, Default)]
struct TextureCache(HashMap<String, Handle<Image>>);

fn setup_scene(mut commands: Commands, assets: Res<AssetServer>) {
    commands.spawn((Camera2d, GameCamera));

    let hud = commands
        .spawn((
            Text::new(""),
            TextFont {
                font: FontSource::Handle(assets.load("fonts/game.ttf")),
                font_size: 28.0.into(),
                ..default()
            },
            TextColor(Color::WHITE),
            Node {
                position_type: PositionType::Absolute,
                top: Val::Px(60.0),
                left: Val::Px(24.0),
                ..default()
            },
        ))
        .id();
    commands.insert_resource(Hud(hud));
}

// ---------------------------------------------------------------------------
// Lua source as a Bevy asset (hot-reload on desktop, bundle-loading on iOS)
// ---------------------------------------------------------------------------

#[derive(Asset, TypePath, Debug)]
pub struct LuaScript {
    pub source: String,
}

#[derive(Default, TypePath)]
struct LuaScriptLoader;

impl AssetLoader for LuaScriptLoader {
    type Asset = LuaScript;
    type Settings = ();
    type Error = std::io::Error;

    async fn load(
        &self,
        reader: &mut dyn Reader,
        _settings: &(),
        _ctx: &mut LoadContext<'_>,
    ) -> Result<LuaScript, std::io::Error> {
        let mut bytes = Vec::new();
        reader.read_to_end(&mut bytes).await?;
        Ok(LuaScript {
            source: String::from_utf8_lossy(&bytes).into_owned(),
        })
    }

    fn extensions(&self) -> &[&str] {
        &["lua"]
    }
}

/// Extra Lua game modules loaded alongside `main.lua`. They run *before* it (so
/// `main.lua`'s `on_start` can see the globals they define, e.g. `make_roguelike`)
/// and are re-run together on any hot-reload.
const EXTRA_SCRIPTS: &[&str] = &[
    "scripts/roguelike.lua",
    "scripts/game2048.lua",
    "scripts/shooter.lua",
    "scripts/world.lua",
    "scripts/craftworld.lua",
    "scripts/match3.lua",
    "scripts/umami.lua",
];

/// Directory (under the asset root) scanned at runtime for drop-in game packs.
/// Any `*.lua` here is loaded dynamically and self-registers into `PACKS` — so a
/// pack is published by dropping a file in, with no recompile and no edit to
/// EXTRA_SCRIPTS. See tools/PACK_SPEC.md.
const PACKS_DIR: &str = "scripts/packs";

/// Enumerate `*.lua` under the asset root's PACKS_DIR. We only use `std::fs` to
/// LIST names; each is then loaded through the normal asset pipeline (so
/// hot-reload still works). Checks the working dir (`assets/…`, desktop) and the
/// executable's bundle (`<app>/assets/…`, iOS). Returns asset-relative paths.
#[cfg(not(target_arch = "wasm32"))]
fn discover_packs() -> Vec<String> {
    let mut roots: Vec<PathBuf> = vec![PathBuf::from("assets")];
    if let Ok(exe) = std::env::current_exe() {
        if let Some(dir) = exe.parent() {
            roots.push(dir.join("assets"));
        }
    }
    let mut found: Vec<String> = Vec::new();
    for root in roots {
        if let Ok(entries) = std::fs::read_dir(root.join(PACKS_DIR)) {
            for entry in entries.flatten() {
                let path = entry.path();
                if path.extension().and_then(|e| e.to_str()) == Some("lua") {
                    if let Some(name) = path.file_name().and_then(|n| n.to_str()) {
                        found.push(format!("{PACKS_DIR}/{name}"));
                    }
                }
            }
            if !found.is_empty() {
                break; // first root that has packs wins
            }
        }
    }
    found.sort();
    found.dedup();
    found
}

/// On the web there is no filesystem to scan — assets are fetched over HTTP — so
/// packs can't be auto-discovered. List them explicitly; each still loads through
/// the normal asset pipeline. Keep in sync with `assets/scripts/packs/`.
#[cfg(target_arch = "wasm32")]
fn discover_packs() -> Vec<String> {
    vec![
        format!("{PACKS_DIR}/catch.lua"),
        format!("{PACKS_DIR}/ponies.lua"),
        format!("{PACKS_DIR}/gallery.lua"),
        format!("{PACKS_DIR}/showcase.lua"),
        format!("{PACKS_DIR}/timedodge.lua"),
        format!("{PACKS_DIR}/forge.lua"),
        format!("{PACKS_DIR}/fireflies.lua"),
        format!("{PACKS_DIR}/ant_clear.lua"),
    ]
}

/// All Lua chunks in execution order: extras first, then `main.lua` last.
/// `dirty` means "(re)run once everything has settled" and persists across
/// frames — so we retry every frame until all scripts load, instead of only
/// reacting to a single asset event (which could be missed on device).
#[derive(Resource)]
struct ScriptHandles {
    list: Vec<(String, Handle<LuaScript>)>,
    dirty: bool,
    initialized: bool,
}

fn load_scripts(mut commands: Commands, assets: Res<AssetServer>) {
    let mut list: Vec<(String, Handle<LuaScript>)> = EXTRA_SCRIPTS
        .iter()
        .map(|p| (p.to_string(), assets.load(*p)))
        .collect();
    // Dynamic drop-in packs, discovered at runtime (before main.lua so their
    // PACKS registration is visible to on_start).
    for path in discover_packs() {
        info!("loading dynamic pack: {path}");
        let handle = assets.load(&path);
        list.push((path, handle));
    }
    list.push((MAIN_SCRIPT_PATH.to_string(), assets.load(MAIN_SCRIPT_PATH)));
    commands.insert_resource(ScriptHandles {
        list,
        dirty: true,
        initialized: false,
    });
}

// ---------------------------------------------------------------------------
// The Lua <-> ECS channel
// ---------------------------------------------------------------------------

enum LuaCommand {
    Spawn {
        id: u32,
        x: f32,
        y: f32,
        w: f32,
        h: f32,
        color: (f32, f32, f32, f32),
    },
    MoveTo {
        id: u32,
        x: f32,
        y: f32,
    },
    SetColor {
        id: u32,
        color: (f32, f32, f32, f32),
    },
    SetSize {
        id: u32,
        w: f32,
        h: f32,
    },
    SetRotation {
        id: u32,
        radians: f32,
    },
    Tween {
        id: u32,
        x: Option<f32>,
        y: Option<f32>,
        scale: Option<f32>,
        dur: f32,
        ease: String,
        delay: f32,
        from_scale: Option<f32>,
    },
    SetLayer {
        id: u32,
        z: f32,
    },
    SpawnPanel {
        id: u32,
        x: f32,
        y: f32,
        w: f32,
        h: f32,
        image: String,
        border: f32,
    },
    SetSpriteImage {
        id: u32,
        image: String,
    },
    SpawnText {
        id: u32,
        x: f32,
        y: f32,
        size: f32,
        color: (f32, f32, f32, f32),
        text: String,
    },
    SpawnSprite {
        id: u32,
        x: f32,
        y: f32,
        w: f32,
        h: f32,
        image: String,
    },
    SpawnSheet {
        id: u32,
        x: f32,
        y: f32,
        w: f32,
        h: f32,
        image: String,
        fw: f32,
        fh: f32,
        cols: u32,
        frames: u32,
    },
    SetFrame {
        id: u32,
        frame: i64,
    },
    Tilemap {
        id: u32,
        x: f32,
        y: f32,
        cols: u32,
        rows: u32,
        tw: f32,
        th: f32,
        image: String,
        tcols: u32,
        tframes: u32,
    },
    SetTile {
        id: u32,
        tx: i64,
        ty: i64,
        index: i64,
    },
    Rock3d {
        id: u32,
        x: f32,
        y: f32,
        z: f32,
        size: f32,
    },
    Move3d {
        id: u32,
        x: f32,
        y: f32,
        z: f32,
    },
    Rot3d {
        id: u32,
        rx: f32,
        ry: f32,
        rz: f32,
    },
    Color3d {
        id: u32,
        color: (f32, f32, f32),
    },
    Scale3d {
        id: u32,
        s: f32,
    },
    /// Request/release the persistent 3D space backdrop (used by timedodge on
    /// every screen, so the animated space shader is visible even with no rocks
    /// alive — menus, cards). Boots the 3D rig on first `true`.
    SpaceMode(bool),
    SpawnRig {
        id: u32,
        x: f32,
        y: f32,
        name: String,
        scale: f32,
    },
    PlayAnim {
        id: u32,
        clip: String,
    },
    SetBone {
        id: u32,
        bone: String,
        pose: Option<(f32, f32, f32)>,
    },
    Despawn {
        id: u32,
    },
    Emit {
        preset: String,
        x: f32,
        y: f32,
        count: u32,
    },
    SetText(String),
    Shake(f32),
    Zoom(f32),
    Cam {
        x: f32,
        y: f32,
        zoom: f32,
    },
    SetBgTheme(f32, f32),
    PlaySound(String),
    PlayMusic(String),
    PlayVoice(String),
    StopVoice,
    StopMusic,
    SetVolume {
        channel: String,
        volume: f32,
    },
    Track {
        event: String,
        value: Option<f64>,
    },
    OpenUrl(String),
    Haptic(i32),
}

/// Shared state stored in `mlua` app-data: the command queue, the id counter,
/// the current screen half-extents (so `game.bounds()` is always fresh), and a
/// per-frame snapshot of input that the `game.pointer`/`game.key` reads serve.
#[derive(Default)]
struct Bridge {
    queue: Vec<LuaCommand>,
    next_id: u32,
    screen: (f32, f32),
    /// Mouse cursor / first active touch in world coords, if any this frame.
    pointer: Option<(f32, f32)>,
    /// Whether the left mouse button or a touch is currently held.
    pointer_down: bool,
    /// Names of the keys held this frame (see `key_snapshot`).
    keys: std::collections::HashSet<&'static str>,
    /// All active touches this frame in world coords (multi-touch read path).
    /// On desktop a held left mouse button appears as a single touch with
    /// id 0 so multi-touch code paths stay exercisable during development.
    touches: Vec<(f32, f32, u64)>,
    /// Persistent KV store backing `game.save`/`game.load`. Values are stored
    /// pre-encoded (`s:`/`n:`/`b:` type prefix) so the file codec and the Lua
    /// boundary share one representation. Loaded from disk once at VM creation;
    /// `store_dirty` asks the flush system to write it back out.
    store: HashMap<String, String>,
    store_dirty: bool,
    /// Today's UTC civil date `(year, month, day)`, snapshotted once per frame
    /// before `on_update` — serves `game.date_utc()` (daily-challenge seeds).
    date_utc: (i32, u32, u32),
}

// ---------------------------------------------------------------------------
// The VM
// ---------------------------------------------------------------------------

#[cfg(not(target_arch = "wasm32"))]
pub struct LuaVm {
    lua: Lua,
    has_update: bool,
    has_tap: bool,
}

#[cfg(not(target_arch = "wasm32"))]
impl LuaVm {
    fn new() -> Self {
        let lua = Lua::new();
        let bridge = Bridge {
            store: load_store_from_disk(),
            ..Bridge::default()
        };
        lua.set_app_data(bridge);
        register_api(&lua).expect("failed to register Lua `game` API");
        Self {
            lua,
            has_update: false,
            has_tap: false,
        }
    }

    /// If `game.save` touched the store this frame, return the encoded file
    /// content to persist and clear the dirty flag.
    fn take_dirty_store(&mut self) -> Option<String> {
        let mut bridge = self.lua.app_data_mut::<Bridge>()?;
        if !bridge.store_dirty {
            return None;
        }
        bridge.store_dirty = false;
        Some(encode_store(&bridge.store))
    }

    /// Execute one Lua chunk (no lifecycle callbacks yet).
    fn exec_chunk(&mut self, source: &str, name: &str) -> mlua::Result<()> {
        self.lua.load(source).set_name(name).exec()
    }

    /// After all chunks are executed, refresh the callback flags and run
    /// `on_start` once.
    fn finish_reload(&mut self) -> mlua::Result<()> {
        let globals = self.lua.globals();
        self.has_update = globals.get::<Option<Function>>("on_update")?.is_some();
        self.has_tap = globals.get::<Option<Function>>("on_tap")?.is_some();
        if let Some(on_start) = globals.get::<Option<Function>>("on_start")? {
            on_start.call::<()>(())?;
        }
        Ok(())
    }

    fn set_screen(&mut self, half_w: f32, half_h: f32) {
        if let Some(mut bridge) = self.lua.app_data_mut::<Bridge>() {
            bridge.screen = (half_w, half_h);
        }
    }

    fn set_date(&mut self, date: (i32, u32, u32)) {
        if let Some(mut bridge) = self.lua.app_data_mut::<Bridge>() {
            bridge.date_utc = date;
        }
    }

    fn set_input(
        &mut self,
        pointer: Option<(f32, f32)>,
        pointer_down: bool,
        keys: std::collections::HashSet<&'static str>,
        touches: Vec<(f32, f32, u64)>,
    ) {
        if let Some(mut bridge) = self.lua.app_data_mut::<Bridge>() {
            bridge.pointer = pointer;
            bridge.pointer_down = pointer_down;
            bridge.keys = keys;
            bridge.touches = touches;
        }
    }

    fn on_tap(&mut self, x: f32, y: f32) {
        if !self.has_tap {
            return;
        }
        let result: mlua::Result<()> = (|| {
            let f: Function = self.lua.globals().get("on_tap")?;
            f.call::<()>((x, y))
        })();
        if let Err(err) = result {
            error!("lua on_tap error: {err}");
        }
    }

    fn update(&mut self, dt: f32) {
        if !self.has_update {
            return;
        }
        let result: mlua::Result<()> = (|| {
            let f: Function = self.lua.globals().get("on_update")?;
            f.call::<()>(dt)
        })();
        if let Err(err) = result {
            error!("lua on_update error: {err}");
        }
    }

    fn drain(&mut self) -> Vec<LuaCommand> {
        match self.lua.app_data_mut::<Bridge>() {
            Some(mut bridge) => std::mem::take(&mut bridge.queue),
            None => Vec::new(),
        }
    }
}

#[cfg(not(target_arch = "wasm32"))]
fn register_api(lua: &Lua) -> mlua::Result<()> {
    let game = lua.create_table()?;

    game.set(
        "log",
        lua.create_function(|_, msg: String| {
            info!("[lua] {msg}");
            Ok(())
        })?,
    )?;

    game.set(
        "bounds",
        lua.create_function(|lua, ()| {
            let (hw, hh) = lua
                .app_data_ref::<Bridge>()
                .map(|b| b.screen)
                .unwrap_or((0.0, 0.0));
            Ok((hw, hh))
        })?,
    )?;

    game.set(
        "pointer",
        lua.create_function(|lua, ()| {
            let snapshot = lua
                .app_data_ref::<Bridge>()
                .map(|b| (b.pointer, b.pointer_down));
            match snapshot {
                Some((Some((x, y)), down)) => Ok((Some(x), Some(y), down)),
                Some((None, down)) => Ok((None, None, down)),
                None => Ok((None, None, false)),
            }
        })?,
    )?;

    game.set(
        "touches",
        lua.create_function(|lua, ()| {
            let touches = lua
                .app_data_ref::<Bridge>()
                .map(|b| b.touches.clone())
                .unwrap_or_default();
            let list = lua.create_table()?;
            for (i, (x, y, id)) in touches.iter().enumerate() {
                let t = lua.create_table()?;
                t.set("x", *x)?;
                t.set("y", *y)?;
                t.set("id", *id)?;
                list.set(i + 1, t)?;
            }
            Ok(list)
        })?,
    )?;

    game.set(
        "key",
        lua.create_function(|lua, name: String| {
            let held = lua
                .app_data_ref::<Bridge>()
                .map(|b| b.keys.contains(name.as_str()))
                .unwrap_or(false);
            Ok(held)
        })?,
    )?;

    game.set(
        "date_utc",
        lua.create_function(|lua, ()| {
            let (y, m, d) = lua
                .app_data_ref::<Bridge>()
                .map(|b| b.date_utc)
                .filter(|&(y, _, _)| y > 0)
                .unwrap_or((1970, 1, 1));
            Ok((y, m, d))
        })?,
    )?;

    game.set(
        "spawn",
        lua.create_function(
            #[allow(clippy::type_complexity)]
            |lua, (x, y, w, h, r, g, b, a): (f32, f32, f32, f32, f32, f32, f32, Option<f32>)| {
                let mut bridge = lua
                    .app_data_mut::<Bridge>()
                    .ok_or_else(|| mlua::Error::runtime("bridge missing"))?;
                bridge.next_id += 1;
                let id = bridge.next_id;
                bridge.queue.push(LuaCommand::Spawn {
                    id,
                    x,
                    y,
                    w,
                    h,
                    color: (r, g, b, a.unwrap_or(1.0)),
                });
                Ok(id)
            },
        )?,
    )?;

    game.set(
        "move_to",
        lua.create_function(|lua, (id, x, y): (u32, f32, f32)| {
            if let Some(mut bridge) = lua.app_data_mut::<Bridge>() {
                bridge.queue.push(LuaCommand::MoveTo { id, x, y });
            }
            Ok(())
        })?,
    )?;

    game.set(
        "set_color",
        lua.create_function(|lua, (id, r, g, b, a): (u32, f32, f32, f32, f32)| {
            if let Some(mut bridge) = lua.app_data_mut::<Bridge>() {
                bridge.queue.push(LuaCommand::SetColor {
                    id,
                    color: (r, g, b, a),
                });
            }
            Ok(())
        })?,
    )?;

    game.set(
        "set_size",
        lua.create_function(|lua, (id, w, h): (u32, f32, f32)| {
            if let Some(mut bridge) = lua.app_data_mut::<Bridge>() {
                bridge.queue.push(LuaCommand::SetSize { id, w, h });
            }
            Ok(())
        })?,
    )?;

    game.set(
        "set_rotation",
        lua.create_function(|lua, (id, radians): (u32, f32)| {
            if let Some(mut bridge) = lua.app_data_mut::<Bridge>() {
                bridge.queue.push(LuaCommand::SetRotation { id, radians });
            }
            Ok(())
        })?,
    )?;

    game.set(
        "tween",
        lua.create_function(
            |lua,
             (id, x, y, scale, dur, ease, delay, from_scale): (
                u32,
                Option<f32>,
                Option<f32>,
                Option<f32>,
                f32,
                Option<String>,
                Option<f32>,
                Option<f32>,
            )| {
                if let Some(mut bridge) = lua.app_data_mut::<Bridge>() {
                    bridge.queue.push(LuaCommand::Tween {
                        id,
                        x,
                        y,
                        scale,
                        dur,
                        ease: ease.unwrap_or_else(|| "out".into()),
                        delay: delay.unwrap_or(0.0),
                        from_scale,
                    });
                }
                Ok(())
            },
        )?,
    )?;

    game.set(
        "set_sprite_image",
        lua.create_function(|lua, (id, image): (u32, String)| {
            if let Some(mut bridge) = lua.app_data_mut::<Bridge>() {
                bridge.queue.push(LuaCommand::SetSpriteImage { id, image });
            }
            Ok(())
        })?,
    )?;

    game.set(
        "spawn_text",
        lua.create_function(
            |lua, (x, y, size, r, g, b, a, text): (f32, f32, f32, f32, f32, f32, f32, String)| {
                let mut bridge = lua
                    .app_data_mut::<Bridge>()
                    .ok_or_else(|| mlua::Error::runtime("bridge missing"))?;
                bridge.next_id += 1;
                let id = bridge.next_id;
                bridge.queue.push(LuaCommand::SpawnText {
                    id,
                    x,
                    y,
                    size,
                    color: (r, g, b, a),
                    text,
                });
                Ok(id)
            },
        )?,
    )?;

    game.set(
        "spawn_sprite",
        lua.create_function(|lua, (x, y, w, h, image): (f32, f32, f32, f32, String)| {
            let mut bridge = lua
                .app_data_mut::<Bridge>()
                .ok_or_else(|| mlua::Error::runtime("bridge missing"))?;
            bridge.next_id += 1;
            let id = bridge.next_id;
            bridge.queue.push(LuaCommand::SpawnSprite {
                id,
                x,
                y,
                w,
                h,
                image,
            });
            Ok(id)
        })?,
    )?;

    game.set(
        "spawn_panel",
        lua.create_function(
            |lua, (x, y, w, h, image, border): (f32, f32, f32, f32, String, f32)| {
                let mut bridge = lua
                    .app_data_mut::<Bridge>()
                    .ok_or_else(|| mlua::Error::runtime("bridge missing"))?;
                bridge.next_id += 1;
                let id = bridge.next_id;
                bridge.queue.push(LuaCommand::SpawnPanel {
                    id,
                    x,
                    y,
                    w,
                    h,
                    image,
                    border,
                });
                Ok(id)
            },
        )?,
    )?;

    game.set(
        "set_layer",
        lua.create_function(|lua, (id, z): (u32, f32)| {
            if let Some(mut bridge) = lua.app_data_mut::<Bridge>() {
                bridge.queue.push(LuaCommand::SetLayer { id, z });
            }
            Ok(())
        })?,
    )?;

    game.set(
        "spawn_sheet",
        lua.create_function(
            #[allow(clippy::type_complexity)]
            |lua,
             (x, y, w, h, image, fw, fh, cols, frames): (
                f32,
                f32,
                f32,
                f32,
                String,
                f32,
                f32,
                u32,
                u32,
            )| {
                let mut bridge = lua
                    .app_data_mut::<Bridge>()
                    .ok_or_else(|| mlua::Error::runtime("bridge missing"))?;
                bridge.next_id += 1;
                let id = bridge.next_id;
                bridge.queue.push(LuaCommand::SpawnSheet {
                    id,
                    x,
                    y,
                    w,
                    h,
                    image,
                    fw,
                    fh,
                    cols,
                    frames,
                });
                Ok(id)
            },
        )?,
    )?;

    game.set(
        "set_frame",
        lua.create_function(|lua, (id, frame): (u32, i64)| {
            if let Some(mut bridge) = lua.app_data_mut::<Bridge>() {
                bridge.queue.push(LuaCommand::SetFrame { id, frame });
            }
            Ok(())
        })?,
    )?;

    game.set(
        "tilemap",
        lua.create_function(
            #[allow(clippy::type_complexity)]
            |lua,
             (x, y, cols, rows, tw, th, image, tcols, tframes): (
                f32,
                f32,
                u32,
                u32,
                f32,
                f32,
                String,
                u32,
                u32,
            )| {
                let mut bridge = lua
                    .app_data_mut::<Bridge>()
                    .ok_or_else(|| mlua::Error::runtime("bridge missing"))?;
                bridge.next_id += 1;
                let id = bridge.next_id;
                bridge.queue.push(LuaCommand::Tilemap {
                    id,
                    x,
                    y,
                    cols,
                    rows,
                    tw,
                    th,
                    image,
                    tcols,
                    tframes,
                });
                Ok(id)
            },
        )?,
    )?;

    game.set(
        "set_tile",
        lua.create_function(|lua, (id, tx, ty, index): (u32, i64, i64, i64)| {
            if let Some(mut bridge) = lua.app_data_mut::<Bridge>() {
                bridge.queue.push(LuaCommand::SetTile { id, tx, ty, index });
            }
            Ok(())
        })?,
    )?;

    game.set(
        "rock3d",
        lua.create_function(|lua, (x, y, z, size): (f32, f32, f32, f32)| {
            let mut bridge = lua
                .app_data_mut::<Bridge>()
                .ok_or_else(|| mlua::Error::runtime("bridge missing"))?;
            bridge.next_id += 1;
            let id = bridge.next_id;
            bridge.queue.push(LuaCommand::Rock3d { id, x, y, z, size });
            Ok(id)
        })?,
    )?;

    game.set(
        "move3d",
        lua.create_function(|lua, (id, x, y, z): (u32, f32, f32, f32)| {
            if let Some(mut bridge) = lua.app_data_mut::<Bridge>() {
                bridge.queue.push(LuaCommand::Move3d { id, x, y, z });
            }
            Ok(())
        })?,
    )?;

    game.set(
        "rot3d",
        lua.create_function(|lua, (id, rx, ry, rz): (u32, f32, f32, f32)| {
            if let Some(mut bridge) = lua.app_data_mut::<Bridge>() {
                bridge.queue.push(LuaCommand::Rot3d { id, rx, ry, rz });
            }
            Ok(())
        })?,
    )?;

    game.set(
        "color3d",
        lua.create_function(|lua, (id, r, g, b): (u32, f32, f32, f32)| {
            if let Some(mut bridge) = lua.app_data_mut::<Bridge>() {
                bridge
                    .queue
                    .push(LuaCommand::Color3d { id, color: (r, g, b) });
            }
            Ok(())
        })?,
    )?;

    game.set(
        "scale3d",
        lua.create_function(|lua, (id, s): (u32, f32)| {
            if let Some(mut bridge) = lua.app_data_mut::<Bridge>() {
                bridge.queue.push(LuaCommand::Scale3d { id, s });
            }
            Ok(())
        })?,
    )?;

    game.set(
        "space_mode",
        lua.create_function(|lua, on: bool| {
            if let Some(mut bridge) = lua.app_data_mut::<Bridge>() {
                bridge.queue.push(LuaCommand::SpaceMode(on));
            }
            Ok(())
        })?,
    )?;

    game.set(
        "spawn_rig",
        lua.create_function(
            |lua, (x, y, name, scale): (f32, f32, String, Option<f32>)| {
                let mut bridge = lua
                    .app_data_mut::<Bridge>()
                    .ok_or_else(|| mlua::Error::runtime("bridge missing"))?;
                bridge.next_id += 1;
                let id = bridge.next_id;
                bridge.queue.push(LuaCommand::SpawnRig {
                    id,
                    x,
                    y,
                    name,
                    scale: scale.unwrap_or(1.0),
                });
                Ok(id)
            },
        )?,
    )?;

    game.set(
        "play_anim",
        lua.create_function(|lua, (id, clip): (u32, String)| {
            if let Some(mut bridge) = lua.app_data_mut::<Bridge>() {
                bridge.queue.push(LuaCommand::PlayAnim { id, clip });
            }
            Ok(())
        })?,
    )?;

    game.set(
        "set_bone",
        lua.create_function(
            #[allow(clippy::type_complexity)]
            |lua, (id, bone, angle, dx, dy): (u32, String, Option<f32>, Option<f32>, Option<f32>)| {
                let pose = angle.map(|a| (a, dx.unwrap_or(0.0), dy.unwrap_or(0.0)));
                if let Some(mut bridge) = lua.app_data_mut::<Bridge>() {
                    bridge.queue.push(LuaCommand::SetBone { id, bone, pose });
                }
                Ok(())
            },
        )?,
    )?;

    game.set(
        "despawn",
        lua.create_function(|lua, id: u32| {
            if let Some(mut bridge) = lua.app_data_mut::<Bridge>() {
                bridge.queue.push(LuaCommand::Despawn { id });
            }
            Ok(())
        })?,
    )?;

    game.set(
        "emit",
        lua.create_function(
            |lua, (preset, x, y, count): (String, f32, f32, Option<u32>)| {
                if let Some(mut bridge) = lua.app_data_mut::<Bridge>() {
                    bridge.queue.push(LuaCommand::Emit {
                        preset,
                        x,
                        y,
                        count: count.unwrap_or(16),
                    });
                }
                Ok(())
            },
        )?,
    )?;

    game.set(
        "set_text",
        lua.create_function(|lua, text: String| {
            if let Some(mut bridge) = lua.app_data_mut::<Bridge>() {
                bridge.queue.push(LuaCommand::SetText(text));
            }
            Ok(())
        })?,
    )?;

    game.set(
        "shake",
        lua.create_function(|lua, intensity: f32| {
            if let Some(mut bridge) = lua.app_data_mut::<Bridge>() {
                bridge.queue.push(LuaCommand::Shake(intensity));
            }
            Ok(())
        })?,
    )?;

    game.set(
        "zoom",
        lua.create_function(|lua, intensity: f32| {
            if let Some(mut bridge) = lua.app_data_mut::<Bridge>() {
                bridge.queue.push(LuaCommand::Zoom(intensity));
            }
            Ok(())
        })?,
    )?;

    game.set(
        "cam",
        lua.create_function(|lua, (x, y, zoom): (f32, f32, Option<f32>)| {
            if let Some(mut bridge) = lua.app_data_mut::<Bridge>() {
                bridge.queue.push(LuaCommand::Cam {
                    x,
                    y,
                    zoom: zoom.unwrap_or(1.0),
                });
            }
            Ok(())
        })?,
    )?;

    game.set(
        "set_bg_theme",
        lua.create_function(|lua, (theme, space): (f32, Option<f32>)| {
            if let Some(mut bridge) = lua.app_data_mut::<Bridge>() {
                bridge
                    .queue
                    .push(LuaCommand::SetBgTheme(theme, space.unwrap_or(0.0)));
            }
            Ok(())
        })?,
    )?;


    game.set(
        "play_sound",
        lua.create_function(|lua, name: String| {
            if let Some(mut bridge) = lua.app_data_mut::<Bridge>() {
                bridge.queue.push(LuaCommand::PlaySound(name));
            }
            Ok(())
        })?,
    )?;

    game.set(
        "play_music",
        lua.create_function(|lua, name: String| {
            if let Some(mut bridge) = lua.app_data_mut::<Bridge>() {
                bridge.queue.push(LuaCommand::PlayMusic(name));
            }
            Ok(())
        })?,
    )?;

    game.set(
        "play_voice",
        lua.create_function(|lua, name: String| {
            if let Some(mut bridge) = lua.app_data_mut::<Bridge>() {
                bridge.queue.push(LuaCommand::PlayVoice(name));
            }
            Ok(())
        })?,
    )?;

    game.set(
        "stop_voice",
        lua.create_function(|lua, ()| {
            if let Some(mut bridge) = lua.app_data_mut::<Bridge>() {
                bridge.queue.push(LuaCommand::StopVoice);
            }
            Ok(())
        })?,
    )?;

    game.set(
        "stop_music",
        lua.create_function(|lua, ()| {
            if let Some(mut bridge) = lua.app_data_mut::<Bridge>() {
                bridge.queue.push(LuaCommand::StopMusic);
            }
            Ok(())
        })?,
    )?;

    game.set(
        "set_volume",
        lua.create_function(|lua, (channel, volume): (String, f32)| {
            if let Some(mut bridge) = lua.app_data_mut::<Bridge>() {
                bridge.queue.push(LuaCommand::SetVolume { channel, volume });
            }
            Ok(())
        })?,
    )?;

    game.set(
        "track",
        lua.create_function(|lua, (event, value): (String, Option<f64>)| {
            if let Some(mut bridge) = lua.app_data_mut::<Bridge>() {
                bridge.queue.push(LuaCommand::Track { event, value });
            }
            Ok(())
        })?,
    )?;

    game.set(
        "open_url",
        lua.create_function(|lua, url: String| {
            if let Some(mut bridge) = lua.app_data_mut::<Bridge>() {
                bridge.queue.push(LuaCommand::OpenUrl(url));
            }
            Ok(())
        })?,
    )?;

    game.set(
        "save",
        lua.create_function(|lua, (key, value): (String, mlua::Value)| {
            let encoded = match &value {
                mlua::Value::String(s) => format!("s:{}", s.to_string_lossy()),
                mlua::Value::Integer(i) => format!("n:{i}"),
                mlua::Value::Number(n) => format!("n:{n}"),
                mlua::Value::Boolean(b) => format!("b:{b}"),
                _ => return Ok(false), // unsupported type: refuse, don't crash
            };
            if let Some(mut bridge) = lua.app_data_mut::<Bridge>() {
                bridge.store.insert(key, encoded);
                bridge.store_dirty = true;
            }
            Ok(true)
        })?,
    )?;

    game.set(
        "load",
        lua.create_function(|lua, key: String| {
            let encoded = lua
                .app_data_ref::<Bridge>()
                .and_then(|b| b.store.get(&key).cloned());
            let Some(encoded) = encoded else {
                return Ok(mlua::Value::Nil);
            };
            Ok(match encoded.split_at_checked(2) {
                Some(("s:", rest)) => mlua::Value::String(lua.create_string(rest)?),
                Some(("n:", rest)) => rest
                    .parse::<f64>()
                    .map(mlua::Value::Number)
                    .unwrap_or(mlua::Value::Nil),
                Some(("b:", rest)) => mlua::Value::Boolean(rest == "true"),
                _ => mlua::Value::Nil,
            })
        })?,
    )?;

    game.set(
        "haptic",
        lua.create_function(|lua, kind: String| {
            let style = haptic_style(&kind);
            if let Some(mut bridge) = lua.app_data_mut::<Bridge>() {
                bridge.queue.push(LuaCommand::Haptic(style));
            }
            Ok(())
        })?,
    )?;

    lua.globals().set("game", game)?;
    Ok(())
}

#[cfg(target_arch = "wasm32")]
pub struct LuaVm {
    lua: Lua,
    bridge: Rc<RefCell<Bridge>>,
    has_update: bool,
    has_tap: bool,
}

#[cfg(target_arch = "wasm32")]
impl LuaVm {
    fn new() -> Self {
        let mut lua = Lua::full();
        let bridge = Rc::new(RefCell::new(Bridge {
            store: load_store_from_localstorage(),
            ..Bridge::default()
        }));
        register_api(&mut lua, bridge.clone());
        Self {
            lua,
            bridge,
            has_update: false,
            has_tap: false,
        }
    }

    fn exec_chunk(&mut self, source: &str, name: &str) -> Result<(), String> {
        let ex = self
            .lua
            .try_enter(|ctx| {
                let closure = Closure::load(ctx, Some(name), source.as_bytes())?;
                Ok(ctx.stash(Executor::start(ctx, closure.into(), ())))
            })
            .map_err(|e| e.to_string())?;
        self.lua.execute::<()>(&ex).map_err(|e| e.to_string())
    }

    fn finish_reload(&mut self) -> Result<(), String> {
        self.has_update = self.global_is_fn("on_update");
        self.has_tap = self.global_is_fn("on_tap");
        if self.global_is_fn("on_start") {
            self.call0("on_start")?;
        }
        Ok(())
    }

    fn global_is_fn(&mut self, name: &'static str) -> bool {
        self.lua
            .enter(|ctx| matches!(ctx.get_global_value(name), Value::Function(_)))
    }

    fn call0(&mut self, name: &'static str) -> Result<(), String> {
        let ex = self
            .lua
            .try_enter(|ctx| {
                let f: Function = ctx.get_global(name)?;
                Ok(ctx.stash(Executor::start(ctx, f, ())))
            })
            .map_err(|e| e.to_string())?;
        self.lua.execute::<()>(&ex).map_err(|e| e.to_string())
    }

    fn set_screen(&mut self, half_w: f32, half_h: f32) {
        self.bridge.borrow_mut().screen = (half_w, half_h);
    }

    fn set_date(&mut self, date: (i32, u32, u32)) {
        self.bridge.borrow_mut().date_utc = date;
    }

    fn set_input(
        &mut self,
        pointer: Option<(f32, f32)>,
        pointer_down: bool,
        keys: std::collections::HashSet<&'static str>,
        touches: Vec<(f32, f32, u64)>,
    ) {
        let mut b = self.bridge.borrow_mut();
        b.pointer = pointer;
        b.pointer_down = pointer_down;
        b.keys = keys;
        b.touches = touches;
    }

    fn on_tap(&mut self, x: f32, y: f32) {
        if !self.has_tap {
            return;
        }
        let res = (|| -> Result<(), String> {
            let ex = self
                .lua
                .try_enter(|ctx| {
                    let f: Function = ctx.get_global("on_tap")?;
                    Ok(ctx.stash(Executor::start(ctx, f, (x as f64, y as f64))))
                })
                .map_err(|e| e.to_string())?;
            self.lua.execute::<()>(&ex).map_err(|e| e.to_string())
        })();
        if let Err(err) = res {
            error!("lua on_tap error: {err}");
        }
    }

    fn update(&mut self, dt: f32) {
        if !self.has_update {
            return;
        }
        let res = (|| -> Result<(), String> {
            let ex = self
                .lua
                .try_enter(|ctx| {
                    let f: Function = ctx.get_global("on_update")?;
                    Ok(ctx.stash(Executor::start(ctx, f, dt as f64)))
                })
                .map_err(|e| e.to_string())?;
            self.lua.execute::<()>(&ex).map_err(|e| e.to_string())
        })();
        if let Err(err) = res {
            error!("lua on_update error: {err}");
        }
    }

    fn drain(&mut self) -> Vec<LuaCommand> {
        std::mem::take(&mut self.bridge.borrow_mut().queue)
    }

    /// wasm has no filesystem: the store lives for the session only, so there
    /// is never anything to flush (clearing the flag keeps the system cheap).
    fn take_dirty_store(&mut self) -> Option<String> {
        let mut bridge = self.bridge.borrow_mut();
        if !bridge.store_dirty {
            return None;
        }
        bridge.store_dirty = false;
        Some(encode_store(&bridge.store))
    }
}

/// Register the global `game` table. Each callback captures a clone of the shared
/// `Bridge` `Rc` and pushes `LuaCommand`s / reads the input snapshot. (piccolo/
/// ottavino has no `app_data` like mlua, and its callbacks are `'static`, so the
/// bridge is shared via `Rc<RefCell<_>>` — sound because the VM is single-threaded.)
#[cfg(target_arch = "wasm32")]
fn register_api(lua: &mut Lua, bridge: Rc<RefCell<Bridge>>) {
    lua.enter(|ctx| {
        let game = Table::new(&ctx);

        game.set(ctx, "log", Callback::from_fn(&ctx, |_ctx, _, mut stack| {
            if let Value::String(s) = stack.get(0) {
                info!("[lua] {}", String::from_utf8_lossy(s.as_bytes()));
            }
            stack.clear();
            Ok(CallbackReturn::Return)
        })).unwrap();

        let b = bridge.clone();
        game.set(ctx, "bounds", Callback::from_fn(&ctx, move |ctx, _, mut stack| {
            let (hw, hh) = b.borrow().screen;
            stack.replace(ctx, (hw as f64, hh as f64));
            Ok(CallbackReturn::Return)
        })).unwrap();

        let b = bridge.clone();
        game.set(ctx, "pointer", Callback::from_fn(&ctx, move |ctx, _, mut stack| {
            let (p, down) = { let br = b.borrow(); (br.pointer, br.pointer_down) };
            match p {
                Some((x, y)) => stack.replace(ctx, (x as f64, y as f64, down)),
                None => stack.replace(ctx, (Value::Nil, Value::Nil, down)),
            }
            Ok(CallbackReturn::Return)
        })).unwrap();

        let b = bridge.clone();
        game.set(ctx, "touches", Callback::from_fn(&ctx, move |ctx, _, mut stack| {
            let touches = b.borrow().touches.clone();
            let list = Table::new(&ctx);
            for (i, (x, y, id)) in touches.iter().enumerate() {
                let t = Table::new(&ctx);
                t.set(ctx, "x", *x as f64).unwrap();
                t.set(ctx, "y", *y as f64).unwrap();
                t.set(ctx, "id", *id as i64).unwrap();
                list.set(ctx, (i + 1) as i64, t).unwrap();
            }
            stack.replace(ctx, list);
            Ok(CallbackReturn::Return)
        })).unwrap();

        let b = bridge.clone();
        game.set(ctx, "key", Callback::from_fn(&ctx, move |ctx, _, mut stack| {
            let name: ottavino::String = stack.consume(ctx)?;
            let held = b.borrow().keys.contains(name.to_str().unwrap_or(""));
            stack.replace(ctx, held);
            Ok(CallbackReturn::Return)
        })).unwrap();

        let b = bridge.clone();
        game.set(ctx, "date_utc", Callback::from_fn(&ctx, move |ctx, _, mut stack| {
            let (y, m, d) = { let dt = b.borrow().date_utc; if dt.0 > 0 { dt } else { (1970, 1, 1) } };
            stack.replace(ctx, (y as i64, m as i64, d as i64));
            Ok(CallbackReturn::Return)
        })).unwrap();

        let b = bridge.clone();
        game.set(ctx, "spawn", Callback::from_fn(&ctx, move |ctx, _, mut stack| {
            let (x, y, w, h, r, g, bl, a): (f32, f32, f32, f32, f32, f32, f32, Option<f32>) =
                stack.consume(ctx)?;
            let id = { let mut br = b.borrow_mut(); br.next_id += 1; let id = br.next_id;
                br.queue.push(LuaCommand::Spawn { id, x, y, w, h, color: (r, g, bl, a.unwrap_or(1.0)) }); id };
            stack.replace(ctx, id as i64);
            Ok(CallbackReturn::Return)
        })).unwrap();

        let b = bridge.clone();
        game.set(ctx, "move_to", Callback::from_fn(&ctx, move |ctx, _, mut stack| {
            let (id, x, y): (u32, f32, f32) = stack.consume(ctx)?;
            b.borrow_mut().queue.push(LuaCommand::MoveTo { id, x, y });
            Ok(CallbackReturn::Return)
        })).unwrap();

        let b = bridge.clone();
        game.set(ctx, "set_color", Callback::from_fn(&ctx, move |ctx, _, mut stack| {
            let (id, r, g, bl, a): (u32, f32, f32, f32, f32) = stack.consume(ctx)?;
            b.borrow_mut().queue.push(LuaCommand::SetColor { id, color: (r, g, bl, a) });
            Ok(CallbackReturn::Return)
        })).unwrap();

        let b = bridge.clone();
        game.set(ctx, "set_size", Callback::from_fn(&ctx, move |ctx, _, mut stack| {
            let (id, w, h): (u32, f32, f32) = stack.consume(ctx)?;
            b.borrow_mut().queue.push(LuaCommand::SetSize { id, w, h });
            Ok(CallbackReturn::Return)
        })).unwrap();

        let b = bridge.clone();
        game.set(ctx, "set_rotation", Callback::from_fn(&ctx, move |ctx, _, mut stack| {
            let (id, radians): (u32, f32) = stack.consume(ctx)?;
            b.borrow_mut().queue.push(LuaCommand::SetRotation { id, radians });
            Ok(CallbackReturn::Return)
        })).unwrap();

        let b = bridge.clone();
        game.set(ctx, "set_sprite_image", Callback::from_fn(&ctx, move |ctx, _, mut stack| {
            let (id, image): (u32, ottavino::String) = stack.consume(ctx)?;
            b.borrow_mut().queue.push(LuaCommand::SetSpriteImage { id, image: image.to_str().unwrap_or("").to_string() });
            Ok(CallbackReturn::Return)
        })).unwrap();

        let b = bridge.clone();
        game.set(ctx, "tween", Callback::from_fn(&ctx, move |ctx, _, mut stack| {
            let (id, x, y, scale, dur, ease, delay, from_scale): (
                u32, Option<f32>, Option<f32>, Option<f32>, f32,
                Option<ottavino::String>, Option<f32>, Option<f32>,
            ) = stack.consume(ctx)?;
            b.borrow_mut().queue.push(LuaCommand::Tween {
                id, x, y, scale, dur,
                ease: ease.and_then(|s| s.to_str().ok().map(|s| s.to_string()))
                          .unwrap_or_else(|| "out".into()),
                delay: delay.unwrap_or(0.0),
                from_scale,
            });
            Ok(CallbackReturn::Return)
        })).unwrap();

        let b = bridge.clone();
        game.set(ctx, "spawn_text", Callback::from_fn(&ctx, move |ctx, _, mut stack| {
            let (x, y, size, r, g, bl, a, text): (f32, f32, f32, f32, f32, f32, f32, ottavino::String) =
                stack.consume(ctx)?;
            let id = { let mut br = b.borrow_mut(); br.next_id += 1; let id = br.next_id;
                br.queue.push(LuaCommand::SpawnText { id, x, y, size, color: (r, g, bl, a), text: text.to_str().unwrap_or("").to_string() }); id };
            stack.replace(ctx, id as i64);
            Ok(CallbackReturn::Return)
        })).unwrap();

        let b = bridge.clone();
        game.set(ctx, "spawn_sprite", Callback::from_fn(&ctx, move |ctx, _, mut stack| {
            let (x, y, w, h, image): (f32, f32, f32, f32, ottavino::String) = stack.consume(ctx)?;
            let id = { let mut br = b.borrow_mut(); br.next_id += 1; let id = br.next_id;
                br.queue.push(LuaCommand::SpawnSprite { id, x, y, w, h, image: image.to_str().unwrap_or("").to_string() }); id };
            stack.replace(ctx, id as i64);
            Ok(CallbackReturn::Return)
        })).unwrap();

        let b = bridge.clone();
        game.set(ctx, "spawn_sheet", Callback::from_fn(&ctx, move |ctx, _, mut stack| {
            let (x, y, w, h, image, fw, fh, cols, frames):
                (f32, f32, f32, f32, ottavino::String, f32, f32, u32, u32) = stack.consume(ctx)?;
            let id = { let mut br = b.borrow_mut(); br.next_id += 1; let id = br.next_id;
                br.queue.push(LuaCommand::SpawnSheet { id, x, y, w, h,
                    image: image.to_str().unwrap_or("").to_string(), fw, fh, cols, frames }); id };
            stack.replace(ctx, id as i64);
            Ok(CallbackReturn::Return)
        })).unwrap();

        let b = bridge.clone();
        game.set(ctx, "set_frame", Callback::from_fn(&ctx, move |ctx, _, mut stack| {
            let (id, frame): (u32, i64) = stack.consume(ctx)?;
            b.borrow_mut().queue.push(LuaCommand::SetFrame { id, frame });
            Ok(CallbackReturn::Return)
        })).unwrap();

        let b = bridge.clone();
        game.set(ctx, "spawn_panel", Callback::from_fn(&ctx, move |ctx, _, mut stack| {
            let (x, y, w, h, image, border): (f32, f32, f32, f32, ottavino::String, f32) =
                stack.consume(ctx)?;
            let id = { let mut br = b.borrow_mut(); br.next_id += 1; let id = br.next_id;
                br.queue.push(LuaCommand::SpawnPanel { id, x, y, w, h,
                    image: image.to_str().unwrap_or("").to_string(), border }); id };
            stack.replace(ctx, id as i64);
            Ok(CallbackReturn::Return)
        })).unwrap();

        let b = bridge.clone();
        game.set(ctx, "set_layer", Callback::from_fn(&ctx, move |ctx, _, mut stack| {
            let (id, z): (u32, f32) = stack.consume(ctx)?;
            b.borrow_mut().queue.push(LuaCommand::SetLayer { id, z });
            Ok(CallbackReturn::Return)
        })).unwrap();

        let b = bridge.clone();
        game.set(ctx, "tilemap", Callback::from_fn(&ctx, move |ctx, _, mut stack| {
            let (x, y, cols, rows, tw, th, image, tcols, tframes):
                (f32, f32, u32, u32, f32, f32, ottavino::String, u32, u32) = stack.consume(ctx)?;
            let id = { let mut br = b.borrow_mut(); br.next_id += 1; let id = br.next_id;
                br.queue.push(LuaCommand::Tilemap { id, x, y, cols, rows, tw, th,
                    image: image.to_str().unwrap_or("").to_string(), tcols, tframes }); id };
            stack.replace(ctx, id as i64);
            Ok(CallbackReturn::Return)
        })).unwrap();

        let b = bridge.clone();
        game.set(ctx, "set_tile", Callback::from_fn(&ctx, move |ctx, _, mut stack| {
            let (id, tx, ty, index): (u32, i64, i64, i64) = stack.consume(ctx)?;
            b.borrow_mut().queue.push(LuaCommand::SetTile { id, tx, ty, index });
            Ok(CallbackReturn::Return)
        })).unwrap();

        let b = bridge.clone();
        game.set(ctx, "rock3d", Callback::from_fn(&ctx, move |ctx, _, mut stack| {
            let (x, y, z, size): (f32, f32, f32, f32) = stack.consume(ctx)?;
            let id = { let mut br = b.borrow_mut(); br.next_id += 1; let id = br.next_id;
                br.queue.push(LuaCommand::Rock3d { id, x, y, z, size }); id };
            stack.replace(ctx, id as i64);
            Ok(CallbackReturn::Return)
        })).unwrap();

        let b = bridge.clone();
        game.set(ctx, "move3d", Callback::from_fn(&ctx, move |ctx, _, mut stack| {
            let (id, x, y, z): (u32, f32, f32, f32) = stack.consume(ctx)?;
            b.borrow_mut().queue.push(LuaCommand::Move3d { id, x, y, z });
            Ok(CallbackReturn::Return)
        })).unwrap();

        let b = bridge.clone();
        game.set(ctx, "rot3d", Callback::from_fn(&ctx, move |ctx, _, mut stack| {
            let (id, rx, ry, rz): (u32, f32, f32, f32) = stack.consume(ctx)?;
            b.borrow_mut().queue.push(LuaCommand::Rot3d { id, rx, ry, rz });
            Ok(CallbackReturn::Return)
        })).unwrap();

        let b = bridge.clone();
        game.set(ctx, "color3d", Callback::from_fn(&ctx, move |ctx, _, mut stack| {
            let (id, r, g, bl): (u32, f32, f32, f32) = stack.consume(ctx)?;
            b.borrow_mut().queue.push(LuaCommand::Color3d { id, color: (r, g, bl) });
            Ok(CallbackReturn::Return)
        })).unwrap();

        let b = bridge.clone();
        game.set(ctx, "scale3d", Callback::from_fn(&ctx, move |ctx, _, mut stack| {
            let (id, s): (u32, f32) = stack.consume(ctx)?;
            b.borrow_mut().queue.push(LuaCommand::Scale3d { id, s });
            Ok(CallbackReturn::Return)
        })).unwrap();

        let b = bridge.clone();
        game.set(ctx, "space_mode", Callback::from_fn(&ctx, move |ctx, _, mut stack| {
            let on: bool = stack.consume(ctx)?;
            b.borrow_mut().queue.push(LuaCommand::SpaceMode(on));
            Ok(CallbackReturn::Return)
        })).unwrap();

        let b = bridge.clone();
        game.set(ctx, "spawn_rig", Callback::from_fn(&ctx, move |ctx, _, mut stack| {
            let (x, y, name, scale): (f32, f32, ottavino::String, Option<f32>) =
                stack.consume(ctx)?;
            let id = { let mut br = b.borrow_mut(); br.next_id += 1; let id = br.next_id;
                br.queue.push(LuaCommand::SpawnRig { id, x, y,
                    name: name.to_str().unwrap_or("").to_string(),
                    scale: scale.unwrap_or(1.0) }); id };
            stack.replace(ctx, id as i64);
            Ok(CallbackReturn::Return)
        })).unwrap();

        let b = bridge.clone();
        game.set(ctx, "play_anim", Callback::from_fn(&ctx, move |ctx, _, mut stack| {
            let (id, clip): (u32, ottavino::String) = stack.consume(ctx)?;
            b.borrow_mut().queue.push(LuaCommand::PlayAnim { id,
                clip: clip.to_str().unwrap_or("").to_string() });
            Ok(CallbackReturn::Return)
        })).unwrap();

        let b = bridge.clone();
        game.set(ctx, "set_bone", Callback::from_fn(&ctx, move |ctx, _, mut stack| {
            let (id, bone, angle, dx, dy):
                (u32, ottavino::String, Option<f32>, Option<f32>, Option<f32>) =
                stack.consume(ctx)?;
            let pose = angle.map(|a| (a, dx.unwrap_or(0.0), dy.unwrap_or(0.0)));
            b.borrow_mut().queue.push(LuaCommand::SetBone { id,
                bone: bone.to_str().unwrap_or("").to_string(), pose });
            Ok(CallbackReturn::Return)
        })).unwrap();

        let b = bridge.clone();
        game.set(ctx, "despawn", Callback::from_fn(&ctx, move |ctx, _, mut stack| {
            let id: u32 = stack.consume(ctx)?;
            b.borrow_mut().queue.push(LuaCommand::Despawn { id });
            Ok(CallbackReturn::Return)
        })).unwrap();

        let b = bridge.clone();
        game.set(ctx, "emit", Callback::from_fn(&ctx, move |ctx, _, mut stack| {
            let (preset, x, y, count): (ottavino::String, f32, f32, Option<u32>) =
                stack.consume(ctx)?;
            b.borrow_mut().queue.push(LuaCommand::Emit {
                preset: preset.to_str().unwrap_or("").to_string(),
                x,
                y,
                count: count.unwrap_or(16),
            });
            Ok(CallbackReturn::Return)
        })).unwrap();

        let b = bridge.clone();
        game.set(ctx, "set_text", Callback::from_fn(&ctx, move |ctx, _, mut stack| {
            let text: ottavino::String = stack.consume(ctx)?;
            b.borrow_mut().queue.push(LuaCommand::SetText(text.to_str().unwrap_or("").to_string()));
            Ok(CallbackReturn::Return)
        })).unwrap();

        let b = bridge.clone();
        game.set(ctx, "shake", Callback::from_fn(&ctx, move |ctx, _, mut stack| {
            let intensity: f32 = stack.consume(ctx)?;
            b.borrow_mut().queue.push(LuaCommand::Shake(intensity));
            Ok(CallbackReturn::Return)
        })).unwrap();

        let b = bridge.clone();
        game.set(ctx, "zoom", Callback::from_fn(&ctx, move |ctx, _, mut stack| {
            let intensity: f32 = stack.consume(ctx)?;
            b.borrow_mut().queue.push(LuaCommand::Zoom(intensity));
            Ok(CallbackReturn::Return)
        })).unwrap();

        let b = bridge.clone();
        game.set(ctx, "cam", Callback::from_fn(&ctx, move |ctx, _, mut stack| {
            let (x, y, zoom): (f32, f32, Option<f32>) = stack.consume(ctx)?;
            b.borrow_mut().queue.push(LuaCommand::Cam { x, y, zoom: zoom.unwrap_or(1.0) });
            Ok(CallbackReturn::Return)
        })).unwrap();

        let b = bridge.clone();
        game.set(ctx, "set_bg_theme", Callback::from_fn(&ctx, move |ctx, _, mut stack| {
            let (theme, space): (f32, Option<f32>) = stack.consume(ctx)?;
            b.borrow_mut().queue.push(LuaCommand::SetBgTheme(theme, space.unwrap_or(0.0)));
            Ok(CallbackReturn::Return)
        })).unwrap();

        let b = bridge.clone();
        game.set(ctx, "play_sound", Callback::from_fn(&ctx, move |ctx, _, mut stack| {
            let name: ottavino::String = stack.consume(ctx)?;
            b.borrow_mut().queue.push(LuaCommand::PlaySound(name.to_str().unwrap_or("").to_string()));
            Ok(CallbackReturn::Return)
        })).unwrap();

        let b = bridge.clone();
        game.set(ctx, "play_music", Callback::from_fn(&ctx, move |ctx, _, mut stack| {
            let name: ottavino::String = stack.consume(ctx)?;
            b.borrow_mut().queue.push(LuaCommand::PlayMusic(name.to_str().unwrap_or("").to_string()));
            Ok(CallbackReturn::Return)
        })).unwrap();

        let b = bridge.clone();
        game.set(ctx, "play_voice", Callback::from_fn(&ctx, move |ctx, _, mut stack| {
            let name: ottavino::String = stack.consume(ctx)?;
            b.borrow_mut().queue.push(LuaCommand::PlayVoice(name.to_str().unwrap_or("").to_string()));
            Ok(CallbackReturn::Return)
        })).unwrap();

        let b = bridge.clone();
        game.set(ctx, "stop_voice", Callback::from_fn(&ctx, move |_ctx, _, mut stack| {
            b.borrow_mut().queue.push(LuaCommand::StopVoice);
            stack.clear();
            Ok(CallbackReturn::Return)
        })).unwrap();

        let b = bridge.clone();
        game.set(ctx, "stop_music", Callback::from_fn(&ctx, move |_ctx, _, mut stack| {
            b.borrow_mut().queue.push(LuaCommand::StopMusic);
            stack.clear();
            Ok(CallbackReturn::Return)
        })).unwrap();

        let b = bridge.clone();
        game.set(ctx, "set_volume", Callback::from_fn(&ctx, move |ctx, _, mut stack| {
            let (channel, volume): (ottavino::String, f32) = stack.consume(ctx)?;
            b.borrow_mut().queue.push(LuaCommand::SetVolume {
                channel: channel.to_str().unwrap_or("").to_string(),
                volume,
            });
            Ok(CallbackReturn::Return)
        })).unwrap();

        let b = bridge.clone();
        game.set(ctx, "track", Callback::from_fn(&ctx, move |ctx, _, mut stack| {
            let (event, value): (ottavino::String, Option<f64>) = stack.consume(ctx)?;
            b.borrow_mut().queue.push(LuaCommand::Track {
                event: event.to_str().unwrap_or("").to_string(),
                value,
            });
            Ok(CallbackReturn::Return)
        })).unwrap();

        let b = bridge.clone();
        game.set(ctx, "open_url", Callback::from_fn(&ctx, move |ctx, _, mut stack| {
            let url: ottavino::String = stack.consume(ctx)?;
            b.borrow_mut()
                .queue
                .push(LuaCommand::OpenUrl(url.to_str().unwrap_or("").to_string()));
            Ok(CallbackReturn::Return)
        })).unwrap();

        let b = bridge.clone();
        game.set(ctx, "save", Callback::from_fn(&ctx, move |ctx, _, mut stack| {
            let (key, value): (ottavino::String, Value) = stack.consume(ctx)?;
            let encoded = match value {
                Value::String(s) => Some(format!("s:{}", String::from_utf8_lossy(s.as_bytes()))),
                Value::Integer(i) => Some(format!("n:{i}")),
                Value::Number(n) => Some(format!("n:{n}")),
                Value::Boolean(v) => Some(format!("b:{v}")),
                _ => None,
            };
            let ok = encoded.is_some();
            if let Some(encoded) = encoded {
                let mut br = b.borrow_mut();
                br.store.insert(key.to_str().unwrap_or("").to_string(), encoded);
                br.store_dirty = true;
            }
            stack.replace(ctx, ok);
            Ok(CallbackReturn::Return)
        })).unwrap();

        let b = bridge.clone();
        game.set(ctx, "load", Callback::from_fn(&ctx, move |ctx, _, mut stack| {
            let key: ottavino::String = stack.consume(ctx)?;
            let encoded = b.borrow().store.get(key.to_str().unwrap_or("")).cloned();
            match encoded.as_deref().and_then(|e| e.split_at_checked(2)) {
                Some(("s:", rest)) => {
                    let s = ctx.intern(rest.as_bytes());
                    stack.replace(ctx, Value::String(s));
                }
                Some(("n:", rest)) => match rest.parse::<f64>() {
                    Ok(n) => stack.replace(ctx, n),
                    Err(_) => stack.replace(ctx, Value::Nil),
                },
                Some(("b:", rest)) => stack.replace(ctx, rest == "true"),
                _ => stack.replace(ctx, Value::Nil),
            }
            Ok(CallbackReturn::Return)
        })).unwrap();

        let b = bridge.clone();
        game.set(ctx, "haptic", Callback::from_fn(&ctx, move |ctx, _, mut stack| {
            let kind: ottavino::String = stack.consume(ctx)?;
            let style = haptic_style(kind.to_str().unwrap_or(""));
            b.borrow_mut().queue.push(LuaCommand::Haptic(style));
            Ok(CallbackReturn::Return)
        })).unwrap();

        ctx.set_global("game", game);
    });
}

// ---------------------------------------------------------------------------
// Save-store codec (game.save / game.load)
// ---------------------------------------------------------------------------
// One line per key: `key<TAB>value`, where value carries a type prefix
// (`s:` string, `n:` number, `b:` boolean). Keys and values are escaped so
// tabs/newlines in user strings can't break the framing. Text, diffable,
// no serde needed.

/// Escape `\`, TAB and NL so a store entry always fits one `key\tvalue` line.
fn store_escape(s: &str) -> String {
    s.replace('\\', "\\\\").replace('\t', "\\t").replace('\n', "\\n")
}

fn store_unescape(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    let mut chars = s.chars();
    while let Some(c) = chars.next() {
        if c == '\\' {
            match chars.next() {
                Some('t') => out.push('\t'),
                Some('n') => out.push('\n'),
                Some('\\') => out.push('\\'),
                Some(other) => out.push(other), // tolerate unknown escapes
                None => {}
            }
        } else {
            out.push(c);
        }
    }
    out
}

/// Serialize the store deterministically (sorted keys) for stable diffs.
fn encode_store(store: &HashMap<String, String>) -> String {
    let mut keys: Vec<&String> = store.keys().collect();
    keys.sort();
    let mut out = String::new();
    for k in keys {
        out.push_str(&store_escape(k));
        out.push('\t');
        out.push_str(&store_escape(&store[k]));
        out.push('\n');
    }
    out
}

/// Parse a store file. Malformed lines (no TAB) are skipped, not fatal — a
/// corrupt save must never brick the game.
fn decode_store(text: &str) -> HashMap<String, String> {
    let mut map = HashMap::new();
    for line in text.lines() {
        if let Some((k, v)) = line.split_once('\t') {
            map.insert(store_unescape(k), store_unescape(v));
        }
    }
    map
}

/// Where the save file lives. `$HOME` exists on desktop and inside the iOS app
/// sandbox alike; fall back to the working directory if it's unset.
#[cfg(not(target_arch = "wasm32"))]
fn save_file_path() -> PathBuf {
    let base = std::env::var_os("HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from("."));
    base.join(".hollowlullaby").join("save.txt")
}

#[cfg(not(target_arch = "wasm32"))]
fn load_store_from_disk() -> HashMap<String, String> {
    std::fs::read_to_string(save_file_path())
        .map(|text| decode_store(&text))
        .unwrap_or_default()
}

#[cfg(not(target_arch = "wasm32"))]
fn write_store_to_disk(content: &str) {
    let path = save_file_path();
    if let Some(dir) = path.parent() {
        let _ = std::fs::create_dir_all(dir);
    }
    if let Err(err) = std::fs::write(&path, content) {
        error!("failed to write save file {}: {err}", path.display());
    }
}

/// On the web the save store persists to `localStorage` (survives refresh and
/// tab close), keyed under one entry. Same encoded format as the desktop file.
#[cfg(target_arch = "wasm32")]
const WASM_SAVE_KEY: &str = "hollowlullaby_save";

#[cfg(target_arch = "wasm32")]
fn load_store_from_localstorage() -> HashMap<String, String> {
    web_sys::window()
        .and_then(|w| w.local_storage().ok().flatten())
        .and_then(|s| s.get_item(WASM_SAVE_KEY).ok().flatten())
        .map(|text| decode_store(&text))
        .unwrap_or_default()
}

#[cfg(target_arch = "wasm32")]
fn write_store_to_localstorage(content: &str) {
    if let Some(storage) = web_sys::window().and_then(|w| w.local_storage().ok().flatten()) {
        let _ = storage.set_item(WASM_SAVE_KEY, content);
    }
}

/// Flush `game.save` writes to persistent storage once per frame at most:
/// a file on desktop/iOS, `localStorage` on the web.
fn flush_save(mut vm: NonSendMut<LuaVm>) {
    if let Some(content) = vm.take_dirty_store() {
        #[cfg(not(target_arch = "wasm32"))]
        write_store_to_disk(&content);
        #[cfg(target_arch = "wasm32")]
        write_store_to_localstorage(&content);
    }
}

/// Map a Lua haptic kind name to the integer style `hl_haptic` expects.
fn haptic_style(kind: &str) -> i32 {
    match kind {
        "medium" => 1,
        "heavy" => 2,
        "success" => 3,
        _ => 0, // "light" and anything else
    }
}

/// The camera offset for a given shake `trauma` (0..1) at time `t` seconds.
/// `trauma²` makes light taps fall off fast; the sines supply the jitter.
/// Shared with the 3D camera (rock3d.rs) so both layers jitter as one.
pub(crate) fn shake_offset(trauma: f32, t: f32) -> (f32, f32) {
    const MAX_OFFSET: f32 = 24.0;
    let amount = trauma * trauma;
    (
        amount * MAX_OFFSET * (t * 41.0).sin(),
        amount * MAX_OFFSET * (t * 47.0).cos(),
    )
}

/// Trigger an iOS haptic. On other platforms this is a no-op.
fn trigger_haptic(style: i32) {
    #[cfg(target_os = "ios")]
    unsafe {
        hl_haptic(style);
    }
    #[cfg(not(target_os = "ios"))]
    let _ = style;
}

#[cfg(target_os = "ios")]
extern "C" {
    /// Defined in `ios/Sources/haptics.m`.
    fn hl_haptic(style: i32);
}

// ---------------------------------------------------------------------------
// Systems
// ---------------------------------------------------------------------------

fn reload_changed_scripts(
    mut events: MessageReader<AssetEvent<LuaScript>>,
    scripts: Res<Assets<LuaScript>>,
    assets: Res<AssetServer>,
    handles: Option<ResMut<ScriptHandles>>,
    mut vm: NonSendMut<LuaVm>,
) {
    let Some(mut handles) = handles else { return };
    // First load: run once when all scripts settle. After that, only a *Modified*
    // event (desktop hot-reload) re-runs — this avoids re-executing `on_start`
    // several times for the initial `Added` events (which caused startup churn).
    for event in events.read() {
        match event {
            AssetEvent::Modified { .. } => handles.dirty = true,
            AssetEvent::Added { .. } if !handles.initialized => handles.dirty = true,
            _ => {}
        }
    }
    if !handles.dirty {
        return;
    }

    // Gather sources in execution order. Wait (staying dirty, retrying next
    // frame) while any is still loading, but *skip* one that failed to load so a
    // missing/broken extra file can never block `main.lua` and the menu forever.
    let mut chunks = Vec::with_capacity(handles.list.len());
    for (name, handle) in &handles.list {
        if let Some(script) = scripts.get(handle) {
            chunks.push((name.clone(), script.source.clone()));
        } else if matches!(assets.get_load_state(handle), Some(LoadState::Failed(_))) {
            warn!("skipping Lua script that failed to load: {name}");
        } else {
            return; // still loading; retry next frame
        }
    }

    handles.dirty = false;
    for (name, source) in &chunks {
        if let Err(err) = vm.exec_chunk(source, name) {
            error!("lua load error in {name}: {err}");
            return;
        }
    }
    match vm.finish_reload() {
        Ok(()) => {
            handles.initialized = true;
            info!("loaded {} Lua scripts", chunks.len());
        }
        Err(err) => error!("lua on_start error: {err}"),
    }
}

/// Map the keys Lua can ask about to their Bevy `KeyCode`s.
fn key_snapshot(keyboard: &ButtonInput<KeyCode>) -> std::collections::HashSet<&'static str> {
    const BINDINGS: [(KeyCode, &str); 9] = [
        (KeyCode::ArrowUp, "up"),
        (KeyCode::ArrowDown, "down"),
        (KeyCode::ArrowLeft, "left"),
        (KeyCode::ArrowRight, "right"),
        (KeyCode::KeyW, "w"),
        (KeyCode::KeyA, "a"),
        (KeyCode::KeyS, "s"),
        (KeyCode::KeyD, "d"),
        (KeyCode::Space, "space"),
    ];
    BINDINGS
        .iter()
        .filter(|(code, _)| keyboard.pressed(*code))
        .map(|(_, name)| *name)
        .collect()
}

/// Feed the screen size + input (taps, pointer, keys) into Lua, then tick
/// `on_update`.
fn tick_lua(
    time: Res<Time>,
    mut vm: NonSendMut<LuaVm>,
    windows: Query<&Window>,
    touches: Res<Touches>,
    mouse: Res<ButtonInput<MouseButton>>,
    keyboard: Res<ButtonInput<KeyCode>>,
    // Scoped to the 2D GameCamera: once the 3D camera (rock3d.rs) exists,
    // an unfiltered `.single()` would fail and silently kill all input.
    cameras: Query<(&Camera, &GlobalTransform), With<GameCamera>>,
) {
    let Ok(window) = windows.single() else {
        vm.update(time.delta_secs());
        return;
    };
    vm.set_screen(window.width() * 0.5, window.height() * 0.5);
    vm.set_date(utc_date_now());

    let Ok((camera, cam_transform)) = cameras.single() else {
        vm.update(time.delta_secs());
        return;
    };

    // Taps from touch (just-pressed) and a left click.
    let mut taps: Vec<Vec2> = touches.iter_just_pressed().map(|t| t.position()).collect();
    if mouse.just_pressed(MouseButton::Left) {
        if let Some(cursor) = window.cursor_position() {
            taps.push(cursor);
        }
    }
    for pixel in &taps {
        if let Ok(world) = camera.viewport_to_world_2d(cam_transform, *pixel) {
            vm.on_tap(world.x, world.y);
        }
    }

    // Current pointer (mouse cursor wins; otherwise first active touch) + held.
    let mut pointer_px: Option<Vec2> = touches.iter().next().map(|t| t.position());
    let mut pointer_down = touches.iter().next().is_some();
    if let Some(cursor) = window.cursor_position() {
        pointer_px = Some(cursor);
    }
    if mouse.pressed(MouseButton::Left) {
        pointer_down = true;
    }
    let pointer_world = pointer_px
        .and_then(|p| camera.viewport_to_world_2d(cam_transform, p).ok())
        .map(|w| (w.x, w.y));

    // Multi-touch snapshot: every active touch in world coords. On desktop a
    // held left click doubles as touch id 0 so two-finger code paths can at
    // least be single-finger-exercised without a touchscreen.
    let mut touch_list: Vec<(f32, f32, u64)> = touches
        .iter()
        .filter_map(|t| {
            camera
                .viewport_to_world_2d(cam_transform, t.position())
                .ok()
                .map(|w| (w.x, w.y, t.id()))
        })
        .collect();
    if touch_list.is_empty() && mouse.pressed(MouseButton::Left) {
        if let Some((x, y)) = pointer_world {
            touch_list.push((x, y, 0));
        }
    }

    vm.set_input(pointer_world, pointer_down, key_snapshot(&keyboard), touch_list);
    vm.update(time.delta_secs());
}

/// Apply everything Lua queued this frame.
#[allow(clippy::too_many_arguments)] // Bevy systems legitimately take many params
#[allow(clippy::type_complexity)] // params are bundled into tuples to stay under 16
fn apply_lua(
    mut commands: Commands,
    mut vm: NonSendMut<LuaVm>,
    mut registry: ResMut<EntityRegistry>,
    mut transforms: Query<&mut Transform>,
    mut sprites: Query<&mut Sprite>,
    mut texts: Query<&mut Text>,
    mut shake: ResMut<ScreenShake>,
    mut cam_rig: ResMut<CameraRig>,
    mut bg_theme: ResMut<BackgroundTheme>,
    // Audio channel state, bundled into one SystemParam tuple to stay under
    // Bevy's 16-parameter system limit.
    mut audio: (
        ResMut<CurrentMusic>,
        ResMut<AudioVolumes>,
        Query<Entity, With<MusicSound>>,
        Query<Entity, With<VoiceSound>>,
        Query<&'static mut AudioSink, (With<MusicSound>, Without<VoiceSound>)>,
        Query<&'static mut AudioSink, (With<VoiceSound>, Without<MusicSound>)>,
    ),
    // Visual registries + the 3D path, bundled for the same 16-parameter reason.
    mut vis: (
        ResMut<TextureCache>,
        ResMut<SheetRegistry>,
        ResMut<TilemapRegistry>,
        ResMut<Rock3dState>,
        ResMut<Assets<Mesh>>,
        ResMut<Assets<StandardMaterial>>,
        ResMut<Assets<crate::rock3d::SpaceMaterial>>,
        Query<&'static mut Camera, With<GameCamera>>,
    ),
    particles_alive: Query<(), With<Particle>>,
    mut emit_seed: Local<u64>,
    rig_q: (Query<&mut RigState>, Query<&crate::rig::RigBones>),
    assets: Res<AssetServer>,
    hud: Option<Res<Hud>>,
) {
    let (mut rig_states, rig_bones) = rig_q;
    let (
        ref mut tex_cache,
        ref mut sheet_registry,
        ref mut tilemaps,
        ref mut rocks,
        ref mut meshes,
        ref mut std_materials,
        ref mut space_materials,
        ref mut cameras_2d,
    ) = vis;
    // Sprites spawn at increasing z so later-spawned things (ball) draw in front
    // of earlier ones (net, trail) without depending on transparent-sort order.
    // De-dup identical SFX within this frame so a burst of the same impact plays
    // once rather than stacking into a harsh cluster.
    let mut sfx_this_frame: std::collections::HashSet<String> = std::collections::HashSet::new();
    // A music track spawned by an earlier command in THIS drain isn't in the
    // World yet, so `music_q` misses it. Track it so two `play_music` calls in
    // one frame (menu boots, then AUTOBOOT switches scenes) can't stack tracks.
    let mut music_spawned_this_drain: Option<Entity> = None;
    // Particles spawned by earlier commands in THIS drain aren't in the World
    // yet; count them so a burst of emits still respects PARTICLE_CAP.
    let mut emitted_this_frame: usize = 0;
    let (
        ref mut current_music,
        ref mut volumes,
        ref music_q,
        ref voice_q,
        ref mut music_sinks,
        ref mut voice_sinks,
    ) = audio;
    for command in vm.drain() {
        match command {
            LuaCommand::Spawn {
                id,
                x,
                y,
                w,
                h,
                color: (r, g, b, a),
            } => {
                let z = 0.001 * id as f32;
                let entity = commands
                    .spawn((
                        Sprite::from_color(Color::srgba(r, g, b, a), Vec2::new(w, h)),
                        Transform::from_xyz(x, y, z),
                    ))
                    .id();
                registry.0.insert(id, entity);
            }
            // NOTE on the `else` branches below: entities spawned earlier in
            // THIS drain don't exist in the World yet (Commands apply after the
            // system), so the Query path misses them and the mutation would be
            // silently dropped — a same-frame "spawn then tint/rotate" is the
            // most natural thing for a script to write (the Pony Parade board
            // shipped white because of exactly this). The fallback queues the
            // mutation through Commands, which preserves ordering after Spawn.
            LuaCommand::MoveTo { id, x, y } => {
                if let Some(&entity) = registry.0.get(&id) {
                    if let Ok(mut transform) = transforms.get_mut(entity) {
                        transform.translation.x = x;
                        transform.translation.y = y;
                    } else {
                        commands
                            .entity(entity)
                            .entry::<Transform>()
                            .and_modify(move |mut t| {
                                t.translation.x = x;
                                t.translation.y = y;
                            });
                    }
                }
            }
            LuaCommand::SetColor {
                id,
                color: (r, g, b, a),
            } => {
                if let Some(&entity) = registry.0.get(&id) {
                    if let Ok(bones) = rig_bones.get(entity) {
                        // Rig roots have no Sprite of their own: tint every bone
                        // part instead, so `set_color` recolours the whole
                        // character (ant species tinting).
                        for (bone_entity, _) in bones.0.values() {
                            let e = *bone_entity;
                            if let Ok(mut sprite) = sprites.get_mut(e) {
                                sprite.color = Color::srgba(r, g, b, a);
                            } else {
                                commands
                                    .entity(e)
                                    .entry::<Sprite>()
                                    .and_modify(move |mut s| s.color = Color::srgba(r, g, b, a));
                            }
                        }
                    } else if let Ok(mut sprite) = sprites.get_mut(entity) {
                        sprite.color = Color::srgba(r, g, b, a);
                    } else {
                        commands
                            .entity(entity)
                            .entry::<Sprite>()
                            .and_modify(move |mut s| s.color = Color::srgba(r, g, b, a));
                    }
                }
            }
            LuaCommand::SetSize { id, w, h } => {
                if let Some(&entity) = registry.0.get(&id) {
                    if let Ok(mut sprite) = sprites.get_mut(entity) {
                        sprite.custom_size = Some(Vec2::new(w, h));
                    } else {
                        commands
                            .entity(entity)
                            .entry::<Sprite>()
                            .and_modify(move |mut s| s.custom_size = Some(Vec2::new(w, h)));
                    }
                }
            }
            LuaCommand::SetRotation { id, radians } => {
                if let Some(&entity) = registry.0.get(&id) {
                    if let Ok(mut transform) = transforms.get_mut(entity) {
                        transform.rotation = Quat::from_rotation_z(radians);
                    } else {
                        commands
                            .entity(entity)
                            .entry::<Transform>()
                            .and_modify(move |mut t| t.rotation = Quat::from_rotation_z(radians));
                    }
                }
            }
            LuaCommand::Tween {
                id,
                x,
                y,
                scale,
                dur,
                ease,
                delay,
                from_scale,
            } => {
                if let Some(&entity) = registry.0.get(&id) {
                    let to_xy = match (x, y) {
                        (Some(px), Some(py)) => Some(Vec2::new(px, py)),
                        _ => None,
                    };
                    commands.entity(entity).insert(TweenAnim {
                        to_xy,
                        to_scale: scale,
                        from_scale,
                        from_xy: None,
                        from_scale_cur: 1.0,
                        t: 0.0,
                        dur: dur.max(0.001),
                        delay,
                        ease: ease_from_name(&ease),
                        started: false,
                    });
                }
            }
            LuaCommand::SetSpriteImage { id, image } => {
                if let Some(&entity) = registry.0.get(&id) {
                    let handle = tex_cache
                        .0
                        .entry(image.clone())
                        .or_insert_with(|| assets.load(format!("textures/{image}.png")))
                        .clone();
                    if let Ok(mut sprite) = sprites.get_mut(entity) {
                        sprite.image = handle;
                    } else {
                        commands
                            .entity(entity)
                            .entry::<Sprite>()
                            .and_modify(move |mut s| s.image = handle);
                    }
                }
            }
            LuaCommand::SpawnText {
                id,
                x,
                y,
                size,
                color: (r, g, b, a),
                text,
            } => {
                let z = 100.0 + 0.001 * id as f32;
                let entity = commands
                    .spawn((
                        Text2d::new(text),
                        TextFont {
                            font: FontSource::Handle(assets.load("fonts/game.ttf")),
                            font_size: FontSize::Px(size),
                            ..default()
                        },
                        TextColor(Color::srgba(r, g, b, a)),
                        Anchor::CENTER,
                        Transform::from_xyz(x, y, z),
                    ))
                    .id();
                registry.0.insert(id, entity);
            }
            LuaCommand::SpawnPanel {
                id,
                x,
                y,
                w,
                h,
                image,
                border,
            } => {
                // 9-slice panel: corners stay at native crispness while the
                // centre/edges stretch — trays and bars keep sharp rounded
                // corners at ANY size (a plain stretched sprite blurs them).
                let z = 0.001 * id as f32;
                let handle = tex_cache
                    .0
                    .entry(image.clone())
                    .or_insert_with(|| assets.load(format!("textures/{image}.png")))
                    .clone();
                let entity = commands
                    .spawn((
                        Sprite {
                            image: handle,
                            custom_size: Some(Vec2::new(w, h)),
                            image_mode: SpriteImageMode::Sliced(TextureSlicer {
                                border: BorderRect::all(border),
                                ..default()
                            }),
                            ..default()
                        },
                        Transform::from_xyz(x, y, z),
                    ))
                    .id();
                registry.0.insert(id, entity);
            }
            LuaCommand::SetLayer { id, z } => {
                // explicit render tier: z = layer + the id epsilon (keeps the
                // relative order of same-layer sprites stable). Sprites sit at
                // 0.001*id, text at 100+; e.g. a vignette overlay at 90 covers
                // every game sprite but leaves the HUD text crisp.
                if let Some(&entity) = registry.0.get(&id) {
                    let zz = z + 0.001;
                    if let Ok(mut transform) = transforms.get_mut(entity) {
                        transform.translation.z = zz;
                    } else {
                        commands
                            .entity(entity)
                            .entry::<Transform>()
                            .and_modify(move |mut t| t.translation.z = zz);
                    }
                }
            }
            LuaCommand::SpawnSprite {
                id,
                x,
                y,
                w,
                h,
                image,
            } => {
                let z = 0.001 * id as f32;
                let handle = tex_cache
                    .0
                    .entry(image.clone())
                    .or_insert_with(|| assets.load(format!("textures/{image}.png")))
                    .clone();
                let entity = commands
                    .spawn((
                        Sprite {
                            image: handle,
                            custom_size: Some(Vec2::new(w, h)),
                            ..default()
                        },
                        Transform::from_xyz(x, y, z),
                    ))
                    .id();
                registry.0.insert(id, entity);
            }
            LuaCommand::SpawnSheet {
                id,
                x,
                y,
                w,
                h,
                image,
                fw,
                fh,
                cols,
                frames,
            } => {
                let z = 0.001 * id as f32;
                let handle = tex_cache
                    .0
                    .entry(image.clone())
                    .or_insert_with(|| assets.load(format!("textures/{image}.png")))
                    .clone();
                let info = SheetInfo { fw, fh, cols, frames };
                let (x0, y0, x1, y1) = frame_rect(fw, fh, cols, frames, 0);
                let entity = commands
                    .spawn((
                        Sprite {
                            image: handle,
                            custom_size: Some(Vec2::new(w, h)),
                            rect: Some(Rect::new(x0, y0, x1, y1)),
                            ..default()
                        },
                        Transform::from_xyz(x, y, z),
                    ))
                    .id();
                registry.0.insert(id, entity);
                sheet_registry.0.insert(id, info);
            }
            LuaCommand::SetFrame { id, frame } => {
                if let (Some(&entity), Some(info)) =
                    (registry.0.get(&id), sheet_registry.0.get(&id).copied())
                {
                    let (x0, y0, x1, y1) = frame_rect(info.fw, info.fh, info.cols, info.frames, frame);
                    let rect = Some(Rect::new(x0, y0, x1, y1));
                    if let Ok(mut sprite) = sprites.get_mut(entity) {
                        sprite.rect = rect;
                    } else {
                        commands
                            .entity(entity)
                            .entry::<Sprite>()
                            .and_modify(move |mut s| s.rect = rect);
                    }
                }
            }
            LuaCommand::Tilemap {
                id,
                x,
                y,
                cols,
                rows,
                tw,
                th,
                image,
                tcols,
                tframes,
            } => {
                let handle = tex_cache
                    .0
                    .entry(image.clone())
                    .or_insert_with(|| assets.load(format!("textures/{image}.png")))
                    .clone();
                let z = 0.001 * id as f32;
                let root = commands.spawn(Transform::from_xyz(x, y, z)).id();
                // Cells sit at grid offsets relative to the root (map center)
                // and start invisible; set_tile reveals them with a frame rect.
                let (x0, y0, x1, y1) = frame_rect(tw, th, tcols, tframes, 0);
                let mut cells = Vec::with_capacity((cols * rows) as usize);
                for row in 0..rows {
                    for col in 0..cols {
                        let cx = (col as f32 - (cols as f32 - 1.0) * 0.5) * tw;
                        let cy = ((rows as f32 - 1.0) * 0.5 - row as f32) * th;
                        let cell = commands
                            .spawn((
                                Sprite {
                                    image: handle.clone(),
                                    custom_size: Some(Vec2::new(tw, th)),
                                    rect: Some(Rect::new(x0, y0, x1, y1)),
                                    color: Color::srgba(1.0, 1.0, 1.0, 0.0),
                                    ..default()
                                },
                                Transform::from_xyz(cx, cy, 0.0),
                                ChildOf(root),
                            ))
                            .id();
                        cells.push(cell);
                    }
                }
                registry.0.insert(id, root);
                tilemaps.0.insert(
                    id,
                    TilemapInfo { cols, rows, tw, th, tcols, tframes, cells },
                );
            }
            LuaCommand::SetTile { id, tx, ty, index } => {
                if let Some(info) = tilemaps.0.get(&id) {
                    if let Some(slot) = tile_slot(info.cols, info.rows, tx, ty) {
                        let Some(&cell) = info.cells.get(slot) else { continue };
                        // index -1 (or any negative) hides the cell; otherwise
                        // show the clamped tileset frame at full alpha.
                        let (rect, alpha) = if index < 0 {
                            (None, 0.0)
                        } else {
                            let (x0, y0, x1, y1) =
                                frame_rect(info.tw, info.th, info.tcols, info.tframes, index);
                            (Some(Rect::new(x0, y0, x1, y1)), 1.0)
                        };
                        if let Ok(mut sprite) = sprites.get_mut(cell) {
                            if let Some(r) = rect {
                                sprite.rect = Some(r);
                            }
                            sprite.color = Color::srgba(1.0, 1.0, 1.0, alpha);
                        } else {
                            commands.entity(cell).entry::<Sprite>().and_modify(
                                move |mut s| {
                                    if let Some(r) = rect {
                                        s.rect = Some(r);
                                    }
                                    s.color = Color::srgba(1.0, 1.0, 1.0, alpha);
                                },
                            );
                        }
                    }
                }
            }
            LuaCommand::Rock3d { id, x, y, z, size } => {
                // Lazy bootstrap on the very first rock: spawn the 3D camera +
                // lights and flip the 2D camera to composite ON TOP of them
                // (render order 1, no clear — sprites/text overlay the scene).
                // The opaque aurora quad is hidden by `toggle_2d_backdrop` in
                // rock3d.rs, which also restores it when the last rock dies.
                if !rocks.booted {
                    rocks.booted = true;
                    spawn_3d_rig(
                        &mut commands,
                        &mut *meshes,
                        &mut *std_materials,
                        &mut *space_materials,
                        &assets,
                    );
                    for mut cam in cameras_2d.iter_mut() {
                        cam.order = 1;
                        cam.clear_color = ClearColorConfig::None;
                    }
                }
                // One shared unit-diameter mesh (built once)…
                let mesh = rocks
                    .mesh
                    .get_or_insert_with(|| meshes.add(rock_mesh()))
                    .clone();
                // …but a per-entity material, so color3d tints independently.
                // Fully matte (rock, not plastic) so the flat facets read as
                // stone; a touch of reflectance keeps lit faces from going flat.
                let material = std_materials.add(StandardMaterial {
                    base_color: Color::srgb(0.42, 0.42, 0.46),
                    perceptual_roughness: 1.0,
                    metallic: 0.0,
                    reflectance: 0.18,
                    ..default()
                });
                let entity = commands
                    .spawn((
                        Mesh3d(mesh),
                        MeshMaterial3d(material.clone()),
                        Transform::from_xyz(x, y, z).with_scale(Vec3::splat(size.max(0.001))),
                        Visibility::default(),
                    ))
                    .id();
                registry.0.insert(id, entity);
                rocks.materials.insert(id, material);
            }
            LuaCommand::Move3d { id, x, y, z } => {
                if let Some(&entity) = registry.0.get(&id) {
                    if let Ok(mut transform) = transforms.get_mut(entity) {
                        transform.translation = Vec3::new(x, y, z);
                    } else {
                        commands
                            .entity(entity)
                            .entry::<Transform>()
                            .and_modify(move |mut t| t.translation = Vec3::new(x, y, z));
                    }
                }
            }
            LuaCommand::Rot3d { id, rx, ry, rz } => {
                let rotation = Quat::from_euler(EulerRot::XYZ, rx, ry, rz);
                if let Some(&entity) = registry.0.get(&id) {
                    if let Ok(mut transform) = transforms.get_mut(entity) {
                        transform.rotation = rotation;
                    } else {
                        commands
                            .entity(entity)
                            .entry::<Transform>()
                            .and_modify(move |mut t| t.rotation = rotation);
                    }
                }
            }
            LuaCommand::Color3d { id, color: (r, g, b) } => {
                // Mutates the rock's OWN material (created in Rock3d), so this
                // never affects other rocks. Assets::add is synchronous, so a
                // same-frame "rock3d then color3d" works.
                if let Some(handle) = rocks.materials.get(&id) {
                    // `get_mut` returns a change-detection guard — bind it mut.
                    if let Some(mut material) = std_materials.get_mut(handle) {
                        material.base_color = Color::srgb(r, g, b);
                    }
                }
            }
            LuaCommand::Scale3d { id, s } => {
                let scale = Vec3::splat(s.max(0.001));
                if let Some(&entity) = registry.0.get(&id) {
                    if let Ok(mut transform) = transforms.get_mut(entity) {
                        transform.scale = scale;
                    } else {
                        commands
                            .entity(entity)
                            .entry::<Transform>()
                            .and_modify(move |mut t| t.scale = scale);
                    }
                }
            }
            LuaCommand::SpaceMode(on) => {
                // Explicit request for the deep-space backdrop, independent of any
                // rock being on screen. Boots the same 3D rig (camera + lights +
                // space-shader plane) the first rock would, and flips the 2D camera
                // to composite on top. `toggle_2d_backdrop` reads `rocks.space` and
                // keeps the aurora hidden / 3D camera live while it's set, so the
                // starfield shows on menus and result cards, not just active play.
                rocks.space = on;
                if on && !rocks.booted {
                    rocks.booted = true;
                    spawn_3d_rig(
                        &mut commands,
                        &mut *meshes,
                        &mut *std_materials,
                        &mut *space_materials,
                        &assets,
                    );
                    for mut cam in cameras_2d.iter_mut() {
                        cam.order = 1;
                        cam.clear_color = ClearColorConfig::None;
                    }
                }
            }
            LuaCommand::SpawnRig { id, x, y, name, scale } => {
                let handle = assets.load::<RigAsset>(format!("rigs/{name}.rig"));
                let z = 0.001 * id as f32;
                let root = commands
                    .spawn((
                        Transform::from_xyz(x, y, z).with_scale(Vec3::splat(scale.max(0.01))),
                        Visibility::default(),
                        RigRoot { handle, built: false },
                        RigState::default(),
                    ))
                    .id();
                registry.0.insert(id, root);
            }
            LuaCommand::PlayAnim { id, clip } => {
                if let Some(&entity) = registry.0.get(&id) {
                    // RigState is data the animate system reads, so this works
                    // even before the rig asset finishes loading; same-frame
                    // spawn_rig + play_anim goes through the Commands fallback.
                    if let Ok(mut state) = rig_states.get_mut(entity) {
                        state.clip = Some(clip);
                        state.t = 0.0;
                    } else {
                        commands.entity(entity).entry::<RigState>().and_modify(
                            move |mut s| {
                                s.clip = Some(clip);
                                s.t = 0.0;
                            },
                        );
                    }
                }
            }
            LuaCommand::SetBone { id, bone, pose } => {
                if let Some(&entity) = registry.0.get(&id) {
                    let apply = move |state: &mut RigState| match pose {
                        Some((rot, x, y)) => {
                            state.overrides.insert(bone.clone(), BonePose { rot, x, y });
                        }
                        None => {
                            state.overrides.remove(&bone);
                        }
                    };
                    if let Ok(mut state) = rig_states.get_mut(entity) {
                        apply(&mut state);
                    } else {
                        commands
                            .entity(entity)
                            .entry::<RigState>()
                            .and_modify(move |mut s| apply(&mut s));
                    }
                }
            }
            LuaCommand::Despawn { id } => {
                if let Some(entity) = registry.0.remove(&id) {
                    commands.entity(entity).despawn();
                }
                sheet_registry.0.remove(&id);
                tilemaps.0.remove(&id);
                // Dropping the handle releases the rock's material; when the
                // map empties, rock3d.rs restores the 2D backdrop.
                rocks.materials.remove(&id);
            }
            LuaCommand::Emit { preset, x, y, count } => {
                let params = preset_params(&preset);
                // Cap check counts particles alive in the World plus the ones
                // queued by earlier Emits this frame (tracked via the counter).
                let alive = particles_alive.iter().count() + emitted_this_frame;
                let n = emit_count_allowed(alive, count, PARTICLE_CAP);
                emitted_this_frame += n as usize;
                for _ in 0..n {
                    let angle = if params.up_fan {
                        // Upward fan: 0.15π..0.85π (mostly up, a little sideways).
                        std::f32::consts::PI * (0.15 + 0.7 * lcg(&mut emit_seed))
                    } else {
                        std::f32::consts::TAU * lcg(&mut emit_seed)
                    };
                    let speed =
                        params.speed.0 + (params.speed.1 - params.speed.0) * lcg(&mut emit_seed);
                    let rgb = params.colors
                        [(lcg(&mut emit_seed) * params.colors.len() as f32) as usize
                            % params.colors.len()];
                    let ttl = params.ttl * (0.7 + 0.6 * lcg(&mut emit_seed));
                    commands.spawn((
                        Sprite::from_color(
                            Color::srgba(rgb.0, rgb.1, rgb.2, 1.0),
                            Vec2::splat(params.size),
                        ),
                        Transform::from_xyz(x, y, 50.0),
                        Particle {
                            vel: Vec2::new(angle.cos(), angle.sin()) * speed,
                            gravity: params.gravity,
                            ttl,
                            life: ttl,
                            rgb,
                        },
                    ));
                }
            }
            LuaCommand::SetText(text) => {
                if let Some(hud) = &hud {
                    if let Ok(mut hud_text) = texts.get_mut(hud.0) {
                        hud_text.0 = text;
                    }
                }
            }
            LuaCommand::Shake(intensity) => {
                shake.trauma = (shake.trauma + intensity).clamp(0.0, 1.0);
            }
            LuaCommand::Zoom(intensity) => {
                shake.zoom = shake.zoom.max(intensity.clamp(0.0, 1.0));
            }
            LuaCommand::Cam { x, y, zoom } => {
                cam_rig.x = x;
                cam_rig.y = y;
                cam_rig.zoom = cam_zoom_clamp(zoom);
            }
            LuaCommand::SetBgTheme(theme, space) => {
                bg_theme.target = theme.clamp(0.0, 1.0);
                bg_theme.space_target = space.clamp(0.0, 1.0);
            }
            LuaCommand::PlaySound(name) => {
                // SFX channel: overlap is fine, but collapse duplicates of the
                // same sound within one frame (e.g. many bounces in a tick).
                if sfx_this_frame.insert(name.clone()) {
                    let handle = assets.load::<AudioSource>(format!("audio/{name}.wav"));
                    let settings = PlaybackSettings {
                        volume: Volume::Linear(volumes.sfx),
                        ..PlaybackSettings::DESPAWN
                    };
                    commands.spawn((AudioPlayer::new(handle), settings));
                }
            }
            LuaCommand::PlayMusic(name) => {
                // Music channel: one looping track. If the same track is already
                // playing, do nothing (re-requesting it on scene re-entry must not
                // restart or double it). Otherwise stop the old track and start new.
                let same = current_music.0.as_deref() == Some(name.as_str());
                let already = !music_q.is_empty() || music_spawned_this_drain.is_some();
                if !(same && already) {
                    for e in music_q.iter() {
                        commands.entity(e).despawn();
                    }
                    // also stop a track spawned earlier in THIS drain (not yet
                    // visible to music_q) — otherwise two same-frame play_music
                    // calls stack two looping tracks.
                    if let Some(e) = music_spawned_this_drain.take() {
                        commands.entity(e).despawn();
                    }
                    let handle = assets.load::<AudioSource>(format!("audio/{name}.wav"));
                    let settings = PlaybackSettings {
                        volume: Volume::Linear(volumes.music),
                        ..PlaybackSettings::LOOP
                    };
                    let id = commands
                        .spawn((AudioPlayer::new(handle), settings, MusicSound))
                        .id();
                    music_spawned_this_drain = Some(id);
                    current_music.0 = Some(name);
                }
            }
            LuaCommand::PlayVoice(name) => {
                // Voice channel: single one-shot. Stop any voice still playing so
                // dialogue lines never talk over one another, then start this one.
                for e in voice_q.iter() {
                    commands.entity(e).despawn();
                }
                let handle = assets.load::<AudioSource>(format!("audio/{name}.wav"));
                let settings = PlaybackSettings {
                    volume: Volume::Linear(volumes.voice),
                    ..PlaybackSettings::DESPAWN
                };
                commands.spawn((AudioPlayer::new(handle), settings, VoiceSound));
            }
            LuaCommand::StopVoice => {
                for e in voice_q.iter() {
                    commands.entity(e).despawn();
                }
            }
            LuaCommand::StopMusic => {
                for e in music_q.iter() {
                    commands.entity(e).despawn();
                }
                current_music.0 = None;
            }
            LuaCommand::SetVolume { channel, volume } => {
                let v = volume_clamp(volume);
                match channel.as_str() {
                    // SFX are one-shots: the new volume applies from the next
                    // shot on (a burst mid-flight keeps its launch volume).
                    "sfx" => volumes.sfx = v,
                    "music" => {
                        volumes.music = v;
                        for mut sink in music_sinks.iter_mut() {
                            sink.set_volume(Volume::Linear(v));
                        }
                    }
                    "voice" => {
                        volumes.voice = v;
                        for mut sink in voice_sinks.iter_mut() {
                            sink.set_volume(Volume::Linear(v));
                        }
                    }
                    other => warn!("game.set_volume: unknown channel {other:?}"),
                }
            }
            LuaCommand::Haptic(style) => {
                trigger_haptic(style);
            }
            LuaCommand::Track { event, value } => {
                track_event(&event, value);
            }
            LuaCommand::OpenUrl(url) => {
                open_url(&url);
            }
        }
    }
}

/// Bleed the screen-shake trauma toward zero each frame and offset the camera by
/// a jittering amount derived from it. At zero trauma the camera sits at origin.
fn camera_shake(
    time: Res<Time>,
    mut shake: ResMut<ScreenShake>,
    rig: Res<CameraRig>,
    mut cameras: Query<&mut Transform, With<GameCamera>>,
) {
    shake.trauma = (shake.trauma - time.delta_secs() * 1.6).max(0.0);
    let Ok(mut transform) = cameras.single_mut() else {
        return;
    };
    shake.zoom = (shake.zoom - time.delta_secs() * 2.5).max(0.0);
    // Compose: the rig is the scene's base pose, shake/punch layer on top.
    // Camera Transform.scale is inverse magnification, hence the division.
    let (x, y) = shake_offset(shake.trauma, time.elapsed_secs());
    transform.translation.x = rig.x + x;
    transform.translation.y = rig.y + y;
    transform.scale = Vec3::splat(zoom_scale(shake.zoom) / rig.zoom);
}

/// Pixel rect (min x, min y, max x, max y) of frame `i` in a sprite sheet laid
/// out row-major with `cols` frames per row. The index is CLAMPED into
/// `[0, frames-1]` — an animation driver overshooting its last frame shows the
/// last frame, never garbage texels. `cols`/`frames` are floored to at least 1.
fn frame_rect(fw: f32, fh: f32, cols: u32, frames: u32, i: i64) -> (f32, f32, f32, f32) {
    let cols = cols.max(1) as i64;
    let frames = frames.max(1) as i64;
    let i = i.clamp(0, frames - 1);
    let (col, row) = ((i % cols) as f32, (i / cols) as f32);
    (col * fw, row * fh, (col + 1.0) * fw, (row + 1.0) * fh)
}

/// Civil UTC date `(year, month, day)` from a unix timestamp — Howard
/// Hinnant's days-from-civil inverse. Pure, so the daily-challenge seed is
/// unit-testable without touching the wall clock.
fn civil_from_unix(secs: i64) -> (i32, u32, u32) {
    let days = secs.div_euclid(86400);
    let z = days + 719_468;
    let era = z.div_euclid(146_097);
    let doe = z - era * 146_097; // [0, 146096]
    let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365; // [0, 399]
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100); // [0, 365]
    let mp = (5 * doy + 2) / 153; // [0, 11]
    let d = (doy - (153 * mp + 2) / 5 + 1) as u32; // [1, 31]
    let m = if mp < 10 { mp + 3 } else { mp - 9 } as u32; // [1, 12]
    let y = yoe + era * 400 + i64::from(m <= 2);
    (y as i32, m, d)
}

/// Today's UTC date. On wasm32-unknown-unknown `SystemTime::now()` is
/// unimplemented, so the web build asks the JS clock instead.
fn utc_date_now() -> (i32, u32, u32) {
    #[cfg(not(target_arch = "wasm32"))]
    {
        let secs = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|d| d.as_secs() as i64)
            .unwrap_or(0);
        civil_from_unix(secs)
    }
    #[cfg(target_arch = "wasm32")]
    {
        civil_from_unix((js_sys::Date::now() / 1000.0) as i64)
    }
}

/// Sanitize an analytics event name: strip framing characters (tab/newline →
/// `_` so the TSV log stays line-per-event), cap the length, and give empty
/// names a stable placeholder.
fn track_sanitize(event: &str) -> String {
    let cleaned: String = event
        .trim()
        .chars()
        .map(|c| if c == '\t' || c == '\n' || c == '\r' { '_' } else { c })
        .take(64)
        .collect();
    if cleaned.is_empty() {
        "unnamed".to_string()
    } else {
        cleaned
    }
}

/// Append one analytics event to the local log (same directory as the save
/// file). Local-first: swapping in a remote endpoint later only changes this
/// sink, not the Lua API. On wasm the event goes to the console instead.
fn track_event(event: &str, value: Option<f64>) {
    let name = track_sanitize(event);
    #[cfg(not(target_arch = "wasm32"))]
    {
        let ts = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|d| d.as_secs())
            .unwrap_or(0);
        let line = match value {
            Some(v) => format!("{ts}\t{name}\t{v}\n"),
            None => format!("{ts}\t{name}\t\n"),
        };
        let path = save_file_path().with_file_name("analytics.log");
        if let Some(dir) = path.parent() {
            let _ = std::fs::create_dir_all(dir);
        }
        use std::io::Write;
        if let Ok(mut f) = std::fs::OpenOptions::new().create(true).append(true).open(&path) {
            let _ = f.write_all(line.as_bytes());
        }
    }
    #[cfg(target_arch = "wasm32")]
    info!("[track] {name} {:?}", value);
}

/// `game.open_url` gate: only plain web URLs may leave the sandbox. Anything
/// else (`javascript:`, `file:`, custom app schemes, empty strings) is refused
/// — scripts are data, and data must not get shell/scheme superpowers.
fn url_allowed(url: &str) -> bool {
    url.starts_with("http://") || url.starts_with("https://")
}

/// Open `url` in the platform browser.
/// - wasm: `window.open(url, "_blank")`; a popup blocker returns `Ok(None)`,
///   in which case we fall back to navigating the current tab.
/// - desktop: spawn the OS opener (`open` on macOS, `xdg-open` elsewhere) and
///   ignore errors beyond a log line — a missing opener must not crash a game.
/// - iOS: logged no-op for now (a UIKit `openURL:` shim is future work).
fn open_url(url: &str) {
    if !url_allowed(url) {
        warn!("game.open_url: refusing non-http(s) url {url:?}");
        return;
    }
    #[cfg(target_arch = "wasm32")]
    {
        let Some(window) = web_sys::window() else {
            warn!("game.open_url: no window object");
            return;
        };
        match window.open_with_url_and_target(url, "_blank") {
            Ok(Some(_)) => {}
            Ok(None) => {
                // Popup blocked: navigate the current tab instead.
                if let Err(e) = window.location().set_href(url) {
                    warn!("game.open_url: set_href fallback failed: {e:?}");
                }
            }
            Err(e) => warn!("game.open_url: window.open failed: {e:?}"),
        }
    }
    #[cfg(target_os = "ios")]
    {
        info!("game.open_url: {url} (no-op on iOS: UIKit shim not wired yet)");
    }
    #[cfg(all(not(target_arch = "wasm32"), not(target_os = "ios")))]
    {
        #[cfg(target_os = "macos")]
        const OPENER: &str = "open";
        #[cfg(not(target_os = "macos"))]
        const OPENER: &str = "xdg-open";
        match std::process::Command::new(OPENER).arg(url).spawn() {
            Ok(_) => info!("game.open_url: {url}"),
            Err(e) => warn!("game.open_url: failed to launch {OPENER}: {e}"),
        }
    }
}

/// Clamp a channel volume to 0..1; non-finite input falls back to full volume
/// (a wrong expression should never mute the game silently).
fn volume_clamp(v: f32) -> f32 {
    if !v.is_finite() {
        return 1.0;
    }
    v.clamp(0.0, 1.0)
}

/// Clamp a `game.cam` magnification to sane bounds; non-finite input (NaN/inf
/// from a Lua expression gone wrong) falls back to 1.0 so the camera never
/// disappears into a degenerate scale.
fn cam_zoom_clamp(zoom: f32) -> f32 {
    if !zoom.is_finite() {
        return 1.0;
    }
    zoom.clamp(0.25, 4.0)
}

/// Camera scale for a zoom punch: quadratic ease (light taps barely move it),
/// capped punch-IN so UI never leaves the screen. 0 -> exactly 1.0.
fn zoom_scale(zoom: f32) -> f32 {
    1.0 - 0.06 * zoom * zoom
}

#[cfg(test)]
mod tests {
    use super::{
        cam_zoom_clamp, civil_from_unix, decode_store, emit_count_allowed, encode_store,
        frame_rect, haptic_style, lcg, particle_alpha, preset_params, shake_offset, store_escape,
        store_unescape, tile_slot, track_sanitize, url_allowed, volume_clamp, zoom_scale,
        PARTICLE_CAP,
    };
    use std::collections::HashMap;

    #[test]
    fn civil_from_unix_known_dates() {
        assert_eq!(civil_from_unix(0), (1970, 1, 1)); // the epoch itself
        assert_eq!(civil_from_unix(946_598_400), (1999, 12, 31)); // century boundary eve
        assert_eq!(civil_from_unix(1_709_164_800), (2024, 2, 29)); // leap day
        assert_eq!(civil_from_unix(1_783_382_400), (2026, 7, 7)); // today (test authoring day)
        // any second within a day maps to that same day (23:59:59)
        assert_eq!(civil_from_unix(1_783_382_400 + 86_399), (2026, 7, 7));
        // and the next second rolls over
        assert_eq!(civil_from_unix(1_783_382_400 + 86_400), (2026, 7, 8));
    }

    #[test]
    fn store_roundtrips_awkward_strings() {
        // CJK, tabs, newlines, backslashes — nothing may break line framing.
        let cases = [
            "最高分",
            "line1\nline2",
            "tab\there",
            "back\\slash",
            "\\t not a tab",
            "",
        ];
        for case in cases {
            assert_eq!(store_unescape(&store_escape(case)), case, "case: {case:?}");
        }
    }

    #[test]
    fn store_codec_roundtrips_typed_values() {
        let mut store = HashMap::new();
        store.insert("hiscore".to_string(), "n:9001".to_string());
        store.insert("玩家名".to_string(), "s:小马\t冠军".to_string());
        store.insert("muted".to_string(), "b:true".to_string());
        let decoded = decode_store(&encode_store(&store));
        assert_eq!(decoded, store);
    }

    #[test]
    fn store_decode_skips_malformed_lines() {
        // A corrupt save (missing TAB separator) must never brick loading.
        let text = "good\ts:ok\nno-tab-in-this-line\nalso\tn:5\n";
        let decoded = decode_store(text);
        assert_eq!(decoded.len(), 2);
        assert_eq!(decoded["good"], "s:ok");
        assert_eq!(decoded["also"], "n:5");
    }

    #[test]
    fn store_survives_a_simulated_process_kill() {
        // Write the encoded store to a real file, "kill the process" (drop
        // everything), then read it back cold — the roadmap acceptance test.
        let mut store = HashMap::new();
        store.insert("hiscore".to_string(), "n:12.5".to_string());
        store.insert("seen_intro".to_string(), "b:true".to_string());
        let path = std::env::temp_dir().join("hollowlullaby_save_test.txt");
        std::fs::write(&path, encode_store(&store)).unwrap();
        let reread = decode_store(&std::fs::read_to_string(&path).unwrap());
        let _ = std::fs::remove_file(&path);
        assert_eq!(reread, store);
    }

    #[test]
    fn open_url_only_allows_web_schemes() {
        assert!(url_allowed("https://google.com"));
        assert!(url_allowed("http://example.com/path?q=1"));
        assert!(!url_allowed("javascript:alert(1)"));
        assert!(!url_allowed("file:///etc/passwd"));
        assert!(!url_allowed("ftp://host/file"));
        assert!(!url_allowed("HTTPS://UPPERCASE.SCHEME")); // strict: lowercase only
        assert!(!url_allowed(""));
    }

    #[test]
    fn haptic_kinds_map_to_styles() {
        assert_eq!(haptic_style("light"), 0);
        assert_eq!(haptic_style("medium"), 1);
        assert_eq!(haptic_style("heavy"), 2);
        assert_eq!(haptic_style("success"), 3);
        assert_eq!(haptic_style("nonsense"), 0); // unknown falls back to light
    }

    #[test]
    fn zero_trauma_means_no_camera_offset() {
        for t in 0..100 {
            let (x, y) = shake_offset(0.0, t as f32 * 0.13);
            assert_eq!((x, y), (0.0, 0.0));
        }
    }

    #[test]
    fn shake_offset_is_bounded_by_max() {
        // At full trauma the offset never exceeds MAX_OFFSET (24) on either axis.
        for i in 0..1000 {
            let t = i as f32 * 0.017;
            let (x, y) = shake_offset(1.0, t);
            assert!(x.abs() <= 24.0 + 1e-3, "x={x} out of range");
            assert!(y.abs() <= 24.0 + 1e-3, "y={y} out of range");
        }
    }

    #[test]
    fn track_names_are_sanitized() {
        assert_eq!(track_sanitize("level_won"), "level_won");
        assert_eq!(track_sanitize("  spaced  "), "spaced");
        assert_eq!(track_sanitize("tab\there\nnl"), "tab_here_nl"); // no TSV framing breaks
        assert_eq!(track_sanitize(""), "unnamed");
        assert_eq!(track_sanitize("   "), "unnamed");
        assert_eq!(track_sanitize(&"x".repeat(200)).len(), 64); // capped
    }

    #[test]
    fn tile_slot_is_row_major_and_bounds_safe() {
        // 4×3 grid: row-major slots 0..11.
        assert_eq!(tile_slot(4, 3, 0, 0), Some(0));
        assert_eq!(tile_slot(4, 3, 3, 0), Some(3));
        assert_eq!(tile_slot(4, 3, 0, 1), Some(4));
        assert_eq!(tile_slot(4, 3, 3, 2), Some(11));
        // Out of range in any direction is None — never wraps to a wrong cell.
        assert_eq!(tile_slot(4, 3, 4, 0), None);
        assert_eq!(tile_slot(4, 3, 0, 3), None);
        assert_eq!(tile_slot(4, 3, -1, 0), None);
        assert_eq!(tile_slot(4, 3, 0, -1), None);
        assert_eq!(tile_slot(0, 0, 0, 0), None); // degenerate empty grid
    }

    #[test]
    fn particle_cap_is_enforced_and_lifetime_fades() {
        // Cap: an emit may only fill the remaining headroom, never exceed it.
        assert_eq!(emit_count_allowed(0, 16, PARTICLE_CAP), 16);
        assert_eq!(emit_count_allowed(PARTICLE_CAP - 5, 16, PARTICLE_CAP), 5);
        assert_eq!(emit_count_allowed(PARTICLE_CAP, 16, PARTICLE_CAP), 0);
        assert_eq!(emit_count_allowed(PARTICLE_CAP + 99, 16, PARTICLE_CAP), 0);
        // Fade: alpha runs 1 → 0 with life and clamps outside the range.
        assert_eq!(particle_alpha(1.0), 1.0);
        assert_eq!(particle_alpha(0.0), 0.0);
        assert_eq!(particle_alpha(-0.3), 0.0);
        assert_eq!(particle_alpha(7.0), 1.0);
        // Unknown preset falls back to spark (never "no particles" on a typo).
        let fallback = preset_params("definitely-not-a-preset");
        let spark = preset_params("spark");
        assert_eq!(fallback.speed, spark.speed);
        assert_eq!(fallback.ttl, spark.ttl);
        // LCG stays in [0, 1) and is deterministic for a fixed seed.
        let mut a = 42u64;
        let mut b = 42u64;
        for _ in 0..1000 {
            let (va, vb) = (lcg(&mut a), lcg(&mut b));
            assert_eq!(va, vb);
            assert!((0.0..1.0).contains(&va));
        }
    }

    #[test]
    fn frame_rect_walks_rows_and_clamps() {
        // 3 columns of 16×24 frames, 5 frames total (2 rows, last row partial).
        assert_eq!(frame_rect(16.0, 24.0, 3, 5, 0), (0.0, 0.0, 16.0, 24.0));
        assert_eq!(frame_rect(16.0, 24.0, 3, 5, 2), (32.0, 0.0, 48.0, 24.0)); // end of row 0
        assert_eq!(frame_rect(16.0, 24.0, 3, 5, 3), (0.0, 24.0, 16.0, 48.0)); // wraps to row 1
        // Clamping: negative → frame 0, past-the-end → last frame (index 4).
        assert_eq!(frame_rect(16.0, 24.0, 3, 5, -7), frame_rect(16.0, 24.0, 3, 5, 0));
        assert_eq!(frame_rect(16.0, 24.0, 3, 5, 99), frame_rect(16.0, 24.0, 3, 5, 4));
        // Degenerate layout (0 cols / 0 frames) must not divide by zero.
        assert_eq!(frame_rect(8.0, 8.0, 0, 0, 5), (0.0, 0.0, 8.0, 8.0));
    }

    #[test]
    fn volume_is_clamped_and_survives_nan() {
        assert_eq!(volume_clamp(0.5), 0.5);
        assert_eq!(volume_clamp(-1.0), 0.0); // floor: silence, not negative gain
        assert_eq!(volume_clamp(3.0), 1.0); // ceiling: no boost past unity
        assert_eq!(volume_clamp(f32::NAN), 1.0); // bad math never silently mutes
    }

    #[test]
    fn cam_zoom_is_clamped_and_survives_nan() {
        assert_eq!(cam_zoom_clamp(1.0), 1.0);
        assert_eq!(cam_zoom_clamp(0.0), 0.25); // lower bound
        assert_eq!(cam_zoom_clamp(100.0), 4.0); // upper bound
        assert_eq!(cam_zoom_clamp(f32::NAN), 1.0); // degenerate input falls back
        assert_eq!(cam_zoom_clamp(f32::INFINITY), 1.0);
        // Composed camera scale stays positive & finite across the whole range:
        // scale = zoom_scale(punch) / rig_zoom.
        for punch in [0.0_f32, 0.5, 1.0] {
            for z in [0.25_f32, 1.0, 4.0] {
                let scale = zoom_scale(punch) / cam_zoom_clamp(z);
                assert!(scale.is_finite() && scale > 0.0, "scale={scale}");
            }
        }
    }

    #[test]
    fn zoom_scale_is_identity_at_rest_and_bounded() {
        assert_eq!(zoom_scale(0.0), 1.0);
        let z = zoom_scale(1.0);
        assert!(z < 1.0 && z >= 0.90, "full punch stays a gentle push-in: {z}");
    }
}
