//! Application state above the simulation: screens, checkpoints, the save file, and the decorative blood
//! cells the pilot's display leaves in after filtering.

const std = @import("std");
const m = @import("math.zig");
const game = @import("game.zig");
const guide = @import("guide.zig");
const vein_mod = @import("vein.zig");
const util = @import("util.zig");
const campaign = @import("campaign.zig");
const bot_mod = @import("bot.zig");
const Vec3 = m.Vec3;
const v3 = m.v3;
const Vein = vein_mod.Vein;

pub const Screen = enum { title, briefing, play, pause, map };

pub const UiInput = struct {
    confirm: bool = false,
    back: bool = false,
    up: bool = false,
    down: bool = false,
    map: bool = false,
    retry: bool = false,
    restart: bool = false,
    quit_to_title: bool = false,
};

pub const Save = struct {
    ch1_done: bool = false,
    grade: u8 = '-',
    emboli: u32 = 0,
    stability: f32 = 0,
    marrow: bool = false,
    atlas: u32 = 0,
    time: f32 = 0,
    ch2_done: bool = false,
    grade2: u8 = '-',
};

pub const CellKind = enum(u8) { red, platelet, white };

pub const Cell = struct {
    pos: Vec3 = .{},
    axis: Vec3 = .{ .y = 1 },
    phase: f32 = 0,
    spin: f32 = 0,
    kind: CellKind = .red,
    scale: f32 = 3.9,
    tint: f32 = 0,
    visible: bool = false,
};

pub const near_count = 1500;
pub const far_count = 3200;
const near_half = v3(260, 260, 300);
const far_half = v3(1500, 1500, 2100);

pub const App = struct {
    screen: Screen = .title,
    sim: game.Sim = undefined,
    checkpoint: game.Sim = undefined,
    near: [near_count]Cell = undefined,
    far: [far_count]Cell = undefined,
    rng: m.Rng = m.Rng.init(99),
    time: f32 = 0,
    screen_t: f32 = 0,
    save: Save = .{},
    map_sel: usize = 0,
    briefing_page: usize = 0,
    sway: [2]f32 = .{ 0, 0 },
    bob: f32 = 0,
    bot: ?bot_mod.Bot = null,
    /// Index into campaign.chapters of the chapter being flown.
    chapter: u8 = 0,
    /// Set by --chapter: every playable chapter can be entered regardless of the save.
    unlock_all: bool = false,
    recorded: bool = false,
    /// Set when rendering the app icon: the title backdrop with a mark instead of text.
    icon_mode: bool = false,
    /// Set when the pointer should be captured (play) or released (menus).
    want_capture: bool = false,
    last_voice_serial: u32 = 0,
    comm_chirp: bool = false,
    save_path: [512]u8 = undefined,
    save_path_len: usize = 0,

    /// `persist` is false for bot-driven and scripted runs, which must never touch the player's save.
    pub fn init(app: *App, persist: bool) void {
        app.* = .{};
        app.sim = game.Sim.init();
        app.parkForTitle();
        app.checkpoint = app.sim;
        app.seedCells();
        if (persist) {
            app.locateSave();
            app.loadSave();
        }
    }

    /// Title backdrop: hang in the stream upstream of the first valve.
    fn parkForTitle(app: *App) void {
        const s = &app.sim;
        s.in_bore = false;
        s.pos = Vein.center(2500).add(v3(-380, 260, 0));
        s.yaw = -0.16;
        s.pitch = -0.1;
        s.voice.clear();
    }

    fn locateSave(app: *App) void {
        const home = util.env("HOME") orelse return;
        const dir = std.fmt.bufPrintSentinel(&app.save_path, "{s}/Library/Application Support/Dentro del cuerpo", .{home}, 0) catch return;
        util.makeDir(dir.ptr);
        const full = std.fmt.bufPrintSentinel(&app.save_path, "{s}/Library/Application Support/Dentro del cuerpo/save.txt", .{home}, 0) catch return;
        app.save_path_len = full.len;
    }

    fn loadSave(app: *App) void {
        if (app.save_path_len == 0) return;
        var buf: [512]u8 = undefined;
        const path: [*:0]const u8 = @ptrCast(&app.save_path);
        const data = util.readFile(path, &buf) orelse return;
        var it = std.mem.tokenizeAny(u8, data, " \n");
        var vals: [9]f32 = @splat(0);
        var n: usize = 0;
        while (it.next()) |tok| {
            if (n >= vals.len) break;
            vals[n] = std.fmt.parseFloat(f32, tok) catch 0;
            n += 1;
        }
        if (n < 7) return;
        app.save = .{
            .ch1_done = vals[0] > 0.5,
            .grade = @intFromFloat(m.clamp(vals[1], 32, 126)),
            .emboli = @intFromFloat(@max(0, vals[2])),
            .stability = vals[3],
            .marrow = vals[4] > 0.5,
            .atlas = @intFromFloat(@max(0, vals[5])),
            .time = vals[6],
            .ch2_done = vals[7] > 0.5,
            .grade2 = if (n >= 9) @intFromFloat(m.clamp(vals[8], 32, 126)) else '-',
        };
    }

    fn writeSave(app: *App) void {
        if (app.save_path_len == 0) return;
        var buf: [256]u8 = undefined;
        const sv = app.save;
        const text = std.fmt.bufPrint(&buf, "{d} {d} {d} {d:.1} {d} {d} {d:.1} {d} {d}\n", .{ @intFromBool(sv.ch1_done), sv.grade, sv.emboli, sv.stability, @intFromBool(sv.marrow), sv.atlas, sv.time, @intFromBool(sv.ch2_done), sv.grade2 }) catch return;
        const path: [*:0]const u8 = @ptrCast(&app.save_path);
        _ = util.writeFile(path, text);
    }

    // ------------------------------------------------------------------ decorative cells

    fn seedCells(app: *App) void {
        for (&app.near) |*c| app.respawn(c, near_half, true, 0);
        for (&app.far) |*c| app.respawn(c, far_half, true, 0);
    }

    fn respawn(app: *App, c: *Cell, half: Vec3, anywhere: bool, face_sign: f32) void {
        const p = app.sim.pos;
        var rel = v3(app.rng.range(-half.x, half.x), app.rng.range(-half.y, half.y), app.rng.range(-half.z, half.z));
        if (!anywhere) rel.z = face_sign * half.z * app.rng.range(0.85, 1.0);
        c.pos = p.add(rel);
        c.axis = app.rng.dir();
        c.phase = app.rng.range(0, m.tau);
        c.spin = app.rng.range(0.2, 1.1);
        const k = app.rng.f();
        if (app.sim.chapter == 1) {
            // chyme: fat droplets, flakes of food debris, the odd glob of mucus
            if (k < 0.72) {
                c.kind = .red;
                c.scale = app.rng.range(0.9, 4.2);
            } else if (k < 0.97) {
                c.kind = .platelet;
                c.scale = app.rng.range(1.0, 2.2);
            } else {
                c.kind = .white;
                c.scale = app.rng.range(4.0, 7.5);
            }
        } else if (k < 0.93) {
            c.kind = .red;
            c.scale = app.rng.range(3.7, 4.1);
        } else if (k < 0.992) {
            c.kind = .platelet;
            c.scale = app.rng.range(1.1, 1.6);
        } else {
            c.kind = .white;
            c.scale = app.rng.range(5.2, 6.6);
        }
        c.tint = app.rng.f();
        app.validate(c);
    }

    fn validate(app: *App, c: *Cell) void {
        if (app.sim.chapter == 1) {
            const gut = @import("gut.zig");
            c.visible = c.pos.z > gut.z_min and c.pos.z < gut.z_max and app.sim.gut.clear(c.pos, c.scale + 3);
            return;
        }
        const vn = &app.sim.vein;
        const l = Vein.local(c.pos);
        const n = &vn.needle;
        const a = n.axial(c.pos);
        const in_needle = a < 0 and a > -vein_mod.Needle.len and n.radial(c.pos).len() < vein_mod.Needle.outer + 6;
        c.visible = l.r < vn.wallR(c.pos.z, l.theta) - c.scale - 4 and !in_needle and c.pos.z > vein_mod.z_min + 100 and c.pos.z < vein_mod.z_max - 100;
        // nothing drifts through the scar web or the stone
        if (@abs(c.pos.z - vn.septum.z) < 60) c.visible = false;
    }

    fn updateCells(app: *App, dt: f32) void {
        const p = app.sim.pos;
        inline for (.{ &app.near, &app.far }, .{ near_half, far_half }) |cells, half| {
            for (cells) |*c| {
                if (c.visible) {
                    c.pos = c.pos.add(app.sim.worldFlow(c.pos).scale(dt));
                    c.phase += c.spin * dt;
                }
                const rel = c.pos.sub(p);
                if (@abs(rel.x) > half.x or @abs(rel.y) > half.y) {
                    app.respawn(c, half, true, 0);
                } else if (rel.z > half.z) {
                    app.respawn(c, half, false, -1);
                } else if (rel.z < -half.z) {
                    app.respawn(c, half, false, 1);
                } else if (c.visible) {
                    app.validate(c);
                    if (!c.visible) app.respawn(c, half, true, 0);
                } else if (app.rng.f() < dt * 2) {
                    app.respawn(c, half, true, 0);
                }
            }
        }
    }

    /// Decorative cell under the reticle, so the guide can identify erythrocytes and platelets too.
    fn ambientFocus(app: *App) ?game.Focus {
        const s = &app.sim;
        const o = s.pos;
        const d = s.forward();
        var best: f32 = 140;
        var out: ?game.Focus = null;
        for (&app.near) |*c| {
            if (!c.visible) continue;
            const t = game.raySphere(o, d, c.pos, c.scale * 0.9) orelse continue;
            if (t < best and t > 6) {
                best = t;
                if (s.chapter == 1 and c.kind != .red) continue;
                out = .{ .dist = t, .point = o.add(d.scale(t)), .topic = switch (c.kind) {
                    .red => if (s.chapter == 1) .lipid_droplet else .red_cell,
                    .platelet => .platelet,
                    .white => .neutrophil,
                } };
            }
        }
        return out;
    }

    // ------------------------------------------------------------------ flow of screens

    pub fn chapterDone(app: *const App, i: usize) bool {
        return (i == 0 and app.save.ch1_done) or (i == 1 and app.save.ch2_done);
    }

    pub fn chapterUnlocked(app: *const App, i: usize) bool {
        if (!campaign.chapters[i].playable) return false;
        return i == 0 or app.unlock_all or app.chapterDone(i - 1);
    }

    fn recordCompletion(app: *App) void {
        const s = &app.sim;
        if (app.chapter == 1) {
            if (!app.save.ch2_done or s.grade() < app.save.grade2) app.save.grade2 = s.grade();
            app.save.ch2_done = true;
        } else {
            if (!app.save.ch1_done or s.grade() <= app.save.grade or app.save.grade == '-') {
                app.save.grade = s.grade();
                app.save.emboli = s.stats.emboli_escaped;
                app.save.stability = s.stability;
                app.save.time = s.stats.time;
            }
            app.save.ch1_done = true;
            app.save.marrow = app.save.marrow or s.hidden_unlocked;
        }
        app.writeSave();
    }

    pub fn startChapter(app: *App, retries: u32) void {
        app.recorded = false;
        app.sim = game.Sim.initChapter(app.chapter);
        app.sim.stats.retries = retries;
        app.checkpoint = app.sim;
        app.seedCells();
        app.screen = .play;
        app.screen_t = 0;
        app.want_capture = true;
        if (app.bot != null) app.bot = .{};
    }

    fn toTitle(app: *App) void {
        app.sim = game.Sim.init();
        app.parkForTitle();
        app.seedCells();
        app.screen = .title;
        app.screen_t = 0;
        app.want_capture = false;
    }

    pub fn step(app: *App, controls_in: game.Controls, ui: UiInput, dt: f32) void {
        app.time += dt;
        app.screen_t += dt;
        app.comm_chirp = false;
        var controls = controls_in;

        switch (app.screen) {
            .title => {
                app.sim.clock += dt;
                app.sim.vein.stepValves(app.sim.clock, dt);
                app.sim.yaw = -0.16 + 0.05 * @sin(app.time * 0.21);
                app.sim.pitch = -0.1 + 0.03 * @sin(app.time * 0.17);
                app.updateCells(dt);
                if (ui.confirm) {
                    app.chapter = 0;
                    app.screen = .briefing;
                    app.screen_t = 0;
                    app.briefing_page = 0;
                } else if (ui.map) {
                    app.screen = .map;
                    app.screen_t = 0;
                }
            },
            .briefing => {
                app.sim.clock += dt;
                app.sim.vein.stepValves(app.sim.clock, dt);
                app.updateCells(dt);
                if (ui.confirm) {
                    app.briefing_page += 1;
                    app.screen_t = 0;
                    if (app.briefing_page >= briefing_pages.len) app.startChapter(0);
                } else if (ui.back) {
                    app.screen = .title;
                }
            },
            .map => {
                app.sim.clock += dt;
                app.updateCells(dt);
                if (ui.down) app.map_sel = (app.map_sel + 1) % campaign.chapters.len;
                if (ui.up) app.map_sel = (app.map_sel + campaign.chapters.len - 1) % campaign.chapters.len;
                if (ui.confirm and app.chapterUnlocked(app.map_sel)) {
                    app.chapter = @intCast(app.map_sel);
                    if (app.chapter == 0) {
                        app.screen = .briefing;
                        app.briefing_page = 0;
                        app.screen_t = 0;
                    } else {
                        app.startChapter(0);
                    }
                } else if (ui.back) {
                    app.toTitle();
                }
            },
            .pause => {
                if (ui.back or ui.confirm) {
                    app.screen = .play;
                    app.want_capture = true;
                } else if (ui.retry) {
                    app.restoreCheckpoint();
                    app.screen = .play;
                    app.want_capture = true;
                } else if (ui.restart) {
                    app.startChapter(app.sim.stats.retries + 1);
                } else if (ui.quit_to_title) {
                    app.toTitle();
                }
            },
            .play => {
                const s = &app.sim;
                if (ui.back and s.mode != .complete) {
                    app.screen = .pause;
                    app.want_capture = false;
                    return;
                }
                if (app.bot) |*b| controls = b.think(s, dt);
                s.ambient_focus = app.ambientFocus();
                switch (s.mode) {
                    .dead => if (ui.confirm or ui.retry or (app.bot != null and app.screen_t > 1)) app.restoreCheckpoint(),
                    .lost => if (ui.confirm or ui.retry) app.startChapter(s.stats.retries + 1),
                    .complete => {
                        if (!app.recorded) {
                            app.recorded = true;
                            app.recordCompletion();
                        }
                        app.want_capture = false;
                        if (ui.confirm) {
                            const next: usize = @as(usize, app.chapter) + 1;
                            app.chapter = 0;
                            app.toTitle();
                            app.screen = .map;
                            app.map_sel = next;
                        }
                    },
                    else => {},
                }
                s.update(controls, dt);
                if (s.want_checkpoint) {
                    s.want_checkpoint = false;
                    s.hull = 100;
                    s.checkpoint_toast = 2.5;
                    s.sound(.checkpoint, 0, 1);
                    app.checkpoint = s.*;
                }
                if (s.voice.serial != app.last_voice_serial) {
                    app.last_voice_serial = s.voice.serial;
                    app.comm_chirp = true;
                }
                app.updateCells(dt);

                // arm sway follows the look input and speed
                app.sway[0] = m.approach(app.sway[0], m.clamp(controls.look[0] * 40, -1, 1), 8, dt);
                app.sway[1] = m.approach(app.sway[1], m.clamp(controls.look[1] * 40, -1, 1), 8, dt);
                app.bob += dt * (1.5 + s.vrel.len() / 90.0);
            },
        }
    }

    fn restoreCheckpoint(app: *App) void {
        const stats = app.sim.stats;
        app.sim = app.checkpoint;
        app.sim.stats.retries = stats.retries + 1;
        app.sim.stats.time = stats.time;
        app.sim.voice.clear();
        app.sim.voice.say("Link re-established. You're back at the last checkpoint.", .normal);
        app.seedCells();
        app.screen_t = 0;
        if (app.bot != null) app.bot = .{};
    }
};

pub const briefing_pages = [_][]const u8{
    "Patient: 58, colloid cyst of the third ventricle. It plugs the foramina of Monro without warning; the next time may be the last. She is septic from an infected clot in her right leg, and she will not survive open surgery.\n\nSo we go in through the leg.",
    "You fly a drone the size of a red blood cell: eight micrometres. Two arms, each fitted with a punch, a drill or a lytic emitter, each on its own trigger.\n\nYour display removes ninety-nine red cells in a hundred, or blood would be a wall. Your link runs at one-hundredth speed, so a second of your time is ten milliseconds of hers.",
    "Every stop between here and the brain removes something that would kill her before the operation, and teaches the drone something it needs at the end. First stop is the clot.\n\nI'm Elena Marín. I'll be on comms the whole way. Point at anything and press T — I'll tell you what it is.",
};

test "cells stay inside the lumen" {
    const app = try std.testing.allocator.create(App);
    defer std.testing.allocator.destroy(app);
    app.init(false);
    for (0..120) |_| app.step(.{}, .{}, 1.0 / 60.0);
    var visible: usize = 0;
    for (&app.far) |*c| {
        if (!c.visible) continue;
        visible += 1;
        const l = Vein.local(c.pos);
        try std.testing.expect(l.r < app.sim.vein.wallR(c.pos.z, l.theta));
    }
    try std.testing.expect(visible > 1000);
}

test "both failure states have a way back" {
    const app = try std.testing.allocator.create(App);
    defer std.testing.allocator.destroy(app);
    const dt: f32 = 1.0 / 60.0;
    const first = [_]game.Stage{ .needle, .g_arrive };
    for (first, 0..) |first_stage, ch| {
        app.init(false);
        app.chapter = @intCast(ch);
        app.startChapter(0);
        for (0..30) |_| app.step(.{}, .{}, dt);

        // Drone destroyed: the link drops, R relaunches from the checkpoint with a whole hull.
        app.sim.hurtDrone(1000);
        for (0..5) |_| app.step(.{}, .{}, dt);
        try std.testing.expectEqual(game.Mode.dead, app.sim.mode);
        app.step(.{}, .{ .retry = true }, dt);
        try std.testing.expectEqual(game.Mode.playing, app.sim.mode);
        try std.testing.expectEqual(@as(f32, 100), app.sim.hull);
        try std.testing.expectEqual(@as(u32, 1), app.sim.stats.retries);

        // Patient lost: the chapter restarts from its first stage, and the relaunch is still counted.
        app.sim.stability = 0;
        for (0..5) |_| app.step(.{}, .{}, dt);
        try std.testing.expectEqual(game.Mode.lost, app.sim.mode);
        app.step(.{}, .{ .confirm = true }, dt);
        try std.testing.expectEqual(game.Mode.playing, app.sim.mode);
        try std.testing.expectEqual(first_stage, app.sim.stage);
        try std.testing.expectEqual(@as(u8, @intCast(ch)), app.sim.chapter);
        try std.testing.expect(app.sim.stability > 50);
        try std.testing.expectEqual(@as(u32, 2), app.sim.stats.retries);
    }
}
