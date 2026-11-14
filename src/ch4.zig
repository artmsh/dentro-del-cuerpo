//! Chapter 4 rules: a minor calyx of the right kidney with a calcium oxalate stone on the flank of its
//! papilla. The ducts of Bellini spurt and throw the drone about; the stone is cut from the plaque it grew
//! on, then halved along drilled notches until every piece is small enough to leave by the neck of the
//! calyx; a blow with no notch crushes the surface into shards that cut the hull. The drone, arms, shots
//! and guide queue are the shared machinery in game.zig; this file is what is specific to the place.

const std = @import("std");
const m = @import("math.zig");
const game = @import("game.zig");
const kidney = @import("kidney.zig");
const guide = @import("guide.zig");
const i18n = @import("i18n.zig");
const bindings = @import("bindings.zig");
const strings = @import("strings.zig");
const Text = i18n.Text;
const L = strings.line;
const H = strings.hint;
const O = strings.objective;
const Vec3 = m.Vec3;
const v3 = m.v3;
const Sim = game.Sim;
const Stage = game.Stage;
const Topic = guide.Topic;

/// Radius of the whole stone. A clean split makes two pieces of half the volume each.
pub const stone_r: f32 = 640;
pub const shrink: f32 = 0.7937;
/// Halvings after which a piece is small enough for the neck of the calyx: 640 → 508 → 403 → 320 → 254 µm.
pub const pass_gen: u8 = 4;
/// Halvings after which the Resonance upgrade is delivered.
pub const upgrade_gen: u8 = 3;
/// Where on the papilla the plaque lies: this far from the axis, on the +z side.
pub const plaque_rho: f32 = 1100;
pub const plaque_r: f32 = 90;
/// Seconds of drilling that cut the stalk, and that cut a notch across a piece.
pub const neck_time: f32 = 7;
pub const score_time: f32 = 1.3;
/// How much of a notch a blow needs to open it into a crack.
pub const notch_enough: f32 = 0.85;
pub const wave_reach: f32 = 700;
pub const tether_range: f32 = 420;
pub const shard_r: f32 = 9;
pub const max_shards: u32 = 24;
/// Crystals that came down a duct with a spurt and are loose in the calyx at once, at most.
pub const max_native: u32 = 8;
/// Stability lost per second while the outlet is blocked.
pub const blocked_rate: f32 = 0.35;
/// The duct the drone arrives through.
pub const arrival_duct: usize = 7;

const ivory = [4]f32{ 1, 0.93, 0.74, 1 };
const glass = [4]f32{ 0.85, 0.97, 1, 1 };
const straw = [4]f32{ 1, 0.92, 0.55, 1 };

const Said = struct {
    jet: bool = false,
    native: bool = false,
    shard: bool = false,
    cut: bool = false,
    neck_half: bool = false,
    stalk: bool = false,
    first_split: bool = false,
    bare: bool = false,
    rounds: bool = false,
    lodged: bool = false,
    passed: bool = false,
    line_up: bool = false,
    wave_miss: bool = false,
    tether_none: f32 = 0,
};

pub const State = struct {
    neck_cut: bool = false,
    /// Splits along a notch, and splits made by a Resonance wave.
    clean_splits: u32 = 0,
    wave_splits: u32 = 0,
    /// Blows on stone with no notch under them.
    bad_punches: u32 = 0,
    shards_made: u32 = 0,
    shards_shot: u32 = 0,
    shards_escaped: u32 = 0,
    cuts: u32 = 0,
    cut_cd: f32 = 0,
    /// Pieces that reached the outlet too big to pass, and the seconds it stayed blocked.
    lodged: u32 = 0,
    blocked_t: f32 = 0,
    was_blocked: bool = false,
    passed: u32 = 0,
    jet_time: f32 = 0,
    jet_hits: u32 = 0,
    in_jet: bool = false,
    has_resonance: bool = false,
    ready_t: f32 = 0,
    done_t: f32 = 0,
    shed_t: f32 = 0.9,
    tether_uses: u32 = 0,
    said: Said = .{},
};

// ---------------------------------------------------------------------------------------------- setup

/// The point of the papilla the plaque shows at, and the normal there.
pub fn plaqueSite() Vec3 {
    return kidney.onPapilla(0, plaque_rho);
}

pub fn plaqueNormal() Vec3 {
    return kidney.papillaNormal(0, plaque_rho);
}

pub fn exitSite() Vec3 {
    return kidney.fornixPoint(800);
}

pub fn radiusOf(gen: u8) f32 {
    var r = stone_r;
    for (0..gen) |_| r *= shrink;
    return r;
}

pub fn begin(s: *Sim) void {
    s.chapter = 3;
    s.in_bore = false;
    s.stability = 64;
    s.has_sync = true;
    s.has_tether = true;
    s.arms = .{ .{ .tool = .shoot }, .{ .tool = .punch } };

    const site = plaqueSite();
    const n = plaqueNormal();

    // Arrival: thrown clear of a duct of Bellini on the far side of the tip, facing the stone.
    const d = kidney.ductPos(arrival_duct);
    s.pos = d.add(kidney.ductNormal(arrival_duct).scale(90));
    const to = site.add(n.scale(400)).sub(s.pos).norm();
    s.yaw = std.math.atan2(to.x, to.z);
    s.pitch = 0.12;
    s.warp = 1;

    _ = s.spawn(.{ .kind = .plaque, .pos = site.add(n.scale(70)), .end = n, .radius = plaque_r, .hp = neck_time, .max_hp = neck_time, .seed = 0.6 });
    _ = s.spawn(.{ .kind = .calculus, .pos = site.add(n.scale(stone_r + 150)), .end = v3(1, 0, 0), .radius = stone_r, .state = 1, .seed = 0.3 });
    _ = s.spawn(.{ .kind = .ring, .pos = exitSite(), .radius = 90, .variant = 4 });

    s.setStage(.k_arrive);
}

// ---------------------------------------------------------------------------------------------- stages

pub fn enter(s: *Sim, st: Stage) void {
    switch (st) {
        .k_arrive => {
            s.say(L.out_of_the_duct);
            s.say(L.the_glomerulus_was_a_dead_end);
            s.atlas[@intFromEnum(Topic.glomerulus)] = true;
            s.waypoint = null;
        },
        .k_duct => {
            s.say(L.look_at_the_openings);
            s.waypoint = null;
        },
        .k_jets => {
            s.want_checkpoint = true;
            s.atlas[@intFromEnum(Topic.urine_jet)] = true;
            s.say(L.they_fire_in_spurts);
            s.say(L.the_stone_is_across);
            s.waypoint = standPoint();
        },
        .k_stone => {
            s.say(L.there_is_the_stone);
            s.waypoint = null;
        },
        .k_neck => {
            s.want_checkpoint = true;
            s.say(L.it_sits_on_a_stalk);
            s.say(L.shards_while_you_drill);
            s.waypoint = standPoint();
        },
        .k_split => {
            s.want_checkpoint = true;
            s.say(L.its_free);
            s.say(L.score_then_strike);
        },
        .k_resonance => {
            s.want_checkpoint = true;
            s.say(L.resonance_is_live);
        },
        .k_exit => {
            s.want_checkpoint = true;
            s.stabilise(8);
            s.say(L.every_piece_will_pass);
            s.say(L.out_by_the_fornix);
            s.waypoint = exitSite();
        },
        else => {},
    }
}

pub fn upgradeTaken(s: *Sim) void {
    s.g4.has_resonance = true;
    s.mode = .playing;
    s.sound(.upgrade, 0, 1);
    s.setStage(.k_resonance);
}

pub fn objective(s: *const Sim, p: bindings.Prompt, buf: []u8) []const u8 {
    const text: Text = switch (s.stage) {
        .k_arrive => O.k_arrive,
        .k_duct => O.k_duct,
        .k_jets => O.k_jets,
        .k_stone => O.k_stone,
        .k_neck => return bindings.format(buf, p, O.k_neck, .{i18n.int(neckPercent(s))}),
        .k_split => return bindings.format(buf, p, O.k_split, .{i18n.int(oversized(s))}),
        .k_resonance => return bindings.format(buf, p, O.k_resonance, .{i18n.int(oversized(s))}),
        .k_exit => O.transit_marker,
        else => return "",
    };
    return bindings.resolve(buf, text, p);
}

pub fn hintText(s: *const Sim) Text {
    const lv: usize = @min(s.hint_level, 2);
    return switch (s.stage) {
        .k_duct => H.k_duct[lv],
        .k_jets => H.k_jets[lv],
        .k_stone => H.k_stone[lv],
        .k_neck => H.k_neck[lv],
        .k_split => H.k_split[lv],
        .k_resonance => H.k_resonance[lv],
        .k_exit => H.g_exit,
        else => H.wait,
    };
}

// ---------------------------------------------------------------------------------------------- the place

fn stalk(s: *const Sim) ?*const game.Entity {
    return s.findConst(.plaque);
}

/// Where a drone stands to put its bit on the stalk: beside it, under the stone, on the side of the tip.
pub fn standPoint() Vec3 {
    const n = plaqueNormal();
    // along the papilla's surface towards its axis
    const t = v3(0, 0, -1).sub(n.scale(-n.z)).norm();
    return plaqueSite().add(n.scale(70)).add(t.scale(plaque_r + game.hull_r + 12));
}

pub fn neckPercent(s: *const Sim) i32 {
    if (s.g4.neck_cut) return 100;
    const e = stalk(s) orelse return 0;
    return @intFromFloat(@min(99, 100 * (1 - e.hp / e.max_hp)));
}

pub fn passable(e: *const game.Entity) bool {
    return e.variant >= pass_gen;
}

/// Pieces of stone still too big for the neck of the calyx.
pub fn oversized(s: *const Sim) u32 {
    var n: u32 = 0;
    for (&s.ents) |*e| {
        if (e.kind == .calculus and !passable(e)) n += 1;
    }
    return n;
}

/// Diameter of the largest piece left in the calyx, in millimetres; 0 when there is none.
pub fn largestMm(s: *const Sim) f32 {
    var r: f32 = 0;
    for (&s.ents) |*e| {
        if (e.kind == .calculus) r = @max(r, e.radius);
    }
    return 2 * r / 1000;
}

/// Diameter under which a piece passes, in millimetres.
pub fn limitMm() f32 {
    return 2 * neckRadius() / 1000;
}

fn neckRadius() f32 {
    return 0.5 * (radiusOf(pass_gen) + radiusOf(pass_gen - 1));
}

/// True while a piece too big to pass sits in the outlet.
pub fn blocked(s: *const Sim) bool {
    for (&s.ents) |*e| {
        if (e.kind == .calculus and e.state == 2) return true;
    }
    return false;
}

/// The notch under the bit, 0..1, if the bit is in a piece that is being scored.
pub fn notchUnderBit(s: *const Sim) ?f32 {
    for (&s.ents) |*e| {
        if (e.kind == .calculus and e.state != 1 and e.timer > 0 and !passable(e)) return e.aux;
    }
    return null;
}

pub fn flowAt(s: *const Sim, p: Vec3) Vec3 {
    return kidney.flowAt(p, s.clock);
}

pub fn focusRay(s: *const Sim, o: Vec3, d: Vec3, max_t: f32) ?game.Focus {
    _ = s;
    const h = kidney.raycast(o, d, max_t) orelse return null;
    return .{ .dist = h.t, .point = h.point, .tissue = true, .topic = switch (h.what) {
        .papilla => .renal_papilla,
        .cribrosa => .area_cribrosa,
        .duct => .duct_of_bellini,
        .calyx => .urothelium,
        .fornix => .fornix,
        .infundibulum => .infundibulum,
    } };
}

/// Chapter collision and the hazard tied to position: being caught in a jet.
pub fn moveCollide(s: *Sim, p: Vec3, dt: f32) void {
    const g = &s.g4;
    const res = kidney.collide(p, game.hull_r);
    s.pos = res.pos;

    const jet = kidney.jetsAt(s.pos, s.clock).len();
    const in = jet > 120 and s.tether == null and !s.latched;
    if (in) {
        g.jet_time += dt;
        if (!g.in_jet) {
            g.jet_hits += 1;
            if (!g.said.jet and s.stage != .k_arrive) {
                g.said.jet = true;
                s.urgent(L.thats_a_jet);
            }
        }
    }
    g.in_jet = in;
}

/// What the tether would grab right now: the tissue along the line of sight, within reach.
pub fn tetherTarget(s: *const Sim) ?kidney.RayHit {
    return kidney.raycast(s.pos, s.forward(), tether_range);
}

pub fn tetherKey(s: *Sim) void {
    const g = &s.g4;
    if (!s.has_tether) return;
    const hit = tetherTarget(s);
    if (hit != null and (s.tether == null or hit.?.point.dist(s.tether.?) > 40)) {
        const h = hit.?;
        s.tether = h.point;
        s.tether_hold = h.point.add(kidney.field(h.point.sub(s.forward().scale(2))).n.scale(38));
        g.tether_uses += 1;
        s.sound(.cut, 0, 0.9);
        s.sound(.swing, 0, 0.6);
        return;
    }
    if (s.tether != null) {
        s.tether = null;
        s.sound(.ui, 0, 0.8);
        return;
    }
    if (g.said.tether_none <= 0) {
        g.said.tether_none = 6;
        s.voice.say(L.nothing_in_reach_to_hold, .chatter);
    }
}

pub fn onIdentify(s: *Sim, tp: Topic) void {
    _ = s;
    _ = tp;
    // The script reads the atlas, so something identified ahead of its stage counts when the stage comes.
}

// ---------------------------------------------------------------------------------------------- stone

fn panOf(s: *const Sim, p: Vec3) f32 {
    return m.clamp(p.sub(s.pos).dot(s.right()) / 120, -1, 1);
}

/// Crystals loose in the calyx that came down a duct, not off the stone.
fn nativeShards(s: *const Sim) u32 {
    var n: u32 = 0;
    for (&s.ents) |*e| {
        if (e.kind == .shard and e.known) n += 1;
    }
    return n;
}

/// A shard let loose at `at`. One with `chase` seconds on it tumbles towards the drone for that long
/// before the urine takes it.
fn spawnShard(s: *Sim, at: Vec3, vel: Vec3, chase: f32) void {
    const g = &s.g4;
    if (s.count(.shard) >= max_shards) return;
    if (s.spawn(.{ .kind = .shard, .pos = at, .vel = vel, .radius = shard_r, .seed = s.rng.f(), .timer = chase, .state = if (chase > 0) @as(u8, 1) else 0, .variant = @intCast(s.rng.below(3)) }) != null) g.shards_made += 1;
}

fn breakShard(s: *Sim, idx: u16) void {
    const e = &s.ents[idx];
    if (e.kind != .shard) return;
    s.burst(e.pos, 8, 110, glass, 2, 0.4);
    s.sound(.tink, panOf(s, e.pos), 0.8);
    e.kind = .none;
    s.g4.shards_shot += 1;
    s.stats.kills += 1;
}

/// The bit comes out of whatever has just changed shape under it.
fn unlatch(s: *Sim, idx: u16) void {
    for (&s.arms) |*a| {
        if (a.latch) |lt| {
            if (lt.ent == idx) a.latch = null;
        }
    }
}

/// One piece becomes two of half the volume, parting along `axis_in`.
fn split(s: *Sim, idx: u16, axis_in: Vec3) void {
    const e = &s.ents[idx];
    // a piece wedged in the outlet has room to part only along the tube
    const axis = if (e.state == 2) Vec3.up else axis_in;
    const c = e.pos;
    const r2 = e.radius * shrink;
    const gen = e.variant + 1;
    s.burst(c, 40, 220, ivory, 4, 0.7);
    e.radius = r2;
    e.variant = gen;
    e.state = 0;
    e.aux = 0;
    e.timer = 0;
    e.flash = 1;
    e.pos = c.add(axis.scale(0.62 * r2));
    e.vel = axis.scale(55);
    e.end = axis;
    _ = s.spawn(.{ .kind = .calculus, .pos = c.sub(axis.scale(0.62 * r2)), .vel = axis.scale(-55), .end = axis.neg(), .radius = r2, .variant = gen, .seed = s.rng.f(), .flash = 1 });
    unlatch(s, idx);
    s.sound(.shatter, 0, 0.9);
    s.shake = @max(s.shake, 0.4);
    s.progress();
}

/// A direction across the line of the blow for the halves to part along: to the pilot's left and right.
fn partingAxis(s: *const Sim, dir: Vec3) Vec3 {
    const r = s.right();
    const a = r.sub(dir.scale(r.dot(dir)));
    return if (a.len() > 0.1) a.norm() else dir.perp();
}

fn cleanSplit(s: *Sim, idx: u16, dir: Vec3) void {
    const g = &s.g4;
    split(s, idx, partingAxis(s, dir));
    g.clean_splits += 1;
    s.stabilise(2);
    if (!g.said.first_split) {
        g.said.first_split = true;
        s.say(L.two_clean_halves);
    }
}

/// A blow on stone with no notch under it: the surface is crushed, and what comes off is shards.
fn bareBlow(s: *Sim, idx: u16, dir: Vec3) void {
    const g = &s.g4;
    const e = &s.ents[idx];
    const at = e.pos.sub(dir.scale(e.radius + shard_r + 2));
    g.bad_punches += 1;
    e.flash = 1;
    e.aux = 0;
    s.burst(at, 16, 160, ivory, 3, 0.5);
    s.sound(.tink, 0, 1);
    const side = dir.perp();
    const up = dir.cross(side);
    for (0..3) |i| {
        const a = m.tau * (@as(f32, @floatFromInt(i)) / 3.0 + s.rng.f() * 0.2);
        const off = side.scale(@cos(a)).add(up.scale(@sin(a)));
        spawnShard(s, at.add(off.scale(26)), off.scale(90).sub(dir.scale(40)), 1.8);
    }
    if (e.state == 1) {
        // on its stalk the stone hands the blow to the papilla
        s.tissueDamage(2.5, true);
        if (!g.said.stalk) {
            g.said.stalk = true;
            s.urgent(L.not_while_its_on_the_stalk);
        }
    } else if (!g.said.bare) {
        g.said.bare = true;
        s.urgent(L.not_without_a_notch);
    }
}

/// A Sync punch with Resonance: the blow goes out ahead as a wave that parts every piece in front of the
/// drone that is still too big, and breaks the shards in its way.
pub fn syncWave(s: *Sim) void {
    const g = &s.g4;
    if (!g.has_resonance) return;
    const f = s.forward();
    var hit: [16]u16 = undefined;
    var n: usize = 0;
    for (&s.ents, 0..) |*e, idx| {
        const d = e.pos.sub(s.pos);
        switch (e.kind) {
            .calculus => {
                if (e.state == 1 or passable(e) or n >= hit.len) continue;
                const along = d.dot(f);
                if (along <= 0 or d.len() - e.radius > wave_reach) continue;
                if (d.sub(f.scale(along)).len() > e.radius + 140) continue;
                hit[n] = @intCast(idx);
                n += 1;
            },
            .shard => {
                const dl = d.len();
                if (dl < 80 or (dl < wave_reach and d.dot(f) > 0.8 * dl)) breakShard(s, @intCast(idx));
            },
            else => {},
        }
    }
    s.burst(s.pos.add(f.scale(60)), 30, 520, .{ 0.7, 0.95, 1, 1 }, 3, 0.5);
    for (hit[0..n]) |idx| {
        const e = &s.ents[idx];
        const dir = e.pos.sub(s.pos).norm();
        // a wave is a rougher tool than a notch: one sliver comes back off each piece it parts
        const at = e.pos.sub(dir.scale(e.radius + shard_r + 2));
        split(s, idx, partingAxis(s, dir));
        spawnShard(s, at, dir.scale(-60), 4);
        g.wave_splits += 1;
        s.stabilise(1);
    }
    if (n >= 2 and !g.said.line_up) g.said.line_up = true;
    if (n == 0 and s.stage == .k_resonance and !g.said.wave_miss) {
        g.said.wave_miss = true;
        s.say(L.nothing_in_that_wave);
    }
}

pub fn punched(s: *Sim, idx: u16, dir: Vec3, sync: bool) void {
    const g = &s.g4;
    const e = &s.ents[idx];
    switch (e.kind) {
        .calculus => {
            // with Resonance a Sync punch is the wave, which does its own work
            if (sync and g.has_resonance) return;
            if (e.state != 1 and passable(e)) {
                e.vel = e.vel.add(dir.scale(80));
                e.flash = 0.5;
            } else if (e.state != 1 and e.aux >= notch_enough) {
                cleanSplit(s, idx, dir);
            } else {
                bareBlow(s, idx, dir);
            }
        },
        .plaque => e.flash = 0.5,
        .shard => {
            e.vel = e.vel.add(dir.scale(220));
            e.state = 0;
        },
        else => {},
    }
}

/// Returns true when the round is spent.
pub fn shotHit(s: *Sim, sh: *game.Shot, idx: u16, at: Vec3) bool {
    const g = &s.g4;
    const e = &s.ents[idx];
    switch (e.kind) {
        .shard => {
            breakShard(s, idx);
            s.arms[sh.arm].flash = 1;
            return !sh.lance;
        },
        .calculus, .plaque => {
            s.burst(at, 5, 60, ivory, 2.5, 0.4);
            s.sound(.absorb, 0, 0.5);
            if (!g.said.rounds and e.kind == .calculus and s.stage != .k_jets and s.stage != .k_duct) {
                g.said.rounds = true;
                s.say(L.rounds_do_nothing_to_stone);
            }
            return true;
        },
        else => return false,
    }
}

/// Where the drill is heard: on the side of the arm that carries it.
fn drillPan(s: *const Sim) f32 {
    if (s.arms[0].tool == .drill and s.arms[0].held) return -0.7;
    if (s.arms[1].tool == .drill and s.arms[1].held) return 0.7;
    return 0;
}

fn cutStalk(s: *Sim, idx: u16) void {
    const g = &s.g4;
    const e = &s.ents[idx];
    g.neck_cut = true;
    // what is left is the plaque itself, flush with the papilla
    e.state = 1;
    e.radius = 60;
    e.pos = plaqueSite().add(e.end.scale(10));
    e.flash = 1;
    unlatch(s, idx);
    for (&s.ents) |*st| {
        if (st.kind == .calculus and st.state == 1) {
            st.state = 0;
            st.vel = e.end.scale(45);
            st.flash = 1;
        }
    }
    s.burst(e.pos.add(e.end.scale(60)), 40, 150, ivory, 3.5, 0.8);
    s.sound(.shatter, 0, 1);
    s.sound(.objective, 0, 1);
    s.stabilise(4);
    s.voice.clear();
    s.setStage(.k_split);
}

/// Returns true while the bit is working.
pub fn drilled(s: *Sim, idx: u16, point: Vec3, rate: f32, dt: f32, spark: bool) bool {
    const g = &s.g4;
    const e = &s.ents[idx];
    switch (e.kind) {
        .shard => {
            breakShard(s, idx);
            return true;
        },
        .plaque => {
            s.latched = true;
            if (e.state != 0) return true;
            e.hp -= rate * dt;
            e.flash = 0.6;
            if (spark) s.burst(point, 3, 100, ivory, 2.2, 0.35);
            // the stone above rings with the bit, and lets go of crystals
            g.shed_t -= dt;
            if (g.shed_t <= 0) {
                g.shed_t = 1.5;
                shedOver(s);
            }
            if (!g.said.neck_half and e.hp < 0.5 * e.max_hp) {
                g.said.neck_half = true;
                s.voice.say(L.half_through_the_stalk, .chatter);
            }
            if (e.hp <= 0) cutStalk(s, idx);
            return true;
        },
        .calculus => {
            s.latched = true;
            if (spark) s.burst(point, 3, 110, ivory, 2.2, 0.35);
            if (e.state == 1) {
                if (!g.said.stalk and s.stage_t > 2) {
                    g.said.stalk = true;
                    s.say(L.not_while_its_on_the_stalk);
                }
                return true;
            }
            if (passable(e)) return true;
            // the bit holds the piece still while it cuts
            e.timer = 0.25;
            e.vel = .{};
            const was = e.aux;
            e.aux = @min(1, e.aux + rate * dt / score_time);
            if (was < 1 and e.aux >= 1) {
                e.flash = 1;
                s.sound(.tink, drillPan(s), 1);
            }
            return true;
        },
        else => return false,
    }
}

/// A crystal comes off the underside of the stone near the drone and tumbles towards it.
fn shedOver(s: *Sim) void {
    const g = &s.g4;
    for (&s.ents) |*st| {
        if (st.kind != .calculus or st.state != 1) continue;
        const a = s.rng.f() * m.tau;
        const lateral = v3(@cos(a), 0, @sin(a)).scale(s.rng.range(170, 260));
        const dir = s.pos.add(lateral).sub(st.pos).norm();
        const at = st.pos.add(dir.scale(st.radius + shard_r + 3));
        spawnShard(s, at, .{}, 6);
        s.sound(.tink, panOf(s, at), 0.6);
        if (!g.said.shard) {
            g.said.shard = true;
            s.urgent(L.shard_coming);
        }
        return;
    }
}

/// A round reached the lining.
pub fn shotTissue(s: *Sim, h: kidney.RayHit) void {
    s.burst(h.point, 6, 50, .{ 1, 0.4, 0.3, 1 }, 3, 0.5);
    s.tissueDamage(1.5, true);
}

/// Height on the axis at which a sphere of this radius can rise no further: seated in the rim of the
/// outlet, or wedged where the infundibulum has narrowed to its size. Null if it goes through.
pub fn stopY(r: f32) ?f32 {
    if (r >= kidney.outlet_r) return kidney.mouth_y - @sqrt(r * r - kidney.outlet_r * kidney.outlet_r);
    if (r <= kidney.neck_r) return null;
    var lo: f32 = kidney.mouth_y;
    var hi: f32 = kidney.mouth_y + kidney.neck_len;
    for (0..24) |_| {
        const mid = 0.5 * (lo + hi);
        if (kidney.tubeR(mid) > r) lo = mid else hi = mid;
    }
    return lo;
}

/// Keeps a piece of stone out of the papilla, under the dome and inside the infundibulum. The pieces are
/// as big as the outlet, so the general collision, which wants room on every side, does not serve.
fn fragmentCollide(p_in: Vec3, r: f32) Vec3 {
    var p = p_in;
    for (0..4) |_| {
        const rho = @sqrt(p.x * p.x + p.z * p.z);
        const gp = 2 * rho / kidney.a_pap;
        const dp = (p.y - kidney.papillaY(p.x, p.z)) / @sqrt(1 + gp * gp);
        if (dp < r) p = p.add(kidney.papillaNormal(p.x, p.z).scale(r - dp));

        if (p.y >= kidney.mouth_y) {
            // in the tube: on the axis as far as it fits
            const room = @max(0, kidney.tubeR(p.y) - r);
            const rr = @sqrt(p.x * p.x + p.z * p.z);
            if (rr > room) {
                const k = room / @max(rr, 1e-3);
                p.x *= k;
                p.z *= k;
            }
            continue;
        }
        const gw = 2 * rho / kidney.b_wall;
        const dw = (kidney.wallY(p.x, p.z) - p.y) / @sqrt(1 + gw * gw);
        if (dw >= r) continue;
        const to_wall = v3(2 * p.x / kidney.b_wall, 1, 2 * p.z / kidney.b_wall).norm();
        const touch = p.add(to_wall.scale(dw));
        if (touch.x * touch.x + touch.z * touch.z < kidney.outlet_r * kidney.outlet_r) {
            // under the opening: only its rim is in the way
            const rim = if (rho > 1e-3) v3(p.x / rho * kidney.outlet_r, kidney.mouth_y, p.z / rho * kidney.outlet_r) else v3(kidney.outlet_r, kidney.mouth_y, 0);
            const d = p.sub(rim);
            const dl = d.len();
            if (dl < r and rho > 1e-3) p = rim.add(d.scale(r / @max(dl, 1e-3)));
        } else {
            p = p.sub(to_wall.scale(r - dw));
        }
    }
    if (stopY(r)) |top| p.y = @min(p.y, top);
    return p;
}

fn lodge(s: *Sim, idx: u16) void {
    const g = &s.g4;
    const e = &s.ents[idx];
    e.state = 2;
    e.vel = .{};
    g.lodged += 1;
    s.sound(.bump, 0, 1);
    s.shake = @max(s.shake, 0.3);
    if (!g.said.lodged) {
        g.said.lodged = true;
        s.urgent(L.a_piece_is_in_the_outlet);
    }
}

fn updateFragment(s: *Sim, idx: u16, dt: f32) void {
    const g = &s.g4;
    const e = &s.ents[idx];
    const held = e.timer > 0;
    e.timer = @max(0, e.timer - dt);
    if (e.state == 1) return;
    if (!held) e.aux = @max(0, e.aux - 0.6 * dt);
    if (held or e.state == 2) return;

    const fl = kidney.flowAt(e.pos, s.clock);
    e.vel = e.vel.add(fl.sub(e.vel).scale(1 - @exp(-1.2 * dt)));
    var p = e.pos.add(e.vel.scale(dt));
    // pieces shoulder one another aside
    for (&s.ents, 0..) |*o, j| {
        if (o.kind != .calculus or j == idx) continue;
        const d = p.sub(o.pos);
        const dl = d.len();
        const over = e.radius + o.radius - dl;
        if (over <= 0) continue;
        const dir = if (dl > 1) d.scale(1 / dl) else Vec3.up;
        p = p.add(dir.scale(@min(over, 110 * dt)));
    }
    p = fragmentCollide(p, e.radius);
    e.pos = p;

    const rho = @sqrt(p.x * p.x + p.z * p.z);
    if (passable(e)) {
        if (p.y > kidney.mouth_y + 500 and !blockedAbove(s, p.y)) {
            e.kind = .none;
            g.passed += 1;
            s.sound(.escape, 0, 0.5);
            if (!g.said.passed) {
                g.said.passed = true;
                s.voice.say(L.that_piece_will_pass, .chatter);
            }
        }
    } else if (stopY(e.radius)) |top| {
        if (p.y >= top - 3 and rho < 90) lodge(s, idx);
    }
}

/// True if a wedged piece sits in the tube above this height.
fn blockedAbove(s: *const Sim, y: f32) bool {
    for (&s.ents) |*e| {
        if (e.kind == .calculus and e.state == 2 and e.pos.y > y) return true;
    }
    return false;
}

fn updateShard(s: *Sim, idx: u16, dt: f32) void {
    const g = &s.g4;
    const e = &s.ents[idx];
    const to = s.pos.sub(e.pos);
    const dl = to.len();
    if (dl < game.hull_r + e.radius + 3 and g.cut_cd <= 0) {
        s.burst(e.pos, 8, 110, glass, 2, 0.4);
        e.kind = .none;
        g.cuts += 1;
        g.cut_cd = 0.8;
        s.hurtDrone(9);
        s.sound(.tink, 0, 1);
        if (!g.said.cut) {
            g.said.cut = true;
            s.say(L.that_one_cut_the_hull);
        }
        return;
    }
    e.timer = @max(0, e.timer - dt);
    var want = kidney.flowAt(e.pos, s.clock).scale(0.9);
    if (e.state == 1) {
        if (e.timer <= 0 or dl > 700) {
            e.state = 0;
        } else {
            want = to.scale(75 / @max(dl, 1));
        }
    }
    e.vel = e.vel.add(want.sub(e.vel).scale(1 - @exp(-1.6 * dt)));
    const p = e.pos.add(e.vel.scale(dt));
    if (p.y > kidney.mouth_y + 300) {
        // gone down the ureter, to scratch at everything on the way. What came out of a duct was going
        // that way regardless; what came off the stone is the pilot's doing.
        e.kind = .none;
        if (!e.known) {
            g.shards_escaped += 1;
            s.stability = @max(0, s.stability - 0.8);
        }
        return;
    }
    // a crystal does not pass through stone
    var q = kidney.collide(p, e.radius).pos;
    for (&s.ents) |*o| {
        if (o.kind != .calculus) continue;
        const d = q.sub(o.pos);
        const d2 = d.len();
        if (d2 < o.radius + e.radius and d2 > 1) q = o.pos.add(d.scale((o.radius + e.radius) / d2));
    }
    e.pos = q;
}

pub fn updateEntity(s: *Sim, idx: u16, dt: f32) void {
    switch (s.ents[idx].kind) {
        .calculus => updateFragment(s, idx, dt),
        .shard => updateShard(s, idx, dt),
        else => {},
    }
}

// ---------------------------------------------------------------------------------------------- script

/// The piece to work on next: the nearest that is still too big, with one in the outlet ahead of the rest.
pub fn nextPiece(s: *const Sim) ?*const game.Entity {
    var best: f32 = 1e12;
    var out: ?*const game.Entity = null;
    for (&s.ents) |*e| {
        if (e.kind != .calculus or passable(e)) continue;
        var d = e.pos.dist(s.pos) - e.radius;
        if (e.state == 2) d -= 1e6;
        if (d < best) {
            best = d;
            out = e;
        }
    }
    return out;
}

fn minGeneration(s: *const Sim) ?u8 {
    var out: ?u8 = null;
    for (&s.ents) |*e| {
        if (e.kind == .calculus) out = @min(out orelse 255, e.variant);
    }
    return out;
}

fn jets(s: *Sim, dt: f32) void {
    for (0..kidney.duct_count) |i| {
        const k = kidney.jetStrength(i, s.clock);
        if (k <= 0) continue;
        const at = kidney.ductPos(i);
        const dist = at.dist(s.pos);
        if (dist > 1800) continue;
        if (kidney.jetStrength(i, s.clock - dt) <= 0) {
            s.sound(.jet, panOf(s, at), m.clamp(1.2 - dist / 1500, 0.15, 1));
            // a spurt brings a crystal down the duct with it
            if (dist < 900 and s.stage != .k_arrive and nativeShards(s) < max_native and s.count(.shard) < max_shards) {
                const n = kidney.ductNormal(i);
                if (s.spawn(.{ .kind = .shard, .pos = at.add(n.scale(shard_r + 4)), .vel = n.scale(200), .radius = shard_r, .seed = s.rng.f(), .known = true, .variant = @intCast(s.rng.below(3)) }) != null and !s.g4.said.native and dist < 600) {
                    s.g4.said.native = true;
                    s.say(L.the_jets_carry_crystals);
                }
            }
        }
        if (s.rng.f() < dt * 22 * k) {
            const n = kidney.ductNormal(i);
            s.burst(at.add(n.scale(8)), 1, 26, straw, 5, 1.2);
            const last = &s.parts[(s.part_cursor + game.max_parts - 1) % game.max_parts];
            last.vel = last.vel.add(n.scale(kidney.jet_speed * k));
            last.drag = 0.9;
        }
    }
}

pub fn script(s: *Sim, dt: f32) void {
    const g = &s.g4;
    g.said.tether_none = @max(0, g.said.tether_none - dt);
    g.cut_cd = @max(0, g.cut_cd - dt);
    jets(s, dt);
    if (s.stall_t > 55 and !s.said.stall) {
        s.said.stall = true;
        s.voice.say(L.if_you_want_a_pointer, .chatter);
    }
    // A calyx that cannot drain is a part of the kidney under pressure.
    const now_blocked = blocked(s);
    if (now_blocked) {
        g.blocked_t += dt;
        s.stability = @max(0, s.stability - blocked_rate * dt);
    } else if (g.was_blocked) {
        s.voice.say(L.its_draining_again, .chatter);
    }
    g.was_blocked = now_blocked;

    const seen = struct {
        fn any(sim: *const Sim, topics: []const Topic) bool {
            for (topics) |t| {
                if (sim.atlas[@intFromEnum(t)]) return true;
            }
            return false;
        }
    };
    switch (s.stage) {
        .k_arrive => if (s.stage_t > 6.5) s.setStage(.k_duct),
        .k_duct => if (seen.any(s, &.{ .duct_of_bellini, .area_cribrosa, .renal_papilla })) s.setStage(.k_jets),
        .k_jets => if (stalk(s)) |e| {
            if (s.pos.dist(e.pos) < 420) s.setStage(.k_stone);
        },
        .k_stone => if (seen.any(s, &.{ .kidney_stone, .randalls_plaque })) s.setStage(.k_neck),
        .k_neck => {},
        .k_split => {
            s.waypoint = if (nextPiece(s)) |e| e.pos else null;
            if (minGeneration(s)) |gen| {
                if (gen >= upgrade_gen) {
                    g.ready_t += dt;
                    if (g.ready_t > 1.5) s.mode = .upgrade_card;
                }
            }
        },
        .k_resonance => {
            s.waypoint = if (nextPiece(s)) |e| e.pos else null;
            if (!g.said.line_up and s.stage_t > 9 and oversized(s) >= 2) {
                g.said.line_up = true;
                s.voice.say(L.line_them_up, .chatter);
            }
            if (oversized(s) == 0) {
                g.done_t += dt;
                if (g.done_t > 2.5) s.setStage(.k_exit);
            }
        },
        .k_exit => if (s.atRing(4)) {
            s.say(L.renal_vein_next);
            s.setStage(.done);
        },
        else => {},
    }
}

pub fn gradePenalty(s: *const Sim) f32 {
    const g = &s.g4;
    return @as(f32, @floatFromInt(g.lodged)) * 3 + @as(f32, @floatFromInt(g.bad_punches)) * 1.5 + @as(f32, @floatFromInt(g.shards_escaped)) * 0.5;
}

/// Centimetres to the neck of the calyx, for the HUD.
pub fn locationCm(s: *const Sim) f32 {
    return s.pos.dist(kidney.outlet()) / 10000.0;
}

// ---------------------------------------------------------------------------------------------- tests

fn settle(s: *Sim, c: game.Controls, seconds: f32) void {
    const dt: f32 = 1.0 / 60.0;
    var t: f32 = 0;
    while (t < seconds) : (t += dt) s.update(c, dt);
}

fn lookAt(s: *Sim, p: Vec3) void {
    const d = p.sub(s.pos).norm();
    s.yaw = std.math.atan2(d.x, d.z);
    s.pitch = std.math.asin(d.y);
}

/// A sim with the stalk already cut and the stone hanging free where it grew.
fn freed(s: *Sim) *game.Entity {
    s.* = Sim.initChapter(3);
    s.voice.clear();
    s.stage = .k_split;
    const st = s.find(.calculus).?;
    st.state = 0;
    s.g4.neck_cut = true;
    return st;
}

/// Puts the drone against a piece on the side of the papilla's axis, bit within reach, looking at it.
fn standAt(s: *Sim, e: *const game.Entity) void {
    const out = v3(0, 0.3, -1).norm();
    s.pos = e.pos.add(out.scale(e.radius + game.hull_r + 10));
    s.vrel = .{};
    s.flow = .{};
    lookAt(s, e.pos);
}

test "the stone hangs on its stalk until the stalk is drilled through, and shards come while it is drilled" {
    const gpa = std.testing.allocator;
    const s = try gpa.create(Sim);
    defer gpa.destroy(s);
    s.* = Sim.initChapter(3);
    s.voice.clear();
    s.stage = .k_neck;
    const st = s.find(.calculus).?;
    const at = st.pos;
    settle(s, .{}, 3);
    try std.testing.expectEqual(at, st.pos);
    try std.testing.expectEqual(@as(u8, 1), st.state);

    // the stand point is clear of the stone and the papilla, and the bit reaches the stalk from it
    const e = s.find(.plaque).?;
    try std.testing.expect(kidney.clear(standPoint(), game.hull_r + 2));
    try std.testing.expect(standPoint().dist(st.pos) > st.radius + game.hull_r + 20);
    s.pos = standPoint();
    s.arms = .{ .{ .tool = .shoot }, .{ .tool = .drill } };
    var t: f32 = 0;
    var cool = false;
    while (t < 20 and !s.g4.neck_cut) : (t += 1.0 / 60.0) {
        // a pilot who lets the bit cool when it runs hot, and holds station meanwhile
        if (s.arms[1].heat > 0.92) cool = true;
        if (s.arms[1].heat < 0.5) cool = false;
        if (!s.arms[1].engaged) {
            s.pos = standPoint();
            s.vrel = .{};
            s.flow = .{};
        }
        lookAt(s, e.pos);
        s.update(.{ .arm = .{ false, !cool } }, 1.0 / 60.0);
    }
    try std.testing.expect(s.g4.neck_cut);
    try std.testing.expectEqual(Stage.k_split, s.stage);
    try std.testing.expect(s.g4.shards_made >= 2);
    try std.testing.expectEqual(@as(u8, 0), st.state);
    // free, it drifts towards the outlet
    const d0 = st.pos.dist(kidney.outlet());
    s.arms[1].held = false;
    s.pos = v3(0, 1500, -1500);
    settle(s, .{}, 4);
    try std.testing.expect(st.pos.dist(kidney.outlet()) < d0 - 20);
}

test "a notch and a blow part a piece in two halves; a blow with no notch makes shards and no pieces" {
    const gpa = std.testing.allocator;
    const s = try gpa.create(Sim);
    defer gpa.destroy(s);
    const st = freed(s);
    standAt(s, st);
    s.arms = .{ .{ .tool = .punch }, .{ .tool = .drill } };

    // a bare blow
    s.update(.{ .arm = .{ true, false } }, 1.0 / 60.0);
    settle(s, .{}, 0.4);
    try std.testing.expectEqual(@as(u32, 1), s.g4.bad_punches);
    try std.testing.expectEqual(@as(u32, 1), s.count(.calculus));
    try std.testing.expectEqual(@as(u32, 3), s.count(.shard));
    try std.testing.expectEqual(@as(u32, 0), s.g4.clean_splits);
    for (&s.ents) |*e| {
        if (e.kind == .shard) e.kind = .none;
    }

    // notch, then the blow with the bit still in
    standAt(s, st);
    var t: f32 = 0;
    while (t < 5 and st.aux < 1) : (t += 1.0 / 60.0) {
        lookAt(s, st.pos);
        s.update(.{ .arm = .{ false, true } }, 1.0 / 60.0);
    }
    try std.testing.expect(st.aux >= 1);
    try std.testing.expect(t > score_time - 0.2 and t < score_time + 0.4);
    try std.testing.expectEqual(@as(?f32, 1), notchUnderBit(s));
    t = 0;
    while (t < 0.5) : (t += 1.0 / 60.0) s.update(.{ .arm = .{ true, true } }, 1.0 / 60.0);
    try std.testing.expectEqual(@as(u32, 1), s.g4.clean_splits);
    try std.testing.expectEqual(@as(u32, 1), s.g4.bad_punches);
    try std.testing.expectEqual(@as(u32, 2), s.count(.calculus));
    try std.testing.expectEqual(@as(u32, 0), s.count(.shard));
    var volume: f32 = 0;
    for (&s.ents) |*e| {
        if (e.kind != .calculus) continue;
        try std.testing.expectEqual(@as(u8, 1), e.variant);
        try std.testing.expectApproxEqAbs(radiusOf(1), e.radius, 0.01);
        volume += e.radius * e.radius * e.radius;
    }
    try std.testing.expectApproxEqRel(stone_r * stone_r * stone_r, volume, 0.01);
    try std.testing.expect(s.stats.dual_time > 0.2);

    // a notch left alone closes up: the blow has to come while the bit is in, or just after
    const piece = s.find(.calculus).?;
    piece.aux = 1;
    settle(s, .{}, 1.0);
    try std.testing.expect(piece.aux < notch_enough);
}

test "a piece too big for the outlet wedges in it and costs stability until it is split; small ones pass" {
    const gpa = std.testing.allocator;
    const s = try gpa.create(Sim);
    defer gpa.destroy(s);
    const st = freed(s);
    s.pos = v3(0, 400, -1800);
    st.pos = v3(0, 1700, 0);
    const before = s.stability;
    settle(s, .{}, 40);
    try std.testing.expectEqual(@as(u8, 2), st.state);
    try std.testing.expectEqual(@as(u32, 1), s.g4.lodged);
    try std.testing.expect(blocked(s));
    try std.testing.expect(s.g4.blocked_t > 2);
    try std.testing.expect(s.stability < before - 1);
    // seated in the rim: touching it, not through it
    try std.testing.expectApproxEqAbs(stopY(stone_r).?, st.pos.y, 4);
    try std.testing.expect(st.pos.y < kidney.mouth_y);

    // what wedges, by size: the whole stone in the rim, halves to eighths ever deeper in the taper, and
    // sixteenths nowhere
    try std.testing.expect(stopY(radiusOf(1)).? > kidney.mouth_y);
    try std.testing.expect(stopY(radiusOf(2)).? > stopY(radiusOf(1)).?);
    try std.testing.expect(stopY(radiusOf(3)).? > stopY(radiusOf(2)).?);
    try std.testing.expectEqual(@as(?f32, null), stopY(radiusOf(4)));
    try std.testing.expect(limitMm() > 2 * radiusOf(4) / 1000 and limitMm() < 2 * radiusOf(3) / 1000);

    // a sixteenth let go under the outlet leaves by it
    s.* = Sim.initChapter(3);
    s.voice.clear();
    s.stage = .k_split;
    s.pos = v3(0, 400, -1800);
    const i = s.spawn(.{ .kind = .calculus, .pos = v3(200, 1900, 0), .radius = radiusOf(4), .variant = 4 }).?;
    settle(s, .{}, 40);
    try std.testing.expectEqual(game.Kind.none, s.ents[i].kind);
    try std.testing.expectEqual(@as(u32, 1), s.g4.passed);
    try std.testing.expectEqual(@as(u32, 0), s.g4.lodged);
}

test "Resonance: a Sync punch parts every oversized piece ahead within reach, once each, and breaks shards" {
    const gpa = std.testing.allocator;
    const s = try gpa.create(Sim);
    defer gpa.destroy(s);
    const st = freed(s);
    st.kind = .none;
    s.pos = v3(0, 1200, -900);
    s.yaw = 0;
    s.pitch = 0;
    s.arms = .{ .{ .tool = .punch }, .{ .tool = .punch } };
    const r = radiusOf(3);
    // two side by side ahead, one behind, one ahead but out of reach, one small enough already
    const here = s.pos;
    const left = s.spawn(.{ .kind = .calculus, .pos = here.add(v3(-340, 0, 400)), .radius = r, .variant = 3 }).?;
    const right = s.spawn(.{ .kind = .calculus, .pos = here.add(v3(340, 0, 400)), .radius = r, .variant = 3 }).?;
    const behind = s.spawn(.{ .kind = .calculus, .pos = here.add(v3(0, 0, -(r + 200))), .radius = r, .variant = 3 }).?;
    const beyond = s.spawn(.{ .kind = .calculus, .pos = here.add(v3(0, 0, 1700)), .radius = r, .variant = 3 }).?;
    const small = s.spawn(.{ .kind = .calculus, .pos = here.add(v3(0, 600, 300)), .radius = radiusOf(4), .variant = 4 }).?;
    const sh = s.spawn(.{ .kind = .shard, .pos = here.add(v3(10, 0, 150)), .radius = shard_r }).?;
    const all = [_]u16{ left, right, behind, beyond, small };
    var home: [all.len]Vec3 = undefined;
    for (all, 0..) |i, k| home[k] = s.ents[i].pos;

    // without the upgrade a Sync punch reaches arm's length and no further
    s.update(.{ .arm = .{ true, true } }, 1.0 / 60.0);
    settle(s, .{}, 0.6);
    try std.testing.expectEqual(@as(u32, 0), s.g4.wave_splits);
    try std.testing.expectEqual(@as(u32, 0), s.g4.bad_punches);
    try std.testing.expectEqual(@as(u32, 5), s.count(.calculus));
    try std.testing.expectEqual(game.Kind.shard, s.ents[sh].kind);

    upgradeTaken(s);
    s.voice.clear();
    s.pos = here;
    s.vrel = .{};
    s.flow = .{};
    for (all, 0..) |i, k| {
        s.ents[i].pos = home[k];
        s.ents[i].vel = .{};
    }
    s.ents[sh].pos = here.add(v3(10, 0, 150));
    s.update(.{ .arm = .{ true, true } }, 1.0 / 60.0);
    settle(s, .{}, 0.3);
    try std.testing.expectEqual(@as(u32, 2), s.g4.wave_splits);
    try std.testing.expectEqual(@as(u32, 0), s.g4.bad_punches);
    try std.testing.expectEqual(@as(u32, 7), s.count(.calculus));
    try std.testing.expectEqual(@as(u8, 3), s.ents[behind].variant);
    try std.testing.expectEqual(@as(u8, 3), s.ents[beyond].variant);
    try std.testing.expectEqual(@as(u8, 4), s.ents[small].variant);
    try std.testing.expectEqual(@as(u8, 4), s.ents[left].variant);
    try std.testing.expectEqual(@as(u8, 4), s.ents[right].variant);
    // the shard that was in the way is gone, and each piece parted has thrown one back
    try std.testing.expectEqual(@as(u32, 1), s.g4.shards_shot);
    try std.testing.expectEqual(@as(u32, 2), s.count(.shard));
    try std.testing.expectEqual(@as(u32, 2), oversized(s));
    try std.testing.expect(s.stats.sync_strikes >= 2);
}

test "a shard cuts the hull once and is spent; a round breaks one; one that leaves by the outlet costs her" {
    const gpa = std.testing.allocator;
    const s = try gpa.create(Sim);
    defer gpa.destroy(s);
    s.* = Sim.initChapter(3);
    s.voice.clear();
    s.stage = .k_split;
    s.pos = v3(0, 1000, -1200);
    s.yaw = 0;
    s.pitch = 0;
    // one tumbling at the drone
    const a = s.spawn(.{ .kind = .shard, .pos = s.pos.add(v3(0, 0, 120)), .radius = shard_r, .state = 1, .timer = 6 }).?;
    settle(s, .{}, 4);
    try std.testing.expectEqual(game.Kind.none, s.ents[a].kind);
    try std.testing.expectEqual(@as(u32, 1), s.g4.cuts);
    try std.testing.expectEqual(@as(f32, 91), s.hull);

    // one shot on its way in
    s.pos = v3(0, 1000, -1200);
    s.vrel = .{};
    const b = s.spawn(.{ .kind = .shard, .pos = s.pos.add(v3(0, 0, 300)), .radius = shard_r, .state = 1, .timer = 6 }).?;
    var t: f32 = 0;
    while (t < 3 and s.ents[b].kind == .shard) : (t += 1.0 / 60.0) {
        lookAt(s, s.ents[b].pos);
        s.update(.{ .arm = .{ true, false } }, 1.0 / 60.0);
    }
    try std.testing.expectEqual(game.Kind.none, s.ents[b].kind);
    try std.testing.expectEqual(@as(u32, 1), s.g4.shards_shot);
    try std.testing.expectEqual(@as(f32, 91), s.hull);

    // one let go under the outlet
    const before = s.stability;
    _ = s.spawn(.{ .kind = .shard, .pos = v3(60, kidney.mouth_y - 200, 0), .radius = shard_r }).?;
    settle(s, .{}, 12);
    try std.testing.expectEqual(@as(u32, 1), s.g4.shards_escaped);
    try std.testing.expect(s.stability < before);
}

test "a jet carries the drone off, and the tether holds it against one" {
    const gpa = std.testing.allocator;
    const s = try gpa.create(Sim);
    defer gpa.destroy(s);
    s.* = Sim.initChapter(3);
    s.voice.clear();
    s.stage = .k_jets;
    const duct: usize = 4;
    const n = kidney.ductNormal(duct);
    const over = kidney.ductPos(duct).add(n.scale(80));
    // wait for the duct to be about to fire
    while (kidney.jetEta(duct, s.clock) > 0.1 or kidney.jetEta(duct, s.clock) == 0) s.clock += 0.05;
    const t0 = s.clock;
    s.pos = over;
    settle(s, .{}, 1.2);
    try std.testing.expect(s.pos.sub(over).dot(n) > 200);
    try std.testing.expect(s.g4.jet_time > 0.5);
    try std.testing.expectEqual(@as(u32, 1), s.g4.jet_hits);

    // the same spurt, on the line
    s.* = Sim.initChapter(3);
    s.voice.clear();
    s.stage = .k_jets;
    s.clock = t0;
    s.pos = over;
    lookAt(s, kidney.ductPos(duct).add(n.perp().scale(120)));
    s.update(.{ .tether = true }, 1.0 / 60.0);
    try std.testing.expect(s.tether != null);
    settle(s, .{}, 2.0);
    try std.testing.expect(s.pos.dist(s.tether_hold) < 30);
    try std.testing.expectEqual(@as(f32, 0), s.g4.jet_time);
}
