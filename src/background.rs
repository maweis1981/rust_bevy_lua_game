//! Animated background rendered by a custom WGSL fragment shader.
//!
//! This is the project's example of a *custom* shader (beyond Bevy's built-in
//! sprite/text shaders): a full-screen quad with a `Material2d` whose fragment
//! shader lives in `assets/shaders/background.wgsl`. A single `vec4` uniform
//! feeds it the elapsed time (and aspect ratio) each frame so it animates.
//!
//! It sits at z = -10, behind everything the game spawns.

use bevy::mesh::Mesh2d;
use bevy::prelude::*;
use bevy::render::render_resource::AsBindGroup;
use bevy::shader::ShaderRef;
use bevy::sprite_render::{Material2d, Material2dPlugin, MeshMaterial2d};

use crate::script::{BackgroundTheme, ScreenShake};

const SHADER_PATH: &str = "shaders/background.wgsl";

pub struct BackgroundPlugin;

impl Plugin for BackgroundPlugin {
    fn build(&self, app: &mut App) {
        app.add_plugins(Material2dPlugin::<BackgroundMaterial>::default())
            .add_systems(Startup, setup_background)
            .add_systems(Update, drive_background);
    }
}

/// The material bound to the background quad. `data` packs animation inputs:
/// x = time (s), y = aspect ratio, z = gameplay energy (0..1), w reserved.
#[derive(Asset, TypePath, AsBindGroup, Clone)]
struct BackgroundMaterial {
    #[uniform(0)]
    data: Vec4,
}

impl Material2d for BackgroundMaterial {
    fn fragment_shader() -> ShaderRef {
        SHADER_PATH.into()
    }
}

/// The one background material, plus a smoothed "energy" that ties the shader to
/// gameplay: it snaps up with each `ScreenShake` impulse (paddle hit, brick break,
/// food eaten, death — every game already calls `game.shake`) and eases back down,
/// so the aurora surges and brightens in sync with the action.
#[derive(Resource)]
struct BackgroundState {
    handle: Handle<BackgroundMaterial>,
    energy: f32,
    theme: f32,
    last_safe: (f32, f32, f32),
}

#[cfg(target_os = "ios")]
extern "C" {
    /// Defined in `ios/Sources/haptics.m` — tints the native view that fills the
    /// iOS safe-area strips, so they match the current scene's backdrop.
    fn hl_safe_color(r: f32, g: f32, b: f32);
}

/// Push the safe-area fill colour to the iOS layer (no-op elsewhere).
fn set_safe_color(r: f32, g: f32, b: f32) {
    #[cfg(target_os = "ios")]
    unsafe {
        hl_safe_color(r, g, b);
    }
    #[cfg(not(target_os = "ios"))]
    let _ = (r, g, b);
}

fn setup_background(
    mut commands: Commands,
    mut meshes: ResMut<Assets<Mesh>>,
    mut materials: ResMut<Assets<BackgroundMaterial>>,
) {
    // A quad large enough to cover any phone/desktop window, centered on the camera.
    let mesh = meshes.add(Rectangle::new(3000.0, 3000.0));
    let material = materials.add(BackgroundMaterial { data: Vec4::ZERO });

    commands.spawn((
        Mesh2d(mesh),
        MeshMaterial2d(material.clone()),
        Transform::from_xyz(0.0, 0.0, -10.0),
    ));
    commands.insert_resource(BackgroundState {
        handle: material,
        energy: 0.0,
        theme: 0.0,
        last_safe: (-1.0, -1.0, -1.0),
    });
}

fn drive_background(
    time: Res<Time>,
    shake: Res<ScreenShake>,
    theme: Res<BackgroundTheme>,
    mut state: ResMut<BackgroundState>,
    windows: Query<&Window>,
    mut materials: ResMut<Assets<BackgroundMaterial>>,
) {
    let dt = time.delta_secs();
    // Ease the palette toward the current scene's theme so switching games
    // cross-fades the backdrop instead of snapping.
    state.theme += (theme.target - state.theme) * (dt * 2.5).min(1.0);

    // Tint the native iOS safe-area fill to match: dark teal for the cool aurora
    // (menu / most games), grass green for the garden (Gem Match). Only pushed
    // when it moves, to avoid per-frame FFI churn.
    let th = state.theme;
    let safe = (
        0.14 + (0.42 - 0.14) * th,
        0.28 + (0.62 - 0.28) * th,
        0.32 + (0.38 - 0.32) * th,
    );
    if (safe.0 - state.last_safe.0).abs() > 0.004
        || (safe.1 - state.last_safe.1).abs() > 0.004
        || (safe.2 - state.last_safe.2).abs() > 0.004
    {
        state.last_safe = safe;
        set_safe_color(safe.0, safe.1, safe.2);
    }
    // Fast attack on impact, slower release than the camera trauma so the aurora
    // stays lit through a rally instead of only blipping on each hit.
    if shake.trauma > state.energy {
        state.energy = shake.trauma;
    } else {
        state.energy = (state.energy - dt * 1.4).max(0.0);
    }

    let handle = state.handle.clone();
    if let Some(mut material) = materials.get_mut(&handle) {
        let aspect = windows
            .single()
            .map(|w| w.width() / w.height().max(1.0))
            .unwrap_or(1.0);
        material.data = Vec4::new(time.elapsed_secs(), aspect, state.energy, state.theme);
    }
}
