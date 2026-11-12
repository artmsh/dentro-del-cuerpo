//! Procedural meshes. Everything in the game is generated here or by a chapter; there are no model files.

const std = @import("std");
const m = @import("math.zig");
const gpu = @import("gpu.zig");
const Vec3 = m.Vec3;
const v3 = m.v3;
const Vertex = gpu.Vertex;
const Mesh = gpu.Mesh;

pub const Builder = struct {
    gpa: std.mem.Allocator,
    verts: std.ArrayList(Vertex) = .empty,
    indices: std.ArrayList(u32) = .empty,
    base: u32 = 0,
    index_start: u32 = 0,

    pub fn init(gpa: std.mem.Allocator) Builder {
        return .{ .gpa = gpa };
    }

    pub fn begin(b: *Builder) void {
        b.base = @intCast(b.verts.items.len);
        b.index_start = @intCast(b.indices.items.len);
    }

    pub fn end(b: *Builder) Mesh {
        return .{ .index_start = b.index_start, .index_count = @as(u32, @intCast(b.indices.items.len)) - b.index_start, .base_vertex = b.base };
    }

    /// Returns the vertex index local to the mesh being built.
    pub fn vert(b: *Builder, p: Vec3, n: Vec3, u: f32, v: f32) u32 {
        b.verts.append(b.gpa, .{ .pos = .{ p.x, p.y, p.z }, .nrm = .{ n.x, n.y, n.z }, .uv = .{ u, v } }) catch @panic("oom");
        return @as(u32, @intCast(b.verts.items.len)) - 1 - b.base;
    }

    pub fn tri(b: *Builder, a: u32, c: u32, d: u32) void {
        b.indices.appendSlice(b.gpa, &.{ a, c, d }) catch @panic("oom");
    }

    pub fn quad(b: *Builder, a: u32, c: u32, d: u32, e: u32) void {
        b.tri(a, c, d);
        b.tri(a, d, e);
    }

    fn count(b: *Builder) u32 {
        return @as(u32, @intCast(b.verts.items.len)) - b.base;
    }

    /// Replace the normals of the mesh being built with area-weighted smooth normals.
    pub fn smoothNormals(b: *Builder, flip: bool) void {
        const vs = b.verts.items[b.base..];
        for (vs) |*v| v.nrm = .{ 0, 0, 0 };
        const is = b.indices.items[b.index_start..];
        var i: usize = 0;
        while (i + 2 < is.len) : (i += 3) {
            const a = vs[is[i]].pos;
            const c = vs[is[i + 1]].pos;
            const d = vs[is[i + 2]].pos;
            const n = v3(c[0] - a[0], c[1] - a[1], c[2] - a[2]).cross(v3(d[0] - a[0], d[1] - a[1], d[2] - a[2]));
            for (0..3) |k| {
                const p = &vs[is[i + k]].nrm;
                p[0] += n.x;
                p[1] += n.y;
                p[2] += n.z;
            }
        }
        for (vs) |*v| {
            var n = v3(v.nrm[0], v.nrm[1], v.nrm[2]).norm();
            if (flip) n = n.neg();
            v.nrm = .{ n.x, n.y, n.z };
        }
    }

    /// Weld normals across a seam: vertices at the same position share the summed normal.
    fn weldSeam(b: *Builder, nu: u32, nv: u32) void {
        const vs = b.verts.items[b.base..];
        for (0..nv + 1) |j| {
            const a = &vs[j * (nu + 1)];
            const c = &vs[j * (nu + 1) + nu];
            const n = v3(a.nrm[0] + c.nrm[0], a.nrm[1] + c.nrm[1], a.nrm[2] + c.nrm[2]).norm();
            a.nrm = .{ n.x, n.y, n.z };
            c.nrm = a.nrm;
        }
    }

    /// Grid of (nu+1) x (nv+1) vertices from `ctx.at(u, v)` with u, v in [0,1]; u is assumed to wrap.
    pub fn grid(b: *Builder, nu: u32, nv: u32, ctx: anytype, flip: bool, uv_scale: [2]f32) void {
        const first = b.count();
        for (0..nv + 1) |j| {
            for (0..nu + 1) |i| {
                const u = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(nu));
                const v = @as(f32, @floatFromInt(j)) / @as(f32, @floatFromInt(nv));
                _ = b.vert(ctx.at(u, v), v3(0, 1, 0), u * uv_scale[0], v * uv_scale[1]);
            }
        }
        for (0..nv) |j| {
            for (0..nu) |i| {
                const a = first + @as(u32, @intCast(j * (nu + 1) + i));
                const c = a + 1;
                const d = a + nu + 2;
                const e = a + nu + 1;
                if (flip) b.quad(a, e, d, c) else b.quad(a, c, d, e);
            }
        }
    }

    /// Surface of revolution about +Y from an (r, y) profile listed bottom to top.
    pub fn revolve(b: *Builder, profile: []const [2]f32, segs: u32) Mesh {
        b.begin();
        const n = profile.len;
        for (profile, 0..) |p, j| {
            const prev = profile[if (j == 0) 0 else j - 1];
            const next = profile[if (j + 1 == n) j else j + 1];
            const dr = next[0] - prev[0];
            const dy = next[1] - prev[1];
            const l = @max(@sqrt(dr * dr + dy * dy), 1e-6);
            var nr = dy / l;
            var ny = -dr / l;
            if (p[0] < 1e-5) { // on the axis the normal is the axis, or the pole shades as a pinch
                nr = 0;
                ny = if (ny != 0) std.math.sign(ny) else if (j == 0) @as(f32, -1) else 1;
            }
            for (0..segs + 1) |i| {
                const a = m.tau * @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(segs));
                const c = @cos(a);
                const s = @sin(a);
                _ = b.vert(v3(p[0] * c, p[1], p[0] * s), v3(nr * c, ny, nr * s), @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(segs)), @as(f32, @floatFromInt(j)) / @as(f32, @floatFromInt(n - 1)));
            }
        }
        for (0..n - 1) |j| {
            for (0..segs) |i| {
                const a: u32 = @intCast(j * (segs + 1) + i);
                b.quad(a, a + segs + 1, a + segs + 2, a + 1);
            }
        }
        return b.end();
    }

    pub fn sphere(b: *Builder, lat: u32, lon: u32) Mesh {
        var prof: [64][2]f32 = undefined;
        for (0..lat + 1) |j| {
            const a = m.pi * @as(f32, @floatFromInt(j)) / @as(f32, @floatFromInt(lat)) - m.pi / 2.0;
            prof[j] = .{ @cos(a), @sin(a) };
        }
        return b.revolve(prof[0 .. lat + 1], lon);
    }

    /// Sphere displaced by value noise; `amp` relative to the unit radius. `squash` scales Y.
    pub fn blob(b: *Builder, lat: u32, lon: u32, seed: f32, amp: f32, freq: f32, squash: f32) Mesh {
        b.begin();
        const Ctx = struct {
            seed: f32,
            amp: f32,
            freq: f32,
            squash: f32,
            pub fn at(c: @This(), u: f32, v: f32) Vec3 {
                const th = u * m.tau;
                const ph = v * m.pi;
                const d = v3(@sin(ph) * @cos(th), @cos(ph), @sin(ph) * @sin(th));
                const r = blobRadius(d, c.seed, c.amp, c.freq);
                return v3(d.x * r, d.y * r * c.squash, d.z * r);
            }
        };
        b.grid(lon, lat, Ctx{ .seed = seed, .amp = amp, .freq = freq, .squash = squash }, true, .{ 1, 1 });
        b.smoothNormals(false);
        b.weldSeam(lon, lat);
        return b.end();
    }

    /// Red cell: biconcave disc of unit radius in the XZ plane (Evans & Fung profile).
    pub fn redCell(b: *Builder, rings: u32, segs: u32) Mesh {
        var prof: [64][2]f32 = undefined;
        var n: usize = 0;
        // bottom face from the axis outward, then the top face back to the axis
        for (0..rings + 1) |j| {
            const r = @sin(m.pi / 2.0 * @as(f32, @floatFromInt(j)) / @as(f32, @floatFromInt(rings)));
            prof[n] = .{ r, -redCellHalfThickness(r) };
            n += 1;
        }
        var j: usize = rings;
        while (j > 0) {
            j -= 1;
            const r = @sin(m.pi / 2.0 * @as(f32, @floatFromInt(j)) / @as(f32, @floatFromInt(rings)));
            prof[n] = .{ r, redCellHalfThickness(r) };
            n += 1;
        }
        return b.revolve(prof[0..n], segs);
    }

    pub fn torus(b: *Builder, minor: f32, segs: u32, sides: u32) Mesh {
        b.begin();
        const Ctx = struct {
            minor: f32,
            pub fn at(c: @This(), u: f32, v: f32) Vec3 {
                const a = u * m.tau;
                const p = v * m.tau;
                const r = 1.0 + c.minor * @cos(p);
                return v3(r * @cos(a), c.minor * @sin(p), r * @sin(a));
            }
        };
        b.grid(segs, sides, Ctx{ .minor = minor }, true, .{ 8, 1 });
        b.smoothNormals(false);
        return b.end();
    }

    /// Several unit-ish spheres fused into one mesh: a staphylococcal "grape" cluster.
    pub fn cluster(b: *Builder, lobes: u32, seed: u64) Mesh {
        b.begin();
        var rng = m.Rng.init(seed);
        for (0..lobes) |k| {
            const centre = if (k == 0) Vec3.zero else rng.dir().scale(0.62);
            const rad = rng.range(0.42, 0.56);
            const first = b.count();
            const lat: u32 = 7;
            const lon: u32 = 10;
            for (0..lat + 1) |j| {
                const ph = m.pi * @as(f32, @floatFromInt(j)) / @as(f32, @floatFromInt(lat));
                for (0..lon + 1) |i| {
                    const th = m.tau * @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(lon));
                    const d = v3(@sin(ph) * @cos(th), @cos(ph), @sin(ph) * @sin(th));
                    _ = b.vert(centre.add(d.scale(rad)), d, 0, 0);
                }
            }
            for (0..lat) |j| {
                for (0..lon) |i| {
                    const a = first + @as(u32, @intCast(j * (lon + 1) + i));
                    b.quad(a, a + 1, a + lon + 2, a + lon + 1);
                }
            }
        }
        return b.end();
    }

    /// Axis-aligned box of half-extent 1.
    pub fn box(b: *Builder) Mesh {
        b.begin();
        const axes = [_][3]Vec3{
            .{ v3(1, 0, 0), v3(0, 1, 0), v3(0, 0, 1) },
            .{ v3(-1, 0, 0), v3(0, 0, 1), v3(0, 1, 0) },
            .{ v3(0, 1, 0), v3(0, 0, 1), v3(1, 0, 0) },
            .{ v3(0, -1, 0), v3(1, 0, 0), v3(0, 0, 1) },
            .{ v3(0, 0, 1), v3(1, 0, 0), v3(0, 1, 0) },
            .{ v3(0, 0, -1), v3(0, 1, 0), v3(1, 0, 0) },
        };
        for (axes) |ax| {
            const n = ax[0];
            const a = b.vert(n.sub(ax[1]).sub(ax[2]), n, 0, 0);
            const c = b.vert(n.add(ax[1]).sub(ax[2]), n, 1, 0);
            const d = b.vert(n.add(ax[1]).add(ax[2]), n, 1, 1);
            const e = b.vert(n.sub(ax[1]).add(ax[2]), n, 0, 1);
            b.quad(a, c, d, e);
        }
        return b.end();
    }
};

/// Shape parameters of the thrombus mesh; the game collides against the same function.
pub const clot_seed: f32 = 1.0;
pub const clot_amp: f32 = 0.2;
pub const clot_freq: f32 = 1.6;

/// Radius of `Builder.blob` along unit direction `d` (before squash), so collision can match the mesh.
pub fn blobRadius(d: Vec3, seed: f32, amp: f32, freq: f32) f32 {
    return 1.0 + amp * (fbm3(d.scale(freq).add(v3(seed, seed * 1.7, seed * 0.3))) * 2.0 - 1.0);
}

/// Half thickness of a red cell of unit radius at radial position r in [0,1].
pub fn redCellHalfThickness(r: f32) f32 {
    const r2 = r * r;
    return 0.5 * @sqrt(@max(0, 1 - r2)) * (0.207 + 2.003 * r2 - 1.123 * r2 * r2);
}

fn hash3(x: i32, y: i32, z: i32) f32 {
    var h: u32 = @bitCast(x *% 374761393 +% y *% 668265263 +% z *% 2147483647);
    h = (h ^ (h >> 13)) *% 1274126177;
    h ^= h >> 16;
    return @as(f32, @floatFromInt(h & 0xffffff)) / 16777216.0;
}

pub fn noise3(p: Vec3) f32 {
    const fx = @floor(p.x);
    const fy = @floor(p.y);
    const fz = @floor(p.z);
    const ix: i32 = @intFromFloat(fx);
    const iy: i32 = @intFromFloat(fy);
    const iz: i32 = @intFromFloat(fz);
    var tx = p.x - fx;
    var ty = p.y - fy;
    var tz = p.z - fz;
    tx = tx * tx * (3 - 2 * tx);
    ty = ty * ty * (3 - 2 * ty);
    tz = tz * tz * (3 - 2 * tz);
    const c000 = hash3(ix, iy, iz);
    const c100 = hash3(ix + 1, iy, iz);
    const c010 = hash3(ix, iy + 1, iz);
    const c110 = hash3(ix + 1, iy + 1, iz);
    const c001 = hash3(ix, iy, iz + 1);
    const c101 = hash3(ix + 1, iy, iz + 1);
    const c011 = hash3(ix, iy + 1, iz + 1);
    const c111 = hash3(ix + 1, iy + 1, iz + 1);
    return m.lerp(m.lerp(m.lerp(c000, c100, tx), m.lerp(c010, c110, tx), ty), m.lerp(m.lerp(c001, c101, tx), m.lerp(c011, c111, tx), ty), tz);
}

pub fn fbm3(p: Vec3) f32 {
    var a: f32 = 0.5;
    var s: f32 = 0;
    var q = p;
    for (0..4) |_| {
        s += a * noise3(q);
        q = q.scale(2.03).add(v3(7.1, 3.3, 1.7));
        a *= 0.5;
    }
    return s / 0.9375;
}

test "red cell is thinnest at the centre" {
    try std.testing.expect(redCellHalfThickness(0) < redCellHalfThickness(0.7));
    try std.testing.expectApproxEqAbs(@as(f32, 0), redCellHalfThickness(1), 1e-6);
}
