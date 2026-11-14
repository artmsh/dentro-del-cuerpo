//! Frame assembly: instanced meshes, per-frame dynamic geometry, additive particles, and the 2D HUD.

const std = @import("std");
const m = @import("math.zig");
const gpu = @import("gpu.zig");
const font_mod = @import("font.zig");
const mesh_mod = @import("mesh.zig");
const utf8 = @import("utf8.zig");
const Vec3 = m.Vec3;
const Mat4 = m.Mat4;

pub const Material = enum(u8) {
    lit = 0,
    wall = 1,
    cell = 2,
    metal = 3,
    unlit = 4,
    fibrin = 5,
    slime = 6,
    leaflet = 7,
    clot = 8,
    calcified = 9,
    hologram = 10,
    mucosa = 11,
    crypt_floor = 12,
};

pub const Color = [4]f32;

pub fn rgba(r: f32, g: f32, b: f32, a: f32) Color {
    return .{ r, g, b, a };
}

pub const Style = struct {
    color: Color = .{ 1, 1, 1, 1 },
    mat: Material = .lit,
    emissive: f32 = 0,
    seed: f32 = 0,
    anim: f32 = 0,
};

/// Meshes shared by every chapter.
pub const Meshes = struct {
    sphere: gpu.Mesh,
    sphere_lo: gpu.Mesh,
    red_cell: gpu.Mesh,
    red_cell_lo: gpu.Mesh,
    white_cell: gpu.Mesh,
    platelet: gpu.Mesh,
    cluster: [3]gpu.Mesh,
    blob: [3]gpu.Mesh,
    dome: gpu.Mesh,
    cylinder: gpu.Mesh,
    cone: gpu.Mesh,
    drill_bit: gpu.Mesh,
    torus: gpu.Mesh,
    torus_thin: gpu.Mesh,
    box: gpu.Mesh,
    capsule: gpu.Mesh,
    /// Mucosal floor profile across the trough, one unit long in z (see gut.floorY).
    mucosa_strip: gpu.Mesh,
    /// Chapter 3: one lattice cell of antral mucosa around the mouth of its pit and the pit below it (two
    /// meshes, so the pit can be drawn darker), the floor profile one unit long in z, the ulcer's rim and
    /// bed, the top of the mucus gel (in units of `gel_unit`), a corkscrew rod, and the cut end of a
    /// vessel: a tube of unit radius about +Y with a rolled lip at y = 0 and three radii of length below it.
    pit_tile: gpu.Mesh,
    pit_bore: gpu.Mesh,
    stump: gpu.Mesh,
    antrum_floor: gpu.Mesh,
    ulcer_rim: gpu.Mesh,
    ulcer_bed: gpu.Mesh,
    gel_sheet: gpu.Mesh,
    helix: gpu.Mesh,

    pub fn build(b: *mesh_mod.Builder) Meshes {
        var ms: Meshes = undefined;
        ms.sphere = b.sphere(16, 24);
        ms.sphere_lo = b.sphere(6, 8);
        ms.red_cell = b.redCell(7, 18);
        ms.red_cell_lo = b.redCell(3, 8);
        ms.white_cell = b.blob(14, 20, 3.0, 0.07, 5.0, 1.0);
        ms.platelet = b.blob(6, 10, 9.0, 0.12, 2.0, 0.35);
        for (&ms.cluster, 0..) |*c, i| c.* = b.cluster(@intCast(5 + i), 11 + i * 7);
        ms.blob[0] = b.blob(24, 32, mesh_mod.clot_seed, mesh_mod.clot_amp, mesh_mod.clot_freq, 1.0);
        ms.blob[1] = b.blob(14, 20, 5.0, 0.35, 2.2, 0.85);
        ms.blob[2] = b.blob(14, 20, 8.0, 0.22, 2.8, 1.0);
        ms.dome = b.revolve(&domeProfile(), 22);
        ms.cylinder = b.revolve(&.{ .{ 0, 0 }, .{ 1, 0 }, .{ 1, 0.001 }, .{ 1, 1 }, .{ 1, 1.001 }, .{ 0, 1.001 } }, 16);
        ms.cone = b.revolve(&.{ .{ 0, 0 }, .{ 1, 0 }, .{ 1, 0.001 }, .{ 0.02, 1 } }, 16);
        ms.drill_bit = drillBit(b);
        ms.torus = b.torus(0.06, 48, 10);
        ms.torus_thin = b.torus(0.015, 64, 6);
        ms.box = b.box();
        ms.capsule = b.revolve(&capsuleProfile(), 12);
        {
            const gut = @import("gut.zig");
            b.begin();
            const n: u32 = 44;
            for (0..n + 1) |i| {
                const x = -2700 + 5400 * @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(n));
                const slope = (gut.floorY(x + 1) - gut.floorY(x - 1)) / 2;
                const nrm = m.v3(-slope, 1, 0).norm();
                _ = b.vert(m.v3(x, gut.floorY(x), 0), nrm, x, 0);
                _ = b.vert(m.v3(x, gut.floorY(x), 1), nrm, x, 1);
            }
            for (0..n) |i| {
                const a: u32 = @intCast(i * 2);
                b.quad(a, a + 1, a + 3, a + 2);
            }
            ms.mucosa_strip = b.end();
        }
        buildStomach(b, &ms);
        return ms;
    }

    /// Cobbles of the wall material around a pit, and so around the seam of its texture.
    pub const pit_cells_around: f32 = 24;
    /// Where the antrum's floor strip begins: everything nearer the ulcer is the rim mesh.
    pub const antrum_floor_z0: f32 = 3700;
    /// The gel sheet is modelled at 1/gel_unit scale so the slime material's noise is the right size.
    pub const gel_unit: f32 = 250;

    /// Chapter 3 scenery, from the functions in stomach.zig that the collision reads.
    fn buildStomach(b: *mesh_mod.Builder, ms: *Meshes) void {
        const st = @import("stomach.zig");
        const cell: f32 = 9; // width of one surface cell, for the wall material's cobbles
        const v_per: f32 = 1.0 / (cell * 0.32);

        // A hexagon of surface with the pit sunk in its middle, as a surface of revolution whose first
        // ring is the hexagon's outline. Texture runs around the pit and down into it.
        {
            b.begin();
            const seg: u32 = 12;
            const s30: f32 = 0.5;
            const c30: f32 = 0.8660254;
            const bottom = -(st.pit_depth - st.pit_r);
            // radius, height, and the normal's (radial, vertical) parts; the first ring is the outline
            const rings = [_][4]f32{
                .{ 0, 0, 0, 1 },
                .{ st.pit_r + 7, 0, -0.38, 0.92 },
                .{ st.pit_r, -7, -0.92, 0.38 },
                .{ st.pit_r, -80, -1, 0 },
                .{ st.pit_r, bottom, -1, 0 },
                .{ st.pit_r * c30, bottom - st.pit_r * s30, -c30, s30 },
                .{ st.pit_r * s30, bottom - st.pit_r * c30, -s30, c30 },
                .{ 0.01, -st.pit_depth, 0, 1 },
            };
            // distance along the profile, which is the texture's other axis
            var runs: [rings.len]f32 = undefined;
            var prev_r: f32 = st.pitch * 0.5;
            var prev_y: f32 = 0;
            var run: f32 = 0;
            for (rings, 0..) |ring, j| {
                const rr = if (j == 0) st.pitch * 0.5 else ring[0];
                run += @sqrt((rr - prev_r) * (rr - prev_r) + (ring[1] - prev_y) * (ring[1] - prev_y));
                runs[j] = run;
                prev_r = rr;
                prev_y = ring[1];
            }
            // the surface down to the neck of the pit, then the pit from the neck down
            inline for (.{ [2]usize{ 0, 2 }, [2]usize{ 2, rings.len - 1 } }, 0..) |span, which| {
                b.begin();
                for (span[0]..span[1] + 1) |j| {
                    const ring = rings[j];
                    for (0..seg + 1) |i| {
                        const a = m.tau * @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(seg));
                        var radius = ring[0];
                        if (j == 0) {
                            // apothem pitch/2 towards the neighbours in the row, corners between them
                            const local = @mod(a + m.pi / 6.0, m.pi / 3.0) - m.pi / 6.0;
                            radius = st.pitch * 0.5 / @cos(local);
                        }
                        const c = @cos(a);
                        const s = @sin(a);
                        _ = b.vert(m.v3(radius * c, ring[1], radius * s), m.v3(ring[2] * c, ring[3], ring[2] * s), pit_cells_around * @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(seg)), runs[j] * v_per);
                    }
                }
                for (0..span[1] - span[0]) |j| {
                    for (0..seg) |i| {
                        const a: u32 = @intCast(j * (seg + 1) + i);
                        b.quad(a, a + 1, a + seg + 2, a + seg + 1);
                    }
                }
                if (which == 0) ms.pit_tile = b.end() else ms.pit_bore = b.end();
            }
        }

        // The cut end of a vessel: wall, a lip rolled outwards, and the first of the lumen inside it.
        ms.stump = b.revolve(&.{ .{ 1.0, -3.0 }, .{ 1.0, -0.3 }, .{ 1.07, -0.1 }, .{ 1.0, 0.0 }, .{ 0.84, -0.03 }, .{ 0.74, -0.16 }, .{ 0.70, -0.5 }, .{ 0.0, -0.5 } }, 22);

        // The floor away from the ulcer, under the tiles and up the folds on either side.
        {
            b.begin();
            const n: u32 = 38;
            const len = st.z_max + 600 - antrum_floor_z0;
            for (0..n + 1) |i| {
                const x = -1900 + 3800 * @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(n));
                const slope = (st.floorY(x + 1) - st.floorY(x - 1)) / 2;
                const nrm = m.v3(-slope, 1, 0).norm();
                _ = b.vert(m.v3(x, st.floorY(x), 0), nrm, x / cell, 0);
                _ = b.vert(m.v3(x, st.floorY(x), 1), nrm, x / cell, len * v_per);
            }
            for (0..n) |i| {
                const a: u32 = @intCast(i * 2);
                b.quad(a, a + 1, a + 3, a + 2);
            }
            ms.antrum_floor = b.end();
        }

        // The ulcer, on a polar grid about its centre so that rows follow the edge: the bed in one mesh,
        // the wall of the crater with the heaped rim and the mucosa outside it in the other.
        {
            const Ring = struct {
                fn radius(j: usize) f32 {
                    // coarse over the bed, 20 µm rows across the crater wall and the rim, coarse outside
                    if (j <= 24) return 250 + 100 * @as(f32, @floatFromInt(j));
                    if (j <= 56) return 2650 + 20 * @as(f32, @floatFromInt(j - 24));
                    return 3290 + 150 * @as(f32, @floatFromInt(j - 56));
                }
            };
            const cols: u32 = 96;
            const half_angle: f32 = 1.4;
            const split: usize = 28; // 270 µm inside the edge, where the wall meets the bed
            inline for (.{ [2]usize{ 0, split }, [2]usize{ split, 62 } }, 0..) |span, which| {
                b.begin();
                for (span[0]..span[1] + 1) |j| {
                    const rad = Ring.radius(j);
                    for (0..cols + 1) |i| {
                        const th = -half_angle + 2 * half_angle * @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(cols));
                        const x = rad * @sin(th);
                        const z = rad * @cos(th);
                        const u = th * st.ulcer_r;
                        if (which == 0) {
                            _ = b.vert(m.v3(x, st.surfaceY(x, z), z), m.v3(0, 1, 0), u / 400.0, rad / 400.0);
                        } else {
                            // outside the rim the tiles lie on top of this, so it sits a hair under them
                            const sink = 1.5 * m.smoothstep(260, 300, -st.into(x, z));
                            _ = b.vert(m.v3(x, st.surfaceY(x, z) - sink, z), m.v3(0, 1, 0), u / cell, rad * v_per);
                        }
                    }
                }
                for (0..span[1] - span[0]) |j| {
                    for (0..cols) |i| {
                        const a: u32 = @intCast(j * (cols + 1) + i);
                        b.quad(a, a + 1, a + cols + 2, a + cols + 1);
                    }
                }
                b.smoothNormals(false);
                if (which == 0) ms.ulcer_bed = b.end() else ms.ulcer_rim = b.end();
            }
        }

        // The top of the gel. Its first row lies on the line where the gel runs out, short of the rim.
        {
            b.begin();
            const nx: u32 = 38;
            const nz: u32 = 36;
            const edge = st.ulcer_r + 215;
            for (0..nz + 1) |j| {
                const t = std.math.pow(f32, @as(f32, @floatFromInt(j)) / @as(f32, @floatFromInt(nz)), 1.7);
                for (0..nx + 1) |i| {
                    const x = -1900 + 3800 * @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(nx));
                    const z = m.lerp(@sqrt(edge * edge - x * x), st.z_max + 600, t);
                    const y = st.floorY(x) + st.mucus(x, z);
                    _ = b.vert(m.v3(x / gel_unit, y / gel_unit, z / gel_unit), m.v3(0, 1, 0), x / 300.0, z / 300.0);
                }
            }
            for (0..nz) |j| {
                for (0..nx) |i| {
                    const a: u32 = @intCast(j * (nx + 1) + i);
                    b.quad(a, a + 1, a + nx + 2, a + nx + 1);
                }
            }
            b.smoothNormals(false);
            ms.gel_sheet = b.end();
        }

        // A spiral rod: two turns about +Y, tapered at both ends.
        {
            b.begin();
            const Ctx = struct {
                pub fn at(_: @This(), u: f32, v: f32) Vec3 {
                    const turns = 2.0 * m.tau;
                    const len: f32 = 3.2;
                    const coil: f32 = 0.42;
                    const ph = v * turns;
                    const centre = m.v3(coil * @cos(ph), (v - 0.5) * len, coil * @sin(ph));
                    const tangent = m.v3(-coil * turns * @sin(ph), len, coil * turns * @cos(ph)).norm();
                    const out = m.v3(@cos(ph), 0, @sin(ph));
                    const side = tangent.cross(out).norm();
                    const thick = 0.3 * @sqrt(@max(0, @sin(m.pi * m.clamp(v, 0.02, 0.98))));
                    const a = u * m.tau;
                    return centre.add(out.scale(@cos(a) * thick)).add(side.scale(@sin(a) * thick));
                }
            };
            b.grid(8, 22, Ctx{}, false, .{ 1, 1 });
            b.smoothNormals(false);
            ms.helix = b.end();
        }
    }

    fn domeProfile() [10][2]f32 {
        var p: [10][2]f32 = undefined;
        for (0..10) |j| {
            const a = m.pi / 2.0 * (1.0 - @as(f32, @floatFromInt(j)) / 9.0);
            p[j] = .{ @sin(a), @cos(a) };
        }
        // listed from the rim (r=1,y=0) up to the pole
        return p;
    }

    fn capsuleProfile() [14][2]f32 {
        var p: [14][2]f32 = undefined;
        for (0..7) |j| {
            const a = m.pi / 2.0 * @as(f32, @floatFromInt(j)) / 6.0;
            p[j] = .{ @sin(a) * 0.5, -0.5 - @cos(a) * 0.5 };
            p[13 - j] = .{ @sin(a) * 0.5, 0.5 + @cos(a) * 0.5 };
        }
        return p;
    }

    /// Cone with a helical flute, tip at +Y.
    fn drillBit(b: *mesh_mod.Builder) gpu.Mesh {
        b.begin();
        const Ctx = struct {
            pub fn at(_: @This(), u: f32, v: f32) Vec3 {
                const a = u * m.tau;
                const taper = 1.0 - v * 0.96;
                const flute = 1.0 + 0.22 * @sin(a * 2.0 + v * 14.0);
                const r = taper * flute;
                return m.v3(r * @cos(a), v, r * @sin(a));
            }
        };
        b.grid(28, 22, Ctx{}, false, .{ 1, 1 });
        b.smoothNormals(false);
        return b.end();
    }
};

/// Line height of a paragraph, in units of the type size.
pub const line_spacing: f32 = 1.28;

pub fn widthOf(f: *const font_mod.Font, face: font_mod.Face, size: f32, s: []const u8) f32 {
    const k = size / font_mod.base_px;
    var w: f32 = 0;
    var i: usize = 0;
    while (i < s.len) {
        w += f.glyph(face, utf8.next(s, &i)).adv * k;
    }
    return w;
}

/// The lines of a word-wrapped paragraph, one per call. The text is wrapped whole; each line is returned
/// cut off at `shown` bytes into the text, so lines past that point come back empty. A line breaks at a
/// space when the next word would pass `max_w`, never directly before a dash, and always at a newline.
pub const Lines = struct {
    font: *const font_mod.Font,
    face: font_mod.Face,
    size: f32,
    max_w: f32,
    text: []const u8,
    /// How much of `text` is visible, in bytes.
    shown: usize,
    start: usize = 0,

    pub fn next(it: *Lines) ?[]const u8 {
        const s = it.text;
        if (it.start >= s.len) return null;
        const start = it.start;
        var stop = start;
        var last_break: ?usize = null;
        while (stop < s.len and s[stop] != '\n') {
            if (utf8.breakable(s, stop)) {
                if (widthOf(it.font, it.face, it.size, s[start..stop]) > it.max_w) break;
                last_break = stop;
            }
            stop += 1;
        }
        var cut = stop;
        if (widthOf(it.font, it.face, it.size, s[start..stop]) > it.max_w) {
            if (last_break) |lb| cut = lb;
        }
        var resume_at = cut;
        while (resume_at < s.len and (s[resume_at] == ' ' or s[resume_at] == '\n')) {
            resume_at += 1;
            if (s[resume_at - 1] == '\n') break;
        }
        // A line the width cannot break (one word wider than the box) still has to end.
        it.start = if (resume_at > start) resume_at else s.len;
        return s[start..@max(start, @min(cut, it.shown))];
    }
};

pub const Renderer = struct {
    g: *gpu.Gpu,
    font: font_mod.Font,
    meshes: Meshes,
    batches: [gpu.max_batches]gpu.Batch = undefined,
    nb: usize = 0,
    ninst: u32 = 0,
    ndyn: u32 = 0,
    npart: u32 = 0,
    nhud: u32 = 0,
    /// Pixels per HUD unit; the HUD is laid out on a canvas 900 units high.
    ui: f32 = 1,
    ui_w: f32 = 1600,
    ui_h: f32 = 900,
    cam_right: Vec3 = m.v3(1, 0, 0),
    cam_up: Vec3 = m.v3(0, 1, 0),
    cam_pos: Vec3 = .{},

    pub fn begin(r: *Renderer) void {
        r.nb = 0;
        r.ninst = 0;
        r.ndyn = 0;
        r.npart = 0;
        r.nhud = 0;
        r.ui = @as(f32, @floatFromInt(r.g.height)) / 900.0;
        r.ui_h = 900;
        r.ui_w = @as(f32, @floatFromInt(r.g.width)) / r.ui;
    }

    fn instance(r: *Renderer, model: Mat4, st: Style) ?u32 {
        if (r.ninst >= gpu.max_instances) return null;
        r.g.instances[r.ninst] = .{ .model = model.m, .color = st.color, .params = .{ @floatFromInt(@intFromEnum(st.mat)), st.emissive, st.seed, st.anim } };
        r.ninst += 1;
        return r.ninst - 1;
    }

    pub fn draw(r: *Renderer, mesh: gpu.Mesh, pass: gpu.Pass, model: Mat4, st: Style) void {
        const i = r.instance(model, st) orelse return;
        if (r.nb > 0) {
            const last = &r.batches[r.nb - 1];
            if (!last.dynamic and last.pass == pass and last.mesh.index_start == mesh.index_start and last.mesh.base_vertex == mesh.base_vertex and last.first_instance + last.instance_count == i) {
                last.instance_count += 1;
                return;
            }
        }
        if (r.nb >= gpu.max_batches) return;
        r.batches[r.nb] = .{ .pass = pass, .mesh = mesh, .first_instance = i, .instance_count = 1 };
        r.nb += 1;
    }

    /// Reserve `n` vertices (a triangle list) of per-frame geometry drawn with an identity transform.
    pub fn dynamic(r: *Renderer, n: u32, pass: gpu.Pass, st: Style) ?[]gpu.Vertex {
        if (r.ndyn + n > gpu.max_dyn_verts or r.nb >= gpu.max_batches) return null;
        const i = r.instance(Mat4.identity, st) orelse return null;
        r.batches[r.nb] = .{ .pass = pass, .dynamic = true, .vertex_start = r.ndyn, .vertex_count = n, .first_instance = i, .instance_count = 1 };
        r.nb += 1;
        const out = r.g.dyn_verts[r.ndyn .. r.ndyn + n];
        r.ndyn += n;
        return out;
    }

    /// Camera-facing additive glow.
    pub fn particle(r: *Renderer, pos: Vec3, size: f32, color: Color) void {
        if (r.npart + 6 > gpu.max_part_verts) return;
        const rx = r.cam_right.scale(size);
        const uy = r.cam_up.scale(size);
        r.partQuad(pos.sub(rx).sub(uy), pos.add(rx).sub(uy), pos.add(rx).add(uy), pos.sub(rx).add(uy), color);
    }

    /// Additive streak from `a` to `b`, `width` across, facing the camera.
    pub fn streak(r: *Renderer, a: Vec3, b: Vec3, width: f32, color: Color) void {
        if (r.npart + 6 > gpu.max_part_verts) return;
        const d = b.sub(a);
        const side = d.cross(r.cam_pos.sub(a)).norm().scale(width);
        const ext = d.norm().scale(width);
        r.partQuad(a.sub(side).sub(ext), b.sub(side).add(ext), b.add(side).add(ext), a.add(side).sub(ext), color);
    }

    fn partQuad(r: *Renderer, p0: Vec3, p1: Vec3, p2: Vec3, p3: Vec3, color: Color) void {
        const o = r.g.part_verts[r.npart .. r.npart + 6];
        const ps = [6]Vec3{ p0, p1, p2, p0, p2, p3 };
        const uvs = [6][2]f32{ .{ -1, -1 }, .{ 1, -1 }, .{ 1, 1 }, .{ -1, -1 }, .{ 1, 1 }, .{ -1, 1 } };
        for (0..6) |i| o[i] = .{ .pos = .{ ps[i].x, ps[i].y, ps[i].z }, .uv = uvs[i], .color = color };
        r.npart += 6;
    }

    // ---- HUD (units: 900-high canvas, origin top left) ----

    fn hudQuad(r: *Renderer, x0: f32, y0: f32, x1: f32, y1: f32, x2: f32, y2: f32, x3: f32, y3: f32, uv: [4][2]f32, color: Color) void {
        if (r.nhud + 6 > gpu.max_hud_verts) return;
        const o = r.g.hud_verts[r.nhud .. r.nhud + 6];
        const s = r.ui;
        const ps = [4][2]f32{ .{ x0 * s, y0 * s }, .{ x1 * s, y1 * s }, .{ x2 * s, y2 * s }, .{ x3 * s, y3 * s } };
        const order = [6]usize{ 0, 1, 2, 0, 2, 3 };
        for (order, 0..) |k, i| o[i] = .{ .pos = ps[k], .uv = uv[k], .color = color };
        r.nhud += 6;
    }

    const solid_uv = [4][2]f32{ .{ -1, 0 }, .{ -1, 0 }, .{ -1, 0 }, .{ -1, 0 } };

    pub fn rect(r: *Renderer, x: f32, y: f32, w: f32, h: f32, color: Color) void {
        r.hudQuad(x, y, x + w, y, x + w, y + h, x, y + h, solid_uv, color);
    }

    pub fn frame(r: *Renderer, x: f32, y: f32, w: f32, h: f32, t: f32, color: Color) void {
        r.rect(x, y, w, t, color);
        r.rect(x, y + h - t, w, t, color);
        r.rect(x, y + t, t, h - 2 * t, color);
        r.rect(x + w - t, y + t, t, h - 2 * t, color);
    }

    pub fn line(r: *Renderer, x0: f32, y0: f32, x1: f32, y1: f32, t: f32, color: Color) void {
        const dx = x1 - x0;
        const dy = y1 - y0;
        const l = @max(@sqrt(dx * dx + dy * dy), 1e-5);
        const nx = -dy / l * t * 0.5;
        const ny = dx / l * t * 0.5;
        r.hudQuad(x0 + nx, y0 + ny, x1 + nx, y1 + ny, x1 - nx, y1 - ny, x0 - nx, y0 - ny, solid_uv, color);
    }

    /// Arc of a ring centred at (cx, cy) between angles a0 and a1 (radians, 0 = right, clockwise on screen).
    pub fn arc(r: *Renderer, cx: f32, cy: f32, radius: f32, a0: f32, a1: f32, t: f32, color: Color) void {
        // One annular strip with shared edges, so thick arcs have no seams between segments.
        const n: usize = @max(2, @as(usize, @intFromFloat(@abs(a1 - a0) * @max(10.0, radius * 0.3))));
        const ri = @max(0, radius - t * 0.5);
        const ro = radius + t * 0.5;
        var pc = @cos(a0);
        var ps = @sin(a0);
        for (1..n + 1) |i| {
            const a = a0 + (a1 - a0) * @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(n));
            const c = @cos(a);
            const sn = @sin(a);
            r.hudQuad(cx + pc * ro, cy + ps * ro, cx + c * ro, cy + sn * ro, cx + c * ri, cy + sn * ri, cx + pc * ri, cy + ps * ri, solid_uv, color);
            pc = c;
            ps = sn;
        }
    }

    pub fn textWidth(r: *Renderer, face: font_mod.Face, size: f32, s: []const u8) f32 {
        return widthOf(&r.font, face, size, s);
    }

    /// Draw one line of text with its top at `y`. Returns the advance width.
    pub fn text(r: *Renderer, face: font_mod.Face, x: f32, y: f32, size: f32, color: Color, s: []const u8) f32 {
        const k = size / font_mod.base_px;
        const base = y + r.font.ascent * k;
        var pen = x;
        var i: usize = 0;
        while (i < s.len) {
            const gl = r.font.glyph(face, utf8.next(s, &i));
            if (gl.w > 0) {
                const x0 = pen + gl.ox * k;
                const y0 = base + gl.oy * k;
                const x1 = x0 + gl.w * k;
                const y1 = y0 + gl.h * k;
                r.hudQuad(x0, y0, x1, y0, x1, y1, x0, y1, .{ .{ gl.u0, gl.v0 }, .{ gl.u1, gl.v0 }, .{ gl.u1, gl.v1 }, .{ gl.u0, gl.v1 } }, color);
            }
            pen += gl.adv * k;
        }
        return pen - x;
    }

    pub fn textCentered(r: *Renderer, face: font_mod.Face, cx: f32, y: f32, size: f32, color: Color, s: []const u8) void {
        _ = r.text(face, cx - r.textWidth(face, size, s) * 0.5, y, size, color, s);
    }

    pub fn textRight(r: *Renderer, face: font_mod.Face, right: f32, y: f32, size: f32, color: Color, s: []const u8) void {
        _ = r.text(face, right - r.textWidth(face, size, s), y, size, color, s);
    }

    /// Word-wrapped paragraph; a dash stays on the line of the word before it. Returns the y below the last
    /// line.
    pub fn paragraph(r: *Renderer, face: font_mod.Face, x: f32, y: f32, max_w: f32, size: f32, color: Color, s: []const u8) f32 {
        return r.paragraphRevealed(face, x, y, max_w, size, color, s, s.len);
    }

    /// `paragraph` for text that types itself out: the whole of `s` is laid out, and of that layout only
    /// the first `shown` bytes are drawn. Every word is therefore on its final line from its first letter.
    /// Wrapping only what has been typed so far would put a word at the end of a line and move it to the
    /// next when it grew too long for it. Returns the y below the last line of the whole paragraph.
    pub fn paragraphRevealed(r: *Renderer, face: font_mod.Face, x: f32, y: f32, max_w: f32, size: f32, color: Color, s: []const u8, shown: usize) f32 {
        var line_y = y;
        var lines: Lines = .{ .font = &r.font, .face = face, .size = size, .max_w = max_w, .text = s, .shown = shown };
        while (lines.next()) |visible| {
            if (visible.len > 0) _ = r.text(face, x, line_y, size, color, visible);
            line_y += size * line_spacing;
        }
        return line_y;
    }

    /// Height `paragraph` would use.
    pub fn paragraphHeight(r: *Renderer, face: font_mod.Face, max_w: f32, size: f32, s: []const u8) f32 {
        const saved = r.nhud;
        const y = r.paragraph(face, 0, 0, max_w, size, .{ 0, 0, 0, 0 }, s);
        r.nhud = saved;
        return y;
    }

    pub fn end(r: *Renderer, scene: gpu.Frame, arm: gpu.Frame, post: gpu.Post, wait: bool) bool {
        return r.g.submit(&.{ .scene = scene, .arm = arm, .post = post, .batches = r.batches[0..r.nb], .instance_count = r.ninst, .dyn_count = r.ndyn, .part_count = r.npart, .hud_count = r.nhud }, wait);
    }
};

test "a paragraph that types itself out never moves a word once it has appeared" {
    const strings = @import("strings.zig");
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const font = try font_mod.Font.build(arena.allocator());
    // The subtitle box, and a line long enough to wrap several times, in each language.
    const size: f32 = 20;
    const max_w: f32 = 760;
    var moved_before_the_fix: usize = 0;
    inline for (.{ strings.line.each_arm_carries_three_tools.en, strings.line.each_arm_carries_three_tools.uk, strings.briefing.pages[1].uk }) |text| {
        // The final layout: where each byte of the text ends up.
        var final_line: [1024]u16 = undefined;
        var final_starts: [32]usize = undefined;
        var count: usize = 0;
        var whole: Lines = .{ .font = &font, .face = .regular, .size = size, .max_w = max_w, .text = text, .shown = text.len };
        while (whole.next()) |line| : (count += 1) {
            const at = @intFromPtr(line.ptr) - @intFromPtr(text.ptr);
            final_starts[count] = at;
            for (at..at + line.len) |i| final_line[i] = @intCast(count);
            try std.testing.expect(widthOf(&font, .regular, size, line) <= max_w);
        }
        try std.testing.expect(count >= 3);

        var shown: usize = 0;
        while (shown <= text.len) : (shown += 1) {
            if (shown < text.len and (text[shown] & 0xC0) == 0x80) continue; // inside a code point
            // What is drawn with `shown` bytes revealed: every visible line starts where the final layout
            // starts that line and is a prefix of it, so no letter is ever on a line it will later leave.
            var partial: Lines = .{ .font = &font, .face = .regular, .size = size, .max_w = max_w, .text = text, .shown = shown };
            var n: usize = 0;
            var drawn: usize = 0;
            while (partial.next()) |line| : (n += 1) {
                if (line.len == 0) continue;
                const at = @intFromPtr(line.ptr) - @intFromPtr(text.ptr);
                try std.testing.expectEqual(final_starts[n], at);
                try std.testing.expect(at + line.len <= shown);
                drawn = at + line.len;
            }
            try std.testing.expectEqual(count, n);
            // Everything revealed so far is drawn, up to the spaces a line break swallows.
            try std.testing.expect(std.mem.trim(u8, text[drawn..shown], " \n").len == 0);

            // The way it was done before: wrap only the revealed prefix. Count the moments at which that
            // puts a letter on a line other than its final one, to show this text does exercise the case.
            var naive: Lines = .{ .font = &font, .face = .regular, .size = size, .max_w = max_w, .text = text[0..shown], .shown = shown };
            var k: usize = 0;
            var jumped = false;
            while (naive.next()) |line| : (k += 1) {
                if (line.len == 0) continue;
                const at = @intFromPtr(line.ptr) - @intFromPtr(text.ptr);
                if (final_line[at + line.len - 1] != k) jumped = true;
            }
            if (jumped) moved_before_the_fix += 1;
        }
    }
    try std.testing.expect(moved_before_the_fix > 0);
}
