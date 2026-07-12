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

/// PURE: derive sun direction, elevation and grade colour from a day phase
/// (0 = noon, 0.5 = midnight). Split out so the headless tests can drive it.
pub fn sky_sample(phase: f32) -> (Vec2, f32, Vec4) {
    let a = phase.rem_euclid(1.0) * std::f32::consts::TAU;
    let elev = 0.5 + 0.5 * a.cos(); // 1 at noon .. 0 at midnight
    // Sun swings east<->west; shadows fall opposite it and toward the viewer,
    // stretching longer (bigger downward bias) as the sun drops.
    let sun_x = a.sin();
    let down = 0.35 + 0.55 * (1.0 - elev);
    let sun_dir = Vec2::new(-sun_x * 0.85, -down).normalize_or_zero();
    // Colour grade: cool + dim at night, a warm wash at golden hour, clear by day.
    let night = ((0.25 - elev) / 0.25).clamp(0.0, 1.0);
    let golden = (1.0 - (elev - 0.32).abs() / 0.24).clamp(0.0, 1.0) * (1.0 - night);
    let (cr, cg, cb) = if golden > night {
        (1.0, 0.62, 0.32) // warm golden hour
    } else {
        (0.18, 0.27, 0.52) // cool night (kept readable, not black)
    };
    let alpha = (0.24 * night + 0.12 * golden).clamp(0.0, 0.26);
    (sun_dir, elev, Vec4::new(cr, cg, cb, alpha))
}

/// PURE: a block's shadow geometry from the sun — (offset from the block, shadow
/// size, alpha). Long+soft at low sun, short+dark at noon, gone at night.
pub fn shadow_geom(sun_dir: Vec2, sun_up: f32, size: Vec2) -> (Vec2, Vec2, f32) {
    let e = sun_up.clamp(0.0, 1.0);
    let len = size.y * (0.12 + 0.85 * (1.0 - e));
    let s = Vec2::new(size.x * (0.94 + 0.22 * (1.0 - e)), size.y * (0.5 + 0.14 * (1.0 - e)));
    (sun_dir * len, s, (0.34 * e).clamp(0.0, 0.34))
}

/// Advance the clock and derive the sun direction, elevation, and grade colour.
fn advance_sky(time: Res<Time>, mut sky: ResMut<Sky>) {
    sky.phase = (sky.phase + time.delta_secs() / sky.day_secs.max(1.0)).rem_euclid(1.0);
    let (sun_dir, elev, grade) = sky_sample(sky.phase);
    sky.sun_dir = sun_dir;
    sky.sun_up = elev;
    sky.grade = grade;
}

/// Reposition/resize/tint every shadow from the sun; reap shadows whose caster
/// has been despawned (block carried away, board rebuilt).
fn update_shadows(
    sky: Res<Sky>,
    mut commands: Commands,
    mut shadows: Query<(Entity, &ShadowFor, &mut Sprite, &mut Transform)>,
    casters: Query<(&Transform, &Sprite), Without<ShadowFor>>,
) {
    for (shadow_entity, shadow_for, mut sprite, mut xf) in &mut shadows {
        let Ok((caster_xf, caster_sprite)) = casters.get(shadow_for.0) else {
            commands.entity(shadow_entity).despawn();
            continue;
        };
        let size = caster_sprite.custom_size.unwrap_or(Vec2::splat(24.0));
        let (off, ssize, alpha) = shadow_geom(sky.sun_dir, sky.sun_up, size);
        xf.translation.x = caster_xf.translation.x + off.x;
        xf.translation.y = caster_xf.translation.y + off.y;
        xf.translation.z = caster_xf.translation.z - 0.0003; // just under its block
        sprite.custom_size = Some(ssize);
        sprite.color = Color::srgba(0.05, 0.035, 0.03, alpha);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const CELL: Vec2 = Vec2::new(30.0, 30.0);

    #[test]
    fn noon_is_bright_with_a_short_dark_shadow() {
        let (dir, up, grade) = sky_sample(0.0);
        assert!(up > 0.99, "noon = highest sun: {up}");
        assert!(grade.w < 0.02, "clear sky at noon (no overlay): {}", grade.w);
        let (off, _, a) = shadow_geom(dir, up, CELL);
        assert!(off.length() < CELL.y * 0.15, "short shadow at noon: {}", off.length());
        assert!(a > 0.30, "shadow at its darkest at noon: {a}");
    }

    #[test]
    fn midnight_is_dark_and_cool_with_no_shadow() {
        let (dir, up, grade) = sky_sample(0.5);
        assert!(up < 0.01, "midnight sun below horizon: {up}");
        assert!(grade.w > 0.20, "night darkens the scene: {}", grade.w);
        assert!(grade.z > grade.x, "night is cool (blue>red): {:?}", grade);
        let (_, _, a) = shadow_geom(dir, up, CELL);
        assert!(a < 0.001, "no cast shadow at night: {a}");
    }

    #[test]
    fn shadows_fall_away_from_the_sun_and_toward_the_viewer() {
        // first half of the day: sun to one side -> shadow to the other, always down
        let (d1, _, _) = sky_sample(0.1);
        assert!(d1.x < 0.0 && d1.y < 0.0, "shadow points away+down: {:?}", d1);
        // second half mirrors it horizontally
        let (d2, _, _) = sky_sample(0.9);
        assert!(d2.x > 0.0 && d2.y < 0.0, "mirrored shadow: {:?}", d2);
        assert!(d1.is_normalized() && d2.is_normalized(), "sun_dir is unit");
    }

    #[test]
    fn low_sun_stretches_the_shadow() {
        let noon = shadow_geom(sky_sample(0.0).0, sky_sample(0.0).1, CELL).0.length();
        let (d, u, _) = sky_sample(0.35); // sun low
        let dusk = shadow_geom(d, u, CELL).0.length();
        assert!(dusk > noon * 2.0, "shadow stretches as the sun drops: noon={noon} dusk={dusk}");
    }

    #[test]
    fn grade_alpha_stays_bounded_and_continuous() {
        let mut prev = sky_sample(0.0).2.w;
        for i in 1..=400 {
            let w = sky_sample(i as f32 / 400.0).2.w;
            assert!((0.0..=0.26).contains(&w), "grade alpha out of range: {w}");
            assert!((w - prev).abs() < 0.02, "grade alpha jumps at phase {}: {prev}->{w}", i);
            prev = w;
        }
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
