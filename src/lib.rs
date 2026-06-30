//! hollowlullaby — a Bevy game whose logic is driven by Lua scripts.
//!
//! This crate is the single source of truth for both the desktop binary
//! (`src/main.rs`) and the iOS app (which links the `staticlib` and calls the
//! `main_rs` C entrypoint defined at the bottom of this file).

use bevy::prelude::*;

mod script;

pub use script::ScriptPlugin;

/// Builds and runs the game. Shared by every platform.
pub fn run() {
    let mut app = App::new();

    app.add_plugins(DefaultPlugins.set(WindowPlugin {
        primary_window: Some(Window {
            title: "hollowlullaby".into(),
            // On iOS the OS controls the surface size; on desktop this is the
            // initial window size.
            resolution: (430, 932).into(),
            ..default()
        }),
        ..default()
    }))
    .add_plugins(ScriptPlugin)
    .add_systems(Startup, setup);

    app.run();
}

/// Marker for the entity whose transform Lua drives via `game.set_player_pos`.
#[derive(Component)]
pub struct Player;

fn setup(mut commands: Commands) {
    commands.spawn(Camera2d);

    // The player sprite. Its position is updated every frame from Lua.
    commands.spawn((
        Player,
        Sprite::from_color(Color::srgb(0.4, 0.7, 1.0), Vec2::splat(64.0)),
        Transform::from_xyz(0.0, 0.0, 0.0),
    ));
}

/// iOS entrypoint. The Xcode app's `main.m` declares and calls this symbol.
/// `#[no_mangle]` keeps the name stable for the C linker.
#[cfg(target_os = "ios")]
#[no_mangle]
pub extern "C" fn main_rs() {
    run();
}
