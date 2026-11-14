//! Chapter 1 simulation. Pure state and rules: no rendering, no platform calls, so the whole chapter can be
//! played headless by the scripted pilot in bot.zig.

const std = @import("std");
const m = @import("math.zig");
const mesh = @import("mesh.zig");
const vein_mod = @import("vein.zig");
const guide = @import("guide.zig");
const gut_mod = @import("gut.zig");
const ch2 = @import("ch2.zig");
const stomach_mod = @import("stomach.zig");
const ch3 = @import("ch3.zig");
const i18n = @import("i18n.zig");
const bindings = @import("bindings.zig");
const strings = @import("strings.zig");
const Text = i18n.Text;
const Lang = i18n.Lang;
const L = strings.line;
const H = strings.hint;
const O = strings.objective;
const Vec3 = m.Vec3;
const v3 = m.v3;
const Vein = vein_mod.Vein;
const Topic = guide.Topic;

pub const hull_r: f32 = 4;
pub const cruise_speed: f32 = 260;
pub const boost_speed: f32 = 650;
pub const drill_reach: f32 = 24;
pub const punch_reach: f32 = 28;
pub const punch_delay: f32 = 0.12;
pub const sync_window: f32 = 0.12;
/// What a Sync Strike is worth. Two punches landing as one do this many times the damage of a single
/// punch to something brittle; two rounds merged into a lance do the damage of this many rounds. The
/// upgrade card and Marín's line quote both figures, and a test holds the words to these numbers.
pub const sync_punch_factor: f32 = 10;
pub const lance_factor: f32 = 3;
pub const clot_radius: f32 = 340;

pub const Tool = enum(u8) {
    punch,
    drill,
    shoot,

    pub fn name(t: Tool) Text {
        return switch (t) {
            .punch => strings.tool.punch,
            .drill => strings.tool.drill,
            .shoot => strings.tool.shoot,
        };
    }
    pub fn next(t: Tool) Tool {
        return @enumFromInt((@intFromEnum(t) + 1) % 3);
    }
};

pub const Controls = struct {
    /// x right, y up, z forward; each in [-1, 1].
    move: Vec3 = .{},
    /// Yaw (positive turns right) and pitch (positive looks up) deltas in radians.
    look: [2]f32 = .{ 0, 0 },
    boost: bool = false,
    arm: [2]bool = .{ false, false },
    cycle: [2]bool = .{ false, false },
    select: [2]?Tool = .{ null, null },
    examine: bool = false,
    hint: bool = false,
    confirm: bool = false,
    skip: bool = false,
    /// Chapter 2 upgrade, carried from then on: fire or release the mucus tether.
    tether: bool = false,
};

pub const Arm = struct {
    tool: Tool,
    cooldown: f32 = 0,
    heat: f32 = 0,
    overheated: bool = false,
    charge: f32 = 1,
    /// Seconds since the punch was triggered, or -1 when idle.
    punch_t: f32 = -1,
    struck: bool = false,
    punch_clock: f32 = -10,
    shot_clock: f32 = -10,
    shot_idx: u16 = 0,
    /// Drill is biting something this frame.
    engaged: bool = false,
    /// What the bit is locked into. Once it bites it stays in while the key is held, so the pilot can
    /// look elsewhere and work the other arm.
    latch: ?DrillTarget = null,
    held: bool = false,
    // presentation
    ext: f32 = 0,
    recoil: f32 = 0,
    swap: f32 = 0,
    spin: f32 = 0,
    flash: f32 = 0,
};

pub const DrillTarget = struct {
    ent: ?u16 = null,
    kind: Kind = .none,
    point: Vec3 = .{},
    tissue: bool = false,
    cannula: bool = false,
};

pub const Kind = enum(u8) { none, cocci, nest, anchor, embolus, neutrophil, odd_cell, thrombus, phlebolith, ring, infected, shed, virion, commensal, factory, pylori, colony, vessel, grit };

pub const Entity = struct {
    kind: Kind = .none,
    pos: Vec3 = .{},
    vel: Vec3 = .{},
    /// Anchors: far end. Nests: outward normal. Neutrophils: (theta, z, speed).
    end: Vec3 = .{},
    radius: f32 = 1,
    hp: f32 = 1,
    max_hp: f32 = 1,
    /// Cocci: 0 drift, 1 wind-up, 2 lunge, 3 recover.
    state: u8 = 0,
    timer: f32 = 0,
    /// Nests: how far the drill has opened the slime (0..1).
    aux: f32 = 0,
    seed: f32 = 0,
    flash: f32 = 0,
    variant: u8 = 0,
    /// Chapter 2: the scan has resolved what this is.
    known: bool = false,
    sides: vein_mod.Sides = .{},
};

pub const Shot = struct {
    alive: bool = false,
    pos: Vec3 = .{},
    vel: Vec3 = .{},
    life: f32 = 0,
    arm: u8 = 0,
    lance: bool = false,
};

pub const Particle = struct {
    life: f32 = 0,
    max_life: f32 = 1,
    pos: Vec3 = .{},
    vel: Vec3 = .{},
    size: f32 = 1,
    color: [4]f32 = .{ 1, 1, 1, 1 },
    drag: f32 = 2,
};

pub const Sfx = enum(u8) { shoot, lance, swing, punch_hit, sync, kill, nest_die, hurt, tissue, scan, objective, checkpoint, upgrade, cut, shatter, escape, absorb, overheat, windup, transit, ui, bump, acid, sizzle };

pub const SfxEvent = struct { id: Sfx, pan: f32 = 0, gain: f32 = 1 };

pub const Stage = enum(u8) {
    needle,
    flow_wall,
    flow_core,
    to_valve1,
    valve1_identify,
    valve1_pass,
    neutrophil,
    staph,
    tools,
    transit1,
    v2_approach,
    treat,
    lyse_core,
    freed,
    to_ring2,
    transit2,
    septum_find,
    septum_break,
    exit,
    // chapter 2
    g_arrive,
    g_villus,
    g_descend,
    g_wave,
    g_scan,
    g_extrude,
    g_factory,
    g_tether,
    g_flume,
    g_exit,
    // chapter 3
    s_arrive,
    s_pits,
    s_gradient,
    s_wave,
    s_swim,
    s_margin,
    s_cross,
    s_cautery,
    s_exit,
    done,

    /// Index of the chapter whose script owns this stage; `done` belongs to all of them.
    pub fn chapter(st: Stage) ?u8 {
        if (st == .done) return null;
        const i = @intFromEnum(st);
        if (i >= @intFromEnum(Stage.s_arrive)) return 2;
        if (i >= @intFromEnum(Stage.g_arrive)) return 1;
        return 0;
    }
};

pub const Mode = enum(u8) { playing, transit, upgrade_card, dead, lost, complete };

pub const Focus = struct {
    topic: ?Topic = null,
    ent: ?u16 = null,
    dist: f32 = 0,
    point: Vec3 = .{},
    /// Living tissue of the patient (wall, cusp, web).
    tissue: bool = false,
};

pub const Stats = struct {
    time: f32 = 0,
    tissue_hits: u32 = 0,
    friendly_fire: u32 = 0,
    emboli_escaped: u32 = 0,
    emboli_lysed: u32 = 0,
    kills: u32 = 0,
    retries: u32 = 0,
    sync_strikes: u32 = 0,
    hints: u32 = 0,
    dual_time: f32 = 0,
};

const Said = struct {
    exit_bore: bool = false,
    wall_hit: bool = false,
    friendly: bool = false,
    absorb: bool = false,
    nest_open: bool = false,
    nest_dead: bool = false,
    embolus: bool = false,
    escaped: bool = false,
    overheat: bool = false,
    drill_clot: bool = false,
    reflux: bool = false,
    windup: bool = false,
    sinus: bool = false,
    regrow: bool = false,
    stone_colony: bool = false,
    single_punch: bool = false,
    punch_clot: bool = false,
    odd_hint: bool = false,
    stall: bool = false,
    core_half: bool = false,
    sync_try: bool = false,
    needle_drill: bool = false,
};

pub const max_ents = 220;
pub const max_shots = 64;
pub const max_parts = 700;

pub const Sim = struct {
    clock: f32 = 0,
    mode: Mode = .playing,
    stage: Stage = .needle,
    stage_t: f32 = 0,
    stall_t: f32 = 0,
    vein: Vein = .{},
    /// 0 vein, 1 jejunum, 2 stomach.
    chapter: u8 = 0,
    gut: gut_mod.Gut = .{},
    g: ch2.State = .{},
    sto: stomach_mod.Stomach = .{},
    g3: ch3.State = .{},
    has_tether: bool = false,
    tether: ?Vec3 = null,
    /// Where the line holds the drone: a little off the surface, so there is a sightline to the next hold.
    tether_hold: Vec3 = .{},

    pos: Vec3 = .{},
    vrel: Vec3 = .{},
    flow: Vec3 = .{},
    yaw: f32 = 0,
    pitch: f32 = 0,
    hull: f32 = 100,
    stability: f32 = 62,
    sides: vein_mod.Sides = .{},
    in_bore: bool = true,
    latched: bool = false,
    arms: [2]Arm = .{ .{ .tool = .shoot }, .{ .tool = .punch } },
    has_sync: bool = false,

    ents: [max_ents]Entity = @splat(.{}),
    shots: [max_shots]Shot = @splat(.{}),
    parts: [max_parts]Particle = @splat(.{}),
    part_cursor: usize = 0,

    atlas: [Topic.count]bool = @splat(false),
    atlas_deep: [Topic.count]bool = @splat(false),
    focus: Focus = .{},
    /// Decorative cell under the reticle, supplied by the presentation layer (which owns those cells).
    ambient_focus: ?Focus = null,
    examine_cd: f32 = 0,
    voice: guide.Voice = .{},
    hint_level: u8 = 0,
    said: Said = .{},
    waypoint: ?Vec3 = null,
    odd_found: u8 = 0,
    hidden_unlocked: bool = false,

    stats: Stats = .{},
    want_checkpoint: bool = false,
    checkpoint_toast: f32 = 0,

    transit_t: f32 = 0,
    transit_from: Vec3 = .{},
    transit_to_z: f32 = 0,
    transit_look: [2]f32 = .{ 0, 0 },
    station: u8 = 0,
    windup_lock: f32 = 0,
    nest_spawn_t: f32 = 3,
    stone_spawn_t: f32 = 2,
    clot_shed_t: f32 = 0,
    freed_t: f32 = 0,

    // presentation feedback
    shake: f32 = 0,
    hurt: f32 = 0,
    heal: f32 = 0,
    tissue_flash: f32 = 0,
    sync_flash: f32 = 0,
    scan_r: f32 = -1,
    warp: f32 = 0,
    sfx: [32]SfxEvent = undefined,
    nsfx: usize = 0,
    rng: m.Rng = m.Rng.init(7),

    // ------------------------------------------------------------------ setup

    pub fn init() Sim {
        var s: Sim = .{};
        const n = &s.vein.needle;
        s.pos = n.at(-2300);
        s.yaw = 0;
        s.pitch = std.math.asin(n.dir.y);
        s.spawnWorld();
        s.setStage(.needle);
        return s;
    }

    pub fn initChapter(chapter: u8) Sim {
        var s: Sim = .{};
        switch (chapter) {
            1 => ch2.begin(&s),
            2 => ch3.begin(&s),
            else => return init(),
        }
        return s;
    }

    pub const ring1_z: f32 = 9300;
    pub const ring2_z: f32 = 17900;
    pub const station_b_z: f32 = 12600;
    pub const station_c_z: f32 = 20300;

    fn spawnWorld(s: *Sim) void {
        const vn = &s.vein;
        // Transit markers.
        _ = s.spawn(.{ .kind = .ring, .pos = Vein.center(ring1_z), .radius = 170, .variant = 0 });
        _ = s.spawn(.{ .kind = .ring, .pos = Vein.center(ring2_z).add(v3(0, -500, 0)), .radius = 170, .variant = 1 });

        // Neutrophils rolling on the wall: a few in station A, thick around the infected valve.
        for (0..16) |_| s.spawnNeutrophil(s.rng.range(6300, 9100), s.rng.range(0, m.tau));
        for (0..30) |_| {
            // biased toward the pinned cusp's side of the wall
            const th = m.pi / 2.0 + s.rng.range(-1.5, 1.5) * s.rng.f();
            s.spawnNeutrophil(s.rng.range(13400, 17000), th);
        }

        // The three cells that should not be in peripheral blood (hidden-chapter clue).
        {
            const v0 = &vn.valves[0];
            const z0 = v0.zb + 1350;
            const c0 = Vein.center(z0);
            const ys = vn.cuspY(0, 1, 250, z0) orelse 900;
            _ = s.spawn(.{ .kind = .odd_cell, .pos = c0.add(v3(250, -(ys + 260), 0)), .radius = 4.6, .variant = 0, .seed = 0.3 });
            const z1: f32 = 7700;
            const c1 = Vein.center(z1);
            const th: f32 = 3.6;
            const r1 = vn.wallR(z1, th) - 22;
            _ = s.spawn(.{ .kind = .odd_cell, .pos = c1.add(v3(r1 * @cos(th), r1 * @sin(th), 0)), .radius = 6.8, .variant = 1, .seed = 0.6 });
            const v1 = &vn.valves[1];
            const z2 = v1.zb + 1250;
            const c2 = Vein.center(z2);
            const ys2 = vn.cuspY(1, 1, -300, z2) orelse 900;
            _ = s.spawn(.{ .kind = .odd_cell, .pos = c2.add(v3(-300, -(ys2 + 300), 0)), .radius = 4.8, .variant = 2, .seed = 0.9 });
        }

        // Septic thrombus in the pocket behind the pinned cusp of valve 2.
        const v = &vn.valves[1];
        const cz = v.zb + 0.62 * v.len;
        const ctr = Vein.center(cz);
        const ys = vn.cuspY(1, 0, 0, cz) orelse 500;
        const rw = vn.wallR(cz, m.pi / 2.0);
        const clot = ctr.add(v3(0, ys + 0.56 * (rw - ys), 0));
        _ = s.spawn(.{ .kind = .thrombus, .pos = clot, .radius = clot_radius, .hp = 40, .max_hp = 40 });

        const nest_dirs = [3]Vec3{ v3(0.3, -0.2, 0.93), v3(-0.8, 0.1, 0.5), v3(0.75, 0.45, -0.2) };
        for (nest_dirs, 0..) |d0, i| {
            const d = d0.norm();
            const p = clot.add(d.scale(clotSurface(d) - 10));
            _ = s.spawn(.{ .kind = .nest, .pos = p, .end = d, .radius = 46, .hp = 8, .max_hp = 8, .seed = @as(f32, @floatFromInt(i)) * 0.37 + 0.1 });
        }
        const anchor_dirs = [4]Vec3{ v3(0.35, 0.9, 0.2), v3(-0.4, 0.85, -0.3), v3(0.25, -0.95, 0.15), v3(-0.3, -0.9, -0.25) };
        for (anchor_dirs, 0..) |d0, i| {
            const d = d0.norm();
            const a = clot.add(d.scale(clotSurface(d) - 12));
            const far = if (vn.raycast(a.add(d.scale(20)), d, 1500)) |h| h.point.add(d.scale(8)) else a.add(d.scale(520));
            _ = s.spawn(.{ .kind = .anchor, .pos = a, .end = far, .radius = 9, .hp = 3.2, .max_hp = 3.2, .seed = @as(f32, @floatFromInt(i)) * 0.21 });
        }

        // Phlebolith corking the only channel through the web.
        const sp = &vn.septum;
        const sc = Vein.center(sp.z);
        _ = s.spawn(.{ .kind = .phlebolith, .pos = v3(sc.x + sp.hole_x, sc.y + sp.hole_y, sp.z - 120), .radius = 190, .hp = 50, .max_hp = 50 });
    }

    fn spawnNeutrophil(s: *Sim, z: f32, theta: f32) void {
        _ = s.spawn(.{ .kind = .neutrophil, .radius = 6, .end = v3(theta, z, s.rng.range(8, 20)), .seed = s.rng.f() });
    }

    pub fn clotSurface(d: Vec3) f32 {
        return mesh.blobRadius(d, mesh.clot_seed, mesh.clot_amp, mesh.clot_freq) * clot_radius;
    }

    pub fn spawn(s: *Sim, e: Entity) ?u16 {
        for (&s.ents, 0..) |*slot, i| {
            if (slot.kind == .none) {
                slot.* = e;
                return @intCast(i);
            }
        }
        return null;
    }

    // ------------------------------------------------------------------ helpers

    pub fn forward(s: *const Sim) Vec3 {
        const cp = @cos(s.pitch);
        return v3(cp * @sin(s.yaw), @sin(s.pitch), cp * @cos(s.yaw));
    }
    pub fn right(s: *const Sim) Vec3 {
        const f = s.forward();
        return v3(-f.z, 0, f.x).norm();
    }
    pub fn upVec(s: *const Sim) Vec3 {
        return s.right().cross(s.forward());
    }

    pub fn sound(s: *Sim, id: Sfx, pan: f32, gain: f32) void {
        if (s.nsfx < s.sfx.len) {
            s.sfx[s.nsfx] = .{ .id = id, .pan = pan, .gain = gain };
            s.nsfx += 1;
        }
    }

    pub fn say(s: *Sim, text: Text) void {
        s.voice.say(text, .normal);
    }
    pub fn urgent(s: *Sim, text: Text) void {
        s.voice.say(text, .urgent);
    }

    pub fn count(s: *const Sim, kind: Kind) u32 {
        var n: u32 = 0;
        for (&s.ents) |*e| {
            if (e.kind == kind) n += 1;
        }
        return n;
    }

    pub fn find(s: *Sim, kind: Kind) ?*Entity {
        for (&s.ents) |*e| {
            if (e.kind == kind) return e;
        }
        return null;
    }

    pub fn findConst(s: *const Sim, kind: Kind) ?*const Entity {
        for (&s.ents) |*e| {
            if (e.kind == kind) return e;
        }
        return null;
    }

    pub fn progress(s: *Sim) void {
        s.stall_t = 0;
        s.hint_level = 0;
        s.said.stall = false;
    }

    pub fn stabilise(s: *Sim, d: f32) void {
        s.stability = m.clamp(s.stability + d, 0, 100);
        if (d > 0) s.heal = 1;
    }

    pub fn tissueDamage(s: *Sim, amount: f32, event: bool) void {
        s.stability = @max(0, s.stability - amount);
        s.tissue_flash = 1;
        if (event) {
            s.stats.tissue_hits += 1;
            s.sound(.tissue, 0, 1);
        }
        if (!s.said.wall_hit) {
            s.said.wall_hit = true;
            s.urgent(L.thats_healthy_tissue);
        }
    }

    pub fn friendlyFire(s: *Sim) void {
        s.stats.friendly_fire += 1;
        s.stabilise(-3);
        s.sound(.tissue, 0, 0.8);
        if (!s.said.friendly) {
            s.said.friendly = true;
            s.urgent(L.that_cell_was_on_our_side);
        }
    }

    pub fn burst(s: *Sim, pos: Vec3, n: usize, speed: f32, color: [4]f32, size: f32, life: f32) void {
        for (0..n) |_| {
            const p = &s.parts[s.part_cursor];
            s.part_cursor = (s.part_cursor + 1) % max_parts;
            const k = s.rng.range(0.6, 1.4);
            p.* = .{ .life = life * k, .max_life = life * k, .pos = pos, .vel = s.rng.dir().scale(speed * s.rng.range(0.3, 1)), .size = size * s.rng.range(0.6, 1.3), .color = color, .drag = 2.5 };
        }
    }

    pub fn hurtDrone(s: *Sim, dmg: f32) void {
        s.hull -= dmg;
        s.hurt = 1;
        s.shake = @max(s.shake, 0.6);
        s.sound(.hurt, 0, 1);
        if (s.hull <= 0) {
            s.hull = 0;
            s.mode = .dead;
            s.voice.clear();
        }
    }

    pub fn dualActive(s: *const Sim) bool {
        return s.arms[0].held and s.arms[1].held;
    }

    pub fn locationCm(s: *const Sim) f32 {
        switch (s.chapter) {
            1 => return ch2.locationCm(s),
            2 => return ch3.locationCm(s),
            else => {},
        }
        return veinLocationCm(s.station, s.pos.z);
    }

    /// Centimetres of vein between a point of the chapter 1 model and the femoral junction. The model
    /// is three short stretches of a vein some thirty centimetres long, one per station, joined by the
    /// transits.
    pub fn veinLocationCm(station: u8, z: f32) f32 {
        return switch (station) {
            0 => 31.2 - z / 10000.0,
            1 => 18.9 - (z - station_b_z) / 10000.0,
            else => @max(0, (vein_mod.z_exit - z) / 10000.0),
        };
    }

    // ------------------------------------------------------------------ stages

    pub fn setStage(s: *Sim, st: Stage) void {
        s.stage = st;
        s.stage_t = 0;
        s.progress();
        s.voice.supersede();
        if (st.chapter()) |ch| switch (ch) {
            1 => return ch2.enter(s, st),
            2 => return ch3.enter(s, st),
            else => {},
        };
        const vn = &s.vein;
        switch (st) {
            .g_arrive, .g_villus, .g_descend, .g_wave, .g_scan, .g_extrude, .g_factory, .g_tether, .g_flume, .g_exit => unreachable,
            .s_arrive, .s_pits, .s_gradient, .s_wave, .s_swim, .s_margin, .s_cross, .s_cautery, .s_exit => unreachable,
            .needle => {
                s.say(L.comms_check);
                s.say(L.youre_inside_the_cannula);
                s.waypoint = vn.needle.at(-300);
            },
            .flow_wall => {
                s.say(L.first_lesson);
                const c = Vein.center(s.pos.z + 900);
                s.waypoint = c.add(v3(-(vn.wallR(c.z, m.pi) - 60), 0, 0));
            },
            .flow_core => {
                s.say(L.feel_it_against_the_wall);
                s.say(L.now_the_middle_of_the_stream);
                s.waypoint = null;
            },
            .to_valve1 => {
                s.say(L.and_here_it_carries_you);
                s.say(L.ride_it_downstream);
                s.waypoint = Vein.center(vn.valves[0].zb - 500);
            },
            .valve1_identify => {
                s.say(L.there_the_wall_bulges);
                s.waypoint = Vein.center(vn.valves[0].zb + 700);
            },
            .valve1_pass => {
                s.say(L.watch_one_cycle);
                s.waypoint = Vein.center(vn.valves[0].top() + 300);
            },
            .neutrophil => {
                s.want_checkpoint = true;
                s.say(L.clean_position_saved);
                s.say(L.pale_cells_are_rolling);
                s.waypoint = null;
            },
            .staph => {
                s.say(L.more_of_them_on_the_wall);
                s.say(L.bacteria_ahead);
                const f = Vein.tangent(s.pos.z);
                for (0..4) |i| {
                    const off = v3(s.rng.range(-70, 70), s.rng.range(-70, 70), 260 + @as(f32, @floatFromInt(i)) * 70);
                    _ = s.spawn(.{ .kind = .cocci, .pos = s.pos.add(f.scale(off.z)).add(v3(off.x, off.y, 0)), .radius = 2.6, .seed = s.rng.f(), .variant = @intCast(i % 3), .timer = 1.5 + @as(f32, @floatFromInt(i)) });
                }
                s.waypoint = null;
            },
            .tools => {
                s.say(L.each_arm_carries_three_tools);
                s.say(L.fit_the_drill_to_one_arm);
                s.waypoint = null;
            },
            .transit1 => s.beginTransit(0),
            .v2_approach => {
                s.station = 1;
                s.say(L.next_valve);
                s.say(L.go_past_its_free_edge);
                const v = &vn.valves[1];
                s.waypoint = Vein.center(v.top() + 150).add(v3(0, 900, 0));
            },
            .treat => {
                s.want_checkpoint = true;
                s.say(L.there_it_is_a_septic_thrombus);
                s.say(L.colonies_first);
                s.waypoint = if (s.find(.thrombus)) |e| e.pos else null;
            },
            .lyse_core => {
                s.urgent(L.its_loose_and_drifting);
                s.say(L.dissolve_it_before_it_leaves);
            },
            .freed => {
                vn.valves[1].pinned[0] = false;
                s.freed_t = 0;
                s.stabilise(15);
                s.sound(.objective, 0, 1);
                s.say(L.the_cusp_is_moving);
                s.waypoint = null;
            },
            .to_ring2 => {
                s.want_checkpoint = true;
                s.say(L.sync_servo_is_live);
                s.say(L.put_both_arms_on_punch);
                s.waypoint = if (s.findRing(1)) |e| e.pos else null;
            },
            .transit2 => s.beginTransit(1),
            .septum_find => {
                s.station = 2;
                s.say(L.last_stretch);
                s.say(L.no_flow_at_all);
                s.waypoint = null;
            },
            .septum_break => {
                s.say(L.a_stone_in_the_only_channel);
                s.say(L.both_arms_to_punch);
                s.waypoint = if (s.find(.phlebolith)) |e| e.pos.add(v3(0, 0, -230)) else null;
            },
            .exit => {
                vn.septum.corked = false;
                s.stabilise(10);
                s.sound(.shatter, 0, 1);
                s.urgent(L.its_through_hold_on);
                s.say(L.fine_grit);
                s.waypoint = Vein.center(vein_mod.z_exit);
            },
            .done => {
                s.mode = .complete;
                s.waypoint = null;
            },
        }
    }

    pub fn findRing(s: *Sim, which: u8) ?*Entity {
        for (&s.ents) |*e| {
            if (e.kind == .ring and e.variant == which) return e;
        }
        return null;
    }

    /// Where each of the chapter's two transits begins (its marker ring) and where it sets the drone down.
    pub const transits = [2]struct { from_z: f32, to_z: f32 }{
        .{ .from_z = ring1_z, .to_z = station_b_z },
        .{ .from_z = ring2_z, .to_z = station_c_z },
    };

    /// How far transit `which` carries the drone, in centimetres of vein, as the HUD's location readout
    /// measures it: the reading at the marker less the reading on arrival. The stations stand for
    /// stretches of the vein further apart than the model is long, so this is not the distance in world
    /// units.
    pub fn transitCm(which: usize) f32 {
        const t = transits[which];
        return veinLocationCm(@intCast(which), t.from_z) - veinLocationCm(@intCast(which + 1), t.to_z);
    }

    fn beginTransit(s: *Sim, which: usize) void {
        s.mode = .transit;
        s.transit_t = 0;
        s.transit_from = s.pos;
        s.transit_to_z = transits[which].to_z;
        s.transit_look = .{ s.yaw, s.pitch };
        s.vrel = .{};
        s.latched = false;
        s.sound(.transit, 0, 1);
        s.voice.clear();
        s.say(L.tempo_link_down[which]);
    }

    pub fn hintText(s: *const Sim) Text {
        switch (s.chapter) {
            1 => return ch2.hintText(s),
            2 => return ch3.hintText(s),
            else => {},
        }
        const lv: usize = @min(s.hint_level, 2);
        return switch (s.stage) {
            .needle => H.needle[lv],
            .flow_wall => H.flow_wall[lv],
            .flow_core => H.flow_core[lv],
            .to_valve1 => H.to_valve1[lv],
            .valve1_identify => H.valve1_identify[lv],
            .valve1_pass => H.valve1_pass[lv],
            .neutrophil => H.neutrophil[lv],
            .staph => H.staph[lv],
            .tools => H.tools[lv],
            .v2_approach => H.v2_approach[lv],
            .treat => if (s.count(.nest) > 0) H.treat_colonies[lv] else H.treat_cables[lv],
            .lyse_core => H.lyse_core[lv],
            .freed => H.freed,
            .to_ring2 => H.to_ring2[lv],
            .septum_find => H.septum_find[lv],
            .septum_break => H.septum_break[lv],
            .exit => H.exit,
            else => H.ring,
        };
    }

    // ------------------------------------------------------------------ frame

    pub fn update(s: *Sim, c: Controls, dt: f32) void {
        s.nsfx = 0;
        s.clock += dt;
        s.decay(dt);
        s.voice.update(dt);
        if (c.skip) s.voice.skip();
        s.updateParticles(dt);

        switch (s.mode) {
            .dead, .lost, .complete => return,
            .upgrade_card => {
                if (c.confirm and s.chapter == 1) {
                    ch2.upgradeTaken(s);
                } else if (c.confirm and s.chapter == 2) {
                    ch3.upgradeTaken(s);
                } else if (c.confirm) {
                    s.has_sync = true;
                    s.mode = .playing;
                    s.sound(.upgrade, 0, 1);
                    s.setStage(.to_ring2);
                }
                return;
            },
            .transit => {
                s.vein.stepValves(s.clock, dt);
                s.updateTransit(dt);
                return;
            },
            .playing => {},
        }

        s.stats.time += dt;
        s.stage_t += dt;
        s.stall_t += dt;
        switch (s.chapter) {
            0 => s.vein.stepValves(s.clock, dt),
            1 => s.gut.step(dt),
            else => s.sto.step(dt),
        }

        s.yaw -= c.look[0];
        s.pitch = m.clamp(s.pitch + c.look[1], -1.5, 1.5);

        s.updateFocus();
        if (c.examine) s.examine();
        if (c.hint) s.giveHint();
        if (c.tether) switch (s.chapter) {
            1 => ch2.tetherKey(s),
            2 => ch3.tetherKey(s),
            else => {},
        };

        s.latched = false;
        for (0..2) |i| s.updateTool(i, c, dt);
        if (s.dualActive() and s.arms[0].tool != s.arms[1].tool) s.stats.dual_time += dt;

        s.move(c, dt);
        s.updateEntities(dt);
        s.updateShots(dt);
        s.script(dt);

        if (s.stability <= 0 and s.mode == .playing) {
            s.mode = .lost;
            s.voice.clear();
        }
    }

    fn decay(s: *Sim, dt: f32) void {
        s.shake = @max(0, s.shake - dt * 2.5);
        s.hurt = @max(0, s.hurt - dt * 1.6);
        s.heal = @max(0, s.heal - dt * 0.8);
        s.tissue_flash = @max(0, s.tissue_flash - dt * 2.0);
        s.sync_flash = @max(0, s.sync_flash - dt * 1.5);
        s.checkpoint_toast = @max(0, s.checkpoint_toast - dt);
        s.examine_cd = @max(0, s.examine_cd - dt);
        s.windup_lock = @max(0, s.windup_lock - dt);
        if (s.scan_r >= 0) {
            s.scan_r += dt * 900;
            if (s.scan_r > 1400) s.scan_r = -1;
        }
        if (s.mode != .transit) s.warp = m.approach(s.warp, 0, 6, dt);
    }

    fn updateParticles(s: *Sim, dt: f32) void {
        for (&s.parts) |*p| {
            if (p.life <= 0) continue;
            p.life -= dt;
            p.pos = p.pos.add(p.vel.scale(dt));
            p.vel = p.vel.scale(@exp(-p.drag * dt));
        }
    }

    fn updateTransit(s: *Sim, dt: f32) void {
        const dur: f32 = 3.4;
        s.transit_t += dt;
        const k = m.smoothstep(0, 1, s.transit_t / dur);
        const z = m.lerp(s.transit_from.z, s.transit_to_z, k);
        const from_c = Vein.center(s.transit_from.z);
        const off = s.transit_from.sub(from_c).scale(1 - m.smoothstep(0, 0.5, s.transit_t / dur));
        const ctr = Vein.center(z);
        s.pos = v3(ctr.x + off.x, ctr.y + off.y, z);
        const tg = Vein.tangent(z);
        const target_yaw = std.math.atan2(tg.x, tg.z);
        const target_pitch = std.math.asin(tg.y);
        const a = m.smoothstep(0, 0.35, s.transit_t / dur);
        var dy = target_yaw - s.transit_look[0];
        while (dy > m.pi) dy -= m.tau;
        while (dy < -m.pi) dy += m.tau;
        s.yaw = s.transit_look[0] + dy * a;
        s.pitch = m.lerp(s.transit_look[1], target_pitch, a);
        s.warp = @sin(m.pi * m.sat(s.transit_t / dur));
        if (s.transit_t >= dur) {
            s.mode = .playing;
            s.warp = 0;
            s.sides = .{};
            s.flow = .{};
            s.setStage(if (s.stage == .transit1) .v2_approach else .septum_find);
        }
    }

    fn move(s: *Sim, c: Controls, dt: f32) void {
        const f = s.forward();
        const r = s.right();
        const u = s.upVec();
        var want = f.scale(c.move.z).add(r.scale(c.move.x)).add(u.scale(c.move.y));
        const wl = want.len();
        if (wl > 1) want = want.scale(1 / wl);
        var speed: f32 = if (c.boost) boost_speed else cruise_speed;
        if (s.latched) speed *= 0.1;
        s.vrel = s.vrel.add(want.scale(speed).sub(s.vrel).scale(1 - @exp(-6 * dt)));
        const fl = if (s.latched or s.tether != null) Vec3.zero else s.worldFlow(s.pos);
        s.flow = s.flow.add(fl.sub(s.flow).scale(1 - @exp(-8 * dt)));
        const before = s.pos;
        var p = s.pos.add(s.vrel.add(s.flow).scale(dt));
        if (s.tether) |anchor| {
            if (s.pos.dist(anchor) > ch2.tether_range + 80) {
                s.tether = null; // the line parted
            } else {
                p = ch2.tetherMove(s, anchor, want, dt);
            }
        }

        // Solid bodies.
        for (&s.ents) |*e| {
            switch (e.kind) {
                .thrombus => {
                    const d = p.sub(e.pos);
                    const dl = d.len();
                    const surf = clotSurface(d.norm()) * (e.radius / clot_radius) + hull_r;
                    if (dl < surf) p = e.pos.add(d.norm().scale(surf));
                },
                .phlebolith, .nest, .factory, .colony, .vessel => {
                    const d = p.sub(e.pos);
                    const dl = d.len();
                    const rad = (if (e.kind == .nest) e.radius * 0.8 else e.radius) + hull_r;
                    if (dl < rad) p = e.pos.add(d.norm().scale(rad));
                },
                .anchor => {
                    const q = closestOnSegment(p, e.pos, e.end);
                    const d = p.sub(q);
                    const dl = d.len();
                    if (dl < e.radius + hull_r) p = q.add(d.norm().scale(e.radius + hull_r));
                },
                else => {},
            }
        }

        switch (s.chapter) {
            1 => return ch2.moveCollide(s, p, dt),
            2 => return ch3.moveCollide(s, p, dt),
            else => {},
        }
        const res = s.vein.collide(p, hull_r, &s.sides, &s.in_bore);
        s.pos = res.pos;
        if (res.squeezed) {
            s.pos.z -= 140 * dt;
            if (!s.said.reflux) {
                s.said.reflux = true;
                s.urgent(L.reflux_back_off);
            }
        }
        if (res.wall or res.leaflet) {
            const impact = p.sub(before).len() / @max(dt, 1e-4);
            if (impact > 480 and s.shake < 0.2) {
                s.shake = 0.5;
                s.sound(.bump, 0, 0.7);
                s.hull = @max(1, s.hull - 2);
            }
        }
    }

    pub fn worldFlow(s: *const Sim, p: Vec3) Vec3 {
        return switch (s.chapter) {
            1 => s.gut.flowAt(p, s.clock),
            2 => ch3.flowAt(s, p),
            else => s.vein.flowAt(p, s.clock),
        };
    }

    // ------------------------------------------------------------------ focus and the guide

    fn updateFocus(s: *Sim) void {
        const o = s.pos;
        const d = s.forward();
        var best: Focus = .{};
        var best_t: f32 = 2600;
        var found = false;

        if (s.chapter != 0) {
            const hit = if (s.chapter == 1) ch2.focusRay(s, o, d, best_t) else ch3.focusRay(s, o, d, best_t);
            if (hit) |f| {
                best = f;
                best_t = f.dist;
                found = true;
            }
        } else if (s.vein.raycast(o, d, best_t)) |h| {
            best_t = h.t;
            found = true;
            best = .{ .dist = h.t, .point = h.point, .tissue = h.what != .needle, .topic = switch (h.what) {
                .wall => .vein_wall,
                .sinus => .sinus,
                .leaflet => .leaflet,
                .needle => .cannula,
                .septum => .septum,
            } };
        }
        for (&s.ents, 0..) |*e, i| {
            if (e.kind == .none) continue;
            if (e.kind == .infected and e.state == 0) continue; // indistinguishable from its neighbours until scanned
            var t: ?f32 = null;
            switch (e.kind) {
                .anchor => t = raySegment(o, d, e.pos, e.end, e.radius + 2),
                .ring => {
                    if (!s.ringVisible(e.variant)) continue;
                    // the ring is a marker: only its rim counts
                    if (raySphere(o, d, e.pos, e.radius + 12)) |tt| {
                        const hit = o.add(d.scale(tt));
                        if (hit.dist(e.pos) > e.radius * 0.75) t = tt;
                    }
                },
                .thrombus => t = raySphere(o, d, e.pos, e.radius * 0.93),
                else => t = raySphere(o, d, e.pos, e.radius + if (e.radius < 8) @as(f32, 2.5) else 0),
            }
            if (t) |tt| {
                if (tt < best_t) {
                    best_t = tt;
                    found = true;
                    best = .{ .ent = @intCast(i), .dist = tt, .point = o.add(d.scale(tt)), .topic = topicOf(e) };
                }
            }
        }
        if (s.ambient_focus) |af| {
            if (af.dist < best_t) {
                best = af;
                found = true;
            }
        }
        s.focus = if (found) best else .{};
    }

    pub fn ringVisible(s: *const Sim, which: u8) bool {
        if (which == 2) return s.stage == .g_exit;
        if (which == 3) return s.stage == .s_exit;
        return if (which == 0) s.stage == .tools or s.stage == .staph or s.stage == .neutrophil else s.stage == .to_ring2;
    }

    pub fn topicOf(e: *const Entity) Topic {
        return switch (e.kind) {
            .cocci => .staph,
            .nest => .nest,
            .anchor => .anchor,
            .embolus => .embolus,
            .neutrophil => .neutrophil,
            .odd_cell => switch (e.variant) {
                0 => .reticulocyte,
                1 => .band_cell,
                else => .nucleated_red_cell,
            },
            .thrombus => .thrombus,
            .phlebolith => .phlebolith,
            .ring => .transit,
            .infected => .infected_cell,
            .shed => .shed_cell,
            .virion => if (e.known) .rotavirus else .unknown_microbe,
            .commensal => if (e.known) .commensal else .unknown_microbe,
            .factory => .viral_factory,
            .pylori => .helicobacter,
            .colony => .colonised_pit,
            .vessel => .bleeding_vessel,
            .grit => .food_particle,
            .none => .red_cell,
        };
    }

    fn examine(s: *Sim) void {
        if (s.examine_cd > 0) return;
        s.examine_cd = 0.5;
        if (s.chapter == 1) {
            s.scan_r = 0;
            ch2.scanPulse(s);
            if (s.focus.ent) |fi| s.focus.topic = topicOf(&s.ents[fi]);
        }
        const tp = s.focus.topic orelse {
            if (s.chapter == 1) {
                s.sound(.scan, 0, 1);
                return;
            }
            s.voice.say(L.nothing_under_your_reticle, .chatter);
            return;
        };
        const i = @intFromEnum(tp);
        const e = guide.entry(tp);
        s.scan_r = 0;
        s.sound(.scan, 0, 1);
        if (!s.atlas[i]) {
            s.atlas[i] = true;
            s.say(e.short);
            s.onIdentify(tp);
        } else {
            s.atlas_deep[i] = true;
            s.say(e.deep);
        }
    }

    fn onIdentify(s: *Sim, tp: Topic) void {
        switch (tp) {
            .leaflet => if (s.stage == .valve1_identify or s.stage == .to_valve1) s.setStage(.valve1_pass),
            .sinus => if (s.stage == .valve1_identify and !s.said.sinus) {
                s.said.sinus = true;
                s.say(L.thats_the_bulge_itself);
            },
            .neutrophil => if (s.stage == .neutrophil) s.setStage(.staph),
            .phlebolith => if (s.stage == .septum_find) s.setStage(.septum_break),
            .reticulocyte, .band_cell, .nucleated_red_cell => {
                s.odd_found += 1;
                if (s.odd_found == 1) {
                    s.say(L.keep_an_eye_out_for_more);
                } else if (s.odd_found == 3) {
                    s.hidden_unlocked = true;
                    s.sound(.objective, 0, 1);
                    s.say(L.three_immature_cells);
                    s.say(L.the_femurs_nutrient_vein);
                }
            },
            else => switch (s.chapter) {
                1 => ch2.onIdentify(s, tp),
                2 => ch3.onIdentify(s, tp),
                else => {},
            },
        }
    }

    fn giveHint(s: *Sim) void {
        s.say(s.hintText());
        s.stats.hints += 1;
        s.sound(.ui, 0, 1);
        if (s.hint_level < 2) s.hint_level += 1;
        s.stall_t = 0;
    }

    // ------------------------------------------------------------------ arms

    fn updateTool(s: *Sim, i: usize, c: Controls, dt: f32) void {
        const a = &s.arms[i];
        const pan: f32 = if (i == 0) -0.7 else 0.7;
        a.cooldown = @max(0, a.cooldown - dt);
        a.flash = @max(0, a.flash - dt * 4);
        a.recoil = @max(0, a.recoil - dt * 7);
        a.swap = @max(0, a.swap - dt * 3.5);
        a.engaged = false;

        var new_tool: ?Tool = c.select[i];
        if (c.cycle[i]) new_tool = a.tool.next();
        if (new_tool) |t| {
            if (t != a.tool) {
                a.tool = t;
                a.swap = 1;
                a.punch_t = -1;
                a.cooldown = @max(a.cooldown, 0.25);
                s.sound(.ui, pan, 0.8);
            }
        }
        const held = c.arm[i] and a.swap < 0.3;
        a.held = held;

        // passive recovery
        if (!(a.tool == .drill and held)) {
            a.heat = @max(0, a.heat - 0.3 * dt);
            a.latch = null;
        }
        if (a.overheated and a.heat < 0.35) a.overheated = false;
        a.charge = @min(1, a.charge + 0.3 * dt);

        var ext_target: f32 = 0;
        switch (a.tool) {
            .shoot => {
                if (held and a.cooldown <= 0 and a.charge >= 0.085) {
                    a.charge -= 0.085;
                    a.cooldown = 0.2;
                    a.recoil = 1;
                    s.fire(i);
                }
            },
            .punch => {
                if (held and a.cooldown <= 0 and a.punch_t < 0) {
                    a.punch_t = 0;
                    a.struck = false;
                    a.punch_clock = s.clock;
                    a.cooldown = 0.5;
                    s.sound(.swing, pan, 0.8);
                }
                if (a.punch_t >= 0) {
                    a.punch_t += dt;
                    if (a.punch_t < punch_delay) {
                        ext_target = a.punch_t / punch_delay;
                    } else {
                        ext_target = @max(0, 1 - (a.punch_t - punch_delay) / 0.28);
                    }
                    a.ext = ext_target;
                    if (a.punch_t >= punch_delay and !a.struck) s.resolvePunch(i);
                    if (a.punch_t > punch_delay + 0.3) a.punch_t = -1;
                    return;
                }
            },
            .drill => {
                if (held and !a.overheated) {
                    ext_target = 1;
                    a.spin += dt * 60;
                    const engaged = s.drill(i, dt);
                    a.engaged = engaged;
                    a.heat += (if (engaged) @as(f32, 0.2) else 0.07) * dt;
                    if (a.heat >= 1) {
                        a.heat = 1;
                        a.overheated = true;
                        s.sound(.overheat, pan, 1);
                        if (!s.said.overheat) {
                            s.said.overheat = true;
                            s.say(L.drills_overheated);
                        }
                    }
                }
            },
        }
        a.ext = m.approach(a.ext, ext_target, 14, dt);
    }

    pub fn muzzle(s: *const Sim, i: usize) Vec3 {
        const side: f32 = if (i == 0) -1 else 1;
        return s.pos.add(s.right().scale(side * 2.4)).add(s.upVec().scale(-1.5)).add(s.forward().scale(6));
    }

    fn fire(s: *Sim, i: usize) void {
        const a = &s.arms[i];
        const other = &s.arms[1 - i];
        const pan: f32 = if (i == 0) -0.7 else 0.7;
        a.shot_clock = s.clock;

        // Sync Servo: two rounds inside the window merge into one lance.
        if (s.has_sync and other.tool == .shoot and s.clock - other.shot_clock <= sync_window) {
            const sh = &s.shots[other.shot_idx];
            if (sh.alive and !sh.lance) {
                sh.lance = true;
                sh.pos = sh.pos.add(s.muzzle(i).sub(sh.pos).scale(0.5));
                s.syncFeedback();
                s.sound(.lance, 0, 1);
                return;
            }
        }

        const f = s.forward();
        var aim = if (s.focus.topic != null and s.focus.dist < 900) s.focus.point else s.pos.add(f.scale(420));
        // light aim assist onto hostile organisms close to the reticle
        var best_cos: f32 = 0.9982; // ~3.4 degrees
        for (&s.ents) |*e| {
            if (!(e.kind == .cocci or e.kind == .embolus or e.kind == .shed or e.kind == .pylori or (e.kind == .virion and e.known))) continue;
            const d = e.pos.sub(s.pos);
            const dl = d.len();
            if (dl > 750 or dl < 1) continue;
            const cs = d.dot(f) / dl;
            if (cs > best_cos) {
                best_cos = cs;
                aim = e.pos.add(e.vel.scale(dl / 950));
            }
        }
        const from = s.muzzle(i);
        const dir = aim.sub(from).norm();
        for (&s.shots, 0..) |*sh, k| {
            if (!sh.alive) {
                sh.* = .{ .alive = true, .pos = from, .vel = dir.scale(950).add(s.flow), .life = 0.85, .arm = @intCast(i) };
                a.shot_idx = @intCast(k);
                break;
            }
        }
        s.sound(.shoot, pan, 0.8);
    }

    pub fn syncFeedback(s: *Sim) void {
        s.sync_flash = 1;
        s.stats.sync_strikes += 1;
        s.arms[0].flash = 1;
        s.arms[1].flash = 1;
    }

    fn resolvePunch(s: *Sim, i: usize) void {
        const a = &s.arms[i];
        const other = &s.arms[1 - i];
        a.struck = true;
        var sync = false;
        if (s.has_sync and other.tool == .punch and other.punch_t >= 0 and !other.struck and @abs(other.punch_clock - a.punch_clock) <= sync_window) {
            sync = true;
            other.struck = true;
        }
        const pan: f32 = if (sync) 0 else if (i == 0) -0.7 else 0.7;
        const f = s.forward();
        const reach: f32 = if (sync) 70 else punch_reach;
        const cos_lim: f32 = if (sync) 0.45 else 0.74;
        var landed = false;

        for (&s.ents, 0..) |*e, idx| {
            if (e.kind == .none or e.kind == .ring) continue;
            if (e.kind == .infected and e.state == 0) continue;
            var d = e.pos.sub(s.pos);
            var surface = e.radius;
            if (e.kind == .anchor) {
                d = closestOnSegment(s.pos, e.pos, e.end).sub(s.pos);
            } else if (e.kind == .thrombus) {
                surface = clotSurface(d.norm().neg()) * (e.radius / clot_radius);
            }
            const dl = d.len();
            if (dl - surface > reach) continue;
            // big bodies only need to be in front; small ones must be inside the cone
            const cs = if (dl > 1) d.dot(f) / dl else 1;
            if (cs < (if (surface > 40) @as(f32, 0.3) else cos_lim)) continue;
            landed = true;
            const hit_at = s.pos.add(d.norm().scale(@max(0, dl - surface)));
            switch (e.kind) {
                .cocci => s.killCocci(@intCast(idx), d.norm().scale(120)),
                .embolus => {
                    // a punch only makes two
                    s.splitEmbolus(@intCast(idx), d.norm());
                },
                .phlebolith => {
                    const dmg: f32 = if (sync) sync_punch_factor else 1;
                    e.hp -= dmg;
                    e.flash = 1;
                    s.burst(hit_at, if (sync) 40 else 8, if (sync) 220 else 90, .{ 1, 0.9, 0.7, 1 }, 3, 0.6);
                    if (!sync and !s.said.single_punch and s.stage == .septum_break) {
                        s.said.single_punch = true;
                        s.say(L.one_arm_only_chips_it);
                    }
                    if (e.hp <= 0) s.shatterStone(@intCast(idx));
                },
                .thrombus => {
                    if (s.stage != .lyse_core) {
                        s.shedEmbolus(hit_at, d.norm().neg());
                        if (!s.said.punch_clot) {
                            s.said.punch_clot = true;
                            s.urgent(L.dont_hit_the_clot_it_sheds);
                        }
                    }
                },
                .neutrophil, .odd_cell => {
                    // shoved aside, unharmed
                    e.vel = e.vel.add(d.norm().scale(160));
                    e.state = 1;
                    e.timer = 2.5;
                },
                .nest => e.flash = 0.5,
                .anchor => e.flash = 0.5,
                .infected, .shed, .virion, .commensal, .factory => ch2.punched(s, @intCast(idx), d.norm()),
                .pylori, .colony, .vessel, .grit => ch3.punched(s, @intCast(idx), d.norm()),
                else => {},
            }
        }
        if (!landed and s.focus.tissue and s.focus.dist < reach + 4) {
            s.tissueDamage(if (sync) 5 else 2.5, true);
            s.burst(s.focus.point, 6, 60, .{ 1, 0.3, 0.3, 1 }, 3, 0.5);
            landed = true;
        }
        if (sync) {
            s.syncFeedback();
            s.sound(.sync, 0, 1);
            s.shake = @max(s.shake, 0.7);
            s.burst(s.pos.add(f.scale(18)), 30, 260, .{ 0.6, 0.95, 1, 1 }, 3.5, 0.45);
            // shockwave clears small organisms all around
            for (&s.ents, 0..) |*e, idx| {
                if (e.kind == .cocci and e.pos.dist(s.pos) < 75) s.killCocci(@intCast(idx), e.pos.sub(s.pos).norm().scale(200));
            }
            if (s.chapter == 2) ch3.syncWave(s);
        } else if (landed) {
            s.sound(.punch_hit, pan, 1);
            s.shake = @max(s.shake, 0.25);
            a.flash = 1;
        }
    }

    fn drillTarget(s: *Sim, i: usize) ?DrillTarget {
        const a = &s.arms[i];
        if (a.latch) |lt| {
            var ok = s.pos.dist(lt.point) < drill_reach + 16;
            if (lt.ent) |idx| {
                if (s.ents[idx].kind != lt.kind) ok = false;
            }
            if (ok) return lt;
            a.latch = null;
        }
        const fo = s.focus;
        if (fo.topic == null or fo.dist > drill_reach) return null;
        const t: DrillTarget = .{ .ent = fo.ent, .kind = if (fo.ent) |idx| s.ents[idx].kind else .none, .point = fo.point, .tissue = fo.tissue, .cannula = fo.topic == .cannula };
        if (t.ent == null and !t.tissue and !t.cannula) return null;
        // moving organisms are shredded on contact rather than held
        if (t.kind != .cocci and t.kind != .embolus and t.kind != .virion and t.kind != .shed and t.kind != .commensal and t.kind != .infected and t.kind != .pylori and t.kind != .grit) a.latch = t;
        return t;
    }

    /// Returns true while the bit is cutting something.
    fn drill(s: *Sim, i: usize, dt: f32) bool {
        const tg = s.drillTarget(i) orelse return false;
        const other = &s.arms[1 - i];
        const both = other.tool == .drill and other.engaged;
        const rate: f32 = if (both and s.has_sync) 1.5 else 1.0;
        const spark = s.rng.f() < dt * 40;

        if (tg.ent) |idx| {
            const e = &s.ents[idx];
            switch (e.kind) {
                .anchor => {
                    e.hp -= rate * dt;
                    e.flash = 1;
                    e.timer = 0.6; // suppress re-knit while being cut
                    s.latched = true;
                    if (spark) s.burst(tg.point, 2, 70, .{ 1, 0.8, 0.4, 1 }, 2.2, 0.35);
                    if (e.hp <= 0) s.cutAnchor(idx);
                    return true;
                },
                .nest => {
                    e.aux = @min(1, e.aux + 1.3 * rate * dt);
                    e.timer = 0.25;
                    s.latched = true;
                    if (spark) s.burst(tg.point, 2, 50, .{ 1, 0.85, 0.3, 1 }, 2.5, 0.4);
                    if (e.aux > 0.6 and !s.said.nest_open) {
                        s.said.nest_open = true;
                        s.urgent(L.its_open_fire_into_it);
                    }
                    return true;
                },
                .thrombus => {
                    s.latched = true;
                    if (s.stage == .lyse_core) return true;
                    s.clot_shed_t += dt;
                    if (s.clot_shed_t > 1.1) {
                        s.clot_shed_t = 0;
                        s.shedEmbolus(tg.point, tg.point.sub(e.pos).norm());
                    }
                    if (!s.said.drill_clot) {
                        s.said.drill_clot = true;
                        s.urgent(L.not_the_clot_body_it_fragments);
                    }
                    return true;
                },
                .embolus => {
                    s.splitEmbolus(idx, s.right());
                    return true;
                },
                .cocci => {
                    s.killCocci(idx, s.forward().scale(60));
                    return true;
                },
                .phlebolith => {
                    e.hp -= 0.25 * rate * dt;
                    e.flash = 0.6;
                    s.latched = true;
                    if (spark) s.burst(tg.point, 3, 120, .{ 1, 0.95, 0.8, 1 }, 2, 0.3);
                    if (e.hp <= 0) s.shatterStone(idx);
                    return true;
                },
                .neutrophil, .odd_cell => {
                    s.burst(e.pos, 14, 60, .{ 0.9, 0.9, 1, 1 }, 3, 0.6);
                    e.kind = .none;
                    s.friendlyFire();
                    return true;
                },
                .infected, .shed, .virion, .commensal, .factory => return ch2.drilled(s, idx, tg.point, rate, dt, spark),
                .pylori, .colony, .vessel, .grit => return ch3.drilled(s, idx, tg.point, rate, dt, spark),
                else => return false,
            }
        }
        if (tg.tissue) {
            s.latched = true;
            s.tissueDamage(5 * dt, s.rng.f() < dt * 2);
            if (spark) s.burst(tg.point, 2, 60, .{ 1, 0.25, 0.25, 1 }, 2.5, 0.4);
            return true;
        }
        if (tg.cannula) {
            if (spark) s.burst(tg.point, 2, 140, .{ 1, 1, 0.9, 1 }, 1.8, 0.25);
            if (!s.said.needle_drill) {
                s.said.needle_drill = true;
                s.voice.say(L.thats_my_needle_youre_drilling, .chatter);
            }
            return true;
        }
        return false;
    }

    // ------------------------------------------------------------------ treatment events

    fn killCocci(s: *Sim, idx: u16, push: Vec3) void {
        const e = &s.ents[idx];
        if (e.kind != .cocci) return;
        s.burst(e.pos, 10, 90, .{ 1, 0.85, 0.25, 1 }, 2.2, 0.5);
        s.parts[(s.part_cursor + max_parts - 1) % max_parts].vel = push;
        e.kind = .none;
        s.stats.kills += 1;
        s.sound(.kill, m.clamp(e.pos.sub(s.pos).dot(s.right()) / 60, -1, 1), 0.9);
        if (s.stage == .staph) s.progress();
    }

    fn shedEmbolus(s: *Sim, at: Vec3, dir: Vec3) void {
        _ = s.spawn(.{ .kind = .embolus, .pos = at.add(dir.scale(14)), .vel = dir.scale(35), .radius = 11, .hp = 2, .max_hp = 2, .seed = s.rng.f() });
        s.sound(.cut, 0, 0.6);
        s.noteEmbolus();
    }

    fn noteEmbolus(s: *Sim) void {
        if (!s.said.embolus) {
            s.said.embolus = true;
            s.urgent(L.fragments_loose_dissolve_them);
        }
    }

    fn splitEmbolus(s: *Sim, idx: u16, dir: Vec3) void {
        const e = &s.ents[idx];
        if (e.radius < 7) {
            e.vel = e.vel.add(dir.scale(80));
            return;
        }
        const r = e.radius * 0.72;
        const side = dir.perp();
        const base = e.*;
        e.radius = r;
        e.hp = @ceil(r / 5);
        e.max_hp = e.hp;
        e.vel = base.vel.add(side.scale(40));
        var twin = base;
        twin.radius = r;
        twin.hp = e.hp;
        twin.max_hp = e.hp;
        twin.vel = base.vel.sub(side.scale(40));
        twin.seed = s.rng.f();
        _ = s.spawn(twin);
        s.burst(base.pos, 8, 60, .{ 0.8, 0.2, 0.2, 1 }, 3, 0.5);
    }

    fn cutAnchor(s: *Sim, idx: u16) void {
        const e = &s.ents[idx];
        const mid = e.pos.lerp(e.end, 0.5);
        const axis = e.end.sub(e.pos).norm();
        s.burst(mid, 30, 120, .{ 1, 0.9, 0.6, 1 }, 3, 0.7);
        e.kind = .none;
        s.sound(.cut, 0, 1);
        s.stabilise(1);
        s.progress();
        // fragments of the clot it held
        const side = axis.perp();
        _ = s.spawn(.{ .kind = .embolus, .pos = mid.add(side.scale(16)), .vel = side.scale(30), .radius = 14, .hp = 3, .max_hp = 3, .seed = s.rng.f() });
        _ = s.spawn(.{ .kind = .embolus, .pos = mid.sub(side.scale(16)), .vel = side.scale(-30), .radius = 10, .hp = 2, .max_hp = 2, .seed = s.rng.f() });
        s.noteEmbolus();
    }

    fn killNest(s: *Sim, idx: u16) void {
        const e = &s.ents[idx];
        s.burst(e.pos, 50, 150, .{ 1, 0.8, 0.2, 1 }, 4, 0.9);
        e.kind = .none;
        s.sound(.nest_die, 0, 1);
        s.stabilise(3);
        s.progress();
        const left = s.count(.nest);
        if (left == 0) {
            s.say(L.colonies_are_gone);
        } else if (!s.said.nest_dead) {
            s.said.nest_dead = true;
            s.say(L.one_down_same_again);
        }
    }

    fn shatterStone(s: *Sim, idx: u16) void {
        const e = &s.ents[idx];
        s.burst(e.pos, 120, 380, .{ 1, 0.95, 0.85, 1 }, 5, 1.2);
        e.kind = .none;
        s.shake = 1;
        if (s.stage == .septum_find or s.stage == .septum_break) s.setStage(.exit);
    }

    fn shotHit(s: *Sim, sh: *Shot, idx: u16, at: Vec3) bool {
        const e = &s.ents[idx];
        const dmg: f32 = if (sh.lance) lance_factor else 1;
        const arm = &s.arms[sh.arm];
        switch (e.kind) {
            .cocci => {
                s.killCocci(idx, sh.vel.norm().scale(80));
                arm.flash = 1;
                return !sh.lance; // a lance pierces
            },
            .nest => {
                if (e.aux > 0.5) {
                    e.hp -= dmg;
                    e.flash = 1;
                    arm.flash = 1;
                    s.burst(at, 6, 80, .{ 1, 0.9, 0.3, 1 }, 2.5, 0.4);
                    s.sound(.punch_hit, 0, 0.5);
                    if (e.hp <= 0) s.killNest(idx);
                } else {
                    s.burst(at, 3, 30, .{ 0.7, 0.6, 0.2, 1 }, 3, 0.5);
                    s.sound(.absorb, 0, 0.7);
                    if (!s.said.absorb) {
                        s.said.absorb = true;
                        s.say(L.the_slime_is_soaking_up_rounds);
                    }
                }
                return true;
            },
            .embolus => {
                e.hp -= dmg;
                e.flash = 1;
                arm.flash = 1;
                e.radius = @max(4, e.radius * 0.8);
                s.burst(at, 5, 50, .{ 0.5, 1, 0.9, 1 }, 2.5, 0.5);
                if (e.hp <= 0) {
                    s.burst(e.pos, 16, 70, .{ 0.5, 1, 0.9, 1 }, 3, 0.8);
                    e.kind = .none;
                    s.stats.emboli_lysed += 1;
                    s.sound(.kill, 0, 0.7);
                }
                return !sh.lance;
            },
            .thrombus => {
                if (s.stage == .lyse_core) {
                    e.hp -= dmg;
                    e.flash = 1;
                    arm.flash = 1;
                    e.radius = clot_radius * (0.35 + 0.65 * @max(0, e.hp) / e.max_hp);
                    s.burst(at, 8, 90, .{ 0.5, 1, 0.9, 1 }, 4, 0.7);
                    s.sound(.punch_hit, 0, 0.4);
                    if (!s.said.core_half and e.hp < e.max_hp * 0.5) {
                        s.said.core_half = true;
                        s.voice.say(L.its_dissolving, .chatter);
                    }
                    if (e.hp <= 0) {
                        s.burst(e.pos, 90, 200, .{ 0.5, 1, 0.9, 1 }, 6, 1.4);
                        e.kind = .none;
                        s.setStage(.freed);
                    }
                } else {
                    s.burst(at, 3, 30, .{ 0.6, 0.2, 0.2, 1 }, 3, 0.4);
                    s.sound(.absorb, 0, 0.5);
                }
                return true;
            },
            .anchor => {
                e.flash = 0.4;
                s.sound(.absorb, 0, 0.5);
                return true;
            },
            .phlebolith => {
                e.flash = 0.3;
                s.burst(at, 3, 100, .{ 1, 1, 0.9, 1 }, 1.5, 0.25);
                s.sound(.absorb, 0, 0.6);
                return true;
            },
            .neutrophil, .odd_cell => {
                s.burst(e.pos, 14, 60, .{ 0.9, 0.9, 1, 1 }, 3, 0.6);
                e.kind = .none;
                s.friendlyFire();
                return true;
            },
            .infected, .shed, .virion, .commensal, .factory => return ch2.shotHit(s, sh, idx, at),
            .pylori, .colony, .vessel, .grit => return ch3.shotHit(s, sh, idx, at),
            else => return false,
        }
    }

    fn updateShots(s: *Sim, dt: f32) void {
        for (&s.shots) |*sh| {
            if (!sh.alive) continue;
            sh.life -= dt;
            if (sh.life <= 0) {
                sh.alive = false;
                continue;
            }
            const step = sh.vel.scale(dt);
            const len = step.len();
            const dir = step.scale(1 / @max(len, 1e-4));
            var best_t: f32 = len;
            var best_ent: ?u16 = null;
            for (&s.ents, 0..) |*e, i| {
                if (e.kind == .none or e.kind == .ring) continue;
                if (e.kind == .infected and e.state == 0) continue;
                const pad: f32 = if (sh.lance) 4 else 1.5;
                const t = switch (e.kind) {
                    .anchor => raySegment(sh.pos, dir, e.pos, e.end, e.radius + pad),
                    .thrombus => raySphere(sh.pos, dir, e.pos, e.radius * 0.9),
                    else => raySphere(sh.pos, dir, e.pos, e.radius + pad),
                };
                if (t) |tt| {
                    if (tt <= best_t) {
                        best_t = tt;
                        best_ent = @intCast(i);
                    }
                }
            }
            if (s.chapter == 1) {
                if (s.gut.raycast(sh.pos, dir, best_t)) |h| {
                    sh.alive = false;
                    ch2.shotTissue(s, h);
                    continue;
                }
            }
            if (s.chapter == 2) {
                ch3.shotDrag(sh, dt);
                if (s.sto.raycast(sh.pos, dir, best_t)) |h| {
                    sh.alive = false;
                    ch3.shotTissue(s, h);
                    continue;
                }
            }
            var tissue: ?vein_mod.RayHit = null;
            if (s.chapter == 0 and !s.vein.inBore(sh.pos)) {
                if (s.vein.raycast(sh.pos, dir, best_t)) |h| {
                    if (h.t <= best_t) {
                        tissue = h;
                        best_ent = null;
                    }
                }
            }
            if (tissue) |h| {
                sh.alive = false;
                if (h.what != .needle) {
                    s.tissueDamage(1.5, true);
                    s.burst(h.point, 6, 50, .{ 1, 0.3, 0.3, 1 }, 3, 0.5);
                } else {
                    s.burst(h.point, 4, 120, .{ 1, 1, 0.9, 1 }, 1.5, 0.25);
                }
                continue;
            }
            if (best_ent) |idx| {
                const at = sh.pos.add(dir.scale(best_t));
                if (s.shotHit(sh, idx, at)) {
                    sh.alive = false;
                    continue;
                }
            }
            sh.pos = sh.pos.add(step);
        }
    }

    // ------------------------------------------------------------------ entities

    fn updateEntities(s: *Sim, dt: f32) void {
        const nests_alive = s.count(.nest);
        var cocci_alive: u32 = 0;
        for (&s.ents, 0..) |*e, idx| {
            e.flash = @max(0, e.flash - dt * 3);
            switch (e.kind) {
                .cocci => {
                    cocci_alive += 1;
                    s.updateCocci(@intCast(idx), dt);
                },
                .nest => {
                    e.timer -= dt;
                    if (e.timer <= 0) e.aux = @max(0, e.aux - 1.6 * dt);
                },
                .anchor => {
                    e.timer -= dt;
                    if (nests_alive > 0 and e.timer <= 0 and e.hp < e.max_hp) {
                        e.hp = @min(e.max_hp, e.hp + 0.3 * dt);
                        if (!s.said.regrow and e.hp < e.max_hp - 0.8) {
                            s.said.regrow = true;
                            s.say(L.see_it_knitting_back);
                        }
                    }
                },
                .embolus => {
                    const fl = s.vein.flowAt(e.pos, s.clock);
                    e.vel = e.vel.add(fl.add(v3(0, 0, 16)).sub(e.vel).scale(1 - @exp(-1.5 * dt)));
                    var bore = false;
                    e.pos = s.vein.collide(e.pos.add(e.vel.scale(dt)), e.radius, &e.sides, &bore).pos;
                    const v = &s.vein.valves[1];
                    if (e.pos.z > v.top() + 2300) {
                        e.kind = .none;
                        s.stats.emboli_escaped += 1;
                        s.stabilise(if (e.radius > 12) -9 else -6);
                        s.sound(.escape, 0, 1);
                        if (!s.said.escaped) {
                            s.said.escaped = true;
                            s.say(L.one_got_past_you);
                        }
                    }
                },
                .neutrophil => {
                    if (e.state == 1) {
                        // knocked loose: drift, then settle back onto the wall
                        e.timer -= dt;
                        e.pos = e.pos.add(e.vel.scale(dt));
                        e.vel = e.vel.scale(@exp(-2 * dt));
                        if (e.timer <= 0) {
                            const l = Vein.local(e.pos);
                            e.end = v3(l.theta, e.pos.z, e.end.z);
                            e.state = 0;
                        }
                    } else {
                        e.end.y += e.end.z * dt * @max(Vein.pump(s.clock), 0);
                        const z = e.end.y;
                        const zone_lo: f32 = if (z < 11000) 6300 else 13400;
                        const zone_hi: f32 = if (z < 11000) 9100 else 17000;
                        if (z > zone_hi) e.end.y = zone_lo;
                        const th = e.end.x;
                        const c = Vein.center(e.end.y);
                        const r = s.vein.wallR(e.end.y, th) - e.radius * 0.85;
                        const target = v3(c.x + r * @cos(th), c.y + r * @sin(th), e.end.y);
                        e.pos = if (e.pos.len2() == 0) target else e.pos.lerp(target, 1 - @exp(-4 * dt));
                    }
                },
                .odd_cell => {
                    if (e.state == 1) {
                        e.timer -= dt;
                        e.pos = e.pos.add(e.vel.scale(dt));
                        e.vel = e.vel.scale(@exp(-2 * dt));
                        if (e.timer <= 0) e.state = 0;
                    }
                },
                .thrombus => {
                    if (s.stage == .lyse_core) {
                        e.pos.z += 38 * dt;
                        const v = &s.vein.valves[1];
                        if (e.pos.z > v.top() + 260) {
                            // it reached the stream
                            e.kind = .none;
                            s.stats.emboli_escaped += 5;
                            s.stabilise(-25);
                            s.sound(.escape, 0, 1);
                            s.urgent(L.its_in_the_stream);
                            s.setStage(.freed);
                        }
                    }
                },
                .infected, .shed, .virion, .commensal, .factory => ch2.updateEntity(s, @intCast(idx), dt),
                .pylori, .colony, .vessel, .grit => ch3.updateEntity(s, @intCast(idx), dt),
                else => {},
            }
        }

        // Colonies shed swimmers while the pilot is near.
        if ((s.stage == .treat) and nests_alive > 0) {
            s.nest_spawn_t -= dt;
            if (s.nest_spawn_t <= 0 and cocci_alive < 7) {
                s.nest_spawn_t = 4.2;
                var pick = s.rng.below(nests_alive);
                for (&s.ents) |*e| {
                    if (e.kind != .nest) continue;
                    if (pick == 0) {
                        _ = s.spawn(.{ .kind = .cocci, .pos = e.pos.add(e.end.scale(55)), .vel = e.end.scale(50), .radius = 2.6, .seed = s.rng.f(), .variant = @intCast(s.rng.below(3)), .timer = 1.0 });
                        break;
                    }
                    pick -= 1;
                }
            }
        }
        if (s.stage == .septum_break) {
            if (s.find(.phlebolith)) |stone| {
                s.stone_spawn_t -= dt;
                if (s.stone_spawn_t <= 0 and cocci_alive < 6 and s.pos.dist(stone.pos) < 700) {
                    s.stone_spawn_t = 3.4;
                    const d = s.pos.sub(stone.pos).norm().add(s.rng.dir().scale(0.6)).norm();
                    _ = s.spawn(.{ .kind = .cocci, .pos = stone.pos.add(d.scale(stone.radius + 6)), .vel = d.scale(45), .radius = 2.6, .seed = s.rng.f(), .variant = @intCast(s.rng.below(3)), .timer = 0.8 });
                    if (!s.said.stone_colony) {
                        s.said.stone_colony = true;
                        s.urgent(L.the_stones_colonised_company);
                    }
                }
            }
        }
    }

    fn updateCocci(s: *Sim, idx: u16, dt: f32) void {
        const e = &s.ents[idx];
        const to = s.pos.sub(e.pos);
        const dist = to.len();
        const dir = to.scale(1 / @max(dist, 1e-3));
        const fl = s.vein.flowAt(e.pos, s.clock);
        e.timer -= dt;
        switch (e.state) {
            0 => { // drift toward the drone
                var want = fl;
                if (dist < 900) {
                    const wob = v3(@sin(s.clock * 2.3 + e.seed * 40), @cos(s.clock * 1.9 + e.seed * 23), @sin(s.clock * 1.4 + e.seed * 11)).scale(22);
                    const approach: f32 = if (dist > 46) 72 else 0;
                    want = want.add(dir.scale(approach)).add(wob);
                }
                e.vel = e.vel.add(want.sub(e.vel).scale(1 - @exp(-3 * dt)));
                if (dist < 62 and e.timer <= 0 and s.windup_lock <= 0) {
                    e.state = 1;
                    e.timer = 0.75;
                    s.windup_lock = 0.45;
                    s.sound(.windup, m.clamp(e.pos.sub(s.pos).dot(s.right()) / 40, -1, 1), 0.8);
                    if (!s.said.windup) {
                        s.said.windup = true;
                        s.urgent(L.its_glowing_shoot_it_or_move);
                    }
                }
            },
            1 => { // wind-up: glows, holds
                e.vel = e.vel.add(fl.sub(e.vel).scale(1 - @exp(-6 * dt)));
                e.aux = 1 - e.timer / 0.75;
                if (e.timer <= 0) {
                    e.state = 2;
                    e.timer = 0.36;
                    e.end = dir; // lunge direction is fixed at release
                    e.aux = 1;
                }
            },
            2 => { // lunge
                e.vel = e.end.scale(430).add(fl);
                if (dist < e.radius + hull_r + 2) {
                    s.burst(e.pos, 12, 90, .{ 1, 0.7, 0.2, 1 }, 2.5, 0.5);
                    e.kind = .none;
                    s.hurtDrone(9);
                    return;
                }
                if (e.timer <= 0) {
                    e.state = 3;
                    e.timer = 1.3;
                    e.aux = 0;
                }
            },
            else => { // recover
                e.vel = e.vel.add(fl.sub(e.vel).scale(1 - @exp(-2.5 * dt)));
                if (e.timer <= 0) {
                    e.state = 0;
                    e.timer = 0.6;
                }
            },
        }
        e.pos = e.pos.add(e.vel.scale(dt));
        // keep inside the lumen
        const l = Vein.local(e.pos);
        const rw = s.vein.wallR(e.pos.z, l.theta) - 6;
        if (l.r > rw) {
            const c = Vein.center(e.pos.z);
            e.pos.x = c.x + l.x * rw / l.r;
            e.pos.y = c.y + l.y * rw / l.r;
        }
    }

    // ------------------------------------------------------------------ script

    fn script(s: *Sim, dt: f32) void {
        switch (s.chapter) {
            1 => return ch2.script(s, dt),
            2 => return ch3.script(s, dt),
            else => {},
        }
        const vn = &s.vein;
        const l = Vein.local(s.pos);
        const rw = vn.wallR(s.pos.z, l.theta);

        if (s.stall_t > 50 and !s.said.stall and s.stage != .freed) {
            s.said.stall = true;
            s.voice.say(L.if_you_want_a_pointer, .chatter);
        }

        switch (s.stage) {
            .needle => {
                if (!s.in_bore) {
                    s.say(L.youre_out);
                    s.setStage(.flow_wall);
                }
            },
            .flow_wall => {
                if (l.r > rw - 130 and !s.in_bore) s.setStage(.flow_core);
            },
            .flow_core => {
                if (l.r < 0.3 * rw) s.setStage(.to_valve1);
            },
            .to_valve1 => {
                if (s.pos.z > vn.valves[0].zb - 1300) s.setStage(.valve1_identify);
            },
            .valve1_identify => {
                // a pilot who flies straight through has read the valve well enough
                if (s.pos.z > vn.valves[0].top() + 150) s.setStage(.neutrophil);
            },
            .valve1_pass => {
                if (s.pos.z > vn.valves[0].top() + 150) s.setStage(.neutrophil);
            },
            .neutrophil => {
                if (s.waypoint == null and s.stage_t > 1) {
                    // point at the nearest roller
                    var best: f32 = 1e9;
                    for (&s.ents) |*e| {
                        if (e.kind != .neutrophil or e.pos.z < 6000 or e.pos.z > 9200) continue;
                        const d = e.pos.dist(s.pos);
                        if (d < best) {
                            best = d;
                            s.waypoint = e.pos;
                        }
                    }
                }
            },
            .staph => {
                if (s.count(.cocci) == 0 and s.stage_t > 1) s.setStage(.tools);
            },
            .tools => {
                const a = s.arms[0].tool;
                const b = s.arms[1].tool;
                const ok = (a == .drill and b == .shoot) or (a == .shoot and b == .drill);
                if (ok and s.waypoint == null) {
                    s.progress();
                    s.say(L.good_the_marker_is_ahead);
                    s.waypoint = if (s.findRing(0)) |e| e.pos else null;
                }
                if (s.atRing(0) and ok) s.setStage(.transit1);
            },
            .v2_approach => {
                const clot = s.find(.thrombus);
                const in_pocket = s.sides.cusp[1][0] == 1 and s.pos.z < vn.valves[1].top() - 200;
                if (in_pocket or (clot != null and s.pos.dist(clot.?.pos) < 800)) s.setStage(.treat);
            },
            .treat => {
                const nests = s.count(.nest);
                const anchors = s.count(.anchor);
                if (nests == 0 and anchors == 0) {
                    s.setStage(.lyse_core);
                } else if (nests > 0) {
                    s.waypoint = s.nearest(.nest);
                } else {
                    s.waypoint = s.nearest(.anchor);
                }
            },
            .lyse_core => {
                s.waypoint = if (s.find(.thrombus)) |e| e.pos else null;
            },
            .freed => {
                if (s.stage_t > 5.5 and s.count(.embolus) == 0) s.mode = .upgrade_card;
                if (s.stage_t > 14) s.mode = .upgrade_card;
            },
            .to_ring2 => {
                if (s.atRing(1)) s.setStage(.transit2);
                if (!s.said.sync_try and s.stats.sync_strikes > 0) {
                    s.said.sync_try = true;
                    s.say(L.thats_it_youll_feel_the_difference);
                }
            },
            .septum_find => {
                if (s.find(.phlebolith)) |e| {
                    if (s.pos.dist(e.pos) < 900 and s.waypoint == null) s.waypoint = e.pos;
                    if (s.pos.z > vn.septum.z - 1500 and s.waypoint == null) s.waypoint = e.pos;
                }
            },
            .septum_break => {},
            .exit => {
                if (s.pos.z > vein_mod.z_exit) {
                    s.say(L.femoral_vein_the_leg_is_done);
                    s.setStage(.done);
                }
            },
            else => {},
        }
    }

    pub fn nearest(s: *Sim, kind: Kind) ?Vec3 {
        var best: f32 = 1e12;
        var out: ?Vec3 = null;
        for (&s.ents) |*e| {
            if (e.kind != kind) continue;
            const p = if (kind == .anchor) e.pos.lerp(e.end, 0.5) else e.pos;
            const d = p.dist(s.pos);
            if (d < best) {
                best = d;
                out = p;
            }
        }
        return out;
    }

    pub fn atRing(s: *Sim, which: u8) bool {
        const e = s.findRing(which) orelse return false;
        return @abs(s.pos.z - e.pos.z) < 60 and s.pos.dist(e.pos) < e.radius * 0.95;
    }

    /// One-line objective for the HUD, as the player `p` describes reads it. `buf` holds the result where it
    /// has numbers or control names in it.
    pub fn objective(s: *const Sim, p: bindings.Prompt, buf: []u8) []const u8 {
        const text: Text = switch (s.stage) {
            .g_arrive, .g_villus, .g_descend, .g_wave, .g_scan, .g_extrude, .g_factory, .g_tether, .g_flume, .g_exit => return ch2.objective(s, p, buf),
            .s_arrive, .s_pits, .s_gradient, .s_wave, .s_swim, .s_margin, .s_cross, .s_cautery, .s_exit => return ch3.objective(s, p, buf),
            .needle => O.needle,
            .flow_wall => O.flow_wall,
            .flow_core => O.flow_core,
            .to_valve1 => O.to_valve1,
            .valve1_identify => O.valve1_identify,
            .valve1_pass => O.valve1_pass,
            .neutrophil => O.neutrophil,
            .staph => return bindings.format(buf, p, O.staph, .{i18n.int(s.count(.cocci))}),
            .tools => if (s.waypoint == null) O.tools else O.transit_marker,
            .transit1, .transit2 => O.transit,
            .v2_approach => O.v2_approach,
            .treat => return bindings.format(buf, p, O.treat, .{ i18n.int(3 - @as(i32, @intCast(s.count(.nest)))), i18n.int(4 - @as(i32, @intCast(s.count(.anchor)))), i18n.int(s.count(.embolus)) }),
            .lyse_core => O.lyse_core,
            .freed => O.freed,
            .to_ring2 => O.to_ring2,
            .septum_find => O.septum_find,
            .septum_break => return bindings.format(buf, p, O.septum_break, .{i18n.int(@as(i32, @intFromFloat(100 * (1 - (if (s.findConst(.phlebolith)) |e| e.hp / e.max_hp else 0)))))}),
            .exit => O.exit,
            .done => O.done,
        };
        return bindings.resolve(buf, text, p);
    }

    pub fn grade(s: *const Sim) u8 {
        var score: f32 = s.stability;
        score -= @as(f32, @floatFromInt(s.stats.emboli_escaped)) * 4;
        score -= @as(f32, @floatFromInt(s.stats.friendly_fire)) * 2;
        score -= @as(f32, @floatFromInt(s.stats.retries)) * 5;
        switch (s.chapter) {
            1 => score -= ch2.gradePenalty(s),
            2 => score -= ch3.gradePenalty(s),
            else => {},
        }
        if (score >= 85) return 'A';
        if (score >= 70) return 'B';
        if (score >= 50) return 'C';
        return 'D';
    }

    /// Atlas entries that belong to this chapter: [first, end).
    pub fn atlasRange(s: *const Sim) [2]usize {
        const first = [_]usize{ 0, @intFromEnum(Topic.villus), @intFromEnum(Topic.gastric_pit), Topic.count };
        return .{ first[s.chapter], first[s.chapter + 1] };
    }

    pub fn atlasTotal(s: *const Sim) u32 {
        const r = s.atlasRange();
        return @intCast(r[1] - r[0]);
    }

    pub fn atlasCount(s: *const Sim) u32 {
        const r = s.atlasRange();
        var n: u32 = 0;
        for (s.atlas[r[0]..r[1]]) |b| {
            if (b) n += 1;
        }
        return n;
    }
};

// ---------------------------------------------------------------------- geometry helpers

pub fn raySphere(o: Vec3, d: Vec3, c: Vec3, r: f32) ?f32 {
    const oc = o.sub(c);
    const b = oc.dot(d);
    const cc = oc.len2() - r * r;
    if (cc <= 0) return 0;
    const disc = b * b - cc;
    if (disc < 0 or b > 0) return null;
    return -b - @sqrt(disc);
}

pub fn closestOnSegment(p: Vec3, a: Vec3, b: Vec3) Vec3 {
    const ab = b.sub(a);
    const t = m.sat(p.sub(a).dot(ab) / @max(ab.len2(), 1e-6));
    return a.add(ab.scale(t));
}

/// Distance along the ray at which it first comes within `r` of segment ab.
pub fn raySegment(o: Vec3, d: Vec3, a: Vec3, b: Vec3, r: f32) ?f32 {
    const ab = b.sub(a);
    const ao = o.sub(a);
    const dd = d.dot(ab);
    const ab2 = ab.len2();
    const denom = ab2 - dd * dd;
    var t: f32 = 0;
    if (denom > 1e-6) t = (dd * ao.dot(ab) - ab2 * ao.dot(d)) / denom;
    if (t < 0) t = 0;
    const p = o.add(d.scale(t));
    const q = closestOnSegment(p, a, b);
    // re-project the closest segment point onto the ray
    const t2 = @max(0, q.sub(o).dot(d));
    const p2 = o.add(d.scale(t2));
    const dist = p2.dist(q);
    if (dist > r) return null;
    return @max(0, t2 - @sqrt(@max(0, r * r - dist * dist)));
}

test "ray helpers" {
    try std.testing.expectApproxEqAbs(@as(f32, 8), raySphere(v3(0, 0, 0), v3(0, 0, 1), v3(0, 0, 10), 2).?, 1e-4);
    try std.testing.expect(raySphere(v3(0, 0, 0), v3(0, 0, 1), v3(5, 0, 10), 2) == null);
    const t = raySegment(v3(0, 0, 0), v3(0, 0, 1), v3(-10, 0, 20), v3(10, 0, 20), 3).?;
    try std.testing.expectApproxEqAbs(@as(f32, 17), t, 1e-3);
    try std.testing.expect(raySegment(v3(0, 0, 0), v3(0, 0, 1), v3(-10, 8, 20), v3(10, 8, 20), 3) == null);
}

test "a fresh run starts in the cannula with the world populated" {
    const s = Sim.init();
    try std.testing.expect(s.in_bore);
    try std.testing.expectEqual(@as(u32, 3), s.count(.nest));
    try std.testing.expectEqual(@as(u32, 4), s.count(.anchor));
    try std.testing.expectEqual(@as(u32, 1), s.count(.thrombus));
    try std.testing.expectEqual(@as(u32, 3), s.count(.odd_cell));
    try std.testing.expect(s.vein.inBore(s.pos));
}

test "biofilm absorbs rounds until the drill opens it; both arms together kill it" {
    var s = Sim.init();
    s.in_bore = false;
    s.stage = .treat;
    var nest_idx: u16 = 0;
    for (&s.ents, 0..) |*e, i| {
        if (e.kind == .nest) {
            nest_idx = @intCast(i);
            break;
        }
    }
    const nest = &s.ents[nest_idx];
    // park in front of the dome, looking at it
    s.pos = nest.pos.add(nest.end.scale(nest.radius + 14));
    const to = nest.pos.sub(s.pos).norm();
    s.yaw = std.math.atan2(to.x, to.z);
    s.pitch = std.math.asin(to.y);
    s.sides = .{};
    s.arms[0].tool = .shoot;
    s.arms[1].tool = .drill;

    // rounds alone do nothing
    var c: Controls = .{ .arm = .{ true, false } };
    for (0..240) |_| s.update(c, 1.0 / 120.0);
    try std.testing.expectEqual(@as(f32, 8), s.ents[nest_idx].hp);
    try std.testing.expect(s.said.absorb);

    // drill and shoot at once
    c = .{ .arm = .{ true, true } };
    var frames: usize = 0;
    while (s.ents[nest_idx].kind == .nest and frames < 2000) : (frames += 1) {
        // hold the reticle on the dome whatever the swimmers do
        const d = s.ents[nest_idx].pos.sub(s.pos).norm();
        s.yaw = std.math.atan2(d.x, d.z);
        s.pitch = std.math.asin(d.y);
        s.hull = 100;
        s.update(c, 1.0 / 120.0);
    }
    try std.testing.expect(s.ents[nest_idx].kind == .none);
    try std.testing.expect(s.stats.dual_time > 0.5);
}

test "sync punch needs the upgrade and both arms inside the window" {
    var s = Sim.init();
    s.in_bore = false;
    s.stage = .septum_break;
    s.station = 2;
    const stone = s.find(.phlebolith).?;
    s.pos = stone.pos.add(v3(0, 0, -(stone.radius + 12)));
    s.yaw = 0;
    s.pitch = 0;
    s.sides = .{};
    s.arms[0].tool = .punch;
    s.arms[1].tool = .punch;
    const dt: f32 = 1.0 / 120.0;

    // without the upgrade two punches are just two punches
    s.update(.{ .arm = .{ true, true } }, dt);
    for (0..80) |_| s.update(.{}, dt);
    try std.testing.expectEqual(@as(f32, 48), s.find(.phlebolith).?.hp);
    try std.testing.expectEqual(@as(u32, 0), s.stats.sync_strikes);

    // with it, the same input is one Sync Strike
    s.has_sync = true;
    s.update(.{ .arm = .{ true, true } }, dt);
    for (0..80) |_| s.update(.{}, dt);
    try std.testing.expectEqual(@as(f32, 38), s.find(.phlebolith).?.hp);
    try std.testing.expectEqual(@as(u32, 1), s.stats.sync_strikes);

    // arms triggered too far apart do not sync
    s.update(.{ .arm = .{ true, false } }, dt);
    for (0..30) |_| s.update(.{}, dt);
    s.update(.{ .arm = .{ false, true } }, dt);
    for (0..80) |_| s.update(.{}, dt);
    try std.testing.expectEqual(@as(f32, 36), s.find(.phlebolith).?.hp);
    try std.testing.expectEqual(@as(u32, 1), s.stats.sync_strikes);
}

test "rounds into the wall cost the patient" {
    var s = Sim.init();
    s.in_bore = false;
    const c = Vein.center(2500);
    s.pos = c.add(v3(s.vein.wallR(2500, 0) - 120, 0, 0));
    s.yaw = m.pi / 2.0; // face +X, the wall
    s.sides = .{};
    const before = s.stability;
    for (0..120) |_| s.update(.{ .arm = .{ true, false } }, 1.0 / 120.0);
    try std.testing.expect(s.stats.tissue_hits > 0);
    try std.testing.expect(s.stability < before);
}

/// The cardinal numbers the script spells out, as Marín says them at the start of a sentence or inside one.
const number_words = [_]struct { n: u32, en: []const u8, uk: []const u8 }{
    .{ .n = 3, .en = "three", .uk = "три" },
    .{ .n = 10, .en = "ten", .uk = "десять" },
    .{ .n = 11, .en = "eleven", .uk = "одинадцять" },
    .{ .n = 12, .en = "twelve", .uk = "дванадцять" },
    .{ .n = 17, .en = "seventeen", .uk = "сімнадцять" },
    .{ .n = 18, .en = "eighteen", .uk = "вісімнадцять" },
    .{ .n = 19, .en = "nineteen", .uk = "дев’ятнадцять" },
};

/// True if `word` is one of the words of `text`, with either case of its first letter (Latin or Cyrillic).
fn saysWord(text: []const u8, word: []const u8) bool {
    var capital: [64]u8 = undefined;
    @memcpy(capital[0..word.len], word);
    if (word[0] >= 'a' and word[0] <= 'z') {
        capital[0] = word[0] - 32;
    } else if (word[0] == 0xD0 and word[1] >= 0xB0 and word[1] <= 0xBF) {
        capital[1] = word[1] - 0x20; // а..п
    } else if (word[0] == 0xD1 and word[1] >= 0x80 and word[1] <= 0x8F) {
        capital[0] = 0xD0; // р..я
        capital[1] = word[1] + 0x20;
    }
    var it = std.mem.tokenizeAny(u8, text, " .,;:!?");
    while (it.next()) |tok| {
        if (std.mem.eql(u8, tok, word) or std.mem.eql(u8, tok, capital[0..word.len])) return true;
    }
    return false;
}

fn wordFor(n: u32) !@TypeOf(number_words[0]) {
    for (number_words) |w| {
        if (w.n == n) return w;
    }
    std.debug.print("no number word for {d}: add it to number_words\n", .{n});
    return error.TestUnexpectedResult;
}

test "the distance Marín gives for each transit is the distance the HUD will show it cover" {
    // The geometry: marker to arrival, read off the same function the HUD's location readout uses.
    try std.testing.expectApproxEqAbs(@as(f32, 11.37), Sim.transitCm(0), 0.01);
    try std.testing.expectApproxEqAbs(@as(f32, 17.87), Sim.transitCm(1), 0.01);
    for (0..2) |which| {
        const cm: u32 = @intFromFloat(@round(Sim.transitCm(which)));
        const w = try wordFor(cm);
        const line = L.tempo_link_down[which];
        try std.testing.expect(saysWord(line.en, w.en));
        try std.testing.expect(saysWord(line.uk, w.uk));
        // and names no other distance: no other number word stands before "centimetres"
        for (number_words) |other| {
            if (other.n == cm or other.n == 3) continue;
            try std.testing.expect(!saysWord(line.en, other.en));
            try std.testing.expect(!saysWord(line.uk, other.uk));
        }
    }

    // The same thing flown: enter each transit at its marker and compare what the HUD reads before and
    // after with the line that was spoken on the way.
    var s = Sim.init();
    s.in_bore = false;
    for (0..2) |which| {
        s.mode = .playing;
        s.station = @intCast(which);
        s.pos = Vein.center(Sim.transits[which].from_z);
        const before = s.locationCm();
        s.setStage(if (which == 0) .transit1 else .transit2);
        try std.testing.expectEqual(Mode.transit, s.mode);
        const spoken = s.voice.current.?;
        try std.testing.expectEqualStrings(L.tempo_link_down[which].en, spoken.en);
        var guard: usize = 0;
        while (s.mode == .transit and guard < 2000) : (guard += 1) s.update(.{}, 1.0 / 120.0);
        try std.testing.expectEqual(Mode.playing, s.mode);
        const covered = before - s.locationCm();
        const w = try wordFor(@intFromFloat(@round(covered)));
        try std.testing.expect(saysWord(spoken.en, w.en));
        try std.testing.expect(saysWord(spoken.uk, w.uk));
    }
}

test "the upgrade card and Marín quote the Sync Strike's real multipliers" {
    // What the rule does, measured: one punch against two in sync on the stone, one round against a lance.
    var s = Sim.init();
    s.in_bore = false;
    s.stage = .septum_break;
    s.station = 2;
    const stone = s.find(.phlebolith).?;
    s.pos = stone.pos.add(v3(0, 0, -(stone.radius + 12)));
    s.yaw = 0;
    s.pitch = 0;
    s.sides = .{};
    s.arms[0].tool = .punch;
    s.arms[1].tool = .punch;
    const dt: f32 = 1.0 / 120.0;
    const hp0 = stone.hp;
    s.update(.{ .arm = .{ true, false } }, dt);
    for (0..80) |_| s.update(.{}, dt);
    const single = hp0 - s.find(.phlebolith).?.hp;
    s.has_sync = true;
    s.update(.{ .arm = .{ true, true } }, dt);
    for (0..80) |_| s.update(.{}, dt);
    const synced = hp0 - single - s.find(.phlebolith).?.hp;
    try std.testing.expectEqual(@as(u32, 1), s.stats.sync_strikes);
    try std.testing.expectEqual(sync_punch_factor, synced / single);

    // The words. "So many times as hard" for the punch, a count of rounds for the lance, each spelled out
    // in both languages on the card, and the punch figure again in the line that announces the upgrade.
    const Times = struct { n: u32, en: []const u8, uk: []const u8 };
    const times = [_]Times{
        .{ .n = 3, .en = "three times", .uk = "утричі" },
        .{ .n = 5, .en = "five times", .uk = "уп’ятеро" },
        .{ .n = 10, .en = "ten times", .uk = "удесятеро" },
    };
    const punch: Times = for (times) |t| {
        if (t.n == @as(u32, @intFromFloat(sync_punch_factor))) break t;
    } else return error.TestUnexpectedResult;
    const lance = try wordFor(@intFromFloat(lance_factor));
    const card = strings.card.sync_body;
    const line = L.sync_servo_is_live;
    inline for (.{ card, line }) |t| {
        try std.testing.expect(std.mem.indexOf(u8, t.en, punch.en) != null);
        try std.testing.expect(std.mem.indexOf(u8, t.uk, punch.uk) != null);
        // and no other multiplier
        for (times) |other| {
            if (other.n == punch.n) continue;
            try std.testing.expect(std.mem.indexOf(u8, t.en, other.en) == null);
            try std.testing.expect(std.mem.indexOf(u8, t.uk, other.uk) == null);
        }
    }
    try std.testing.expect(std.mem.indexOf(u8, card.en, lance.en) != null);
    try std.testing.expect(std.mem.indexOf(u8, card.uk, lance.uk) != null);
}
