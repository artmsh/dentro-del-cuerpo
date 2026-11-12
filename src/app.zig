//! Application state above the simulation: screens, checkpoints, the save file, and the decorative blood
//! cells the pilot's display leaves in after filtering.

const std = @import("std");
const m = @import("math.zig");
const game = @import("game.zig");
const guide = @import("guide.zig");
const vein_mod = @import("vein.zig");
const util = @import("util.zig");
const paths = @import("os/paths.zig");
const campaign = @import("campaign.zig");
const bot_mod = @import("bot.zig");
const i18n = @import("i18n.zig");
const strings = @import("strings.zig");
const bindings = @import("bindings.zig");
const Lang = i18n.Lang;

/// The game's name. It is Spanish in every language.
pub const title = "Dentro del cuerpo";
const Vec3 = m.Vec3;
const v3 = m.v3;
const Vein = vein_mod.Vein;

pub const Screen = enum { title, briefing, play, pause, map };

pub const UiInput = struct {
    confirm: bool = false,
    /// The keyboard's Esc: back out of a menu, and pause or resume the game.
    back: bool = false,
    /// A controller splits Esc in two, because its back button is also the one that descends: `cancel`
    /// backs out of a menu and does nothing while flying, `pause` pauses and resumes and does nothing else.
    cancel: bool = false,
    pause: bool = false,
    up: bool = false,
    down: bool = false,
    /// Change the value of the entry under the selection (the language).
    left: bool = false,
    right: bool = false,
    map: bool = false,
    retry: bool = false,
    restart: bool = false,
    quit_to_title: bool = false,
    /// Switch to the next language (title and pause screens).
    language: bool = false,
};

/// The entries of the pause menu, top to bottom. Each has a key of its own on the keyboard; all of them
/// can be selected with up and down and chosen with confirm, which is how a controller reaches them.
pub const PauseItem = enum(u8) {
    resume_game,
    retry,
    restart,
    leave,
    language,

    pub const count = @typeInfo(PauseItem).@"enum".field_names.len;
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
    /// The language the player picked in the game; null until they pick one, so the system's preference
    /// keeps applying.
    lang: ?Lang = null,

    /// The file is one line of space-separated values in field order. Fields were appended over time, so a
    /// file may stop after any field from `time` on; what is missing keeps its default.
    pub fn parse(data: []const u8) ?Save {
        var it = std.mem.tokenizeAny(u8, data, " \r\n");
        var toks: [10][]const u8 = undefined;
        var n: usize = 0;
        while (it.next()) |tok| {
            if (n >= toks.len) break;
            toks[n] = tok;
            n += 1;
        }
        if (n < 7) return null;
        var vals: [9]f32 = @splat(0);
        for (toks[0..@min(n, 9)], 0..) |tok, i| vals[i] = std.fmt.parseFloat(f32, tok) catch 0;
        return .{
            .ch1_done = vals[0] > 0.5,
            .grade = @intFromFloat(m.clamp(vals[1], 32, 126)),
            .emboli = @intFromFloat(@max(0, vals[2])),
            .stability = vals[3],
            .marrow = vals[4] > 0.5,
            .atlas = @intFromFloat(@max(0, vals[5])),
            .time = vals[6],
            .ch2_done = vals[7] > 0.5,
            .grade2 = if (n >= 9) @intFromFloat(m.clamp(vals[8], 32, 126)) else '-',
            .lang = if (n >= 10) Lang.fromTag(toks[9]) else null,
        };
    }

    pub fn format(sv: Save, buf: []u8) []const u8 {
        const lang_tag = if (sv.lang) |l| l.tag() else "";
        return std.fmt.bufPrint(buf, "{d} {d} {d} {d:.1} {d} {d} {d:.1} {d} {d}{s}{s}\n", .{ @intFromBool(sv.ch1_done), sv.grade, sv.emboli, sv.stability, @intFromBool(sv.marrow), sv.atlas, sv.time, @intFromBool(sv.ch2_done), sv.grade2, if (lang_tag.len > 0) " " else "", lang_tag }) catch "";
    }
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
    /// Language everything is drawn in. Changing it takes effect on the next frame.
    lang: Lang = .en,
    /// Device the prompts are written for: the one the player last used, or the one `--prompts` names.
    prompts: bindings.Device = .kbm,
    map_sel: usize = 0,
    pause_sel: PauseItem = .resume_game,
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
    /// The keyboard shortcut for full screen as this platform's window has it, where that is not the one
    /// the string catalogue names; the pause screen prints it. Set once at startup.
    fullscreen_key: ?[]const u8 = null,
    save_path: [paths.max_path]u8 = undefined,
    save_path_len: usize = 0,

    /// `persist` is false for bot-driven and scripted runs, which must never touch the player's save.
    /// `default_lang` applies unless the save holds a language the player chose.
    pub fn init(app: *App, persist: bool, default_lang: Lang) void {
        app.* = .{ .lang = default_lang };
        app.sim = game.Sim.init();
        app.parkForTitle();
        app.checkpoint = app.sim;
        app.seedCells();
        if (persist) {
            app.locateSave();
            app.loadSave();
            if (app.save.lang) |l| app.lang = l;
        }
    }

    /// The player's switch: the next language, from the next frame, remembered across launches.
    pub fn cycleLanguage(app: *App) void {
        app.lang = app.lang.next();
        app.save.lang = app.lang;
        app.writeSave();
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
        var dir_buf: [paths.max_path]u8 = undefined;
        const dir = util.saveDir(&dir_buf) orelse return;
        const full = paths.saveFile(&app.save_path, dir, util.sep) orelse return;
        app.save_path_len = full.len;
    }

    fn loadSave(app: *App) void {
        if (app.save_path_len == 0) return;
        var buf: [512]u8 = undefined;
        const path: [*:0]const u8 = @ptrCast(&app.save_path);
        const data = util.readFile(path, &buf) orelse return;
        if (Save.parse(data)) |sv| app.save = sv;
    }

    fn writeSave(app: *App) void {
        if (app.save_path_len == 0) return;
        var buf: [256]u8 = undefined;
        const text = app.save.format(&buf);
        if (text.len == 0) return;
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

    /// Stop the game on the pause menu, with Resume selected.
    pub fn openPause(app: *App) void {
        app.screen = .pause;
        app.pause_sel = .resume_game;
        app.want_capture = false;
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
                if (ui.language or ui.left or ui.right) app.cycleLanguage();
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
                    if (app.briefing_page >= strings.briefing.pages.len) app.startChapter(0);
                } else if (ui.back or ui.cancel) {
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
                } else if (ui.back or ui.cancel) {
                    app.toTitle();
                }
            },
            .pause => {
                const n = PauseItem.count;
                const at = @intFromEnum(app.pause_sel);
                if (ui.down) app.pause_sel = @enumFromInt((at + 1) % n);
                if (ui.up) app.pause_sel = @enumFromInt((at + n - 1) % n);
                if (ui.language or ((ui.left or ui.right) and app.pause_sel == .language)) app.cycleLanguage();
                // A key of its own first, then whatever is selected.
                const choice: ?PauseItem = if (ui.back or ui.cancel or ui.pause)
                    .resume_game
                else if (ui.retry)
                    .retry
                else if (ui.restart)
                    .restart
                else if (ui.quit_to_title)
                    .leave
                else if (ui.confirm)
                    app.pause_sel
                else
                    null;
                if (choice) |item| switch (item) {
                    .resume_game => {
                        app.screen = .play;
                        app.want_capture = true;
                    },
                    .retry => {
                        app.restoreCheckpoint();
                        app.screen = .play;
                        app.want_capture = true;
                    },
                    .restart => app.startChapter(app.sim.stats.retries + 1),
                    .leave => app.toTitle(),
                    .language => app.cycleLanguage(),
                };
            },
            .play => {
                const s = &app.sim;
                if ((ui.back or ui.pause) and s.mode != .complete) {
                    app.openPause();
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
        app.sim.voice.say(strings.line.link_re_established, .normal);
        app.seedCells();
        app.screen_t = 0;
        if (app.bot != null) app.bot = .{};
    }
};

test "cells stay inside the lumen" {
    const app = try std.testing.allocator.create(App);
    defer std.testing.allocator.destroy(app);
    app.init(false, .en);
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
        app.init(false, .en);
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

test "the save file round-trips, and files from before a field existed still load" {
    var buf: [128]u8 = undefined;
    const sv: Save = .{ .ch1_done = true, .grade = 'B', .emboli = 2, .stability = 81.5, .marrow = true, .atlas = 9, .time = 312.4, .ch2_done = true, .grade2 = 'A', .lang = .uk };
    const text = sv.format(&buf);
    try std.testing.expectEqualStrings("1 66 2 81.5 1 9 312.4 1 65 uk\n", text);
    try std.testing.expectEqualDeep(sv, Save.parse(text).?);

    // No language chosen: the token is left out, which is also what every earlier build wrote.
    var plain = sv;
    plain.lang = null;
    try std.testing.expectEqualStrings("1 66 2 81.5 1 9 312.4 1 65\n", plain.format(&buf));
    try std.testing.expectEqualDeep(plain, Save.parse("1 66 2 81.5 1 9 312.4 1 65\n").?);

    // The first format had seven fields; chapter 2's two were appended later.
    const old = Save.parse("1 66 2 81.5 1 9 312.4\n").?;
    try std.testing.expect(old.ch1_done and !old.ch2_done and old.grade == 'B' and old.grade2 == '-' and old.lang == null);
    try std.testing.expectEqual(@as(?Save, null), Save.parse("1 66 2\n"));
    try std.testing.expectEqual(@as(?Lang, null), Save.parse("1 66 2 81.5 1 9 312.4 1 65 xx\n").?.lang);
}

test "the language switch works on the title and pause screens and never writes a save in scripted runs" {
    const app = try std.testing.allocator.create(App);
    defer std.testing.allocator.destroy(app);
    const dt: f32 = 1.0 / 60.0;
    app.init(false, .en);
    app.step(.{}, .{ .language = true }, dt);
    try std.testing.expectEqual(Lang.uk, app.lang);
    try std.testing.expectEqual(@as(?Lang, .uk), app.save.lang);
    try std.testing.expectEqual(@as(usize, 0), app.save_path_len);

    // In play the key belongs to the simulation (it skips a comms line); the language stays.
    app.startChapter(0);
    app.step(.{}, .{ .language = true }, dt);
    try std.testing.expectEqual(Lang.uk, app.lang);
    app.step(.{}, .{ .back = true }, dt);
    try std.testing.expectEqual(Screen.pause, app.screen);
    app.step(.{}, .{ .language = true }, dt);
    try std.testing.expectEqual(Lang.en, app.lang);
    try std.testing.expectEqual(Screen.pause, app.screen);
}

test "the chosen language survives a relaunch, in a real save file under a scratch profile" {
    var profile: util.ScratchProfile = .{};
    profile.begin() orelse return error.SkipZigTest;
    defer profile.end();

    const app = try std.testing.allocator.create(App);
    defer std.testing.allocator.destroy(app);
    const dt: f32 = 1.0 / 60.0;
    var file: [256]u8 = undefined;

    // First launch on a Ukrainian system: no save, so the system's language applies and nothing is written.
    app.init(true, .uk);
    const save_path: [*:0]const u8 = @ptrCast(&app.save_path);
    try std.testing.expect(app.save_path_len > 0);
    try std.testing.expect(std.mem.endsWith(u8, app.save_path[0..app.save_path_len], paths.app_dir_name ++ [_]u8{util.sep} ++ paths.save_file_name));
    try std.testing.expectEqual(Lang.uk, app.lang);
    try std.testing.expectEqual(@as(?[]u8, null), util.readFile(save_path, &file));

    // The player switches to English on the title screen; the file now says so.
    app.step(.{}, .{ .language = true }, dt);
    try std.testing.expectEqual(Lang.en, app.lang);
    try std.testing.expectEqualStrings("0 45 0 0.0 0 0 0.0 0 45 en\n", util.readFile(save_path, &file).?);

    // Relaunch: the player's choice wins over the system's language.
    app.init(true, .uk);
    try std.testing.expectEqual(Lang.en, app.lang);

    // A save written by a build that had no language: progress loads, the system's language applies, and
    // saving progress again does not invent a choice.
    try std.testing.expect(util.writeFile(save_path, "1 66 2 81.5 1 9 312.4 1 65\n"));
    app.init(true, .uk);
    try std.testing.expectEqual(Lang.uk, app.lang);
    try std.testing.expect(app.save.ch1_done and app.save.ch2_done and app.save.lang == null);
    app.writeSave();
    try std.testing.expectEqualStrings("1 66 2 81.5 1 9 312.4 1 65\n", util.readFile(save_path, &file).?);
}

test "every entry of the pause menu can be selected and chosen without a key of its own" {
    const app = try std.testing.allocator.create(App);
    defer std.testing.allocator.destroy(app);
    const dt: f32 = 1.0 / 60.0;
    const Case = struct { item: PauseItem, downs: usize };
    for ([_]Case{
        .{ .item = .resume_game, .downs = 0 },
        .{ .item = .retry, .downs = 1 },
        .{ .item = .restart, .downs = 2 },
        .{ .item = .leave, .downs = 3 },
        .{ .item = .language, .downs = 4 },
    }) |case| {
        app.init(false, .en);
        app.chapter = 1;
        app.startChapter(0);
        for (0..20) |_| app.step(.{}, .{}, dt);
        // A controller pauses with `pause`; the selection starts on Resume every time.
        app.step(.{}, .{ .pause = true }, dt);
        try std.testing.expectEqual(Screen.pause, app.screen);
        try std.testing.expectEqual(PauseItem.resume_game, app.pause_sel);
        for (0..case.downs) |_| app.step(.{}, .{ .down = true }, dt);
        try std.testing.expectEqual(case.item, app.pause_sel);
        app.step(.{}, .{ .confirm = true }, dt);
        switch (case.item) {
            .resume_game => {
                try std.testing.expectEqual(Screen.play, app.screen);
                try std.testing.expectEqual(@as(u32, 0), app.sim.stats.retries);
            },
            .retry => {
                try std.testing.expectEqual(Screen.play, app.screen);
                try std.testing.expectEqual(@as(u32, 1), app.sim.stats.retries);
                try std.testing.expect(app.sim.voice.current != null);
            },
            .restart => {
                try std.testing.expectEqual(Screen.play, app.screen);
                try std.testing.expectEqual(@as(u32, 1), app.sim.stats.retries);
                try std.testing.expectEqual(@as(u8, 1), app.sim.chapter);
                try std.testing.expect(app.sim.voice.current == null or app.sim.stats.time < 0.1);
            },
            .leave => try std.testing.expectEqual(Screen.title, app.screen),
            .language => {
                try std.testing.expectEqual(Screen.pause, app.screen);
                try std.testing.expectEqual(Lang.uk, app.lang);
                // left and right change it too, on this entry only
                app.step(.{}, .{ .right = true }, dt);
                try std.testing.expectEqual(Lang.en, app.lang);
                app.step(.{}, .{ .up = true }, dt);
                app.step(.{}, .{ .left = true }, dt);
                try std.testing.expectEqual(Lang.en, app.lang);
            },
        }
    }

    // The selection wraps, and the keys of their own still work whatever is selected.
    app.init(false, .en);
    app.startChapter(0);
    app.step(.{}, .{ .back = true }, dt);
    app.step(.{}, .{ .up = true }, dt);
    try std.testing.expectEqual(PauseItem.language, app.pause_sel);
    app.step(.{}, .{ .down = true }, dt);
    try std.testing.expectEqual(PauseItem.resume_game, app.pause_sel);
    app.step(.{}, .{ .down = true }, dt);
    app.step(.{}, .{ .down = true }, dt);
    app.step(.{}, .{ .cancel = true }, dt);
    try std.testing.expectEqual(Screen.play, app.screen);
    try std.testing.expectEqual(@as(u32, 0), app.sim.stats.retries);
    app.step(.{}, .{ .pause = true }, dt);
    app.step(.{}, .{ .down = true }, dt);
    app.step(.{}, .{ .quit_to_title = true }, dt);
    try std.testing.expectEqual(Screen.title, app.screen);
}

test "a controller's cancel backs out of menus and does nothing in flight; its pause only pauses" {
    const app = try std.testing.allocator.create(App);
    defer std.testing.allocator.destroy(app);
    const dt: f32 = 1.0 / 60.0;
    app.init(false, .en);
    // title: left and right switch the language, cancel and pause do nothing
    app.step(.{}, .{ .right = true }, dt);
    try std.testing.expectEqual(Lang.uk, app.lang);
    app.step(.{}, .{ .left = true }, dt);
    try std.testing.expectEqual(Lang.en, app.lang);
    app.step(.{}, .{ .cancel = true, .pause = true }, dt);
    try std.testing.expectEqual(Screen.title, app.screen);
    // map and back
    app.step(.{}, .{ .map = true }, dt);
    try std.testing.expectEqual(Screen.map, app.screen);
    app.step(.{}, .{ .pause = true }, dt);
    try std.testing.expectEqual(Screen.map, app.screen);
    app.step(.{}, .{ .cancel = true }, dt);
    try std.testing.expectEqual(Screen.title, app.screen);
    // briefing and back
    app.step(.{}, .{ .confirm = true }, dt);
    try std.testing.expectEqual(Screen.briefing, app.screen);
    app.step(.{}, .{ .cancel = true }, dt);
    try std.testing.expectEqual(Screen.title, app.screen);
    // in flight the cancel button is the one that descends: it must not open the pause menu
    app.startChapter(0);
    app.step(.{}, .{ .cancel = true }, dt);
    try std.testing.expectEqual(Screen.play, app.screen);
    app.step(.{}, .{ .pause = true }, dt);
    try std.testing.expectEqual(Screen.pause, app.screen);
    app.step(.{}, .{ .pause = true }, dt);
    try std.testing.expectEqual(Screen.play, app.screen);
}
