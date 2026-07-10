//! hollowlullaby — a Bevy game whose logic is driven by Lua scripts.
//!
//! This crate is the single source of truth for both the desktop binary
//! (`src/main.rs`) and the iOS app (which links the `staticlib` and calls the
//! `main_rs` C entrypoint defined at the bottom of this file).

use bevy::asset::AssetMetaCheck;
use bevy::diagnostic::{DiagnosticsStore, FrameTimeDiagnosticsPlugin};
use bevy::prelude::*;

mod background;
mod rig;
mod rock3d;
mod script;

pub use script::ScriptPlugin;

/// Builds and runs the game. Shared by every platform.
pub fn run() {
    let mut app = App::new();

    app.add_plugins(
        DefaultPlugins
            .set(WindowPlugin {
                primary_window: Some(Window {
                    title: "hollowlullaby".into(),
                    // On iOS the OS controls the surface size; on desktop this is
                    // the initial window size (portrait phone aspect for parity).
                    resolution: (430, 932).into(),
                    ..default()
                }),
                ..default()
            })
            // Nearest sampling keeps the pixel-art sprites crisp when scaled up.
            .set(ImagePlugin::default_nearest())
            // Don't probe for `<asset>.meta` sidecars: we ship none, and on the
            // web each probe is a 404 (harmless but noisy in the console).
            .set(AssetPlugin {
                meta_check: AssetMetaCheck::Never,
                ..default()
            }),
    )
    // A garden green (not black) so any strip the camera viewport doesn't cover
    // — e.g. the iOS home-indicator safe area — reads as the grassy background
    // continuing rather than a black bar.
    .insert_resource(ClearColor(Color::srgb(0.36, 0.56, 0.34)))
    .add_plugins(FrameTimeDiagnosticsPlugin::default())
    .add_plugins(background::BackgroundPlugin)
    .add_plugins(rock3d::Rock3dPlugin)
    .add_plugins(ScriptPlugin);
    // FPS overlay is dev-only; enable with FPS_OVERLAY=1 (kept off for players).
    if std::env::var("FPS_OVERLAY").is_ok() {
        app.add_systems(Startup, spawn_fps_overlay)
            .add_systems(Update, update_fps_overlay);
    }

    app.run();
}

/// On-screen FPS readout (top-right), independent of the game's HUD.
#[derive(Component)]
struct FpsText;

fn spawn_fps_overlay(mut commands: Commands, assets: Res<AssetServer>) {
    commands.spawn((
        FpsText,
        Text::new("FPS --"),
        TextFont {
            font: FontSource::Handle(assets.load("fonts/game.ttf")),
            font_size: 24.0.into(),
            ..default()
        },
        TextColor(Color::srgb(0.4, 1.0, 0.5)),
        Node {
            position_type: PositionType::Absolute,
            top: Val::Px(60.0),
            right: Val::Px(24.0),
            ..default()
        },
    ));
}

fn update_fps_overlay(
    diagnostics: Res<DiagnosticsStore>,
    time: Res<Time>,
    mut query: Query<&mut Text, With<FpsText>>,
    mut log_accum: Local<f32>,
) {
    let fps = diagnostics
        .get(&FrameTimeDiagnosticsPlugin::FPS)
        .and_then(|d| d.smoothed());

    if let Ok(mut text) = query.single_mut() {
        match fps {
            Some(fps) => text.0 = format!("FPS {fps:.0}"),
            None => text.0 = "FPS --".into(),
        }
    }

    // Log once per second so we can read frame rate off the device console.
    *log_accum += time.delta_secs();
    if *log_accum >= 1.0 {
        *log_accum = 0.0;
        if let Some(fps) = fps {
            info!("FPS: {fps:.1}");
        }
    }
}

/// iOS entrypoint. The Xcode app's `main.m` declares and calls this symbol.
/// `#[no_mangle]` keeps the name stable for the C linker.
#[cfg(target_os = "ios")]
#[no_mangle]
pub extern "C" fn main_rs() {
    run();
}
