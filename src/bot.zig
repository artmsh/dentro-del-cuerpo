//! Scripted pilot. It plays chapter 1 through the same Controls a person produces, which makes it the
//! end-to-end check that the chapter can be finished, and the driver for the on-screen demo run.

const std = @import("std");
const m = @import("math.zig");
const game = @import("game.zig");
const vein_mod = @import("vein.zig");
const gut = @import("gut.zig");
const ch2 = @import("ch2.zig");
const stomach = @import("stomach.zig");
const ch3 = @import("ch3.zig");
const kidney = @import("kidney.zig");
const ch4 = @import("ch4.zig");
const Vec3 = m.Vec3;
const v3 = m.v3;
const Vein = vein_mod.Vein;
const Sim = game.Sim;
const Controls = game.Controls;

pub const Bot = struct {
    phase: u8 = 0,
    stage: game.Stage = .needle,
    tap_cd: f32 = 0,
    cooling: bool = false,

    fn flyTo(s: *const Sim, c: *Controls, target: Vec3, fast: bool) f32 {
        const d = target.sub(s.pos);
        const dist = d.len();
        const want_speed = @min(if (fast) game.boost_speed else game.cruise_speed, dist * 3.0);
        const want = d.norm().scale(want_speed);
        const flow = if (s.latched) Vec3.zero else s.worldFlow(s.pos);
        const rel = want.sub(flow);
        const boost = rel.len() > game.cruise_speed * 0.95;
        const top: f32 = if (boost) game.boost_speed else game.cruise_speed;
        var mv = v3(rel.dot(s.right()), rel.dot(s.upVec()), rel.dot(s.forward())).scale(1.0 / top);
        const l = mv.len();
        if (l > 1) mv = mv.scale(1 / l);
        c.move = mv;
        c.boost = boost;
        return dist;
    }

    /// Turn toward `point`; returns the cosine of the remaining error.
    fn aimAt(s: *const Sim, c: *Controls, point: Vec3, dt: f32) f32 {
        const d = point.sub(s.pos).norm();
        const yaw_t = std.math.atan2(d.x, d.z);
        const pitch_t = std.math.asin(m.clamp(d.y, -1, 1));
        var dy = yaw_t - s.yaw;
        while (dy > m.pi) dy -= m.tau;
        while (dy < -m.pi) dy += m.tau;
        const lim = 7.0 * dt;
        c.look[0] = -m.clamp(dy, -lim, lim);
        c.look[1] = m.clamp(pitch_t - s.pitch, -lim, lim);
        return d.dot(s.forward());
    }

    fn nearestOf(s: *const Sim, kind: game.Kind, max_dist: f32) ?*const game.Entity {
        var best = max_dist;
        var out: ?*const game.Entity = null;
        for (&s.ents) |*e| {
            if (e.kind != kind) continue;
            const d = e.pos.dist(s.pos);
            if (d < best) {
                best = d;
                out = e;
            }
        }
        return out;
    }

    fn focusKind(s: *const Sim) game.Kind {
        return if (s.focus.ent) |i| s.ents[i].kind else .none;
    }

    fn tap(b: *Bot) bool {
        if (b.tap_cd > 0) return false;
        b.tap_cd = 0.7;
        return true;
    }

    /// Shoot whatever is about to bite. Returns true if it took over the reticle.
    fn defend(s: *const Sim, c: *Controls, dt: f32, arm: usize, range: f32) bool {
        const e = nearestOf(s, .cocci, range) orelse return false;
        const lead = e.pos.add(e.vel.sub(s.flow).scale(e.pos.dist(s.pos) / 950.0));
        if (aimAt(s, c, lead, dt) > 0.999) c.arm[arm] = true;
        return true;
    }

    // ------------------------------------------------------------------ chapter 2

    /// Travel inside the canopy, where the stream does not reach, to the gap nearest (x, z).
    fn lowTo(s: *const Sim, c: *Controls, x: f32, z: f32, y: f32) f32 {
        const gp = gut.gapNear(x, z);
        const here = gut.gapNear(s.pos.x, s.pos.z);
        const far = @abs(gp.x - s.pos.x) + @abs(gp.z - s.pos.z) > 260;
        // drop into the local gap first, then run along the floor between the villi
        const target = if (far and s.pos.y > y + 160) v3(here.x, y, here.z) else v3(gp.x, y, gp.z);
        return flyTo(s, c, target, true) + (if (far) @as(f32, 1000) else 0);
    }

    fn unknownNear(s: *const Sim, range: f32) bool {
        for (&s.ents) |*e| {
            if ((e.kind == .virion or e.kind == .commensal) and !e.known and e.pos.dist(s.pos) < range) return true;
        }
        return false;
    }

    fn nearestKnown(s: *const Sim, kind: game.Kind, max_dist: f32) ?*const game.Entity {
        var best = max_dist;
        var out: ?*const game.Entity = null;
        for (&s.ents) |*e| {
            if (e.kind != kind or !e.known) continue;
            if (kind == .infected and e.state == 0) continue;
            const d = e.pos.dist(s.pos);
            if (d < best) {
                best = d;
                out = e;
            }
        }
        return out;
    }

    fn shootAt(s: *const Sim, c: *Controls, e: *const game.Entity, dt: f32, arm: usize) void {
        const lead = e.pos.add(e.vel.sub(s.flow).scale(e.pos.dist(s.pos) / 950.0));
        if (aimAt(s, c, lead, dt) > 0.9985) c.arm[arm] = true;
    }

    /// Let go of the tether: aim at open lumen, where there is nothing to hold, and press G.
    fn release(b: *Bot, s: *const Sim, c: *Controls, dt: f32) void {
        _ = aimAt(s, c, s.pos.add(v3(0, 1, -0.15).scale(500)), dt);
        if (ch2.tetherTarget(s) == null) {
            if (b.tap()) c.tether = true;
        }
    }

    fn thinkGut(b: *Bot, s: *const Sim, dt: f32, c: *Controls) void {
        const g = &s.g;
        // Left arm shoots throughout; the right arm is the punch, or the drill at the dome.
        if (s.arms[0].tool != .shoot) c.select[0] = .shoot;
        const want_right: game.Tool = if (s.stage == .g_factory) .drill else .punch;
        if (s.arms[1].tool != want_right) c.select[1] = want_right;

        // A ring is coming or overhead: down to the floor and wait, whatever else was going on.
        const eta = ch2.ringEta(s);
        const ring_close = ch2.underRing(s) or (eta != null and eta.? < 3.0 and eta.? > 0) or (eta != null and eta.? == 0 and s.gut.ring_z.? - gut.ring_half < s.pos.z);
        if (ring_close and s.tether == null and @intFromEnum(s.stage) >= @intFromEnum(game.Stage.g_wave)) {
            const gp = gut.gapNear(s.pos.x, s.pos.z);
            _ = flyTo(s, c, v3(gp.x, 60, gp.z), true);
            // keep the drill arm down but still deal with anything that comes close
            if (nearestKnown(s, .virion, 200)) |e| shootAt(s, c, e, dt, 0);
            return;
        }

        switch (s.stage) {
            .g_arrive => {},
            .g_villus => {
                const cl = gut.cellOf(s.pos.x + 300, s.pos.z - 260);
                const v = gut.villusAt(cl[0], cl[1]);
                _ = aimAt(s, c, v3(v.x, v.base + v.h * 0.7, v.z), dt);
                if ((s.focus.topic == .villus or s.focus.topic == .villus_tip) and b.tap()) c.examine = true;
            },
            .g_descend, .g_wave => {
                const p = s.waypoint orelse blk: {
                    const gp = gut.gapNear(s.pos.x, s.pos.z);
                    break :blk v3(gp.x, 60, gp.z);
                };
                _ = flyTo(s, c, v3(p.x, 60, p.z), true);
                _ = aimAt(s, c, s.pos.add(v3(0, 0.6, -1).scale(300)), dt);
            },
            .g_scan => {
                const wp = s.waypoint orelse return;
                if (b.phase == 0) {
                    if (lowTo(s, c, wp.x + 150, wp.z, 300) < 80) b.phase = 1;
                    _ = aimAt(s, c, wp, dt);
                } else {
                    const gp = gut.gapNear(wp.x + 150, wp.z);
                    const d = flyTo(s, c, v3(gp.x, wp.y - 60, gp.z), true);
                    _ = aimAt(s, c, wp, dt);
                    if (d < 120 and b.tap()) c.examine = true;
                }
            },
            .g_extrude => {
                if (unknownNear(s, 600) and b.tap()) c.examine = true;
                if (nearestKnown(s, .virion, 260)) |e| {
                    shootAt(s, c, e, dt, 0);
                    return;
                }
                if (nearestOf(s, .shed, 900)) |e| {
                    shootAt(s, c, e, dt, 0);
                    // hold position near where we are; do not chase into the stream
                    return;
                }
                if (nearestKnown(s, .virion, 700)) |e| {
                    shootAt(s, c, e, dt, 0);
                    return;
                }
                if (nearestKnown(s, .infected, 5000)) |e| {
                    // hover just off the cell along its outward normal and punch it out
                    const hover = e.pos.add(e.end.scale(19));
                    const d = s.pos.dist(hover);
                    if (d > 500 and s.pos.y < 500) {
                        _ = lowTo(s, c, e.pos.x + 140, e.pos.z, 300);
                    } else if (d > 240) {
                        // come in from above the tips
                        _ = flyTo(s, c, v3(hover.x, @max(hover.y + 60, s.pos.y), hover.z), true);
                    } else {
                        _ = flyTo(s, c, hover, false);
                    }
                    const cs = aimAt(s, c, e.pos, dt);
                    if (d < 9 and cs > 0.93 and s.pos.dist(e.pos) < game.punch_reach + e.radius - 3) c.arm[1] = true;
                    return;
                }
                // nothing visible: something is still hidden; go and scan where the marker says
                if (s.waypoint) |wp| {
                    const d = s.pos.dist(wp);
                    if (d > 500 and s.pos.y < 500) _ = lowTo(s, c, wp.x + 140, wp.z, 300) else _ = flyTo(s, c, wp, true);
                    _ = aimAt(s, c, wp.add(v3(0, -150, 0)), dt);
                    if (d < 260 and b.tap()) c.examine = true;
                }
            },
            .g_factory => {
                const e = nearestOf(s, .factory, 1e9) orelse {
                    if (nearestKnown(s, .virion, 600)) |v| shootAt(s, c, v, dt, 0);
                    return;
                };
                const hover = e.pos.add(v3(0, e.radius + 12, 0));
                const d = s.pos.dist(hover);
                if (b.phase == 0) {
                    if (lowTo(s, c, e.pos.x + 150, e.pos.z, 300) < 90) b.phase = 1;
                    _ = aimAt(s, c, e.pos, dt);
                    if (nearestKnown(s, .virion, 220)) |v| shootAt(s, c, v, dt, 0);
                    return;
                }
                if (d > 30 and !s.latched) _ = flyTo(s, c, hover, d > 200);
                const threat = nearestKnown(s, .virion, 150);
                const on_dome = focusKind(s) == .factory and s.focus.dist < game.drill_reach;
                if (s.arms[1].tool == .drill and !s.arms[1].overheated and !b.cooling) {
                    // keep the bit in once it has bitten; start it only when the dome is under the reticle
                    if (s.arms[1].latch != null or on_dome) c.arm[1] = true;
                }
                if (s.arms[1].heat > 0.9) b.cooling = true;
                if (s.arms[1].heat < 0.3) b.cooling = false;
                if (threat) |v| {
                    shootAt(s, c, v, dt, 0);
                } else {
                    const cs = aimAt(s, c, e.pos, dt);
                    if (e.aux > 0.55 and cs > 0.99) c.arm[0] = true;
                }
            },
            .g_tether => {
                // two holds on two different villi
                const off: f32 = if (g.tether_uses % 2 == 0) 300 else -300;
                const cl = gut.cellOf(s.pos.x + off, s.pos.z - 200);
                const v = gut.villusAt(cl[0], cl[1]);
                const p = v3(v.x, m.clamp(s.pos.y, v.base + 120, v.base + v.h - 150), v.z);
                const cs = aimAt(s, c, p, dt);
                const reeled = s.tether == null or s.pos.dist(s.tether_hold) < 14;
                if (reeled and cs > 0.995 and ch2.tetherTarget(s) != null and b.tap()) c.tether = true;
            },
            .g_flume => {
                if (s.tether != null and s.pos.z > gut.blunt_z1 + 420) {
                    b.release(s, c, dt);
                    return;
                }
                if (s.tether == null and s.pos.z > gut.blunt_z1 + 420) {
                    // still in the forest: run along the floor
                    _ = lowTo(s, c, s.pos.x * 0.5, s.pos.z - 600, 120);
                    _ = aimAt(s, c, s.pos.add(v3(0, -0.2, -1).scale(300)), dt);
                    return;
                }
                // the stripped stretch: pull from hold to hold along the floor
                // a stub right in front blocks the long pull: try the next sightline
                const tries = [_]Vec3{ v3(0, 6, -330), v3(170, 6, -300), v3(-170, 6, -300), v3(90, 110, -260), v3(-90, 110, -260), v3(260, 6, -220), v3(-260, 6, -220) };
                const off = tries[b.phase % tries.len];
                const p = v3(s.pos.x * 0.8 + off.x, off.y, s.pos.z + off.z);
                const cs = aimAt(s, c, p, dt);
                const reeled = s.tether == null or s.pos.dist(s.tether_hold) < 14;
                const tt = ch2.tetherTarget(s);
                const good = tt != null and tt.?.t > 70 and tt.?.point.z < s.pos.z - 55;
                if (reeled and cs > 0.99) {
                    if (good) {
                        if (b.tap()) {
                            c.tether = true;
                            b.phase = 0;
                        }
                    } else b.phase +%= 1;
                }
            },
            .g_exit => {
                if (s.tether != null) {
                    b.release(s, c, dt);
                    return;
                }
                const wp = s.waypoint orelse return;
                if (b.phase == 0) {
                    if (lowTo(s, c, wp.x, wp.z + 260, 300) < 90) b.phase = 1;
                    _ = aimAt(s, c, wp, dt);
                } else {
                    _ = flyTo(s, c, wp.add(v3(0, 0, -40)), true);
                    _ = aimAt(s, c, wp.add(v3(0, 0, -300)), dt);
                }
            },
            else => {},
        }
    }

    // ------------------------------------------------------------------ chapter 3

    fn colonisedPit(s: *const Sim, pit: stomach.Pit) bool {
        for (&s.ents) |*e| {
            if (e.kind == .colony and @abs(e.pos.x - pit.x) < 5 and @abs(e.pos.z - pit.z) < 5) return true;
        }
        return false;
    }

    /// Into the pit nearest the drone: over its mouth first, then down the axis.
    fn intoPit(s: *const Sim, c: *Controls) void {
        const pit = stomach.pitNear(s.pos.x, s.pos.z) orelse return;
        const off = @abs(pit.x - s.pos.x) + @abs(pit.z - s.pos.z);
        const depth: f32 = if (colonisedPit(s, pit)) 46 else 150;
        _ = flyTo(s, c, if (off > 14 and s.pos.y > -4) pit.mouth().add(v3(0, 10, 0)) else pit.down(depth), true);
    }

    /// Out of a pit by its axis; true while the drone is still below the mouth.
    fn climbOut(s: *const Sim, c: *Controls) bool {
        if (s.pos.y > 4 or ch3.inCrater(s.pos)) return false;
        const pit = stomach.pitNear(s.pos.x, s.pos.z) orelse return false;
        _ = flyTo(s, c, pit.mouth().add(v3(0, 24, 0)), true);
        return true;
    }

    /// A round arrives only while the swimmer holds still to flare, or at arm's length. Returns true if
    /// one is near enough to need the reticle.
    fn fightSwimmers(s: *const Sim, c: *Controls, dt: f32, range: f32) bool {
        const e = nearestOf(s, .pylori, range) orelse return false;
        const d = e.pos.dist(s.pos);
        const cs = aimAt(s, c, e.pos, dt);
        if (cs > 0.995 and (e.state == 1 or d < 55) and s.arms[0].tool == .shoot) c.arm[0] = true;
        if (cs > 0.9 and d < game.punch_reach + 2 and s.arms[1].tool == .punch) c.arm[1] = true;
        return true;
    }

    fn releaseLine(b: *Bot, s: *const Sim, c: *Controls, dt: f32) void {
        _ = aimAt(s, c, s.pos.add(v3(0, 1, -0.15).scale(500)), dt);
        if (ch3.tetherTarget(s) == null) {
            if (b.tap()) c.tether = true;
        }
    }

    fn thinkStomach(b: *Bot, s: *const Sim, dt: f32, c: *Controls) void {
        const g = &s.g3;
        // Left arm shoots and the right punches; at the colonies the right arm drills, and at the vessel
        // the left presses while the right welds.
        const cautery = s.stage == .s_cautery;
        const want_left: game.Tool = if (cautery) .punch else .shoot;
        const want_right: game.Tool = if (cautery or s.stage == .s_margin) .drill else .punch;
        if (s.arms[0].tool != want_left) c.select[0] = want_left;
        if (s.arms[1].tool != want_right) c.select[1] = want_right;
        const drill = &s.arms[1];
        if (drill.heat > 0.9) b.cooling = true;
        if (drill.heat < 0.3) b.cooling = false;

        // A wave is coming or overhead: outside the crater, get below the mouth of a pit and stay there.
        const eta = ch3.ringEta(s);
        const wave = ch3.underRing(s) or (eta != null and eta.? > 0 and eta.? < 3.2) or (eta != null and eta.? == 0 and s.sto.ring_z.? - stomach.ring_half < s.pos.z);
        if (wave and s.tether == null and !ch3.inCrater(s.pos) and @intFromEnum(s.stage) > @intFromEnum(game.Stage.s_wave)) {
            if (!ch3.sheltered(s)) {
                intoPit(s, c);
                _ = aimAt(s, c, s.pos.add(v3(0, -1, -0.3).scale(200)), dt);
                return;
            }
            if (s.stage != .s_margin) {
                intoPit(s, c);
                _ = fightSwimmers(s, c, dt, 120);
                return;
            }
        }

        switch (s.stage) {
            .s_arrive => {},
            .s_pits => {
                const pit = stomach.pitNear(s.pos.x, s.pos.z - 220) orelse return;
                _ = aimAt(s, c, pit.down(20), dt);
                if ((s.focus.topic == .gastric_pit or s.focus.topic == .surface_mucous_cell) and b.tap()) c.examine = true;
            },
            .s_gradient => {
                const y: f32 = if (g.said.acid_reached) 70 else 270;
                _ = flyTo(s, c, v3(s.pos.x, y, s.pos.z), false);
                _ = aimAt(s, c, s.pos.add(v3(0, -0.3, -1).scale(300)), dt);
            },
            .s_wave => {
                // hover over a mouth, aim down the pit, and let the line pull the drone in
                const pit = stomach.pitNear(s.pos.x, s.pos.z) orelse return;
                if (s.tether != null) return;
                if (eta != null and eta.? < 2.0) {
                    intoPit(s, c);
                    return;
                }
                const d = flyTo(s, c, pit.mouth().add(v3(0, 46, 0)), false);
                const cs = aimAt(s, c, pit.down(170), dt);
                if (d < 12 and cs > 0.995) {
                    if (ch3.tetherTarget(s)) |h| {
                        if (h.what == .pit and b.tap()) c.tether = true;
                    }
                }
            },
            .s_swim => {
                if (s.tether != null) return b.releaseLine(s, c, dt);
                if (climbOut(s, c)) return;
                if (fightSwimmers(s, c, dt, 420)) return;
                const wp = s.waypoint orelse return;
                _ = flyTo(s, c, wp, true);
                _ = aimAt(s, c, wp.add(v3(0, -40, -300)), dt);
            },
            .s_margin => {
                if (s.tether != null) return b.releaseLine(s, c, dt);
                const col = nearestOf(s, .colony, 1e9) orelse {
                    // the margin is clear: wait deep in the pit, where the gel is still neutral
                    intoPit(s, c);
                    if (!fightSwimmers(s, c, dt, 300)) _ = aimAt(s, c, s.pos.add(v3(0, 1, -0.2).scale(200)), dt);
                    return;
                };
                const hover = v3(col.pos.x, -44, col.pos.z);
                const off = @abs(col.pos.x - s.pos.x) + @abs(col.pos.z - s.pos.z);
                const flaring = if (nearestOf(s, .pylori, 110)) |e| (e.state == 1 or e.state == 2 or e.pos.dist(s.pos) < 55) else false;
                if (off > 16) {
                    // the surface between pits is acid here: cross low and fast
                    if (climbOut(s, c)) return;
                    const far = off > 500;
                    _ = flyTo(s, c, v3(col.pos.x, if (far) 70 else 14, col.pos.z), true);
                    if (!(flaring and fightSwimmers(s, c, dt, 110))) _ = aimAt(s, c, col.pos, dt);
                    return;
                }
                const d = flyTo(s, c, hover, false);
                // a swimmer that flares gets the shooting arm; the drill stays in the colony meanwhile
                if (!(flaring and fightSwimmers(s, c, dt, 110))) {
                    const cs = aimAt(s, c, col.pos, dt);
                    if (cs > 0.98 and d < 16) c.arm[0] = true;
                }
                if (!b.cooling and (drill.latch != null or (focusKind(s) == .colony and s.focus.dist < game.drill_reach))) c.arm[1] = true;
            },
            .s_cross => {
                if (s.tether != null) return b.releaseLine(s, c, dt);
                if (climbOut(s, c)) return;
                const e = s.findConst(.vessel) orelse return;
                const stand = vesselStand(e);
                // up and over the rim first, then down the crater wall to the vessel
                const outside = stomach.into(s.pos.x, s.pos.z) < 70;
                const target = if (outside) v3(m.lerp(s.pos.x, stand.x, 0.3), 190, stomach.marginZ(s.pos.x) - 140) else stand;
                _ = flyTo(s, c, target, true);
                _ = aimAt(s, c, e.pos, dt);
            },
            .s_cautery => {
                const e = s.findConst(.vessel) orelse return;
                if (g.sealed) return;
                const stand = vesselStand(e);
                const d = s.pos.dist(stand);
                if (s.tether == null) {
                    // fix a line to the bed beside the vessel before starting: the jet and the waves
                    // would otherwise take the drone every time the bit has to cool
                    _ = flyTo(s, c, stand, d > 150);
                    const anchor = e.pos.sub(e.end.scale(8)).add(vesselSide(e).scale(e.radius));
                    const cs = aimAt(s, c, anchor, dt);
                    if (d < 16 and cs > 0.995 and ch3.tetherTarget(s) != null and b.tap()) c.tether = true;
                    return;
                }
                const cs = aimAt(s, c, e.pos, dt);
                const on = focusKind(s) == .vessel and s.focus.dist < game.drill_reach;
                if (cs > 0.97) c.arm[0] = true;
                if (!b.cooling and (drill.latch != null or on)) c.arm[1] = true;
            },
            .s_exit => {
                if (s.tether != null) return b.releaseLine(s, c, dt);
                const wp = s.waypoint orelse return;
                if (b.phase == 0) {
                    if (flyTo(s, c, wp.add(v3(0, 20, 170)), true) < 40) b.phase = 1;
                    _ = aimAt(s, c, wp, dt);
                } else {
                    _ = flyTo(s, c, wp.add(v3(0, 0, -70)), true);
                    _ = aimAt(s, c, wp.add(v3(0, 0, -300)), dt);
                }
            },
            else => {},
        }
    }

    fn vesselSide(e: *const game.Entity) Vec3 {
        return e.end.cross(v3(0, 0, 1)).norm();
    }

    /// Where to work on the vessel from: beside it, off the axis of its jet.
    fn vesselStand(e: *const game.Entity) Vec3 {
        return e.pos.add(vesselSide(e).scale(e.radius + 16)).add(e.end.scale(24));
    }

    // ------------------------------------------------------------------ chapter 4

    /// Fly towards `target` through the calyx, keeping off the papilla and the dome on the way.
    fn calyxTo(s: *const Sim, c: *Controls, target: Vec3, fast: bool) f32 {
        const d = target.sub(s.pos);
        const dist = d.len();
        var p = target;
        if (dist > 220) {
            p = s.pos.add(d.scale(220 / dist));
            const lo = kidney.papillaY(p.x, p.z) + 130;
            p.y = @max(p.y, lo);
            if (p.x * p.x + p.z * p.z > kidney.outlet_r * kidney.outlet_r) {
                const hi = kidney.wallY(p.x, p.z) - 130;
                p.y = if (hi > lo) @min(p.y, hi) else 0.5 * (lo + hi);
            }
        }
        _ = flyTo(s, c, p, fast);
        return dist;
    }

    /// The piece to work on: one wedged in the outlet first, then the biggest, then the nearest.
    fn kidneyPiece(s: *const Sim) ?*const game.Entity {
        var best: f32 = 1e12;
        var out: ?*const game.Entity = null;
        for (&s.ents) |*e| {
            if (e.kind != .calculus or e.state == 1 or ch4.passable(e)) continue;
            var score = e.pos.dist(s.pos) - e.radius + 1e4 * @as(f32, @floatFromInt(e.variant));
            if (e.state == 2) score -= 1e6;
            if (score < best) {
                best = score;
                out = e;
            }
        }
        return out;
    }

    /// Turn the shooting arm on the nearest shard in range. Returns true if one took the reticle.
    fn shootShards(s: *const Sim, c: *Controls, dt: f32, arm: usize, range: f32) bool {
        const e = nearestOf(s, .shard, range) orelse return false;
        const lead = e.pos.add(e.vel.sub(s.flow).scale(e.pos.dist(s.pos) / 950.0));
        if (aimAt(s, c, lead, dt) > 0.9995) c.arm[arm] = true;
        return true;
    }

    fn thinkKidney(b: *Bot, s: *const Sim, dt: f32, c: *Controls) void {
        // Left arm shoots and the right drills at the stalk; the left punches while the right notches;
        // with Resonance both punch.
        const resonance = s.stage == .k_resonance;
        const want_left: game.Tool = if (s.stage == .k_split or resonance) .punch else .shoot;
        const want_right: game.Tool = if (resonance) .punch else if (s.stage == .k_neck or s.stage == .k_split) .drill else .punch;
        if (s.arms[0].tool != want_left) c.select[0] = want_left;
        if (s.arms[1].tool != want_right) c.select[1] = want_right;
        const drill = &s.arms[1];
        if (drill.heat > 0.93) b.cooling = true;
        if (drill.heat < 0.3) b.cooling = false;

        // The way across the tip that passes over no duct: out between two of the outer ring, round
        // between the rings, and out again between two more on the stone's side.
        const route = [_]Vec3{
            kidney.onPapilla(-316, -182).add(v3(0, 150, 0)),
            kidney.onPapilla(-316, 182).add(v3(0, 150, 0)),
            kidney.onPapilla(-260, 450).add(v3(0, 150, 0)),
        };
        switch (s.stage) {
            .k_arrive => {
                _ = calyxTo(s, c, route[0], false);
                _ = aimAt(s, c, kidney.ductPos(6), dt);
            },
            .k_duct => {
                _ = calyxTo(s, c, route[0], false);
                // the nearest opening
                var best: f32 = 1e9;
                var at = kidney.ductPos(0);
                for (0..kidney.duct_count) |i| {
                    const d = kidney.ductPos(i).dist(s.pos);
                    if (d < best) {
                        best = d;
                        at = kidney.ductPos(i);
                    }
                }
                _ = aimAt(s, c, at, dt);
                if ((s.focus.topic == .duct_of_bellini or s.focus.topic == .area_cribrosa) and b.tap()) c.examine = true;
            },
            .k_jets => {
                const stand = ch4.standPoint();
                if (b.phase < route.len) {
                    if (calyxTo(s, c, route[b.phase], false) < 50) b.phase += 1;
                } else {
                    _ = calyxTo(s, c, stand, true);
                }
                if (!shootShards(s, c, dt, 0, 320)) _ = aimAt(s, c, stand.add(v3(0, 200, 300)), dt);
            },
            .k_stone => {
                const st = s.findConst(.calculus) orelse return;
                _ = calyxTo(s, c, ch4.standPoint(), false);
                _ = aimAt(s, c, st.pos, dt);
                if (focusKind(s) == .calculus and b.tap()) c.examine = true;
            },
            .k_neck => {
                const e = s.findConst(.plaque) orelse return;
                const d = calyxTo(s, c, ch4.standPoint(), false);
                // once the bit is in, the reticle is free for the shards
                if (drill.latch != null and shootShards(s, c, dt, 0, 420)) {
                    if (!b.cooling) c.arm[1] = true;
                    return;
                }
                _ = aimAt(s, c, e.pos, dt);
                const on = focusKind(s) == .plaque and s.focus.dist < game.drill_reach;
                if (!b.cooling and d < 30 and (drill.latch != null or on)) c.arm[1] = true;
            },
            .k_split => {
                const e = kidneyPiece(s) orelse return;
                const out = s.pos.sub(e.pos).norm();
                const stand = e.pos.add(out.scale(e.radius + game.hull_r + 9));
                const d = s.pos.dist(e.pos) - e.radius;
                if (d > 40) _ = calyxTo(s, c, stand, d > 300) else _ = flyTo(s, c, stand, false);
                const cs = aimAt(s, c, e.pos, dt);
                const on = focusKind(s) == .calculus and s.focus.dist < game.drill_reach;
                if (!b.cooling and (drill.latch != null or (on and cs > 0.97))) c.arm[1] = true;
                // the notch is through: the blow, with the bit still in
                if (drill.engaged and e.aux >= 1 and cs > 0.9) c.arm[0] = true;
            },
            .k_resonance => {
                // a shard on its way in gets a wave to itself
                if (nearestOf(s, .shard, 160)) |sh| {
                    if (aimAt(s, c, sh.pos, dt) > 0.95 and b.tap()) c.arm = .{ true, true };
                    return;
                }
                const e = kidneyPiece(s) orelse return;
                // two pieces that parted together are still side by side: aim between them
                var aim = e.pos;
                for (&s.ents) |*o| {
                    if (o == e or o.kind != .calculus or ch4.passable(o)) continue;
                    if (o.pos.dist(e.pos) < 2.6 * e.radius) {
                        aim = e.pos.add(o.pos).scale(0.5);
                        break;
                    }
                }
                const d = s.pos.dist(e.pos) - e.radius;
                const out = s.pos.sub(aim).norm();
                if (d > 320 or d < 120) _ = calyxTo(s, c, aim.add(out.scale(e.radius + 220)), d > 600);
                const cs = aimAt(s, c, aim, dt);
                if (d < 420 and cs > 0.985 and b.tap()) c.arm = .{ true, true };
            },
            .k_exit => {
                const wp = s.waypoint orelse return;
                if (b.phase == 0) {
                    if (calyxTo(s, c, wp.add(v3(0, 20, 170)), true) < 40) b.phase = 1;
                    _ = aimAt(s, c, wp, dt);
                } else {
                    _ = flyTo(s, c, wp.add(v3(0, 0, -70)), true);
                    _ = aimAt(s, c, wp.add(v3(0, 0, -300)), dt);
                }
            },
            else => {},
        }
    }

    pub fn think(b: *Bot, s: *const Sim, dt: f32) Controls {
        var c: Controls = .{};
        b.tap_cd = @max(0, b.tap_cd - dt);
        if (s.stage != b.stage) {
            b.stage = s.stage;
            b.phase = 0;
        }
        if (s.mode == .upgrade_card) {
            c.confirm = true;
            return c;
        }
        if (s.mode != .playing) return c;
        if (s.chapter == 1) {
            b.thinkGut(s, dt, &c);
            return c;
        }
        if (s.chapter == 2) {
            b.thinkStomach(s, dt, &c);
            return c;
        }
        if (s.chapter == 3) {
            b.thinkKidney(s, dt, &c);
            return c;
        }
        const vn = &s.vein;

        switch (s.stage) {
            .needle => {
                const p = vn.needle.at(700);
                _ = aimAt(s, &c, p, dt);
                _ = flyTo(s, &c, p, true);
            },
            .flow_wall => {
                const p = s.waypoint orelse Vein.center(s.pos.z).add(v3(-1700, 0, 0));
                _ = aimAt(s, &c, p, dt);
                _ = flyTo(s, &c, p, true);
            },
            .flow_core => {
                const p = Vein.center(s.pos.z + 300);
                _ = aimAt(s, &c, p, dt);
                _ = flyTo(s, &c, p, true);
            },
            .to_valve1 => {
                const p = Vein.center(@min(s.pos.z + 600, vn.valves[0].zb - 700));
                _ = aimAt(s, &c, p, dt);
                _ = flyTo(s, &c, p, true);
            },
            .valve1_identify => {
                const v = &vn.valves[0];
                _ = flyTo(s, &c, Vein.center(v.zb - 450), true);
                const za = v.zb + 900;
                const ys = vn.cuspY(0, 0, 0, za) orelse 600;
                _ = aimAt(s, &c, Vein.center(za).add(v3(0, ys, 0)), dt);
                if (s.focus.topic == .leaflet and b.tap()) c.examine = true;
            },
            .valve1_pass => {
                const v = &vn.valves[0];
                if (b.phase == 0) {
                    const wait = Vein.center(v.zb - 300);
                    const d = flyTo(s, &c, wait, true);
                    _ = aimAt(s, &c, Vein.center(v.zb + 800), dt);
                    if (d < 200 and v.open[0] > 0.8 and v.open[1] > 0.8 and Vein.timeToReflux(s.clock) > 3.3) b.phase = 1;
                    if (s.pos.z > v.zb + 300) b.phase = 1;
                } else {
                    const p = Vein.center(@min(s.pos.z + 500, v.top() + 500));
                    _ = aimAt(s, &c, p, dt);
                    _ = flyTo(s, &c, p, true);
                }
            },
            .neutrophil => {
                var target: ?*const game.Entity = null;
                var best: f32 = 1e9;
                for (&s.ents) |*e| {
                    if (e.kind != .neutrophil or e.pos.z < 6200 or e.pos.z > 9000) continue;
                    const d = e.pos.dist(s.pos);
                    if (d < best) {
                        best = d;
                        target = e;
                    }
                }
                if (target) |e| {
                    const inward = Vein.center(e.pos.z).sub(e.pos).norm();
                    _ = flyTo(s, &c, e.pos.add(inward.scale(40)), true);
                    _ = aimAt(s, &c, e.pos, dt);
                    if (focusKind(s) == .neutrophil and b.tap()) c.examine = true;
                }
            },
            .staph => {
                if (nearestOf(s, .cocci, 2000)) |e| {
                    const lead = e.pos.add(e.vel.sub(s.flow).scale(e.pos.dist(s.pos) / 950.0));
                    if (aimAt(s, &c, lead, dt) > 0.999) c.arm[0] = true;
                    // keep some distance, drift with them
                    const away = s.pos.sub(e.pos).norm();
                    _ = flyTo(s, &c, e.pos.add(away.scale(110)), false);
                }
            },
            .tools => {
                if (s.arms[1].tool != .drill) c.select[1] = .drill;
                if (s.arms[0].tool != .shoot) c.select[0] = .shoot;
                if (s.waypoint) |p| {
                    _ = aimAt(s, &c, p, dt);
                    _ = flyTo(s, &c, p, true);
                }
            },
            .v2_approach => {
                const v = &vn.valves[1];
                switch (b.phase) {
                    0 => {
                        const a = Vein.center(v.zb + 150).add(v3(0, -520, 0));
                        const d = flyTo(s, &c, a, true);
                        _ = aimAt(s, &c, Vein.center(v.top()).add(v3(0, -420, 0)), dt);
                        if (d < 150 and v.open[1] > 0.8 and Vein.timeToReflux(s.clock) > 3.6) b.phase = 1;
                    },
                    1 => {
                        const p = Vein.center(@min(s.pos.z + 500, v.top() + 300)).add(v3(0, -430, 0));
                        _ = aimAt(s, &c, p, dt);
                        _ = flyTo(s, &c, p, true);
                        if (s.pos.z > v.top() + 150) b.phase = 2;
                    },
                    2 => {
                        const p = Vein.center(v.top() + 300).add(v3(0, 1250, 0));
                        _ = aimAt(s, &c, p, dt);
                        if (flyTo(s, &c, p, true) < 120) b.phase = 3;
                    },
                    else => {
                        if (s.findConst(.thrombus)) |clot| {
                            const p = clot.pos.add(v3(0, 0, 520));
                            _ = aimAt(s, &c, clot.pos, dt);
                            _ = flyTo(s, &c, p, true);
                        }
                    },
                }
            },
            .treat => b.treat(s, &c, dt),
            .lyse_core => {
                if (s.arms[0].tool != .shoot) c.select[0] = .shoot;
                if (s.arms[1].tool != .shoot) c.select[1] = .shoot;
                if (s.findConst(.thrombus)) |clot| {
                    const out = s.pos.sub(clot.pos).norm();
                    _ = flyTo(s, &c, clot.pos.add(out.scale(clot.radius + 170)), false);
                    if (aimAt(s, &c, clot.pos, dt) > 0.97) c.arm = .{ true, true };
                }
            },
            .freed => {
                if (nearestOf(s, .embolus, 3000)) |e| b.chase(s, &c, e, dt);
            },
            .to_ring2 => {
                if (s.arms[0].tool != .punch) c.select[0] = .punch;
                if (s.arms[1].tool != .punch) c.select[1] = .punch;
                const v = &vn.valves[1];
                if (b.phase == 0) {
                    const p = Vein.center(v.top() + 320).add(v3(0, 1250, 0));
                    _ = aimAt(s, &c, p, dt);
                    if (flyTo(s, &c, p, true) < 150 or s.pos.z > v.top() + 250) b.phase = 1;
                } else if (s.waypoint) |p| {
                    _ = aimAt(s, &c, p, dt);
                    _ = flyTo(s, &c, p, true);
                    // one practice Sync Strike on the way
                    if (s.stats.sync_strikes == 0 and s.arms[0].tool == .punch and s.arms[1].tool == .punch) c.arm = .{ true, true };
                }
            },
            .septum_find => {
                if (s.findConst(.phlebolith)) |stone| {
                    _ = flyTo(s, &c, stone.pos.add(v3(0, 0, -(stone.radius + 70))), true);
                    _ = aimAt(s, &c, stone.pos, dt);
                    if (focusKind(s) == .phlebolith and s.focus.dist < 400 and b.tap()) c.examine = true;
                }
            },
            .septum_break => {
                if (s.arms[0].tool != .punch) c.select[0] = .punch;
                if (s.arms[1].tool != .punch) c.select[1] = .punch;
                if (s.findConst(.phlebolith)) |stone| {
                    const d = flyTo(s, &c, stone.pos.add(v3(0, 0, -(stone.radius + 16))), false);
                    const cs = aimAt(s, &c, stone.pos, dt);
                    if (d < 30 and cs > 0.9 and s.arms[0].tool == .punch and s.arms[1].tool == .punch) c.arm = .{ true, true };
                }
            },
            .exit => {
                const sp = &vn.septum;
                const ctr = Vein.center(sp.z);
                const p = if (s.pos.z < sp.z + 80) v3(ctr.x + sp.hole_x, ctr.y + sp.hole_y, sp.z + 200) else Vein.center(@min(s.pos.z + 600, vein_mod.z_exit + 400));
                _ = aimAt(s, &c, p, dt);
                _ = flyTo(s, &c, p, true);
            },
            else => {},
        }
        return c;
    }

    fn chase(b: *Bot, s: *const Sim, c: *Controls, e: *const game.Entity, dt: f32) void {
        _ = b;
        const shooter: usize = if (s.arms[0].tool == .shoot) 0 else 1;
        if (s.arms[shooter].tool != .shoot) c.select[0] = .shoot;
        const away = s.pos.sub(e.pos).norm();
        _ = flyTo(s, c, e.pos.add(away.scale(90)), true);
        const lead = e.pos.add(e.vel.sub(s.flow).scale(e.pos.dist(s.pos) / 950.0));
        if (aimAt(s, c, lead, dt) > 0.9995) c.arm[shooter] = true;
    }

    fn treat(b: *Bot, s: *const Sim, c: *Controls, dt: f32) void {
        if (s.arms[0].tool != .shoot) c.select[0] = .shoot;
        if (s.arms[1].tool != .drill) c.select[1] = .drill;
        const drill = &s.arms[1];
        if (drill.heat > 0.9) b.cooling = true;
        if (drill.heat < 0.25) b.cooling = false;
        const latched = drill.latch != null;

        // Swimmers first: the drill stays in whatever it is locked into while the other arm deals with them.
        if (defend(s, c, dt, 0, 240)) {
            if (latched and !b.cooling) c.arm[1] = true;
            return;
        }
        // Loose clot before anything else gets cut.
        if (!latched) {
            if (nearestOf(s, .embolus, 5000)) |e| {
                b.chase(s, c, e, dt);
                return;
            }
        }
        if (nearestOf(s, .nest, 1e9)) |nest| {
            const stand = nest.pos.add(nest.end.scale(nest.radius * 0.8 + game.hull_r + 9));
            const d = s.pos.dist(stand);
            if (d > 260) {
                // come in along the dome's normal so the clot is never in the way
                _ = flyTo(s, c, nest.pos.add(nest.end.scale(240)), true);
            } else {
                _ = flyTo(s, c, stand, false);
            }
            const cs = aimAt(s, c, nest.pos, dt);
            if (d < 14 and cs > 0.98) {
                if (!b.cooling) c.arm[1] = true;
                c.arm[0] = nest.aux > 0.5;
            }
            return;
        }
        if (nearestOf(s, .anchor, 1e9)) |anchor| {
            const mid = anchor.pos.lerp(anchor.end, 0.5);
            const axis = anchor.end.sub(anchor.pos).norm();
            var side = s.pos.sub(mid);
            side = side.sub(axis.scale(side.dot(axis)));
            if (side.len() < 1) side = axis.perp();
            const stand = mid.add(side.norm().scale(anchor.radius + game.hull_r + 7));
            const d = s.pos.dist(stand);
            _ = flyTo(s, c, stand, d > 200);
            const cs = aimAt(s, c, mid, dt);
            if ((d < 14 and cs > 0.98 and !b.cooling) or (latched and !b.cooling)) c.arm[1] = true;
        }
    }
};

pub const Result = struct {
    completed: bool,
    sim_seconds: f32,
    stage: game.Stage,
    deaths: u32,
    stats: game.Stats,
    stability: f32,
    hull: f32,
    grade: u8,
    atlas: u32,
};

/// Play the chapter headless at a fixed step. `log` prints each stage change to stderr.
pub fn runHeadless(sim: *Sim, checkpoint: *Sim, max_seconds: f32, log: bool) Result {
    return runHeadlessChapter(sim, checkpoint, 0, max_seconds, log);
}

pub var trace: bool = false;

pub fn runHeadlessChapter(sim: *Sim, checkpoint: *Sim, chapter: u8, max_seconds: f32, log: bool) Result {
    const Direct = struct {
        pub fn pass(_: *@This(), c: Controls, _: *const Sim, _: f32) Controls {
            return c;
        }
    };
    var direct: Direct = .{};
    return runHeadlessVia(sim, checkpoint, chapter, max_seconds, log, &direct);
}

/// As `runHeadlessChapter`, with the pilot's controls handed to `via.pass(controls, sim, dt)` on their way
/// to the simulation. The tests use it to route them through a game controller and back.
pub fn runHeadlessVia(sim: *Sim, checkpoint: *Sim, chapter: u8, max_seconds: f32, log: bool, via: anytype) Result {
    sim.* = Sim.initChapter(chapter);
    checkpoint.* = sim.*;
    var bot: Bot = .{};
    const dt: f32 = 1.0 / 60.0;
    var t: f32 = 0;
    var deaths: u32 = 0;
    var last = sim.stage;
    if (log) std.debug.print("[{d:7.1}s] start: stage {s}\n", .{ t, @tagName(sim.stage) });
    while (t < max_seconds and sim.mode != .complete and sim.mode != .lost) : (t += dt) {
        const c = via.pass(bot.think(sim, dt), sim, dt);
        sim.update(c, dt);
        if (sim.want_checkpoint) {
            sim.want_checkpoint = false;
            sim.hull = 100;
            checkpoint.* = sim.*;
            if (log) std.debug.print("[{d:7.1}s] checkpoint\n", .{t});
        }
        if (sim.mode == .dead) {
            deaths += 1;
            const stats = sim.stats;
            sim.* = checkpoint.*;
            sim.stats.time = stats.time;
            sim.stats.retries = stats.retries + 1;
            bot = .{};
            if (log) std.debug.print("[{d:7.1}s] hull lost, retry from checkpoint (stage {s})\n", .{ t, @tagName(sim.stage) });
        }
        if (log and trace and @mod(t, 4.0) < dt) std.debug.print("    t={d:.0} pos=({d:.0},{d:.0},{d:.0}) hull={d:.0} flow={d:.0} phase={d} ring={?d:.0} tether={} wp={?d:.0}\n", .{ t, sim.pos.x, sim.pos.y, sim.pos.z, sim.hull, sim.flow.z, bot.phase, if (sim.chapter == 2) sim.sto.ring_z else if (sim.chapter == 1) sim.gut.ring_z else null, sim.tether != null, if (sim.waypoint) |w| @as(?f32, w.z) else null });
        if (sim.stage != last) {
            last = sim.stage;
            if (log) std.debug.print("[{d:7.1}s] stage {s}  hull {d:.0} stability {d:.0} z {d:.0}\n", .{ t, @tagName(sim.stage), sim.hull, sim.stability, sim.pos.z });
        }
    }
    return .{
        .completed = sim.mode == .complete,
        .sim_seconds = t,
        .stage = sim.stage,
        .deaths = deaths,
        .stats = sim.stats,
        .stability = sim.stability,
        .hull = sim.hull,
        .grade = sim.grade(),
        .atlas = sim.atlasCount(),
    };
}

test "scripted pilot finishes the vein chapter using both arms together and the upgrade" {
    const gpa = std.testing.allocator;
    const sim = try gpa.create(Sim);
    defer gpa.destroy(sim);
    const cp = try gpa.create(Sim);
    defer gpa.destroy(cp);
    const r = runHeadless(sim, cp, 1500, false);
    try std.testing.expect(r.completed);
    try std.testing.expect(sim.has_sync);
    try std.testing.expect(!sim.vein.septum.corked);
    try std.testing.expect(!sim.vein.valves[1].pinned[0]);
    // drilled with one arm while shooting with the other for a meaningful stretch
    try std.testing.expect(r.stats.dual_time > 3);
    // the exit stone needed the upgrade's Sync Strikes
    try std.testing.expect(r.stats.sync_strikes >= 3);
    try std.testing.expect(r.stability > 0);
}

test "scripted pilot finishes the jejunum chapter: extrusion, the dome with both arms, and the tether crossing" {
    const gpa = std.testing.allocator;
    const sim = try gpa.create(Sim);
    defer gpa.destroy(sim);
    const cp = try gpa.create(Sim);
    defer gpa.destroy(cp);
    const r = runHeadlessChapter(sim, cp, 1, 1500, false);
    try std.testing.expect(r.completed);
    try std.testing.expect(sim.has_tether);
    try std.testing.expectEqual(@as(u32, 0), sim.count(.infected));
    try std.testing.expectEqual(@as(u32, 0), sim.count(.factory));
    try std.testing.expect(sim.g.extruded >= 8);
    try std.testing.expect(sim.g.waves_survived >= 2);
    // the stripped stretch cannot be flown; it was crossed on the line
    try std.testing.expect(sim.g.tether_uses >= 6);
    try std.testing.expect(r.stats.dual_time > 1.5);
    try std.testing.expect(r.stability > 0);
}

test "scripted pilot finishes the stomach chapter: pits under the waves, the colonies, the coat and the weld" {
    const gpa = std.testing.allocator;
    const sim = try gpa.create(Sim);
    defer gpa.destroy(sim);
    const cp = try gpa.create(Sim);
    defer gpa.destroy(cp);
    const r = runHeadlessChapter(sim, cp, 2, 1500, false);
    try std.testing.expect(r.completed);
    const g = &sim.g3;
    try std.testing.expectEqual(@as(u32, 0), sim.count(.colony));
    try std.testing.expectEqual(g.total, g.cleared);
    try std.testing.expect(g.sealed);
    // the waves were sat out in pits, not on the surface
    try std.testing.expect(g.waves_survived >= 2);
    try std.testing.expectEqual(@as(u32, 0), g.crush_hits);
    // swimmers were killed as they flared, and the hull met acid both bare and under the coat
    try std.testing.expect(g.swimmers_killed >= 4);
    try std.testing.expect(g.acid_time > 0.5);
    try std.testing.expect(g.has_coat and g.coat_time > 1.5);
    // the weld is the two-arm job: all of its heat went in while the other arm pressed
    try std.testing.expect(g.cautery_t >= ch3.seal_time - 0.1);
    try std.testing.expect(r.stats.dual_time > ch3.seal_time);
    try std.testing.expect(g.tether_uses >= 2);
    try std.testing.expect(r.stability > 0);
}

test "scripted pilot finishes the kidney chapter: the stalk, notch and blow, Resonance, and nothing lodged" {
    const gpa = std.testing.allocator;
    const sim = try gpa.create(Sim);
    defer gpa.destroy(sim);
    const cp = try gpa.create(Sim);
    defer gpa.destroy(cp);
    const r = runHeadlessChapter(sim, cp, 3, 1500, false);
    try std.testing.expect(r.completed);
    const g = &sim.g4;
    try std.testing.expect(g.neck_cut and g.has_resonance);
    // every piece left is small enough to pass, and none of them was made with a bare blow
    try std.testing.expectEqual(@as(u32, 0), ch4.oversized(sim));
    try std.testing.expect(g.clean_splits >= 7);
    try std.testing.expect(g.wave_splits >= 4);
    try std.testing.expectEqual(@as(u32, 15), g.clean_splits + g.wave_splits);
    try std.testing.expectEqual(@as(u32, 0), g.bad_punches);
    try std.testing.expectEqual(@as(u32, 0), g.lodged);
    // the shards shaken loose over the stalk were shot while the other arm kept drilling
    try std.testing.expect(g.shards_shot >= 2);
    try std.testing.expect(r.stats.dual_time > 3);
    // the tip was crossed between the ducts: the one spurt that took the drone is the one that delivered it
    try std.testing.expect(g.jet_hits <= 1);
    try std.testing.expect(r.stats.sync_strikes >= 2);
    try std.testing.expect(r.stability > 0);
}
