// Animated deep-space backdrop for Time Dodge's 3D scene — a custom Bevy 3D
// `Material` on the far backdrop plane (src/rock3d.rs). Procedural: a nebula
// from domain-warped fractal noise, three parallax layers of twinkling stars,
// and a slow drift, all driven by time so it lives. Loaded as an asset (WGSL ->
// Metal on iOS, WGSL -> SPIR-V/wgpu on web/desktop).

#import bevy_pbr::forward_io::VertexOutput

// data = (time_seconds, aspect_ratio, energy 0..1, unused). Bevy fills the
// bind-group index via its preprocessor.
@group(#{MATERIAL_BIND_GROUP}) @binding(0) var<uniform> data: vec4<f32>;

fn hash2(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.x, p.y, p.x) * 0.1031);
    p3 = p3 + dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

fn noise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
    let a = hash2(i + vec2<f32>(0.0, 0.0));
    let b = hash2(i + vec2<f32>(1.0, 0.0));
    let c = hash2(i + vec2<f32>(0.0, 1.0));
    let d = hash2(i + vec2<f32>(1.0, 1.0));
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

fn fbm(p0: vec2<f32>) -> f32 {
    var p = p0;
    var value = 0.0;
    var amp = 0.5;
    let m = mat2x2<f32>(1.6, 1.2, -1.2, 1.6);
    for (var i: i32 = 0; i < 5; i = i + 1) {
        value = value + amp * noise(p);
        p = m * p;
        amp = amp * 0.5;
    }
    return value;
}

// One parallax layer of stars: a grid of cells, each with a jittered star whose
// brightness twinkles. `scale` = density, `drift` = parallax speed.
fn star_layer(uv: vec2<f32>, t: f32, scale: f32, drift: f32) -> f32 {
    let q = uv * scale + vec2<f32>(t * drift, t * drift * 0.3);
    let id = floor(q);
    let f = fract(q);
    let ctr = vec2<f32>(hash2(id), hash2(id + 7.3));
    let d = length(f - ctr);
    // some cells hold a star; brighter ones get a soft halo
    let present = step(0.66, hash2(id + 1.7));
    let tw = 0.6 + 0.4 * sin(t * 2.2 + hash2(id) * 6.2831);
    let core = smoothstep(0.09, 0.0, d) + 0.35 * smoothstep(0.22, 0.0, d);
    return present * core * tw;
}

@fragment
fn fragment(mesh: VertexOutput) -> @location(0) vec4<f32> {
    let t = data.x;
    let aspect = max(data.y, 0.0001);
    let energy = clamp(data.z, 0.0, 1.0);

    let uv = mesh.uv;
    var p = vec2<f32>((uv.x - 0.5) * aspect, uv.y - 0.5);

    // Nebula: domain-warped fbm, drifting slowly. Deep navy base -> indigo ->
    // violet -> teal wisps, kept dim so stars and rocks stay readable.
    let flow = t * (0.05 + energy * 0.15);
    let warp = vec2<f32>(fbm(p * 2.2 + vec2<f32>(0.0, flow)),
                         fbm(p * 2.2 + vec2<f32>(4.1, 1.3) - flow));
    let neb = fbm(p * 2.6 + 2.4 * warp);
    let c_base = vec3<f32>(0.02, 0.03, 0.07);
    let c_ind = vec3<f32>(0.10, 0.08, 0.26);
    let c_vio = vec3<f32>(0.24, 0.10, 0.36);
    let c_teal = vec3<f32>(0.06, 0.24, 0.36);
    var col = c_base;
    col = mix(col, c_ind, clamp(neb * neb * 2.6, 0.0, 1.0));
    col = mix(col, c_vio, clamp((neb - 0.32) * 1.9, 0.0, 1.0));
    col = mix(col, c_teal, clamp(length(warp) * 0.9, 0.0, 1.0));
    col = col * (0.85 + 0.15 * sin(t * 0.3));

    // Three parallax star layers (far dim + small, near bright + sparse).
    var stars = 0.0;
    stars = stars + star_layer(p, t, 34.0, 0.010) * 0.8;
    stars = stars + star_layer(p + 11.0, t, 20.0, 0.020) * 1.1;
    stars = stars + star_layer(p + 27.0, t, 12.0, 0.035) * 1.4;
    let star_col = vec3<f32>(0.9, 0.94, 1.0);
    col = col + star_col * stars;

    // Energy blooms the nebula a touch on impacts (ties to gameplay shake).
    col = col + vec3<f32>(0.10, 0.16, 0.24) * energy * smoothstep(0.4, 0.95, neb);

    // Gentle vignette to seat the play area.
    let d = distance(uv, vec2<f32>(0.5, 0.5));
    col = col * (1.0 - smoothstep(0.55, 1.1, d) * 0.5);

    return vec4<f32>(col, 1.0);
}
