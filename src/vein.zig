//! Chapter 1 anatomy: a 3.6 mm great saphenous vein, modelled analytically so that the mesh, the collision,
//! the flow field and the guide's ray casts all read the same functions. Units are micrometres; +Z is
//! downstream (toward the heart), +Y is the skin side.

const std = @import("std");
const m = @import("math.zig");
const gpu = @import("gpu.zig");
const mesh = @import("mesh.zig");
const Vec3 = m.Vec3;
const v3 = m.v3;

pub const R0: f32 = 1800;
pub const z_min: f32 = -1500;
pub const z_max: f32 = 26400;
pub const z_exit: f32 = 25300;
/// Peak perceived core velocity (tempo link 1:100 of ~3 cm/s).
pub const core_speed: f32 = 300;
pub const pump_period: f32 = 7.0;

pub const Valve = struct {
    zb: f32,
    len: f32 = 2000,
    /// Openness of the +Y and -Y cusp, 0 = meeting on the midline, 1 = against the wall.
    open: [2]f32 = .{ 1, 1 },
    pinned: [2]bool = .{ false, false },

    pub fn top(v: *const Valve) f32 {
        return v.zb + v.len;
    }
};

pub const Needle = struct {
    tip: Vec3,
    dir: Vec3,
    e1: Vec3,
    e2: Vec3,
    pub const bore: f32 = 205;
    pub const outer: f32 = 360;
    pub const len: f32 = 3600;
    pub const bevel: f32 = 2.2;
    /// Axial coordinate past which the drone is out of the bore.
    pub const mouth: f32 = -700;

    pub fn axial(n: *const Needle, p: Vec3) f32 {
        return p.sub(n.tip).dot(n.dir);
    }
    pub fn radial(n: *const Needle, p: Vec3) Vec3 {
        const d = p.sub(n.tip);
        return d.sub(n.dir.scale(d.dot(n.dir)));
    }
    pub fn at(n: *const Needle, a: f32) Vec3 {
        return n.tip.add(n.dir.scale(a));
    }
};

pub const Septum = struct {
    z: f32 = 22200,
    hole_x: f32 = 260,
    hole_y: f32 = -340,
    hole_r: f32 = 190,
    corked: bool = true,
    pub const half_thick: f32 = 30;
};

pub const Hit = enum { wall, sinus, leaflet, needle, septum };

pub const RayHit = struct { t: f32, what: Hit, point: Vec3 };

pub const Local = struct { x: f32, y: f32, r: f32, theta: f32 };

/// Which side of each cusp (and of the septum) a body is on; carried between frames so thin surfaces hold.
pub const Sides = struct {
    cusp: [2][2]i8 = .{ .{ 0, 0 }, .{ 0, 0 } },
    septum: i8 = 0,
};

pub const Vein = struct {
    valves: [2]Valve = .{ .{ .zb = 4200 }, .{ .zb = 14500, .open = .{ 0, 1 }, .pinned = .{ true, false } } },
    septum: Septum = .{},
    needle: Needle = makeNeedle(),

    fn makeNeedle() Needle {
        const c = center(0);
        const dir = v3(0, -@sin(0.35), @cos(0.35)).norm();
        // e1 points to the deep side: the sharp tip is there and the bevel opens toward the skin.
        const e2 = v3(1, 0, 0);
        const e1 = e2.cross(dir).norm().scale(-1);
        return .{ .tip = v3(c.x, c.y + 700, 0), .dir = dir, .e1 = if (e1.y < 0) e1 else e1.neg(), .e2 = e2 };
    }

    pub fn center(z: f32) Vec3 {
        return v3(220 * @sin(z / 2900.0) + 90 * @sin(z / 1130.0 + 1.0), 160 * @sin(z / 3700.0 + 2.0), z);
    }

    pub fn tangent(z: f32) Vec3 {
        return v3(220.0 / 2900.0 * @cos(z / 2900.0) + 90.0 / 1130.0 * @cos(z / 1130.0 + 1.0), 160.0 / 3700.0 * @cos(z / 3700.0 + 2.0), 1).norm();
    }

    pub fn local(p: Vec3) Local {
        const c = center(p.z);
        const x = p.x - c.x;
        const y = p.y - c.y;
        return .{ .x = x, .y = y, .r = @sqrt(x * x + y * y), .theta = std.math.atan2(y, x) };
    }

    /// Sinus bulge amplitude at z (0 away from valves).
    pub fn bulgeAmp(vn: *const Vein, z: f32) f32 {
        var a: f32 = 0;
        for (&vn.valves) |*v| {
            a += 0.30 * m.smoothstep(v.zb, v.zb + 900, z) * (1 - m.smoothstep(v.top() - 100, v.top() + 900, z));
        }
        return a;
    }

    pub fn wallR(vn: *const Vein, z: f32, theta: f32) f32 {
        const ripple = 0.022 * @sin(3 * theta + z / 410.0) + 0.014 * @sin(5 * theta - z / 233.0 + 1.3) + 0.01 * @sin(z / 97.0 + 2 * theta);
        const s = @abs(@sin(theta));
        const bulge = vn.bulgeAmp(z) * s * @sqrt(@sqrt(s));
        const confluence = 1 + 0.9 * m.smoothstep(24500, 25900, z);
        return R0 * (1 + bulge + ripple) * confluence;
    }

    /// |y| of the wall above (sigma=+1) or below (sigma=-1) local x at z.
    fn wallY(vn: *const Vein, x: f32, z: f32, sigma: f32) f32 {
        var y = @sqrt(@max(R0 * R0 - x * x, 0));
        for (0..2) |_| {
            const rw = vn.wallR(z, std.math.atan2(sigma * y, x));
            y = @sqrt(@max(rw * rw - x * x, 0));
        }
        return y;
    }

    pub const cusp_half_width: f32 = 0.97 * R0;

    /// |y| of cusp `ci` (0 = +Y, 1 = -Y) of valve `vi` at local x and z, or null outside the cusp.
    pub fn cuspY(vn: *const Vein, vi: usize, ci: usize, x: f32, z: f32) ?f32 {
        const v = &vn.valves[vi];
        const u = x / cusp_half_width;
        if (@abs(u) >= 0.995) return null;
        const uu = u * u;
        const zbu = v.zb + v.len * 0.78 * uu * uu;
        const ztop = v.top();
        if (z < zbu or z > ztop) return null;
        const t = (z - zbu) / (ztop - zbu);
        const sigma: f32 = if (ci == 0) 1 else -1;
        const ybase = vn.wallY(x, zbu, sigma) - 3;
        const yfree = (0.004 + 0.62 * v.open[ci]) * R0 * @sqrt(1 - uu);
        return m.lerp(ybase, @min(yfree, ybase), std.math.pow(f32, t, 0.7));
    }

    /// Calf-pump cycle: forward surge, then a short reflux that shuts the valves. Returns the raw multiplier.
    pub fn pump(t: f32) f32 {
        const ph = @mod(t, pump_period) / pump_period;
        if (ph < 0.62) {
            const s = @sin(m.pi * ph / 0.62);
            return 0.55 + 0.95 * s * s;
        }
        return 0.55 - 0.67 * @sin(m.pi * (ph - 0.62) / 0.38);
    }

    /// Seconds until the next reflux begins closing the valves (0 while closed).
    pub fn timeToReflux(t: f32) f32 {
        const ph = @mod(t, pump_period) / pump_period;
        const close_ph: f32 = 0.62 + 0.38 * 0.31; // pump() falls through ~0.05 here
        const open_ph: f32 = 0.62 + 0.38 * 0.69;
        if (ph < close_ph) return (close_ph - ph) * pump_period;
        if (ph < open_ph) return 0;
        return (1 - ph + close_ph) * pump_period;
    }

    /// Step valve leaflets toward the state the flow dictates.
    pub fn stepValves(vn: *Vein, t: f32, dt: f32) void {
        const target = m.smoothstep(0.0, 0.3, pump(t));
        for (&vn.valves) |*v| {
            for (0..2) |ci| {
                if (v.pinned[ci]) {
                    v.open[ci] = m.approach(v.open[ci], 0, 6, dt);
                } else {
                    v.open[ci] = m.approach(v.open[ci], target, if (target < v.open[ci]) 5 else 2.2, dt);
                }
            }
        }
    }

    pub fn inBore(vn: *const Vein, p: Vec3) bool {
        const a = vn.needle.axial(p);
        return a < Needle.mouth and a > -Needle.len and vn.needle.radial(p).len() < Needle.bore;
    }

    /// Blood velocity at `p`.
    pub fn flowAt(vn: *const Vein, p: Vec3, t: f32) Vec3 {
        if (vn.inBore(p)) return vn.needle.dir.scale(150);
        const l = local(p);
        const rw = vn.wallR(p.z, l.theta);
        const q = @max(0, 1 - (l.r / rw) * (l.r / rw));
        var speed = core_speed * @max(pump(t), -0.04) * q;
        var extra = Vec3.zero;

        for (&vn.valves, 0..) |*v, vi| {
            if (p.z < v.zb or p.z > v.top() + 400) continue;
            const ci: usize = if (l.y >= 0) 0 else 1;
            const avg = 0.5 * (v.open[0] + v.open[1]);
            if (vn.cuspY(vi, ci, l.x, p.z)) |ys| {
                if (@abs(l.y) > ys) {
                    // Pocket: near-stagnant, with the slow vortex that makes valve pockets clot.
                    speed *= 0.04;
                    const sigma: f32 = if (ci == 0) 1 else -1;
                    const cz = v.zb + v.len * 0.6;
                    const cy = sigma * (ys + rw) * 0.5;
                    const dz = (p.z - cz) / 900.0;
                    const dy = (l.y - cy) / 700.0;
                    extra = v3(0, dz * 22 * sigma, -dy * 22 * sigma).scale(@max(pump(t), 0.2));
                } else {
                    const tt = m.sat((p.z - v.zb) / v.len);
                    speed *= m.lerp(1, m.clamp(1.0 / (0.08 + 0.62 * avg), 0.3, 2.2), tt) * m.smoothstep(0.0, 0.12, avg);
                }
            }
        }

        // Station C: stagnant behind the corked web; once open, the channel pulls everything through.
        const s = &vn.septum;
        if (p.z > 19500 and p.z < s.z + 1500) {
            if (s.corked) {
                if (p.z < s.z) speed *= 0.1 else speed *= 0.25;
            } else {
                const c = center(s.z);
                const hole = v3(c.x + s.hole_x, c.y + s.hole_y, s.z);
                const d = hole.sub(p);
                const dist = d.len();
                if (p.z < s.z and dist < 1400) {
                    const k = 1 - dist / 1400;
                    extra = extra.add(d.norm().scale(520 * k * k + 60 * k));
                    speed *= 1 - k;
                } else if (p.z >= s.z and dist < 900) {
                    extra = extra.add(v3(0, 0, 420 * (1 - dist / 900)));
                }
            }
        }
        return tangent(p.z).scale(speed).add(extra);
    }

    pub const Contact = struct { pos: Vec3, wall: bool = false, leaflet: bool = false, squeezed: bool = false };

    /// Resolve a sphere of `radius` at `p` against wall, cusps, cannula and septum.
    pub fn collide(vn: *const Vein, p_in: Vec3, radius: f32, sides: *Sides, in_bore: *bool) Contact {
        var c: Contact = .{ .pos = p_in };
        const n = &vn.needle;

        // Cannula.
        {
            const a = n.axial(c.pos);
            const rad = n.radial(c.pos);
            const rl = rad.len();
            if (in_bore.*) {
                if (a >= Needle.mouth) {
                    in_bore.* = false;
                } else {
                    if (rl > Needle.bore - radius) c.pos = n.at(a).add(rad.scale((Needle.bore - radius) / @max(rl, 1e-3)));
                    if (a < -Needle.len + 400) c.pos = c.pos.add(n.dir.scale(-Needle.len + 400 - a));
                    c.wall = rl > Needle.bore - radius - 0.5;
                    return c;
                }
            } else if (a < Needle.mouth and a > -Needle.len) {
                if (rl < Needle.bore - radius and a < Needle.mouth - 40) {
                    in_bore.* = true;
                    return c;
                }
                if (rl < Needle.outer + radius and a < -300 - Needle.bevel * Needle.outer) {
                    c.pos = n.at(a).add(rad.scale((Needle.outer + radius) / @max(rl, 1e-3)));
                }
            }
        }

        // Wall.
        var l = local(c.pos);
        const rw = vn.wallR(c.pos.z, l.theta);
        if (l.r > rw - radius) {
            const k = (rw - radius) / @max(l.r, 1e-3);
            const ctr = center(c.pos.z);
            c.pos.x = ctr.x + l.x * k;
            c.pos.y = ctr.y + l.y * k;
            c.wall = true;
            l = local(c.pos);
        }

        // Cusps.
        for (&vn.valves, 0..) |*v, vi| {
            if (c.pos.z < v.zb - 5 or c.pos.z > v.top() + 5) {
                sides.cusp[vi] = .{ 0, 0 };
                continue;
            }
            var ys2: [2]?f32 = .{ null, null };
            for (0..2) |ci| {
                const sigma: f32 = if (ci == 0) 1 else -1;
                const ys = vn.cuspY(vi, ci, l.x, c.pos.z) orelse {
                    sides.cusp[vi][ci] = 0;
                    continue;
                };
                ys2[ci] = ys;
                const d = sigma * l.y - ys; // > 0 in the pocket
                if (sides.cusp[vi][ci] == 0) sides.cusp[vi][ci] = if (d > 0) 1 else -1;
                const side: f32 = @floatFromInt(sides.cusp[vi][ci]);
                if (d * side < radius) {
                    const ctr = center(c.pos.z);
                    c.pos.y = ctr.y + sigma * (ys + side * radius);
                    c.leaflet = true;
                    l = local(c.pos);
                }
            }
            // Caught between two closing cusps: squeezed back upstream.
            if (ys2[0] != null and ys2[1] != null and sides.cusp[vi][0] == -1 and sides.cusp[vi][1] == -1) {
                if (ys2[0].? + ys2[1].? < 2 * radius + 2) {
                    const ctr = center(c.pos.z);
                    c.pos.y = ctr.y + 0.5 * (ys2[0].? - ys2[1].?);
                    c.squeezed = true;
                }
            }
        }

        // Septum.
        const s = &vn.septum;
        const dz = c.pos.z - s.z;
        if (@abs(dz) > 400) {
            sides.septum = if (dz > 0) 1 else -1;
        } else {
            if (sides.septum == 0) sides.septum = if (dz > 0) 1 else -1;
            const ctr = center(s.z);
            const hx = c.pos.x - (ctr.x + s.hole_x);
            const hy = c.pos.y - (ctr.y + s.hole_y);
            const hd = @sqrt(hx * hx + hy * hy);
            const in_hole = hd < s.hole_r - radius;
            const side: f32 = @floatFromInt(sides.septum);
            if (in_hole) {
                if (@abs(dz) > Septum.half_thick + radius) sides.septum = if (dz > 0) 1 else -1;
            } else if (dz * side < Septum.half_thick + radius) {
                if (@abs(dz) < Septum.half_thick and hd < s.hole_r) {
                    // inside the channel: slide along its rim
                    const k = (s.hole_r - radius) / @max(hd, 1e-3);
                    c.pos.x = ctr.x + s.hole_x + hx * k;
                    c.pos.y = ctr.y + s.hole_y + hy * k;
                } else {
                    c.pos.z = s.z + side * (Septum.half_thick + radius);
                }
                c.wall = true;
            }
        }

        if (c.pos.z < z_min + 150) c.pos.z = z_min + 150;
        if (c.pos.z > z_max - 150) c.pos.z = z_max - 150;
        return c;
    }

    /// First anatomical surface along a ray, by marching the analytic model.
    pub fn raycast(vn: *const Vein, o: Vec3, d: Vec3, max_t: f32) ?RayHit {
        var t: f32 = 0;
        var prev_t: f32 = 0;
        var prev_side: [2][2]i8 = .{ .{ 0, 0 }, .{ 0, 0 } };
        var prev_dz: f32 = o.z - vn.septum.z;
        const n = &vn.needle;
        const start_in_bore = vn.inBore(o);
        var first = true;
        while (t <= max_t) {
            const p = o.add(d.scale(t));
            const l = local(p);
            const rw = vn.wallR(p.z, l.theta);

            // cannula
            const a = n.axial(p);
            if (a < 0 and a > -Needle.len) {
                const rl = n.radial(p).len();
                const cut = Needle.bevel * (n.radial(p).dot(n.e1) - Needle.outer);
                if (a < cut) {
                    if (start_in_bore) {
                        if (rl >= Needle.bore) return .{ .t = t, .what = .needle, .point = p };
                    } else if (rl < Needle.outer and rl > Needle.bore) {
                        return .{ .t = t, .what = .needle, .point = p };
                    }
                }
            }
            if (!start_in_bore or a >= Needle.mouth) {
                if (l.r >= rw) {
                    // refine
                    var lo = prev_t;
                    var hi = t;
                    for (0..5) |_| {
                        const mid = 0.5 * (lo + hi);
                        const pm = o.add(d.scale(mid));
                        const lm = local(pm);
                        if (lm.r >= vn.wallR(pm.z, lm.theta)) hi = mid else lo = mid;
                    }
                    const ph = o.add(d.scale(hi));
                    const what: Hit = if (vn.bulgeAmp(ph.z) > 0.06 and @abs(@sin(local(ph).theta)) > 0.35) .sinus else .wall;
                    return .{ .t = hi, .what = what, .point = ph };
                }
            }
            for (0..2) |vi| {
                for (0..2) |ci| {
                    const sigma: f32 = if (ci == 0) 1 else -1;
                    if (vn.cuspY(vi, ci, l.x, p.z)) |ys| {
                        const side: i8 = if (sigma * l.y - ys > 0) 1 else -1;
                        if (!first and prev_side[vi][ci] != 0 and prev_side[vi][ci] != side) return .{ .t = t, .what = .leaflet, .point = p };
                        prev_side[vi][ci] = side;
                    } else prev_side[vi][ci] = 0;
                }
            }
            const dz = p.z - vn.septum.z;
            if (!first and (dz > 0) != (prev_dz > 0)) {
                const ctr = center(vn.septum.z);
                const hx = p.x - (ctr.x + vn.septum.hole_x);
                const hy = p.y - (ctr.y + vn.septum.hole_y);
                if (hx * hx + hy * hy > vn.septum.hole_r * vn.septum.hole_r) return .{ .t = t, .what = .septum, .point = p };
            }
            prev_dz = dz;
            first = false;
            prev_t = t;
            const near_valve = (p.z > vn.valves[0].zb - 150 and p.z < vn.valves[0].top() + 150) or (p.z > vn.valves[1].zb - 150 and p.z < vn.valves[1].top() + 150);
            const gap = @max(rw - l.r, 0);
            var step = m.clamp(gap * 0.5, 3, 110);
            if (near_valve) step = @min(step, 14);
            if (@abs(dz) < 300) step = @min(step, 20);
            if (a < 200 and a > -Needle.len) step = @min(step, 12);
            t += step;
        }
        return null;
    }
};

pub const Meshes = struct {
    tube: gpu.Mesh,
    needle: gpu.Mesh,
    septum: gpu.Mesh,
};

/// Endothelial cells per turn of the wall texture (must be an integer so the pattern closes on itself).
pub const wall_cells_around: f32 = 808;

pub fn buildMeshes(b: *mesh.Builder, vn: *const Vein) Meshes {
    var out: Meshes = undefined;

    // Vessel wall.
    b.begin();
    const Tube = struct {
        vn: *const Vein,
        pub fn at(c: @This(), u: f32, v: f32) Vec3 {
            const th = u * m.tau;
            const z = m.lerp(z_min, z_max, v);
            const ctr = Vein.center(z);
            const r = c.vn.wallR(z, th);
            return v3(ctr.x + r * @cos(th), ctr.y + r * @sin(th), z);
        }
    };
    b.grid(96, 520, Tube{ .vn = vn }, false, .{ wall_cells_around, (z_max - z_min) / 14.0 });
    b.smoothNormals(false);
    out.tube = b.end();

    // Cannula: outer and inner shells cut by the bevel plane, plus the ground rim between them.
    b.begin();
    const Shell = struct {
        n: *const Needle,
        r0: f32,
        r1: f32,
        back: bool,
        pub fn at(c: @This(), u: f32, v: f32) Vec3 {
            const th = u * m.tau;
            const radial = c.n.e1.scale(@cos(th)).add(c.n.e2.scale(@sin(th)));
            if (c.back) {
                // v sweeps across the ground face from the outer to the inner shell
                const r = m.lerp(c.r0, c.r1, v);
                const a = Needle.bevel * (r * @cos(th) - Needle.outer);
                return c.n.at(a).add(radial.scale(r));
            }
            const a_end = Needle.bevel * (c.r0 * @cos(th) - Needle.outer);
            const a = m.lerp(-Needle.len, a_end, v * v);
            return c.n.at(a).add(radial.scale(c.r0));
        }
    };
    b.grid(40, 30, Shell{ .n = &vn.needle, .r0 = Needle.outer, .r1 = 0, .back = false }, false, .{ 6, 30 });
    b.grid(40, 30, Shell{ .n = &vn.needle, .r0 = Needle.bore, .r1 = 0, .back = false }, false, .{ 6, 30 });
    b.grid(40, 2, Shell{ .n = &vn.needle, .r0 = Needle.outer, .r1 = Needle.bore, .back = true }, false, .{ 6, 1 });
    b.smoothNormals(false);
    out.needle = b.end();

    // Post-thrombotic web with its one channel.
    b.begin();
    const Web = struct {
        vn: *const Vein,
        face: f32,
        pub fn at(c: @This(), u: f32, v: f32) Vec3 {
            const s = &c.vn.septum;
            const th = u * m.tau;
            const ctr = Vein.center(s.z);
            const hx = ctr.x + s.hole_x;
            const hy = ctr.y + s.hole_y;
            if (c.face == 0) {
                // channel lining
                return v3(hx + s.hole_r * @cos(th), hy + s.hole_r * @sin(th), s.z + m.lerp(-Septum.half_thick, Septum.half_thick, v));
            }
            const rw = c.vn.wallR(s.z, th) * 1.02;
            const ix = hx + s.hole_r * @cos(th);
            const iy = hy + s.hole_r * @sin(th);
            const ox = ctr.x + rw * @cos(th);
            const oy = ctr.y + rw * @sin(th);
            const x = m.lerp(ix, ox, v);
            const y = m.lerp(iy, oy, v);
            const lump = (mesh.fbm3(v3(x * 0.004, y * 0.004, c.face * 3)) - 0.5) * 90 * @sin(v * m.pi);
            // thicker where it meets the wall, like a scar
            const flare = 160 * v * v * v;
            return v3(x, y, s.z + c.face * (Septum.half_thick + flare) + lump);
        }
    };
    b.grid(72, 26, Web{ .vn = vn, .face = -1 }, false, .{ 60, 30 });
    b.grid(72, 26, Web{ .vn = vn, .face = 1 }, false, .{ 60, 30 });
    b.grid(72, 2, Web{ .vn = vn, .face = 0 }, false, .{ 60, 2 });
    b.smoothNormals(false);
    out.septum = b.end();
    return out;
}

pub const cusp_nu: u32 = 28;
pub const cusp_nv: u32 = 16;
pub const cusp_verts: u32 = cusp_nu * cusp_nv * 6;

/// Fill `out` (cusp_verts long) with the triangle list of one cusp in its current position.
pub fn buildCusp(vn: *const Vein, vi: usize, ci: usize, out: []gpu.Vertex) void {
    const v = &vn.valves[vi];
    const sigma: f32 = if (ci == 0) 1 else -1;
    var pts: [(cusp_nu + 1) * (cusp_nv + 1)]Vec3 = undefined;
    for (0..cusp_nv + 1) |j| {
        for (0..cusp_nu + 1) |i| {
            const u = (@as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(cusp_nu)) * 2 - 1) * 0.99;
            const t = @as(f32, @floatFromInt(j)) / @as(f32, @floatFromInt(cusp_nv));
            const x = u * Vein.cusp_half_width;
            const uu = u * u;
            const zbu = v.zb + v.len * 0.78 * uu * uu;
            const z = m.lerp(zbu + 0.5, v.top() - 0.5, t);
            const y = vn.cuspY(vi, ci, x, z) orelse 0;
            const ctr = Vein.center(z);
            pts[j * (cusp_nu + 1) + i] = v3(ctr.x + x, ctr.y + sigma * y, z);
        }
    }
    var k: usize = 0;
    for (0..cusp_nv) |j| {
        for (0..cusp_nu) |i| {
            const idx = [4]usize{ j * (cusp_nu + 1) + i, j * (cusp_nu + 1) + i + 1, (j + 1) * (cusp_nu + 1) + i + 1, (j + 1) * (cusp_nu + 1) + i };
            const order = [6]usize{ 0, 1, 2, 0, 2, 3 };
            for (order) |q| {
                const ii = idx[q] % (cusp_nu + 1);
                const jj = idx[q] / (cusp_nu + 1);
                const p = pts[idx[q]];
                // normal from neighbours
                const il = if (ii > 0) ii - 1 else ii;
                const ir = if (ii < cusp_nu) ii + 1 else ii;
                const jl = if (jj > 0) jj - 1 else jj;
                const jr = if (jj < cusp_nv) jj + 1 else jj;
                const du = pts[jj * (cusp_nu + 1) + ir].sub(pts[jj * (cusp_nu + 1) + il]);
                const dv = pts[jr * (cusp_nu + 1) + ii].sub(pts[jl * (cusp_nu + 1) + ii]);
                const nn = du.cross(dv).norm();
                out[k] = .{ .pos = .{ p.x, p.y, p.z }, .nrm = .{ nn.x, nn.y, nn.z }, .uv = .{ @as(f32, @floatFromInt(ii)) / @as(f32, @floatFromInt(cusp_nu)), @as(f32, @floatFromInt(jj)) / @as(f32, @floatFromInt(cusp_nv)) } };
                k += 1;
            }
        }
    }
}

test "pump has a forward surge and a brief reflux" {
    var lo: f32 = 10;
    var hi: f32 = -10;
    var t: f32 = 0;
    while (t < pump_period) : (t += 0.01) {
        lo = @min(lo, Vein.pump(t));
        hi = @max(hi, Vein.pump(t));
    }
    try std.testing.expect(hi > 1.4 and lo < 0 and lo > -0.2);
}

test "flow is parabolic: fast core, still wall" {
    const vn: Vein = .{};
    const c = Vein.center(2000);
    const core = vn.flowAt(c, 1.5).len();
    const near_wall = vn.flowAt(c.add(v3(0, R0 * 0.97, 0)), 1.5).len();
    try std.testing.expect(core > 200);
    try std.testing.expect(near_wall < core * 0.1);
}

test "valve pocket is stagnant and the cusp separates it from the channel" {
    var vn: Vein = .{};
    vn.valves[0].open = .{ 0.5, 0.5 };
    const z = vn.valves[0].zb + 1200;
    const ys = vn.cuspY(0, 0, 0, z).?;
    const c = Vein.center(z);
    const channel = vn.flowAt(c.add(v3(0, ys - 60, 0)), 1.5).len();
    const pocket = vn.flowAt(c.add(v3(0, ys + 200, 0)), 1.5).len();
    try std.testing.expect(pocket < 40 and channel > pocket * 2);

    // a body in the pocket cannot be pushed through the cusp
    var sides: Sides = .{};
    var bore = false;
    var p = c.add(v3(0, ys + 50, 0));
    _ = vn.collide(p, 4, &sides, &bore);
    p = c.add(v3(0, ys - 20, 0));
    const res = vn.collide(p, 4, &sides, &bore);
    try std.testing.expect(res.leaflet);
    try std.testing.expect(res.pos.y - c.y >= ys + 3.9);
}

test "ray from the core hits the wall at the wall radius" {
    const vn: Vein = .{};
    const c = Vein.center(2500);
    const hit = vn.raycast(c, v3(1, 0, 0), 5000).?;
    try std.testing.expect(hit.what == .wall);
    try std.testing.expectApproxEqAbs(vn.wallR(2500, 0), hit.t, 25);
}

test "corked web blocks, open channel passes" {
    var vn: Vein = .{};
    const s = vn.septum;
    const ctr = Vein.center(s.z);
    var sides: Sides = .{ .septum = -1 };
    var bore = false;
    const solid = v3(ctr.x - 600, ctr.y + 500, s.z - 10);
    try std.testing.expect(vn.collide(solid, 4, &sides, &bore).pos.z < s.z - Septum.half_thick);
    const through = v3(ctr.x + s.hole_x, ctr.y + s.hole_y, s.z + 10);
    vn.septum.corked = false;
    try std.testing.expectApproxEqAbs(s.z + 10, vn.collide(through, 4, &sides, &bore).pos.z, 0.01);
}
