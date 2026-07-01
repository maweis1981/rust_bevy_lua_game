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
//!   game.spawn(x, y, w, h, r, g, b) -> id      (colored sprite; rgb in 0..1)
//!   game.move_to(id, x, y)
//!   game.despawn(id)
//!   game.set_text(string)                      (updates the on-screen HUD text)
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

use bevy::asset::{io::Reader, AssetLoader, LoadContext};
use bevy::prelude::*;
use mlua::{Function, Lua};

const MAIN_SCRIPT_PATH: &str = "scripts/main.lua";

pub struct ScriptPlugin;

impl Plugin for ScriptPlugin {
    fn build(&self, app: &mut App) {
        app.init_asset::<LuaScript>()
            .init_asset_loader::<LuaScriptLoader>()
            .init_resource::<EntityRegistry>()
            .insert_non_send(LuaVm::new())
            .add_systems(Startup, (setup_scene, load_main_script))
            .add_systems(Update, (reload_changed_scripts, tick_lua, apply_lua).chain());
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

fn setup_scene(mut commands: Commands) {
    commands.spawn(Camera2d);

    let hud = commands
        .spawn((
            Text::new(""),
            TextFont {
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

#[derive(Resource)]
struct MainScript(#[allow(dead_code)] Handle<LuaScript>);

fn load_main_script(mut commands: Commands, assets: Res<AssetServer>) {
    commands.insert_resource(MainScript(assets.load(MAIN_SCRIPT_PATH)));
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
        color: (f32, f32, f32),
    },
    MoveTo {
        id: u32,
        x: f32,
        y: f32,
    },
    Despawn {
        id: u32,
    },
    SetText(String),
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

pub struct LuaVm {
    lua: Lua,
    has_update: bool,
    has_tap: bool,
}

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

    fn load(&mut self, source: &str) -> mlua::Result<()> {
        self.lua.load(source).set_name(MAIN_SCRIPT_PATH).exec()?;
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
            |lua, (x, y, w, h, r, g, b): (f32, f32, f32, f32, f32, f32, f32)| {
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
                    color: (r, g, b),
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

    lua.globals().set("game", game)?;
    Ok(())
}

// ---------------------------------------------------------------------------
// Systems
// ---------------------------------------------------------------------------

fn reload_changed_scripts(
    mut events: MessageReader<AssetEvent<LuaScript>>,
    scripts: Res<Assets<LuaScript>>,
    mut vm: NonSendMut<LuaVm>,
) {
    for event in events.read() {
        let id = match event {
            AssetEvent::Added { id } | AssetEvent::Modified { id } => *id,
            _ => continue,
        };
        if let Some(script) = scripts.get(id) {
            match vm.load(&script.source) {
                Ok(()) => info!("loaded Lua script: {MAIN_SCRIPT_PATH}"),
                Err(err) => error!("lua load error: {err}"),
            }
        }
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
    if let Ok(window) = windows.single() {
        vm.set_screen(window.width() * 0.5, window.height() * 0.5);
    }

    // Collect tap positions (window/logical pixels) from touch and mouse.
    let mut taps: Vec<Vec2> = touches.iter_just_pressed().map(|t| t.position()).collect();
    if mouse.just_pressed(MouseButton::Left) {
        if let Ok(window) = windows.single() {
            if let Some(cursor) = window.cursor_position() {
                taps.push(cursor);
            }
        }
    }

    // Current pointer (mouse cursor wins; otherwise first active touch) and
    // whether it is held. Touches imply "down"; the mouse needs its button.
    let mut pointer_px: Option<Vec2> = touches.iter().next().map(|t| t.position());
    let mut pointer_down = touches.iter().next().is_some();
    if let Ok(window) = windows.single() {
        if let Some(cursor) = window.cursor_position() {
            pointer_px = Some(cursor);
        }
    }
    if mouse.pressed(MouseButton::Left) {
        pointer_down = true;
    }

    let mut pointer_world: Option<(f32, f32)> = None;
    if let Ok((camera, cam_transform)) = cameras.single() {
        for pixel in taps {
            if let Ok(world) = camera.viewport_to_world_2d(cam_transform, pixel) {
                vm.on_tap(world.x, world.y);
            }
        }
        if let Some(pixel) = pointer_px {
            if let Ok(world) = camera.viewport_to_world_2d(cam_transform, pixel) {
                pointer_world = Some((world.x, world.y));
            }
        }
    }

    vm.set_input(pointer_world, pointer_down, key_snapshot(&keyboard));
    vm.update(time.delta_secs());
}

/// Apply everything Lua queued this frame.
fn apply_lua(
    mut commands: Commands,
    mut vm: NonSendMut<LuaVm>,
    mut registry: ResMut<EntityRegistry>,
    mut transforms: Query<&mut Transform>,
    mut texts: Query<&mut Text>,
    hud: Option<Res<Hud>>,
) {
    for command in vm.drain() {
        match command {
            LuaCommand::Spawn {
                id,
                x,
                y,
                w,
                h,
                color: (r, g, b),
            } => {
                let entity = commands
                    .spawn((
                        Sprite::from_color(Color::srgb(r, g, b), Vec2::new(w, h)),
                        Transform::from_xyz(x, y, 0.0),
                    ))
                    .id();
                registry.0.insert(id, entity);
            }
            LuaCommand::MoveTo { id, x, y } => {
                if let Some(&entity) = registry.0.get(&id) {
                    if let Ok(mut transform) = transforms.get_mut(entity) {
                        transform.translation.x = x;
                        transform.translation.y = y;
                    }
                }
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
        }
    }
}
