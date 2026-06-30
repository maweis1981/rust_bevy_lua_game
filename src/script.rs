//! Lua scripting layer.
//!
//! Design: Lua never touches the Bevy `World` directly (that would fight the
//! borrow checker and require the VM to be `Send + Sync`). Instead, Lua-callable
//! functions push *intents* onto a command queue stored in the VM's app-data.
//! Rust systems run the Lua callbacks, then drain the queue and apply each
//! command to the ECS. The VM is a `NonSend` resource because `mlua::Lua` is
//! single-threaded.
//!
//! Lua-facing API (global table `game`):
//!   game.log(message)                         -> print to the Bevy log
//!   game.set_player_pos(x, y)                  -> move the Player sprite
//!   game.spawn_box(x, y, w, h, r, g, b)        -> spawn a colored sprite
//!
//! Script lifecycle callbacks (optional globals in the script):
//!   function on_start()      -- called once when the script (re)loads
//!   function on_update(dt)   -- called every frame, dt = seconds since last frame

use bevy::asset::{io::Reader, AssetLoader, LoadContext};
use bevy::prelude::*;
use mlua::{Function, Lua};

use crate::Player;

/// Where the main game script lives, relative to the `assets/` folder.
const MAIN_SCRIPT_PATH: &str = "scripts/main.lua";

pub struct ScriptPlugin;

impl Plugin for ScriptPlugin {
    fn build(&self, app: &mut App) {
        app.init_asset::<LuaScript>()
            .init_asset_loader::<LuaScriptLoader>()
            .insert_non_send(LuaVm::new())
            .add_systems(Startup, load_main_script)
            .add_systems(Update, (reload_changed_scripts, run_lua).chain());
    }
}

// ---------------------------------------------------------------------------
// Lua source as a Bevy asset (gives hot-reload on desktop, bundle-loading on iOS)
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

/// Keeps the script handle alive so the asset stays loaded (and watched).
#[derive(Resource)]
struct MainScript(#[allow(dead_code)] Handle<LuaScript>);

fn load_main_script(mut commands: Commands, assets: Res<AssetServer>) {
    commands.insert_resource(MainScript(assets.load(MAIN_SCRIPT_PATH)));
}

// ---------------------------------------------------------------------------
// The command queue: the only channel from Lua back into the ECS
// ---------------------------------------------------------------------------

enum LuaCommand {
    SetPlayerPos { x: f32, y: f32 },
    SpawnBox {
        x: f32,
        y: f32,
        w: f32,
        h: f32,
        color: (f32, f32, f32),
    },
}

#[derive(Default)]
struct CommandQueue(Vec<LuaCommand>);

// ---------------------------------------------------------------------------
// The VM
// ---------------------------------------------------------------------------

pub struct LuaVm {
    lua: Lua,
    has_update: bool,
}

impl LuaVm {
    fn new() -> Self {
        let lua = Lua::new();
        lua.set_app_data(CommandQueue::default());
        register_api(&lua).expect("failed to register Lua `game` API");
        Self {
            lua,
            has_update: false,
        }
    }

    /// (Re)load a script: execute its chunk to define globals, then call
    /// `on_start` if present. Cached `on_update` presence is refreshed.
    fn load(&mut self, source: &str) -> mlua::Result<()> {
        self.lua.load(source).set_name(MAIN_SCRIPT_PATH).exec()?;
        let globals = self.lua.globals();
        self.has_update = globals.get::<Option<Function>>("on_update")?.is_some();
        if let Some(on_start) = globals.get::<Option<Function>>("on_start")? {
            on_start.call::<()>(())?;
        }
        Ok(())
    }

    /// Call `on_update(dt)` if the script defines it.
    fn update(&mut self, dt: f32) {
        if !self.has_update {
            return;
        }
        let result: mlua::Result<()> = (|| {
            let on_update: Function = self.lua.globals().get("on_update")?;
            on_update.call::<()>(dt)
        })();
        if let Err(err) = result {
            error!("lua on_update error: {err}");
        }
    }

    /// Take everything Lua queued since the last drain.
    fn drain(&mut self) -> Vec<LuaCommand> {
        match self.lua.app_data_mut::<CommandQueue>() {
            Some(mut queue) => std::mem::take(&mut queue.0),
            None => Vec::new(),
        }
    }
}

/// Install the global `game` table of host functions.
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
        "set_player_pos",
        lua.create_function(|lua, (x, y): (f32, f32)| {
            if let Some(mut q) = lua.app_data_mut::<CommandQueue>() {
                q.0.push(LuaCommand::SetPlayerPos { x, y });
            }
            Ok(())
        })?,
    )?;

    game.set(
        "spawn_box",
        lua.create_function(
            |lua, (x, y, w, h, r, g, b): (f32, f32, f32, f32, f32, f32, f32)| {
                if let Some(mut q) = lua.app_data_mut::<CommandQueue>() {
                    q.0.push(LuaCommand::SpawnBox {
                        x,
                        y,
                        w,
                        h,
                        color: (r, g, b),
                    });
                }
                Ok(())
            },
        )?,
    )?;

    lua.globals().set("game", game)?;
    Ok(())
}

// ---------------------------------------------------------------------------
// Systems
// ---------------------------------------------------------------------------

/// Re-run a script whenever its asset is first loaded or edited on disk.
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

/// Tick the script and apply whatever it queued.
fn run_lua(
    time: Res<Time>,
    mut vm: NonSendMut<LuaVm>,
    mut commands: Commands,
    mut players: Query<&mut Transform, With<Player>>,
) {
    vm.update(time.delta_secs());

    for command in vm.drain() {
        match command {
            LuaCommand::SetPlayerPos { x, y } => {
                if let Ok(mut transform) = players.single_mut() {
                    transform.translation.x = x;
                    transform.translation.y = y;
                }
            }
            LuaCommand::SpawnBox {
                x,
                y,
                w,
                h,
                color: (r, g, b),
            } => {
                commands.spawn((
                    Sprite::from_color(Color::srgb(r, g, b), Vec2::new(w, h)),
                    Transform::from_xyz(x, y, -1.0),
                ));
            }
        }
    }
}
