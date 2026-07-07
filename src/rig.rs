//! Cutout skeletal animation ("rig") — roadmap §1.1 route B.
//!
//! A rig is DATA: one `assets/rigs/<name>.rig` file (JSON) describes the
//! character's parts (texture, size, pivot, parent, rest pose) and its
//! animation clips (per-bone keyframe tracks). Text in, diffable, reviewable —
//! and generatable by an agent, which is the whole reason this exists instead
//! of a binary Spine workflow (whose runtime also requires a paid editor
//! license). Parts themselves come from the Floniks layered-parts pipeline.
//!
//! Engine mapping:
//!   part          -> child entity of the rig root, `Sprite` textured quad
//!   pivot         -> `Anchor::Custom` (the pivot sits AT the entity origin,
//!                    so rotation is about the pivot — a part can never
//!                    "detach" from its anchor, structurally)
//!   parent        -> Bevy `ChildOf` hierarchy (transforms compose for free)
//!   clip          -> per-bone keyframe tracks (t, rot, x, y), linearly
//!                    interpolated; looping clips wrap, one-shots clamp
//!   game.set_bone -> a manual override applied AFTER the clip each frame
//!                    (procedural animation, e.g. aim an arm at the pointer)
//!
//! Lua never touches any of this directly — `game.spawn_rig` / `game.play_anim`
//! / `game.set_bone` push commands like every other API (see script.rs).

use std::collections::HashMap;

use bevy::asset::{io::Reader, AssetLoader, LoadContext};
use bevy::prelude::*;
use bevy::sprite::Anchor;
use serde::Deserialize;

// ---------------------------------------------------------------------------
// Data model (the .rig JSON)
// ---------------------------------------------------------------------------

#[derive(Deserialize, Debug, Clone)]
pub struct RigDef {
    pub parts: Vec<PartDef>,
    #[serde(default)]
    pub clips: HashMap<String, ClipDef>,
}

#[derive(Deserialize, Debug, Clone)]
pub struct PartDef {
    pub name: String,
    /// Texture name under assets/textures/<image>.png (transparent-background
    /// part from the AIGC pipeline).
    pub image: String,
    pub w: f32,
    pub h: f32,
    /// Pivot in 0..1 part-local coords, (0,0) = bottom-left, (0.5,0.5) = center.
    /// The part rotates about this point.
    #[serde(default = "default_pivot")]
    pub pivot: [f32; 2],
    /// Parent part name; None/absent = attached directly to the rig root.
    #[serde(default)]
    pub parent: Option<String>,
    /// Rest-pose offset of this part's pivot, in the parent's local space.
    #[serde(default)]
    pub pos: [f32; 2],
    /// Draw-order bias among siblings (bigger = in front).
    #[serde(default)]
    pub z: f32,
}

fn default_pivot() -> [f32; 2] {
    [0.5, 0.5]
}

#[derive(Deserialize, Debug, Clone)]
pub struct ClipDef {
    /// Loop (wrap time) or one-shot (clamp at the last key).
    #[serde(default, rename = "loop")]
    pub looping: bool,
    /// bone name -> keyframes sorted by t (seconds).
    pub tracks: HashMap<String, Vec<Key>>,
}

#[derive(Deserialize, Debug, Clone, Copy, PartialEq)]
pub struct Key {
    pub t: f32,
    /// Rotation in radians about the pivot (0 = rest).
    #[serde(default)]
    pub rot: f32,
    /// Pivot translation offset from the rest pose, parent-local units.
    #[serde(default)]
    pub x: f32,
    #[serde(default)]
    pub y: f32,
}

/// A sampled bone pose (offset from the rest pose).
#[derive(Debug, Clone, Copy, PartialEq, Default)]
pub struct BonePose {
    pub rot: f32,
    pub x: f32,
    pub y: f32,
}

// ---------------------------------------------------------------------------
// Sampling (pure — this is what the headless tests drive)
// ---------------------------------------------------------------------------

/// Duration of a clip = the largest key time across its tracks.
pub fn clip_duration(clip: &ClipDef) -> f32 {
    clip.tracks
        .values()
        .flat_map(|keys| keys.iter().map(|k| k.t))
        .fold(0.0, f32::max)
}

/// Sample one track at time `t` (already wrapped/clamped): linear
/// interpolation between the surrounding keys, constant outside the key range.
fn sample_track(keys: &[Key], t: f32) -> BonePose {
    let Some(first) = keys.first() else {
        return BonePose::default();
    };
    if t <= first.t {
        return BonePose { rot: first.rot, x: first.x, y: first.y };
    }
    for pair in keys.windows(2) {
        let (a, b) = (pair[0], pair[1]);
        if t <= b.t {
            let span = (b.t - a.t).max(1e-6);
            let f = ((t - a.t) / span).clamp(0.0, 1.0);
            return BonePose {
                rot: a.rot + (b.rot - a.rot) * f,
                x: a.x + (b.x - a.x) * f,
                y: a.y + (b.y - a.y) * f,
            };
        }
    }
    let last = keys.last().unwrap();
    BonePose { rot: last.rot, x: last.x, y: last.y }
}

/// Sample every track of a clip at absolute time `t`. Looping clips wrap
/// (`t % duration`, so `sample(duration) == sample(0)` — the "loops return to
/// the start pose" invariant); one-shots clamp at the end.
pub fn sample_clip(clip: &ClipDef, t: f32) -> HashMap<&str, BonePose> {
    let dur = clip_duration(clip);
    let t = if dur <= 0.0 {
        0.0
    } else if clip.looping {
        t.rem_euclid(dur)
    } else {
        t.clamp(0.0, dur)
    };
    clip.tracks
        .iter()
        .map(|(name, keys)| (name.as_str(), sample_track(keys, t)))
        .collect()
}

/// Largest per-channel step a clip can make in one frame of length `dt` —
/// the "no bone teleports in a single frame" acceptance check. Scans the clip
/// at `dt` resolution (plus the loop seam, which `rem_euclid` makes continuous
/// by construction for clips whose last key returns to the first pose).
pub fn clip_max_rot_step(clip: &ClipDef, dt: f32) -> f32 {
    let dur = clip_duration(clip);
    if dur <= 0.0 || dt <= 0.0 {
        return 0.0;
    }
    let steps = (dur / dt).ceil() as usize + 1;
    let mut max_step = 0.0f32;
    for (_bone, keys) in clip.tracks.iter() {
        let mut prev = sample_track(keys, 0.0);
        for i in 1..=steps {
            let t = (i as f32 * dt).min(dur);
            let cur = sample_track(keys, t);
            max_step = max_step.max((cur.rot - prev.rot).abs());
            prev = cur;
        }
    }
    max_step
}

/// Parse a `.rig` JSON document.
pub fn parse_rig(text: &str) -> Result<RigDef, String> {
    serde_json::from_str(text).map_err(|e| e.to_string())
}

// ---------------------------------------------------------------------------
// Bevy side: asset, components, systems
// ---------------------------------------------------------------------------

#[derive(Asset, TypePath, Debug)]
pub struct RigAsset(pub RigDef);

#[derive(Default, TypePath)]
pub struct RigAssetLoader;

impl AssetLoader for RigAssetLoader {
    type Asset = RigAsset;
    type Settings = ();
    type Error = std::io::Error;

    async fn load(
        &self,
        reader: &mut dyn Reader,
        _settings: &(),
        _ctx: &mut LoadContext<'_>,
    ) -> Result<RigAsset, std::io::Error> {
        let mut bytes = Vec::new();
        reader.read_to_end(&mut bytes).await?;
        let text = String::from_utf8_lossy(&bytes);
        parse_rig(&text)
            .map(RigAsset)
            .map_err(|e| std::io::Error::new(std::io::ErrorKind::InvalidData, e))
    }

    fn extensions(&self) -> &[&str] {
        &["rig"]
    }
}

/// On the rig root from spawn time; `built` flips once parts exist.
#[derive(Component)]
pub struct RigRoot {
    pub handle: Handle<RigAsset>,
    pub built: bool,
}

/// Playback + override state (root component; commands mutate this, the
/// animate system consumes it — so play_anim before the asset arrives is fine).
#[derive(Component, Default)]
pub struct RigState {
    pub clip: Option<String>,
    pub t: f32,
    /// Manual bone overrides (game.set_bone), applied after the clip sample.
    pub overrides: HashMap<String, BonePose>,
}

/// bone name -> part entity + its rest-pose offset, filled at build time.
#[derive(Component, Default)]
pub struct RigBones(pub HashMap<String, (Entity, Vec2)>);

/// Build part hierarchies for rig roots whose asset has arrived.
pub fn build_rigs(
    mut commands: Commands,
    mut roots: Query<(Entity, &mut RigRoot)>,
    rigs: Res<Assets<RigAsset>>,
    assets: Res<AssetServer>,
) {
    for (root_entity, mut root) in &mut roots {
        if root.built {
            continue;
        }
        let Some(RigAsset(def)) = rigs.get(&root.handle) else {
            continue; // still loading; retry next frame
        };
        // First pass: spawn every part; second pass: parent them.
        let mut bones: HashMap<String, (Entity, Vec2)> = HashMap::new();
        for part in &def.parts {
            let anchor = Vec2::new(part.pivot[0] - 0.5, part.pivot[1] - 0.5);
            let entity = commands
                .spawn((
                    Sprite {
                        image: assets.load(format!("textures/{}.png", part.image)),
                        custom_size: Some(Vec2::new(part.w, part.h)),
                        ..default()
                    },
                    // Anchor is its own component in Bevy 0.19; putting the
                    // pivot at the entity origin makes rotation pivot-true.
                    Anchor(anchor),
                    Transform::from_xyz(part.pos[0], part.pos[1], 0.01 + part.z * 0.001),
                ))
                .id();
            bones.insert(part.name.clone(), (entity, Vec2::new(part.pos[0], part.pos[1])));
        }
        for part in &def.parts {
            let (entity, _) = bones[&part.name];
            let parent = part
                .parent
                .as_ref()
                .and_then(|p| bones.get(p).map(|(e, _)| *e))
                .unwrap_or(root_entity);
            commands.entity(entity).insert(ChildOf(parent));
        }
        commands
            .entity(root_entity)
            .insert(RigBones(bones));
        root.built = true;
    }
}

/// Advance clips and pose every bone: clip sample first, manual overrides win.
pub fn animate_rigs(
    time: Res<Time>,
    mut roots: Query<(&RigRoot, &mut RigState, &RigBones)>,
    rigs: Res<Assets<RigAsset>>,
    mut transforms: Query<&mut Transform>,
) {
    let dt = time.delta_secs();
    for (root, mut state, bones) in &mut roots {
        let Some(RigAsset(def)) = rigs.get(&root.handle) else {
            continue;
        };
        state.t += dt;
        let sampled = state
            .clip
            .as_ref()
            .and_then(|name| def.clips.get(name))
            .map(|clip| {
                let s = sample_clip(clip, state.t);
                // Detach borrow from `def` for the merge below.
                s.into_iter()
                    .map(|(k, v)| (k.to_string(), v))
                    .collect::<HashMap<String, BonePose>>()
            })
            .unwrap_or_default();
        for (bone, (entity, rest)) in bones.0.iter() {
            let pose = state
                .overrides
                .get(bone)
                .copied()
                .or_else(|| sampled.get(bone).copied());
            let Some(pose) = pose else { continue };
            if let Ok(mut transform) = transforms.get_mut(*entity) {
                transform.translation.x = rest.x + pose.x;
                transform.translation.y = rest.y + pose.y;
                transform.rotation = Quat::from_rotation_z(pose.rot);
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const SAMPLE: &str = r#"{
      "parts": [
        {"name": "torso", "image": "hero_torso", "w": 48, "h": 64},
        {"name": "arm",   "image": "hero_arm",   "w": 18, "h": 40,
         "pivot": [0.5, 0.9], "parent": "torso", "pos": [20, 22], "z": 1}
      ],
      "clips": {
        "wave": {
          "loop": true,
          "tracks": {
            "arm": [
              {"t": 0.0, "rot": 0.0},
              {"t": 0.5, "rot": 0.8, "x": 2},
              {"t": 1.0, "rot": 0.0}
            ]
          }
        },
        "raise": {
          "tracks": { "arm": [ {"t": 0.0}, {"t": 0.4, "rot": 1.2} ] }
        }
      }
    }"#;

    #[test]
    fn rig_json_parses_with_defaults() {
        let rig = parse_rig(SAMPLE).unwrap();
        assert_eq!(rig.parts.len(), 2);
        assert_eq!(rig.parts[0].pivot, [0.5, 0.5]); // default pivot = center
        assert_eq!(rig.parts[1].parent.as_deref(), Some("torso"));
        assert!(rig.clips["wave"].looping);
        assert!(!rig.clips["raise"].looping);
    }

    #[test]
    fn malformed_rig_is_an_error_not_a_panic() {
        assert!(parse_rig("{ not json").is_err());
        assert!(parse_rig("{\"clips\": {}}").is_err()); // parts is required
    }

    #[test]
    fn sampling_interpolates_linearly() {
        let rig = parse_rig(SAMPLE).unwrap();
        let clip = &rig.clips["wave"];
        let mid = sample_clip(clip, 0.25)["arm"];
        assert!((mid.rot - 0.4).abs() < 1e-5, "midpoint rot: {}", mid.rot);
        assert!((mid.x - 1.0).abs() < 1e-5, "midpoint x: {}", mid.x);
    }

    #[test]
    fn looping_clip_returns_to_its_start_pose() {
        // The roadmap invariant: a loop ends where it began.
        let rig = parse_rig(SAMPLE).unwrap();
        let clip = &rig.clips["wave"];
        let start = sample_clip(clip, 0.0)["arm"];
        let wrapped = sample_clip(clip, clip_duration(clip))["arm"];
        assert!((start.rot - wrapped.rot).abs() < 1e-5);
        assert!((start.x - wrapped.x).abs() < 1e-5);
        // And keeps doing so on later laps.
        let lap3 = sample_clip(clip, 3.0 * clip_duration(clip) + 0.25)["arm"];
        let ref_pose = sample_clip(clip, 0.25)["arm"];
        assert!((lap3.rot - ref_pose.rot).abs() < 1e-4);
    }

    #[test]
    fn one_shot_clip_clamps_at_its_last_key() {
        let rig = parse_rig(SAMPLE).unwrap();
        let clip = &rig.clips["raise"];
        let end = sample_clip(clip, 0.4)["arm"];
        let past = sample_clip(clip, 99.0)["arm"];
        assert_eq!(end, past); // holds the final pose forever
        assert!((past.rot - 1.2).abs() < 1e-5);
    }

    #[test]
    fn no_bone_teleports_within_a_frame() {
        // The roadmap invariant: max single-frame rotation stays bounded at
        // 60 fps. 0.8 rad over 0.5 s = 1.6 rad/s → ~0.027 rad per frame.
        let rig = parse_rig(SAMPLE).unwrap();
        for clip in rig.clips.values() {
            let step = clip_max_rot_step(clip, 1.0 / 60.0);
            assert!(step < 0.1, "single-frame rotation step too big: {step}");
        }
    }

    #[test]
    fn empty_and_single_key_tracks_are_stable() {
        let empty: Vec<Key> = vec![];
        assert_eq!(sample_track(&empty, 1.0), BonePose::default());
        let single = vec![Key { t: 0.0, rot: 0.5, x: 1.0, y: 2.0 }];
        for t in [0.0, 0.5, 100.0] {
            let p = sample_track(&single, t);
            assert_eq!((p.rot, p.x, p.y), (0.5, 1.0, 2.0));
        }
    }
}
