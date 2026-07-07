//! True-3D render path for Lua games: procedural rock meshes + a lazily
//! bootstrapped 3D camera/light rig that composites UNDER the existing 2D layer.
//!
//! Driven from Lua through the command bridge in `src/script.rs`:
//!   game.rock3d(x, y, z, size) -> id   spawn a rock (unit-diameter mesh,
//!                                      uniformly scaled so scale == size)
//!   game.move3d(id, x, y, z)           set translation
//!   game.rot3d(id, rx, ry, rz)         set absolute rotation (Lua drives spin
//!                                      per frame, so a time-freeze in the game
//!                                      sim freezes the tumble for free)
//!   game.color3d(id, r, g, b)          tint this rock's own StandardMaterial
//!   game.scale3d(id, s)                uniform world size (s = diameter)
//!   game.despawn(id)                   works unchanged (same EntityRegistry)
//!
//! Coexistence with the 2D game (the whole point):
//!   * The 3D camera renders FIRST (`order = -1`) and clears to deep space
//!     navy; at bootstrap the 2D `GameCamera` is patched to `order = 1` with
//!     `ClearColorConfig::None`, so sprites/HUD/menus composite on top.
//!   * The animated aurora background (`src/background.rs`) is an OPAQUE
//!     full-screen 2D quad that would hide the 3D scene — while any rock is
//!     alive it is `Visibility::Hidden`, and it comes back automatically when
//!     the last rock despawns (so the menu/other games look unchanged).
//!   * The 3D camera's perspective FOV is fitted every frame so the z = 0
//!     plane maps 1:1 onto 2D world pixels — Lua keeps thinking in the same
//!     coordinates it uses for sprites.
//!
//! The rock mesh is generated ONCE (icosphere, 2 subdivisions, per-vertex
//! radial displacement from a deterministic position hash) and cached as a
//! `Handle<Mesh>`; every rock shares it. Each rock gets its OWN
//! `StandardMaterial` so `color3d` tints entities independently.

use bevy::mesh::VertexAttributeValues;
use bevy::prelude::*;
use bevy::render::render_resource::AsBindGroup;
use bevy::shader::ShaderRef;
use std::collections::HashMap;

use crate::background::BackgroundQuad;
use crate::script::{shake_offset, ScreenShake};

const SPACE_SHADER: &str = "shaders/space.wgsl";

/// Custom 3D material for the animated deep-space backdrop. `data` packs
/// (time, aspect, energy, _) and is refreshed every frame; the fragment shader
/// (`assets/shaders/space.wgsl`) draws a procedural nebula + parallax stars.
#[derive(Asset, TypePath, AsBindGroup, Clone)]
pub(crate) struct SpaceMaterial {
    #[uniform(0)]
    data: Vec4,
}

impl Material for SpaceMaterial {
    fn fragment_shader() -> ShaderRef {
        SPACE_SHADER.into()
    }
}

/// Camera distance from the z = 0 gameplay plane. Lua's depth mapping
/// (`-420 * z`) keeps rocks well inside the near/far range.
const CAM_DIST: f32 = 900.0;

/// Deep space the 3D camera clears to (behind the starfield backdrop).
const CLEAR_3D: Color = Color::srgb(0.015, 0.02, 0.05);

/// Radial displacement amplitude as a fraction of the sphere radius. Higher =
/// more jagged; with FLAT normals + few subdivisions this gives big, hard,
/// crystalline facets — a proper angular asteroid.
const ROCK_NOISE: f32 = 0.46;

/// Icosphere subdivisions for the rock. 1 = 80 chunky faces (very faceted);
/// 2 would be 320 (smoother). We want angular, so 1.
const ROCK_SUBDIV: u32 = 1;

/// The space backdrop plane sits this far behind the gameplay plane and is this
/// big — large enough to fill the view at that depth on any window.
const BACKDROP_Z: f32 = -2600.0;
const BACKDROP_SIZE: f32 = 9000.0;

pub struct Rock3dPlugin;

impl Plugin for Rock3dPlugin {
    fn build(&self, app: &mut App) {
        app.init_resource::<Rock3dState>()
            .add_plugins(MaterialPlugin::<SpaceMaterial>::default())
            .add_systems(
                Update,
                (sync_rock3d_camera, drive_space_backdrop, toggle_2d_backdrop),
            );
    }
}

/// Shared state of the 3D path. `materials` doubles as the live-rock set:
/// entries are added by `game.rock3d` and removed by `game.despawn`
/// synchronously during the command drain, so systems reading it this frame
/// agree with what Lua just did.
#[derive(Resource, Default)]
pub(crate) struct Rock3dState {
    /// The one shared unit-diameter rock mesh (built on first use).
    pub(crate) mesh: Option<Handle<Mesh>>,
    /// Per-Lua-id material — each rock owns its material so tints are per-entity.
    pub(crate) materials: HashMap<u32, Handle<StandardMaterial>>,
    /// Whether the 3D camera/light rig has been spawned (first `rock3d` call).
    pub(crate) booted: bool,
    /// A scene has explicitly requested the space backdrop (`game.space_mode(true)`),
    /// so keep the 3D camera live + aurora hidden even with no rocks on screen
    /// (menus, result cards). Cleared on `game.space_mode(false)`.
    pub(crate) space: bool,
}

/// Tags the (single) 3D camera so it can be resized/shaken/toggled.
#[derive(Component)]
pub(crate) struct Rock3dCamera;

/// Tags the starfield backdrop plane (spawned once with the rig).
#[derive(Component)]
pub(crate) struct Rock3dBackdrop;

/// Spawn the 3D rig: perspective camera at (0, 0, CAM_DIST) looking at the
/// origin (renders under the 2D camera), a strong key light + a dim cool fill,
/// a low ambient (deep shadows make the faceted rocks pop), and a big unlit
/// starfield plane far behind. Called once on the first `game.rock3d`.
pub(crate) fn spawn_3d_rig(
    commands: &mut Commands,
    meshes: &mut Assets<Mesh>,
    _materials: &mut Assets<StandardMaterial>,
    space_materials: &mut Assets<SpaceMaterial>,
    _assets: &AssetServer,
) {
    commands.spawn((
        Camera3d::default(),
        Camera {
            order: -1,
            clear_color: ClearColorConfig::Custom(CLEAR_3D),
            ..default()
        },
        // `far` must exceed CAM_DIST + the backdrop depth with margin.
        Projection::Perspective(PerspectiveProjection {
            far: 6000.0,
            ..default()
        }),
        Transform::from_xyz(0.0, 0.0, CAM_DIST).looking_at(Vec3::ZERO, Vec3::Y),
        // Very low ambient: the unlit side of a rock goes near-black, so the key
        // light alone carves out every facet — deep shadows, hard edges. Cool
        // tint reads as faint reflected starlight.
        AmbientLight {
            color: Color::srgb(0.45, 0.55, 0.9),
            brightness: 16.0,
            affects_lightmapped_meshes: true,
        },
        Rock3dCamera,
    ));
    // Key light: hard, warm-white, low-angle from the upper-left-front — a
    // grazing light rakes across every facet edge, maximizing the angular look.
    commands.spawn((
        DirectionalLight {
            illuminance: 24_000.0,
            color: Color::srgb(1.0, 0.96, 0.86),
            ..default()
        },
        Transform::from_xyz(-900.0, 620.0, 480.0).looking_at(Vec3::ZERO, Vec3::Y),
    ));
    // Cool rim from behind-right: a thin bright edge separates rocks from the
    // dark space without lifting the shadow side (keeps contrast punchy).
    commands.spawn((
        DirectionalLight {
            illuminance: 6_500.0,
            color: Color::srgb(0.45, 0.6, 1.0),
            ..default()
        },
        Transform::from_xyz(760.0, -260.0, -520.0).looking_at(Vec3::ZERO, Vec3::Y),
    ));
    // Space backdrop: a big plane far behind the rocks with the animated
    // SpaceMaterial shader (procedural nebula + parallax stars).
    let backdrop_mat = space_materials.add(SpaceMaterial { data: Vec4::ZERO });
    let backdrop_mesh = meshes.add(Rectangle::new(BACKDROP_SIZE, BACKDROP_SIZE));
    commands.spawn((
        Mesh3d(backdrop_mesh),
        MeshMaterial3d(backdrop_mat),
        Transform::from_xyz(0.0, 0.0, BACKDROP_Z),
        Rock3dBackdrop,
    ));
}

/// The vertical FOV that makes the z = 0 plane span exactly the window height
/// at `CAM_DIST` — so 2D world coordinates map 1:1 onto the gameplay plane.
fn fov_for_window_height(height: f32) -> f32 {
    2.0 * (height.max(1.0) * 0.5 / CAM_DIST).atan()
}

/// Keep the 3D camera fitted to the window (1:1 plane mapping survives
/// resizes) and mirror the 2D screen-shake jitter so both layers move as one.
fn sync_rock3d_camera(
    time: Res<Time>,
    shake: Res<ScreenShake>,
    windows: Query<&Window>,
    mut cameras: Query<(&mut Transform, &mut Projection), With<Rock3dCamera>>,
) {
    let Ok((mut transform, mut projection)) = cameras.single_mut() else {
        return;
    };
    if let Ok(window) = windows.single() {
        let fov = fov_for_window_height(window.height());
        // Only write on real change to avoid dirtying the projection per frame.
        if let Projection::Perspective(p) = projection.as_ref() {
            if (p.fov - fov).abs() > 1e-5 {
                if let Projection::Perspective(p) = &mut *projection {
                    p.fov = fov;
                }
            }
        }
    }
    let (x, y) = shake_offset(shake.trauma, time.elapsed_secs());
    transform.translation.x = x;
    transform.translation.y = y;
}

/// Feed time/aspect/energy to the animated space backdrop shader each frame.
fn drive_space_backdrop(
    time: Res<Time>,
    shake: Res<ScreenShake>,
    windows: Query<&Window>,
    mut mats: ResMut<Assets<SpaceMaterial>>,
) {
    let aspect = windows
        .single()
        .map(|w| w.width() / w.height().max(1.0))
        .unwrap_or(1.0);
    let data = Vec4::new(time.elapsed_secs(), aspect, shake.trauma, 0.0);
    for (_, m) in mats.iter_mut() {
        m.data = data;
    }
}

/// While any rock is alive, hide the opaque aurora quad (it would cover the 3D
/// scene) and keep the 3D camera active; when the last rock despawns, restore
/// the aurora and put the 3D camera to sleep — the menu and every 2D game look
/// exactly as before.
fn toggle_2d_backdrop(
    state: Res<Rock3dState>,
    mut backdrop: Query<&mut Visibility, With<BackgroundQuad>>,
    mut cameras: Query<&mut Camera, With<Rock3dCamera>>,
) {
    if !state.booted {
        return;
    }
    let live = state.space || !state.materials.is_empty();
    let desired = if live {
        Visibility::Hidden
    } else {
        Visibility::Inherited
    };
    for mut vis in &mut backdrop {
        if *vis != desired {
            *vis = desired;
        }
    }
    for mut cam in &mut cameras {
        if cam.is_active != live {
            cam.is_active = live;
        }
    }
}

/// Deterministic noise in [-1, 1] from a vertex position. Positions are
/// quantized first, so the icosphere's UV-seam duplicate vertices (identical
/// positions, different indices) displace identically — no cracks.
fn vertex_noise(p: [f32; 3]) -> f32 {
    let q = |v: f32| (v * 512.0).round() as i64;
    let h = (q(p[0]).wrapping_mul(0x9E37_79B9_7F4A_7C15u64 as i64))
        ^ (q(p[1]).wrapping_mul(0xC2B2_AE3D_27D4_EB4Fu64 as i64))
        ^ (q(p[2]).wrapping_mul(0x1656_67B1_9E37_79F9u64 as i64));
    let mut h = h as u64;
    h ^= h >> 33;
    h = h.wrapping_mul(0xFF51_AFD7_ED55_8CCD);
    h ^= h >> 33;
    ((h & 0xFF_FFFF) as f32 / 16_777_216.0) * 2.0 - 1.0
}

/// Build the shared rock mesh: a unit-DIAMETER icosphere (radius 0.5, two
/// subdivisions) with per-vertex radial displacement from `vertex_noise`, then
/// duplicated vertices + FLAT normals so every triangle shades as a hard facet
/// — a faceted, angular asteroid rather than a smooth lumpy ball. Unit diameter
/// means a rock's `Transform::scale` IS its world size.
pub(crate) fn rock_mesh() -> Mesh {
    let mut mesh = Sphere::new(0.5)
        .mesh()
        .ico(ROCK_SUBDIV)
        .expect("subdivisions are far below the icosphere vertex limit");
    if let Some(VertexAttributeValues::Float32x3(positions)) =
        mesh.attribute_mut(Mesh::ATTRIBUTE_POSITION)
    {
        for p in positions.iter_mut() {
            let s = 1.0 + ROCK_NOISE * vertex_noise(*p);
            p[0] *= s;
            p[1] *= s;
            p[2] *= s;
        }
    }
    // Split shared vertices so each face owns its own — then flat normals give
    // each triangle a single normal, i.e. crisp facet edges (the "棱角" look).
    // duplicate_vertices() drops the index buffer (mesh becomes non-indexed),
    // which is exactly what compute_flat_normals() requires.
    mesh.duplicate_vertices();
    mesh.compute_flat_normals();
    mesh
}

#[cfg(test)]
mod tests {
    use super::{fov_for_window_height, rock_mesh, vertex_noise, CAM_DIST, ROCK_NOISE};
    use bevy::mesh::{Mesh, VertexAttributeValues};

    #[test]
    fn vertex_noise_is_deterministic_and_bounded() {
        for i in 0..500 {
            let p = [
                i as f32 * 0.013 - 3.0,
                (i as f32 * 0.007).sin(),
                0.5 - i as f32 * 0.001,
            ];
            let a = vertex_noise(p);
            let b = vertex_noise(p);
            assert_eq!(a, b, "same position must displace identically");
            assert!((-1.0..=1.0).contains(&a), "noise out of range: {a}");
        }
        // Quantization: positions closer than half a quantum hash the same, so
        // seam-duplicated vertices (bit-identical) can never crack apart.
        assert_eq!(
            vertex_noise([0.25, -0.125, 0.5]),
            vertex_noise([0.25, -0.125, 0.5])
        );
    }

    #[test]
    fn rock_mesh_is_a_displaced_unit_sphere_with_normals() {
        let mesh = rock_mesh();
        let Some(VertexAttributeValues::Float32x3(positions)) =
            mesh.attribute(Mesh::ATTRIBUTE_POSITION)
        else {
            panic!("rock mesh must have float3 positions");
        };
        assert!(!positions.is_empty());
        let (mut min_r, mut max_r) = (f32::MAX, 0.0f32);
        for p in positions {
            let r = (p[0] * p[0] + p[1] * p[1] + p[2] * p[2]).sqrt();
            min_r = min_r.min(r);
            max_r = max_r.max(r);
        }
        // Radii stay inside the displacement envelope around radius 0.5
        // (unit diameter — so Transform scale == world size)…
        assert!(
            min_r >= 0.5 * (1.0 - ROCK_NOISE) - 1e-4,
            "min radius {min_r}"
        );
        assert!(
            max_r <= 0.5 * (1.0 + ROCK_NOISE) + 1e-4,
            "max radius {max_r}"
        );
        // …and the surface is actually lumpy, not a repainted sphere.
        assert!(max_r - min_r > 0.02, "displacement had no effect");
        assert!(
            mesh.attribute(Mesh::ATTRIBUTE_NORMAL).is_some(),
            "displaced mesh must carry recomputed normals"
        );
        // Flat shading duplicates vertices and drops the index buffer, so the
        // faceted rock is intentionally NON-indexed.
        assert!(
            mesh.indices().is_none(),
            "flat-normal rock must be non-indexed"
        );
    }

    #[test]
    fn fov_fits_the_window_onto_the_plane() {
        // tan(fov/2) * CAM_DIST must equal the window half-height, so 2D world
        // units map 1:1 onto the z = 0 plane.
        for h in [400.0f32, 932.0, 1200.0] {
            let fov = fov_for_window_height(h);
            let half = (fov * 0.5).tan() * CAM_DIST;
            assert!((half - h * 0.5).abs() < 1e-2, "h={h}: {half}");
        }
        // Degenerate window height must not produce a degenerate FOV.
        assert!(fov_for_window_height(0.0) > 0.0);
    }
}
