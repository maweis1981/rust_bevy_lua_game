// Animated background for hollowlullaby, drawn on a full-screen quad behind the
// game (a custom Bevy `Material2d`). Loaded as an asset, so it hot-reloads on
// desktop and is bundled on iOS (compiled WGSL -> Metal by wgpu/naga).

#import bevy_sprite::mesh2d_vertex_output::VertexOutput

// Material uniform (bind group index is filled in by Bevy's preprocessor).
// data = (time_seconds, aspect_ratio, unused, unused)
@group(#{MATERIAL_BIND_GROUP}) @binding(0) var<uniform> data: vec4<f32>;

@fragment
fn fragment(mesh: VertexOutput) -> @location(0) vec4<f32> {
    let t = data.x;
    let uv = mesh.uv;                 // 0..1 across the quad

    // Vertical base gradient.
    let top = vec3<f32>(0.04, 0.05, 0.11);
    let bottom = vec3<f32>(0.09, 0.12, 0.20);
    var col = mix(bottom, top, uv.y);

    // Slow diagonal light bands drifting over time.
    let band = sin((uv.x + uv.y) * 16.0 - t * 1.4) * 0.5 + 0.5;
    col += vec3<f32>(0.03, 0.05, 0.09) * band;

    // Faint moving grid, brighter where the bands pass.
    let cell = fract(uv * vec2<f32>(12.0, 26.0) + vec2<f32>(0.0, t * 0.05)) - 0.5;
    let grid = smoothstep(0.47, 0.5, max(abs(cell.x), abs(cell.y)));
    col += vec3<f32>(0.05, 0.07, 0.12) * grid * (0.35 + 0.65 * band);

    // Gentle vignette to focus the play area.
    let d = distance(uv, vec2<f32>(0.5, 0.5));
    col *= 1.0 - smoothstep(0.45, 0.95, d) * 0.5;

    return vec4<f32>(col, 1.0);
}
