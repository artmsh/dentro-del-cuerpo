// The Direct3D 11 port of shaders.metal, kept in the same order with the same names so the two files can
// be read side by side and changed together. What differs is spelling (lerp for mix, frac for fract,
// mul(M, v) for M * v, IN for the reserved word in) and how the stages are bound; the arithmetic is the
// same line for line, and a test in src/gpu/shader_parity.zig fails if the shared functions drift apart.

// Layouts mirror src/gpu.zig. A structured buffer packs its members to 4 bytes, so the Zig extern structs
// match byte for byte, as the packed types do in the Metal file.
struct Vertex { float3 pos; float3 nrm; float2 uv; };
struct Instance { float4x4 model; float4 color; float4 params; }; // params: material, emissive, seed, anim
struct PVertex { float3 pos; float2 uv; float4 color; };
struct HVertex { float2 pos; float2 uv; float4 color; };

struct Frame {
    float4x4 view_proj;
    float4 cam_pos;     // xyz, w = time
    float4 cam_fwd;     // xyz, w = headlamp intensity
    float4 fog_color;   // rgb, w = density
    float4 ambient;     // rgb, w = flow pulse 0..1
    float4 lamp_color;  // rgb, w = lamp range
    float4 misc;        // x = 1 for the first-person arms, y = scan pulse radius, z = unused, w = unused
};

struct Post {
    float4 a; // x exposure, y vignette, z damage flash, w warp
    float4 b; // x time, y fade, z aberration, w bloom
    float4 c; // x 1/width, y 1/height, z heal flash, w low-stability pulse
    float4 tint;
};

// Bindings. Metal passes buffers as arguments to each function; here they are globals with registers.
// Matrices are stored column-major in both, which is HLSL's default packing, so the bytes of a Zig Mat4
// are read the same way and mul(M, v) is Metal's M * v.
cbuffer FrameBuffer : register(b0) { Frame fr; };
cbuffer PostBuffer : register(b1) { Post po; };
// Metal's vertex_id and instance_id already include the draw's base vertex and base instance.
// SV_VertexID and SV_InstanceID do not, so each draw passes its bases here.
cbuffer DrawBuffer : register(b2) { uint base_vertex; uint base_instance; uint2 draw_unused; };
StructuredBuffer<Vertex> verts : register(t0);
StructuredBuffer<Instance> insts : register(t1);
StructuredBuffer<PVertex> pverts : register(t2);
StructuredBuffer<HVertex> hverts : register(t3);
Texture2D<float4> hdr : register(t4);
Texture2D<float4> font : register(t5);
SamplerState smp : register(s0);

struct SceneOut {
    float4 position : SV_Position;
    float3 wpos : TEXCOORD0;
    float3 nrm : TEXCOORD1;
    float3 lpos : TEXCOORD2;
    float2 uv : TEXCOORD3;
    float4 color : COLOR0;
    nointerpolation float4 params : TEXCOORD4;
};

float hash1(float3 p) {
    p = frac(p * 0.3183099 + float3(0.71, 0.113, 0.419));
    p *= 17.0;
    return frac(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float vnoise(float3 x) {
    float3 i = floor(x);
    float3 f = frac(x);
    f = f * f * (3.0 - 2.0 * f);
    return lerp(lerp(lerp(hash1(i), hash1(i + float3(1, 0, 0)), f.x),
                   lerp(hash1(i + float3(0, 1, 0)), hash1(i + float3(1, 1, 0)), f.x), f.y),
               lerp(lerp(hash1(i + float3(0, 0, 1)), hash1(i + float3(1, 0, 1)), f.x),
                   lerp(hash1(i + float3(0, 1, 1)), hash1(i + float3(1, 1, 1)), f.x), f.y), f.z);
}

float fbm(float3 p) {
    float a = 0.5, s = 0.0;
    for (int i = 0; i < 4; i++) { s += a * vnoise(p); p = p * 2.03 + 7.1; a *= 0.5; }
    return s;
}

float2 hash2(float2 p) {
    p = float2(dot(p, float2(127.1, 311.7)), dot(p, float2(269.5, 183.3)));
    return frac(sin(p) * 43758.5453);
}

// x = distance to nearest cell centre, y = distance to the cell border, z = cell id hash.
float2 cellHash(float2 c, float period) {
    if (period > 0.5) c.x = fmod(c.x + period * 8.0, period);
    return hash2(c);
}

// `period` > 0 makes the pattern repeat every `period` cells along x (so it closes around a tube).
float3 voronoi(float2 x, float period) {
    float2 n = floor(x), f = frac(x);
    float2 mg = 0, mr = 0;
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

SceneOut scene_vs(uint vid : SV_VertexID, uint iid : SV_InstanceID) {
    Vertex v = verts[vid + base_vertex];
    Instance inst = insts[iid + base_instance];
    float3 p = float3(v.pos);
    float3 n = float3(v.nrm);
    int mat = int(inst.params.x + 0.5);
    float t = fr.cam_pos.w;
    if (mat == 6) { // biofilm slime breathes
        float w = sin(t * 2.1 + p.x * 3.0 + inst.params.z * 9.0) * sin(t * 1.7 + p.y * 4.0) * 0.06;
        p += n * w;
    }
    float4 wp = mul(inst.model, float4(p, 1.0));
    SceneOut o;
    o.position = mul(fr.view_proj, wp);
    o.wpos = wp.xyz;
    o.nrm = mul(inst.model, float4(n, 0.0)).xyz;
    o.lpos = p;
    o.uv = float2(v.uv);
    o.color = inst.color;
    o.params = inst.params;
    return o;
}

float4 scene_fs(SceneOut IN) : SV_Target {
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
        float edge = lerp(1.0, smoothstep(0.0, 0.09, vo.y), near);
        float nucleus = smoothstep(0.34, 0.0, vo.x) * near;
        float mott = fbm(IN.wpos * 0.0045);
        float big = fbm(IN.wpos * 0.0011 + 5.0);
        float streak = vnoise(float3(IN.wpos.x * 0.02, IN.wpos.y * 0.02, IN.wpos.z * 0.0016));
        albedo *= lerp(0.55, 1.0, edge) * (0.6 + 0.6 * mott) * (0.7 + 0.6 * big) * (0.85 + 0.3 * streak) * (1.0 + (vo.z - 0.5) * 0.3 * near);
        albedo = lerp(albedo, albedo * float3(1.3, 1.08, 1.0), nucleus * 0.5);
        N = normalize(N + (nucleus * 0.45 - (1.0 - edge) * 0.6) * V);
        spec = 0.3 * edge; gloss = 40.0; rim = 0.22; rimCol = float3(0.9, 0.3, 0.28); wrap = 0.4;
    } else if (mat == 2) { // free cell membrane
        rim = 0.55; wrap = 0.45; spec = 0.3; gloss = 34.0;
        rimCol = lerp(albedo, float3(1.0, 0.8, 0.7), 0.18);
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
        alpha = lerp(0.62, 0.2, open) * (0.45 + 0.55 * pow(1.0 - ndv, 1.5));
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
        albedo *= (0.55 + 0.7 * lump) * lerp(0.6, 1.0, smoothstep(0.0, 0.12, vo.y));
        albedo = lerp(albedo, float3(0.75, 0.62, 0.45), smoothstep(0.62, 0.8, lump) * 0.6); // fibrin streaks
        spec = 0.45; gloss = 30.0; rim = 0.3; rimCol = float3(0.9, 0.3, 0.25); wrap = 0.4;
    } else if (mat == 9) { // calcified
        float3 vo = voronoi(IN.lpos.xy * 3.0 + IN.lpos.z * 2.3, 0.0);
        float crack = 1.0 - smoothstep(0.0, 0.05 + 0.1 * IN.params.w, vo.y);
        float3 fine = voronoi(IN.lpos.xy * 17.0 + IN.lpos.z * 13.1, 0.0);
        float pits = smoothstep(0.0, 0.08, fine.y);
        albedo *= (0.62 + 0.45 * fbm(IN.lpos * 6.0)) * (0.8 + 0.3 * fbm(IN.lpos * 41.0)) * lerp(0.62, 1.0, pits) * (0.9 + 0.2 * fine.z);
        // lamellae: phleboliths grow in concentric layers
        albedo *= 0.88 + 0.12 * sin(length(IN.lpos) * 60.0 + fbm(IN.lpos * 5.0) * 6.0);
        albedo = lerp(albedo, albedo * 0.3, crack);
        emisCol = float3(1.0, 0.7, 0.3);
        emissive = IN.params.y + crack * IN.params.w * 2.5;
        spec = 0.12; gloss = 16.0; rim = 0.15; wrap = 0.2;
    } else if (mat == 11) { // villus epithelium: one cobble per enterocyte, goblet cells scattered among them
        float near = smoothstep(900.0, 40.0, dist);
        float ang = atan2(IN.lpos.z, IN.lpos.x);
        float cells = max(6.0, floor(6.2832 * IN.params.w / 8.5));
        float2 q = float2((ang / 6.2832 + 0.5) * cells, IN.wpos.y / 8.5);
        float3 vo = voronoi(q, cells);
        float edge = lerp(1.0, smoothstep(0.0, 0.1, vo.y), near);
        float goblet = step(0.93, vo.z) * near;
        float mott = fbm(IN.wpos * 0.006 + IN.params.z * 13.0);
        float band = 0.85 + 0.15 * vnoise(float3(IN.wpos.y * 0.012, IN.params.z * 50.0, 0.0));
        albedo *= lerp(0.58, 1.0, edge) * (0.68 + 0.5 * mott) * band * (1.0 + (vo.z - 0.5) * 0.25 * near);
        albedo = lerp(albedo, float3(0.92, 0.86, 0.70), goblet * 0.55);
        N = normalize(N - (1.0 - edge) * 0.5 * V);
        // the brush border gives the surface a soft sheen
        spec = 0.45 * edge; gloss = 26.0; rim = 0.5; rimCol = float3(1.0, 0.78, 0.55); wrap = 0.5;
    } else if (mat == 12) { // crypt floor: a dark mouth at the centre of every cell of the pattern
        float near = smoothstep(1700.0, 80.0, dist);
        float3 vo = voronoi(IN.wpos.xz / 52.0, 0.0);
        float pit = smoothstep(0.42, 0.14, vo.x) * near;
        albedo *= (0.62 + 0.5 * fbm(IN.wpos * 0.004)) * lerp(1.0, 0.16, pit) * lerp(1.0, 0.8 + 0.4 * vo.z, near);
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

    float3 hemi = lerp(fr.ambient.rgb * 0.5, fr.ambient.rgb * 1.2, N.y * 0.5 + 0.5);
    // Within a few body lengths the lamp is dimmed, as an exposure-controlled work light would be, so a
    // subject at arm's length keeps its colour and form instead of clipping.
    if (!arm) lampGain *= lerp(0.55, 1.0, smoothstep(10.0, 90.0, dist));
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
        col = lerp(fogc, col, f);
        if (mat == 6 || mat == 7) alpha = lerp(1.0, alpha, saturate(f + 0.2));
    }
    return float4(col, alpha);
}

struct PartOut {
    float4 position : SV_Position;
    float2 uv : TEXCOORD0;
    float4 color : COLOR0;
};

PartOut part_vs(uint vid : SV_VertexID) {
    PVertex v = pverts[vid];
    PartOut o;
    o.position = mul(fr.view_proj, float4(float3(v.pos), 1.0));
    o.uv = float2(v.uv);
    float dist = length(fr.cam_pos.xyz - float3(v.pos));
    float f = exp(-dist * fr.fog_color.w * 0.6) * smoothstep(5.0, 38.0, dist); // glows at the lens would white out the view
    o.color = float4(v.color) * float4(f, f, f, 1.0);
    return o;
}

float4 part_fs(PartOut IN) : SV_Target {
    float r2 = dot(IN.uv, IN.uv);
    float a = exp(-r2 * 3.5) - 0.03;
    return float4(IN.color.rgb * IN.color.a * max(a, 0.0), 1.0);
}

struct FsOut {
    float4 position : SV_Position;
    float2 uv : TEXCOORD0;
};

FsOut post_vs(uint vid : SV_VertexID) {
    float2 p = float2((vid << 1) & 2, vid & 2);
    FsOut o;
    o.position = float4(p * 2.0 - 1.0, 0.0, 1.0);
    o.uv = float2(p.x, 1.0 - p.y);
    return o;
}

float3 aces(float3 x) {
    return saturate((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14));
}

// The full-resolution taps name level 0 outright. The Metal file leaves the level to the sampler, which
// picks 0 for a target drawn one texel to one pixel; HLSL will not take an implicit level inside a loop
// or a branch, and the answer is the same.
float4 post_fs(FsOut IN) : SV_Target {
    float2 uv = IN.uv;
    float2 c = uv - 0.5;
    float r = length(c);
    float warp = po.a.w;
    float3 col = 0;
    if (warp > 0.001) { // radial streak for time-compressed transit
        float tot = 0;
        for (int i = 0; i < 12; i++) {
            float k = 1.0 - warp * 0.5 * float(i) / 12.0;
            float w = 1.0 - float(i) / 14.0;
            col += hdr.SampleLevel(smp, 0.5 + c * k, 0.0).rgb * w;
            tot += w;
        }
        col /= tot;
    } else {
        float ab = po.b.z * r;
        col.r = hdr.SampleLevel(smp, uv + c * ab, 0.0).r;
        col.g = hdr.SampleLevel(smp, uv, 0.0).g;
        col.b = hdr.SampleLevel(smp, uv - c * ab, 0.0).b;
    }
    float3 bloom = 0;
    bloom += hdr.SampleLevel(smp, uv, 2.0).rgb * 0.3;
    bloom += hdr.SampleLevel(smp, uv, 3.5).rgb * 0.3;
    bloom += hdr.SampleLevel(smp, uv, 5.0).rgb * 0.25;
    bloom += hdr.SampleLevel(smp, uv, 6.5).rgb * 0.15;
    bloom = max(bloom - 0.9, 0.0);
    col += bloom * po.b.w;

    col *= po.a.x;
    col = lerp(col, col * po.tint.rgb, po.tint.a);
    col = aces(col);
    float vig = 1.0 - po.a.y * smoothstep(0.25, 0.85, r);
    col *= vig;
    col = lerp(col, float3(0.75, 0.02, 0.02), po.a.z * smoothstep(0.1, 0.8, r));
    col = lerp(col, float3(0.15, 0.95, 0.75), po.c.z * 0.5 * smoothstep(0.2, 0.9, r));
    col = lerp(col, float3(0.6, 0.0, 0.0), po.c.w * 0.35 * smoothstep(0.35, 0.9, r));
    float g = frac(sin(dot(uv * float2(1920.0, 1080.0) + po.b.x * 61.0, float2(12.9898, 78.233))) * 43758.5453);
    col += (g - 0.5) * 0.018;
    col = pow(saturate(col), 1.0 / 2.2);
    col *= po.b.y;
    return float4(col, 1.0);
}

struct HudOut {
    float4 position : SV_Position;
    float2 uv : TEXCOORD0;
    float4 color : COLOR0;
};

HudOut hud_vs(uint vid : SV_VertexID) {
    HVertex v = hverts[vid];
    HudOut o;
    float2 p = float2(v.pos) * po.c.xy;
    o.position = float4(p.x * 2.0 - 1.0, 1.0 - p.y * 2.0, 0.0, 1.0);
    o.uv = float2(v.uv);
    o.color = float4(v.color);
    return o;
}

// The glyph is sampled before the test, not inside it: the mip level comes from screen-space derivatives,
// which HLSL requires outside flow control. A solid quad's sample is taken and not used.
float4 hud_fs(HudOut IN) : SV_Target {
    float a = IN.color.a;
    float coverage = font.Sample(smp, IN.uv).r;
    if (IN.uv.x >= 0.0) a *= coverage;
    return float4(IN.color.rgb, a);
}
