//! Real-time lighting + time-of-day for Lua games (roadmap: an engine light rig,
//! not baked art). A `Sky` resource advances a day/night clock; from it we derive
//! a moving sun and drive TWO real-time effects:
//!
//!   * **Dynamic block shadows** — sprites tagged `game.shadow(id)` get a
//!     companion shadow sprite the engine repositions every frame from the sun
//!     direction (long + soft at dawn/dusk, short at noon, gone at night). The
//!     shadow is *computed*, never painted into the block texture — remove the
//!     block and its shadow goes; the sun moves and every shadow swings with it.
//!   * **Day/night colour grade** — a full-screen overlay whose tint follows the
//!     clock (transparent noon, warm golden hour, cool + dim night). Only active
//!     while a scene actually casts shadows, so the menu/other games are
//!     untouched (mirrors how the 3D path gates its backdrop).
//!
//! Lua touches only `game.shadow(id)` (see `src/script.rs`); the clock, sun and
//! grade run autonomously. Animal-Crossing runs on a real clock — this is the
//! same idea, just on an accelerated in-game day so the light visibly lives.

use bevy::prelude::*;

/// The day/night clock + derived sun. `phase` 0 = local noon, 0.5 = midnight.
#[derive(Resource)]
pub struct Sky {
    /// 0..1 over one in-game day.
    pub phase: f32,
    /// Real seconds per in-game day (accelerated so the light visibly moves).
    pub day_secs: f32,
    /// Unit direction shadows fall (away from the sun, biased toward the viewer).
    pub sun_dir: Vec2,
    /// Sun elevation, 1 at noon .. 0 at night (drives shadow length + brightness).
    pub sun_up: f32,
    /// Day/night overlay colour+alpha (r, g, b, a) for the full-screen grade.
    pub grade: Vec4,
}

impl Default for Sky {
    fn default() -> Self {
        Self {
            phase: 0.10, // a warm morning, sun in the upper-left (matches the art DNA)
            day_secs: 1200.0, // a gentle 20-min day so lighting drifts, never lurches
            sun_dir: Vec2::new(-0.4, -0.92).normalize(),
            sun_up: 0.85,
            grade: Vec4::ZERO,
        }
    }
}

/// Marks a shadow-casting sprite (gates the day/night grade to shadow scenes).
/// The companion shadow is reaped via its `ShadowFor` link, so no field needed.
#[derive(Component)]
pub struct ShadowCaster;

/// On a shadow sprite: points back at the caster it tracks.
#[derive(Component)]
pub struct ShadowFor(pub Entity);

/// The single full-screen day/night grade overlay.
#[derive(Component)]
pub struct GradeOverlay;

pub struct LightingPlugin;

impl Plugin for LightingPlugin {
    fn build(&self, app: &mut App) {
        app.init_resource::<Sky>()
            .add_systems(Startup, spawn_grade)
            .add_systems(Update, (advance_sky, update_shadows, update_grade).chain());
    }
}

/// Spawn the (invisible until a scene casts shadows) full-screen grade quad.
/// One giant sprite at a high 2D layer covers the play field but sits under the
/// HUD text tier (z = 100+), so labels stay crisp.
fn spawn_grade(mut commands: Commands) {
    commands.spawn((
        Sprite::from_color(Color::NONE, Vec2::splat(8000.0)),
        Transform::from_xyz(0.0, 0.0, 60.0),
        GradeOverlay,
    ));
}

/// Advance the clock and derive the sun direction, elevation, and grade colour.
fn advance_sky(time: Res<Time>, mut sky: ResMut<Sky>) {
    sky.phase = (sky.phase + time.delta_secs() / sky.day_secs.max(1.0)).rem_euclid(1.0);
    let a = sky.phase * std::f32::consts::TAU; // 0 = noon, PI = midnight
    let elev = 0.5 + 0.5 * a.cos(); // 1 at noon .. 0 at midnight
    sky.sun_up = elev;
    // Sun swings east->west; shadows fall opposite it and toward the viewer,
    // stretching longer as the sun drops.
    let sun_x = a.sin();
    let down = 0.35 + 0.55 * (1.0 - elev);
    sky.sun_dir = Vec2::new(-sun_x * 0.85, -down).normalize_or_zero();
    // Colour grade: cool + dim at night, a warm wash at golden hour, clear by day.
    let night = ((0.25 - elev) / 0.25).clamp(0.0, 1.0);
    let golden = (1.0 - (elev - 0.32).abs() / 0.24).clamp(0.0, 1.0) * (1.0 - night);
    let (cr, cg, cb) = if golden > night {
        (1.0, 0.62, 0.32) // warm golden hour
    } else {
        (0.18, 0.27, 0.52) // cool night (kept readable, not black)
    };
    let alpha = (0.24 * night + 0.12 * golden).clamp(0.0, 0.26);
    sky.grade = Vec4::new(cr, cg, cb, alpha);
}

/// Reposition/resize/tint every shadow from the sun; reap shadows whose caster
/// has been despawned (block carried away, board rebuilt).
fn update_shadows(
    sky: Res<Sky>,
    mut commands: Commands,
    mut shadows: Query<(Entity, &ShadowFor, &mut Sprite, &mut Transform)>,
    casters: Query<(&Transform, &Sprite), Without<ShadowFor>>,
) {
    let e = sky.sun_up.clamp(0.0, 1.0);
    for (shadow_entity, shadow_for, mut sprite, mut xf) in &mut shadows {
        let Ok((caster_xf, caster_sprite)) = casters.get(shadow_for.0) else {
            commands.entity(shadow_entity).despawn();
            continue;
        };
        let size = caster_sprite.custom_size.unwrap_or(Vec2::splat(24.0));
        let len = size.y * (0.12 + 0.85 * (1.0 - e));
        let off = sky.sun_dir * len;
        xf.translation.x = caster_xf.translation.x + off.x;
        xf.translation.y = caster_xf.translation.y + off.y;
        xf.translation.z = caster_xf.translation.z - 0.0003; // just under its block
        sprite.custom_size = Some(Vec2::new(
            size.x * (0.94 + 0.22 * (1.0 - e)),
            size.y * (0.5 + 0.14 * (1.0 - e)),
        ));
        // Darker/sharper when the sun is high; fades out into the night.
        sprite.color = Color::srgba(0.05, 0.035, 0.03, (0.34 * e).clamp(0.0, 0.34));
    }
}

/// Tint the full-screen grade from the clock — but only while a scene is casting
/// shadows (i.e. the ant board is up), so menus/other games stay unaffected.
fn update_grade(
    sky: Res<Sky>,
    casters: Query<(), With<ShadowCaster>>,
    mut grade: Query<&mut Sprite, With<GradeOverlay>>,
) {
    let active = !casters.is_empty();
    for mut sprite in &mut grade {
        sprite.color = if active {
            Color::srgba(sky.grade.x, sky.grade.y, sky.grade.z, sky.grade.w)
        } else {
            Color::NONE
        };
    }
}
