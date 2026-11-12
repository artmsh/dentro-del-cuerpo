//! Chapter 2 rules: the jejunum. Rotavirus-infected enterocytes at the villus tips, the blebs that spread
//! them, the commensal bacteria that must be left alone, a viroplasm dome, peristaltic rings, and the mucus
//! tether. The drone, arms, shots and guide queue are the shared machinery in game.zig; this file is what
//! is specific to the place.

const std = @import("std");
const m = @import("math.zig");
const game = @import("game.zig");
const gut = @import("gut.zig");
const guide = @import("guide.zig");
const i18n = @import("i18n.zig");
const strings = @import("strings.zig");
const Text = i18n.Text;
const Lang = i18n.Lang;
const L = strings.line;
const H = strings.hint;
const O = strings.objective;
const Vec3 = m.Vec3;
const v3 = m.v3;
const Sim = game.Sim;
const Stage = game.Stage;
const Entity = game.Entity;
const Topic = guide.Topic;

pub const start_z: f32 = 10300;
pub const work_z: f32 = 8300;
pub const factory_z: f32 = 6100;
pub const exit_z: f32 = 1500;
pub const tether_range: f32 = 420;
pub const scan_range: f32 = 700;
pub const wave_period: f32 = 38;

pub const Tip = struct {
    cap: Vec3 = .{},
    r: f32 = 60,
};

const Said = struct {
    stream: f32 = 0,
    crushed: bool = false,
    revealed: bool = false,
    unknown: bool = false,
    extruded: bool = false,
    in_place: bool = false,
    burst: bool = false,
    spread: bool = false,
    commensal: bool = false,
    absorb: bool = false,
    open: bool = false,
    crypt_shot: bool = false,
    tether_first: bool = false,
    tether_none: f32 = 0,
    blunt: bool = false,
    flume_push: f32 = 0,
    wave_ok: bool = false,
    bleb_attack: bool = false,
    guess: bool = false,
    half: bool = false,
};

pub const State = struct {
    tips: [12]Tip = @splat(.{}),
    ntips: usize = 0,
    cleared: u32 = 0,
    total: u32 = 0,
    spread: u32 = 0,
    bursts: u32 = 0,
    crush_hits: u32 = 0,
    commensals_lost: u32 = 0,
    extruded: u32 = 0,
    waves_survived: u32 = 0,
    wave_t: f32 = wave_period,
    ring_was_behind: bool = false,
    crush_t: f32 = 0,
    stream_t: f32 = 0,
    factory_spawn_t: f32 = 2,
    factory_dead_t: f32 = -1,
    tether_uses: u32 = 0,
    arrivals: u32 = 0,
    said: Said = .{},
};

// ---------------------------------------------------------------------------------------------- setup

fn villusNear(x: f32, z: f32) gut.Villus {
    const c = gut.cellOf(x, z);
    return gut.villusAt(c[0], c[1]);
}

fn addTip(s: *Sim, v: gut.Villus) usize {
    const g = &s.g;
    g.tips[g.ntips] = .{ .cap = v.capCentre(), .r = v.r };
    g.ntips += 1;
    return g.ntips - 1;
}

fn capDir(k: usize, seed: f32) Vec3 {
    const a = @as(f32, @floatFromInt(k)) * 2.2 + seed * 6.0;
    return v3(@sin(a) * 0.8, 0.62, @cos(a) * 0.8).norm();
}

fn addInfected(s: *Sim, tip: usize, dir: Vec3, revealed: bool) void {
    const t = s.g.tips[tip];
    _ = s.spawn(.{ .kind = .infected, .pos = t.cap.add(dir.scale(t.r + 1)), .end = dir, .radius = 9, .hp = 1, .max_hp = 1, .state = if (revealed) 1 else 0, .known = revealed, .seed = s.rng.f(), .variant = @intCast(tip) });
    s.g.total += 1;
}

fn addCommensals(s: *Sim, home: Vec3, n: usize) void {
    for (0..n) |_| {
        const off = s.rng.dir().scale(s.rng.range(8, 34));
        _ = s.spawn(.{ .kind = .commensal, .pos = home.add(off), .end = home.add(off), .radius = 3.2, .seed = s.rng.f(), .variant = @intCast(s.rng.below(3)) });
    }
}

pub fn begin(s: *Sim) void {
    s.chapter = 1;
    s.in_bore = false;
    s.stability = 66;
    s.has_sync = true;
    s.arms = .{ .{ .tool = .shoot }, .{ .tool = .punch } };

    // Arrival: out through the extrusion zone of a villus tip, facing upstream.
    const home = villusNear(0, start_z);
    s.pos = home.top().add(v3(0, 34, 0));
    s.yaw = m.pi;
    s.pitch = -0.25;
    s.warp = 1;

    // Work area: three infected villi, and their neighbours as places the virus can spread to.
    const sites = [_][2]f32{ .{ -310, work_z + 260 }, .{ 170, work_z }, .{ 520, work_z - 330 } };
    const loads = [_]usize{ 3, 3, 2 };
    for (sites, loads) |xy, n| {
        const v = villusNear(xy[0], xy[1]);
        const tip = addTip(s, v);
        for (0..n) |k| addInfected(s, tip, capDir(k, v.r), false);
    }
    const spare = [_][2]f32{ .{ -40, work_z + 300 }, .{ 420, work_z + 40 }, .{ -150, work_z - 290 }, .{ 250, work_z - 560 }, .{ -560, work_z - 60 } };
    for (spare) |xy| _ = addTip(s, villusNear(xy[0], xy[1]));

    // The factory: one tip fused into a dome.
    const fv = villusNear(0, factory_z);
    _ = s.spawn(.{ .kind = .factory, .pos = fv.top().add(v3(0, 12, 0)), .end = Vec3.up, .radius = 62, .hp = 16, .max_hp = 16, .seed = 0.37 });

    // Residents.
    addCommensals(s, villusNear(-80, work_z + 120).top().add(v3(110, -260, 40)), 6);
    addCommensals(s, villusNear(360, work_z - 200).top().add(v3(-120, -180, -60)), 5);
    addCommensals(s, fv.top().add(v3(170, -140, 150)), 6);
    addCommensals(s, villusNear(200, start_z - 700).top().add(v3(90, -300, 0)), 5);

    // Exit marker, upstream of the blunted stretch.
    _ = s.spawn(.{ .kind = .ring, .pos = v3(0, 430, exit_z), .radius = 150, .variant = 2 });

    s.setStage(.g_arrive);
}

// ---------------------------------------------------------------------------------------------- stages

pub fn enter(s: *Sim, st: Stage) void {
    switch (st) {
        .g_arrive => {
            s.say(L.and_youre_through);
            s.say(L.this_is_the_jejunum);
            s.waypoint = null;
        },
        .g_villus => {
            s.say(L.look_around_before_you_move);
            s.waypoint = null;
        },
        .g_descend => {
            s.say(L.now_feel_the_stream);
            s.say(L.go_down_all_the_way);
            const gp = gut.gapNear(s.pos.x, s.pos.z - 200);
            s.waypoint = v3(gp.x, 70, gp.z);
        },
        .g_wave => {
            s.gut.launch(@max(-1700, s.pos.z - 4400));
            s.g.ring_was_behind = false;
            s.urgent(L.contraction_ring_coming);
            s.say(L.watch_the_roof);
            s.waypoint = null;
        },
        .g_scan => {
            s.want_checkpoint = true;
            s.say(L.that_happens_every_half_minute);
            s.say(L.now_the_job);
            s.waypoint = s.g.tips[1].cap.add(v3(0, 150, 0));
            s.g.wave_t = wave_period;
        },
        .g_extrude => {
            s.say(L.there_the_swollen_ones);
            s.say(L.one_arm_on_punch_one_on_shoot);
        },
        .g_factory => {
            s.want_checkpoint = true;
            s.stabilise(8);
            s.say(L.that_villus_is_clean);
            s.waypoint = if (s.find(.factory)) |e| e.pos else null;
        },
        .g_tether => {
            s.want_checkpoint = true;
            s.say(L.upstream_the_villi_are_gone);
            s.say(L.aim_at_a_villus_within_reach);
            s.waypoint = null;
        },
        .g_flume => {
            s.say(L.good_now_go_upstream);
            s.waypoint = v3(0, 300, gut.blunt_z0 - 300);
        },
        .g_exit => {
            s.want_checkpoint = true;
            s.stabilise(6);
            s.say(L.youre_across);
            s.say(L.the_marker_takes_you_up);
            s.waypoint = v3(0, 430, exit_z);
        },
        else => {},
    }
}

pub fn upgradeTaken(s: *Sim) void {
    s.has_tether = true;
    s.mode = .playing;
    s.sound(.upgrade, 0, 1);
    s.setStage(.g_tether);
}

pub fn objective(s: *const Sim, lang: Lang, buf: []u8) []const u8 {
    const g = &s.g;
    const text: Text = switch (s.stage) {
        .g_arrive => O.g_arrive,
        .g_villus => O.g_villus,
        .g_descend => O.g_descend,
        .g_wave => O.g_wave,
        .g_scan => O.g_scan,
        .g_extrude => return i18n.format(buf, lang, O.g_extrude, .{ i18n.int(g.cleared), i18n.int(g.total), i18n.int(g.spread), i18n.int(s.count(.shed) + s.count(.virion)) }),
        .g_factory => if (s.findConst(.factory)) |e|
            return i18n.format(buf, lang, O.g_factory, .{i18n.int(@as(i32, @intFromFloat(100 * (1 - e.hp / e.max_hp))))})
        else
            O.g_factory_done,
        .g_tether => O.g_tether,
        .g_flume => O.g_flume,
        .g_exit => O.transit_marker,
        else => return "",
    };
    return text.get(lang);
}

pub fn hintText(s: *const Sim) Text {
    const lv: usize = @min(s.hint_level, 2);
    return switch (s.stage) {
        .g_villus => H.g_villus[lv],
        .g_descend => H.g_descend[lv],
        .g_wave => H.g_wave[lv],
        .g_scan => H.g_scan[lv],
        .g_extrude => H.g_extrude[lv],
        .g_factory => H.g_factory[lv],
        .g_tether => H.g_tether[lv],
        .g_flume => H.g_flume[lv],
        .g_exit => H.g_exit,
        else => H.wait,
    };
}

// ---------------------------------------------------------------------------------------------- movement

pub fn focusRay(s: *const Sim, o: Vec3, d: Vec3, max_t: f32) ?game.Focus {
    const h = s.gut.raycast(o, d, max_t) orelse return null;
    return .{ .dist = h.t, .point = h.point, .tissue = true, .topic = switch (h.what) {
        .villus => .villus,
        .tip => .villus_tip,
        .stub => .blunted_villus,
        .crypt => .crypt,
        .contraction => .contraction,
    } };
}

/// Chapter collision and the hazards tied to position: the ring crushing, the stream sweeping.
pub fn moveCollide(s: *Sim, p: Vec3, dt: f32) void {
    const g = &s.g;
    const res = s.gut.collide(p, game.hull_r);
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
            s.urgent(L.youre_on_a_tip);
        }
        if (s.hull <= 0) s.hurtDrone(1);
    }
    // Being carried by the stream.
    g.said.stream = @max(0, g.said.stream - dt);
    const fast = s.flow.z > 330 and s.tether == null and !s.latched;
    g.stream_t = if (fast) g.stream_t + dt else 0;
    if (g.stream_t > 1.3 and g.said.stream <= 0 and @intFromEnum(s.stage) >= @intFromEnum(Stage.g_descend)) {
        g.said.stream = 18;
        if (gut.blunting(s.pos.z) > 0.5) {
            s.urgent(if (s.has_tether) L.the_stream_has_you else L.nothing_to_hide_behind_here);
        } else {
            s.urgent(L.youre_in_the_stream);
        }
    }
}

/// Reeling in and holding on the tether. Returns the position before collision.
pub fn tetherMove(s: *Sim, anchor: Vec3, want: Vec3, dt: f32) Vec3 {
    const to = s.tether_hold.sub(s.pos);
    const dist = to.len();
    s.flow = s.flow.scale(@exp(-10 * dt));
    var vel = want.scale(game.cruise_speed * 0.3);
    if (dist > 1) vel = vel.add(to.scale(1 / dist).scale(@min(540, dist * 9)));
    s.vrel = vel;
    var p = s.pos.add(vel.add(s.flow).scale(dt));
    // the line does not stretch
    const leash = @max(s.pos.dist(anchor), 70);
    const off = p.sub(anchor);
    if (off.len() > leash) p = anchor.add(off.norm().scale(leash));
    return p;
}

/// What the tether would grab right now: the mucosa along the line of sight, within reach. Droplets and
/// organisms in the way do not count; the line passes through them.
pub fn tetherTarget(s: *const Sim) ?gut.RayHit {
    const h = s.gut.raycast(s.pos, s.forward(), tether_range) orelse return null;
    if (h.what == .contraction) return null;
    return h;
}

pub fn tetherKey(s: *Sim) void {
    const g = &s.g;
    if (!s.has_tether) return;
    const hit = tetherTarget(s);
    if (hit != null and (s.tether == null or hit.?.point.dist(s.tether.?) > 40)) {
        const point = hit.?.point;
        s.tether = point;
        const n = s.gut.field(point.sub(s.forward().scale(2))).n;
        s.tether_hold = point.add(n.scale(38));
        // never park on the floor itself: from there every sightline to the next hold is a grazing one
        s.tether_hold.y = @max(s.tether_hold.y, gut.floorY(s.tether_hold.x) + 44);
        g.tether_uses += 1;
        s.sound(.cut, 0, 0.9);
        s.sound(.swing, 0, 0.6);
        if (!g.said.tether_first) {
            g.said.tether_first = true;
            s.say(L.holding_feel_that);
        }
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

// ---------------------------------------------------------------------------------------------- scanning

/// T sends a pulse that resolves what the optics cannot: infected cells in the sheet, and which small
/// organisms are virus and which are hers.
pub fn scanPulse(s: *Sim) void {
    const g = &s.g;
    var cells: u32 = 0;
    var microbes: u32 = 0;
    for (&s.ents) |*e| {
        if (e.known) continue;
        if (e.kind != .infected and e.kind != .virion and e.kind != .commensal) continue;
        if (e.pos.dist(s.pos) > scan_range) continue;
        e.known = true;
        e.flash = 1;
        if (e.kind == .infected) {
            e.state = 1;
            cells += 1;
        } else microbes += 1;
    }
    if (cells > 0) {
        s.sound(.objective, 0, 0.8);
        if (!g.said.revealed) {
            g.said.revealed = true;
            if (s.stage == .g_scan) s.setStage(.g_extrude);
        } else if (s.stage == .g_extrude) {
            s.voice.say(L.more_of_them_same_again, .chatter);
        }
    }
    if (microbes > 0 and !g.said.unknown) {
        g.said.unknown = true;
        s.atlas[@intFromEnum(Topic.unknown_microbe)] = true;
        s.say(L.resolved_green_rods_are_hers);
    }
}

pub fn onIdentify(s: *Sim, tp: Topic) void {
    switch (tp) {
        .villus, .villus_tip => if (s.stage == .g_villus) {
            s.setStage(.g_descend);
        },
        .crypt => if (s.stage == .g_descend or s.stage == .g_wave) s.voice.say(L.the_safest_place_in_the_gut, .chatter),
        else => {},
    }
}

// ---------------------------------------------------------------------------------------------- organisms

fn spawnVirion(s: *Sim, at: Vec3, vel: Vec3, known: bool) void {
    _ = s.spawn(.{ .kind = .virion, .pos = at, .vel = vel, .radius = 3, .hp = 1, .seed = s.rng.f(), .variant = @intCast(s.rng.below(3)), .known = known, .timer = 0.9 });
}

fn killVirion(s: *Sim, idx: u16) void {
    const e = &s.ents[idx];
    s.burst(e.pos, 9, 80, .{ 1, 0.35, 0.8, 1 }, 2.2, 0.5);
    e.kind = .none;
    s.stats.kills += 1;
    s.sound(.kill, 0, 0.6);
}

/// An infected cell ruptured where it sat, or a shed one burst on its own.
fn rupture(s: *Sim, idx: u16, n: usize, in_place: bool) void {
    const g = &s.g;
    const e = &s.ents[idx];
    const out = if (in_place) e.end else Vec3.up;
    s.burst(e.pos, 22, 110, .{ 1, 0.3, 0.75, 1 }, 3.2, 0.8);
    for (0..n) |_| spawnVirion(s, e.pos.add(out.scale(10)), out.scale(50).add(s.rng.dir().scale(60)), true);
    e.kind = .none;
    g.cleared += 1;
    g.bursts += 1;
    s.sound(.escape, 0, 0.8);
    if (in_place) {
        s.tissueDamage(2, true);
        if (!g.said.in_place) {
            g.said.in_place = true;
            s.urgent(L.not_in_the_sheet);
        }
    } else if (!g.said.burst) {
        g.said.burst = true;
        s.say(L.that_one_burst);
    }
}

fn killCommensal(s: *Sim, idx: u16) void {
    const g = &s.g;
    const e = &s.ents[idx];
    s.burst(e.pos, 8, 50, .{ 0.5, 1, 0.6, 1 }, 2.2, 0.5);
    e.kind = .none;
    g.commensals_lost += 1;
    s.stats.friendly_fire += 1;
    s.stabilise(-2);
    s.sound(.tissue, 0, 0.8);
    if (!g.said.commensal) {
        g.said.commensal = true;
        s.urgent(L.those_were_hers);
    }
}

fn killFactory(s: *Sim, idx: u16) void {
    const g = &s.g;
    const e = &s.ents[idx];
    s.burst(e.pos, 80, 220, .{ 1, 0.5, 0.85, 1 }, 5, 1.2);
    e.kind = .none;
    g.factory_dead_t = 0;
    s.stabilise(10);
    s.shake = @max(s.shake, 0.8);
    s.sound(.nest_die, 0, 1);
    s.voice.clear();
    s.say(L.domes_gone);
}

pub fn punched(s: *Sim, idx: u16, dir: Vec3) void {
    const g = &s.g;
    const e = &s.ents[idx];
    switch (e.kind) {
        .infected => {
            // extrusion: the neighbours squeeze it out and close underneath
            const n = e.end;
            e.kind = .shed;
            e.pos = e.pos.add(n.scale(16));
            e.vel = n.scale(75).add(dir.scale(25));
            e.timer = 7.5;
            e.radius = 8;
            e.hp = 2;
            e.flash = 1;
            g.extruded += 1;
            s.burst(e.pos, 10, 60, .{ 1, 0.8, 0.9, 1 }, 2.5, 0.5);
            s.sound(.cut, 0, 0.9);
            if (!g.said.extruded) {
                g.said.extruded = true;
                s.say(L.out_and_the_sheet_has_closed);
            }
        },
        .shed => e.vel = e.vel.add(dir.scale(150)),
        .virion => killVirion(s, idx),
        .commensal => {
            e.vel = dir.scale(120);
            e.timer = 1.5;
        },
        .factory => e.flash = 0.5,
        else => {},
    }
}

/// Returns true when the round is spent.
pub fn shotHit(s: *Sim, sh: *game.Shot, idx: u16, at: Vec3) bool {
    const g = &s.g;
    const e = &s.ents[idx];
    const dmg: f32 = if (sh.lance) 3 else 1;
    const arm = &s.arms[sh.arm];
    switch (e.kind) {
        .infected => {
            rupture(s, idx, 2, true);
            return true;
        },
        .shed => {
            e.hp -= dmg;
            e.flash = 1;
            arm.flash = 1;
            s.burst(at, 5, 50, .{ 0.5, 1, 0.9, 1 }, 2.5, 0.5);
            if (e.hp <= 0) {
                s.burst(e.pos, 18, 80, .{ 0.5, 1, 0.9, 1 }, 3, 0.8);
                e.kind = .none;
                g.cleared += 1;
                s.stats.kills += 1;
                s.stabilise(1.5);
                s.sound(.kill, 0, 0.8);
                if (!g.said.half and g.cleared * 2 >= g.total) {
                    g.said.half = true;
                    s.voice.say(L.half_of_them, .chatter);
                }
            }
            return !sh.lance;
        },
        .virion => {
            killVirion(s, idx);
            arm.flash = 1;
            return !sh.lance;
        },
        .commensal => {
            killCommensal(s, idx);
            return true;
        },
        .factory => {
            if (e.aux > 0.5) {
                e.hp -= dmg;
                e.flash = 1;
                arm.flash = 1;
                s.burst(at, 6, 80, .{ 1, 0.5, 0.85, 1 }, 2.5, 0.4);
                s.sound(.punch_hit, 0, 0.5);
                if (e.hp <= 0) killFactory(s, idx);
            } else {
                s.burst(at, 3, 30, .{ 0.7, 0.7, 0.5, 1 }, 3, 0.5);
                s.sound(.absorb, 0, 0.7);
                if (!g.said.absorb) {
                    g.said.absorb = true;
                    s.say(L.mucus_it_soaks_up_rounds);
                }
            }
            return true;
        },
        else => return false,
    }
}

/// Returns true while the bit is cutting.
pub fn drilled(s: *Sim, idx: u16, point: Vec3, rate: f32, dt: f32, spark: bool) bool {
    const g = &s.g;
    const e = &s.ents[idx];
    switch (e.kind) {
        .infected => {
            rupture(s, idx, 3, true);
            return true;
        },
        .shed => {
            rupture(s, idx, 1, false);
            return true;
        },
        .virion => {
            killVirion(s, idx);
            return true;
        },
        .commensal => {
            killCommensal(s, idx);
            return true;
        },
        .factory => {
            e.aux = @min(1, e.aux + 1.3 * rate * dt);
            e.timer = 0.25;
            s.latched = true;
            if (spark) s.burst(point, 2, 50, .{ 1, 0.7, 0.9, 1 }, 2.5, 0.4);
            if (e.aux > 0.6 and !g.said.open) {
                g.said.open = true;
                s.urgent(L.its_open_fire_into_it);
            }
            return true;
        },
        else => return false,
    }
}

/// A round reached the mucosa.
pub fn shotTissue(s: *Sim, h: gut.RayHit) void {
    const g = &s.g;
    s.burst(h.point, 6, 50, .{ 1, 0.4, 0.3, 1 }, 3, 0.5);
    if (h.what == .crypt) {
        s.tissueDamage(3, true);
        if (!g.said.crypt_shot) {
            g.said.crypt_shot = true;
            s.urgent(L.not_the_crypts);
        }
    } else {
        s.tissueDamage(1.5, true);
        if (h.what == .tip and !g.said.guess and s.stage == .g_extrude) {
            g.said.guess = true;
            s.say(L.dont_guess_at_tips);
        }
    }
}

fn nearestTip(s: *const Sim, p: Vec3) ?usize {
    var best: f32 = 1e12;
    var out: ?usize = null;
    for (s.g.tips[0..s.g.ntips], 0..) |t, i| {
        const d = t.cap.dist(p);
        if (d < best) {
            best = d;
            out = i;
        }
    }
    return out;
}

fn updateVirion(s: *Sim, idx: u16, dt: f32) void {
    const g = &s.g;
    const e = &s.ents[idx];
    e.timer -= dt;
    const to_drone = s.pos.sub(e.pos);
    const dd = to_drone.len();
    switch (e.state) {
        0 => {
            // seek: the drone if it is close, otherwise the nearest tip
            var target = e.pos;
            var speed: f32 = 70;
            var at_tip: ?usize = null;
            if (dd < 240) {
                target = s.pos;
                speed = 95;
                if (dd < 75 and e.timer <= 0) {
                    e.state = 1;
                    e.timer = 0.65;
                    e.aux = 0;
                    s.sound(.windup, m.clamp(to_drone.dot(s.right()) / -60, -1, 1), 0.8);
                    if (!g.said.bleb_attack) {
                        g.said.bleb_attack = true;
                        s.voice.say(L.it_flares_before_it_darts, .chatter);
                    }
                }
            } else if (nearestTip(s, e.pos)) |ti| {
                const t = g.tips[ti];
                target = t.cap.add(v3(0, t.r, 0));
                at_tip = ti;
            }
            const want = target.sub(e.pos).norm().scale(speed).add(s.gut.flowAt(e.pos, s.clock).scale(0.35));
            e.vel = e.vel.add(want.sub(e.vel).scale(1 - @exp(-3 * dt)));
            e.pos = s.gut.collide(e.pos.add(e.vel.scale(dt)), e.radius).pos;
            if (at_tip) |ti| {
                const t = g.tips[ti];
                if (e.pos.dist(t.cap) < t.r + 12 and e.pos.y > t.cap.y) {
                    // it found a mature cell
                    const dir = e.pos.sub(t.cap).norm();
                    e.kind = .none;
                    addInfected(s, ti, dir, false);
                    g.spread += 1;
                    s.stabilise(-3);
                    s.sound(.escape, 0, 0.7);
                    if (!g.said.spread) {
                        g.said.spread = true;
                        s.say(L.a_bleb_reached_a_clean_tip);
                    }
                }
            }
        },
        1 => {
            e.aux = m.sat(1 - e.timer / 0.65);
            e.vel = e.vel.scale(@exp(-6 * dt));
            e.pos = e.pos.add(e.vel.scale(dt));
            if (e.timer <= 0) {
                e.state = 2;
                e.timer = 0.42;
                e.vel = to_drone.scale(1 / @max(dd, 1e-3)).scale(430);
            }
        },
        2 => {
            e.pos = e.pos.add(e.vel.scale(dt));
            if (dd < game.hull_r + e.radius + 2) {
                s.burst(e.pos, 10, 90, .{ 1, 0.35, 0.8, 1 }, 2.4, 0.5);
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
        else => e.state = 0,
    }
}

pub fn updateEntity(s: *Sim, idx: u16, dt: f32) void {
    const g = &s.g;
    const e = &s.ents[idx];
    switch (e.kind) {
        .infected => {},
        .shed => {
            const fl = s.gut.flowAt(e.pos, s.clock);
            e.vel = e.vel.add(fl.scale(0.6).add(v3(0, 6, 0)).sub(e.vel).scale(1 - @exp(-1.2 * dt)));
            e.pos = s.gut.collide(e.pos.add(e.vel.scale(dt)), e.radius).pos;
            e.timer -= dt;
            if (e.timer <= 0) {
                rupture(s, idx, 3, false);
            } else if (e.pos.z > s.pos.z + 3200) {
                // carried off downstream: it will burst somewhere we are not
                e.kind = .none;
                g.cleared += 1;
                g.spread += 1;
                s.stabilise(-3);
                s.sound(.escape, 0, 0.7);
            }
        },
        .virion => updateVirion(s, idx, dt),
        .commensal => {
            if (e.timer > 0) {
                e.timer -= dt;
                e.pos = e.pos.add(e.vel.scale(dt));
                e.vel = e.vel.scale(@exp(-2.5 * dt));
                if (e.timer <= 0) e.end = e.pos;
            } else {
                const t = s.clock * (0.4 + 0.5 * e.seed) + e.seed * 40;
                e.pos = e.end.add(v3(@sin(t) * 7, @sin(t * 0.7 + 1) * 5, @cos(t * 1.1) * 7));
            }
        },
        .factory => {
            e.timer -= dt;
            if (e.timer <= 0) e.aux = @max(0, e.aux - 1.6 * dt);
            if (s.stage == .g_factory and s.pos.dist(e.pos) < 620) {
                g.factory_spawn_t -= dt;
                if (g.factory_spawn_t <= 0 and s.count(.virion) < 5) {
                    g.factory_spawn_t = 3.3;
                    const d = s.pos.sub(e.pos).norm().add(s.rng.dir().scale(0.7)).add(v3(0, 0.5, 0)).norm();
                    spawnVirion(s, e.pos.add(d.scale(e.radius + 5)), d.scale(60), true);
                }
            }
        },
        else => {},
    }
}

// ---------------------------------------------------------------------------------------------- script

fn waveClock(s: *Sim, dt: f32) void {
    const g = &s.g;
    g.said.tether_none = @max(0, g.said.tether_none - dt);
    // survived: the ring's trailing edge has gone past the drone
    if (s.gut.ring_z) |rz| {
        const behind = rz < s.pos.z;
        if (g.ring_was_behind and !behind and rz > s.pos.z + gut.ring_half * 0.9) {
            g.ring_was_behind = false;
            g.waves_survived += 1;
            if (s.stage == .g_extrude and g.arrivals < 3) arrivals(s);
        }
        if (behind) g.ring_was_behind = true;
    }
    if (@intFromEnum(s.stage) < @intFromEnum(Stage.g_scan) or s.stage == .g_exit) return;
    g.wave_t -= dt;
    if (g.wave_t <= 0 and s.gut.ring_z == null) {
        g.wave_t = wave_period;
        s.gut.launch(@max(-1700, s.pos.z - 4400));
        g.ring_was_behind = false;
        s.urgent(if (s.tether != null) L.ring_coming_stay_on_the_line else L.ring_coming_get_down);
        s.sound(.transit, 0, 0.5);
    }
}

/// What the ring washes in: a mixed handful that only the scan can sort.
fn arrivals(s: *Sim) void {
    const g = &s.g;
    g.arrivals += 1;
    const base = s.pos.add(v3(s.rng.range(-160, 160), 0, -260));
    const y = 560 + s.rng.range(0, 160);
    addCommensals(s, v3(base.x - 60, y, base.z), 3);
    for (0..2) |_| spawnVirion(s, v3(base.x + 70 + s.rng.range(-20, 20), y + s.rng.range(-20, 20), base.z + s.rng.range(-20, 20)), .{}, false);
    s.voice.say(L.the_ring_washed_something_in, .chatter);
}

/// Seconds until the leading edge of the ring reaches the drone, if one is on its way.
pub fn ringEta(s: *const Sim) ?f32 {
    const rz = s.gut.ring_z orelse return null;
    const lead = rz + gut.ring_half;
    if (lead >= s.pos.z) return 0;
    return (s.pos.z - lead) / gut.ring_speed;
}

/// True while the lumen above the drone is closed down.
pub fn underRing(s: *const Sim) bool {
    return s.gut.squeeze(s.pos.z) > 0.02;
}

pub fn script(s: *Sim, dt: f32) void {
    const g = &s.g;
    waveClock(s, dt);
    if (s.stall_t > 55 and !s.said.stall) {
        s.said.stall = true;
        s.voice.say(L.if_you_want_a_pointer, .chatter);
    }
    const h = s.pos.y - gut.floorY(s.pos.x);
    switch (s.stage) {
        .g_arrive => if (s.stage_t > 6.5) s.setStage(.g_villus),
        .g_villus => {},
        .g_descend => if (h < 230) s.setStage(.g_wave),
        .g_wave => {
            const passed = if (s.gut.ring_z) |rz| rz > s.pos.z + gut.ring_half else true;
            if (passed and s.stage_t > 3) {
                if (!g.said.wave_ok and g.crush_hits == 0) {
                    g.said.wave_ok = true;
                    s.say(L.it_has_gone_over_you);
                }
                s.setStage(.g_scan);
            }
        },
        .g_scan => {},
        .g_extrude => {
            const left = s.count(.infected) + s.count(.shed);
            if (left == 0 and s.count(.virion) == 0 and s.stage_t > 2) {
                s.setStage(.g_factory);
                return;
            }
            // point at the nearest thing to deal with; a hidden cell gets a marker above its tip
            var best: f32 = 1e12;
            s.waypoint = null;
            for (&s.ents) |*e| {
                if (e.kind != .infected and e.kind != .shed) continue;
                const p = if (e.kind == .infected and e.state == 0) g.tips[e.variant].cap.add(v3(0, 150, 0)) else e.pos;
                const d = p.dist(s.pos) + (if (e.kind == .shed) @as(f32, -400) else 0);
                if (d < best) {
                    best = d;
                    s.waypoint = p;
                }
            }
        },
        .g_factory => {
            if (s.find(.factory)) |e| {
                s.waypoint = e.pos;
            } else {
                s.waypoint = null;
                g.factory_dead_t += dt;
                if ((g.factory_dead_t > 3 and s.count(.virion) == 0) or g.factory_dead_t > 12) s.mode = .upgrade_card;
            }
        },
        .g_tether => if (g.tether_uses >= 2 and s.stage_t > 3) s.setStage(.g_flume),
        .g_flume => {
            if (!g.said.blunt and s.pos.z < gut.blunt_z1 + 500) {
                g.said.blunt = true;
                s.say(L.here_the_virus_killed_the_tips);
            }
            if (s.pos.z < gut.blunt_z0 - 250) s.setStage(.g_exit);
        },
        .g_exit => if (s.atRing(2)) {
            s.say(L.lines_on);
            s.setStage(.done);
        },
        else => {},
    }
}

pub fn gradePenalty(s: *const Sim) f32 {
    const g = &s.g;
    return @as(f32, @floatFromInt(g.spread)) * 3 + @as(f32, @floatFromInt(g.bursts)) * 1.5;
}

/// Centimetres to the duodenojejunal flexure, for the HUD.
pub fn locationCm(s: *const Sim) f32 {
    return 11.0 + s.pos.z / 10000.0;
}

// ---------------------------------------------------------------------------------------------- tests

fn settle(s: *Sim, c: game.Controls, seconds: f32) void {
    const dt: f32 = 1.0 / 60.0;
    var t: f32 = 0;
    while (t < seconds) : (t += dt) s.update(c, dt);
}

test "the blunted stretch cannot be flown upstream, and the tether holds in it" {
    const gpa = std.testing.allocator;
    const s = try gpa.create(Sim);
    defer gpa.destroy(s);
    s.* = Sim.initChapter(1);
    s.stage = .g_flume;
    s.voice.clear();
    const z0 = (gut.blunt_z0 + gut.blunt_z1) / 2;
    const gp = gut.gapNear(0, z0);
    s.pos = v3(gp.x, 40, gp.z);
    s.yaw = m.pi;
    s.pitch = 0;
    const start = s.pos.z;
    // full boost upstream, hugging the floor
    settle(s, .{ .move = v3(0, 0, 1), .boost = true }, 6);
    try std.testing.expect(s.pos.z > start - 20);

    // with the line on the floor ahead, the drone stays put with no thrust at all
    s.has_tether = true;
    s.pos = v3(gp.x, 60, gp.z);
    s.pitch = -0.5;
    settle(s, .{}, 0.05);
    try std.testing.expect(tetherTarget(s) != null);
    settle(s, .{ .tether = true }, 1.0 / 60.0);
    try std.testing.expect(s.tether != null);
    settle(s, .{}, 4);
    try std.testing.expect(s.pos.dist(s.tether_hold) < 6);
    const held = s.pos;
    settle(s, .{}, 4);
    try std.testing.expect(s.pos.dist(held) < 2);
}

test "an infected cell is invisible until scanned, then punched out and shot" {
    const gpa = std.testing.allocator;
    const s = try gpa.create(Sim);
    defer gpa.destroy(s);
    s.* = Sim.initChapter(1);
    s.stage = .g_extrude;
    s.voice.clear();
    s.arms = .{ .{ .tool = .shoot }, .{ .tool = .punch } };
    var idx: usize = 0;
    for (&s.ents, 0..) |*e, i| {
        if (e.kind == .infected) {
            idx = i;
            break;
        }
    }
    const cell = s.ents[idx];
    // hover off the cell, looking at it
    s.pos = cell.pos.add(cell.end.scale(20));
    const d = cell.pos.sub(s.pos).norm();
    s.yaw = std.math.atan2(d.x, d.z);
    s.pitch = std.math.asin(d.y);
    settle(s, .{}, 0.05);
    // unscanned: the reticle reads the tip, and a punch lands on healthy tissue
    try std.testing.expect(s.focus.ent == null);
    try std.testing.expect(s.focus.tissue);
    const before = s.stability;
    settle(s, .{ .arm = .{ false, true } }, 0.3);
    try std.testing.expect(s.stability < before);
    try std.testing.expectEqual(@as(u32, 0), s.g.extruded);

    // scan resolves it; the same punch now extrudes it
    settle(s, .{}, 0.6);
    settle(s, .{ .examine = true }, 1.0 / 60.0);
    try std.testing.expect(s.ents[idx].known and s.ents[idx].state == 1);
    settle(s, .{}, 0.3);
    settle(s, .{ .arm = .{ false, true } }, 0.3);
    try std.testing.expectEqual(game.Kind.shed, s.ents[idx].kind);
    try std.testing.expectEqual(@as(u32, 1), s.g.extruded);

    // two rounds clear it
    const cleared = s.g.cleared;
    var t: f32 = 0;
    while (t < 3 and s.ents[idx].kind == .shed) : (t += 1.0 / 60.0) {
        const to = s.ents[idx].pos.sub(s.pos).norm();
        s.yaw = std.math.atan2(to.x, to.z);
        s.pitch = std.math.asin(to.y);
        s.update(.{ .arm = .{ true, false } }, 1.0 / 60.0);
    }
    try std.testing.expectEqual(cleared + 1, s.g.cleared);
    try std.testing.expectEqual(@as(u32, 0), s.g.bursts);
}

test "a shed cell left alone bursts into blebs; killing a commensal costs the patient" {
    const gpa = std.testing.allocator;
    const s = try gpa.create(Sim);
    defer gpa.destroy(s);
    s.* = Sim.initChapter(1);
    s.stage = .g_extrude;
    s.voice.clear();
    s.pos = v3(0, 400, 9500);
    const at = v3(0, 420, 9300);
    const i = s.spawn(.{ .kind = .shed, .pos = at, .radius = 8, .hp = 2, .timer = 1.0, .known = true }).?;
    s.g.total += 1;
    const virions = s.count(.virion);
    settle(s, .{}, 1.2);
    try std.testing.expect(s.ents[i].kind != .shed);
    try std.testing.expectEqual(virions + 3, s.count(.virion));
    try std.testing.expectEqual(@as(u32, 1), s.g.bursts);

    var ci: u16 = 0;
    for (&s.ents, 0..) |*e, k| {
        if (e.kind == .commensal) {
            ci = @intCast(k);
            break;
        }
    }
    const before = s.stability;
    var sh: game.Shot = .{ .alive = true, .arm = 0 };
    try std.testing.expect(shotHit(s, &sh, ci, s.ents[ci].pos));
    try std.testing.expectEqual(@as(u32, 1), s.g.commensals_lost);
    try std.testing.expect(s.stability < before);
}
