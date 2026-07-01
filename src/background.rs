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
/// x = time (s), y = aspect ratio; z/w reserved for future use.
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

/// Handle to the one background material instance, so we can update its uniform.
#[derive(Resource)]
struct BackgroundHandle(Handle<BackgroundMaterial>);

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
    commands.insert_resource(BackgroundHandle(material));
}

fn drive_background(
    time: Res<Time>,
    handle: Res<BackgroundHandle>,
    windows: Query<&Window>,
    mut materials: ResMut<Assets<BackgroundMaterial>>,
) {
    if let Some(mut material) = materials.get_mut(&handle.0) {
        let aspect = windows
            .single()
            .map(|w| w.width() / w.height().max(1.0))
            .unwrap_or(1.0);
        material.data = Vec4::new(time.elapsed_secs(), aspect, 0.0, 0.0);
    }
}
