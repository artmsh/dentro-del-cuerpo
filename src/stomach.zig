//! Chapter 3 anatomy: a strip of gastric antrum beside a peptic ulcer, at 1 unit = 1 µm.
//!
//! +z is aboral (towards the pylorus, the way a grinding wave travels), +y is up into the lumen, and the
//! epithelial surface between the gastric pits is y = 0. The pits stand on a hexagonal lattice, as they do
//! in an en-face view of real antral mucosa. The ulcer is a crater 6 mm across centred on the origin, so
//! the map sees one arc of its margin crossing the trough at z ≈ 3000 and the bed beyond it. Everything the
//! chapter needs is derived from the functions here: the instanced pits and the crater mesh that are
//! drawn, the collision, the acid, the flow, and the ray casts for the reticle and the weapons.
//!
//! Real numbers the model keeps: pit openings ~70 µm across and 0.1–0.15 mm apart, pits ~0.2 mm deep in
//! the antrum, an adherent mucus gel 0.1–0.3 mm thick holding a gradient from pH 7 at the cells to pH 2 at
//! the lumen, antral waves three a minute travelling at a few millimetres a second (the tempo link shows
//! them at 400 µm/s, as it shows chapter 2's rings), and the terminal antrum closing completely as a wave
//! passes. The regenerating epithelium next to an ulcer has no pits, which is the bare band before the rim.

const std = @import("std");
const m = @import("math.zig");
const Vec3 = m.Vec3;
const v3 = m.v3;

pub const pitch: f32 = 150;
pub const row: f32 = pitch * 0.8660254;
pub const half_w: f32 = 1300;
pub const z_min: f32 = 600;
pub const z_max: f32 = 10000;
/// Open lumen above this is out of the drone's working envelope.
pub const roof: f32 = 1500;

pub const pit_r: f32 = 34;
pub const pit_depth: f32 = 230;

/// The crater is a disc of this radius about the origin; only its aboral arc is on the map.
pub const ulcer_r: f32 = 3000;
pub const crater_depth: f32 = 520;
pub const rim_h: f32 = 90;
/// Pits stop this far short of the crater edge: scar epithelium has none.
pub const bare_band: f32 = 350;

/// Thickness of the mucus gel over healthy mucosa, and of the firm layer at the bottom of it.
pub const mucus_full: f32 = 300;
pub const acid_ph: f32 = 2;
pub const cell_ph: f32 = 7;
/// Below this the hull erodes.
pub const safe_ph: f32 = 4.5;

pub const ring_half: f32 = 1500;
pub const ring_speed: f32 = 400;

pub const What = enum { surface, pit, margin, bed, contraction };

pub const RayHit = struct {
    t: f32,
    point: Vec3,
    what: What,
};

pub const Contact = struct {
    pos: Vec3,
    floor: bool = false,
    pit: bool = false,
    ceiling: bool = false,
    /// Pinned between the two walls as they meet.
    crushed: bool = false,
};

pub const Pit = struct {
    x: f32,
    z: f32,
    ix: i32,
    iz: i32,

    /// Centre of the mouth, level with the surface.
    pub fn mouth(p: Pit) Vec3 {
        return v3(p.x, 0, p.z);
    }
    /// A point on the axis this far below the mouth.
    pub fn down(p: Pit, depth: f32) Vec3 {
        return v3(p.x, -depth, p.z);
    }
};

/// Mucosal floor away from the ulcer: flat in the trough, rising into a fold on either side.
pub fn floorY(x: f32) f32 {
    const over = @abs(x) - half_w;
    if (over <= 0) return 0;
    return over * over / 600.0;
}

/// Signed distance into the crater: negative on mucosa, zero at the edge, positive over the bed.
pub fn into(x: f32, z: f32) f32 {
    return ulcer_r - @sqrt(x * x + z * z);
}

/// Where the crater edge crosses the line x = const.
pub fn marginZ(x: f32) f32 {
    return @sqrt(@max(0, ulcer_r * ulcer_r - x * x));
}

/// Height of the tissue surface with the pits filled in: flat mucosa, the heaped rim, the crater and
/// the uneven granulation tissue of its bed.
pub fn surfaceY(x: f32, z: f32) f32 {
    const d = into(x, z);
    var y = floorY(x);
    if (d <= -260) return y;
    y += rim_h * m.smoothstep(-260, -110, d) * (1 - m.smoothstep(-110, 20, d));
    y -= crater_depth * m.smoothstep(0, 300, d);
    y += 22 * @sin(x / 95.0) * @sin(z / 120.0 + 1.3) * m.smoothstep(180, 420, d);
    return y;
}

pub fn cellOf(x: f32, z: f32) [2]i32 {
    const iz: i32 = @intFromFloat(@round(z / row));
    const off: f32 = if (iz & 1 != 0) 0.5 else 0;
    const ix: i32 = @intFromFloat(@round(x / pitch - off));
    return .{ ix, iz };
}

pub fn cellCentre(ix: i32, iz: i32) [2]f32 {
    const off: f32 = if (iz & 1 != 0) 0.5 else 0;
    return .{ (@as(f32, @floatFromInt(ix)) + off) * pitch, @as(f32, @floatFromInt(iz)) * row };
}

/// The pit of a lattice cell, where the mucosa there still has one.
pub fn pitAt(ix: i32, iz: i32) ?Pit {
    const c = cellCentre(ix, iz);
    if (@abs(c[0]) > half_w - 60) return null;
    if (into(c[0], c[1]) > -bare_band) return null;
    return .{ .x = c[0], .z = c[1], .ix = ix, .iz = iz };
}

/// The pit nearest to (x, z), searching the cells around it.
pub fn pitNear(x: f32, z: f32) ?Pit {
    const c = cellOf(x, z);
    var best: f32 = 1e12;
    var out: ?Pit = null;
    var dz: i32 = -3;
    while (dz <= 3) : (dz += 1) {
        var dx: i32 = -3;
        while (dx <= 3) : (dx += 1) {
            const p = pitAt(c[0] + dx, c[1] + dz) orelse continue;
            const d = (p.x - x) * (p.x - x) + (p.z - z) * (p.z - z);
            if (d < best) {
                best = d;
                out = p;
            }
        }
    }
    return out;
}

/// Thickness of the mucus gel above the surface at (x, z). It thins towards the ulcer and is gone before
/// the rim; nothing covers the crater.
pub fn mucus(x: f32, z: f32) f32 {
    return mucus_full * m.smoothstep(200, 900, -into(x, z));
}

/// Acidity at a point. The gel holds bicarbonate secreted by the cells under it, so pH falls from 7 at the
/// epithelium to 2 at the top of the gel; a pit is a well of gel and counts by its depth.
pub fn ph(p: Vec3) f32 {
    const dep = surfaceY(p.x, p.z) + mucus(p.x, p.z) - p.y;
    return acid_ph + (cell_ph - acid_ph) * m.smoothstep(0, 200, dep);
}

pub const Stomach = struct {
    /// Centre of the grinding wave, or null between waves.
    ring_z: ?f32 = null,
    rings_done: u32 = 0,

    pub fn launch(g: *Stomach, z: f32) void {
        g.ring_z = z;
    }

    pub fn step(g: *Stomach, dt: f32) void {
        if (g.ring_z) |*z| {
            z.* += ring_speed * dt;
            if (z.* > z_max + ring_half + 800) {
                g.ring_z = null;
                g.rings_done += 1;
            }
        }
    }

    /// 0 away from the wave, 1 where the walls have met.
    pub fn squeeze(g: *const Stomach, z: f32) f32 {
        const rz = g.ring_z orelse return 0;
        const d = @abs(z - rz) / ring_half;
        if (d >= 1) return 0;
        const k = 1 - d * d;
        return m.sat(k * k * 1.25);
    }

    /// Height of the opposite wall above the mucosal floor. It comes all the way down: only a pit, or the
    /// crater, stays open under a wave.
    pub fn ceilY(g: *const Stomach, z: f32) f32 {
        return m.lerp(roof, 0, g.squeeze(z));
    }

    /// How exposed a point is to whatever the lumen is doing: 0 in a pit or deep in the gel, 1 in open
    /// juice. Over the crater there is no gel, only the slow layer against the bed.
    fn exposure(p: Vec3) f32 {
        const y = p.y - surfaceY(p.x, p.z);
        const t = mucus(p.x, p.z);
        return m.smoothstep(-25, 15, y) * (0.05 + 0.95 * m.smoothstep(0.5 * t, t + 170, y));
    }

    /// Velocity of the gastric contents. Between waves the antrum barely moves. A wave pushes a bolus
    /// ahead of itself towards the pylorus and, as it closes, squirts what it holds back through its own
    /// narrowing ring (retropulsion): under the wave the stream runs the other way.
    pub fn flowAt(g: *const Stomach, p: Vec3, t: f32) Vec3 {
        const ex = exposure(p);
        var u = 45 * @sin(t * 0.7) * ex;
        if (g.ring_z) |rz| {
            const ahead = p.z - rz;
            if (ahead > 0 and ahead < 3200) {
                u += 460 * (1 - ahead / 3200) * ex;
            } else if (ahead <= 0 and ahead > -ring_half) {
                u -= 520 * (1 + ahead / ring_half) * ex;
            }
        }
        return v3(0, 0, u);
    }

    pub const Field = struct { d: f32, n: Vec3, what: What };

    /// Distance to the tissue of this wall (surface, pit, rim, crater), ignoring the opposite wall.
    pub fn tissue(p: Vec3) Field {
        const e: f32 = 3;
        const h = surfaceY(p.x, p.z);
        const hx = (surfaceY(p.x + e, p.z) - surfaceY(p.x - e, p.z)) / (2 * e);
        const hz = (surfaceY(p.x, p.z + e) - surfaceY(p.x, p.z - e)) / (2 * e);
        const inv = 1.0 / @sqrt(1 + hx * hx + hz * hz);
        const din = into(p.x, p.z);
        var out: Field = .{ .d = (p.y - h) * inv, .n = v3(-hx * inv, inv, -hz * inv), .what = if (din > 120) .bed else if (din > -270) .margin else .surface };

        const c = cellOf(p.x, p.z);
        if (pitAt(c[0], c[1])) |pit| {
            const rx = p.x - pit.x;
            const rz = p.z - pit.z;
            const cy = -pit_depth + pit_r;
            var d: f32 = undefined;
            var n: Vec3 = undefined;
            if (p.y >= cy) {
                const rad = @sqrt(rx * rx + rz * rz);
                d = pit_r - rad;
                n = if (rad > 1e-3) v3(-rx / rad, 0, -rz / rad) else Vec3.up;
            } else {
                const off = v3(rx, p.y - cy, rz);
                const l = off.len();
                d = pit_r - l;
                n = if (l > 1e-3) off.scale(-1 / l) else Vec3.up;
            }
            // the fluid is the space above the surface joined to the inside of the pit
            if (d > out.d) out = .{ .d = d, .n = n, .what = .pit };
        }
        return out;
    }

    /// Distance to the nearest surface, which surface it is, and the direction away from it.
    pub fn field(g: *const Stomach, p: Vec3) Field {
        var out = tissue(p);
        const cd = g.ceilY(p.z) + floorY(p.x) - p.y;
        if (cd < out.d) out = .{ .d = cd, .n = v3(0, -1, 0), .what = .contraction };
        return out;
    }

    pub fn collide(g: *const Stomach, p_in: Vec3, radius: f32) Contact {
        var p = p_in;
        p.z = m.clamp(p.z, z_min + radius, z_max - radius);
        p.x = m.clamp(p.x, -(half_w + 600), half_w + 600);
        var c: Contact = .{ .pos = p };
        for (0..4) |_| {
            var moved = false;
            const f = tissue(p);
            if (f.d < radius) {
                p = p.add(f.n.scale(radius - f.d));
                if (f.what == .pit) c.pit = true else c.floor = true;
                moved = true;
            }
            const cd = g.ceilY(p.z) + floorY(p.x) - p.y;
            if (cd < radius) {
                p.y -= radius - cd;
                c.ceiling = true;
                moved = true;
            }
            if (!moved) break;
        }
        if (c.ceiling) {
            const f = tissue(p);
            if (f.d < radius - 0.5) {
                // the walls have met with the sphere between them: it stays on this one
                c.crushed = true;
                p = p.add(f.n.scale(radius - f.d));
            }
        }
        c.pos = p;
        return c;
    }

    /// Sphere-traced ray against the mucosa and the opposite wall.
    pub fn raycast(g: *const Stomach, o: Vec3, d: Vec3, max_t: f32) ?RayHit {
        var t: f32 = 0;
        for (0..160) |_| {
            const p = o.add(d.scale(t));
            if (p.z < z_min - 200 or p.z > z_max + 200) return null;
            const f = g.field(p);
            if (f.d < 0.6) return .{ .t = t, .point = p, .what = f.what };
            // the height field's distance is first-order, so steps stay short of it
            t += @min(f.d * 0.85, 90);
            if (t > max_t) return null;
        }
        return null;
    }

    /// True when a sphere of this radius at p is clear of every surface.
    pub fn clear(g: *const Stomach, p: Vec3, radius: f32) bool {
        return g.field(p).d >= radius;
    }
};

test "pits stand on healthy mucosa and stop short of the ulcer" {
    const far = pitNear(0, 8000).?;
    try std.testing.expect(@abs(far.x) < 80 and @abs(far.z - 8000) < 80);
    // none in the scar band, on the rim or in the crater
    const c = cellOf(0, ulcer_r + 200);
    try std.testing.expect(pitAt(c[0], c[1]) == null);
    const b = cellOf(0, 1500);
    try std.testing.expect(pitAt(b[0], b[1]) == null);
    // the nearest one to the edge is still a pit's width outside the bare band
    const edge = pitNear(0, ulcer_r).?;
    try std.testing.expect(into(edge.x, edge.z) <= -bare_band);
    try std.testing.expect(into(edge.x, edge.z) > -bare_band - 2 * pitch);
}

test "the rim stands above the mucosa and the bed lies well below it" {
    try std.testing.expectEqual(@as(f32, 0), surfaceY(0, 6000));
    try std.testing.expect(surfaceY(0, ulcer_r + 100) > 70);
    try std.testing.expect(surfaceY(0, 2000) < -450);
    try std.testing.expectApproxEqAbs(ulcer_r, marginZ(0), 0.01);
    try std.testing.expectApproxEqAbs(@as(f32, 0), into(900, marginZ(900)), 0.05);
}

test "the gel keeps the cells neutral and the lumen is acid; the crater has no gel" {
    // healthy mucosa: neutral at the surface, acid at the top of the gel
    try std.testing.expectApproxEqAbs(cell_ph, ph(v3(0, 5, 8000)), 0.01);
    try std.testing.expect(ph(v3(0, 150, 8000)) > 6);
    try std.testing.expect(ph(v3(0, 230, 8000)) < 4);
    try std.testing.expectApproxEqAbs(acid_ph, ph(v3(0, 320, 8000)), 0.01);
    // bare bed
    try std.testing.expectApproxEqAbs(acid_ph, ph(v3(0, surfaceY(0, 2000) + 10, 2000)), 0.01);
    // beside the ulcer the gel is thin: acid at the surface, and a pit is safe only deep down
    const p = pitNear(0, ulcer_r).?;
    try std.testing.expect(mucus(p.x, p.z) < 90);
    try std.testing.expect(ph(p.mouth().add(v3(0, 6, 0))) < safe_ph);
    try std.testing.expect(ph(p.down(190)) > safe_ph + 1);
}

test "collision keeps a sphere on the surface and inside a pit" {
    const g: Stomach = .{};
    const p = pitNear(200, 7000).?;
    // between pits: stopped by the surface
    const land = g.collide(v3(p.x + pitch / 2, -30, p.z), 4);
    try std.testing.expect(land.floor);
    try std.testing.expectApproxEqAbs(@as(f32, 4), land.pos.y, 0.2);
    // down the axis: nothing in the way until the bottom
    try std.testing.expect(g.clear(p.down(120), 20));
    const deep = g.collide(p.down(pit_depth + 40), 4);
    try std.testing.expect(deep.pit);
    try std.testing.expectApproxEqAbs(-pit_depth + 4, deep.pos.y, 0.5);
    // against the wall of the pit
    const side = g.collide(p.down(100).add(v3(pit_r + 5, 0, 0)), 4);
    try std.testing.expect(side.pit);
    try std.testing.expectApproxEqAbs(p.x + pit_r - 4, side.pos.x, 0.5);
    try std.testing.expect(g.field(side.pos).d >= 3.9);
    // the crater bed holds a sphere too
    const bed = g.collide(v3(100, -900, 2000), 4);
    try std.testing.expect(bed.floor);
    try std.testing.expect(Stomach.tissue(bed.pos).d >= 3.9);
}

test "rays read the pit, the surface, the rim and the bed; a wave closes everything but the pits" {
    var g: Stomach = .{};
    const p = pitNear(-300, 7000).?;
    const down_axis = g.raycast(p.mouth().add(v3(0, 100, 0)), v3(0, -1, 0), 2000).?;
    try std.testing.expectEqual(What.pit, down_axis.what);
    try std.testing.expectApproxEqAbs(100 + pit_depth, down_axis.t, 3.0);
    const between = g.raycast(v3(p.x + pitch / 2, 100, p.z), v3(0, -1, 0), 2000).?;
    try std.testing.expectEqual(What.surface, between.what);
    try std.testing.expectApproxEqAbs(@as(f32, 100), between.t, 2.0);
    const rim = g.raycast(v3(0, 300, ulcer_r + 90), v3(0, -1, 0), 2000).?;
    try std.testing.expectEqual(What.margin, rim.what);
    const bed = g.raycast(v3(0, 100, 2000), v3(0, -1, 0), 2000).?;
    try std.testing.expectEqual(What.bed, bed.what);
    try std.testing.expect(bed.point.y < -450);
    // a level ray over healthy mucosa has nothing in range
    try std.testing.expect(g.raycast(v3(0, 60, 6000), v3(0, 0.02, 1).norm(), 2000) == null);

    g.launch(p.z);
    try std.testing.expectApproxEqAbs(@as(f32, 0), g.ceilY(p.z), 0.01);
    const up = g.raycast(p.down(60), Vec3.up, 2000).?;
    try std.testing.expectEqual(What.contraction, up.what);
    const on_surface = g.collide(v3(p.x + pitch / 2, 10, p.z), 4);
    try std.testing.expect(on_surface.crushed);
    const in_pit = g.collide(p.down(60), 4);
    try std.testing.expect(!in_pit.crushed and !in_pit.ceiling);
    // hovering over a mouth, the wall pushes the sphere into the pit rather than onto tissue
    const over = g.collide(p.mouth().add(v3(0, 20, 0)), 4);
    try std.testing.expect(over.ceiling and !over.crushed);
    try std.testing.expect(over.pos.y < 0);
    // the crater stays open under a wave
    g.launch(2000);
    const pocket = g.collide(v3(0, -300, 2000), 4);
    try std.testing.expect(!pocket.ceiling);
}

test "a pit is still water under a wave; the lumen is pushed ahead of it and squirted back under it" {
    var g: Stomach = .{};
    const p = pitNear(0, 7000).?;
    try std.testing.expect(@abs(g.flowAt(v3(0, 600, 7000), 0.5).z) < 60);
    g.launch(p.z - 1000);
    try std.testing.expect(g.flowAt(v3(p.x, 500, p.z), 0).z > 250);
    try std.testing.expect(@abs(g.flowAt(p.down(80), 0).z) < 1);
    // in the firm gel at the surface it is a fraction of the stream
    try std.testing.expect(g.flowAt(v3(p.x + 75, 40, p.z), 0).z < 40);
    g.launch(2400);
    try std.testing.expect(g.flowAt(v3(0, -300, 2000), 0).z < -250);
    try std.testing.expect(@abs(g.flowAt(v3(0, surfaceY(0, 2000) + 6, 2000), 0).z) < 40);

    var t: f32 = 0;
    while (g.ring_z != null and t < 200) : (t += 0.1) g.step(0.1);
    try std.testing.expectEqual(@as(u32, 1), g.rings_done);
}
