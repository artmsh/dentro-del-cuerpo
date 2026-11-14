//! Chapter 4 anatomy: a minor calyx of the right kidney and the renal papilla it cups, at 1 unit = 1 µm.
//!
//! +y is the axis of the papilla, which stands up into the calyx with its tip at the origin. The papilla is
//! a paraboloid of revolution; the wall of the calyx is a second, steeper one over it, and the two meet in
//! the fornix, the gutter around the papilla's foot. At the top of the dome the wall opens into the
//! infundibulum, the tube that drains the calyx towards the renal pelvis and the ureter. The ducts of
//! Bellini open on the tip of the papilla (the area cribrosa) and each sends urine out in spurts. Everything
//! the chapter needs is derived from the functions here: the meshes that are drawn, the collision, the flow
//! that carries the drone and the stone's fragments, and the ray casts for the reticle and the weapons.
//!
//! Real numbers the model keeps: a papilla several millimetres across at its foot, a dozen or two papillary
//! ducts 0.1–0.2 mm wide opening on its tip, a calyx a few millimetres deep over it, and an infundibulum
//! under a millimetre wide at its narrowest. Urine does leave the ducts intermittently, milked out by the
//! calyx's own contractions; the tempo link shows each spurt at about half a millimetre a second.

const std = @import("std");
const m = @import("math.zig");
const Vec3 = m.Vec3;
const v3 = m.v3;

/// The papilla's surface is y = -rho² / a_pap, rho being the distance from its axis.
pub const a_pap: f32 = 4000;
/// Where the wall of the calyx meets the papilla.
pub const fornix_r: f32 = 3200;
/// Height of the calyx's dome over the tip of the papilla. The wall is y = dome_h - rho² / b_wall.
pub const dome_h: f32 = 3000;
pub const b_wall: f32 = fornix_r * fornix_r / (dome_h + fornix_r * fornix_r / a_pap);

/// The infundibulum: its mouth in the dome, and the neck it narrows to over `neck_len`.
pub const outlet_r: f32 = 600;
pub const neck_r: f32 = 290;
pub const neck_len: f32 = 400;
pub const mouth_y: f32 = dome_h - outlet_r * outlet_r / b_wall;
/// Top of the modelled infundibulum; beyond it is the renal pelvis.
pub const y_max: f32 = mouth_y + 1500;

/// The area cribrosa: the part of the tip the ducts open on.
pub const cribrosa_r: f32 = 950;
pub const duct_r: f32 = 55;
pub const duct_count: usize = 9;

/// A duct fires for `jet_on` seconds in every `jet_period`; the ducts take turns.
pub const jet_period: f32 = 7.2;
pub const jet_on: f32 = 1.6;
pub const jet_stagger: f32 = 0.8;
/// Shifts the whole rota so that duct 7 begins a spurt at time 0.
pub const jet_phase: f32 = jet_period - 7 * jet_stagger;
pub const jet_speed: f32 = 520;
pub const jet_reach: f32 = 700;

pub const What = enum { papilla, cribrosa, duct, calyx, fornix, infundibulum };

pub const RayHit = struct {
    t: f32,
    point: Vec3,
    what: What,
};

pub const Contact = struct {
    pos: Vec3,
    papilla: bool = false,
    wall: bool = false,
};

pub const Field = struct { d: f32, n: Vec3, what: What };

fn rhoOf(p: Vec3) f32 {
    return @sqrt(p.x * p.x + p.z * p.z);
}

/// Height of the papilla's surface under (x, z).
pub fn papillaY(x: f32, z: f32) f32 {
    return -(x * x + z * z) / a_pap;
}

/// Height of the calyx wall over (x, z), as if the dome had no opening.
pub fn wallY(x: f32, z: f32) f32 {
    return dome_h - (x * x + z * z) / b_wall;
}

/// Outward normal of the papilla over (x, z).
pub fn papillaNormal(x: f32, z: f32) Vec3 {
    return v3(2 * x / a_pap, 1, 2 * z / a_pap).norm();
}

/// The point of the papilla's surface under (x, z).
pub fn onPapilla(x: f32, z: f32) Vec3 {
    return v3(x, papillaY(x, z), z);
}

/// Radius of the infundibulum at height y.
pub fn tubeR(y: f32) f32 {
    return m.lerp(outlet_r, neck_r, m.smoothstep(mouth_y, mouth_y + neck_len, y));
}

/// Centre of the infundibulum's mouth: where everything loose in the calyx is carried to.
pub fn outlet() Vec3 {
    return v3(0, mouth_y, 0);
}

/// Centre of duct `i`'s opening: three around the very tip and six in a ring outside them.
pub fn ductPos(i: usize) Vec3 {
    const k: f32 = @floatFromInt(i);
    const inner = i < 3;
    const rho: f32 = if (inner) 210 else 520;
    const phi = if (inner) m.tau * (k / 3.0 + 0.25) else m.tau * ((k - 3) / 6.0 + 1.0 / 12.0);
    return onPapilla(rho * @cos(phi), rho * @sin(phi));
}

pub fn ductNormal(i: usize) Vec3 {
    const p = ductPos(i);
    return papillaNormal(p.x, p.z);
}

/// The duct whose opening `p` lies in, if any.
pub fn ductAt(p: Vec3) ?usize {
    for (0..duct_count) |i| {
        if (ductPos(i).dist(p) < duct_r * 1.2) return i;
    }
    return null;
}

/// How hard duct `i` is spurting at time `t`, 0..1.
pub fn jetStrength(i: usize, t: f32) f32 {
    const ph = @mod(t + @as(f32, @floatFromInt(i)) * jet_stagger + jet_phase, jet_period);
    if (ph >= jet_on) return 0;
    return m.smoothstep(0, 0.2, ph) * (1 - m.smoothstep(jet_on - 0.3, jet_on, ph));
}

/// Seconds until duct `i` next begins to spurt; 0 while it is spurting.
pub fn jetEta(i: usize, t: f32) f32 {
    const ph = @mod(t + @as(f32, @floatFromInt(i)) * jet_stagger + jet_phase, jet_period);
    return if (ph < jet_on) 0 else jet_period - ph;
}

/// Velocity that duct `i`'s jet gives the fluid at `p`: along the duct's axis, widening and weakening
/// with distance.
pub fn jetAt(i: usize, p: Vec3, t: f32) Vec3 {
    const k = jetStrength(i, t);
    if (k <= 0) return Vec3.zero;
    const n = ductNormal(i);
    const rel = p.sub(ductPos(i));
    const along = rel.dot(n);
    if (along < -10 or along > jet_reach) return Vec3.zero;
    const lateral = rel.sub(n.scale(along)).len();
    const width = 60 + 0.25 * @max(0, along);
    if (lateral >= width) return Vec3.zero;
    const q = lateral / width;
    return n.scale(jet_speed * k * (1 - @max(0, along) / jet_reach) * (1 - q * q));
}

/// The jets alone at `p`.
pub fn jetsAt(p: Vec3, t: f32) Vec3 {
    var v = Vec3.zero;
    // nothing a jet reaches is far from the tip
    if (p.x * p.x + p.z * p.z > 1500 * 1500 or p.y > jet_reach + 100) return v;
    for (0..duct_count) |i| v = v.add(jetAt(i, p, t));
    return v;
}

/// Velocity of the urine: a slow drift from everywhere towards the outlet, quickening as it converges,
/// then up the infundibulum, with the jets on top.
pub fn flowAt(p: Vec3, t: f32) Vec3 {
    var v: Vec3 = undefined;
    if (p.y >= mouth_y) {
        v = v3(0, 70, 0);
    } else {
        const to = outlet().sub(p);
        const dist = @max(to.len(), 1);
        const k = 900 / @max(dist, 300);
        v = to.scale(@min(70, 14 + 30 * k * k) / dist);
    }
    return v.add(jetsAt(p, t));
}

/// Distance to the nearest tissue, which tissue it is, and the direction away from it. The distances are
/// first-order (height over the surface divided by its slope), which is exact at the surface and an
/// underestimate away from it.
pub fn field(p: Vec3) Field {
    const rho = rhoOf(p);
    const gp = 2 * rho / a_pap;
    const dp = (p.y - papillaY(p.x, p.z)) / @sqrt(1 + gp * gp);
    var out: Field = .{ .d = dp, .n = papillaNormal(p.x, p.z), .what = if (rho > fornix_r - 450) .fornix else if (rho < cribrosa_r) .cribrosa else .papilla };

    const gw = 2 * rho / b_wall;
    var dw = (wallY(p.x, p.z) - p.y) / @sqrt(1 + gw * gw);
    var nw = v3(-2 * p.x / b_wall, -1, -2 * p.z / b_wall).norm();
    var ww: What = if (rho > fornix_r - 450) .fornix else .calyx;
    if (p.y > mouth_y - outlet_r) {
        // the fluid is the space under the dome joined to the inside of the tube
        const dt = tubeR(p.y) - rho;
        if (dt > dw) {
            dw = dt;
            nw = if (rho > 1e-3) v3(-p.x / rho, 0, -p.z / rho) else v3(1, 0, 0);
            ww = .infundibulum;
        }
    }
    if (dw < out.d) out = .{ .d = dw, .n = nw, .what = ww };
    return out;
}

/// Keeps a sphere out of the tissue and inside the model.
pub fn collide(p_in: Vec3, radius: f32) Contact {
    var p = p_in;
    var c: Contact = .{ .pos = p };
    var last: ?Vec3 = null;
    for (0..40) |_| {
        const f = field(p);
        if (f.d >= radius) break;
        p = p.add(f.n.scale(radius - f.d));
        if (f.what == .papilla or f.what == .cribrosa) c.papilla = true else c.wall = true;
        // In the wedge of the fornix the two surfaces push a sphere back and forth between them. Where
        // it does not fit, the way out is along the wedge, which is where the two normals add up to.
        if (last) |q| {
            if (q.dot(f.n) < 0.3) p = p.add(q.add(f.n).norm().scale(0.25 * radius + 1));
        }
        last = f.n;
    }
    p.y = @min(p.y, y_max - radius);
    c.pos = p;
    return c;
}

/// Sphere-traced ray against the papilla, the calyx wall and the infundibulum.
pub fn raycast(o: Vec3, d: Vec3, max_t: f32) ?RayHit {
    var t: f32 = 0;
    for (0..200) |_| {
        const p = o.add(d.scale(t));
        if (p.y > y_max) return null;
        const f = field(p);
        if (f.d < 0.6) {
            var what = f.what;
            if (what == .cribrosa and ductAt(p) != null) what = .duct;
            return .{ .t = t, .point = p, .what = what };
        }
        t += @min(f.d * 0.9, 140);
        if (t > max_t) return null;
    }
    return null;
}

/// True when a sphere of this radius at p is clear of every surface.
pub fn clear(p: Vec3, radius: f32) bool {
    return p.y < y_max and field(p).d >= radius;
}

/// A point in the fornix on the side away from +z: mid-way between papilla and wall where the gutter is
/// still `gap` wide.
pub fn fornixPoint(gap: f32) Vec3 {
    // gap(rho) = dome_h - rho² (1/b - 1/a)
    const rho = @sqrt((dome_h - gap) / (1.0 / b_wall - 1.0 / a_pap));
    return v3(0, 0.5 * (papillaY(0, -rho) + wallY(0, -rho)), -rho);
}

test "the calyx is the space between the papilla and the dome, and closes at the fornix" {
    // over the tip: open up to the dome, and through it into the infundibulum
    try std.testing.expect(clear(v3(0, 400, 0), 20));
    try std.testing.expect(!clear(v3(0, -40, 0), 20));
    try std.testing.expect(clear(v3(0, mouth_y + 200, 0), 20));
    try std.testing.expect(!clear(v3(650, mouth_y + 300, 0), 20));
    // off the axis the dome is closed
    try std.testing.expect(!clear(v3(1500, wallY(1500, 0) + 30, 0), 5));
    try std.testing.expect(clear(v3(1500, wallY(1500, 0) - 60, 0), 5));
    // the two surfaces meet at the fornix, and the gap narrows steadily towards it
    try std.testing.expectApproxEqAbs(papillaY(fornix_r, 0), wallY(fornix_r, 0), 0.5);
    var last: f32 = 1e9;
    var rho: f32 = 0;
    while (rho < fornix_r) : (rho += 200) {
        const gap = wallY(rho, 0) - papillaY(rho, 0);
        try std.testing.expect(gap > 0 and gap < last);
        last = gap;
    }
    // the gutter is a narrow wedge: 0.8 mm from surface to surface vertically leaves room for a sphere a
    // quarter of that across
    const f = fornixPoint(800);
    try std.testing.expect(clear(f, 100));
    try std.testing.expect(!clear(f, 200));
    try std.testing.expectApproxEqAbs(@as(f32, 800), wallY(f.x, f.z) - papillaY(f.x, f.z), 2);
}

test "the ducts open on the area cribrosa, apart from one another, and a ray finds them" {
    for (0..duct_count) |i| {
        const p = ductPos(i);
        try std.testing.expect(rhoOf(p) < cribrosa_r - duct_r);
        try std.testing.expectApproxEqAbs(@as(f32, 0), field(p).d, 0.01);
        for (0..i) |j| try std.testing.expect(ductPos(j).dist(p) > 4 * duct_r);
        const n = ductNormal(i);
        try std.testing.expect(n.y > 0.9);
        const hit = raycast(p.add(n.scale(300)), n.neg(), 600).?;
        try std.testing.expectEqual(What.duct, hit.what);
        try std.testing.expectApproxEqAbs(@as(f32, 300), hit.t, 2);
    }
    // between the ducts the tip is area cribrosa, and the flank is plain papilla
    try std.testing.expectEqual(What.cribrosa, raycast(v3(0, 300, 0), v3(0, -1, 0), 600).?.what);
    try std.testing.expectEqual(What.papilla, raycast(v3(1800, 300, 0), v3(0, -1, 0), 2000).?.what);
    try std.testing.expectEqual(What.calyx, raycast(v3(1500, 0, 0), v3(0, 1, 0), 3000).?.what);
    try std.testing.expectEqual(What.infundibulum, raycast(v3(0, 1000, 0), v3(0.2, 1, 0).norm(), 4000).?.what);
    try std.testing.expectEqual(What.fornix, raycast(v3(2500, -1300, 0), v3(1, -0.9, 0).norm(), 2000).?.what);
}

test "the ducts spurt in turn: some are always firing and most are not" {
    var t: f32 = 0;
    while (t < 2 * jet_period) : (t += 0.05) {
        var on: usize = 0;
        for (0..duct_count) |i| {
            if (jetStrength(i, t) > 0.5) on += 1;
        }
        try std.testing.expect(on >= 1 and on <= 3);
    }
    // a jet is a column over its duct: strong on the axis, gone beside it and beyond its reach
    var best: f32 = 0;
    t = 0;
    while (t < jet_period) : (t += 0.05) best = @max(best, jetStrength(4, t));
    try std.testing.expect(best > 0.99);
    t = 0;
    while (jetStrength(4, t) < 0.99) t += 0.05;
    const p = ductPos(4);
    const n = ductNormal(4);
    const on_axis = jetAt(4, p.add(n.scale(150)), t);
    try std.testing.expect(on_axis.dot(n) > 0.7 * jet_speed);
    try std.testing.expectEqual(@as(f32, 0), jetAt(4, p.add(n.scale(150)).add(n.perp().scale(200)), t).len());
    try std.testing.expectEqual(@as(f32, 0), jetAt(4, p.add(n.scale(jet_reach + 50)), t).len());
    // and before it fires, the wait is what the clock says
    try std.testing.expect(jetEta(4, t) == 0);
    try std.testing.expect(jetEta(4, t + jet_on) > jet_period - jet_on - 1.5);
}

test "whatever is loose in the calyx is carried to the outlet and up the infundibulum" {
    // a marker let go beside the papilla's flank, away from the jets
    var p = v3(0, 600, 1900);
    var t: f32 = 0;
    const dt: f32 = 1.0 / 30.0;
    while (t < 300 and p.y < mouth_y + 300) : (t += dt) {
        p = collide(p.add(flowAt(p, t).scale(dt)), 5).pos;
    }
    try std.testing.expect(p.y >= mouth_y + 300);
    try std.testing.expect(t > 20);
    try std.testing.expect(rhoOf(p) < neck_r);
    try std.testing.expect(flowAt(v3(0, mouth_y + 200, 0), 0).y > 50);
}

test "a sphere pushed into the fornix stays out of both surfaces" {
    var rng = m.Rng.init(4);
    var tried: usize = 0;
    for (0..4000) |_| {
        const raw = v3(rng.range(-3300, 3300), rng.range(-2700, y_max + 300), rng.range(-3300, 3300));
        // a move never takes the drone further into tissue than this in one step
        if (field(raw).d < -40) continue;
        tried += 1;
        const c = collide(raw, 6);
        try std.testing.expect(field(c.pos).d > 4.5);
        try std.testing.expect(c.pos.y <= y_max);
    }
    try std.testing.expect(tried > 400);
}
