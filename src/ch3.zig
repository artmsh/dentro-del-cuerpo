//! Chapter 3 rules: the gastric antrum beside a bleeding ulcer. Acid outside the mucus gel, grinding waves
//! that close the lumen, Helicobacter that swims the gel faster than a round travels in it, the colonised
//! pits along the ulcer margin, and the eroded vessel in the crater that is welded shut with both arms.
//! The drone, arms, shots and guide queue are the shared machinery in game.zig; this file is what is
//! specific to the place.

const std = @import("std");
const m = @import("math.zig");
const game = @import("game.zig");
const stomach = @import("stomach.zig");
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
const Stomach = stomach.Stomach;

pub const start_z: f32 = 9000;
pub const swim_z: f32 = 6500;
pub const tether_range: f32 = 420;
pub const wave_period: f32 = 40;
/// Seconds of acid the Buffer Coat carries, and how fast it comes back in neutral surroundings.
pub const coat_max: f32 = 12;
pub const coat_recharge: f32 = 3;
/// Hull lost per second for each pH unit below `stomach.safe_ph`.
pub const acid_rate: f32 = 6;
/// Seconds of heat on the pressed vessel that weld it.
pub const seal_time: f32 = 6;
/// How long one punch holds the vessel flat.
pub const press_time: f32 = 1.1;
pub const colony_depth: f32 = 90;
pub const colony_r: f32 = 26;
pub const vessel_x: f32 = 90;
pub const vessel_z: f32 = 2100;
pub const exit_x: f32 = -260;
pub const exit_z: f32 = 1720;

const Said = struct {
    acid_reached: bool = false,
    acid: bool = false,
    heals: bool = false,
    crushed: bool = false,
    wave_ok: bool = false,
    seen: bool = false,
    outrun: bool = false,
    flare: bool = false,
    sync: bool = false,
    thin: bool = false,
    ammonia: bool = false,
    first_pit: bool = false,
    pit_shot: bool = false,
    coat_spent: bool = false,
    heat_alone: bool = false,
    pressed: bool = false,
    half: bool = false,
    vessel_shot: bool = false,
    tether_none: f32 = 0,
};

pub const State = struct {
    cleared: u32 = 0,
    total: u32 = 0,
    swimmers_killed: u32 = 0,
    crush_hits: u32 = 0,
    crush_t: f32 = 0,
    waves_survived: u32 = 0,
    wave_t: f32 = wave_period,
    ring_was_behind: bool = false,
    /// pH at the drone, for the HUD.
    ph: f32 = stomach.cell_ph,
    /// Seconds the bare hull spent in acid, and hull lost to it that neutral gel will give back.
    acid_time: f32 = 0,
    acid_dmg: f32 = 0,
    fizz_t: f32 = 0,
    has_coat: bool = false,
    coat: f32 = 0,
    /// Seconds the coat stood between the hull and acid.
    coat_time: f32 = 0,
    sealed: bool = false,
    sealed_t: f32 = 0,
    /// Seconds of heat applied while the vessel was pressed.
    cautery_t: f32 = 0,
    heat_t: f32 = 0,
    sizzle_t: f32 = 0,
    blood_lost: f32 = 0,
    colony_spawn_t: f32 = 2.5,
    clean_t: f32 = 0,
    tether_uses: u32 = 0,
    said: Said = .{},
};

// ---------------------------------------------------------------------------------------------- setup

pub fn vesselSite() Vec3 {
    return v3(vessel_x, stomach.surfaceY(vessel_x, vessel_z), vessel_z);
}

pub fn exitSite() Vec3 {
    return v3(exit_x, stomach.surfaceY(exit_x, exit_z) + 95, exit_z);
}

fn spawnSwimmer(s: *Sim, at: Vec3, home: Vec3, vel: Vec3) void {
    _ = s.spawn(.{ .kind = .pylori, .pos = at, .vel = vel, .end = home, .radius = 3, .hp = 1, .seed = s.rng.f(), .variant = @intCast(s.rng.below(3)), .timer = 1.0 });
}

pub fn begin(s: *Sim) void {
    const g = &s.g3;
    s.chapter = 2;
    s.in_bore = false;
    s.stability = 64;
    s.has_sync = true;
    s.has_tether = true;
    s.arms = .{ .{ .tool = .shoot }, .{ .tool = .punch } };

    // Arrival: set down in the gel over healthy mucosa near the pylorus, facing the ulcer.
    const home = stomach.pitNear(0, start_z).?;
    s.pos = home.mouth().add(v3(0, 110, 0));
    s.yaw = m.pi;
    s.pitch = -0.3;
    s.warp = 1;

    // Four colonised pits in the first rows of pits beside the ulcer.
    const sites = [_][2]f32{ .{ -560, 60 }, .{ -190, 190 }, .{ 180, 60 }, .{ 560, 190 } };
    for (sites) |xz| {
        const pit = stomach.pitNear(xz[0], stomach.marginZ(xz[0]) + stomach.bare_band + xz[1]).?;
        _ = s.spawn(.{ .kind = .colony, .pos = pit.down(colony_depth), .end = Vec3.up, .radius = colony_r, .hp = 9, .max_hp = 9, .seed = s.rng.f() });
        g.total += 1;
    }

    // The eroded vessel in the bed, and the venule beside it that is the way out.
    const vs = vesselSite();
    const n = Stomach.tissue(vs.add(v3(0, 6, 0))).n;
    _ = s.spawn(.{ .kind = .vessel, .pos = vs.add(n.scale(8)), .end = n, .radius = 22, .seed = 0.4 });
    _ = s.spawn(.{ .kind = .ring, .pos = exitSite(), .radius = 90, .variant = 3 });

    // What the antrum is grinding: particles of the last meal, above the gel.
    for (0..10) |i| {
        const z = 3900 + @as(f32, @floatFromInt(i)) * 580 + s.rng.range(-150, 150);
        const at = v3(s.rng.range(-900, 900), s.rng.range(380, 760), z);
        _ = s.spawn(.{ .kind = .grit, .pos = at, .radius = s.rng.range(12, 26), .seed = s.rng.f(), .variant = @intCast(s.rng.below(3)) });
    }

    s.setStage(.s_arrive);
}

// ---------------------------------------------------------------------------------------------- stages

pub fn enter(s: *Sim, st: Stage) void {
    const g = &s.g3;
    switch (st) {
        .s_arrive => {
            s.say(L.through_the_pylorus);
            s.say(L.this_is_the_antrum);
            s.waypoint = null;
        },
        .s_pits => {
            s.say(L.look_down_at_the_pits);
            s.waypoint = null;
        },
        .s_gradient => {
            s.atlas[@intFromEnum(Topic.mucus_gel)] = true;
            s.say(L.you_are_inside_the_gel);
            s.say(L.climb_and_watch_the_ph);
            s.waypoint = v3(s.pos.x, 260, s.pos.z - 60);
        },
        .s_wave => {
            s.want_checkpoint = true;
            s.sto.launch(@max(-1700, s.pos.z - 4400));
            g.ring_was_behind = false;
            s.urgent(L.antral_wave_coming);
            s.say(L.get_into_a_pit);
            s.sound(.transit, 0, 0.5);
            const pit = stomach.pitNear(s.pos.x, s.pos.z).?;
            s.waypoint = pit.down(100);
        },
        .s_swim => {
            s.want_checkpoint = true;
            s.say(L.the_ulcer_is_ahead);
            g.wave_t = wave_period;
            for (0..3) |i| {
                const k = @as(f32, @floatFromInt(i));
                const at = v3(s.pos.x - 160 + 160 * k, 70 + 20 * k, s.pos.z - 620 - 90 * k);
                spawnSwimmer(s, at, at, .{});
            }
            s.waypoint = v3(0, 90, swim_z);
        },
        .s_margin => {
            s.want_checkpoint = true;
            s.stabilise(6);
            s.say(L.thats_the_ulcer);
            s.say(L.colonies_in_the_pits);
            g.wave_t = @min(g.wave_t, 24);
        },
        .s_cross => {
            s.want_checkpoint = true;
            s.say(L.coat_is_live);
            s.say(L.the_vessel_is_in_the_bed);
            s.waypoint = vesselSite().add(v3(0, 40, 0));
        },
        .s_cautery => {
            s.want_checkpoint = true;
            s.say(L.there_it_is_pulsing);
            s.say(L.press_it_then_weld);
        },
        .s_exit => {
            s.want_checkpoint = true;
            s.say(L.marker_on_a_venule);
            s.waypoint = exitSite();
        },
        else => {},
    }
}

pub fn upgradeTaken(s: *Sim) void {
    const g = &s.g3;
    g.has_coat = true;
    g.coat = coat_max;
    s.mode = .playing;
    s.sound(.upgrade, 0, 1);
    s.setStage(.s_cross);
}

pub fn objective(s: *const Sim, p: bindings.Prompt, buf: []u8) []const u8 {
    const g = &s.g3;
    const text: Text = switch (s.stage) {
        .s_arrive => O.s_arrive,
        .s_pits => O.s_pits,
        .s_gradient => {
            if (g.said.acid_reached) return bindings.format(buf, p, O.s_gradient_back, .{i18n.fixed(g.ph, 1)});
            return bindings.format(buf, p, O.s_gradient, .{i18n.fixed(g.ph, 1)});
        },
        .s_wave => O.s_wave,
        .s_swim => return bindings.format(buf, p, O.s_swim, .{i18n.int(s.count(.pylori))}),
        .s_margin => return bindings.format(buf, p, O.s_margin, .{ i18n.int(g.cleared), i18n.int(g.total), i18n.int(s.count(.pylori)) }),
        .s_cross => O.s_cross,
        .s_cautery => return bindings.format(buf, p, O.s_cautery, .{i18n.int(sealPercent(s))}),
        .s_exit => O.transit_marker,
        else => return "",
    };
    return bindings.resolve(buf, text, p);
}

pub fn hintText(s: *const Sim) Text {
    const lv: usize = @min(s.hint_level, 2);
    return switch (s.stage) {
        .s_pits => H.s_pits[lv],
        .s_gradient => H.s_gradient[lv],
        .s_wave => H.s_wave[lv],
        .s_swim => H.s_swim[lv],
        .s_margin => H.s_margin[lv],
        .s_cross => H.s_cross[lv],
        .s_cautery => H.s_cautery[lv],
        .s_exit => H.g_exit,
        else => H.wait,
    };
}

// ---------------------------------------------------------------------------------------------- the place

fn vessel(s: *const Sim) ?*const game.Entity {
    return s.findConst(.vessel);
}

pub fn sealPercent(s: *const Sim) i32 {
    if (s.g3.sealed) return 100;
    const e = vessel(s) orelse return 0;
    return @intFromFloat(@min(99, 100 * e.aux));
}

/// Strength of the arterial pulse in the eroded vessel, 0..1.
pub fn pulse(s: *const Sim) f32 {
    const k = @max(0, @sin(s.clock * m.tau * 1.15));
    return k * k;
}

/// Acidity at a point: the gel's gradient, raised around anything that neutralises acid. A Helicobacter
/// colony splits urea into ammonia; blood is buffered at pH 7.4.
pub fn phAt(s: *const Sim, p: Vec3) f32 {
    var out = stomach.ph(p);
    if (out >= stomach.cell_ph) return out;
    for (&s.ents) |*e| {
        const reach: [2]f32 = switch (e.kind) {
            .colony => .{ 60, 135 },
            .vessel => if (e.state == 0) .{ 70, 200 } else continue,
            else => continue,
        };
        const k = 1 - m.smoothstep(reach[0], reach[1], e.pos.dist(p));
        out = @max(out, stomach.acid_ph + (stomach.cell_ph - stomach.acid_ph) * k);
    }
    return out;
}

/// The gastric contents plus the jet from the bleeding vessel.
pub fn flowAt(s: *const Sim, p: Vec3) Vec3 {
    var fl = s.sto.flowAt(p, s.clock);
    if (vessel(s)) |e| {
        if (e.state == 0 and e.timer <= 0) {
            const rel = p.sub(e.pos);
            const along = rel.dot(e.end);
            if (along > 0 and along < 300) {
                const lateral = rel.sub(e.end.scale(along)).len();
                if (lateral < 40 + along * 0.3) fl = fl.add(e.end.scale(360 * pulse(s) * (1 - along / 300)));
            }
        }
    }
    return fl;
}

pub fn focusRay(s: *const Sim, o: Vec3, d: Vec3, max_t: f32) ?game.Focus {
    const h = s.sto.raycast(o, d, max_t) orelse return null;
    return .{ .dist = h.t, .point = h.point, .tissue = h.what != .contraction, .topic = switch (h.what) {
        .surface => .surface_mucous_cell,
        .pit => .gastric_pit,
        .margin => .ulcer_margin,
        .bed => .ulcer_bed,
        .contraction => .antral_wave,
    } };
}

/// Chapter collision and the hazards tied to position: the walls meeting, and acid.
pub fn moveCollide(s: *Sim, p: Vec3, dt: f32) void {
    const g = &s.g3;
    const res = s.sto.collide(p, game.hull_r);
    s.pos = res.pos;
    if (res.crushed) {
        g.crush_t += dt;
        s.hull -= 34 * dt;
        s.hurt = @max(s.hurt, 0.7);
        s.shake = @max(s.shake, 0.5);
        if (g.crush_t > 0.35) {
            g.crush_t = 0;
            g.crush_hits += 1;
            s.sound(.hurt, 0, 1);
        }
        if (!g.said.crushed) {
            g.said.crushed = true;
            s.urgent(L.the_walls_have_you);
        }
        if (s.hull <= 0) s.hurtDrone(1);
    }

    const ph = phAt(s, s.pos);
    g.ph = ph;
    if (s.hull >= 100) g.acid_dmg = 0;
    if (ph < stomach.safe_ph) {
        if (g.coat > 0) {
            g.coat = @max(0, g.coat - dt);
            g.coat_time += dt;
            if (g.coat <= 0 and !g.said.coat_spent) {
                g.said.coat_spent = true;
                s.urgent(L.coats_spent);
            }
        } else {
            const loss = (stomach.safe_ph - ph) * acid_rate * dt;
            s.hull -= loss;
            g.acid_dmg += loss;
            g.acid_time += dt;
            s.hurt = @max(s.hurt, 0.3);
            g.fizz_t -= dt;
            if (g.fizz_t <= 0) {
                g.fizz_t = 0.35;
                s.sound(.acid, 0, 0.7);
            }
            if (!g.said.acid and s.stage != .s_gradient and s.stage != .s_arrive and s.stage != .s_pits) {
                g.said.acid = true;
                s.urgent(L.thats_acid_on_the_hull);
            }
            if (s.hull <= 0) s.hurtDrone(1);
        }
    } else if (ph >= 6) {
        const back = @min(@min(g.acid_dmg, 5 * dt), @max(0, 100 - s.hull));
        s.hull += back;
        g.acid_dmg -= back;
        if (g.has_coat) g.coat = @min(coat_max, g.coat + coat_recharge * dt);
    }
}

/// What the tether would grab right now: the tissue along the line of sight, within reach.
pub fn tetherTarget(s: *const Sim) ?stomach.RayHit {
    const h = s.sto.raycast(s.pos, s.forward(), tether_range) orelse return null;
    if (h.what == .contraction) return null;
    return h;
}

/// Where the line holds the drone for a grab at `h`: off the surface, or on the axis of a pit.
fn holdFor(s: *const Sim, h: stomach.RayHit) Vec3 {
    if (h.what == .pit) {
        const c = stomach.cellOf(h.point.x, h.point.z);
        if (stomach.pitAt(c[0], c[1])) |pit| {
            var depth = m.clamp(-h.point.y, 60, stomach.pit_depth - 40);
            // a colonised pit is plugged: hold in its mouth
            for (&s.ents) |*e| {
                if (e.kind == .colony and @abs(e.pos.x - pit.x) < 5 and @abs(e.pos.z - pit.z) < 5) depth = colony_depth - colony_r - 30;
            }
            return pit.down(depth);
        }
    }
    const n = Stomach.tissue(h.point.sub(s.forward().scale(2))).n;
    return h.point.add(n.scale(38));
}

pub fn tetherKey(s: *Sim) void {
    const g = &s.g3;
    if (!s.has_tether) return;
    const hit = tetherTarget(s);
    if (hit != null and (s.tether == null or hit.?.point.dist(s.tether.?) > 40)) {
        s.tether = hit.?.point;
        s.tether_hold = holdFor(s, hit.?);
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
    switch (tp) {
        .gastric_pit, .surface_mucous_cell => if (s.stage == .s_pits) s.setStage(.s_gradient),
        else => {},
    }
}

// ---------------------------------------------------------------------------------------------- organisms

fn killSwimmer(s: *Sim, idx: u16) void {
    const g = &s.g3;
    const e = &s.ents[idx];
    if (e.kind != .pylori) return;
    s.burst(e.pos, 10, 90, .{ 0.75, 1, 0.35, 1 }, 2.2, 0.5);
    s.sound(.kill, m.clamp(e.pos.sub(s.pos).dot(s.right()) / 60, -1, 1), 0.9);
    e.kind = .none;
    g.swimmers_killed += 1;
    s.stats.kills += 1;
    if (s.stage == .s_swim) s.progress();
}

fn killColony(s: *Sim, idx: u16) void {
    const g = &s.g3;
    const e = &s.ents[idx];
    s.burst(e.pos.add(v3(0, e.radius, 0)), 50, 150, .{ 0.75, 1, 0.35, 1 }, 4, 0.9);
    e.kind = .none;
    g.cleared += 1;
    s.sound(.nest_die, 0, 1);
    s.stabilise(3);
    s.progress();
    if (g.cleared >= g.total) {
        s.say(L.the_margin_is_clean);
    } else if (!g.said.first_pit) {
        g.said.first_pit = true;
        s.say(L.one_pit_clean);
    }
}

fn sealVessel(s: *Sim, idx: u16) void {
    const g = &s.g3;
    const e = &s.ents[idx];
    e.state = 1;
    e.aux = 1;
    e.flash = 1;
    g.sealed = true;
    g.sealed_t = 0;
    s.burst(e.pos, 40, 120, .{ 1, 0.95, 0.8, 1 }, 3, 0.9);
    s.stabilise(12);
    s.sound(.objective, 0, 1);
    s.voice.clear();
    s.say(L.its_sealed);
}

/// Where the drill is heard: on the side of the arm that carries it.
fn drillPan(s: *const Sim) f32 {
    if (s.arms[0].tool == .drill and s.arms[0].held) return -0.7;
    if (s.arms[1].tool == .drill and s.arms[1].held) return 0.7;
    return 0;
}

/// A Sync punch: the shockwave reaches every swimmer within arm's length, gel or no gel.
pub fn syncWave(s: *Sim) void {
    for (&s.ents, 0..) |*e, idx| {
        if (e.kind == .pylori and e.pos.dist(s.pos) < 75) killSwimmer(s, @intCast(idx));
    }
}

pub fn punched(s: *Sim, idx: u16, dir: Vec3) void {
    const g = &s.g3;
    const e = &s.ents[idx];
    switch (e.kind) {
        .pylori => killSwimmer(s, idx),
        .colony => e.flash = 0.5,
        .vessel => if (e.state == 0) {
            e.timer = press_time;
            e.flash = 0.6;
            s.burst(e.pos, 6, 60, .{ 1, 0.25, 0.2, 1 }, 2.5, 0.4);
            if (!g.said.pressed and g.heat_t <= 0 and g.has_coat) {
                g.said.pressed = true;
                s.say(L.its_pressed_heat_it_now);
            }
        },
        .grit => e.vel = e.vel.add(dir.scale(140)),
        else => {},
    }
}

/// Returns true when the round is spent.
pub fn shotHit(s: *Sim, sh: *game.Shot, idx: u16, at: Vec3) bool {
    const g = &s.g3;
    const e = &s.ents[idx];
    const dmg: f32 = if (sh.lance) game.lance_factor else 1;
    const arm = &s.arms[sh.arm];
    switch (e.kind) {
        .pylori => {
            killSwimmer(s, idx);
            arm.flash = 1;
            return !sh.lance;
        },
        .colony => {
            e.hp -= dmg;
            e.flash = 1;
            arm.flash = 1;
            s.burst(at, 6, 80, .{ 0.75, 1, 0.35, 1 }, 2.5, 0.4);
            s.sound(.punch_hit, 0, 0.5);
            if (e.hp <= 0) killColony(s, idx);
            return true;
        },
        .vessel => {
            s.burst(at, 8, 90, .{ 1, 0.2, 0.2, 1 }, 3, 0.5);
            if (e.state == 0) {
                s.tissueDamage(3, true);
                e.aux = @max(0, e.aux - 0.15);
                if (!g.said.vessel_shot) {
                    g.said.vessel_shot = true;
                    s.urgent(L.not_rounds_at_a_vessel);
                }
            }
            return true;
        },
        .grit => {
            s.burst(at, 4, 40, .{ 0.8, 0.7, 0.45, 1 }, 3, 0.4);
            s.sound(.absorb, 0, 0.5);
            return true;
        },
        else => return false,
    }
}

/// Returns true while the bit is working.
pub fn drilled(s: *Sim, idx: u16, point: Vec3, rate: f32, dt: f32, spark: bool) bool {
    const g = &s.g3;
    const e = &s.ents[idx];
    switch (e.kind) {
        .pylori => {
            killSwimmer(s, idx);
            return true;
        },
        .colony => {
            e.hp -= 2.2 * rate * dt;
            e.flash = 0.6;
            s.latched = true;
            if (spark) s.burst(point, 2, 60, .{ 0.75, 1, 0.35, 1 }, 2.5, 0.4);
            if (e.hp <= 0) killColony(s, idx);
            return true;
        },
        .vessel => {
            s.latched = true;
            if (e.state != 0) return true;
            g.heat_t = 0.3;
            if (!g.has_coat) return true;
            if (e.timer > 0) {
                e.aux += rate * dt / seal_time;
                g.cautery_t += dt;
                if (spark) s.burst(point, 3, 70, .{ 1, 0.9, 0.7, 1 }, 2.2, 0.35);
                g.sizzle_t -= dt;
                if (g.sizzle_t <= 0) {
                    g.sizzle_t = 0.3;
                    s.sound(.sizzle, drillPan(s), 0.7);
                }
                if (!g.said.half and e.aux > 0.5) {
                    g.said.half = true;
                    s.voice.say(L.half_welded, .chatter);
                }
                if (e.aux >= 1) sealVessel(s, idx);
            } else if (!g.said.heat_alone and s.stage_t > 2.5) {
                g.said.heat_alone = true;
                s.say(L.heat_alone_wont_hold);
            }
            return true;
        },
        .grit => {
            s.burst(e.pos, 12, 70, .{ 0.8, 0.7, 0.45, 1 }, 3, 0.6);
            e.kind = .none;
            return true;
        },
        else => return false,
    }
}

/// A round reached the mucosa.
pub fn shotTissue(s: *Sim, h: stomach.RayHit) void {
    const g = &s.g3;
    s.burst(h.point, 6, 50, .{ 1, 0.4, 0.3, 1 }, 3, 0.5);
    switch (h.what) {
        .pit => {
            s.tissueDamage(2.5, true);
            if (!g.said.pit_shot) {
                g.said.pit_shot = true;
                s.urgent(L.mind_the_pit_walls);
            }
        },
        .surface, .margin => s.tissueDamage(1.5, true),
        // slough and granulation tissue: already lost, and it soaks up a round
        .bed => s.sound(.absorb, 0, 0.5),
        .contraction => s.tissueDamage(1.5, true),
    }
}

/// Rounds drag in the gel: a round that leaves the muzzle at 950 µm/s is down to walking pace within a
/// tenth of a millimetre, which is what lets a swimmer outrun it.
pub fn shotDrag(sh: *game.Shot, dt: f32) void {
    const p = sh.pos;
    if (p.y >= stomach.surfaceY(p.x, p.z) + stomach.mucus(p.x, p.z)) return;
    const v = sh.vel.len();
    const slow: f32 = 200;
    if (v <= slow) return;
    sh.vel = sh.vel.scale((slow + (v - slow) * @exp(-7 * dt)) / v);
}

/// Top of the layer a swimmer keeps to at (x, z).
fn gelCeiling(x: f32, z: f32) f32 {
    return stomach.surfaceY(x, z) + @max(0.7 * stomach.mucus(x, z), 70);
}

fn updateSwimmer(s: *Sim, idx: u16, dt: f32) void {
    const g = &s.g3;
    const e = &s.ents[idx];
    e.timer -= dt;
    const to_drone = s.pos.sub(e.pos);
    const dd = to_drone.len();
    const dir = to_drone.scale(1 / @max(dd, 1e-3));
    switch (e.state) {
        0 => {
            // a round coming its way through the gel: gone before it arrives
            for (&s.shots) |*sh| {
                if (!sh.alive) continue;
                const rel = e.pos.sub(sh.pos);
                const rl = rel.len();
                if (rl > 260 or rl < 1) continue;
                const sd = sh.vel.norm();
                if (rel.dot(sd) / rl < 0.93) continue;
                e.state = 3;
                e.timer = 0.75;
                e.vel = sd.scale(330).add(sd.perp().scale(if (e.seed > 0.5) @as(f32, 60) else -60));
                if (!g.said.outrun and rl > 70) {
                    g.said.outrun = true;
                    s.say(L.they_outrun_your_rounds);
                }
                break;
            }
            if (e.state == 0) {
                var want: Vec3 = undefined;
                if (dd < 330) {
                    // corkscrew: the path winds around the line to the drone
                    const a = s.clock * 9 + e.seed * 40;
                    const side = dir.perp();
                    const wind = side.scale(@cos(a)).add(dir.cross(side).scale(@sin(a))).scale(36);
                    want = dir.scale(if (dd > 50) @as(f32, 118) else 0).add(wind);
                } else {
                    const a = s.clock * (0.5 + 0.4 * e.seed) + e.seed * 30;
                    const home = e.end.add(v3(@sin(a) * 60, @sin(a * 0.7) * 14, @cos(a * 1.2) * 60));
                    want = home.sub(e.pos).scale(1.2);
                    const wl = want.len();
                    if (wl > 60) want = want.scale(60 / wl);
                }
                e.vel = e.vel.add(want.sub(e.vel).scale(1 - @exp(-4 * dt)));
                if (dd < 72 and e.timer <= 0 and s.windup_lock <= 0) {
                    e.state = 1;
                    e.timer = 0.7;
                    e.aux = 0;
                    s.windup_lock = 0.45;
                    s.sound(.windup, m.clamp(to_drone.dot(s.right()) / -60, -1, 1), 0.8);
                    if (!g.said.flare) {
                        g.said.flare = true;
                        s.urgent(L.strike_when_it_flares);
                    }
                }
            }
        },
        1 => {
            e.aux = m.sat(1 - e.timer / 0.7);
            e.vel = e.vel.scale(@exp(-7 * dt));
            if (e.timer <= 0) {
                e.state = 2;
                e.timer = 0.42;
                e.vel = dir.scale(430);
            }
        },
        2 => {
            if (dd < game.hull_r + e.radius + 2) {
                s.burst(e.pos, 10, 90, .{ 0.75, 1, 0.35, 1 }, 2.4, 0.5);
                e.kind = .none;
                s.hurtDrone(8);
                return;
            }
            if (e.timer <= 0) {
                e.state = 0;
                e.timer = 1.2;
                e.aux = 0;
            }
        },
        else => {
            e.vel = e.vel.scale(@exp(-1.2 * dt));
            if (e.timer <= 0) {
                e.state = 0;
                e.timer = 0.6;
            }
        },
    }
    var p = s.sto.collide(e.pos.add(e.vel.scale(dt)), e.radius).pos;
    p.y = @min(p.y, gelCeiling(p.x, p.z));
    e.pos = p;
}

pub fn updateEntity(s: *Sim, idx: u16, dt: f32) void {
    const g = &s.g3;
    const e = &s.ents[idx];
    switch (e.kind) {
        .pylori => updateSwimmer(s, idx, dt),
        .colony => {
            if (s.stage != .s_margin or s.pos.dist(e.pos) > 420) return;
            if (!g.said.ammonia and s.pos.dist(e.pos) < 110) {
                g.said.ammonia = true;
                s.say(L.their_ammonia);
            }
        },
        .vessel => {
            e.timer = @max(0, e.timer - dt);
            if (e.state != 0) return;
            if (g.heat_t <= 0) e.aux = @max(0, e.aux - 0.04 * dt);
            // the jet: a few drops each beat, thrown along the vessel's axis
            if (e.timer <= 0 and s.rng.f() < dt * 50 * pulse(s)) {
                s.burst(e.pos.add(e.end.scale(e.radius * 0.6)), 1, 40, .{ 1, 0.12, 0.1, 1 }, 4.5, 1.1);
                const last = &s.parts[(s.part_cursor + game.max_parts - 1) % game.max_parts];
                last.vel = last.vel.add(e.end.scale(230));
                last.drag = 1.4;
            }
        },
        .grit => {
            const fl = s.sto.flowAt(e.pos, s.clock);
            e.vel = e.vel.add(fl.scale(0.8).sub(e.vel).scale(1 - @exp(-1.5 * dt)));
            var p = e.pos.add(e.vel.scale(dt));
            // carried off through the pylorus: another takes its place upstream
            if (p.z > stomach.z_max - 200) p.z = stomach.ulcer_r + 500;
            if (p.z < stomach.ulcer_r + 300) p.z = stomach.ulcer_r + 300;
            p.y = @max(p.y, stomach.mucus(p.x, p.z) + e.radius + 20);
            e.pos = s.sto.collide(p, e.radius).pos;
        },
        else => {},
    }
}

// ---------------------------------------------------------------------------------------------- script

/// Seconds until the leading edge of the wave reaches the drone, if one is on its way.
pub fn ringEta(s: *const Sim) ?f32 {
    const rz = s.sto.ring_z orelse return null;
    const lead = rz + stomach.ring_half;
    if (lead >= s.pos.z) return 0;
    return (s.pos.z - lead) / stomach.ring_speed;
}

/// True while the lumen above the drone is closing or closed.
pub fn underRing(s: *const Sim) bool {
    return s.sto.squeeze(s.pos.z) > 0.02;
}

/// True where a wave can do nothing to the drone: inside a pit, below its mouth.
pub fn sheltered(s: *const Sim) bool {
    return s.pos.y < -game.hull_r and stomach.into(s.pos.x, s.pos.z) < -stomach.bare_band + 40;
}

pub fn inCrater(p: Vec3) bool {
    return stomach.into(p.x, p.z) > 0;
}

fn waveClock(s: *Sim, dt: f32) void {
    const g = &s.g3;
    g.said.tether_none = @max(0, g.said.tether_none - dt);
    if (s.sto.ring_z) |rz| {
        const behind = rz < s.pos.z;
        if (g.ring_was_behind and !behind and rz > s.pos.z + stomach.ring_half * 0.9) {
            g.ring_was_behind = false;
            g.waves_survived += 1;
        }
        if (behind) g.ring_was_behind = true;
    }
    if (@intFromEnum(s.stage) < @intFromEnum(Stage.s_swim) or s.stage == .s_exit) return;
    g.wave_t -= dt;
    if (g.wave_t <= 0 and s.sto.ring_z == null) {
        g.wave_t = wave_period;
        s.sto.launch(@max(-1700, s.pos.z - 4400));
        g.ring_was_behind = false;
        s.urgent(if (inCrater(s.pos)) L.wave_coming_hold_the_bed else L.wave_coming_into_a_pit);
        s.sound(.transit, 0, 0.5);
    }
}

fn nearestColony(s: *const Sim) ?Vec3 {
    var best: f32 = 1e12;
    var out: ?Vec3 = null;
    for (&s.ents) |*e| {
        if (e.kind != .colony) continue;
        const d = e.pos.dist(s.pos);
        if (d < best) {
            best = d;
            out = v3(e.pos.x, 30, e.pos.z);
        }
    }
    return out;
}

pub fn script(s: *Sim, dt: f32) void {
    const g = &s.g3;
    waveClock(s, dt);
    g.heat_t = @max(0, g.heat_t - dt);
    if (s.stall_t > 55 and !s.said.stall) {
        s.said.stall = true;
        s.voice.say(L.if_you_want_a_pointer, .chatter);
    }
    // The vessel bleeds from the moment its plug of colonised slough is gone until it is welded.
    if (g.has_coat and !g.sealed) {
        if (vessel(s)) |e| {
            if (e.timer <= 0) {
                g.blood_lost += dt;
                s.stability = @max(0, s.stability - 0.3 * dt);
            }
        }
    }
    switch (s.stage) {
        .s_arrive => if (s.stage_t > 6.5) s.setStage(.s_pits),
        .s_pits => {},
        .s_gradient => {
            if (!g.said.acid_reached and g.ph < 4) {
                g.said.acid_reached = true;
                s.atlas[@intFromEnum(Topic.gastric_juice)] = true;
                s.urgent(L.thats_acid_come_down);
                s.waypoint = v3(s.pos.x, 80, s.pos.z);
            }
            if (g.said.acid_reached and g.ph > 6.5) {
                if (!g.said.heals) {
                    g.said.heals = true;
                    s.say(L.the_hull_recovers_in_gel);
                }
                s.setStage(.s_wave);
            }
        },
        .s_wave => {
            const passed = if (s.sto.ring_z) |rz| rz > s.pos.z + stomach.ring_half else true;
            if (passed and s.stage_t > 3) {
                if (!g.said.wave_ok and g.crush_hits == 0) {
                    g.said.wave_ok = true;
                    s.say(L.it_has_closed_over_you);
                }
                s.setStage(.s_swim);
            }
        },
        .s_swim => {
            if (!g.said.seen and s.stage_t > 1.5) {
                if (s.nearest(.pylori)) |p| {
                    if (p.dist(s.pos) < 420) {
                        g.said.seen = true;
                        s.say(L.corkscrews_in_the_gel);
                    }
                }
            }
            if (s.count(.pylori) == 0 and s.stage_t > 2) s.setStage(.s_margin);
        },
        .s_margin => {
            s.waypoint = nearestColony(s);
            if (!g.said.thin and stomach.mucus(s.pos.x, s.pos.z) < 150) {
                g.said.thin = true;
                s.say(L.the_gel_is_thin_here);
            }
            if (g.cleared < g.total) {
                // colonies shed swimmers while the pilot is near
                g.colony_spawn_t -= dt;
                if (g.colony_spawn_t <= 0 and s.count(.pylori) < 3) {
                    g.colony_spawn_t = 4.5;
                    var best: f32 = 420;
                    var from: ?Vec3 = null;
                    for (&s.ents) |*e| {
                        if (e.kind != .colony) continue;
                        const d = e.pos.dist(s.pos);
                        if (d < best) {
                            best = d;
                            from = e.pos;
                        }
                    }
                    if (from) |c| {
                        const at = v3(c.x + s.rng.range(-14, 14), -colony_depth + colony_r + 8, c.z + s.rng.range(-14, 14));
                        spawnSwimmer(s, at, v3(c.x, 40, c.z), v3(0, 80, 0));
                    }
                }
                if (!g.said.sync and s.count(.pylori) >= 3) {
                    g.said.sync = true;
                    s.voice.say(L.a_sync_punch_clears_them, .chatter);
                }
            } else {
                g.clean_t += dt;
                if ((g.clean_t > 3 and s.count(.pylori) == 0) or g.clean_t > 14) s.mode = .upgrade_card;
            }
        },
        .s_cross => if (vessel(s)) |e| {
            s.waypoint = e.pos.add(e.end.scale(34));
            if (s.pos.dist(e.pos) < 190) s.setStage(.s_cautery);
        },
        .s_cautery => {
            s.waypoint = if (vessel(s)) |e| e.pos else null;
            if (g.sealed) {
                g.sealed_t += dt;
                if (g.sealed_t > 2.5) s.setStage(.s_exit);
            }
        },
        .s_exit => if (s.atRing(3)) {
            s.say(L.gastric_vein_next);
            s.setStage(.done);
        },
        else => {},
    }
}

pub fn gradePenalty(s: *const Sim) f32 {
    const g = &s.g3;
    return @as(f32, @floatFromInt(g.crush_hits)) * 1.5;
}

/// Centimetres to the pylorus, for the HUD.
pub fn locationCm(s: *const Sim) f32 {
    return 1.2 + (stomach.z_max - s.pos.z) / 10000.0;
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

test "acid erodes the bare hull above the gel, the gel gives it back, and the coat buys twelve seconds" {
    const gpa = std.testing.allocator;
    const s = try gpa.create(Sim);
    defer gpa.destroy(s);
    s.* = Sim.initChapter(2);
    s.stage = .s_swim;
    s.voice.clear();
    const pit = stomach.pitNear(300, 8000).?;
    // in the gel: nothing happens
    s.pos = v3(pit.x + 75, 60, pit.z);
    settle(s, .{}, 2);
    try std.testing.expectEqual(@as(f32, 100), s.hull);
    try std.testing.expect(s.g3.ph > 6.5);
    // above it: the hull goes at ~15 a second
    s.pos = v3(pit.x + 75, 420, pit.z);
    settle(s, .{}, 2);
    try std.testing.expect(s.hull < 76 and s.hull > 62);
    try std.testing.expect(s.g3.ph < 2.1);
    try std.testing.expect(s.g3.acid_time > 1.9);
    // back down: what acid took comes back, and no more than that
    s.hull -= 10;
    s.pos = v3(pit.x + 75, 60, pit.z);
    settle(s, .{}, 12);
    try std.testing.expectApproxEqAbs(@as(f32, 90), s.hull, 0.5);

    // with the coat, the same two seconds cost nothing, and the reserve runs out at twelve
    s.g3.has_coat = true;
    s.g3.coat = coat_max;
    s.pos = v3(pit.x + 75, 420, pit.z);
    settle(s, .{}, 2);
    try std.testing.expectApproxEqAbs(@as(f32, 90), s.hull, 0.5);
    try std.testing.expectApproxEqAbs(coat_max - 2, s.g3.coat, 0.1);
    s.pos = v3(pit.x + 75, 420, pit.z);
    settle(s, .{}, 10.5);
    try std.testing.expect(s.g3.coat == 0 and s.hull < 88);
    // and it recharges in the gel
    s.pos = v3(pit.x + 75, 60, pit.z);
    s.vrel = .{};
    settle(s, .{}, 5);
    try std.testing.expectApproxEqAbs(coat_max, s.g3.coat, 0.01);
}

test "a wave crushes a drone on the surface and passes over one in a pit" {
    const gpa = std.testing.allocator;
    const s = try gpa.create(Sim);
    defer gpa.destroy(s);
    s.* = Sim.initChapter(2);
    s.stage = .s_swim;
    s.voice.clear();
    const pit = stomach.pitNear(-300, 8000).?;
    s.pos = v3(pit.x + 75, 40, pit.z);
    s.sto.launch(pit.z - 2600);
    settle(s, .{}, 12);
    try std.testing.expect(s.g3.crush_hits > 0);
    try std.testing.expect(s.hull < 60 or s.mode == .dead);

    s.* = Sim.initChapter(2);
    s.stage = .s_swim;
    s.voice.clear();
    s.pos = pit.down(100);
    s.sto.launch(pit.z - 2600);
    settle(s, .{}, 12);
    try std.testing.expectEqual(@as(u32, 0), s.g3.crush_hits);
    try std.testing.expectEqual(@as(f32, 100), s.hull);
    try std.testing.expectEqual(@as(u32, 1), s.g3.waves_survived);
    try std.testing.expect(s.pos.dist(pit.down(100)) < 30);
}

test "a swimmer outruns a round fired from a distance through the gel and dies to one fired as it flares" {
    const gpa = std.testing.allocator;
    const s = try gpa.create(Sim);
    defer gpa.destroy(s);
    s.* = Sim.initChapter(2);
    s.stage = .s_swim;
    s.voice.clear();
    s.arms = .{ .{ .tool = .shoot }, .{ .tool = .punch } };
    const pit = stomach.pitNear(0, 8000).?;
    s.pos = v3(pit.x + 75, 80, pit.z);
    s.yaw = m.pi;
    s.pitch = 0;
    // far enough that it has not noticed the drone yet
    const at = s.pos.add(v3(0, 0, -200));
    const i = s.spawn(.{ .kind = .pylori, .pos = at, .end = at, .radius = 3, .hp = 1, .seed = 0.2, .timer = 30 }).?;
    s.g3.wave_t = 1000;
    var t: f32 = 0;
    while (t < 1.5) : (t += 1.0 / 60.0) {
        lookAt(s, s.ents[i].pos);
        s.update(.{ .arm = .{ true, false } }, 1.0 / 60.0);
    }
    try std.testing.expectEqual(game.Kind.pylori, s.ents[i].kind);
    try std.testing.expect(s.g3.said.outrun);

    // let it come in and flare, then fire
    s.ents[i].timer = 0;
    t = 0;
    while (t < 20 and s.ents[i].kind == .pylori) : (t += 1.0 / 60.0) {
        lookAt(s, s.ents[i].pos);
        s.update(.{ .arm = .{ s.ents[i].state == 1, false } }, 1.0 / 60.0);
    }
    try std.testing.expect(s.ents[i].kind != .pylori);
    try std.testing.expectEqual(@as(u32, 1), s.g3.swimmers_killed);
    try std.testing.expectEqual(@as(f32, 100), s.hull);

    // the same round above the gel keeps its speed
    var free: game.Shot = .{ .alive = true, .pos = v3(0, 500, 8000), .vel = v3(0, 0, -950) };
    shotDrag(&free, 0.1);
    try std.testing.expectEqual(@as(f32, -950), free.vel.z);
    var dragged: game.Shot = .{ .alive = true, .pos = v3(0, 80, 8000), .vel = v3(0, 0, -950) };
    shotDrag(&dragged, 0.1);
    try std.testing.expect(dragged.vel.z > -600);
}

test "the vessel welds only while it is pressed: drill alone does nothing, punch and drill together seal it" {
    const gpa = std.testing.allocator;
    const s = try gpa.create(Sim);
    defer gpa.destroy(s);
    s.* = Sim.initChapter(2);
    s.voice.clear();
    upgradeTaken(s);
    s.stage = .s_cautery;
    s.g3.wave_t = 1000;
    const e = s.find(.vessel).?;
    // off to the side of the jet, bit within reach
    s.pos = e.pos.add(e.end.scale(e.radius + 12)).add(v3(14, 0, 0));
    lookAt(s, e.pos);
    s.arms = .{ .{ .tool = .punch }, .{ .tool = .drill } };

    var t: f32 = 0;
    while (t < 3) : (t += 1.0 / 60.0) {
        lookAt(s, e.pos);
        s.update(.{ .arm = .{ false, true } }, 1.0 / 60.0);
    }
    try std.testing.expectEqual(@as(f32, 0), e.aux);
    try std.testing.expect(s.arms[1].engaged);
    try std.testing.expect(s.g3.blood_lost > 2);

    const before = s.stability;
    s.arms[1].heat = 0;
    t = 0;
    while (t < 30 and !s.g3.sealed) : (t += 1.0 / 60.0) {
        lookAt(s, e.pos);
        // a pilot who lets the bit cool when it runs hot
        const cool = s.arms[1].overheated or (s.arms[1].heat > 0.92);
        s.update(.{ .arm = .{ true, !cool } }, 1.0 / 60.0);
    }
    try std.testing.expect(s.g3.sealed);
    try std.testing.expect(s.g3.cautery_t >= seal_time - 0.1);
    try std.testing.expect(s.stats.dual_time > 4);
    try std.testing.expect(s.stability > before);
    // once sealed there is no blood to buffer the bed
    try std.testing.expect(phAt(s, e.pos.add(e.end.scale(40))) < 2.5);
}

test "a colony keeps its pit neutral with ammonia; cleared, the mouth is acid again" {
    const gpa = std.testing.allocator;
    const s = try gpa.create(Sim);
    defer gpa.destroy(s);
    s.* = Sim.initChapter(2);
    s.stage = .s_margin;
    s.voice.clear();
    // the colony nearest the margin, where the gel alone is too thin to keep the mouth neutral
    var idx: u16 = 0;
    var thinnest: f32 = 1e9;
    for (&s.ents, 0..) |*e, i| {
        if (e.kind != .colony) continue;
        const gel = stomach.mucus(e.pos.x, e.pos.z);
        if (gel < thinnest) {
            thinnest = gel;
            idx = @intCast(i);
        }
    }
    const c = s.ents[idx].pos;
    const mouth = v3(c.x, -20, c.z);
    try std.testing.expect(stomach.ph(mouth) < stomach.safe_ph);
    try std.testing.expect(phAt(s, mouth) > 6.5);
    var sh: game.Shot = .{ .alive = true, .arm = 0 };
    for (0..9) |_| try std.testing.expect(shotHit(s, &sh, idx, c));
    try std.testing.expectEqual(game.Kind.none, s.ents[idx].kind);
    try std.testing.expectEqual(@as(u32, 1), s.g3.cleared);
    try std.testing.expect(phAt(s, mouth) < stomach.safe_ph);
    // deep in the cleared pit the gel is enough
    try std.testing.expect(phAt(s, v3(c.x, -190, c.z)) > 6);
}
