//! Dentro del cuerpo — entry point.
//!
//!   dentro                     windowed game
//!   dentro --demo              windowed, flown by the scripted pilot (end-to-end run on the real display)
//!   dentro --demo --pad        the same, with the pilot's controls passed through a game controller's state
//!   dentro --inputtest         windowed, posts key events into its own queue and checks they reach the arms
//!   dentro --padtest           windowed, plays from the title screen with a synthetic game controller
//!   dentro --selftest          headless: scripted pilot plays chapter 1, prints the timeline
//!   dentro --shots <dir>       headless GPU: renders every screen offscreen and writes BMP frames
//!   dentro --icon <file>       headless GPU: renders the app icon as a .png master or a Windows .ico
//!
//! `--prompts kbm|xbox|ps` fixes the device the on-screen prompts are written for; without it they follow
//! the device last used. `--lang en|uk` picks the language for the run. Without it the game uses the language the player chose in
//! the game, or else the first supported one in the system's preference list; the scripted modes, whose
//! output is compared between runs, use English.

const std = @import("std");
const m = @import("math.zig");
const gpu = @import("gpu.zig");
const mesh = @import("mesh.zig");
const render = @import("render.zig");
const font = @import("font.zig");
const platform = @import("platform.zig");
const util = @import("util.zig");
const image = @import("image.zig");
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
const pad = @import("pad.zig");
const bindings = @import("bindings.zig");
const input = @import("input.zig");
const Lang = i18n.Lang;
const Text = i18n.Text;

const Mode = enum { play, demo, inputtest, padtest, selftest, shots, icon };

const usage = "usage: dentro [--fullscreen] [--software] [--lang en|uk] [--prompts kbm|xbox|ps] [--chapter 1|2] [--demo [--pad] | --inputtest | --padtest | --selftest | --shots <dir> | --icon <png|ico>]\n";

pub fn main(init: std.process.Init) !void {
    platform.initProcess();
    const arena = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena);
    var mode: Mode = .play;
    var shots_dir: []const u8 = ".";
    var start_chapter: ?u8 = null;
    var fullscreen = false;
    var lang_arg: ?Lang = null;
    var prompts_arg: ?bindings.Device = null;
    var via_pad = false;
    var software = false;
    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const a = args[i];
        const known = [_][]const u8{ "--selftest", "--demo", "--inputtest", "--padtest", "--pad", "--fullscreen", "--software", "--icon", "--shots", "--chapter", "--lang", "--prompts" };
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
            std.debug.print("unknown argument: {s}\n" ++ usage, .{a});
            std.process.exit(2);
        }
        if (std.mem.eql(u8, a, "--selftest")) mode = .selftest;
        if (std.mem.eql(u8, a, "--demo")) mode = .demo;
        if (std.mem.eql(u8, a, "--inputtest")) mode = .inputtest;
        if (std.mem.eql(u8, a, "--padtest")) mode = .padtest;
        if (std.mem.eql(u8, a, "--pad")) via_pad = true;
        if (std.mem.eql(u8, a, "--prompts")) {
            prompts_arg = if (i + 1 < args.len) bindings.Device.fromArg(args[i + 1]) else null;
            if (prompts_arg == null) {
                std.debug.print("--prompts takes kbm, xbox or ps\n", .{});
                std.process.exit(2);
            }
            i += 1;
            continue;
        }
        if (std.mem.eql(u8, a, "--fullscreen")) fullscreen = true;
        if (std.mem.eql(u8, a, "--software")) software = true;
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
    const gpu_options: gpu.Options = .{ .software = software };
    const result = switch (mode) {
        .selftest => runSelftest(arena),
        .shots => runShots(arena, gpu_options, shots_dir, start_chapter, lang_arg, prompts_arg orelse .kbm),
        .icon => runIcon(arena, gpu_options, shots_dir),
        else => runWindow(arena, mode, .{ .fullscreen = fullscreen, .start_chapter = start_chapter, .lang = lang_arg, .prompts = prompts_arg, .via_pad = via_pad, .gpu = gpu_options }),
    };
    result catch |err| {
        // A player who double-clicked the game has no terminal to read the error from.
        if (mode == .play) platform.reportFatal(@errorName(err));
        return err;
    };
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
        bot.trace = util.envIsSet("DENTRO_TRACE");
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

/// Shader source: the copy shipped beside the executable if present (so it can be edited without
/// rebuilding), otherwise the one compiled into the binary.
fn shaderSource(arena: std.mem.Allocator) [:0]const u8 {
    var path_buf: [1200]u8 = undefined;
    const path = platform.shaderPath(&path_buf, gpu.shader_file) orelse return gpu.embedded_shaders;
    const buf = arena.alloc(u8, 256 * 1024) catch return gpu.embedded_shaders;
    const data = util.readFile(path.ptr, buf[0 .. buf.len - 1]) orelse return gpu.embedded_shaders;
    if (data.len <= 100) return gpu.embedded_shaders;
    buf[data.len] = 0;
    return buf[0..data.len :0];
}

const Engine = struct {
    g: gpu.Gpu,
    r: render.Renderer,
    vm: vein_mod.Meshes,
    app: *app_mod.App,

    /// `lang` is the language asked for on the command line; `fallback` applies when neither it nor the
    /// save file names one.
    fn init(e: *Engine, arena: std.mem.Allocator, options: gpu.Options, persist: bool, lang: ?Lang, fallback: Lang) !void {
        e.g = try gpu.Gpu.init(shaderSource(arena), options);
        e.app = try arena.create(app_mod.App);
        e.app.init(persist, fallback);
        e.app.fullscreen_key = platform.fullscreen_key;
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

fn runShots(arena: std.mem.Allocator, options: gpu.Options, dir: []const u8, only: ?u8, lang: ?Lang, prompts: bindings.Device) !void {
    const pool = platform.scopeBegin();
    defer platform.scopeEnd(pool);
    const e = try arena.create(Engine);
    try e.init(arena, options, false, lang, .en);
    e.app.prompts = prompts;
    const w: u32 = 1600;
    const h: u32 = 1000;
    e.g.resize(w, h, true);
    {
        var name: [256]u8 = undefined;
        std.debug.print("shots: rendering with {s}\n", .{e.g.describe(&name)});
    }
    const px = try arena.alloc(u8, w * h * 4);
    const app = e.app;
    const dt: f32 = 1.0 / 60.0;

    const Shooter = struct {
        e: *Engine,
        px: []u8,
        dir: []const u8,
        n: u32 = 0,
        failed: bool = false,
        fn snap(sh: *@This(), name: []const u8) void {
            const p2 = platform.scopeBegin();
            defer platform.scopeEnd(p2);
            _ = sh.e.renderFrame(1.0 / 60.0, true);
            sh.e.g.readback(sh.px);
            var path: [600]u8 = undefined;
            const full = std.fmt.bufPrintSentinel(&path, "{s}/{d:0>2}-{s}.bmp", .{ sh.dir, sh.n, name }, 0) catch return;
            const hdr = image.bmpHeader(sh.e.g.width, sh.e.g.height);
            if (!util.writeFileParts(full.ptr, &.{ &hdr, sh.px })) {
                std.debug.print("could not write {s}\n", .{full});
                sh.failed = true;
                return;
            }
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

    // Pause screen, the language key on it, and the selection moved down to the language entry.
    app.openPause();
    sh.snap("pause");
    for (1..Lang.count) |_| {
        app.step(.{}, .{ .language = true }, dt);
        sh.snap("pause-language-switched");
    }
    app.step(.{}, .{ .language = true }, dt);
    for (1..app_mod.PauseItem.count) |_| app.step(.{}, .{ .down = true }, dt);
    sh.snap("pause-language-selected");
    std.debug.print("shots: {d} frames, chapters complete = {}\n", .{ sh.n, all_done });
    if (sh.failed) return error.ShotWriteFailed;
}

/// Render the app icon from the title backdrop and the reticle mark, 2048 px and clipped to a rounded
/// square. A path ending in .ico gets the Windows icon, every size it carries scaled down from that
/// render; any other path gets the 2048 px PNG that the macOS iconset is made from.
fn runIcon(arena: std.mem.Allocator, options: gpu.Options, path: []const u8) !void {
    const pool = platform.scopeBegin();
    defer platform.scopeEnd(pool);
    const e = try arena.create(Engine);
    try e.init(arena, options, false, null, .en);
    const n: u32 = 2048; // supersampled; the iconset step scales it down
    e.g.resize(n, n, true);
    const px = try arena.alloc(u8, n * n * 4);
    e.app.icon_mode = true;
    for (0..240) |_| e.app.step(.{}, .{}, 1.0 / 60.0);
    _ = e.renderFrame(1.0 / 60.0, true);
    e.g.readback(px);
    const ico = std.ascii.endsWithIgnoreCase(path, ".ico");
    // The macOS icon grid leaves a margin: the shape fills 824/1024 of the canvas, as a superellipse.
    // Windows draws an icon edge to edge, so there the same shape fills the canvas but for a pixel or
    // two of the smallest size.
    const half: f32 = if (ico) 992 else 824;
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
    const bytes = if (ico) try image.encodeIco(arena, px, n) else try image.encodePng(arena, px, n, n);
    if (!util.writeFile(z.ptr, bytes)) return error.IconWriteFailed;
    std.debug.print("icon: {s}\n", .{path});
}

// ---------------------------------------------------------------------------- windowed game

/// Keyboard and mouse as the game's actions. The controller's half of this is `input.Mapper`.
fn gather(in: *const platform.Input, captured: bool, dt: f32) input.Out {
    var c: game.Controls = .{};
    const f = struct {
        fn axis(keys: *const platform.Input, pos: platform.Key, neg: platform.Key) f32 {
            return @as(f32, if (keys.down(pos)) 1 else 0) - @as(f32, if (keys.down(neg)) 1 else 0);
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
    return .{ .controls = c, .ui = ui };
}

var live_audio: ?*audio_mod.Audio = null;

fn stopAudioOnTerminate() void {
    if (live_audio) |a| a.stop();
}

const WindowOptions = struct {
    fullscreen: bool = false,
    start_chapter: ?u8 = null,
    lang: ?Lang = null,
    /// The device the prompts are written for, if the command line fixed it.
    prompts: ?bindings.Device = null,
    /// `--demo --pad`: the scripted pilot holds a controller instead of handing its controls to the game.
    via_pad: bool = false,
    gpu: gpu.Options = .{},
};

const SyntheticPad = platform.SyntheticPad;

fn runWindow(arena: std.mem.Allocator, mode: Mode, opts: WindowOptions) !void {
    const fullscreen = opts.fullscreen;
    const start_chapter = opts.start_chapter;
    const lang = opts.lang;
    const outer = platform.scopeBegin();
    defer platform.scopeEnd(outer);
    const e = try arena.create(Engine);
    // The scripted tests assert on their output, so they do not follow the machine they run on.
    try e.init(arena, opts.gpu, mode == .play, lang, if (mode == .inputtest or mode == .padtest) .en else systemLanguage());
    const app = e.app;
    if (opts.prompts) |d| app.prompts = d;
    var menu_text: MenuText = .{};
    var menu_lang = app.lang;
    var plat = platform.Platform.init(app_mod.title, menu_text.set(menu_lang), 1440, 900);
    try e.g.attach(plat.surface());
    plat.show();
    if (fullscreen) plat.toggleFullscreen();

    const audio = try arena.create(audio_mod.Audio);
    audio.* = .{};
    const audio_ok = audio.start();
    defer audio.stop();
    live_audio = audio;
    platform.setTerminateHook(&stopAudioOnTerminate);
    if (!audio_ok) std.debug.print("audio: output queue failed to start; continuing silent\n", .{});

    if (start_chapter) |ch| {
        app.unlock_all = true;
        app.chapter = ch;
    }
    const pad_pilot = mode == .demo and opts.via_pad;
    if (mode == .demo) {
        if (!pad_pilot) app.bot = .{};
        app.startChapter(0);
    } else if (mode == .play and start_chapter != null) {
        app.startChapter(0);
    }
    var it: InputTest = .{};
    if (mode == .inputtest) it.begin(app);
    var pt: PadTest = .{};
    if (mode == .padtest) pt.begin(&plat, app);
    var held_pad: SyntheticPad = .{};
    if (pad_pilot) held_pad = SyntheticPad.attach(&plat);
    var pilot: bot.Bot = .{};
    var pilot_retries: u32 = 0;
    var puppet: input.Puppet = .{};
    var mapper: input.Mapper = .{};
    var tracker: input.Tracker = .{};
    if (mode == .demo) {
        var prefs: [512]u8 = undefined;
        std.debug.print("[demo] language {s} (asked for: {s}; system preference: {s})\n", .{ app.lang.tag(), if (lang) |l| l.tag() else "-", platform.preferredLanguages(&prefs) });
    }

    var last = platform.now();
    var frames: u64 = 0;
    var demo_logged: ?game.Stage = null;
    const t_start = last;
    while (!plat.shouldQuit()) {
        const pool = platform.scopeBegin();
        defer platform.scopeEnd(pool);

        const now = platform.now();
        const dt: f32 = @floatCast(@min(@max(now - last, 0.0005), 1.0 / 20.0));
        last = now;

        if (mode == .inputtest) it.post(&plat, app);
        if (mode == .padtest) pt.drive(&plat, app, dt);
        if (pad_pilot) {
            // The pilot decides what it wants, and a controller is held the way that takes. From here its
            // input is a controller's: read by the platform, mapped, merged with the keyboard's.
            const s = &app.sim;
            if (s.stats.retries != pilot_retries) {
                pilot_retries = s.stats.retries;
                pilot = .{};
            }
            var want: game.Controls = .{};
            if (app.screen == .play) {
                want = pilot.think(s, dt);
                if (s.mode == .dead and app.screen_t > 1) want.confirm = true;
            }
            held_pad.set(&plat, puppet.drive(want, input.Context.of(app), dt));
        }
        const lost_focus = plat.pump();
        if (lost_focus and app.screen == .play and mode == .play) app.openPause();
        const size = plat.pixelSize();
        if (size.w != e.g.width or size.h != e.g.height) e.g.resizeSurface(size.w, size.h, size.scale);

        // Both devices are read every frame and their input is added together; the prompts are written
        // for whichever was used last.
        const from_pad = mapper.update(plat.pad, plat.padFocused(), input.Context.of(app), dt);
        const gathered = gather(&plat.input, plat.captured, dt).merge(from_pad);
        const used = tracker.update(.{ .pressed = plat.input.anyPressed(), .held = plat.input.anyHeld() }, &mapper.sample);
        app.prompts = opts.prompts orelse used;

        const steps: usize = @intFromFloat(m.clamp(@ceil(dt * 120.0), 1, 4));
        const sub = dt / @as(f32, @floatFromInt(steps));
        for (0..steps) |k| {
            var c = gathered.controls;
            if (k > 0) {
                // One-shot actions belong to the frame, not to each step of it.
                c.look = .{ 0, 0 };
                c.cycle = .{ false, false };
                c.select = .{ null, null };
                c.examine = false;
                c.hint = false;
                c.confirm = false;
                c.skip = false;
                c.tether = false;
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
        if (mode == .demo and frames == 30) {
            std.debug.print("[demo] controller: {s}, {s}; {s}\n", .{
                if (plat.pad.connected) @tagName(plat.pad.family) else "none attached",
                switch (plat.pad_source) {
                    .system => "polled from the system",
                    else => held_pad.describe(),
                },
                platform.padBackendStatus(),
            });
        }

        if (mode == .demo) {
            const s = &app.sim;
            if (demo_logged == null or demo_logged.? != s.stage) {
                demo_logged = s.stage;
                std.debug.print("[demo {d:6.1}s] stage {s} hull {d:.0} stability {d:.0}\n", .{ now - t_start, @tagName(s.stage), s.hull, s.stability });
            }
            if (s.mode == .complete and app.screen_t > 0) {
                const secs = now - t_start;
                if (it.linger == 0) std.debug.print("demo: chapter complete on the display. grade={c} stability={d:.0} dual_arm_time={d:.1}s sync_strikes={d} retries={d} frames={d} avg_fps={d:.0} drawable={d}x{d} audio={} input={s}\n", .{ s.grade(), s.stability, s.stats.dual_time, s.stats.sync_strikes, s.stats.retries, frames, @as(f64, @floatFromInt(frames)) / secs, e.g.width, e.g.height, audio_ok, if (pad_pilot) held_pad.describe() else "pilot's controls, direct" });
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
        if (mode == .padtest and pt.finished) {
            std.debug.print("padtest: {s} ({d} checks, {d} failed) pad={s} drawable={d}x{d}\n", .{ if (pt.failed == 0) "PASS" else "FAIL", pt.checks, pt.failed, pt.held.describe(), e.g.width, e.g.height });
            if (pt.failed != 0) {
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
        standAtStone(app);
    }

    /// Stand in front of the phlebolith with the upgrade installed, both arms on Punch.
    fn standAtStone(app: *app_mod.App) void {
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

/// Plays the game from the title screen with a controller and nothing else. The controller is synthetic
/// (see `SyntheticPad`), and from there on its input takes the path a real one's does: `Platform.pump`
/// reads it, `input.Mapper` turns it into actions, and the result is read back from the game. Where the
/// script needs a particular place to stand it sets the simulation up, as the input test does; it never
/// hands the game an action.
const PadTest = struct {
    phase: u32 = 0,
    /// Seconds spent in the current phase.
    t: f32 = 0,
    advanced: bool = false,
    checks: u32 = 0,
    failed: u32 = 0,
    finished: bool = false,
    held: SyntheticPad = .{},
    st: pad.State = .{ .connected = true },
    lang0: Lang = .en,
    pos0: m.Vec3 = .{},
    yaw0: f32 = 0,
    pitch0: f32 = 0,
    stone_hp: f32 = 0,
    sel0: usize = 0,
    steps: u32 = 0,
    pages: usize = 0,
    count0: u32 = 0,
    serial0: u32 = 0,
    top_speed: f32 = 0,
    lift: [2]f32 = .{ 0, 0 },
    saw_both: bool = false,
    saw_mixed: bool = false,
    saw_key_arm: bool = false,
    /// The controller is reported as gone, whatever `st` holds.
    unplugged: bool = false,

    fn begin(pt: *PadTest, plat: *platform.Platform, app: *app_mod.App) void {
        pt.held = SyntheticPad.attach(plat);
        // The route map is walked to chapter 2, which a fresh save has locked.
        app.unlock_all = true;
    }

    fn check(pt: *PadTest, ok: bool, what: []const u8) void {
        pt.checks += 1;
        if (!ok) pt.failed += 1;
        std.debug.print("  [{s}] {s}\n", .{ if (ok) "ok" else "FAIL", what });
    }

    /// True while the script is at the `k`th phase, counting them in the order they are written.
    fn at(pt: *PadTest, k: *u32) bool {
        defer k.* += 1;
        return pt.phase == k.* and !pt.advanced;
    }

    fn next(pt: *PadTest) void {
        pt.phase += 1;
        pt.t = 0;
        pt.advanced = true;
    }

    /// Press `b` and let it go. True once the game has had a few frames to act on the press.
    fn tap(pt: *PadTest, b: pad.Button) bool {
        pt.st.set(b, pt.t < 0.07);
        return pt.t >= 0.2;
    }

    /// `n` taps of `b`, one after another.
    fn taps(pt: *PadTest, b: pad.Button, n: u32) bool {
        const period: f32 = 0.2;
        pt.st.set(b, pt.t < period * @as(f32, @floatFromInt(n)) and @mod(pt.t, period) < 0.07);
        return pt.t >= period * @as(f32, @floatFromInt(n)) + 0.1;
    }

    fn rest(pt: *PadTest) void {
        pt.st = .{ .connected = true };
    }

    /// Everything a controller has, written to the synthetic device and read back by the code that reads
    /// a real one. Opposite d-pad directions cannot be down together, so it takes two states.
    fn roundTrip(pt: *PadTest) bool {
        if (!pt.held.real()) return false;
        const tol = SyntheticPad.tolerance;
        var ok = true;
        for (0..2) |pass| {
            var st: pad.State = .{ .connected = true };
            if (pass == 0) {
                st.left = .{ 0.25, -0.5 };
                st.right = .{ -0.75, 1 };
                st.lt = 0.5;
                st.rt = 1;
            }
            for (std.enums.values(pad.Button)) |b| {
                const second = b == .dpad_down or b == .dpad_left or b == .b or b == .rb;
                // The triggers are analog here; their buttons are derived from the values further on.
                if (b != .lt and b != .rt) st.set(b, second == (pass == 1));
            }
            const got = pt.held.roundTrip(st);
            var analog_ok = @abs(got.lt - st.lt) <= tol and @abs(got.rt - st.rt) <= tol;
            for (0..2) |axis| analog_ok = analog_ok and @abs(got.left[axis] - st.left[axis]) <= tol and @abs(got.right[axis] - st.right[axis]) <= tol;
            if (!analog_ok) {
                std.debug.print("      sticks or triggers read back as {any} {any} {d} {d}\n", .{ got.left, got.right, got.lt, got.rt });
                ok = false;
            }
            for (std.enums.values(pad.Button)) |b| {
                if (got.buttons.contains(b) != st.buttons.contains(b)) {
                    std.debug.print("      {s} was written {} and read back {}\n", .{ @tagName(b), st.buttons.contains(b), got.buttons.contains(b) });
                    ok = false;
                }
            }
        }
        _ = pt.held.roundTrip(.{ .connected = true });
        return ok;
    }

    fn drive(pt: *PadTest, plat: *platform.Platform, app: *app_mod.App, dt: f32) void {
        const s = &app.sim;
        pt.t += dt;
        pt.advanced = false;
        if (s.arms[0].held and s.arms[1].held) pt.saw_both = true;
        if (s.arms[0].held and s.arms[1].held and s.arms[0].tool != s.arms[1].tool) pt.saw_mixed = true;
        pt.top_speed = @max(pt.top_speed, s.vrel.len());
        var k: u32 = 0;

        // ------------------------------------------------------------------ the device and the prompts
        if (pt.at(&k) and pt.t >= 0.4) {
            pt.check(app.screen == .title, "the game opens on the title screen");
            pt.check(app.prompts == .kbm, "an attached controller that nobody has touched leaves the prompts on the keyboard");
            if (pt.held.real()) {
                pt.check(pt.roundTrip(), SyntheticPad.round_trip_name);
            } else {
                std.debug.print("  [--] " ++ SyntheticPad.no_device_note ++ "\n", .{});
            }
            pt.lang0 = app.lang;
            pt.next();
        }
        if (pt.at(&k) and pt.tap(.dpad_right)) {
            pt.check(app.lang == pt.lang0.next() and app.lang != pt.lang0, "d-pad right on the title screen switches to the next language");
            pt.check(std.mem.eql(u8, plat.menuTitle(.quit), strings.menu.quit.get(app.lang)), "the menu bar follows the language");
            pt.check(app.prompts == .xbox, "a button press moves the prompts to the controller (one of no known family gets Xbox names)");
            pt.next();
        }
        if (pt.at(&k) and pt.taps(.back, Lang.count - 1)) {
            pt.check(app.lang == pt.lang0, "View on the title screen switches language too, back to the first");
            pt.next();
        }
        if (pt.at(&k)) {
            plat.postMouseMove();
            if (pt.t >= 0.4) {
                pt.check(app.prompts == .xbox, "mouse-moved events arriving do not take the prompts from the controller");
                plat.postKey(.h, true);
                pt.next();
            }
        }
        if (pt.at(&k) and pt.t >= 0.1) {
            plat.postKey(.h, false);
            pt.check(app.prompts == .kbm, "a key press moves the prompts to the keyboard");
            pt.st.right = .{ pad.look_shape.inner * 0.8, 0 };
            pt.next();
        }
        if (pt.at(&k) and pt.t >= 0.3) {
            pt.check(app.prompts == .kbm, "a stick resting inside its dead zone does not take the prompts");
            pt.st.right = .{ 0.6, 0 };
            pt.next();
        }
        if (pt.at(&k) and pt.t >= 0.2) {
            pt.check(app.prompts == .xbox, "a stick pushed past its dead zone does");
            pt.rest();
            // The framework's own controller has no family; a PlayStation one is written at the seam.
            plat.pad_source = .injected;
            pt.st.family = .playstation;
            pt.next();
        }
        if (pt.at(&k) and pt.tap(.x)) {
            pt.check(app.prompts == .playstation, "a press on a PlayStation controller moves the prompts to PlayStation names");
            pt.rest();
            plat.pad_source = pt.held.source();
            pt.next();
        }

        // ------------------------------------------------------------------ menus
        if (pt.at(&k) and pt.tap(.y)) {
            pt.check(app.screen == .map, "Y on the title screen opens the route map");
            pt.sel0 = app.map_sel;
            pt.next();
        }
        if (pt.at(&k) and pt.tap(.dpad_down)) {
            pt.check(app.map_sel == (pt.sel0 + 1) % campaign.chapters.len, "d-pad down moves the map selection one chapter");
            pt.sel0 = app.map_sel;
            pt.steps = 0;
            pt.next();
        }
        if (pt.at(&k)) {
            // Held down on the stick for the repeat delay and two and a half intervals: one step at once,
            // one at the end of the delay, two more an interval apart.
            pt.st.left = .{ 0, -1 };
            if (app.map_sel != pt.sel0) {
                pt.sel0 = app.map_sel;
                pt.steps += 1;
            }
            if (pt.t >= pad.Repeat.delay + 2.5 * pad.Repeat.interval) {
                pt.st.left = .{ 0, 0 };
                pt.check(pt.steps >= 3 and pt.steps <= 5, "the left stick held down steps the selection and then repeats");
                pt.next();
            }
        }
        if (pt.at(&k) and pt.tap(.b)) {
            pt.check(app.screen == .title, "B backs out of the route map");
            pt.next();
        }
        if (pt.at(&k) and pt.tap(.a)) {
            pt.check(app.screen == .briefing and app.briefing_page == 0, "A on the title screen opens the briefing");
            pt.next();
        }
        if (pt.at(&k) and pt.tap(.b)) {
            pt.check(app.screen == .title, "B backs out of the briefing");
            pt.next();
        }
        if (pt.at(&k) and pt.tap(.a)) {
            pt.pages = 0;
            pt.next();
        }
        if (pt.at(&k) and pt.tap(.a)) {
            pt.pages += 1;
            if (app.screen == .briefing and pt.pages <= strings.briefing.pages.len) {
                pt.t = 0;
            } else {
                pt.check(app.screen == .play and pt.pages == strings.briefing.pages.len, "A pages through the briefing and launches chapter 1");
                pt.next();
            }
        }

        // ------------------------------------------------------------------ flying, chapter 1
        if (pt.at(&k) and pt.t >= 0.3) {
            InputTest.standAtStone(app);
            pt.stone_hp = s.findConst(.phlebolith).?.hp;
            pt.saw_both = false;
            pt.next();
        }
        if (pt.at(&k)) {
            // Both triggers pulled in the same frame, past the press point but not to the end of their travel.
            const pull: f32 = if (pt.t >= 0.3 and pt.t < 0.4) 0.7 else 0;
            pt.st.lt = pull;
            pt.st.rt = pull;
            if (pt.t >= 1.2) {
                pt.check(pt.saw_both, "LT and RT pulled in the same frame drive both arms");
                pt.check(s.stats.sync_strikes == 1, "the two punches landed as one Sync Strike");
                pt.check(s.findConst(.phlebolith).?.hp == pt.stone_hp - 10, "the Sync Strike did 10 damage to the phlebolith");
                pt.next();
            }
        }
        if (pt.at(&k) and pt.tap(.dpad_left)) {
            pt.check(s.arms[0].tool == .shoot, "d-pad left steps the left arm back a tool, Punch to Shoot");
            pt.next();
        }
        if (pt.at(&k) and pt.tap(.lb)) {
            pt.check(s.arms[0].tool == .punch, "LB steps the left arm on a tool, Shoot to Punch");
            pt.next();
        }
        if (pt.at(&k) and pt.tap(.dpad_left)) pt.next();
        if (pt.at(&k) and pt.tap(.rb)) {
            pt.check(s.arms[1].tool == .drill, "RB steps the right arm on a tool, Punch to Drill");
            pt.next();
        }
        if (pt.at(&k) and pt.tap(.dpad_right)) {
            pt.check(s.arms[1].tool == .punch, "d-pad right steps the right arm back a tool, Drill to Punch");
            pt.next();
        }
        if (pt.at(&k) and pt.tap(.rb)) {
            pt.saw_mixed = false;
            pt.next();
        }
        if (pt.at(&k)) {
            pt.st.lt = 1;
            pt.st.rt = 1;
            if (pt.t >= 1.0) {
                pt.check(s.arms[0].tool == .shoot and s.arms[1].tool == .drill and pt.saw_mixed, "different tools run on both arms at once");
                pt.check(s.arms[1].engaged, "the drill arm is cutting while the other arm fires");
                pt.check(s.arms[0].charge < 1, "the shoot arm fired");
                pt.rest();
                pt.pos0 = s.pos;
                pt.yaw0 = s.yaw;
                pt.saw_key_arm = false;
                plat.postKey(.q, true);
                pt.next();
            }
        }
        if (pt.at(&k)) {
            // Thrust and turn on the sticks, with a key held down on the keyboard through it.
            pt.st.left = .{ 0, -1 };
            pt.st.right = .{ -1, 0 };
            if (s.arms[0].held) pt.saw_key_arm = true;
            if (pt.t >= 1.0) {
                plat.postKey(.q, false);
                pt.check(s.pos.dist(pt.pos0) > 20, "the left stick pulled back thrusts the drone backward");
                pt.check(s.yaw - pt.yaw0 > 1.5, "the right stick pushed left turns the view left");
                pt.check(pt.saw_key_arm, "a key held on the keyboard works its arm while the sticks fly");
                pt.rest();
                pt.pitch0 = s.pitch;
                pt.next();
            }
        }
        if (pt.at(&k)) {
            pt.st.right = .{ 0, 1 };
            if (pt.t >= 0.4) {
                pt.check(s.pitch - pt.pitch0 > 0.4, "the right stick pushed up looks up");
                pt.rest();
                pt.next();
            }
        }
        if (pt.at(&k)) {
            pt.st.set(.a, true);
            pt.lift[0] = s.vrel.dot(s.upVec());
            if (pt.t >= 0.4) {
                pt.rest();
                pt.next();
            }
        }
        if (pt.at(&k)) {
            pt.st.set(.b, pt.t >= 0.1);
            pt.lift[1] = s.vrel.dot(s.upVec());
            if (pt.t >= 0.6) {
                pt.check(pt.lift[0] > 100, "A climbs");
                pt.check(pt.lift[1] < -100, "B descends");
                pt.check(app.screen == .play, "and neither confirmed nor backed out of anything while flying");
                pt.rest();
                pt.next();
            }
        }
        if (pt.at(&k)) {
            // Cruise, then a click of the stick while it is pushed: boost, for as long as it stays pushed.
            pt.st.left = .{ 0, 1 };
            if (pt.t < 0.1) pt.top_speed = 0;
            if (pt.t >= 0.7) {
                pt.check(pt.top_speed > game.cruise_speed * 0.7 and pt.top_speed <= game.cruise_speed * 1.01, "the left stick pushed forward thrusts at cruise speed");
                pt.top_speed = 0;
                pt.next();
            }
        }
        if (pt.at(&k)) {
            pt.st.left = .{ 0, 1 };
            pt.st.set(.ls, pt.t < 0.07);
            if (pt.t >= 0.7) {
                pt.check(pt.top_speed > game.cruise_speed * 1.5, "a click of the left stick boosts, and the boost lasts after the click while the stick is pushed");
                pt.rest();
                s.voice.clear();
                pt.next();
            }
        }
        // Let the drone coast to a stop before the one-shot actions.
        if (pt.at(&k) and pt.t >= 0.5) pt.next();
        if (pt.at(&k) and pt.tap(.x)) {
            pt.check(s.examine_cd > 0, "X identifies whatever is under the reticle");
            pt.count0 = s.stats.hints;
            s.voice.clear();
            pt.next();
        }
        if (pt.at(&k) and pt.tap(.y)) {
            pt.check(s.stats.hints == pt.count0 + 1, "Y asks Marín for a hint");
            pt.check(s.voice.current != null, "and she is saying it");
            pt.serial0 = s.voice.serial;
            pt.next();
        }
        if (pt.at(&k) and pt.tap(.back)) {
            pt.check(s.voice.current == null or s.voice.serial != pt.serial0, "View cuts her line short");
            pt.next();
        }

        // ------------------------------------------------------------------ the pause menu
        if (pt.at(&k) and pt.tap(.start)) {
            pt.check(app.screen == .pause and app.pause_sel == .resume_game, "Menu pauses, with Resume selected");
            pt.next();
        }
        if (pt.at(&k) and pt.taps(.dpad_down, 4)) {
            pt.check(app.pause_sel == .language, "d-pad down four times selects the language entry");
            pt.next();
        }
        if (pt.at(&k) and pt.tap(.a)) {
            pt.check(app.lang == pt.lang0.next(), "A on the language entry switches to the next language");
            pt.check(std.mem.eql(u8, plat.menuTitle(.quit), strings.menu.quit.get(app.lang)), "the menu bar follows the language");
            pt.check(app.save.lang == app.lang and app.save_path_len == 0, "the choice is recorded for saving, and a scripted run has no save file to write");
            pt.next();
        }
        if (pt.at(&k) and pt.taps(.dpad_right, Lang.count - 1)) {
            pt.check(app.lang == pt.lang0, "d-pad right on the language entry switches it too, back to the first");
            pt.count0 = s.stats.retries;
            pt.next();
        }
        if (pt.at(&k) and pt.taps(.dpad_up, 3)) {
            pt.check(app.pause_sel == .retry, "d-pad up three times selects Relaunch from last checkpoint");
            pt.next();
        }
        if (pt.at(&k) and pt.tap(.a)) {
            pt.check(app.screen == .play and s.stats.retries == pt.count0 + 1, "A chooses it: the drone is back at the checkpoint");
            pt.next();
        }
        if (pt.at(&k) and pt.tap(.start)) pt.next();
        if (pt.at(&k) and pt.tap(.b)) {
            pt.check(app.screen == .play, "B backs out of the pause menu into the game");
            pt.next();
        }
        if (pt.at(&k) and pt.tap(.start)) {
            pt.check(app.screen == .pause, "Menu pauses again");
            pt.next();
        }
        if (pt.at(&k) and pt.tap(.start)) {
            pt.check(app.screen == .play, "Menu on the pause menu resumes");
            pt.next();
        }

        // ------------------------------------------------------------------ the controller goes away
        if (pt.at(&k)) {
            pt.st.rt = 1;
            if (pt.t >= 0.3) {
                pt.check(s.arms[1].held, "RT held works the right arm");
                plat.pad_source = .injected;
                pt.unplugged = true;
                pt.next();
            }
        }
        if (pt.at(&k)) {
            if (pt.t >= 0.2) {
                pt.check(!s.arms[1].held, "the controller disconnects with the trigger held: the arm stops");
                pt.check(app.prompts == .kbm, "and the prompts return to the keyboard");
                pt.rest();
                pt.unplugged = false;
                plat.pad_source = pt.held.source();
                pt.next();
            }
        }

        // ------------------------------------------------------------------ leaving, and chapter 2 from the map
        if (pt.at(&k) and pt.t >= 0.2) pt.next();
        if (pt.at(&k) and pt.tap(.start)) pt.next();
        if (pt.at(&k) and pt.taps(.dpad_down, 3)) {
            pt.check(app.screen == .pause and app.pause_sel == .leave, "Leave to title is selected");
            pt.next();
        }
        if (pt.at(&k) and pt.tap(.a)) {
            pt.check(app.screen == .title, "A chooses it: back on the title screen");
            pt.next();
        }
        if (pt.at(&k) and pt.tap(.y)) pt.next();
        if (pt.at(&k) and pt.tap(.dpad_down)) {
            // The selection is wherever the earlier walk left it; step until it is on chapter 2.
            if (app.map_sel != 1 and pt.steps < 40) {
                pt.steps += 1;
                pt.t = 0;
            } else {
                pt.check(app.screen == .map and app.map_sel == 1, "the route map selection is on chapter 2");
                pt.next();
            }
        }
        if (pt.at(&k) and pt.tap(.a)) {
            pt.check(app.screen == .play and app.chapter == 1, "A on the route map launches the selected chapter");
            // The tether, from where the drone arrives among the villi.
            s.has_tether = true;
            s.stage = .g_tether;
            s.voice.clear();
            pt.next();
        }
        if (pt.at(&k) and pt.t >= 0.5) {
            pt.check(InputTest.aim(s, true), "a villus is within tether range of the arrival point");
            pt.next();
        }
        if (pt.at(&k)) {
            // The reticle is held on the villus until the click lands, as a hand would hold it. The drone
            // drifts with the chyme between the frame that aimed and the frame that reads the click, and
            // at a low frame rate (a software renderer draws a few frames a second) it drifts far enough
            // for an aim taken once to miss.
            if (s.tether == null) _ = InputTest.aim(s, true);
            if (pt.tap(.rs)) {
                pt.check(s.tether != null and s.g.tether_uses == 1, "a click of the right stick fires the tether at the tissue under the reticle");
                pt.next();
            }
        }
        if (pt.at(&k) and (pt.t >= 4 or (s.tether != null and s.pos.dist(s.tether_hold) < 30))) {
            pt.check(s.tether != null and s.pos.dist(s.tether_hold) < 30, "the line reels the drone in and holds it with no thrust");
            pt.check(InputTest.aim(s, false), "open lumen is in view from the hold point");
            pt.next();
        }
        if (pt.at(&k) and pt.tap(.dpad_up)) {
            pt.check(s.tether == null, "d-pad up, the tether's other button, releases it on nothing");
            pt.finished = true;
            pt.next();
        }

        if (pt.unplugged) plat.pad = .{} else pt.held.set(plat, pt.st);
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
    _ = @import("pad.zig");
    _ = @import("bindings.zig");
    _ = @import("input.zig");
    _ = @import("gpu.zig");
    _ = @import("image.zig");
    _ = @import("util.zig");
    _ = @import("platform.zig");
}
