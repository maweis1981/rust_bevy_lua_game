//! CPU particle bursts (roadmap 1.1, the zero-dependency fallback route).
//!
//! `game.emit(preset, x, y[, count])` spawns a burst of small colored sprites
//! that fly, fade and despawn on their own — no per-frame Lua involvement.
//! Presets are engine data; if/when `bevy_hanabi` replaces this implementation
//! the Lua API stays identical (the command-queue architecture's whole point).
//!
//! Particles are engine-side entities: they never enter the `EntityRegistry`,
//! so scripts can't retain (or leak) handles to them, and a scene switch can't
//! orphan them — they simply live out their lifetime and vanish.

use bevy::prelude::*;

/// Hard cap on live particles across all bursts. Emits beyond the budget are
/// trimmed (oldest requests win) so a script spamming `emit` every frame can't
/// starve the frame loop on a phone.
pub const MAX_PARTICLES: usize = 512;

/// One burst particle: straight-line flight + gravity, fading out over `life`.
#[derive(Component)]
pub struct Particle {
    pub vel: Vec2,
    pub gravity: f32,
    pub age: f32,
    pub life: f32,
    pub base_color: (f32, f32, f32, f32),
}

/// Everything that differs between "spark" and "confetti": burst size, speed
/// and lifetime ranges, particle size, gravity, and a small palette cycled
/// through the burst.
pub struct ParticlePreset {
    pub count: u32,
    pub speed: (f32, f32),
    pub life: (f32, f32),
    pub size: (f32, f32),
    pub gravity: f32,
    pub palette: &'static [(f32, f32, f32)],
}

const SPARK_COLORS: &[(f32, f32, f32)] = &[(1.0, 0.9, 0.4), (1.0, 0.6, 0.2), (1.0, 1.0, 0.9)];
const DUST_COLORS: &[(f32, f32, f32)] = &[(0.6, 0.55, 0.45), (0.7, 0.65, 0.55), (0.5, 0.45, 0.4)];
const CONFETTI_COLORS: &[(f32, f32, f32)] = &[
    (1.0, 0.3, 0.4),
    (0.3, 0.8, 1.0),
    (1.0, 0.85, 0.2),
    (0.5, 1.0, 0.5),
    (0.9, 0.5, 1.0),
];
const SPLASH_COLORS: &[(f32, f32, f32)] = &[(0.4, 0.7, 1.0), (0.6, 0.85, 1.0), (0.9, 0.97, 1.0)];

/// Look up a preset by name. Unknown names fall back to `spark` so a typo in a
/// script still shows *something* instead of silently doing nothing.
pub fn preset(name: &str) -> ParticlePreset {
    match name {
        "dust" => ParticlePreset {
            count: 10,
            speed: (20.0, 70.0),
            life: (0.5, 1.1),
            size: (3.0, 7.0),
            gravity: -30.0,
            palette: DUST_COLORS,
        },
        "confetti" => ParticlePreset {
            count: 24,
            speed: (80.0, 240.0),
            life: (0.8, 1.6),
            size: (4.0, 8.0),
            gravity: -260.0,
            palette: CONFETTI_COLORS,
        },
        "splash" => ParticlePreset {
            count: 14,
            speed: (90.0, 260.0),
            life: (0.4, 0.9),
            size: (3.0, 6.0),
            gravity: -420.0,
            palette: SPLASH_COLORS,
        },
        _ => ParticlePreset {
            // "spark" and anything unknown
            count: 16,
            speed: (120.0, 320.0),
            life: (0.25, 0.6),
            size: (2.0, 5.0),
            gravity: -80.0,
            palette: SPARK_COLORS,
        },
    }
}

/// Tiny deterministic LCG so bursts look varied without pulling in a rand
/// crate (and without wall-clock seeding, which headless tests can't control).
#[derive(Resource)]
pub struct ParticleRng(pub u32);

impl Default for ParticleRng {
    fn default() -> Self {
        Self(0x9E37_79B9)
    }
}

impl ParticleRng {
    /// Uniform in [0, 1).
    pub fn next_f32(&mut self) -> f32 {
        self.0 = self.0.wrapping_mul(1_664_525).wrapping_add(1_013_904_223);
        (self.0 >> 8) as f32 / (1 << 24) as f32
    }

    fn range(&mut self, (lo, hi): (f32, f32)) -> f32 {
        lo + (hi - lo) * self.next_f32()
    }
}

/// How many of `requested` particles may spawn given `active` live ones.
pub fn emit_budget(active: usize, requested: u32, cap: usize) -> u32 {
    cap.saturating_sub(active).min(requested as usize) as u32
}

/// Position/velocity integration for one step (gravity is a downward accel).
pub fn particle_step(pos: Vec2, vel: Vec2, gravity: f32, dt: f32) -> (Vec2, Vec2) {
    let vel = Vec2::new(vel.x, vel.y + gravity * dt);
    (pos + vel * dt, vel)
}

/// Alpha over a particle's lifetime: starts at the base alpha, fades linearly
/// to zero at end of life. Monotonically non-increasing.
pub fn particle_alpha(base: f32, age: f32, life: f32) -> f32 {
    if life <= 0.0 {
        return 0.0;
    }
    (base * (1.0 - age / life)).max(0.0)
}

/// Spawn one burst at (x, y). Called by `apply_lua` when it drains an
/// `Emit` command; `active` is the current live-particle count for budgeting.
pub fn spawn_burst(
    commands: &mut Commands,
    rng: &mut ParticleRng,
    active: usize,
    name: &str,
    x: f32,
    y: f32,
    count_override: Option<u32>,
) {
    let p = preset(name);
    let count = emit_budget(active, count_override.unwrap_or(p.count), MAX_PARTICLES);
    for i in 0..count {
        let angle = std::f32::consts::TAU * rng.next_f32();
        let speed = rng.range(p.speed);
        let life = rng.range(p.life);
        let size = rng.range(p.size);
        let (r, g, b) = p.palette[i as usize % p.palette.len()];
        commands.spawn((
            Sprite::from_color(Color::srgba(r, g, b, 1.0), Vec2::splat(size)),
            // z = 50: above gameplay sprites (fractional z), below text (100+).
            Transform::from_xyz(x, y, 50.0),
            Particle {
                vel: Vec2::new(angle.cos(), angle.sin()) * speed,
                gravity: p.gravity,
                age: 0.0,
                life,
                base_color: (r, g, b, 1.0),
            },
        ));
    }
}

/// Fly, fade, die. Runs after `apply_lua` so a particle emitted this frame
/// renders at its birth position before its first step.
pub fn tick_particles(
    time: Res<Time>,
    mut commands: Commands,
    mut particles: Query<(Entity, &mut Particle, &mut Transform, &mut Sprite)>,
) {
    let dt = time.delta_secs().min(0.1); // a hitch shouldn't teleport particles
    for (entity, mut particle, mut transform, mut sprite) in particles.iter_mut() {
        particle.age += dt;
        if particle.age >= particle.life {
            commands.entity(entity).despawn();
            continue;
        }
        let (pos, vel) = particle_step(
            transform.translation.truncate(),
            particle.vel,
            particle.gravity,
            dt,
        );
        particle.vel = vel;
        transform.translation.x = pos.x;
        transform.translation.y = pos.y;
        let (r, g, b, a) = particle.base_color;
        sprite.color = Color::srgba(r, g, b, particle_alpha(a, particle.age, particle.life));
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn budget_caps_total_particles() {
        assert_eq!(emit_budget(0, 16, 512), 16, "plenty of room: full burst");
        assert_eq!(emit_budget(500, 16, 512), 12, "partial room: trimmed");
        assert_eq!(emit_budget(512, 16, 512), 0, "at cap: nothing spawns");
        assert_eq!(emit_budget(9999, 16, 512), 0, "over cap can't underflow");
    }

    #[test]
    fn alpha_fades_monotonically_to_zero() {
        let life = 0.8;
        let mut last = f32::INFINITY;
        for i in 0..=20 {
            let age = life * i as f32 / 20.0;
            let a = particle_alpha(1.0, age, life);
            assert!(a <= last, "alpha must never increase");
            assert!((0.0..=1.0).contains(&a));
            last = a;
        }
        assert_eq!(particle_alpha(1.0, life, life), 0.0, "gone at end of life");
        assert_eq!(particle_alpha(1.0, 0.1, 0.0), 0.0, "zero life is invisible");
    }

    #[test]
    fn step_integrates_gravity_downward() {
        // Semi-implicit Euler: gravity hits the velocity first, then the move.
        let (pos, vel) = particle_step(Vec2::ZERO, Vec2::new(10.0, 100.0), -400.0, 0.1);
        assert_eq!(vel.x, 10.0, "no horizontal force");
        assert_eq!(vel.y, 60.0, "gravity pulls the velocity down");
        assert_eq!(pos, Vec2::new(1.0, 6.0), "moves with the post-gravity velocity");
        // Integrated long enough, the particle falls: after 2s at -400 the
        // velocity is deeply negative and the arc has come back down.
        let mut p = Vec2::ZERO;
        let mut v = Vec2::new(10.0, 100.0);
        for _ in 0..120 {
            (p, v) = particle_step(p, v, -400.0, 1.0 / 60.0);
        }
        assert!(v.y < 0.0 && p.y < 0.0, "the arc comes back down: v={v:?} p={p:?}");
    }

    #[test]
    fn unknown_preset_falls_back_to_spark() {
        let unknown = preset("definitely-not-a-preset");
        let spark = preset("spark");
        assert_eq!(unknown.count, spark.count);
        assert_eq!(unknown.palette, spark.palette);
    }

    #[test]
    fn rng_is_deterministic_and_in_range() {
        let mut a = ParticleRng::default();
        let mut b = ParticleRng::default();
        for _ in 0..1000 {
            let v = a.next_f32();
            assert_eq!(v, b.next_f32(), "same seed, same sequence");
            assert!((0.0..1.0).contains(&v));
        }
    }
}
