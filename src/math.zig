const std = @import("std");

pub const pi: f32 = 3.14159265358979;
pub const tau: f32 = 6.28318530717958;

pub const Vec3 = extern struct {
    x: f32 = 0,
    y: f32 = 0,
    z: f32 = 0,

    pub const zero: Vec3 = .{};
    pub const up: Vec3 = .{ .y = 1 };

    pub fn init(x: f32, y: f32, z: f32) Vec3 {
        return .{ .x = x, .y = y, .z = z };
    }
    pub fn add(a: Vec3, b: Vec3) Vec3 {
        return .{ .x = a.x + b.x, .y = a.y + b.y, .z = a.z + b.z };
    }
    pub fn sub(a: Vec3, b: Vec3) Vec3 {
        return .{ .x = a.x - b.x, .y = a.y - b.y, .z = a.z - b.z };
    }
    pub fn scale(a: Vec3, s: f32) Vec3 {
        return .{ .x = a.x * s, .y = a.y * s, .z = a.z * s };
    }
    pub fn mul(a: Vec3, b: Vec3) Vec3 {
        return .{ .x = a.x * b.x, .y = a.y * b.y, .z = a.z * b.z };
    }
    pub fn dot(a: Vec3, b: Vec3) f32 {
        return a.x * b.x + a.y * b.y + a.z * b.z;
    }
    pub fn cross(a: Vec3, b: Vec3) Vec3 {
        return .{ .x = a.y * b.z - a.z * b.y, .y = a.z * b.x - a.x * b.z, .z = a.x * b.y - a.y * b.x };
    }
    pub fn len(a: Vec3) f32 {
        return @sqrt(a.dot(a));
    }
    pub fn len2(a: Vec3) f32 {
        return a.dot(a);
    }
    pub fn dist(a: Vec3, b: Vec3) f32 {
        return a.sub(b).len();
    }
    pub fn norm(a: Vec3) Vec3 {
        const l = a.len();
        if (l < 1e-12) return .{ .z = 1 };
        return a.scale(1.0 / l);
    }
    pub fn lerp(a: Vec3, b: Vec3, t: f32) Vec3 {
        return a.add(b.sub(a).scale(t));
    }
    pub fn neg(a: Vec3) Vec3 {
        return .{ .x = -a.x, .y = -a.y, .z = -a.z };
    }
    /// Any unit vector perpendicular to `a`.
    pub fn perp(a: Vec3) Vec3 {
        const o: Vec3 = if (@abs(a.y) < 0.9) .{ .y = 1 } else .{ .x = 1 };
        return a.cross(o).norm();
    }
};

pub fn v3(x: f32, y: f32, z: f32) Vec3 {
    return .{ .x = x, .y = y, .z = z };
}

pub const Vec4 = extern struct {
    x: f32 = 0,
    y: f32 = 0,
    z: f32 = 0,
    w: f32 = 0,
};

pub fn v4(x: f32, y: f32, z: f32, w: f32) Vec4 {
    return .{ .x = x, .y = y, .z = z, .w = w };
}

/// Column-major 4x4, column vectors, right-handed, clip z in [0,1] (Metal).
pub const Mat4 = extern struct {
    m: [16]f32,

    pub const identity: Mat4 = .{ .m = .{ 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1 } };

    pub fn mul(a: Mat4, b: Mat4) Mat4 {
        var r: Mat4 = undefined;
        for (0..4) |c| {
            for (0..4) |row| {
                var s: f32 = 0;
                for (0..4) |k| s += a.m[k * 4 + row] * b.m[c * 4 + k];
                r.m[c * 4 + row] = s;
            }
        }
        return r;
    }

    pub fn translation(t: Vec3) Mat4 {
        var r = identity;
        r.m[12] = t.x;
        r.m[13] = t.y;
        r.m[14] = t.z;
        return r;
    }

    pub fn scaling(s: Vec3) Mat4 {
        var r = identity;
        r.m[0] = s.x;
        r.m[5] = s.y;
        r.m[10] = s.z;
        return r;
    }

    /// Columns are the basis vectors `x`, `y`, `z` and the origin `t`.
    pub fn fromBasis(x: Vec3, y: Vec3, z: Vec3, t: Vec3) Mat4 {
        return .{ .m = .{ x.x, x.y, x.z, 0, y.x, y.y, y.z, 0, z.x, z.y, z.z, 0, t.x, t.y, t.z, 1 } };
    }

    pub fn rotation(axis_in: Vec3, angle: f32) Mat4 {
        const a = axis_in.norm();
        const c = @cos(angle);
        const s = @sin(angle);
        const t = 1 - c;
        return .{ .m = .{
            t * a.x * a.x + c,       t * a.x * a.y + s * a.z, t * a.x * a.z - s * a.y, 0,
            t * a.x * a.y - s * a.z, t * a.y * a.y + c,       t * a.y * a.z + s * a.x, 0,
            t * a.x * a.z + s * a.y, t * a.y * a.z - s * a.x, t * a.z * a.z + c,       0,
            0,                       0,                       0,                       1,
        } };
    }

    pub fn perspective(fovy: f32, aspect: f32, near: f32, far: f32) Mat4 {
        const f = 1.0 / @tan(fovy * 0.5);
        var r: Mat4 = .{ .m = @splat(0) };
        r.m[0] = f / aspect;
        r.m[5] = f;
        r.m[10] = far / (near - far);
        r.m[11] = -1;
        r.m[14] = near * far / (near - far);
        return r;
    }

    /// View matrix for a camera at `eye` with orthonormal right/up/back axes.
    pub fn view(eye: Vec3, right: Vec3, upv: Vec3, back: Vec3) Mat4 {
        return .{ .m = .{
            right.x,         upv.x,         back.x,         0,
            right.y,         upv.y,         back.y,         0,
            right.z,         upv.z,         back.z,         0,
            -right.dot(eye), -upv.dot(eye), -back.dot(eye), 1,
        } };
    }

    pub fn point(a: Mat4, p: Vec3) Vec3 {
        return .{
            .x = a.m[0] * p.x + a.m[4] * p.y + a.m[8] * p.z + a.m[12],
            .y = a.m[1] * p.x + a.m[5] * p.y + a.m[9] * p.z + a.m[13],
            .z = a.m[2] * p.x + a.m[6] * p.y + a.m[10] * p.z + a.m[14],
        };
    }

    pub fn dir(a: Mat4, p: Vec3) Vec3 {
        return .{
            .x = a.m[0] * p.x + a.m[4] * p.y + a.m[8] * p.z,
            .y = a.m[1] * p.x + a.m[5] * p.y + a.m[9] * p.z,
            .z = a.m[2] * p.x + a.m[6] * p.y + a.m[10] * p.z,
        };
    }

    /// Translate, orient so local +Y points along `yaxis`, scale.
    pub fn place(pos: Vec3, yaxis: Vec3, s: Vec3) Mat4 {
        const y = yaxis.norm();
        const x = y.perp();
        const z = x.cross(y);
        return fromBasis(x.scale(s.x), y.scale(s.y), z.scale(s.z), pos);
    }

    pub fn trs(pos: Vec3, axis: Vec3, angle: f32, s: f32) Mat4 {
        var r = rotation(axis, angle);
        for (0..12) |i| r.m[i] *= s;
        r.m[12] = pos.x;
        r.m[13] = pos.y;
        r.m[14] = pos.z;
        return r;
    }
};

pub fn clamp(x: f32, lo: f32, hi: f32) f32 {
    return @max(lo, @min(hi, x));
}

pub fn sat(x: f32) f32 {
    return clamp(x, 0, 1);
}

pub fn lerp(a: f32, b: f32, t: f32) f32 {
    return a + (b - a) * t;
}

pub fn smoothstep(e0: f32, e1: f32, x: f32) f32 {
    const t = sat((x - e0) / (e1 - e0));
    return t * t * (3 - 2 * t);
}

/// Exponential approach of `cur` to `target`, frame-rate independent.
pub fn approach(cur: f32, target: f32, rate: f32, dt: f32) f32 {
    return target + (cur - target) * @exp(-rate * dt);
}

pub const Rng = struct {
    s: u64,

    pub fn init(seed: u64) Rng {
        return .{ .s = seed *% 0x9E3779B97F4A7C15 +% 0x1234567 };
    }
    pub fn next(r: *Rng) u32 {
        r.s ^= r.s << 13;
        r.s ^= r.s >> 7;
        r.s ^= r.s << 17;
        return @truncate(r.s >> 16);
    }
    /// Uniform in [0,1).
    pub fn f(r: *Rng) f32 {
        return @as(f32, @floatFromInt(r.next() >> 8)) / 16777216.0;
    }
    pub fn range(r: *Rng, lo: f32, hi: f32) f32 {
        return lo + (hi - lo) * r.f();
    }
    /// Uniform on the unit sphere.
    pub fn dir(r: *Rng) Vec3 {
        const z = r.range(-1, 1);
        const a = r.range(0, tau);
        const q = @sqrt(@max(0, 1 - z * z));
        return .{ .x = q * @cos(a), .y = q * @sin(a), .z = z };
    }
    pub fn below(r: *Rng, n: u32) u32 {
        return r.next() % n;
    }
};

test "perspective maps near and far to 0 and 1" {
    const p = Mat4.perspective(1.0, 1.5, 2.0, 100.0);
    const n = p.m[10] * -2.0 + p.m[14];
    const fz = p.m[10] * -100.0 + p.m[14];
    try std.testing.expectApproxEqAbs(@as(f32, 0), n / 2.0, 1e-5);
    try std.testing.expectApproxEqAbs(@as(f32, 1), fz / 100.0, 1e-5);
}

test "place orients +Y" {
    const m = Mat4.place(v3(1, 2, 3), v3(0, 0, 1), v3(1, 2, 1));
    const p = m.point(v3(0, 1, 0));
    try std.testing.expectApproxEqAbs(@as(f32, 5), p.z, 1e-5);
}
