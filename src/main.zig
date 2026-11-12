//! Dentro del cuerpo — entry point.
//!
//!   dentro                     windowed game
//!   dentro --demo              windowed, flown by the scripted pilot (end-to-end run on the real display)
//!   dentro --inputtest         windowed, posts key events into its own queue and checks they reach the arms
//!   dentro --selftest          headless: scripted pilot plays chapter 1, prints the timeline
//!   dentro --shots <dir>       headless GPU: renders every screen offscreen and writes BMP frames
//!
//! `--lang en|uk` picks the language for the run. Without it the game uses the language the player chose in
//! the game, or else the first supported one in the system's preference list; the scripted modes, whose
//! output is compared between runs, use English.

const std = @import("std");
const objc = @import("objc.zig");
const m = @import("math.zig");
const gpu = @import("gpu.zig");
const mesh = @import("mesh.zig");
const render = @import("render.zig");
const font = @import("font.zig");
const platform = @import("platform.zig");
const util = @import("util.zig");
const game = @import("game.zig");
const ch2 = @import("ch2.zig");
const bot = @import("bot.zig");
const vein_mod = @import("vein.zig");
const app_mod = @import("app.zig");
const draw = @import("draw.zig");
const audio_mod = @import("audio.zig");
const i18n = @import("i18n.zig");
const strings = @import("strings.zig");
const guide = @import("guide.zig");
const campaign = @import("campaign.zig");
const l10n = @import("l10n.zig");
const Lang = i18n.Lang;
const Text = i18n.Text;

const embedded_shaders = @embedFile("shaders/shaders.metal");
extern "c" fn _NSGetExecutablePath(buf: [*]u8, size: *u32) c_int;

const Mode = enum { play, demo, inputtest, selftest, shots, icon };

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena);
    var mode: Mode = .play;
    var shots_dir: []const u8 = ".";
    var start_chapter: ?u8 = null;
    var fullscreen = false;
    var lang_arg: ?Lang = null;
    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const a = args[i];
        const known = [_][]const u8{ "--selftest", "--demo", "--inputtest", "--fullscreen", "--icon", "--shots", "--chapter", "--lang" };
        var ok = false;
        for (known) |k| ok = ok or std.mem.eql(u8, a, k);
        // Cocoa reads "-AppleLanguages (uk)" and its kin from the command line as user defaults; they come
        // with a value and are not this program's to judge.
        if (std.mem.startsWith(u8, a, "-Apple")) {
            i += 1;
            continue;
        }
        // Finder passes -psn_… on some launch paths; anything else unknown is a mistake worth stopping for.
        if (!ok and !std.mem.startsWith(u8, a, "-psn")) {
            std.debug.print("unknown argument: {s}\nusage: dentro [--fullscreen] [--lang en|uk] [--chapter 1|2] [--demo | --inputtest | --selftest | --shots <dir> | --icon <png>]\n", .{a});
            std.process.exit(2);
        }
        if (std.mem.eql(u8, a, "--selftest")) mode = .selftest;
        if (std.mem.eql(u8, a, "--demo")) mode = .demo;
        if (std.mem.eql(u8, a, "--inputtest")) mode = .inputtest;
        if (std.mem.eql(u8, a, "--fullscreen")) fullscreen = true;
        if (std.mem.eql(u8, a, "--chapter") and i + 1 < args.len) {
            const n = std.fmt.parseInt(u8, args[i + 1], 10) catch 0;
            if (n < 1 or n > 2) {
                std.debug.print("--chapter takes 1 or 2 (the playable chapters)\n", .{});
                std.process.exit(2);
            }
            start_chapter = n - 1;
            i += 1;
            continue;
        }
        if (std.mem.eql(u8, a, "--lang")) {
            lang_arg = if (i + 1 < args.len) Lang.fromTag(args[i + 1]) else null;
            if (lang_arg == null) {
                std.debug.print("--lang takes en or uk\n", .{});
                std.process.exit(2);
            }
            i += 1;
            continue;
        }
        if (std.mem.eql(u8, a, "--icon") and i + 1 < args.len) {
            mode = .icon;
            shots_dir = args[i + 1];
            i += 1;
        }
        if (std.mem.eql(u8, a, "--shots") and i + 1 < args.len) {
            mode = .shots;
            shots_dir = args[i + 1];
            i += 1;
        }
    }
    switch (mode) {
        .selftest => return runSelftest(arena),
        .shots => return runShots(arena, shots_dir, start_chapter, lang_arg),
        .icon => return runIcon(arena, shots_dir),
        else => return runWindow(arena, mode, fullscreen, start_chapter, lang_arg),
    }
}

/// The language the system would like, for a first launch: the first supported one in its preference list.
fn systemLanguage() Lang {
    var buf: [512]u8 = undefined;
    return Lang.fromPreferences(platform.preferredLanguages(&buf));
}

/// NUL-terminated copies of the menu titles in `lang`, for the platform layer.
const MenuText = struct {
    fullscreen: [96:0]u8 = undefined,
    quit: [96:0]u8 = undefined,

    fn set(mt: *MenuText, lang: Lang) platform.MenuTitles {
        return .{
            .fullscreen = terminate(&mt.fullscreen, strings.menu.fullscreen.get(lang)),
            .quit = terminate(&mt.quit, strings.menu.quit.get(lang)),
        };
    }

    fn terminate(out: *[96:0]u8, s: []const u8) [*:0]const u8 {
        const n = @min(s.len, out.len);
        @memcpy(out[0..n], s[0..n]);
        out[n] = 0;
        return out;
    }
};

fn runSelftest(arena: std.mem.Allocator) !void {
    const sim = try arena.create(game.Sim);
    const cp = try arena.create(game.Sim);
    {
        std.debug.print("--- chapter 2: intestines\n", .{});
        bot.trace = util.env("DENTRO_TRACE") != null;
        const r2 = bot.runHeadlessChapter(sim, cp, 1, 1500, true);
        const g = &sim.g;
        std.debug.print("selftest ch2: completed={} stage={s} sim_time={d:.1}s deaths={d} stability={d:.1} grade={c} atlas={d}\n  cleared={d}/{d} extruded={d} spread={d} bursts={d} commensals_lost={d} tissue_hits={d} crush_hits={d} waves_survived={d} tether_uses={d} dual_arm_time={d:.1}s\n", .{ r2.completed, @tagName(r2.stage), r2.sim_seconds, r2.deaths, r2.stability, r2.grade, r2.atlas, g.cleared, g.total, g.extruded, g.spread, g.bursts, g.commensals_lost, r2.stats.tissue_hits, g.crush_hits, g.waves_survived, g.tether_uses, r2.stats.dual_time });
        if (!r2.completed) std.process.exit(1);
        std.debug.print("--- chapter 1: vein\n", .{});
    }
    const r = bot.runHeadless(sim, cp, 1500, true);
    std.debug.print(
        \\selftest: completed={} stage={s} sim_time={d:.1}s deaths={d}
        \\  stability={d:.1} hull={d:.0} grade={c} atlas={d}
        \\  dual_arm_time={d:.1}s sync_strikes={d} kills={d} emboli_lysed={d} emboli_escaped={d} tissue_hits={d} friendly_fire={d}
        \\
    , .{ r.completed, @tagName(r.stage), r.sim_seconds, r.deaths, r.stability, r.hull, r.grade, r.atlas, r.stats.dual_time, r.stats.sync_strikes, r.stats.kills, r.stats.emboli_lysed, r.stats.emboli_escaped, r.stats.tissue_hits, r.stats.friendly_fire });
    if (!r.completed) std.process.exit(1);
}

/// Shader source: the copy in the bundle's Resources if present (so it can be edited without rebuilding),
/// otherwise the one compiled into the binary.
fn shaderSource(arena: std.mem.Allocator) [*:0]const u8 {
    var path_buf: [1024]u8 = undefined;
    var size: u32 = path_buf.len;
    if (_NSGetExecutablePath(&path_buf, &size) == 0) {
        const exe = std.mem.span(@as([*:0]u8, @ptrCast(&path_buf)));
        if (std.mem.lastIndexOfScalar(u8, exe, '/')) |slash| {
            var full: [1200]u8 = undefined;
            if (std.fmt.bufPrintSentinel(&full, "{s}/../Resources/shaders/shaders.metal", .{exe[0..slash]}, 0)) |p| {
                const buf = arena.alloc(u8, 256 * 1024) catch return embedded_shaders;
                if (util.readFile(p.ptr, buf[0 .. buf.len - 1])) |data| {
                    if (data.len > 100) {
                        buf[data.len] = 0;
                        return @ptrCast(buf.ptr);
                    }
                }
            } else |_| {}
        }
    }
    return embedded_shaders;
}

const Engine = struct {
    g: gpu.Gpu,
    r: render.Renderer,
    vm: vein_mod.Meshes,
    app: *app_mod.App,

    /// `lang` is the language asked for on the command line; `fallback` applies when neither it nor the
    /// save file names one.
    fn init(e: *Engine, arena: std.mem.Allocator, persist: bool, lang: ?Lang, fallback: Lang) !void {
        e.g = try gpu.Gpu.init(shaderSource(arena));
        e.app = try arena.create(app_mod.App);
        e.app.init(persist, fallback);
        if (lang) |l| e.app.lang = l;
        var b = mesh.Builder.init(arena);
        const meshes = render.Meshes.build(&b);
        e.vm = vein_mod.buildMeshes(&b, &e.app.sim.vein);
        e.g.uploadMeshes(b.verts.items, b.indices.items);
        const f = try font.Font.build(arena);
        try e.g.uploadFont(arena, f.pixels, font.atlas_w, font.atlas_h);
        e.r = .{ .g = &e.g, .font = f, .meshes = meshes };
    }

    fn renderFrame(e: *Engine, dt: f32, wait: bool) bool {
        e.r.begin();
        const out = draw.frame(e.app, &e.r, &e.vm, dt);
        return e.r.end(out.scene, out.arm, out.post, wait);
    }
};

// ---------------------------------------------------------------------------- offscreen screenshots

/// The atlas entry whose long text is longest in `lang`.
fn longestDeep(lang: Lang) Text {
    var best = guide.entry(@enumFromInt(0)).deep;
    for (1..guide.Topic.count) |k| {
        const d = guide.entry(@enumFromInt(k)).deep;
        if (d.get(lang).len > best.get(lang).len) best = d;
    }
    return best;
}

fn runShots(arena: std.mem.Allocator, dir: []const u8, only: ?u8, lang: ?Lang) !void {
    const pool = objc.poolPush();
    defer objc.poolPop(pool);
    const e = try arena.create(Engine);
    try e.init(arena, false, lang, .en);
    const w: u32 = 1600;
    const h: u32 = 1000;
    e.g.resize(w, h, true);
    const px = try arena.alloc(u8, w * h * 4);
    const app = e.app;
    const dt: f32 = 1.0 / 60.0;

    const Shooter = struct {
        e: *Engine,
        px: []u8,
        dir: []const u8,
        n: u32 = 0,
        fn snap(sh: *@This(), name: []const u8) void {
            const p2 = objc.poolPush();
            defer objc.poolPop(p2);
            _ = sh.e.renderFrame(1.0 / 60.0, true);
            sh.e.g.readback(sh.px);
            var path: [600]u8 = undefined;
            const full = std.fmt.bufPrintSentinel(&path, "{s}/{d:0>2}-{s}.bmp", .{ sh.dir, sh.n, name }, 0) catch return;
            _ = util.writeBmp(full.ptr, sh.px, sh.e.g.width, sh.e.g.height);
            std.debug.print("wrote {s}\n", .{full});
            sh.n += 1;
        }
    };
    var sh: Shooter = .{ .e = e, .px = px, .dir = dir };

    // Menus. The language key is pressed on the title screen to show the switch taking effect at once,
    // then pressed until the run is back in its own language.
    for (0..150) |_| app.step(.{}, .{}, dt);
    sh.snap("title");
    for (1..Lang.count) |_| {
        app.step(.{}, .{ .language = true }, dt);
        sh.snap("title-language-switched");
    }
    app.step(.{}, .{ .language = true }, dt);
    // The route map with each chapter selected in turn, before anything is unlocked.
    app.step(.{}, .{ .map = true }, dt);
    for (0..30) |_| app.step(.{}, .{}, dt);
    for (0..campaign.chapters.len) |k| {
        var nb: [24]u8 = undefined;
        sh.snap(if (k == 0) "map" else std.fmt.bufPrint(&nb, "map-row{d:0>2}", .{k + 1}) catch "map");
        app.step(.{}, .{ .down = true }, dt);
    }
    app.step(.{}, .{ .back = true }, dt);
    app.step(.{}, .{ .confirm = true }, dt);
    for (0..strings.briefing.pages.len) |k| {
        for (0..600) |_| app.step(.{}, .{}, dt);
        var nb: [24]u8 = undefined;
        sh.snap(if (k == 0) "briefing" else std.fmt.bufPrint(&nb, "briefing-page{d}", .{k + 1}) catch "briefing");
        if (k + 1 < strings.briefing.pages.len) app.step(.{}, .{ .confirm = true }, dt);
    }

    // The chapters, flown by the scripted pilot.
    app.bot = .{};
    app.unlock_all = true;
    var all_done = true;
    for (0..2) |ch| {
        if (only) |o| {
            if (o != ch) continue;
        }
        app.chapter = @intCast(ch);
        app.startChapter(0);
        var last_stage: ?game.Stage = null;
        var since: f32 = 0;
        var extra: u32 = 0;
        var t: f32 = 0;
        var done_mode: [6]bool = @splat(false);
        var ring_shot = false;
        while (t < 900) : (t += dt) {
            app.step(.{}, .{}, dt);
            const s = &app.sim;
            since += dt;
            if (last_stage == null or last_stage.? != s.stage) {
                last_stage = s.stage;
                since = 0;
                extra = 0;
            }
            const delay: f32 = switch (s.stage) {
                .needle => 1.0,
                .valve1_pass => 2.0,
                .treat => 3.0,
                .septum_break => 1.2,
                .exit => 0.6,
                .g_arrive => 2.5,
                .g_wave => 9.0,
                .g_exit => 0.8,
                else => 1.4,
            };
            if (since >= delay and since < delay + dt) sh.snap(@tagName(s.stage));
            const busy = s.stage == .treat or s.stage == .g_extrude or s.stage == .g_factory or s.stage == .g_flume or s.stage == .g_wave;
            const every: f32 = if (s.stage == .treat) 5.0 else 3.0;
            if (busy and since > delay + 1 and extra < 5 and @mod(since, every) < dt) {
                extra += 1;
                var nb: [40]u8 = undefined;
                sh.snap(std.fmt.bufPrint(&nb, "{s}-more", .{@tagName(s.stage)}) catch "more");
            }
            // The pilot shelters facing a villus; the contraction itself is overhead, so look at it once.
            if (s.stage == .g_wave and !ring_shot and s.gut.squeeze(s.pos.z) > 0.7) {
                ring_shot = true;
                const keep = s.pitch;
                s.pitch = 1.05;
                sh.snap("g_wave-ring-overhead");
                s.pitch = 0.45;
                sh.snap("g_wave-ring-ahead");
                s.pitch = keep;
            }
            const mi = @intFromEnum(s.mode);
            if (s.mode != .playing and !done_mode[mi]) {
                done_mode[mi] = true;
                // Hold the pilot off so a card it would dismiss stays up for the frame.
                const name = @tagName(s.mode);
                const pilot = app.bot;
                app.bot = null;
                for (0..30) |_| app.step(.{}, .{}, dt);
                sh.snap(name);
                app.bot = pilot;
            }
            if (s.mode == .complete) break;
        }
        all_done = all_done and app.sim.mode == .complete;
    }

    // The route map as the debrief leaves it, with the flown chapters logged.
    if (app.sim.mode == .complete) {
        app.step(.{}, .{ .confirm = true }, dt);
        for (0..30) |_| app.step(.{}, .{}, dt);
        sh.snap("map-after-debrief");
        while (app.map_sel > 0) {
            app.step(.{}, .{ .up = true }, dt);
            var nb: [32]u8 = undefined;
            sh.snap(std.fmt.bufPrint(&nb, "map-logged-row{d:0>2}", .{app.map_sel + 1}) catch "map");
        }
    }

    // Text the pilot's run does not reach. Each case is put on screen directly: the worst case for the
    // subtitle box from each source of lines, the HUD warnings, the failure cards and the debrief notes.
    app.bot = null;
    for (0..2) |ch| {
        app.chapter = @intCast(ch);
        app.startChapter(0);
        for (0..40) |_| app.step(.{}, .{}, dt);
        const s = &app.sim;
        const tag: []const u8 = if (ch == 0) "vein" else "gut";
        var nb: [48]u8 = undefined;
        if (ch == 0) {
            const cases = [_]struct { []const u8, Text }{
                .{ "subtitle-longest-line", l10n.longestIn(strings.line, app.lang) },
                .{ "subtitle-longest-hint", l10n.longestIn(strings.hint, app.lang) },
                .{ "subtitle-longest-atlas", longestDeep(app.lang) },
            };
            for (cases) |case| {
                s.voice.clear();
                s.voice.say(case[1], .normal);
                s.voice.age = 60;
                sh.snap(case[0]);
            }
            s.voice.clear();
            s.arms[0].tool = .drill;
            s.arms[0].overheated = true;
            s.arms[1].tool = .shoot;
            s.tissue_flash = 1;
            s.checkpoint_toast = 2;
            s.hidden_unlocked = true;
            sh.snap("hud-warnings");
            s.tissue_flash = 0;
            s.checkpoint_toast = 0;
            s.mode = .dead;
            sh.snap("dead");
        }
        s.voice.clear();
        s.mode = .lost;
        sh.snap(std.fmt.bufPrint(&nb, "lost-{s}", .{tag}) catch "lost");
        // The debrief with the notes a clean run does not earn.
        s.mode = .complete;
        s.stats.emboli_escaped = 3;
        s.hidden_unlocked = true;
        s.g.spread = 2;
        sh.snap(std.fmt.bufPrint(&nb, "complete-notes-{s}", .{tag}) catch "complete");
        if (ch == 1) {
            s.g.commensals_lost = 5;
            sh.snap("complete-notes-gut-flora");
        }
        s.mode = .playing;
    }

    // Pause screen, and the language key on it.
    app.screen = .pause;
    sh.snap("pause");
    for (1..Lang.count) |_| {
        app.step(.{}, .{ .language = true }, dt);
        sh.snap("pause-language-switched");
    }
    app.step(.{}, .{ .language = true }, dt);
    std.debug.print("shots: {d} frames, chapters complete = {}\n", .{ sh.n, all_done });
}

/// Render the app icon: 2048 px, the title backdrop and the reticle mark, clipped to the macOS icon shape.
fn runIcon(arena: std.mem.Allocator, path: []const u8) !void {
    const pool = objc.poolPush();
    defer objc.poolPop(pool);
    const e = try arena.create(Engine);
    try e.init(arena, false, null, .en);
    const n: u32 = 2048; // supersampled; the iconset step scales it down
    e.g.resize(n, n, true);
    const px = try arena.alloc(u8, n * n * 4);
    e.app.icon_mode = true;
    for (0..240) |_| e.app.step(.{}, .{}, 1.0 / 60.0);
    _ = e.renderFrame(1.0 / 60.0, true);
    e.g.readback(px);
    // Icon grid: the shape fills 824/1024 of the canvas, as a superellipse.
    const half: f32 = 824;
    for (0..n) |y| for (0..n) |x| {
        const dx = @abs(@as(f32, @floatFromInt(x)) + 0.5 - 1024) / half;
        const dy = @abs(@as(f32, @floatFromInt(y)) + 0.5 - 1024) / half;
        const d = std.math.pow(f32, std.math.pow(f32, dx, 5) + std.math.pow(f32, dy, 5), 0.2);
        const a = m.sat((1 - d) * half / 1.5);
        const o = (y * n + x) * 4;
        for (0..3) |c| px[o + c] = @intFromFloat(@as(f32, @floatFromInt(px[o + c])) * a);
        px[o + 3] = @intFromFloat(255 * a);
    };
    var zbuf: [1024]u8 = undefined;
    const z = try std.fmt.bufPrintSentinel(&zbuf, "{s}", .{path}, 0);
    if (!util.writePng(z.ptr, px, n, n)) return error.IconWriteFailed;
    std.debug.print("icon: {s}\n", .{path});
}

// ---------------------------------------------------------------------------- windowed game

fn gather(in: *const platform.Input, captured: bool, dt: f32) struct { c: game.Controls, ui: app_mod.UiInput } {
    var c: game.Controls = .{};
    const f = struct {
        fn axis(input: *const platform.Input, pos: platform.Key, neg: platform.Key) f32 {
            return @as(f32, if (input.down(pos)) 1 else 0) - @as(f32, if (input.down(neg)) 1 else 0);
        }
    };
    c.move = m.v3(f.axis(in, .d, .a), f.axis(in, .space, .c), f.axis(in, .w, .s));
    c.boost = in.down(.shift);
    const key_rate: f32 = 2.1;
    c.look[0] = f.axis(in, .right, .left) * key_rate * dt;
    c.look[1] = f.axis(in, .up, .down) * key_rate * dt;
    if (captured) {
        c.look[0] += in.mouse_dx * 0.0024;
        c.look[1] -= in.mouse_dy * 0.0024;
    }
    c.arm[0] = in.down(.q) or (captured and in.lmb);
    c.arm[1] = in.down(.e) or (captured and in.rmb);
    c.cycle = .{ in.hit(.z), in.hit(.x) };
    if (in.hit(.n1)) c.select[0] = .punch;
    if (in.hit(.n2)) c.select[0] = .drill;
    if (in.hit(.n3)) c.select[0] = .shoot;
    if (in.hit(.n8)) c.select[1] = .punch;
    if (in.hit(.n9)) c.select[1] = .drill;
    if (in.hit(.n0)) c.select[1] = .shoot;
    c.examine = in.hit(.t) or in.hit(.f);
    c.hint = in.hit(.h);
    c.tether = in.hit(.g);
    c.confirm = in.hit(.enter);
    c.skip = in.hit(.tab);
    const ui: app_mod.UiInput = .{
        .confirm = in.hit(.enter),
        .back = in.hit(.escape),
        .up = in.hit(.up) or in.hit(.w),
        .down = in.hit(.down) or in.hit(.s),
        .map = in.hit(.m),
        .retry = in.hit(.r),
        .restart = in.hit(.n),
        .quit_to_title = in.hit(.l),
        .language = in.hit(.tab),
    };
    return .{ .c = c, .ui = ui };
}

var live_audio: ?*audio_mod.Audio = null;

fn stopAudioOnTerminate() void {
    if (live_audio) |a| a.stop();
}

fn runWindow(arena: std.mem.Allocator, mode: Mode, fullscreen: bool, start_chapter: ?u8, lang: ?Lang) !void {
    const outer = objc.poolPush();
    defer objc.poolPop(outer);
    const e = try arena.create(Engine);
    // The input test asserts on its output, so it does not follow the machine it runs on.
    try e.init(arena, mode == .play, lang, if (mode == .inputtest) .en else systemLanguage());
    const app = e.app;
    const layer = e.g.makeLayer();
    var menu_text: MenuText = .{};
    var menu_lang = app.lang;
    var plat = platform.Platform.init(app_mod.title, menu_text.set(menu_lang), layer, 1440, 900);
    if (fullscreen) plat.toggleFullscreen();

    const audio = try arena.create(audio_mod.Audio);
    audio.* = .{};
    const audio_ok = audio.start();
    defer audio.stop();
    live_audio = audio;
    platform.on_terminate = &stopAudioOnTerminate;
    if (!audio_ok) std.debug.print("audio: output queue failed to start; continuing silent\n", .{});

    if (start_chapter) |ch| {
        app.unlock_all = true;
        app.chapter = ch;
    }
    if (mode == .demo) {
        app.bot = .{};
        app.startChapter(0);
    } else if (mode == .play and start_chapter != null) {
        app.startChapter(0);
    }
    var it: InputTest = .{};
    if (mode == .inputtest) it.begin(app);
    if (mode == .demo) {
        var prefs: [512]u8 = undefined;
        std.debug.print("[demo] language {s} (asked for: {s}; system preference: {s})\n", .{ app.lang.tag(), if (lang) |l| l.tag() else "-", platform.preferredLanguages(&prefs) });
    }

    var last = platform.now();
    var frames: u64 = 0;
    var demo_logged: ?game.Stage = null;
    const t_start = last;
    while (!plat.shouldQuit()) {
        const pool = objc.poolPush();
        defer objc.poolPop(pool);

        if (mode == .inputtest) it.post(&plat, app);
        const lost_focus = plat.pump();
        if (lost_focus and app.screen == .play and mode == .play) {
            app.screen = .pause;
            app.want_capture = false;
        }
        const size = plat.pixelSize();
        if (size.w != e.g.width or size.h != e.g.height) {
            objc.send(fn (objc.id, objc.SEL, f64) callconv(.c) void, layer, "setContentsScale:", .{size.scale});
            e.g.resize(size.w, size.h, false);
        }

        const now = platform.now();
        const dt: f32 = @floatCast(@min(@max(now - last, 0.0005), 1.0 / 20.0));
        last = now;

        const gathered = gather(&plat.input, plat.captured, dt);
        const steps: usize = @intFromFloat(m.clamp(@ceil(dt * 120.0), 1, 4));
        const sub = dt / @as(f32, @floatFromInt(steps));
        for (0..steps) |k| {
            var c = gathered.c;
            if (k > 0) {
                c.look = .{ 0, 0 };
                c.cycle = .{ false, false };
                c.select = .{ null, null };
                c.examine = false;
                c.hint = false;
                c.confirm = false;
                c.skip = false;
            }
            app.step(c, if (k == 0) gathered.ui else .{}, sub);
            for (app.sim.sfx[0..app.sim.nsfx]) |ev| audio.playSfx(ev);
            if (app.comm_chirp) audio.play(audio_mod.comm_chirp, 0, 1);
        }
        plat.input.endFrame();
        plat.capture(app.want_capture and mode == .play);
        if (app.lang != menu_lang) {
            menu_lang = app.lang;
            plat.setMenuTitles(menu_text.set(menu_lang));
        }

        // Continuous audio state.
        {
            const s = &app.sim;
            const in_play = app.screen == .play and (s.mode == .playing or s.mode == .transit);
            const p = &audio.params;
            for (0..2) |k| {
                const a = &s.arms[k];
                p.drill_on[k] = if (in_play and a.tool == .drill and a.held and !a.overheated) 1 else 0;
                p.drill_bite[k] = if (in_play and a.engaged) 1 else 0;
            }
            p.flow = m.sat((s.flow.len() + s.vrel.len() * 0.6) / 500.0) + s.warp;
            p.heart_bpm = 68 + (100 - s.stability) * 0.75;
            p.alarm = if (in_play and s.stability < 25) 1 else 0;
            p.heart_gain = if (app.screen == .pause) 0.5 else 1;
        }

        _ = e.renderFrame(dt, false);
        frames += 1;

        if (mode == .demo) {
            const s = &app.sim;
            if (demo_logged == null or demo_logged.? != s.stage) {
                demo_logged = s.stage;
                std.debug.print("[demo {d:6.1}s] stage {s} hull {d:.0} stability {d:.0}\n", .{ now - t_start, @tagName(s.stage), s.hull, s.stability });
            }
            if (s.mode == .complete and app.screen_t > 0) {
                const secs = now - t_start;
                if (it.linger == 0) std.debug.print("demo: chapter complete on the display. grade={c} stability={d:.0} dual_arm_time={d:.1}s sync_strikes={d} retries={d} frames={d} avg_fps={d:.0} drawable={d}x{d} audio={}\n", .{ s.grade(), s.stability, s.stats.dual_time, s.stats.sync_strikes, s.stats.retries, frames, @as(f64, @floatFromInt(frames)) / secs, e.g.width, e.g.height, audio_ok });
                // linger on the debrief for a moment so it is visible
                if (it.linger == 0) it.linger = now;
                if (now - it.linger > 2.5) return;
            }
            if (now - t_start > 600) {
                std.debug.print("demo: timed out in stage {s}\n", .{@tagName(s.stage)});
                std.process.exit(1);
            }
        }
        if (mode == .inputtest and it.finished) {
            std.debug.print("inputtest: {s} ({d} checks, {d} failed) drawable={d}x{d}\n", .{ if (it.failed == 0) "PASS" else "FAIL", it.checks, it.failed, e.g.width, e.g.height });
            if (it.failed != 0) {
                audio.stop();
                std.process.exit(1);
            }
            return;
        }
    }
}

/// Drives the real event path: key events are posted to this application's own queue, drained by the
/// normal pump, mapped by `gather`, and the result is read back from the simulation.
const InputTest = struct {
    frame: u32 = 0,
    checks: u32 = 0,
    failed: u32 = 0,
    finished: bool = false,
    linger: f64 = 0,
    start_pos: m.Vec3 = .{},
    start_yaw: f32 = 0,
    stone_hp: f32 = 0,
    saw_both: bool = false,
    saw_drill_and_shoot: bool = false,
    start_lang: Lang = .en,

    fn begin(it: *InputTest, app: *app_mod.App) void {
        _ = it;
        app.startChapter(0);
        // Stand in front of the phlebolith with the upgrade installed, both arms on Punch.
        const s = &app.sim;
        s.in_bore = false;
        s.stage = .septum_break;
        s.station = 2;
        s.has_sync = true;
        s.voice.clear();
        const stone = s.findConst(.phlebolith).?;
        s.pos = stone.pos.add(m.v3(0, 0, -(stone.radius + 14)));
        s.yaw = 0;
        s.pitch = 0;
        s.sides = .{};
        s.arms[0].tool = .punch;
        s.arms[1].tool = .punch;
        app.checkpoint = s.*;
    }

    /// Turn the view until the tether would (or would not) find tissue. Test setup only: the key press
    /// that follows still travels the real event path.
    fn aim(s: *game.Sim, want_hit: bool) bool {
        const pitches = [_]f32{ 0, -0.3, 0.3, -0.8, 0.8, 1.2, 1.45 };
        for (pitches) |p| {
            for (0..24) |k| {
                s.pitch = p;
                s.yaw = @as(f32, @floatFromInt(k)) * std.math.tau / 24.0;
                if ((ch2.tetherTarget(s) != null) == want_hit) return true;
            }
        }
        return false;
    }

    fn check(it: *InputTest, ok: bool, what: []const u8) void {
        it.checks += 1;
        if (!ok) it.failed += 1;
        std.debug.print("  [{s}] {s}\n", .{ if (ok) "ok" else "FAIL", what });
    }

    fn post(it: *InputTest, plat: *platform.Platform, app: *app_mod.App) void {
        const s = &app.sim;
        it.frame += 1;
        if (s.arms[0].held and s.arms[1].held) it.saw_both = true;
        if (s.arms[0].held and s.arms[1].held and s.arms[0].tool != s.arms[1].tool) it.saw_drill_and_shoot = true;
        switch (it.frame) {
            20 => {
                it.stone_hp = s.findConst(.phlebolith).?.hp;
                plat.postKey(.q, true);
                plat.postKey(.e, true);
            },
            26 => {
                plat.postKey(.q, false);
                plat.postKey(.e, false);
            },
            70 => {
                it.check(it.saw_both, "Q and E held in the same frame drive both arms");
                it.check(s.stats.sync_strikes == 1, "simultaneous punches landed as one Sync Strike");
                it.check(s.findConst(.phlebolith).?.hp == it.stone_hp - 10, "Sync Strike did 10 damage to the phlebolith");
                // tool selection: left arm to Shoot (3), right arm to Drill via cycle (X)
                plat.postKey(.n3, true);
                plat.postKey(.x, true);
            },
            72 => {
                plat.postKey(.n3, false);
                plat.postKey(.x, false);
            },
            110 => {
                it.check(s.arms[0].tool == .shoot, "3 selects Shoot on the left arm");
                it.check(s.arms[1].tool == .drill, "X cycles the right arm from Punch to Drill");
                it.saw_drill_and_shoot = false;
                plat.postKey(.q, true);
                plat.postKey(.e, true);
            },
            170 => {
                it.check(it.saw_drill_and_shoot, "different tools run on both arms at once");
                it.check(s.arms[1].engaged, "the drill arm is cutting while the other arm fires");
                it.check(s.arms[0].charge < 1, "the shoot arm fired");
                plat.postKey(.q, false);
                plat.postKey(.e, false);
                it.start_pos = s.pos;
                it.start_yaw = s.yaw;
                plat.postKey(.s, true);
                plat.postKey(.left, true);
            },
            230 => {
                plat.postKey(.s, false);
                plat.postKey(.left, false);
                it.check(s.pos.dist(it.start_pos) > 20, "S thrusts the drone backward");
                it.check(@abs(s.yaw - it.start_yaw) > 0.3, "arrow keys turn the view");
                plat.postKey(.t, true);
            },
            232 => plat.postKey(.t, false),
            260 => {
                plat.postKey(.escape, true);
            },
            262 => plat.postKey(.escape, false),
            280 => {
                it.check(app.screen == .pause, "Esc pauses");
                it.start_lang = app.lang;
                plat.postKey(.tab, true);
            },
            282 => plat.postKey(.tab, false),
            286 => {
                it.check(app.lang == it.start_lang.next() and app.lang != it.start_lang, "Tab in the pause menu switches to the next language");
                it.check(std.mem.eql(u8, plat.menuTitle(.quit), strings.menu.quit.get(app.lang)), "the menu bar follows the language");
                it.check(app.save.lang == app.lang and app.save_path_len == 0, "the choice is recorded for saving, and a scripted run has no save file to write");
                plat.postKey(.tab, true);
            },
            288 => plat.postKey(.tab, false),
            292 => {
                var want = it.start_lang;
                for (0..2) |_| want = want.next();
                it.check(app.lang == want, "Tab again moves on to the language after that");
                while (app.lang != it.start_lang) app.cycleLanguage();
                plat.postKey(.r, true);
            },
            294 => plat.postKey(.r, false),
            312 => {
                it.check(app.screen == .play and s.stats.retries == 1, "R in the pause menu relaunches from the checkpoint");
                // Chapter 2: the tether key, from where the drone arrives among the villi.
                app.chapter = 1;
                app.startChapter(0);
                s.has_tether = true;
                s.stage = .g_tether;
                s.voice.clear();
            },
            341 => it.check(aim(s, true), "a villus is within tether range of the arrival point"),
            342 => plat.postKey(.g, true),
            344 => plat.postKey(.g, false),
            352 => it.check(s.tether != null and s.g.tether_uses == 1, "G fires the tether at the tissue under the reticle"),
            482 => {
                it.check(s.tether != null and s.pos.dist(s.tether_hold) < 30, "the line reels the drone in and holds it with no thrust");
                it.check(aim(s, false), "open lumen is in view from the hold point");
                plat.postKey(.g, true);
            },
            484 => plat.postKey(.g, false),
            497 => {
                it.check(s.tether == null, "G on nothing releases the tether");
                it.finished = true;
            },
            else => {},
        }
    }
};

test {
    _ = @import("math.zig");
    _ = @import("mesh.zig");
    _ = @import("font.zig");
    _ = @import("vein.zig");
    _ = @import("guide.zig");
    _ = @import("game.zig");
    _ = @import("audio.zig");
    _ = @import("gut.zig");
    _ = @import("app.zig");
    _ = @import("bot.zig");
    _ = @import("utf8.zig");
    _ = @import("i18n.zig");
    _ = @import("l10n.zig");
}
