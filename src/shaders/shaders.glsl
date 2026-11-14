// The GLSL ES 3.00 port of shaders.metal, for the OpenGL ES backend (src/gpu/gles.zig). It is one file
// for every stage of every program: the backend compiles it eight times, each time behind a
// `#version 300 es` line and two definitions, one of SCENE, PART, POST or HUD and one of VERTEX or
// FRAGMENT, which select the sections below. The functions keep the names and the order they have in the
// Metal file, and the ones that hold the look of the game are the same text line for line
// (src/gpu/shader_parity.zig compares them), so the three shader files can be read side by side.

precision highp float;
precision highp int;
precision highp sampler2D;

// Metal's spelling of the types and of two functions, so that the shared functions need no rewriting.
#define float2 vec2
#define float3 vec3
#define float4 vec4
#define int2 ivec2
#define int3 ivec3
#define uint2 uvec2
#define uint3 uvec3
#define saturate(x) clamp(x, 0.0, 1.0)
#define atan2(y, x) atan(y, x)
// GLSL leaves two things undefined that the shared text relies on and that Metal and Direct3D define:
// smoothstep with its edges in descending order, and pow of a negative base (the scan pulse squares a
// signed distance). Both are spelled out here, so every driver computes what the other two backends do.
#define SSTEP_T(a, b, x) clamp(((x) - (a)) / ((b) - (a)), 0.0, 1.0)
#define smoothstep(a, b, x) (SSTEP_T(a, b, x) * SSTEP_T(a, b, x) * (3.0 - 2.0 * SSTEP_T(a, b, x)))
#define pow(a, b) pow(abs(a), b)

// Layouts mirror src/gpu.zig; std140 lays a mat4 and vec4s out exactly as the Zig extern structs are.
layout(std140) uniform FrameBlock {
    mat4 view_proj;
    float4 cam_pos;     // xyz, w = time
    float4 cam_fwd;     // xyz, w = headlamp intensity
    float4 fog_color;   // rgb, w = density
    float4 ambient;     // rgb, w = flow pulse 0..1
    float4 lamp_color;  // rgb, w = lamp range
    float4 misc;        // x = 1 for the first-person arms, y = scan pulse radius, z = unused, w = unused
} fr;

layout(std140) uniform PostBlock {
    float4 a; // x exposure, y vignette, z damage flash, w warp
    float4 b; // x time, y fade, z aberration, w bloom
    float4 c; // x 1/width, y 1/height, z heal flash, w low-stability pulse
    float4 tint;
} po;

#ifdef FRAGMENT
// The hashes take whole-number coordinates and work in 32-bit integers (the PCG hashes of Jarzynski and
// Olano, "Hash Functions for GPU Rendering", 2020), so that every GPU and every call site computes the same
// value for the same lattice point. A hash made of floating-point products and a sine or a fraction gives
// a different value when its last bit is rounded differently, which compilers and drivers are free to do
// from one call site to the next, and a cell pattern or a noise lattice then disagrees with itself.
float hash1(float3 p) {
    uint3 v = uint3(int3(p)) * 1664525u + 1013904223u;
    v.x += v.y * v.z; v.y += v.z * v.x; v.z += v.x * v.y;
    v ^= v >> 16;
    v.x += v.y * v.z; v.y += v.z * v.x; v.z += v.x * v.y;
    return float(v.x >> 8) * (1.0 / 16777216.0);
}

#ifdef BAKED_PATTERNS
// The patterns drawn from three baked textures (src/gpu/gles_bake.zig) instead of computed: the noise
// volume holds `hash1` at 64 lattice points a side, the fbm volume holds four octaves of that noise
// summed over 8 cells of the first a side, and the cell tile holds what `voronoi` returns over 32 cells a
// side. All repeat, which the computed ones below do not.
uniform highp sampler3D noise_tex;
uniform highp sampler3D fbm_tex;
uniform highp sampler2D cell_tex;

float fbm(float3 p) {
    return textureLod(fbm_tex, p * (1.0 / 8.0), 0.0).r * 0.9375;
}

float vnoise(float3 x) {
    float3 i = floor(x);
    float3 f = fract(x);
    f = f * f * (3.0 - 2.0 * f);
    // Half a texel past the lattice point, the filter's weights are the fractions.
    return textureLod(noise_tex, (i + f + 0.5) * (1.0 / 64.0), 0.0).r;
}

float3 cellTap(float2 q, float2 dx, float2 dy) {
    float4 c = textureGrad(cell_tex, q * (1.0 / 32.0), dx * (1.0 / 32.0), dy * (1.0 / 32.0));
    return float3(c.r * 1.5, c.g, c.b);
}

float3 voronoi(float2 x, float period) {
    float2 dx = dFdx(x), dy = dFdy(x);
    if (period < 0.5) return cellTap(x, dx, dy);
    // Where the pattern wraps, x jumps by a whole period from one pixel to the next and its rate of
    // change must not.
    dx.x -= period * floor(dx.x / period + 0.5);
    dy.x -= period * floor(dy.x / period + 0.5);
    if (period >= 64.0) {
        // A long period is rounded to a whole number of tiles and the pattern stretched to fit.
        float2 fit = float2(floor(period / 32.0 + 0.5) * 32.0 / period, 1.0);
        return cellTap(x * fit, dx * fit, dy * fit);
    }
    // A short one keeps its cells' size, and the last cell before the wrap fades into the first.
    float2 q = float2(x.x - period * floor(x.x / period), x.y);
    return mix(cellTap(q, dx, dy), cellTap(q - float2(period, 0.0), dx, dy), saturate(q.x - (period - 1.0)));
}
#else
float vnoise(float3 x) {
    float3 i = floor(x);
    float3 f = fract(x);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(mix(hash1(i), hash1(i + float3(1, 0, 0)), f.x),
                   mix(hash1(i + float3(0, 1, 0)), hash1(i + float3(1, 1, 0)), f.x), f.y),
               mix(mix(hash1(i + float3(0, 0, 1)), hash1(i + float3(1, 0, 1)), f.x),
                   mix(hash1(i + float3(0, 1, 1)), hash1(i + float3(1, 1, 1)), f.x), f.y), f.z);
}


float fbm(float3 p) {
    float a = 0.5, s = 0.0;
    for (int i = 0; i < 4; i++) { s += a * vnoise(p); p = p * 2.03 + 7.1; a *= 0.5; }
    return s;
}
#endif

float2 hash2(float2 p) {
    uint2 v = uint2(int2(p)) * 1664525u + 1013904223u;
    v.x += v.y * 1664525u; v.y += v.x * 1664525u;
    v ^= v >> 16;
    v.x += v.y * 1664525u; v.y += v.x * 1664525u;
    v ^= v >> 16;
    return float2(v >> 8) * (1.0 / 16777216.0);
}

// x = distance to nearest cell centre, y = distance to the cell border, z = cell id hash.
float2 cellHash(float2 c, float period) {
    // The column wraps as an integer remainder. The divisor is kept from zero because the HLSL compiler
    // also evaluates this where the caller's period is the constant 0 and the branch is never taken.
    if (period > 0.5) c.x = float(uint(int(c.x + period * 8.0)) % uint(max(period, 1.0)));
    return hash2(c);
}

// `period` > 0 makes the pattern repeat every `period` cells along x (so it closes around a tube).
#ifndef BAKED_PATTERNS
float3 voronoi(float2 x, float period) {
    float2 n = floor(x), f = fract(x);
    float2 mg = float2(0.0), mr = float2(0.0);
    float md = 8.0;
    for (int j = -1; j <= 1; j++)
        for (int i = -1; i <= 1; i++) {
            float2 g = float2(i, j);
            float2 o = cellHash(n + g, period);
            float2 r = g + o - f;
            float d = dot(r, r);
            if (d < md) { md = d; mr = r; mg = g; }
        }
    float border = 8.0;
    for (int j = -2; j <= 2; j++)
        for (int i = -2; i <= 2; i++) {
            float2 g = mg + float2(i, j);
            float2 o = cellHash(n + g, period);
            float2 r = g + o - f;
            if (dot(mr - r, mr - r) > 0.00001) border = min(border, dot(0.5 * (mr + r), normalize(r - mr)));
        }
    return float3(sqrt(md), border, cellHash(n + mg, period).x);
}
#endif
#endif

#ifdef SCENE
struct SceneOut {
    float4 position;
    float3 wpos;
    float3 nrm;
    float3 lpos;
    float2 uv;
    float4 color;
    float4 params; // material, emissive, seed, anim
};

#ifdef VERTEX
// Vertex and instance data arrive as attributes: OpenGL ES 3.0 has no buffer a shader can index by
// vertex and instance number. The instance attributes advance once per instance, and the backend points
// them at the batch's first instance, which is how a base instance is expressed here.
layout(location = 0) in float3 a_pos;
layout(location = 1) in float3 a_nrm;
layout(location = 2) in float2 a_uv;
layout(location = 3) in mat4 i_model;
layout(location = 7) in float4 i_color;
layout(location = 8) in float4 i_params;
out float3 v_wpos;
out float3 v_nrm;
out float3 v_lpos;
out float2 v_uv;
out float4 v_color;
flat out float4 v_params;

void scene_vs() {
    float3 p = a_pos;
    float3 n = a_nrm;
    int mat = int(i_params.x + 0.5);
    float t = fr.cam_pos.w;
    if (mat == 6) { // biofilm slime breathes
        float w = sin(t * 2.1 + p.x * 3.0 + i_params.z * 9.0) * sin(t * 1.7 + p.y * 4.0) * 0.06;
        p += n * w;
    }
    float4 wp = i_model * float4(p, 1.0);
    gl_Position = fr.view_proj * wp;
    // The game's projection puts depth in 0..1, as Metal and Direct3D clip it; OpenGL clips -w..w.
    gl_Position.z = 2.0 * gl_Position.z - gl_Position.w;
    v_wpos = wp.xyz;
    v_nrm = (i_model * float4(n, 0.0)).xyz;
    v_lpos = p;
    v_uv = a_uv;
    v_color = i_color;
    v_params = i_params;
}

void main() { scene_vs(); }
#endif

#ifdef FRAGMENT
in float3 v_wpos;
in float3 v_nrm;
in float3 v_lpos;
in float2 v_uv;
in float4 v_color;
flat in float4 v_params;
out float4 frag;

float4 scene_fs(SceneOut IN) {
    float t = fr.cam_pos.w;
    int mat = int(IN.params.x + 0.5);
    float3 N = normalize(IN.nrm);
    float3 toCam = fr.cam_pos.xyz - IN.wpos;
    if (dot(N, toCam) < 0.0) N = -N; // every surface is two-sided
    float dist = length(toCam);
    float3 V = toCam / max(dist, 1e-4);
    bool arm = fr.misc.x > 0.5;

    float3 albedo = IN.color.rgb;
    float alpha = IN.color.a;
    float spec = 0.15, gloss = 24.0, rim = 0.0, emissive = IN.params.y, wrap = 0.35;
    float3 rimCol = albedo;
    float3 emisCol = albedo;

    if (mat == 1) { // vessel wall: endothelium, one cobble per cell, stretched along the flow
        float near = smoothstep(1300.0, 60.0, dist); // cell-scale detail fades out before it can alias
        float3 vo = voronoi(IN.uv * float2(1.0, 0.32), IN.params.w);
        float edge = mix(1.0, smoothstep(0.0, 0.09, vo.y), near);
        float nucleus = smoothstep(0.34, 0.0, vo.x) * near;
        float mott = fbm(IN.wpos * 0.0045);
        float big = fbm(IN.wpos * 0.0011 + 5.0);
        float streak = vnoise(float3(IN.wpos.x * 0.02, IN.wpos.y * 0.02, IN.wpos.z * 0.0016));
        albedo *= mix(0.55, 1.0, edge) * (0.6 + 0.6 * mott) * (0.7 + 0.6 * big) * (0.85 + 0.3 * streak) * (1.0 + (vo.z - 0.5) * 0.3 * near);
        albedo = mix(albedo, albedo * float3(1.3, 1.08, 1.0), nucleus * 0.5);
        N = normalize(N + (nucleus * 0.45 - (1.0 - edge) * 0.6) * V);
        spec = 0.3 * edge; gloss = 40.0; rim = 0.22; rimCol = float3(0.9, 0.3, 0.28); wrap = 0.4;
    } else if (mat == 2) { // free cell membrane
        rim = 0.55; wrap = 0.45; spec = 0.3; gloss = 34.0;
        rimCol = mix(albedo, float3(1.0, 0.8, 0.7), 0.18);
        float g = vnoise(IN.lpos * 3.0 + IN.params.z * 31.0);
        albedo *= 0.85 + 0.3 * g;
    } else if (mat == 3) { // drone metal
        float brushed = vnoise(float3(IN.uv.x * 90.0, IN.uv.y * 3.0, 0.0));
        albedo *= 0.8 + 0.25 * brushed;
        spec = 0.7; gloss = 48.0; rim = 0.5; rimCol = fr.fog_color.rgb * 3.0 + float3(0.10, 0.11, 0.13); wrap = 0.15;
    } else if (mat == 5) { // fibrin
        float fib = vnoise(float3(IN.uv.x * 14.0, IN.uv.y * 1.2, IN.params.z * 7.0));
        albedo *= 0.7 + 0.5 * fib;
        rim = 0.6; rimCol = float3(1.0, 0.9, 0.7); spec = 0.2; wrap = 0.6;
        // drilled anchors glow from the cut
        emisCol = float3(1.0, 0.55, 0.15);
    } else if (mat == 6) { // biofilm slime
        float ndv = saturate(dot(N, V));
        float open = IN.params.w;
        alpha = mix(0.62, 0.2, open) * (0.45 + 0.55 * pow(1.0 - ndv, 1.5));
        albedo *= 0.8 + 0.4 * vnoise(IN.lpos * 4.0 + t * 0.3);
        spec = 0.6; gloss = 50.0; rim = 0.5; rimCol = float3(0.9, 0.7, 0.2); wrap = 0.5;
        emisCol = float3(1.0, 0.8, 0.25);
    } else if (mat == 7) { // valve leaflet
        float fibres = vnoise(float3(IN.uv.x * 26.0, IN.uv.y * 3.0, 2.0));
        albedo *= 0.8 + 0.3 * fibres;
        float ndv = saturate(dot(N, V));
        alpha = IN.color.a * (0.72 + 0.28 * pow(1.0 - ndv, 2.0));
        rim = 0.5; rimCol = float3(1.0, 0.7, 0.65); spec = 0.3; gloss = 35.0; wrap = 0.75;
    } else if (mat == 8) { // thrombus
        float3 vo = voronoi(IN.lpos.xy * 5.0 + IN.lpos.z * 3.1, 0.0);
        float lump = fbm(IN.lpos * 3.0);
        albedo *= (0.55 + 0.7 * lump) * mix(0.6, 1.0, smoothstep(0.0, 0.12, vo.y));
        albedo = mix(albedo, float3(0.75, 0.62, 0.45), smoothstep(0.62, 0.8, lump) * 0.6); // fibrin streaks
        spec = 0.45; gloss = 30.0; rim = 0.3; rimCol = float3(0.9, 0.3, 0.25); wrap = 0.4;
    } else if (mat == 9) { // calcified
        float3 vo = voronoi(IN.lpos.xy * 3.0 + IN.lpos.z * 2.3, 0.0);
        float crack = 1.0 - smoothstep(0.0, 0.05 + 0.1 * IN.params.w, vo.y);
        float3 fine = voronoi(IN.lpos.xy * 17.0 + IN.lpos.z * 13.1, 0.0);
        float pits = smoothstep(0.0, 0.08, fine.y);
        albedo *= (0.62 + 0.45 * fbm(IN.lpos * 6.0)) * (0.8 + 0.3 * fbm(IN.lpos * 41.0)) * mix(0.62, 1.0, pits) * (0.9 + 0.2 * fine.z);
        // lamellae: phleboliths grow in concentric layers
        albedo *= 0.88 + 0.12 * sin(length(IN.lpos) * 60.0 + fbm(IN.lpos * 5.0) * 6.0);
        albedo = mix(albedo, albedo * 0.3, crack);
        emisCol = float3(1.0, 0.7, 0.3);
        emissive = IN.params.y + crack * IN.params.w * 2.5;
        spec = 0.12; gloss = 16.0; rim = 0.15; wrap = 0.2;
    } else if (mat == 11) { // villus epithelium: one cobble per enterocyte, goblet cells scattered among them
        float near = smoothstep(900.0, 40.0, dist);
        float ang = atan2(IN.lpos.z, IN.lpos.x);
        float cells = max(6.0, floor(6.2832 * IN.params.w / 8.5));
        float2 q = float2((ang / 6.2832 + 0.5) * cells, IN.wpos.y / 8.5);
        float3 vo = voronoi(q, cells);
        float edge = mix(1.0, smoothstep(0.0, 0.1, vo.y), near);
        float goblet = step(0.93, vo.z) * near;
        float mott = fbm(IN.wpos * 0.006 + IN.params.z * 13.0);
        float band = 0.85 + 0.15 * vnoise(float3(IN.wpos.y * 0.012, IN.params.z * 50.0, 0.0));
        albedo *= mix(0.58, 1.0, edge) * (0.68 + 0.5 * mott) * band * (1.0 + (vo.z - 0.5) * 0.25 * near);
        albedo = mix(albedo, float3(0.92, 0.86, 0.70), goblet * 0.55);
        N = normalize(N - (1.0 - edge) * 0.5 * V);
        // the brush border gives the surface a soft sheen
        spec = 0.45 * edge; gloss = 26.0; rim = 0.5; rimCol = float3(1.0, 0.78, 0.55); wrap = 0.5;
    } else if (mat == 12) { // crypt floor: a dark mouth at the centre of every cell of the pattern
        float near = smoothstep(1700.0, 80.0, dist);
        float3 vo = voronoi(IN.wpos.xz / 52.0, 0.0);
        float pit = smoothstep(0.42, 0.14, vo.x) * near;
        albedo *= (0.62 + 0.5 * fbm(IN.wpos * 0.004)) * mix(1.0, 0.16, pit) * mix(1.0, 0.8 + 0.4 * vo.z, near);
        spec = 0.3 * (1.0 - pit); gloss = 30.0; rim = 0.25; rimCol = float3(1.0, 0.7, 0.5); wrap = 0.5;
    } else if (mat == 10) { // hologram marker
        float scan = 0.6 + 0.4 * sin(IN.wpos.z * 0.35 - t * 6.0);
        float ndv = saturate(dot(N, V));
        float a = IN.color.a * scan * (0.35 + 0.65 * pow(1.0 - ndv, 1.5));
        return float4(IN.color.rgb * (1.5 + IN.params.y), a);
    } else if (mat == 4) { // unlit
        float f = exp(-dist * fr.fog_color.w * 0.5);
        return float4(IN.color.rgb * IN.params.y * f, IN.color.a);
    }

    float lampRange = fr.lamp_color.w;
    float atten = 1.0 / (1.0 + (dist * dist) / (lampRange * lampRange));
    // The work lamp sits up and to the right of the lens, so surfaces show form instead of a flat flash.
    float3 L;
    float lampGain = fr.cam_fwd.w;
    if (arm) {
        atten = 1.0;
        lampGain *= 0.62;
        L = normalize(float3(0.28, 0.80, 0.55)); // the arms are drawn in view space
    } else {
        float3 fw = fr.cam_fwd.xyz;
        float3 rt = cross(fw, float3(0.0, 1.0, 0.0));
        rt = rt / max(length(rt), 1e-3);
        float3 upv = cross(rt, fw);
        L = normalize(V + rt * 0.30 + upv * 0.36);
    }
    float ndl = dot(N, L);
    float ndv = dot(N, V);
    float diff = saturate((ndl + wrap) / (1.0 + wrap));
    float3 H = normalize(L + V);
    float sp = pow(saturate(dot(N, H)), gloss) * spec;
    float fres = pow(1.0 - saturate(ndv), 3.0);

    float3 hemi = mix(fr.ambient.rgb * 0.5, fr.ambient.rgb * 1.2, N.y * 0.5 + 0.5);
    // Within a few body lengths the lamp is dimmed, as an exposure-controlled work light would be, so a
    // subject at arm's length keeps its colour and form instead of clipping.
    if (!arm) lampGain *= mix(0.55, 1.0, smoothstep(10.0, 90.0, dist));
    float3 lamp = fr.lamp_color.rgb * lampGain * atten;
    float3 col = albedo * (hemi + lamp * diff) + lamp * sp + rimCol * fres * rim * (hemi * 1.4 + lamp * 0.35);
    col += emisCol * emissive;

    // Scan pulse: a shell of light expanding from the drone when the pilot identifies something.
    float pulse = fr.misc.y;
    if (pulse > 0.0 && !arm) {
        float band = exp(-pow((dist - pulse) / 14.0, 2.0));
        col += float3(0.2, 0.9, 1.0) * band * 0.9;
    }

    if (!arm) {
        float f = exp(-dist * fr.fog_color.w);
        float3 fogc = fr.fog_color.rgb * (0.9 + 0.2 * fr.ambient.w);
        col = mix(fogc, col, f);
        if (mat == 6 || mat == 7) alpha = mix(1.0, alpha, saturate(f + 0.2));
    }
    return float4(col, alpha);
}

void main() { frag = scene_fs(SceneOut(gl_FragCoord, v_wpos, v_nrm, v_lpos, v_uv, v_color, v_params)); }
#endif
#endif

#ifdef PART
struct PartOut {
    float4 position;
    float2 uv;
    float4 color;
};

#ifdef VERTEX
layout(location = 0) in float3 a_pos;
layout(location = 1) in float2 a_uv;
layout(location = 2) in float4 a_color;
out float2 v_uv;
out float4 v_color;

void part_vs() {
    gl_Position = fr.view_proj * float4(a_pos, 1.0);
    gl_Position.z = 2.0 * gl_Position.z - gl_Position.w;
    v_uv = a_uv;
    float dist = length(fr.cam_pos.xyz - a_pos);
    float f = exp(-dist * fr.fog_color.w * 0.6) * smoothstep(5.0, 38.0, dist); // glows at the lens would white out the view
    v_color = a_color * float4(f, f, f, 1.0);
}

void main() { part_vs(); }
#endif

#ifdef FRAGMENT
in float2 v_uv;
in float4 v_color;
out float4 frag;

float4 part_fs(PartOut IN) {
    float r2 = dot(IN.uv, IN.uv);
    float a = exp(-r2 * 3.5) - 0.03;
    return float4(IN.color.rgb * IN.color.a * max(a, 0.0), 1.0);
}

void main() { frag = part_fs(PartOut(gl_FragCoord, v_uv, v_color)); }
#endif
#endif

#ifdef POST
struct FsOut {
    float4 position;
    float2 uv;
};

#ifdef VERTEX
out float2 v_uv;

void post_vs() {
    float2 p = float2((gl_VertexID << 1) & 2, gl_VertexID & 2);
    gl_Position = float4(p * 2.0 - 1.0, 0.0, 1.0);
    // The scene was drawn with OpenGL's origin at the bottom left and is read back the same way, so the
    // coordinate is not flipped as it is for Metal's and Direct3D's top-left textures.
    v_uv = p;
}

void main() { post_vs(); }
#endif

#ifdef FRAGMENT
in float2 v_uv;
out float4 frag;
uniform sampler2D hdr;
// Added to the mip level of every bloom tap: the scene may be drawn smaller than the output, and a level
// of a smaller image covers more of the screen. Zero when the two are the same size.
uniform float lod_bias;
// 1 when this pass writes the output, 0 when the image is scaled up afterwards (the UPSCALE program
// below). The film grain and the fade are left to the last pass: the grain is one to an output pixel,
// and the fade has to darken the grain as well.
uniform float last_pass;
// One tap of the scene image at a named mip level; level 0 is the image itself.
#define tap(uv, lod) textureLod(hdr, uv, max((lod) + lod_bias, 0.0))

float3 aces(float3 x) {
    return saturate((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14));
}

float4 post_fs(FsOut IN) {
    float2 uv = IN.uv;
    float2 c = uv - 0.5;
    float r = length(c);
    float warp = po.a.w;
    float3 col = float3(0.0);
    if (warp > 0.001) { // radial streak for time-compressed transit
        float tot = 0.0;
        for (int i = 0; i < 12; i++) {
            float k = 1.0 - warp * 0.5 * float(i) / 12.0;
            float w = 1.0 - float(i) / 14.0;
            col += tap(0.5 + c * k, 0.0).rgb * w;
            tot += w;
        }
        col /= tot;
    } else {
        float ab = po.b.z * r;
        col.r = tap(uv + c * ab, 0.0).r;
        col.g = tap(uv, 0.0).g;
        col.b = tap(uv - c * ab, 0.0).b;
    }
    float3 bloom = float3(0.0);
    bloom += tap(uv, 2.0).rgb * 0.3;
    bloom += tap(uv, 3.5).rgb * 0.3;
    bloom += tap(uv, 5.0).rgb * 0.25;
    bloom += tap(uv, 6.5).rgb * 0.15;
    bloom = max(bloom - 0.9, 0.0);
    col += bloom * po.b.w;

    col *= po.a.x;
    col = mix(col, col * po.tint.rgb, po.tint.a);
    col = aces(col);
    float vig = 1.0 - po.a.y * smoothstep(0.25, 0.85, r);
    col *= vig;
    col = mix(col, float3(0.75, 0.02, 0.02), po.a.z * smoothstep(0.1, 0.8, r));
    col = mix(col, float3(0.15, 0.95, 0.75), po.c.z * 0.5 * smoothstep(0.2, 0.9, r));
    col = mix(col, float3(0.6, 0.0, 0.0), po.c.w * 0.35 * smoothstep(0.35, 0.9, r));
    float g = hash1(float3(floor(IN.position.xy), floor(po.b.x * 977.0)));
    col += (g - 0.5) * 0.018 * last_pass;
    col = pow(saturate(col), float3(1.0 / 2.2));
    col *= mix(1.0, po.b.y, last_pass);
    return float4(col, 1.0);
}

void main() { frag = post_fs(FsOut(gl_FragCoord, v_uv)); }
#endif
#endif

// The tonemapped image scaled up to the output, when the scene is drawn smaller than it (OpenGL ES
// only), with the film grain added here, so that it is as fine as the output's pixels whatever the
// scene's size, and the fade after it. This pass runs at every pixel of the output and does not shrink
// with the scene, and on the television's GPU it is the largest cost that does not, so it is kept to two
// texture reads at coordinates that come straight from the vertex shader and a line of arithmetic at
// medium precision. The grain comes from a texture of hashes (src/gpu/gles_bake.zig) and is added to
// the image as it stands, with the display curve already applied; the post pass, when it is the last,
// adds it to linear light, where the same grain shows more in the dark.
#ifdef UPSCALE
#ifdef VERTEX
out float2 v_uv;
out float2 v_grain;
uniform float2 grain_at; // where in the noise this frame starts; changes every frame

void main() {
    float2 p = float2((gl_VertexID << 1) & 2, gl_VertexID & 2);
    gl_Position = float4(p * 2.0 - 1.0, 0.0, 1.0);
    v_uv = p;
    // One texel of the grain to a pixel of the output: po.c is one over the output's size.
    v_grain = p / (po.c.xy * 256.0) + grain_at;
}
#endif

#ifdef FRAGMENT
in float2 v_uv;
in float2 v_grain;
out mediump float4 frag;
uniform mediump sampler2D ldr;
uniform mediump sampler2D grain;

void main() {
    mediump float3 col = texture(ldr, v_uv).rgb;
    mediump float g = texture(grain, v_grain).r;
    mediump float fade = po.b.y;
    frag = float4((col + (g - 0.5) * 0.03) * fade, 1.0);
}
#endif
#endif

#ifdef HUD
#ifdef VERTEX
layout(location = 0) in float2 a_pos;
layout(location = 1) in float2 a_uv;
layout(location = 2) in float4 a_color;
out float2 v_uv;
out float4 v_color;

void hud_vs() {
    float2 p = a_pos * po.c.xy;
    gl_Position = float4(p.x * 2.0 - 1.0, 1.0 - p.y * 2.0, 0.0, 1.0);
    v_uv = a_uv;
    v_color = a_color;
}

void main() { hud_vs(); }
#endif

#ifdef FRAGMENT
in float2 v_uv;
in float4 v_color;
out float4 frag;
uniform sampler2D font;

float4 hud_fs() {
    // The glyph is sampled before the branch: a mip level cannot be derived inside one.
    float glyph = texture(font, v_uv).r;
    float a = v_color.a;
    if (v_uv.x >= 0.0) a *= glyph;
    return float4(v_color.rgb, a);
}

void main() { frag = hud_fs(); }
#endif
#endif
