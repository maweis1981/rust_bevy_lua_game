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
//!   game.move_to(id, x, y)
//!   game.set_color(id, r, g, b, a)             (recolor a sprite; enables
//!                                               flashes and fading trails)
//!   game.set_size(id, w, h)                    (resize a sprite; e.g. a paddle
//!                                               that grows/shrinks)
//!   game.set_rotation(id, radians)             (rotate a sprite about z; e.g. a
//!                                               rolling ball, a kick lunge)
//!   game.despawn(id)
//!   game.spawn_text(x, y, size, r, g, b, a, s) -> id (world-space Text2d label,
//!                                               centered at x,y; for menus/titles)
//!   game.set_text(string)                      (updates the on-screen HUD text)
//!   game.shake(intensity)                      (0..1 impulse; Rust decays a
//!                                               camera screen-shake from it)
//!   game.play_sound(name)                      (one-shot SFX: assets/audio/<name>.wav)
//!   game.play_music(name)                      (looping bg music; replaces any
//!                                               currently-playing track)
//!   game.haptic(kind)                          ("light"/"medium"/"heavy"/
//!                                               "success"; iOS only, else no-op)
//!   game.pointer() -> x, y, down               (mouse/touch in world coords;
//!                                               x,y are nil when unavailable,
//!                                               down = button/finger held)
//!   game.key(name) -> bool                     (held keys: "up"/"down"/"left"/
//!                                               "right"/"w"/"a"/"s"/"d"/"space")
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

use bevy::asset::{io::Reader, AssetLoader, LoadContext, LoadState};
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
            .init_resource::<EntityRegistry>()
            .init_resource::<ScreenShake>()
            .init_resource::<BackgroundTheme>()
            .init_resource::<MusicTrack>()
            .init_resource::<TextureCache>()
            .insert_non_send(LuaVm::new())
            .add_systems(Startup, (setup_scene, load_scripts))
            .add_systems(
                Update,
                (reload_changed_scripts, tick_lua, apply_lua, camera_shake).chain(),
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

/// Per-scene background palette selector, set from Lua via `game.set_bg_theme`.
/// `background.rs` eases the aurora shader toward this target so each mini-game
/// can tint the backdrop to match its mood (e.g. garden greens for Gem Match).
#[derive(Resource, Default)]
pub(crate) struct BackgroundTheme {
    pub(crate) target: f32,
}

/// The currently-playing looping music entity, so `game.play_music` can stop the
/// previous track before starting a new one.
#[derive(Resource, Default)]
struct MusicTrack(Option<Entity>);

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
    Despawn {
        id: u32,
    },
    SetText(String),
    Shake(f32),
    Zoom(f32),
    SetBgTheme(f32),
    PlaySound(String),
    PlayMusic(String),
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
        lua.set_app_data(Bridge::default());
        register_api(&lua).expect("failed to register Lua `game` API");
        Self {
            lua,
            has_update: false,
            has_tap: false,
        }
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

    fn set_input(
        &mut self,
        pointer: Option<(f32, f32)>,
        pointer_down: bool,
        keys: std::collections::HashSet<&'static str>,
    ) {
        if let Some(mut bridge) = self.lua.app_data_mut::<Bridge>() {
            bridge.pointer = pointer;
            bridge.pointer_down = pointer_down;
            bridge.keys = keys;
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
        "despawn",
        lua.create_function(|lua, id: u32| {
            if let Some(mut bridge) = lua.app_data_mut::<Bridge>() {
                bridge.queue.push(LuaCommand::Despawn { id });
            }
            Ok(())
        })?,
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
        "set_bg_theme",
        lua.create_function(|lua, theme: f32| {
            if let Some(mut bridge) = lua.app_data_mut::<Bridge>() {
                bridge.queue.push(LuaCommand::SetBgTheme(theme));
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
        let bridge = Rc::new(RefCell::new(Bridge::default()));
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

    fn set_input(
        &mut self,
        pointer: Option<(f32, f32)>,
        pointer_down: bool,
        keys: std::collections::HashSet<&'static str>,
    ) {
        let mut b = self.bridge.borrow_mut();
        b.pointer = pointer;
        b.pointer_down = pointer_down;
        b.keys = keys;
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
        game.set(ctx, "key", Callback::from_fn(&ctx, move |ctx, _, mut stack| {
            let name: ottavino::String = stack.consume(ctx)?;
            let held = b.borrow().keys.contains(name.to_str().unwrap_or(""));
            stack.replace(ctx, held);
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
        game.set(ctx, "despawn", Callback::from_fn(&ctx, move |ctx, _, mut stack| {
            let id: u32 = stack.consume(ctx)?;
            b.borrow_mut().queue.push(LuaCommand::Despawn { id });
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
        game.set(ctx, "set_bg_theme", Callback::from_fn(&ctx, move |ctx, _, mut stack| {
            let theme: f32 = stack.consume(ctx)?;
            b.borrow_mut().queue.push(LuaCommand::SetBgTheme(theme));
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
        game.set(ctx, "haptic", Callback::from_fn(&ctx, move |ctx, _, mut stack| {
            let kind: ottavino::String = stack.consume(ctx)?;
            let style = haptic_style(kind.to_str().unwrap_or(""));
            b.borrow_mut().queue.push(LuaCommand::Haptic(style));
            Ok(CallbackReturn::Return)
        })).unwrap();

        ctx.set_global("game", game);
    });
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
fn shake_offset(trauma: f32, t: f32) -> (f32, f32) {
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
    cameras: Query<(&Camera, &GlobalTransform)>,
) {
    let Ok(window) = windows.single() else {
        vm.update(time.delta_secs());
        return;
    };
    vm.set_screen(window.width() * 0.5, window.height() * 0.5);

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

    vm.set_input(pointer_world, pointer_down, key_snapshot(&keyboard));
    vm.update(time.delta_secs());
}

/// Apply everything Lua queued this frame.
#[allow(clippy::too_many_arguments)] // Bevy systems legitimately take many params
fn apply_lua(
    mut commands: Commands,
    mut vm: NonSendMut<LuaVm>,
    mut registry: ResMut<EntityRegistry>,
    mut transforms: Query<&mut Transform>,
    mut sprites: Query<&mut Sprite>,
    mut texts: Query<&mut Text>,
    mut shake: ResMut<ScreenShake>,
    mut bg_theme: ResMut<BackgroundTheme>,
    mut music: ResMut<MusicTrack>,
    mut tex_cache: ResMut<TextureCache>,
    assets: Res<AssetServer>,
    hud: Option<Res<Hud>>,
) {
    // Sprites spawn at increasing z so later-spawned things (ball) draw in front
    // of earlier ones (net, trail) without depending on transparent-sort order.
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
                    if let Ok(mut sprite) = sprites.get_mut(entity) {
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
            LuaCommand::Despawn { id } => {
                if let Some(entity) = registry.0.remove(&id) {
                    commands.entity(entity).despawn();
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
            LuaCommand::SetBgTheme(theme) => {
                bg_theme.target = theme.clamp(0.0, 1.0);
            }
            LuaCommand::PlaySound(name) => {
                let handle = assets.load::<AudioSource>(format!("audio/{name}.wav"));
                commands.spawn((AudioPlayer::new(handle), PlaybackSettings::DESPAWN));
            }
            LuaCommand::PlayMusic(name) => {
                if let Some(prev) = music.0.take() {
                    commands.entity(prev).despawn();
                }
                let handle = assets.load::<AudioSource>(format!("audio/{name}.wav"));
                let entity = commands
                    .spawn((AudioPlayer::new(handle), PlaybackSettings::LOOP))
                    .id();
                music.0 = Some(entity);
            }
            LuaCommand::Haptic(style) => {
                trigger_haptic(style);
            }
        }
    }
}

/// Bleed the screen-shake trauma toward zero each frame and offset the camera by
/// a jittering amount derived from it. At zero trauma the camera sits at origin.
fn camera_shake(
    time: Res<Time>,
    mut shake: ResMut<ScreenShake>,
    mut cameras: Query<&mut Transform, With<GameCamera>>,
) {
    shake.trauma = (shake.trauma - time.delta_secs() * 1.6).max(0.0);
    let Ok(mut transform) = cameras.single_mut() else {
        return;
    };
    shake.zoom = (shake.zoom - time.delta_secs() * 2.5).max(0.0);
    let (x, y) = shake_offset(shake.trauma, time.elapsed_secs());
    transform.translation.x = x;
    transform.translation.y = y;
    transform.scale = Vec3::splat(zoom_scale(shake.zoom));
}

/// Camera scale for a zoom punch: quadratic ease (light taps barely move it),
/// capped punch-IN so UI never leaves the screen. 0 -> exactly 1.0.
fn zoom_scale(zoom: f32) -> f32 {
    1.0 - 0.06 * zoom * zoom
}

#[cfg(test)]
mod tests {
    use super::{haptic_style, shake_offset, zoom_scale};

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
    fn zoom_scale_is_identity_at_rest_and_bounded() {
        assert_eq!(zoom_scale(0.0), 1.0);
        let z = zoom_scale(1.0);
        assert!(z < 1.0 && z >= 0.90, "full punch stays a gentle push-in: {z}");
    }
}
