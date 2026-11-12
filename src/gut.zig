//! Chapter 2 anatomy: a trough of proximal jejunum between two circular folds, at 1 unit = 1 µm.
//!
//! +z is aboral (the way chyme travels), +y is up into the lumen, the mucosal floor is y = 0. Villi stand on
//! a jittered hexagonal grid; the crypts open between their feet. Everything the chapter needs is derived
//! from the functions here: the instanced villi that are drawn, the collision, the flow that carries the
//! drone, and the ray casts for the reticle and the weapons.
//!
//! Real numbers the model keeps: villi 0.5–1 mm tall and ~0.12 mm thick, a pitch of ~0.3 mm, enterocytes
//! ~8 µm across, crypt mouths ~50 µm apart, peristaltic rings travelling aborally at 1–2 cm/s (100–200 µm/s
//! through the 1:100 tempo link; the game runs them at the upper end so a ring is a visible, outrunnable wall).
//! Rotavirus blunts villi; the blunted stretch is the part of the map with no shelter.

const std = @import("std");
const m = @import("math.zig");
const Vec3 = m.Vec3;
const v3 = m.v3;

pub const pitch: f32 = 300;
pub const row: f32 = pitch * 0.8660254;
pub const half_w: f32 = 1500;
pub const z_min: f32 = 0;
pub const z_max: f32 = 12000;
/// Open lumen above this is out of the drone's working envelope (the stream there is centimetres per second).
pub const roof: f32 = 2600;
/// Stretch where the infection has already blunted the villi to stubs.
pub const blunt_z0: f32 = 2700;
pub const blunt_z1: f32 = 4700;

pub const ring_half: f32 = 1500;
pub const ring_speed: f32 = 400;
/// Height the opposite wall comes down to at the centre of a contraction ring.
pub const ring_floor: f32 = 250;
/// Speed of the luminal stream well above the villi.
pub const stream_speed: f32 = 820;

pub const Villus = struct {
    x: f32,
    z: f32,
    base: f32,
    h: f32,
    r: f32,
    ix: i32,
    iz: i32,

    pub fn top(v: Villus) Vec3 {
        return v3(v.x, v.base + v.h, v.z);
    }
    /// Centre of the hemispherical cap.
    pub fn capCentre(v: Villus) Vec3 {
        return v3(v.x, v.base + v.h - v.r, v.z);
    }
    pub fn blunted(v: Villus) bool {
        return v.h < 300;
    }
};

pub const What = enum { villus, tip, stub, crypt, contraction };

pub const RayHit = struct {
    t: f32,
    point: Vec3,
    what: What,
    villus: ?Villus = null,
};

pub const Contact = struct {
    pos: Vec3,
    floor: bool = false,
    villus: bool = false,
    ceiling: bool = false,
    /// Pinned between the descending wall and something solid.
    crushed: bool = false,
};

fn hash(ix: i32, iz: i32, salt: u32) f32 {
    var h: u32 = @bitCast(ix *% 374761393 +% iz *% 668265263);
    h +%= salt *% 2246822519;
    h = (h ^ (h >> 15)) *% 2654435761;
    h ^= h >> 13;
    h *%= 1274126177;
    h ^= h >> 16;
    return @as(f32, @floatFromInt(h & 0xffffff)) / 16777216.0;
}

/// Mucosal floor: flat in the trough, rising into the flank of a circular fold on either side.
pub fn floorY(x: f32) f32 {
    const over = @abs(x) - half_w;
    if (over <= 0) return 0;
    return over * over / 700.0;
}

/// How blunted the villi are at z: 0 healthy, 1 stripped to stubs.
pub fn blunting(z: f32) f32 {
    return m.smoothstep(blunt_z0 - 250, blunt_z0 + 150, z) * (1 - m.smoothstep(blunt_z1 - 150, blunt_z1 + 250, z));
}

pub fn villusAt(ix: i32, iz: i32) Villus {
    const fz = @as(f32, @floatFromInt(iz)) * row + (hash(ix, iz, 2) - 0.5) * 70;
    const fx = (@as(f32, @floatFromInt(ix)) + (if (iz & 1 != 0) @as(f32, 0.5) else 0)) * pitch + (hash(ix, iz, 1) - 0.5) * 70;
    const bl = blunting(fz);
    const tall = 640 + 260 * hash(ix, iz, 3);
    const stub = 110 + 60 * hash(ix, iz, 5);
    const r = 54 + 14 * hash(ix, iz, 4);
    return .{ .x = fx, .z = fz, .base = floorY(fx), .h = m.lerp(tall, stub, bl), .r = m.lerp(r, r * 1.15, bl), .ix = ix, .iz = iz };
}

pub fn cellOf(x: f32, z: f32) [2]i32 {
    const iz: i32 = @intFromFloat(@round(z / row));
    const off: f32 = if (iz & 1 != 0) 0.5 else 0;
    const ix: i32 = @intFromFloat(@round(x / pitch - off));
    return .{ ix, iz };
}

/// Height of the villus canopy around (x, z), above the floor.
pub fn canopy(z: f32) f32 {
    return m.lerp(770, 140, blunting(z));
}

pub const Gut = struct {
    /// Centre of the contraction ring, or null between waves.
    ring_z: ?f32 = null,
    /// Counts rings that have finished crossing the map.
    rings_done: u32 = 0,

    pub fn launch(g: *Gut, z: f32) void {
        g.ring_z = z;
    }

    pub fn step(g: *Gut, dt: f32) void {
        if (g.ring_z) |*z| {
            z.* += ring_speed * dt;
            if (z.* > z_max + ring_half + 800) {
                g.ring_z = null;
                g.rings_done += 1;
            }
        }
    }

    /// 0 away from the ring, 1 at its centre.
    pub fn squeeze(g: *const Gut, z: f32) f32 {
        const rz = g.ring_z orelse return 0;
        const d = @abs(z - rz) / ring_half;
        if (d >= 1) return 0;
        const k = 1 - d * d;
        return k * k;
    }

    /// Height of the opposite wall's villus tips above the floor beneath them (the wall follows the trough).
    pub fn ceilY(g: *const Gut, z: f32) f32 {
        return m.lerp(roof, ring_floor, g.squeeze(z));
    }

    /// Chyme velocity. The villi are a canopy: the stream runs over them and is nearly still between them.
    /// A ring pushes a bolus ahead of itself that reaches deeper into the canopy.
    pub fn flowAt(g: *const Gut, p: Vec3, t: f32) Vec3 {
        const y = p.y - floorY(p.x);
        const cy = canopy(p.z);
        const lift = m.smoothstep(cy * 0.72, cy + 760, y);
        const slosh = 1 + 0.1 * @sin(t * 0.9);
        // Over the blunted stretch nothing brakes the stream, and the crypts there pour fluid into it
        // (the virus's NSP4 toxin makes them secrete): the fast layer reaches the floor.
        const profile = m.lerp(0.012 + 0.988 * lift * lift, 0.92 + 0.08 * m.sat(y / 300), blunting(p.z));
        var u = stream_speed * slosh * profile;
        if (g.ring_z) |rz| {
            const ahead = p.z - rz;
            if (ahead > -ring_half and ahead < 3600) {
                const k = if (ahead < 0) 1 + ahead / ring_half else 1 - ahead / 3600;
                const depth = m.smoothstep(40, cy, y);
                u += 520 * k * (0.08 + 0.92 * depth);
            }
        }
        return v3(0, 0, u);
    }

    const Near = struct { d: f32, n: Vec3, villus: ?Villus };

    /// Signed distance to the nearest villus among the cells around p, with the outward direction.
    fn nearVillus(p: Vec3) Near {
        const c = cellOf(p.x, p.z);
        var best: Near = .{ .d = 1e9, .n = Vec3.up, .villus = null };
        var dz: i32 = -1;
        while (dz <= 1) : (dz += 1) {
            var dx: i32 = -1;
            while (dx <= 1) : (dx += 1) {
                const v = villusAt(c[0] + dx, c[1] + dz);
                const top_y = v.base + v.h - v.r;
                const cy = m.clamp(p.y, v.base - 40, top_y);
                const q = v3(v.x, cy, v.z);
                const off = p.sub(q);
                const l = off.len();
                const d = l - v.r;
                if (d < best.d) best = .{ .d = d, .n = if (l > 1e-4) off.scale(1 / l) else Vec3.up, .villus = v };
            }
        }
        return best;
    }

    pub const Field = struct { d: f32, n: Vec3, what: What, villus: ?Villus };

    /// Distance to the nearest surface, which surface it is, and the direction away from it.
    pub fn field(g: *const Gut, p: Vec3) Field {
        const fy = p.y - floorY(p.x);
        var out: Field = .{ .d = fy, .n = Vec3.up, .what = .crypt, .villus = null };
        const nv = nearVillus(p);
        if (nv.d < out.d) {
            const v = nv.villus.?;
            const what: What = if (v.blunted()) .stub else if (p.y > v.base + v.h - 150) .tip else .villus;
            out = .{ .d = nv.d, .n = nv.n, .what = what, .villus = v };
        }
        const cd = g.ceilY(p.z) - fy;
        if (cd < out.d) out = .{ .d = cd, .n = v3(0, -1, 0), .what = .contraction, .villus = null };
        return out;
    }

    pub fn collide(g: *const Gut, p_in: Vec3, radius: f32) Contact {
        var p = p_in;
        p.z = m.clamp(p.z, z_min + radius, z_max - radius);
        p.x = m.clamp(p.x, -(half_w + 700), half_w + 700);
        var c: Contact = .{ .pos = p };
        for (0..4) |_| {
            var moved = false;
            const fy = p.y - floorY(p.x);
            if (fy < radius) {
                p.y += radius - fy;
                c.floor = true;
                moved = true;
            }
            const nv = nearVillus(p);
            if (nv.d < radius) {
                p = p.add(nv.n.scale(radius - nv.d));
                c.villus = true;
                moved = true;
            }
            const cd = g.ceilY(p.z) - (p.y - floorY(p.x));
            if (cd < radius) {
                p.y -= radius - cd;
                c.ceiling = true;
                moved = true;
            }
            if (!moved) break;
        }
        // Still inside something after the passes: the wall has come down onto a tip or the floor.
        if (c.ceiling) {
            const fy = p.y - floorY(p.x);
            const nv = nearVillus(p);
            if (fy < radius - 0.5 or nv.d < radius - 0.5) {
                c.crushed = true;
                // squirt sideways off the tip rather than stay pinned in solid tissue
                if (nv.d < radius) p = p.add(v3(nv.n.x, 0, nv.n.z).norm().scale(radius - nv.d + 1));
                p.y = @max(p.y, floorY(p.x) + radius);
            }
        }
        c.pos = p;
        return c;
    }

    /// Sphere-traced ray against the mucosa and the contraction.
    pub fn raycast(g: *const Gut, o: Vec3, d: Vec3, max_t: f32) ?RayHit {
        var t: f32 = 0;
        for (0..96) |_| {
            const p = o.add(d.scale(t));
            if (p.z < z_min - 50 or p.z > z_max + 50) return null;
            const f = g.field(p);
            if (f.d < 0.6) return .{ .t = t, .point = p, .what = f.what, .villus = f.villus };
            // villi outside the 3x3 neighbourhood are at least ~170 away, so longer steps could tunnel
            t += @min(f.d, 160);
            if (t > max_t) return null;
        }
        return null;
    }

    /// True when a sphere of this radius at p is clear of every surface.
    pub fn clear(g: *const Gut, p: Vec3, radius: f32) bool {
        return g.field(p).d >= radius;
    }
};

/// Centre of the gap between three villi that is nearest to (x, z): a way down to the crypt floor.
/// Stable under motion: from the returned point, the nearest gap is the same point.
pub fn gapNear(x: f32, z: f32) Vec3 {
    const c = cellOf(x, z);
    const o: i32 = if (c[1] & 1 != 0) 1 else 0;
    // the six neighbours of a hex cell, in order around it
    const ring = [6][2]i32{
        .{ c[0] + 1, c[1] },
        .{ c[0] + o, c[1] + 1 },
        .{ c[0] + o - 1, c[1] + 1 },
        .{ c[0] - 1, c[1] },
        .{ c[0] + o - 1, c[1] - 1 },
        .{ c[0] + o, c[1] - 1 },
    };
    const a = villusAt(c[0], c[1]);
    var best: f32 = 1e12;
    var out = v3(x, 0, z);
    for (0..6) |k| {
        const b = villusAt(ring[k][0], ring[k][1]);
        const d = villusAt(ring[(k + 1) % 6][0], ring[(k + 1) % 6][1]);
        const gx = (a.x + b.x + d.x) / 3;
        const gz = (a.z + b.z + d.z) / 3;
        const dist = (gx - x) * (gx - x) + (gz - z) * (gz - z);
        if (dist < best) {
            best = dist;
            out = v3(gx, floorY(gx), gz);
        }
    }
    return out;
}

test "villi stand on the floor and are tall except where blunted" {
    const healthy = villusAt(2, 30);
    try std.testing.expect(healthy.h > 600 and healthy.h < 920);
    try std.testing.expect(!healthy.blunted());
    const c = cellOf(0, (blunt_z0 + blunt_z1) / 2);
    const stub = villusAt(c[0], c[1]);
    try std.testing.expect(stub.blunted());
    try std.testing.expect(stub.h < 200);
}

test "the canopy shelters: fast stream above, near-still between villi" {
    const g: Gut = .{};
    const above = g.flowAt(v3(0, 2000, 8000), 0).z;
    const within = g.flowAt(v3(0, 300, 8000), 0).z;
    try std.testing.expect(above > 650);
    try std.testing.expect(within < 30);
    // no shelter over the blunted stretch at the same height
    const bare = g.flowAt(v3(0, 20, (blunt_z0 + blunt_z1) / 2), 0).z;
    try std.testing.expect(bare > 650);
}

test "collision keeps a sphere out of villi and off the floor" {
    const g: Gut = .{};
    const v = villusAt(3, 28);
    const inside = v3(v.x + 10, v.base + 300, v.z);
    const c = g.collide(inside, 4);
    try std.testing.expect(c.villus);
    try std.testing.expect(g.field(c.pos).d >= 3.9);
    const low = g.collide(gapNear(v.x, v.z).add(v3(0, -20, 0)), 4);
    try std.testing.expect(low.floor);
    try std.testing.expect(low.pos.y >= 3.9);
    // the gap is a fixed point: asking again from it returns it
    const gp = gapNear(v.x + 40, v.z - 30);
    const again = gapNear(gp.x, gp.z);
    try std.testing.expectApproxEqAbs(gp.x, again.x, 0.01);
    try std.testing.expectApproxEqAbs(gp.z, again.z, 0.01);
    try std.testing.expect(g.clear(v3(gp.x, 60, gp.z), 20));
}

test "a ray down a villus axis hits its tip; a ring closes the lumen above the villi" {
    var g: Gut = .{};
    const v = villusAt(1, 26);
    const hit = g.raycast(v.top().add(v3(0, 400, 0)), v3(0, -1, 0), 2000).?;
    try std.testing.expectEqual(What.tip, hit.what);
    try std.testing.expectApproxEqAbs(@as(f32, 400), hit.t, 2.0);

    g.launch(v.z);
    try std.testing.expectApproxEqAbs(ring_floor, g.ceilY(v.z), 0.01);
    const up = g.raycast(v3(v.x + 150, 100, v.z), Vec3.up, 2000).?;
    try std.testing.expectEqual(What.contraction, up.what);
    // on a tip under the ring there is no room: crushed; between the villi there is
    const on_tip = g.collide(v.top().add(v3(0, 6, 0)), 4);
    try std.testing.expect(on_tip.crushed);
    const gap = gapNear(v.x, v.z);
    const down = g.collide(v3(gap.x, 100, gap.z), 4);
    try std.testing.expect(!down.crushed and !down.ceiling);
}

test "the ring travels aborally and leaves the map" {
    var g: Gut = .{};
    g.launch(-2000);
    var t: f32 = 0;
    while (g.ring_z != null and t < 200) : (t += 0.1) g.step(0.1);
    try std.testing.expectEqual(@as(u32, 1), g.rings_done);
    try std.testing.expect(t < 60);
}
